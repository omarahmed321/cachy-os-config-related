#!/usr/bin/env bash
#===============================================================================
#   Omar's Favorite Setup Controller (omar-fav-setup)
#   Part of: CachyOS + HyDE System Restorer
#   Repo:    https://github.com/omarahmed321/cachy-os-config-related
#
#   Function:
#     1. Applies 3-Island Glassmorphism Waybar layout
#     2. Applies 3-Island Glassmorphism Dunst Notification theme
#     3. Sets background-for-me.jpg as active wallpaper with Pywal colors
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALLPAPER="$SCRIPT_DIR/background-for-me.jpg"

if [ ! -f "$WALLPAPER" ]; then
    WALLPAPER="$HOME/Pictures/Wallpapers/background-for-me.jpg"
fi

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
cat << "EOF"
  ==============================================================
       Omar's Favorite Setup Launcher (omar-fav-setup)
  ==============================================================
EOF
echo -e "${NC}"

# 1. Apply Glassmorphism Waybar Config
echo -e "${CYAN}[1/3] Applying Glassmorphism Waybar layout...${NC}"
if [ -f "$SCRIPT_DIR/setup-waybar-glassmorphism.sh" ]; then
    bash "$SCRIPT_DIR/setup-waybar-glassmorphism.sh"
elif [ -f "$HOME/.local/share/bin/setup-waybar-glassmorphism.sh" ]; then
    bash "$HOME/.local/share/bin/setup-waybar-glassmorphism.sh"
fi

# 2. Apply Glassmorphism Notification Theme
echo -e "${CYAN}[2/3] Applying Glassmorphism Notification theme...${NC}"
if [ -f "$SCRIPT_DIR/setup-notifications-theme.py" ]; then
    python3 "$SCRIPT_DIR/setup-notifications-theme.py" --auto
elif [ -f "$HOME/.local/share/bin/setup-notifications-theme.py" ]; then
    python3 "$HOME/.local/share/bin/setup-notifications-theme.py" --auto
fi

# 3. Set Favorite Wallpaper & Pywal colors
echo -e "${CYAN}[3/3] Setting favorite wallpaper (background-for-me.jpg)...${NC}"
if [ -f "$WALLPAPER" ]; then
    swwwallpaper.sh -s "$WALLPAPER" 2>/dev/null || swww img "$WALLPAPER"
    echo -e "${GREEN}[OK] Wallpaper applied successfully!${NC}"
else
    echo -e "${YELLOW}[!] Warning: background-for-me.jpg not found.${NC}"
fi

echo -e "\n${GREEN}${BOLD}[OK] Omar's Favorite Setup loaded successfully!${NC}\n"
