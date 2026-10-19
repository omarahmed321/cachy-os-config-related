#!/usr/bin/env bash
#===============================================================================
#   Dual Monitor Cursor Alignment & Position Calibration Tool
#   Part of: CachyOS + HyDE Complete System Restorer
#   Repo:    https://github.com/omarahmed321/cachy-os-config-related
#===============================================================================

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
cat << "EOF"
  ==============================================================
   Dual Monitor Cursor Alignment & Boundary Calibration Tool
  ==============================================================
EOF
echo -e "${NC}"

# Check Hyprland environment
if [ -z "$WAYLAND_DISPLAY" ]; then
    echo -e "${RED}[ERROR] Wayland display not found. This script requires active Hyprland session.${NC}"
    exit 1
fi

# Detect monitors using hyprctl
MONITORS_JSON=$(hyprctl monitors -j 2>/dev/null)
MONITOR_COUNT=$(echo "$MONITORS_JSON" | jq '. | length' 2>/dev/null || echo "0")

if [ "$MONITOR_COUNT" -lt 2 ]; then
    echo -e "${YELLOW}[WARNING] Only $MONITOR_COUNT monitor detected. Alignment calibration requires dual monitors.${NC}"
    if command -v zenity &>/dev/null; then
        zenity --warning --title="Single Monitor Detected" --text="Only 1 monitor was detected on this system.\nDual monitor cursor alignment requires at least 2 connected displays." --width=350 2>/dev/null
    fi
    exit 0
fi

# Sort monitors by refresh rate descending to pick highest refresh rate (e.g. 144Hz) as default Main
SORTED_MONITORS=$(echo "$MONITORS_JSON" | jq 'sort_by(.refreshRate) | reverse')

MAIN_NAME=$(echo "$SORTED_MONITORS" | jq -r '.[0].name')
SIDE_NAME=$(echo "$SORTED_MONITORS" | jq -r '.[1].name')

MAIN_WIDTH=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$MAIN_NAME\") | .width")
MAIN_HEIGHT=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$MAIN_NAME\") | .height")
MAIN_HZ=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$MAIN_NAME\") | .refreshRate" | cut -d'.' -f1)
MAIN_TRANSFORM=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$MAIN_NAME\") | .transform")

SIDE_WIDTH=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$SIDE_NAME\") | .width")
SIDE_HEIGHT=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$SIDE_NAME\") | .height")
SIDE_HZ=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$SIDE_NAME\") | .refreshRate" | cut -d'.' -f1)
SIDE_TRANSFORM=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$SIDE_NAME\") | .transform")

MAIN_POSITION="RIGHT" # Options: "RIGHT" or "LEFT"
OFFSET_Y=0

# Preserve Y offset from existing monitors.conf if present
MONITORS_CONF="$HOME/.config/hypr/monitors.conf"
if [ -f "$MONITORS_CONF" ]; then
    EXISTING_MAIN_LINE=$(grep -E "^\s*monitor\s*=\s*${MAIN_NAME}\s*," "$MONITORS_CONF" | head -n 1)
    if [ -n "$EXISTING_MAIN_LINE" ]; then
        POS_FIELD=$(echo "$EXISTING_MAIN_LINE" | cut -d',' -f3 | tr -d '[:space:]')
        if [[ "$POS_FIELD" =~ ^([0-9]+)x([0-9]+)$ ]]; then
            OFFSET_Y="${BASH_REMATCH[2]}"
        fi
    fi
fi

# Calibration Loop
while true; do
    # Fetch current widths/heights dynamically in case MAIN_NAME or SIDE_NAME changed
    MAIN_WIDTH=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$MAIN_NAME\") | .width")
    MAIN_HEIGHT=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$MAIN_NAME\") | .height")
    MAIN_HZ=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$MAIN_NAME\") | .refreshRate" | cut -d'.' -f1)

    SIDE_WIDTH=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$SIDE_NAME\") | .width")
    SIDE_HEIGHT=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$SIDE_NAME\") | .height")
    SIDE_HZ=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$SIDE_NAME\") | .refreshRate" | cut -d'.' -f1)

    if [ "$SIDE_TRANSFORM" -eq 1 ] || [ "$SIDE_TRANSFORM" -eq 3 ]; then
        ROTATED_SIDE_WIDTH=${SIDE_HEIGHT}
        ROTATED_SIDE_HEIGHT=${SIDE_WIDTH}
    else
        ROTATED_SIDE_WIDTH=${SIDE_WIDTH}
        ROTATED_SIDE_HEIGHT=${SIDE_HEIGHT}
    fi
    
    if [ "$MAIN_TRANSFORM" -eq 1 ] || [ "$MAIN_TRANSFORM" -eq 3 ]; then
        ROTATED_MAIN_WIDTH=${MAIN_HEIGHT}
        ROTATED_MAIN_HEIGHT=${MAIN_WIDTH}
    else
        ROTATED_MAIN_WIDTH=${MAIN_WIDTH}
        ROTATED_MAIN_HEIGHT=${MAIN_HEIGHT}
    fi
    
    if [ "$MAIN_POSITION" = "RIGHT" ]; then
        SIDE_POS="0x0"
        MAIN_POS="${ROTATED_SIDE_WIDTH}x${OFFSET_Y}"
    else
        MAIN_POS="0x${OFFSET_Y}"
        SIDE_POS="${ROTATED_MAIN_WIDTH}x0"
    fi

    # Generate monitor lines
    MONITOR_CONFIGS="monitor = ${MAIN_NAME},${MAIN_WIDTH}x${MAIN_HEIGHT}@${MAIN_HZ},${MAIN_POS},1,transform,${MAIN_TRANSFORM}\n"
    MONITOR_CONFIGS="${MONITOR_CONFIGS}monitor = ${SIDE_NAME},${SIDE_WIDTH}x${SIDE_HEIGHT}@${SIDE_HZ},${SIDE_POS},1,transform,${SIDE_TRANSFORM}"
    
    # Workspace rules
    WORKSPACE_RULES="# Workspace Rules\n"
    for w in {1..8}; do
        WORKSPACE_RULES="${WORKSPACE_RULES}workspace = ${w}, monitor:${MAIN_NAME}"
        [ $w -eq 1 ] && WORKSPACE_RULES="${WORKSPACE_RULES}, default:true"
        WORKSPACE_RULES="${WORKSPACE_RULES}\n"
    done
    for w in {9..10}; do
        WORKSPACE_RULES="${WORKSPACE_RULES}workspace = ${w}, monitor:${SIDE_NAME}"
        [ $w -eq 9 ] && WORKSPACE_RULES="${WORKSPACE_RULES}, default:true"
        WORKSPACE_RULES="${WORKSPACE_RULES}\n"
    done

    mkdir -p "$HOME/.config/hypr"
    cat << MONEOF > "$HOME/.config/hypr/monitors.conf"
# █▀▄▀█ █▀█ █▄░█ █ ▀█▀ █▀█ █▀█ █▀
# █░▀░█ █▄█ █░▀█ █ ░█░ █▄█ █▀▄ ▄█
# Dynamically configured by monitor-alignment.sh

$(echo -e "$MONITOR_CONFIGS")

$(echo -e "$WORKSPACE_RULES")
MONEOF
    
    # Apply changes dynamically in Hyprland
    if command -v hyprctl &>/dev/null; then
        hyprctl keyword monitor "${MAIN_NAME},${MAIN_WIDTH}x${MAIN_HEIGHT}@${MAIN_HZ},${MAIN_POS},1,transform,${MAIN_TRANSFORM}" &>/dev/null
        hyprctl keyword monitor "${SIDE_NAME},${SIDE_WIDTH}x${SIDE_HEIGHT}@${SIDE_HZ},${SIDE_POS},1,transform,${SIDE_TRANSFORM}" &>/dev/null
        
        # Refresh wallpaper daemon (swww) for both screens
        if command -v swwwallpaper.sh &>/dev/null; then
            swwwallpaper.sh &>/dev/null &
        elif command -v swww &>/dev/null; then
            CURRENT_WALL=$(swww query 2>/dev/null | grep -oP 'image: \K.*' | head -n 1)
            [ -n "$CURRENT_WALL" ] && swww img "$CURRENT_WALL" &>/dev/null &
        fi
    fi

    STATUS_TEXT="👑 Main (Primary): ${MAIN_NAME} (${MAIN_HZ}Hz) [Position: ${MAIN_POSITION}]\n"
    STATUS_TEXT="${STATUS_TEXT}🖥️ Secondary: ${SIDE_NAME} (${SIDE_HZ}Hz)\n"
    STATUS_TEXT="${STATUS_TEXT}📐 Current Y-Offset: ${OFFSET_Y}px"

    # Show list dialog
    if command -v zenity &>/dev/null; then
        choice=$(zenity --list \
            --title="Mouse Path & Monitor Alignment Calibration" \
            --text="$STATUS_TEXT" \
            --column="Action / Adjustment" \
            "👑 Switch Primary Monitor (${MAIN_NAME} ↔ ${SIDE_NAME})" \
            "↔️ Swap Main Position (Main is on ${MAIN_POSITION})" \
            "Rotate Secondary (${SIDE_NAME}): Landscape (Normal)" \
            "Rotate Secondary (${SIDE_NAME}): Portrait (90°)" \
            "Rotate Secondary (${SIDE_NAME}): Flipped Landscape (180°)" \
            "Rotate Secondary (${SIDE_NAME}): Flipped Portrait (270°)" \
            "Rotate Main (${MAIN_NAME}): Landscape (Normal)" \
            "Rotate Main (${MAIN_NAME}): Portrait (90°)" \
            "Enter Custom Y-Offset Value" \
            "Shift Main Monitor Down (+50px)" \
            "Shift Main Monitor Up (-50px)" \
            "Fine-tune Down (+10px)" \
            "Fine-tune Up (-10px)" \
            "Save and Exit" \
            --width=520 --height=600 2>/dev/null)
    else
        echo -e "\n${CYAN}1) Switch Primary Monitor${NC}"
        echo -e "${CYAN}2) Swap Main Position (RIGHT/LEFT)${NC}"
        echo -e "${CYAN}3) Rotate Secondary (${SIDE_NAME}): Landscape${NC}"
        echo -e "${CYAN}4) Rotate Secondary (${SIDE_NAME}): Portrait${NC}"
        echo -e "${CYAN}5) Shift Main Monitor Down (+50px)${NC}"
        echo -e "${CYAN}6) Shift Main Monitor Up (-50px)${NC}"
        echo -e "${CYAN}7) Save and Exit${NC}"
        read -p "Select option [1-7]: " cli_choice
        case "$cli_choice" in
            1) choice="👑 Switch Primary Monitor (${MAIN_NAME} ↔ ${SIDE_NAME})" ;;
            2) choice="↔️ Swap Main Position (Main is on ${MAIN_POSITION})" ;;
            3) choice="Rotate Secondary (${SIDE_NAME}): Landscape (Normal)" ;;
            4) choice="Rotate Secondary (${SIDE_NAME}): Portrait (90°)" ;;
            5) choice="Shift Main Monitor Down (+50px)" ;;
            6) choice="Shift Main Monitor Up (-50px)" ;;
            *) choice="Save and Exit" ;;
        esac
    fi
        
    case "$choice" in
        "👑 Switch Primary Monitor ("*)
            # Swap Main and Side monitors
            TEMP_NAME="$MAIN_NAME"
            MAIN_NAME="$SIDE_NAME"
            SIDE_NAME="$TEMP_NAME"
            TEMP_TRANS="$MAIN_TRANSFORM"
            MAIN_TRANSFORM="$SIDE_TRANSFORM"
            SIDE_TRANSFORM="$TEMP_TRANS"
            ;;
        "↔️ Swap Main Position ("*)
            if [ "$MAIN_POSITION" = "RIGHT" ]; then
                MAIN_POSITION="LEFT"
            else
                MAIN_POSITION="RIGHT"
            fi
            ;;
        "Rotate Secondary ("*"): Landscape (Normal)")
            SIDE_TRANSFORM=0
            ;;
        "Rotate Secondary ("*"): Portrait (90°)")
            SIDE_TRANSFORM=1
            ;;
        "Rotate Secondary ("*"): Flipped Landscape (180°)")
            SIDE_TRANSFORM=2
            ;;
        "Rotate Secondary ("*"): Flipped Portrait (270°)")
            SIDE_TRANSFORM=3
            ;;
        "Rotate Main ("*"): Landscape (Normal)")
            MAIN_TRANSFORM=0
            ;;
        "Rotate Main ("*"): Portrait (90°)")
            MAIN_TRANSFORM=1
            ;;
        "Enter Custom Y-Offset Value")
            if command -v zenity &>/dev/null; then
                custom_val=$(zenity --entry \
                    --title="Custom Y-Offset" \
                    --text="Enter Y-offset in pixels (e.g., 0, 100, 680...):" \
                    --entry-text="$OFFSET_Y" 2>/dev/null)
            else
                read -p "Enter custom Y-offset in pixels: " custom_val
            fi
            if [[ "$custom_val" =~ ^-?[0-9]+$ ]]; then
                OFFSET_Y=$custom_val
            fi
            ;;
        "Shift Main Monitor Down (+50px)")
            OFFSET_Y=$((OFFSET_Y + 50))
            ;;
        "Shift Main Monitor Up (-50px)")
            OFFSET_Y=$((OFFSET_Y - 50))
            ;;
        "Fine-tune Down (+10px)")
            OFFSET_Y=$((OFFSET_Y + 10))
            ;;
        "Fine-tune Up (-10px)")
            OFFSET_Y=$((OFFSET_Y - 10))
            ;;
        *)
            echo -e "${GREEN}[+] Alignment configuration saved to ~/.config/hypr/monitors.conf successfully!${NC}"
            break
            ;;
    esac
done
