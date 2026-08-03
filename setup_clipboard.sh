#!/usr/bin/env bash
#===============================================================================
#   Universal Clipboard Manager Setup (Supports Wayland/Hyprland & X11/i3)
#   This script dynamically detects if you are running Wayland (Hyprland)
#   or X11 (i3/bspwm) and configures the appropriate clipboard history tool
#   (cliphist for Wayland, greenclip for X11).
#===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Root Check ---
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}[ERROR] Please do NOT run this script as root. Run it as your normal user.${NC}"
    exit 1
fi

echo -e "${BLUE}${BOLD}======================================================================${NC}"
echo -e "${BLUE}${BOLD}         Universal Clipboard History Installer & Setup                ${NC}"
echo -e "${BLUE}${BOLD}======================================================================${NC}"

# --- Step 1: Detect Session Type ---
SESSION_TYPE="wayland"
if [ -n "$WAYLAND_DISPLAY" ]; then
    SESSION_TYPE="wayland"
    echo -e "${GREEN}[+] Wayland session detected (Hyprland/Sway).${NC}"
elif [ -n "$DISPLAY" ]; then
    SESSION_TYPE="x11"
    echo -e "${GREEN}[+] X11 session detected (i3/bspwm/XFCE).${NC}"
else
    # Fallback checks based on config directories
    if [ -d "$HOME/.config/i3" ]; then
        SESSION_TYPE="x11"
        echo -e "${YELLOW}[!] Display environment empty, but i3 config folder found. Defaulting to X11.${NC}"
    else
        SESSION_TYPE="wayland"
        echo -e "${YELLOW}[!] Display environment empty. Defaulting to Wayland (Hyprland).${NC}"
    fi
fi

# --- Step 2: Install Dependencies ---
echo -e "\n${BLUE}${BOLD}[1/3] Checking and installing dependencies for $SESSION_TYPE...${NC}"

# Auto detect AUR Helper
AUR_HELPER=""
if command -v yay &>/dev/null; then
    AUR_HELPER="yay"
elif command -v paru &>/dev/null; then
    AUR_HELPER="paru"
else
    AUR_HELPER="sudo pacman"
fi

if [ "$SESSION_TYPE" = "wayland" ]; then
    DEPENDENCIES=(wl-clipboard cliphist rofi-wayland libnotify jq)
    TO_INSTALL=()
    for pkg in "${DEPENDENCIES[@]}"; do
        if pacman -Qi "$pkg" &>/dev/null; then
            echo -e "  - ${GREEN}[Installed]${NC} $pkg"
        else
            TO_INSTALL+=("$pkg")
        fi
    done
    if [ ${#TO_INSTALL[@]} -gt 0 ]; then
        echo -e "${YELLOW}[*] Installing Wayland dependencies: ${TO_INSTALL[*]}...${NC}"
        $AUR_HELPER -S --needed --noconfirm "${TO_INSTALL[@]}"
    fi
else
    # X11 / i3 Dependencies
    DEPENDENCIES=(xclip rofi libnotify)
    TO_INSTALL=()
    for pkg in "${DEPENDENCIES[@]}"; do
        if pacman -Qi "$pkg" &>/dev/null; then
            echo -e "  - ${GREEN}[Installed]${NC} $pkg"
        else
            TO_INSTALL+=("$pkg")
        fi
    done
    if [ ${#TO_INSTALL[@]} -gt 0 ]; then
        echo -e "${YELLOW}[*] Installing X11 dependencies: ${TO_INSTALL[*]}...${NC}"
        $AUR_HELPER -S --needed --noconfirm "${TO_INSTALL[@]}"
    fi

    # Check for greenclip daemon
    if command -v greenclip &>/dev/null; then
        echo -e "  - ${GREEN}[Installed]${NC} greenclip"
    else
        if [ "$AUR_HELPER" = "sudo pacman" ]; then
            echo -e "${RED}[ERROR] greenclip is an AUR package, but no AUR helper (yay/paru) was found. Please install yay first.${NC}"
            exit 1
        fi
        echo -e "${YELLOW}[*] Installing greenclip daemon from AUR...${NC}"
        $AUR_HELPER -S --needed --noconfirm greenclip-bin
    fi
fi

# --- Step 3: Deploy Standalone cliphist-menu.sh ---
echo -e "\n${BLUE}${BOLD}[2/3] Writing standalone clipboard manager script...${NC}"
mkdir -p "$HOME/.local/bin"
MENU_SCRIPT="$HOME/.local/bin/cliphist-menu.sh"

if [ "$SESSION_TYPE" = "wayland" ]; then
    # Wayland menu script using cliphist
    cat << 'EOF' > "$MENU_SCRIPT"
#!/usr/bin/env bash
ROFI_THEME="-theme-str 'window { width: 40%; } listview { lines: 10; }'"
FAVORITES_FILE="$HOME/.cliphist_favorites"

main_action=""
if [ $# -eq 0 ]; then
    main_action=$(echo -e "📋 Clipboard History\n❌ Delete Entry\n⭐ View Favorites\n➕ Add to Favorites\n🗑️ Clear History" | rofi -dmenu -i -p "Clipboard Actions" -font "JetBrainsMono Nerd Font 11" $ROFI_THEME)
else
    main_action="📋 Clipboard History"
fi

case "$main_action" in
    "📋 Clipboard History")
        selected=$(cliphist list | rofi -dmenu -i -p "Paste Item" -font "JetBrainsMono Nerd Font 11" $ROFI_THEME)
        if [ -n "$selected" ]; then
            echo "$selected" | cliphist decode | wl-copy
            notify-send "Clipboard" "Item copied to active clipboard" -i edit-paste
        fi
        ;;
    "❌ Delete Entry")
        selected=$(cliphist list | rofi -dmenu -i -p "Delete Item" -font "JetBrainsMono Nerd Font 11" $ROFI_THEME)
        if [ -n "$selected" ]; then
            echo "$selected" | cliphist delete
            notify-send "Clipboard" "Item deleted from history" -i edit-delete
        fi
        ;;
    "⭐ View Favorites")
        if [ -f "$FAVORITES_FILE" ] && [ -s "$FAVORITES_FILE" ]; then
            mapfile -t favorites < "$FAVORITES_FILE"
            decoded_lines=()
            for fav in "${favorites[@]}"; do
                decoded_lines+=("$(echo "$fav" | base64 --decode | tr '\n' ' ' | cut -c1-60)...")
            done
            selected_fav=$(printf "%s\n" "${decoded_lines[@]}" | rofi -dmenu -i -p "Favorite Item" -font "JetBrainsMono Nerd Font 11" $ROFI_THEME)
            if [ -n "$selected_fav" ]; then
                index=$(printf "%s\n" "${decoded_lines[@]}" | grep -nxF "$selected_fav" | cut -d: -f1)
                if [ -n "$index" ]; then
                    echo "${favorites[$((index - 1))]}" | base64 --decode | wl-copy
                    notify-send "Clipboard" "Favorite item copied to active clipboard" -i edit-paste
                fi
            fi
        else
            notify-send "Clipboard" "No favorites saved yet" -i dialog-warning
        fi
        ;;
    "➕ Add to Favorites")
        selected=$(cliphist list | rofi -dmenu -i -p "Add to Favorites" -font "JetBrainsMono Nerd Font 11" $ROFI_THEME)
        if [ -n "$selected" ]; then
            full_item=$(echo "$selected" | cliphist decode)
            encoded_item=$(echo "$full_item" | base64 -w 0)
            if grep -Fxq "$encoded_item" "$FAVORITES_FILE" 2>/dev/null; then
                notify-send "Clipboard" "Item is already in favorites" -i dialog-information
            else
                echo "$encoded_item" >> "$FAVORITES_FILE"
                notify-send "Clipboard" "Added to favorites successfully" -i emc-favorites
            fi
        fi
        ;;
    "🗑️ Clear History")
        confirm=$(echo -e "No\nYes" | rofi -dmenu -i -p "Clear Entire Clipboard History?" -font "JetBrainsMono Nerd Font 11" $ROFI_THEME)
        if [ "$confirm" = "Yes" ]; then
            cliphist wipe
            notify-send "Clipboard" "Entire clipboard history has been cleared" -i edit-clear
        fi
        ;;
esac
EOF
else
    # X11 / i3 menu script using greenclip
    cat << 'EOF' > "$MENU_SCRIPT"
#!/usr/bin/env bash
# Standalone X11 selector using greenclip
rofi -modi "clipboard:greenclip print" -show clipboard -run-command '{cmd}'
EOF
fi

chmod +x "$MENU_SCRIPT"
echo -e "${GREEN}[+] Standalone script written and made executable at: $MENU_SCRIPT${NC}"

# --- Step 4: Desktop Autostart & Hotkeys Integration ---
echo -e "\n${BLUE}${BOLD}[3/3] Setting up desktop environment integration...${NC}"

if [ "$SESSION_TYPE" = "wayland" ]; then
    HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
    if [ -f "$HYPR_CONF" ]; then
        if ! grep -q "cliphist store" "$HYPR_CONF"; then
            echo -e "\n# Standalone Clipboard History Listeners" >> "$HYPR_CONF"
            echo "exec-once = wl-paste --type text --watch cliphist store" >> "$HYPR_CONF"
            echo "exec-once = wl-paste --type image --watch cliphist store" >> "$HYPR_CONF"
            echo -e "${GREEN}[+] Clipboard listener daemons appended to $HYPR_CONF${NC}"
        fi
        KEY_CONF="$HOME/.config/hypr/keybindings.conf"
        if [ -f "$KEY_CONF" ]; then
            if ! grep -q "cliphist-menu.sh" "$KEY_CONF"; then
                echo -e "\n# Clipboard History Hotkeys\nbind = \$mainMod, V, exec, $MENU_SCRIPT" >> "$KEY_CONF"
                echo -e "${GREEN}[+] Super + V keybinding appended to $KEY_CONF${NC}"
            fi
        fi
    fi
else
    # X11 / i3 Setup
    I3_CONF="$HOME/.config/i3/config"
    if [ -f "$I3_CONF" ]; then
        if ! grep -q "greenclip daemon" "$I3_CONF"; then
            # Comment out duplicate bindsym $mod+v to prevent i3 syntax errors
            if grep -qE "bindsym .*[[:space:]]v[[:space:]]" "$I3_CONF" || grep -qE "bindsym .*\\\$mod\\+v" "$I3_CONF"; then
                echo -e "${YELLOW}[*] Commenting out duplicate keybindings for \$mod+v in i3 config...${NC}"
                # Backup config
                cp "$I3_CONF" "${I3_CONF}.bak"
                # Comment out the matching bindsym line
                sed -i -E 's/^([[:space:]]*bindsym[[:space:]]+(\$mod|Mod[1-5]|[a-zA-Z0-9]+)\+v[[:space:]].*)/# \1 # Disabled by setup_clipboard.sh to avoid duplicate keybinding/g' "$I3_CONF"
            fi

            echo -e "\n# Standalone Clipboard History (Greenclip)" >> "$I3_CONF"
            echo "exec --no-startup-id greenclip daemon" >> "$I3_CONF"
            echo "bindsym \$mod+v exec $MENU_SCRIPT" >> "$I3_CONF"
            echo -e "${GREEN}[+] greenclip daemon and Mod+V keybinding appended to $I3_CONF${NC}"
            # Reload i3 config
            if command -v i3-msg &>/dev/null; then
                i3-msg reload &>/dev/null || true
            fi
        else
            echo -e "${YELLOW}[*] i3 is already configured with greenclip.${NC}"
        fi
    else
        echo -e "${YELLOW}[!] i3/config was not found. Please manually launch these commands at startup:${NC}"
        echo "  greenclip daemon &"
        echo "  And bind a hotkey to run: $MENU_SCRIPT"
    fi
fi

echo -e "\n${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}${BOLD}   Universal Clipboard Setup completed successfully!                 ${NC}"
echo -e "${GREEN}${BOLD}   Use Super + V (or Mod + V in i3) to open clipboard history.        ${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
