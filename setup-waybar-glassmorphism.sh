#!/usr/bin/env bash
#===============================================================================
#   Waybar Glassmorphism Permanent Master Setup Script (Pywal & HyDE Integrated)
#   Part of: CachyOS + HyDE Custom Waybar Enhancements
#   Repo:    https://github.com/omarahmed321/cachy-os-config-related
#===============================================================================

WAYBAR_DIR="$HOME/.config/waybar"
CONFIG_FILE="$WAYBAR_DIR/config.jsonc"
STYLE_FILE="$WAYBAR_DIR/style.css"
MODULE_STYLE_FILE="$WAYBAR_DIR/modules/style.css"
ACTIVE_FLAG="$WAYBAR_DIR/glassmorphism.active"
BIN_DEST="$HOME/.local/share/bin/setup-waybar-glassmorphism.sh"
WBARSTYLEGEN="$HOME/.local/share/bin/wbarstylegen.sh"
WBARCONFGEN="$HOME/.local/share/bin/wbarconfgen.sh"

# Colors for terminal output
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

apply_waybar_config() {
    mkdir -p "$WAYBAR_DIR/modules"

    # Write Glassmorphism Waybar Config (config.jsonc)
    cat << 'EOF' > "$CONFIG_FILE"
{
    "layer": "top",
    "position": "top",
    "height": 34,
    "margin-top": 4,
    "margin-left": 10,
    "margin-right": 10,
    "exclusive": true,
    "passthrough": false,
    "gtk-layer-shell": true,
    "reload_style_on_change": true,

    "modules-left": [
        "hyprland/workspaces"
    ],
    "modules-center": [
        "clock",
        "custom/separator",
        "custom/prayer"
    ],
    "modules-right": [
        "network",
        "bluetooth",
        "pulseaudio",
        "battery",
        "memory",
        "cpu",
        "tray"
    ],

    "hyprland/workspaces": {
        "disable-scroll": false,
        "all-outputs": true,
        "active-only": false,
        "on-click": "activate",
        "on-scroll-up": "hyprctl dispatch workspace -1",
        "on-scroll-down": "hyprctl dispatch workspace +1",
        "format": "{name} {windows}",
        "format-window-separator": " ",
        "window-rewrite-default": "",
        "window-rewrite": {
            "class<kitty>": "",
            "class<firefox>": "",
            "class<zen-alpha>": "󰈹",
            "class<zen-browser>": "󰈹",
            "class<chromium>": "",
            "class<google-chrome>": "",
            "class<dolphin>": "󰉋",
            "class<thunar>": "󰉋",
            "class<vs-code-oss>": "󰨞",
            "class<code-oss>": "󰨞",
            "class<code|Code>": "󰨞",
            "class<discord>": "󰙯",
            "class<spotify>": ""
        },
        "persistent-workspaces": {
            "1": [],
            "2": [],
            "3": [],
            "4": []
        }
    },

    "clock": {
        "format": "{:%I:%M %p}",
        "format-alt": "{:%Y-%m-%d %H:%M}",
        "tooltip-format": "<tt><small>{calendar}</small></tt>",
        "calendar": {
            "mode": "month",
            "on-scroll": 1,
            "format": {
                "months": "<span color='#ffead3'><b>{}</b></span>",
                "weekdays": "<span color='#ffcc66'><b>{}</b></span>",
                "today": "<span color='#ff6699'><b>{}</b></span>"
            }
        }
    },

    "custom/prayer": {
        "format": "{}",
        "exec": "$HOME/.local/share/bin/prayer_times.py",
        "interval": 1,
        "tooltip": false
    },

    "custom/separator": {
        "format": "|",
        "interval": "once",
        "tooltip": false
    },

    "network": {
        "format-wifi": "󰤨  {essid}",
        "format-ethernet": "󰈀 {ifname}",
        "format-linked": "󰈀 {ifname} (No IP)",
        "format-disconnected": "󰤯 Disconnected",
        "format-alt": "󰤨 {signalStrength}% | 󰇚 {bandwidthDownBytes} 󰕒 {bandwidthUpBytes}",
        "on-click": "kitty --class float_nmtui -e nmtui",
        "on-click-right": "nm-connection-editor",
        "tooltip-format": "󰤨 {essid}\nIP: {ipaddr}/{cidr}\nSignal: {signalStrength}%\nInterface: {ifname}"
    },

    "bluetooth": {
        "format": " {status}",
        "format-disabled": "󰂲 Off",
        "format-connected": "󰂱 {num_connections}",
        "tooltip-format": "{controller_alias}\t{controller_address}",
        "tooltip-format-connected": "{controller_alias}\t{controller_address}\n\n{device_enumerate}",
        "tooltip-format-enumerate-connected": "{device_alias}\t{device_address}",
        "on-click": "blueman-manager || kitty --class float_blueman -e bluetoothctl"
    },

    "pulseaudio": {
        "format": "{icon} {volume}%",
        "format-muted": "󰝟 Muted",
        "on-click": "pavucontrol -t 3",
        "on-click-right": "volumecontrol.sh -s '' 2>/dev/null || pamixer -t",
        "on-scroll-up": "volumecontrol.sh -o i 2>/dev/null || pamixer -i 5",
        "on-scroll-down": "volumecontrol.sh -o d 2>/dev/null || pamixer -d 5",
        "scroll-step": 5,
        "format-icons": {
            "headphone": "",
            "hands-free": "",
            "headset": "",
            "phone": "",
            "portable": "",
            "car": "",
            "default": ["", "", ""]
        },
        "tooltip-format": "{icon} {desc} // {volume}%"
    },

    "battery": {
        "states": {
            "good": 95,
            "warning": 30,
            "critical": 15
        },
        "format": "{icon} {capacity}%",
        "format-charging": "󰂄 {capacity}%",
        "format-plugged": "󰚥 {capacity}%",
        "format-alt": "{icon} {time}",
        "format-icons": ["󰂎", "󰁺", "󰁻", "󰁼", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"],
        "tooltip-format": "{timeTo}\nCapacity: {capacity}%\nPower: {power}W"
    },

    "memory": {
        "interval": 10,
        "format": "󰾆 {used:0.1f}G",
        "format-alt": "󰾆 {percentage}%",
        "tooltip-format": "Memory: {used:0.1f}GB / {total:0.1f}GB ({percentage}%)"
    },

    "cpu": {
        "interval": 10,
        "format": "󰍛 {usage}%",
        "format-alt": "󰍛 {avg_frequency}GHz",
        "tooltip-format": "CPU Usage: {usage}%"
    },

    "tray": {
        "icon-size": 16,
        "spacing": 10
    }
}
EOF

    # Write Pywal-integrated GTK Valid CSS to style.css and modules/style.css
    cat << 'EOF' > "$MODULE_STYLE_FILE"
/* =============================================================================
   Waybar Glassmorphism 3-Islands Master Style (Pywal Dynamic & Ultra Soft)
   Part of: CachyOS + HyDE Glassmorphism Setup
   ============================================================================= */

@import "theme.css";

* {
    border: none;
    border-radius: 0px;
    font-family: "JetBrainsMono Nerd Font", "Inter", sans-serif;
    font-weight: bold;
    font-size: 12px;
    min-height: 0px;
}

window#waybar {
    background: transparent;
}

/* ── 3-ISLAND GLASSMORPHISM CONTAINERS ─────────────────────────────────────── */
.modules-left,
.modules-center,
.modules-right {
    background: alpha(@main-bg, 0.50);
    border: 1px solid rgba(255, 255, 255, 0.08);
    border-radius: 16px;
    padding: 2px 12px;
    margin-top: 4px;
    margin-bottom: 4px;
    box-shadow: 0px 2px 6px rgba(0, 0, 0, 0.12);
    color: @main-fg;
}

.modules-left {
    margin-left: 10px;
}

.modules-right {
    margin-right: 10px;
}

/* ── WORKSPACES & WINDOW ICONS (LEFT ISLAND) ─────────────────────────────── */
#workspaces {
    background: transparent;
    padding: 0px;
    margin: 0px;
}

#workspaces button {
    box-shadow: none;
    text-shadow: none;
    padding: 3px 9px;
    margin: 2px 3px;
    border-radius: 8px;
    color: alpha(@main-fg, 0.65);
    background: rgba(255, 255, 255, 0.04);
    border: 1px solid transparent;
    transition: all 0.25s ease;
}

#workspaces button.active {
    background: @wb-act-bg;
    color: @wb-act-fg;
    border-radius: 8px;
    border: 1px solid rgba(255, 255, 255, 0.15);
    box-shadow: none;
}

#workspaces button:hover {
    background: @wb-hvr-bg;
    color: @wb-hvr-fg;
    border-radius: 8px;
}

#workspaces button.urgent {
    background: rgba(235, 77, 75, 0.6);
    color: #ffffff;
    border-radius: 8px;
}

/* ── CENTER ISLAND (CLOCK & PRAYER) ────────────────────────────────────────── */
#clock, #custom-prayer {
    padding: 0px 8px;
    color: alpha(@main-fg, 0.85);
}

#custom-separator {
    color: rgba(255, 255, 255, 0.15);
    padding: 0px 4px;
}

/* ── RIGHT ISLAND (NETWORK, BLUETOOTH, VOLUME, BATTERY, MEM, CPU, TRAY) ──────── */
#network, #bluetooth, #pulseaudio, #battery, #memory, #cpu, #tray {
    padding: 0px 7px;
    margin: 0px 2px;
    color: alpha(@main-fg, 0.85);
    border-radius: 8px;
}

#network:hover, #bluetooth:hover, #pulseaudio:hover, #battery:hover, #memory:hover, #cpu:hover {
    background: rgba(255, 255, 255, 0.08);
}

#network.disconnected {
    color: rgba(255, 107, 107, 0.85);
}

#bluetooth.disabled {
    color: rgba(160, 160, 160, 0.6);
}

#pulseaudio.muted {
    color: rgba(160, 160, 160, 0.7);
}

#battery.charging, #battery.plugged {
    color: rgba(46, 204, 113, 0.85);
}

#battery.critical:not(.charging) {
    color: rgba(231, 76, 60, 0.9);
}

/* ── TOOLTIPS ─────────────────────────────────────────────────────────────── */
tooltip {
    background: alpha(@main-bg, 0.88);
    border: 1px solid rgba(255, 255, 255, 0.12);
    border-radius: 12px;
    color: @main-fg;
    padding: 8px 12px;
    box-shadow: 0px 4px 10px rgba(0, 0, 0, 0.2);
}

tooltip label {
    padding: 4px;
}
EOF

    cp "$MODULE_STYLE_FILE" "$STYLE_FILE" 2>/dev/null || true
}

# Silent re-apply mode (used by HyDE theme change hooks)
if [ "$1" == "--apply-silent" ]; then
    apply_waybar_config
    exit 0
fi

echo -e "${CYAN}${BOLD}"
cat << "EOF"
  ==============================================================
     Waybar Glassmorphism Permanent Master Controller
  ==============================================================
EOF
echo -e "${NC}"

# Restore mode check
if [ "$1" == "--restore" ]; then
    echo -e "${YELLOW}[*] Removing Glassmorphism permanent lock flag...${NC}"
    rm -f "$ACTIVE_FLAG" 2>/dev/null || true
    
    if [ -f "$CONFIG_FILE.glass.bak" ]; then
        echo -e "${YELLOW}[*] Restoring original Waybar configuration...${NC}"
        cp "$CONFIG_FILE.glass.bak" "$CONFIG_FILE" 2>/dev/null || true
        cp "$STYLE_FILE.glass.bak" "$STYLE_FILE" 2>/dev/null || true
        cp "$MODULE_STYLE_FILE.glass.bak" "$MODULE_STYLE_FILE" 2>/dev/null || true
        echo -e "${GREEN}[OK] Restored successfully.${NC}"
        killall -9 waybar 2>/dev/null || true
        waybar &>/dev/null &
        exit 0
    else
        echo -e "${RED}[ERROR] No backup found at $CONFIG_FILE.glass.bak${NC}"
        exit 1
    fi
fi

# Stop waybar process first to release any file locks on style.css
echo -e "${CYAN}[*] Temporarily stopping Waybar to update configuration...${NC}"
killall -9 waybar 2>/dev/null || true
sleep 0.5

# Create Backup if not already backed up
if [ -f "$CONFIG_FILE" ] && [ ! -f "$CONFIG_FILE.glass.bak" ]; then
    echo -e "${CYAN}[*] Creating backup of current Waybar config & styles...${NC}"
    cp "$CONFIG_FILE" "$CONFIG_FILE.glass.bak"
    cp "$STYLE_FILE" "$STYLE_FILE.glass.bak" 2>/dev/null || true
    cp "$MODULE_STYLE_FILE" "$MODULE_STYLE_FILE.glass.bak" 2>/dev/null || true
fi

# Write Glassmorphism Config & Styles
echo -e "${CYAN}[*] Applying permanent Glassmorphism layout & Pywal styles...${NC}"
apply_waybar_config

# Set Active Lock Flag
touch "$ACTIVE_FLAG"
mkdir -p "$HOME/.local/share/bin"
cp "$0" "$BIN_DEST" 2>/dev/null || true
chmod +x "$BIN_DEST" 2>/dev/null || true

# Patch wbarstylegen.sh to maintain Glassmorphism layout permanently on theme switch
if [ -f "$WBARSTYLEGEN" ]; then
    if ! grep -q "glassmorphism.active" "$WBARSTYLEGEN"; then
        echo -e "${CYAN}[*] Registering permanent hook in HyDE theme engine (wbarstylegen.sh)...${NC}"
        cat << 'HOOK' >> "$WBARSTYLEGEN"

# Permanent Glassmorphism Lock Hook
if [ -f "$HOME/.config/waybar/glassmorphism.active" ] && [ -f "$HOME/.local/share/bin/setup-waybar-glassmorphism.sh" ]; then
    bash "$HOME/.local/share/bin/setup-waybar-glassmorphism.sh" --apply-silent
fi
HOOK
    fi
fi

# Patch wbarconfgen.sh to maintain Glassmorphism layout permanently on theme switch
if [ -f "$WBARCONFGEN" ]; then
    if ! grep -q "glassmorphism.active" "$WBARCONFGEN"; then
        echo -e "${CYAN}[*] Registering permanent hook in HyDE config generator (wbarconfgen.sh)...${NC}"
        cat << 'HOOK' >> "$WBARCONFGEN"

# Permanent Glassmorphism Lock Hook
if [ -f "$HOME/.config/waybar/glassmorphism.active" ] && [ -f "$HOME/.local/share/bin/setup-waybar-glassmorphism.sh" ]; then
    bash "$HOME/.local/share/bin/setup-waybar-glassmorphism.sh" --apply-silent
fi
HOOK
    fi
fi

# Restart Waybar to apply changes live
echo -e "${GREEN}[+] Starting Waybar with permanent Glassmorphism layout...${NC}"
waybar &>/dev/null &

echo -e "\n${GREEN}${BOLD}[OK] Clean Glassmorphism Waybar applied successfully!${NC}"
