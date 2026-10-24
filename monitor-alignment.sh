#!/usr/bin/env bash
#===============================================================================
#   Multi-Monitor Alignment & Calibration Tool (any number of screens)
#   Part of: CachyOS + HyDE Complete System Restorer
#   Repo:    https://github.com/omarahmed321/cachy-os-config-related
#
#   Thin wrapper around hypr-monitor-setup.py --calibrate: change screen order,
#   primary screen, rotation, scale, vertical alignment, per-screen Y nudge and
#   VRR, previewed live in Hyprland and saved to ~/.config/hypr/monitors.conf.
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for ENGINE in "$SCRIPT_DIR/hypr-monitor-setup.py" "$HOME/.local/share/bin/hypr-monitor-setup.py"; do
    [ -f "$ENGINE" ] && break
done
if [ ! -f "$ENGINE" ]; then
    echo "[ERROR] hypr-monitor-setup.py not found next to this script or in ~/.local/share/bin" >&2
    exit 1
fi
if [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    echo "[ERROR] Run this inside a Hyprland session (live preview needs hyprctl)." >&2
    exit 1
fi

# Started from a keybind or launcher: open a terminal so the menu can be used
if [ ! -t 0 ] && command -v kitty &>/dev/null; then
    exec kitty --title "Monitor Alignment" python3 "$ENGINE" --calibrate "$@"
fi
exec python3 "$ENGINE" --calibrate "$@"
