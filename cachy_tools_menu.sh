#!/usr/bin/env bash
#===============================================================================
#   CachyOS & Hyprland Universal Tools Control Center Menu
#   Part of: CachyOS + HyDE Complete System Restorer
#   Repo:    https://github.com/omarahmed321/cachy-os-config-related
#
#   Usage:
#     ./cachy_tools_menu.sh          → Interactive Terminal CLI Menu
#     ./cachy_tools_menu.sh --gui    → Graphical Rofi/Zenity Launcher Menu
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Helper to find tool paths
find_tool() {
    local name="$1"
    if [ -f "$SCRIPT_DIR/$name" ]; then
        echo "$SCRIPT_DIR/$name"
    elif [ -f "$HOME/.local/share/bin/$name" ]; then
        echo "$HOME/.local/share/bin/$name"
    elif [ -f "$HOME/.local/bin/$name" ]; then
        echo "$HOME/.local/bin/$name"
    elif [ -f "$HOME/$name" ]; then
        echo "$HOME/$name"
    else
        echo ""
    fi
}

# Locate script targets
FAV_PATH=$(find_tool "omar-fav-setup.sh")
WP_PATH=$(find_tool "setup-wordpress-local.sh")
POLKIT_PATH=$(find_tool "fix-polkit-localwp.sh")
NIGHTLIGHT_PATH=$(find_tool "nightlight-gui.py")
DISPLAY_PATH=$(find_tool "hypr-display-settings.py")
ALIGNMENT_PATH=$(find_tool "monitor-alignment.sh")
WAYBAR_PATH=$(find_tool "setup-waybar-glassmorphism.sh")
PAGEUP_PATH=$(find_tool "double-pageup.sh")
HOTSPOT_PATH=$(find_tool "start_hotspot.sh")

# New Tools
SDDM_PATH=$(find_tool "sddm-screen-config.py")
TASK_SETUP_PATH=$(find_tool "setup-task-manager.sh")
TASK_GUI_PATH=$(find_tool "task-manager-gui.py")
DUNST_PATH=$(find_tool "setup-notifications-theme.py")
OMAR_CMD_PATH=$(find_tool "omar")
ZEN_BROWSER_PATH=$(find_tool "setup-zen-browser-theme.sh")
BOOT_CURSOR_PATH=$(find_tool "setup-initial-cursor-screen.py")
HDMI_AUDIO_PATH=$(find_tool "setup-hdmi-audio.py")

# Launchers
launch_fav_setup() {
    if [ -n "$FAV_PATH" ]; then bash "$FAV_PATH"; else echo -e "${RED}[ERROR] omar-fav-setup.sh not found!${NC}"; fi
}
launch_wordpress_setup() {
    if [ -n "$WP_PATH" ]; then bash "$WP_PATH"; else echo -e "${RED}[ERROR] setup-wordpress-local.sh not found!${NC}"; fi
}
launch_polkit_fix() {
    if [ -n "$POLKIT_PATH" ]; then bash "$POLKIT_PATH"; else echo -e "${RED}[ERROR] fix-polkit-localwp.sh not found!${NC}"; fi
}
launch_nightlight() {
    if [ -n "$NIGHTLIGHT_PATH" ]; then python3 "$NIGHTLIGHT_PATH" & else echo -e "${RED}[ERROR] nightlight-gui.py not found!${NC}"; fi
}
launch_display_settings() {
    if [ -n "$DISPLAY_PATH" ]; then python3 "$DISPLAY_PATH" & else echo -e "${RED}[ERROR] hypr-display-settings.py not found!${NC}"; fi
}
launch_cursor_alignment() {
    if [ -n "$ALIGNMENT_PATH" ]; then bash "$ALIGNMENT_PATH"; else echo -e "${RED}[ERROR] monitor-alignment.sh not found!${NC}"; fi
}
launch_waybar_setup() {
    if [ -n "$WAYBAR_PATH" ]; then bash "$WAYBAR_PATH"; else echo -e "${RED}[ERROR] setup-waybar-glassmorphism.sh not found!${NC}"; fi
}
launch_double_pageup() {
    if [ -n "$PAGEUP_PATH" ]; then bash "$PAGEUP_PATH" & else echo -e "${RED}[ERROR] double-pageup.sh not found!${NC}"; fi
}
launch_hotspot() {
    if [ -n "$HOTSPOT_PATH" ]; then bash "$HOTSPOT_PATH"; else echo -e "${RED}[ERROR] start_hotspot.sh not found!${NC}"; fi
}
launch_sddm_screen() {
    if [ -n "$SDDM_PATH" ]; then python3 "$SDDM_PATH" & else echo -e "${RED}[ERROR] sddm-screen-config.py not found!${NC}"; fi
}
launch_task_setup() {
    if [ -n "$TASK_SETUP_PATH" ]; then
        bash "$TASK_SETUP_PATH"
    elif [ -n "$TASK_GUI_PATH" ]; then
        python3 "$TASK_GUI_PATH" &
    else
        echo -e "${RED}[ERROR] setup-task-manager.sh not found!${NC}"
    fi
}
launch_dunst_theme() {
    if [ -n "$DUNST_PATH" ]; then python3 "$DUNST_PATH" & else echo -e "${RED}[ERROR] setup-notifications-theme.py not found!${NC}"; fi
}
launch_omar_cmd() {
    if [ -n "$OMAR_CMD_PATH" ]; then bash "$OMAR_CMD_PATH"; else echo -e "${RED}[ERROR] 'omar' command not found!${NC}"; fi
}
launch_zen_browser() {
    if [ -n "$ZEN_BROWSER_PATH" ]; then
        bash "$ZEN_BROWSER_PATH"
    else
        echo -e "${RED}[ERROR] setup-zen-browser-theme.sh not found!${NC}"
    fi
}
launch_boot_cursor() {
    if [ -n "$BOOT_CURSOR_PATH" ]; then python3 "$BOOT_CURSOR_PATH" & else echo -e "${RED}[ERROR] setup-initial-cursor-screen.py not found!${NC}"; fi
}

launch_hdmi_audio() {
    if [ -z "$HDMI_AUDIO_PATH" ]; then echo -e "${RED}[ERROR] setup-hdmi-audio.py not found!${NC}"; return; fi
    if [ -t 0 ]; then python3 "$HDMI_AUDIO_PATH"; elif command -v kitty &>/dev/null; then kitty --hold python3 "$HDMI_AUDIO_PATH" & fi
}

# Graphical GUI Rofi / Zenity Launcher
gui_menu() {
    OPTIONS="1. ⭐️ Omar's Favorite Setup (omar-fav-setup)
2. 🌐 Install Local WordPress (LocalWP)
3. 🔐 Fix Polkit Auth for LocalWP
4. 🌙 Night Light GUI
5. 🖥️ Display & Mouse Settings
6. 🎯 Multi-Monitor Alignment
7. 📊 Waybar Glassmorphism Setup
8. ⌨️ Double PageUp Trigger
9. 🔌 Wi-Fi Hotspot Controller
10. 🖥️ SDDM Login Screen Selector
11. 📝 Setup Task Manager & Shell Integrator (setup-task-manager.sh)
12. 🔔 Notification Theme Customizer (Dunst)
13. 🚀 View Command 'omar' System Help
14. 🌐 Zen Browser Glassmorphism Theme (setup-zen-browser-theme.sh)
15. 🎯 Initial Boot Cursor Screen Selector
16. 🔊 HDMI / DisplayPort Audio Output"

    if command -v rofi &>/dev/null; then
        SELECTION=$(echo -e "$OPTIONS" | rofi -dmenu -i -p "CachyOS Control Panel:")
    elif command -v zenity &>/dev/null; then
        SELECTION=$(zenity --list \
            --title="CachyOS Control Panel & System Tools" \
            --text="Choose a tool to launch:" \
            --column="Available Utilities" \
            "1. ⭐️ Omar's Favorite Setup" \
            "2. 🌐 Install Local WordPress" \
            "3. 🔐 Fix Polkit Auth for LocalWP" \
            "4. 🌙 Night Light GUI" \
            "5. 🖥️ Display & Mouse Settings" \
            "6. 🎯 Multi-Monitor Alignment" \
            "7. 📊 Waybar Glassmorphism Setup" \
            "8. ⌨️ Double PageUp Trigger" \
            "9. 🔌 Wi-Fi Hotspot Controller" \
            "10. 🖥️ SDDM Login Screen Selector" \
            "11. 📝 Setup Task Manager & Shell Integrator" \
            "12. 🔔 Notification Theme Customizer" \
            "13. 🚀 View Command 'omar' System Help" \
            "14. 🌐 Zen Browser Glassmorphism Theme" \
            "15. 🎯 Initial Boot Cursor Screen Selector" \
            "16. 🔊 HDMI / DisplayPort Audio Output" \
            --width=540 --height=620 2>/dev/null)
    else
        cli_menu
        return
    fi

    case "$SELECTION" in
        *"Omar's Favorite"*) launch_fav_setup ;;
        *"Local WordPress"*) launch_wordpress_setup ;;
        *"Fix Polkit"*) launch_polkit_fix ;;
        *"Night Light"*) launch_nightlight ;;
        *"Display & Mouse"*) launch_display_settings ;;
        *"Monitor Alignment"*) launch_cursor_alignment ;;
        *"Waybar Glassmorphism"*) launch_waybar_setup ;;
        *"Double PageUp"*) launch_double_pageup ;;
        *"Hotspot"*) launch_hotspot ;;
        *"SDDM Login Screen Selector"*) launch_sddm_screen ;;
        *"Setup Task Manager"*) launch_task_setup ;;
        *"Notification Theme"*) launch_dunst_theme ;;
        *"Command 'omar'"*) launch_omar_cmd ;;
        *"Zen Browser Glassmorphism"*) launch_zen_browser ;;
        *"Boot Cursor Screen"*) launch_boot_cursor ;;
        *"Audio Output"*) launch_hdmi_audio ;;
        *) exit 0 ;;
    esac
}

# Terminal CLI Menu
cli_menu() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}"
        cat << "EOF"
  ==============================================================
         CachyOS + Hyprland Unified Tools Launcher Menu
  ==============================================================
EOF
        echo -e "${NC}"
        echo -e "  ${MAGENTA}${BOLD}1)${NC} ⭐️ Omar's Favorite Setup (${YELLOW}omar-fav-setup.sh${NC})"
        echo -e "  ${MAGENTA}${BOLD}2)${NC} 🌐 Install Local WordPress (${YELLOW}setup-wordpress-local.sh${NC})"
        echo -e "  ${MAGENTA}${BOLD}3)${NC} 🔐 Fix Polkit Auth for LocalWP (${YELLOW}fix-polkit-localwp.sh${NC})"
        echo -e "  ${MAGENTA}${BOLD}4)${NC} 🌙 Launch Night Light GUI (${YELLOW}nightlight-gui.py${NC})"
        echo -e "  ${MAGENTA}${BOLD}5)${NC} 🖥️ Launch Display & Mouse Settings (${YELLOW}hypr-display-settings.py${NC})"
        echo -e "  ${MAGENTA}${BOLD}6)${NC} 🎯 Multi-Monitor Alignment (${YELLOW}monitor-alignment.sh${NC})"
        echo -e "  ${MAGENTA}${BOLD}7)${NC} 📊 Launch Waybar Glassmorphism Setup (${YELLOW}setup-waybar-glassmorphism.sh${NC})"
        echo -e "  ${MAGENTA}${BOLD}8)${NC} ⌨️ Double PageUp Listener Trigger (${YELLOW}double-pageup.sh${NC})"
        echo -e "  ${MAGENTA}${BOLD}9)${NC} 🔌 Wi-Fi Hotspot Controller (${YELLOW}start_hotspot.sh${NC})"
        echo -e "  ${CYAN}--------------------------------------------------------------${NC}"
        echo -e "  ${GREEN}${BOLD}10)${NC} 🖥️ SDDM Login Screen Selector (${YELLOW}sddm-screen-config.py${NC})"
        echo -e "  ${GREEN}${BOLD}11)${NC} 📝 Setup Task Manager & Shell Integrator (${YELLOW}setup-task-manager.sh${NC})"
        echo -e "  ${GREEN}${BOLD}12)${NC} 🔔 Notification Theme Customizer (${YELLOW}setup-notifications-theme.py${NC})"
        echo -e "  ${GREEN}${BOLD}13)${NC} 🚀 View Command 'omar' System Help (${YELLOW}omar${NC})"
        echo -e "  ${GREEN}${BOLD}14)${NC} 🌐 Zen Browser Glassmorphism Theme (${YELLOW}setup-zen-browser-theme.sh${NC})"
        echo -e "  ${GREEN}${BOLD}15)${NC} 🎯 Initial Boot Cursor Screen Selector (${YELLOW}setup-initial-cursor-screen.py${NC})"
        echo -e "  ${GREEN}${BOLD}16)${NC} 🔊 HDMI / DisplayPort Audio Output (${YELLOW}setup-hdmi-audio.py${NC})"
        echo -e "  ${RED}${BOLD}17)${NC} 🚪 Exit"
        echo -e "${CYAN}--------------------------------------------------------------${NC}"
        read -p " Select choice [1-17]: " choice

        case "$choice" in
            1) launch_fav_setup; read -p "Press Enter to continue..." ;;
            2) launch_wordpress_setup; read -p "Press Enter to continue..." ;;
            3) launch_polkit_fix; read -p "Press Enter to continue..." ;;
            4) launch_nightlight; read -p "Press Enter to continue..." ;;
            5) launch_display_settings; read -p "Press Enter to continue..." ;;
            6) launch_cursor_alignment; read -p "Press Enter to continue..." ;;
            7) launch_waybar_setup; read -p "Press Enter to continue..." ;;
            8) launch_double_pageup; read -p "Press Enter to continue..." ;;
            9) launch_hotspot; read -p "Press Enter to continue..." ;;
            10) launch_sddm_screen; read -p "Press Enter to continue..." ;;
            11) launch_task_setup; read -p "Press Enter to continue..." ;;
            12) launch_dunst_theme; read -p "Press Enter to continue..." ;;
            13) launch_omar_cmd; read -p "Press Enter to continue..." ;;
            14) launch_zen_browser; read -p "Press Enter to continue..." ;;
            15) launch_boot_cursor; read -p "Press Enter to continue..." ;;
            16) launch_hdmi_audio; read -p "Press Enter to continue..." ;;
            17|q|Q) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
            *) echo -e "${RED}[!] Invalid choice.${NC}"; sleep 1 ;;
        esac
    done
}

# Check argument for --gui or auto-detect
if [ "$1" == "--gui" ] || [ ! -t 0 ]; then
    gui_menu
else
    cli_menu
fi
