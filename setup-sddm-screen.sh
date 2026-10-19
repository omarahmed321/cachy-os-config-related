#!/usr/bin/env bash
#===============================================================================
#   Standalone SDDM Display & Screen Selector Tool (CLI & GUI)
#   Part of: CachyOS + HyDE System Restorer
#   Repo:    https://github.com/omarahmed321/cachy-os-config-related
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
cat << "EOF"
  ==============================================================
            SDDM Login Screen Selector Tool (Universal)
  ==============================================================
EOF
echo -e "${NC}"

# If GUI environment is active, launch Python GUI panel
if command -v python3 &>/dev/null && [ -f "$SCRIPT_DIR/sddm-screen-config.py" ] && { [ -n "$WAYLAND_DISPLAY" ] || [ -n "$DISPLAY" ]; }; then
    echo -e "${GREEN}[+] Launching SDDM Screen Selector GUI...${NC}"
    python3 "$SCRIPT_DIR/sddm-screen-config.py" &
    exit 0
fi

# Fallback: CLI Terminal Mode
if command -v hyprctl &>/dev/null && hyprctl monitors &>/dev/null; then
    MONITORS_JSON=$(hyprctl monitors -j)
    mapfile -t MONITOR_NAMES < <(echo "$MONITORS_JSON" | jq -r '.[].name')
    NUM_MONITORS=${#MONITOR_NAMES[@]}
    
    if [ "$NUM_MONITORS" -gt 0 ]; then
        echo -e "${YELLOW}Connected Monitors Detected:${NC}"
        for i in "${!MONITOR_NAMES[@]}"; do
            m_name="${MONITOR_NAMES[i]}"
            m_w=$(echo "$MONITORS_JSON" | jq -r ".[$i].width")
            m_h=$(echo "$MONITORS_JSON" | jq -r ".[$i].height")
            m_hz=$(echo "$MONITORS_JSON" | jq -r ".[$i].refreshRate" | cut -d'.' -f1)
            m_model=$(echo "$MONITORS_JSON" | jq -r ".[$i].model // \"Screen\"")
            echo -e "  [$((i+1))] ${GREEN}${m_name}${NC} (${m_w}x${m_h}@${m_hz}Hz - ${m_model})"
        done
        
        read -p "Select monitor for SDDM Login [1-$NUM_MONITORS] (Default: 1): " choice
        choice="${choice:-1}"
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$NUM_MONITORS" ]; then
            echo -e "${YELLOW}[!] Invalid choice: $choice${NC}"
            exit 1
        fi
        TARGET_SCREEN="${MONITOR_NAMES[choice - 1]}"
        
        if [ -n "$TARGET_SCREEN" ]; then
            python3 "$SCRIPT_DIR/sddm-screen-config.py" --set "$TARGET_SCREEN"
            echo -e "${GREEN}[OK] SDDM Login Screen target saved to: ${TARGET_SCREEN}${NC}"
        fi
    fi
fi
