#!/usr/bin/env bash
#===============================================================================
#   Standalone Arabic Keyboard Custom Layout Installer (Thal on Backslash)
#   This script adds a custom XKB keyboard variant that maps the Arabic 'ذ'
#   character to the backslash '\' key, with '\' accessible via AltGr.
#===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

XKB_ARA_FILE="/usr/share/X11/xkb/symbols/ara"

echo -e "${CYAN}${BOLD}======================================================================${NC}"
echo -e "${MAGENTA}${BOLD}         Arabic Keyboard Customizer (Thal on Backslash)               ${NC}"
echo -e "${CYAN}${BOLD}======================================================================${NC}"

# Check for write permissions or sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}[*] Root permissions required to modify system keyboard layouts.${NC}"
    echo -e "${YELLOW}[*] Elevating privileges via sudo...${NC}"
    exec sudo "$0" "$@"
fi

# Verify XKB symbols file exists
if [ ! -f "$XKB_ARA_FILE" ]; then
    echo -e "${RED}[ERROR] System Arabic keyboard layout file not found at: $XKB_ARA_FILE${NC}"
    exit 1
fi

# Check if the variant is already installed
if grep -q 'xkb_symbols "thal_bksl"' "$XKB_ARA_FILE"; then
    echo -e "${GREEN}[+] The 'thal_bksl' layout variant is already installed in your system!${NC}"
else
    echo -e "${BLUE}[*] Backing up system XKB Arabic layout file...${NC}"
    cp "$XKB_ARA_FILE" "${XKB_ARA_FILE}.bak"

    echo -e "${BLUE}[*] Appending the custom 'thal_bksl' variant to $XKB_ARA_FILE...${NC}"
    cat << 'EOF' >> "$XKB_ARA_FILE"

// Custom Arabic layout variant with ذ (Arabic_thal) on the backslash key
partial alphanumeric_keys
xkb_symbols "thal_bksl" {
    include "ara(basic)"

    name[Group1]= "Arabic (Thal on backslash)";

    // Put ذ on the backslash key, with \ on AltGr
    key <BKSL> {[     Arabic_thal,        Arabic_shadda,           backslash,             bar ]};
};
EOF
    echo -e "${GREEN}[+] Successfully installed custom Arabic keyboard variant!${NC}"
fi

echo -e "\n${YELLOW}${BOLD}--- HOW TO ACTIVATE THE NEW LAYOUT ---${NC}"

echo -e "\n${CYAN}Option A: For i3 / X11 desktops:${NC}"
echo -e "Run this command to set layout (toggles layout with Alt+Shift):"
echo -e "${BOLD}setxkbmap -layout us,ara -variant ,thal_bksl -option grp:alt_shift_toggle${NC}"
echo -e "To make it permanent, add the command above to your ${BOLD}~/.config/i3/config${NC} file."

echo -e "\n${CYAN}Option B: For Hyprland / Wayland desktops:${NC}"
echo -e "Open your ${BOLD}~/.config/hypr/hyprland.conf${NC} and edit your input section like this:"
echo -e "${MAGENTA}input {${NC}"
echo -e "${MAGENTA}    kb_layout = us,ara${NC}"
echo -e "${MAGENTA}    kb_variant = ,thal_bksl${NC}"
echo -e "${MAGENTA}    kb_options = grp:alt_shift_toggle  # Or: grp:win_space_toggle${NC}"
echo -e "${MAGENTA}}${NC}"

echo -e "\n${GREEN}${BOLD}======================================================================${NC}"
