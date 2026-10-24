#!/usr/bin/env bash
#===============================================================================
#   System Snapshot Collector (read-only)
#   Part of: CachyOS + HyDE System Restorer
#   Repo:    https://github.com/omarahmed321/cachy-os-config-related
#
#   Records what is installed and configured on this machine so the restore
#   scripts can be compared against it. Changes nothing, needs no sudo.
#
#   Usage:
#     ./collect-system-snapshot.sh            → writes ./system-snapshot/
#     ./collect-system-snapshot.sh /some/dir  → writes /some/dir/system-snapshot/
#
#   Secrets: browser profiles, keyrings, ssh/gpg keys, tokens and the hotspot
#   config are never copied, and lines that look like passwords/tokens in the
#   copied configs are redacted. Review the folder before sharing it anyway.
#===============================================================================

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$SCRIPT_DIR}/system-snapshot"
MAX_FILE_KB=512

rm -rf "$OUT"
mkdir -p "$OUT/dotfiles"

run() {
    # run <output-file> <command...>: save output, never abort on failure
    local file="$OUT/$1"
    shift
    mkdir -p "$(dirname "$file")"
    "$@" > "$file" 2>&1 || true
}

have() { command -v "$1" &>/dev/null; }

echo -e "${CYAN}[1/6] System & hardware...${NC}"
run system/os-release.txt cat /etc/os-release
run system/uname.txt uname -a
run system/kernel-cmdline.txt cat /proc/cmdline
run system/cpu.txt lscpu
run system/memory.txt free -h
run system/disks.txt lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
have lspci && run system/pci.txt lspci -nnk
have lsusb && run system/usb.txt lsusb
run system/chassis-type.txt cat /sys/class/dmi/id/chassis_type
run system/power-supply.txt ls /sys/class/power_supply
run system/input-devices.txt cat /proc/bus/input/devices
run system/loaded-modules.txt lsmod
run system/modprobe.d.txt bash -c 'for f in /etc/modprobe.d/*.conf; do echo "== $f"; cat "$f"; done'
run system/locale.txt localectl status
run system/timezone.txt timedatectl show
have dkms && run system/dkms.txt dkms status

echo -e "${CYAN}[2/6] Packages...${NC}"
if have pacman; then
    run packages/explicit-native.txt pacman -Qqen
    run packages/explicit-foreign-aur.txt pacman -Qqem
    run packages/all-with-versions.txt pacman -Q
    run packages/pacman.conf cat /etc/pacman.conf
    run packages/mirrorlists.txt ls /etc/pacman.d
fi
have flatpak && run packages/flatpak.txt flatpak list --columns=application,origin
have code && run packages/vscode-extensions.txt code --list-extensions
have code-oss && run packages/vscode-oss-extensions.txt code-oss --list-extensions
have pip && run packages/pip-user.txt pip list --user
have npm && run packages/npm-global.txt npm ls -g --depth=0
have cargo && run packages/cargo.txt cargo install --list

echo -e "${CYAN}[3/6] Services...${NC}"
run services/system-enabled.txt systemctl list-unit-files --state=enabled --no-pager
run services/system-running.txt systemctl list-units --type=service --state=running --no-pager
run services/user-enabled.txt systemctl --user list-unit-files --state=enabled --no-pager
run services/user-running.txt systemctl --user list-units --type=service --state=running --no-pager
run services/failed.txt systemctl --failed --no-pager
run services/sddm.txt bash -c 'cat /etc/sddm.conf 2>/dev/null; for f in /etc/sddm.conf.d/*; do echo "== $f"; cat "$f"; done 2>/dev/null; echo "== Xsetup"; cat /usr/share/sddm/scripts/Xsetup 2>/dev/null'

echo -e "${CYAN}[4/6] Desktop session...${NC}"
run desktop/env.txt bash -c 'env | grep -E "^(XDG_|WAYLAND_DISPLAY|DISPLAY|DESKTOP_SESSION|QT_|GTK_|GDK_|SHELL|TERM|EDITOR|LANG|LC_)" | sort'
run desktop/shell.txt bash -c 'getent passwd "$USER" | cut -d: -f7'
run desktop/groups.txt id
if have hyprctl; then
    run desktop/hyprctl-version.txt hyprctl version
    run desktop/hyprctl-monitors.json hyprctl monitors -j
    run desktop/hyprctl-devices.json hyprctl devices -j
    run desktop/hyprctl-layers.json hyprctl layers -j
fi
have gsettings && run desktop/gsettings-interface.txt gsettings list-recursively org.gnome.desktop.interface
have fc-list && run desktop/font-families.txt bash -c 'fc-list : family | sort -u'
run desktop/icon-themes.txt bash -c 'ls /usr/share/icons ~/.local/share/icons ~/.icons 2>/dev/null'
run desktop/autostart.txt bash -c 'ls ~/.config/autostart /etc/xdg/autostart 2>/dev/null'
run desktop/local-share-bin.txt ls -la ~/.local/share/bin
run desktop/local-bin.txt ls -la ~/.local/bin
run desktop/applications.txt ls ~/.local/share/applications
run desktop/home-top-level.txt ls -la ~
run desktop/config-dirs.txt ls -la ~/.config
run desktop/wallpapers.txt bash -c 'find ~/.config/hyde/themes -maxdepth 3 \( -name "*.jpg" -o -name "*.png" \) 2>/dev/null | head -200'
run desktop/hyde-themes.txt ls ~/.config/hyde/themes

echo -e "${CYAN}[5/6] Copying configs (secrets excluded)...${NC}"
CONFIG_DIRS=(
    hypr waybar kitty dunst rofi wlogout swaylock fish fastfetch cava yazi
    gtk-3.0 gtk-4.0 Kvantum qt5ct qt6ct hyde nwg-look dolphinrc
    fontconfig environment.d xdg-desktop-portal starship.toml
    noctalia uwsm wal xsettingsd swappy lsd alacritty btop micro MangoHud
    kdeglobals mimeapps.list libinput-gestures.conf user-dirs.dirs
    code-flags.conf chromium-flags.conf antigravity-ide-flags.conf
)
EXCLUDES=(
    --exclude='*token*' --exclude='*secret*' --exclude='*password*'
    --exclude='*.key' --exclude='*.pem' --exclude='*cache*' --exclude='*Cache*'
    --exclude='*.sqlite' --exclude='*.db' --exclude='hotspot_config'
    --exclude='*.jpg' --exclude='*.png' --exclude='*.gif' --exclude='*.mp4'
    --max-size="${MAX_FILE_KB}k"
)
for item in "${CONFIG_DIRS[@]}"; do
    src="$HOME/.config/$item"
    [ -e "$src" ] || continue
    if have rsync; then
        rsync -a --copy-links "${EXCLUDES[@]}" "$src" "$OUT/dotfiles/" 2>/dev/null || true
    else
        cp -rL "$src" "$OUT/dotfiles/" 2>/dev/null || true
    fi
done
for f in .zshrc .p10k.zsh .bashrc .profile .gitconfig .Xresources; do
    [ -f "$HOME/$f" ] && cp "$HOME/$f" "$OUT/dotfiles/home$f"
done
mkdir -p "$OUT/dotfiles/vscode"
for f in settings.json keybindings.json; do
    [ -f "$HOME/.config/Code/User/$f" ] && cp "$HOME/.config/Code/User/$f" "$OUT/dotfiles/vscode/"
done
# Script names only: their contents may embed personal data
run dotfiles/local-share-bin-files.txt bash -c 'cd ~/.local/share/bin 2>/dev/null && sha256sum -- * 2>/dev/null'

# Active look: HyDE state, current wallpaper and the theme folders in use
mkdir -p "$OUT/theme"
for d in "$HOME/.local/state/hyde" "$HOME/.config/hyde"; do
    [ -d "$d" ] && find "$d" -maxdepth 1 -type f \( -name '*rc' -o -name '*.conf' -o -name '*.toml' \) -exec cp {} "$OUT/theme/" \; 2>/dev/null
done
run theme/wall-links.txt bash -c 'for l in ~/.cache/hyde/wall.set ~/.config/hyde/wall.set ~/.config/hyde/themes/*/wall.set; do [ -e "$l" ] && echo "$l -> $(readlink -f "$l")"; done'
run theme/themes-dirs.txt bash -c 'ls -la ~/.themes ~/.icons ~/.local/share/themes ~/.local/share/icons 2>/dev/null'
for l in "$HOME/.cache/hyde/wall.set" "$HOME/.config/hyde/wall.set"; do
    if [ -e "$l" ]; then
        real="$(readlink -f "$l")"
        cp "$real" "$OUT/theme/current-wallpaper-${real##*/}" 2>/dev/null
        break
    fi
done

echo -e "${CYAN}[6/6] Redacting secrets...${NC}"
# Mask values on lines that look like credentials (key = value / key: value / key=value)
find "$OUT" -type f ! -name "*.jpg" ! -name "*.jpeg" ! -name "*.png" ! -name "*.gif" ! -name "*.webp" -print0 | xargs -0 -r sed -i -E \
    -e 's/^([[:space:]]*(export[[:space:]]+|typeset[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*|env[[:space:]]*=[[:space:]]*)?"?[A-Za-z0-9_.-]*(password|passwd|passphrase|token|secret|api[_-]?key|access[_-]?key|private[_-]?key|credential|auth|psk|SAVED_PASS)[A-Za-z0-9_.-]*"?[[:space:]]*[=:,][[:space:]]*).+/\1<redacted>/I' \
    -e 's/^([[:space:]]*set[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*[A-Za-z0-9_]*(pass|token|secret|key|auth|credential)[A-Za-z0-9_]*[[:space:]]+).+/\1<redacted>/I' \
    -e 's/^(SETUVAR[[:space:]]+(--export[[:space:]]+)?[A-Za-z0-9_]*(pass|token|secret|key|auth|credential)[A-Za-z0-9_]*:).+/\1<redacted>/I' \
    -e 's#([a-z][a-z0-9+.-]*://)[^/@[:space:]]+:[^/@[:space:]]+@#\1<redacted>@#Ig' \
    -e 's/(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|xox[abpr]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16})/<redacted>/g' 2>/dev/null
# .gitconfig: keep it but drop the e-mail address
[ -f "$OUT/dotfiles/home.gitconfig" ] && sed -i -E 's/(email[[:space:]]*=).*/\1 <redacted>/I' "$OUT/dotfiles/home.gitconfig"

SIZE=$(du -sh "$OUT" | cut -f1)
echo -e "\n${GREEN}[OK] Snapshot written to: $OUT ($SIZE)${NC}"
echo -e "${YELLOW}Review it before sharing. To share it with Claude through the repo:${NC}"
echo -e "  cd \"$SCRIPT_DIR\" && git checkout claude/bold-keller-ummi0r && git add -f system-snapshot && git commit -m 'Add system snapshot' && git push"
