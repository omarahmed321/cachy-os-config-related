#!/bin/sh
# SDDM Xsetup: runs as root before the login greeter appears.
# Installed to /usr/share/sddm/scripts/Xsetup by sddm-screen-config.py and
# restore_my_setup.sh (Repo: https://github.com/omarahmed321/cachy-os-config-related)
#
# /etc/sddm.conf.d/target_monitor    kernel connector name of the login screen (e.g. HDMI-A-2)
# /etc/sddm.conf.d/disabled_monitors connector names switched off at the greeter
#
# Xorg names outputs differently from the kernel/Hyprland (modesetting: HDMI-A-2 -> HDMI-2,
# NVIDIA: HDMI-A-2 -> HDMI-0), so outputs are matched by EDID first.

edid_hex() { od -An -v -tx1 "$1" 2>/dev/null | tr -d ' \n' | cut -c1-256; }

# Print "<xrandr-output> <first 128 EDID bytes as hex>" for every connected output
xrandr_edids() {
    xrandr --prop 2>/dev/null | awk '
        / connected/ { if (out != "" && buf != "") print out, substr(buf, 1, 256); out = $1; buf = ""; inedid = 0; next }
        /disconnected/ { if (out != "" && buf != "") print out, substr(buf, 1, 256); out = ""; buf = ""; inedid = 0; next }
        /EDID:/ { inedid = 1; next }
        inedid && /^[ \t]+[0-9a-f]+$/ { gsub(/[ \t]/, ""); buf = buf $0; next }
        { inedid = 0 }
        END { if (out != "" && buf != "") print out, substr(buf, 1, 256) }'
}

# Translate a kernel connector name to the xrandr output name
drm_to_x() {
    name="$1"
    for f in /sys/class/drm/card*-"$name"/edid; do
        [ -s "$f" ] || continue
        hex=$(edid_hex "$f")
        match=$(xrandr_edids | awk -v h="$hex" '$2 == h { print $1; exit }')
        [ -n "$match" ] && { echo "$match"; return; }
    done
    connected=$(xrandr | awk '/ connected/ { print $1 }')
    for cand in "$name" "$(echo "$name" | sed 's/-A-/-/')"; do
        echo "$connected" | grep -qx "$cand" && { echo "$cand"; return; }
    done
}

# 1. Login screen only on the chosen monitor, every other connected screen off
CONNECTED=$(xrandr | awk '/ connected/ { print $1 }')
if [ "$(echo "$CONNECTED" | grep -c .)" -gt 1 ]; then
    TARGET=$(tr -d '[:space:]' < /etc/sddm.conf.d/target_monitor 2>/dev/null)
    PRIMARY=""
    [ -n "$TARGET" ] && PRIMARY=$(drm_to_x "$TARGET")
    [ -z "$PRIMARY" ] && PRIMARY=$(echo "$CONNECTED" | head -n 1)

    DISABLED=""
    if [ -f /etc/sddm.conf.d/disabled_monitors ]; then
        while read -r drm; do
            [ -n "$drm" ] && DISABLED="$DISABLED $(drm_to_x "$drm")"
        done < /etc/sddm.conf.d/disabled_monitors
    fi

    # Separate calls: turning outputs off in the same call as --primary can fail with BadMatch
    xrandr --output "$PRIMARY" --auto --primary 2>/dev/null || true
    for mon in $CONNECTED; do
        [ "$mon" = "$PRIMARY" ] && continue
        case " $DISABLED " in
            *" $mon "*) xrandr --output "$mon" --off 2>/dev/null || true ;;
            *) xrandr --output "$mon" --auto --right-of "$PRIMARY" 2>/dev/null || true ;;
        esac
    done
fi

# 2. Flat mouse acceleration at the greeter
for id in $(xinput list --id-only 2>/dev/null); do
    xinput set-prop "$id" "libinput Accel Profile Enabled" 0 1 0 2>/dev/null || true
    xinput set-prop "$id" "libinput Accel Speed" -0.5 2>/dev/null || true
done

# 3. Night light at the greeter, using the first regular user's setting
PRIMARY_USER=$(awk -F: '$3 >= 1000 && $3 < 60000 { print $1; exit }' /etc/passwd)
PRIMARY_HOME=$(getent passwd "$PRIMARY_USER" | cut -d: -f6)
CONF="$PRIMARY_HOME/.config/hypr/nightlight.conf"
TEMP=3500
ENABLED=true
if [ -f "$CONF" ]; then
    t=$(sed -n 's/^temperature=\([0-9]*\).*/\1/p' "$CONF" | head -n 1)
    e=$(sed -n 's/^enabled=\([a-z]*\).*/\1/p' "$CONF" | head -n 1)
    [ -n "$t" ] && TEMP=$t
    [ "$e" = "false" ] && ENABLED=false
fi
if [ "$ENABLED" = "true" ] && command -v gammastep >/dev/null 2>&1; then
    pkill -x gammastep 2>/dev/null || true
    gammastep -O "$TEMP" -P >/dev/null 2>&1 &
fi
