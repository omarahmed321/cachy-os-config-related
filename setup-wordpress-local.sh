#!/usr/bin/env bash
#===============================================================================
#   WordPress Local Development Setup Script (LocalWP & Tools)
#   Part of: CachyOS + HyDE System Restorer
#   Repo:    https://github.com/omarahmed321/cachy-os-config-related
#===============================================================================

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
cat << "EOF"
  ==============================================================
       Local WordPress Development Installer & Setup
  ==============================================================
EOF
echo -e "${NC}"

# Fix pacman DB lock if present
if [ -f "/var/lib/pacman/db.lck" ]; then
    echo -e "${YELLOW}[!] Pacman database is locked. Checking...${NC}"
    if ! pgrep -x "pacman" >/dev/null && ! pgrep -x "yay" >/dev/null && ! pgrep -x "paru" >/dev/null; then
        sudo rm -f /var/lib/pacman/db.lck 2>/dev/null || true
    fi
fi

# Locate AUR Helper
AUR_HELPER=""
if command -v yay &>/dev/null; then
    AUR_HELPER="yay"
elif command -v paru &>/dev/null; then
    AUR_HELPER="paru"
fi

if [ -z "$AUR_HELPER" ]; then
    echo -e "${RED}[!] Error: Neither yay nor paru found. Please install yay first.${NC}"
    exit 1
fi

echo -e "${CYAN}[1/2] Installing LocalWP (#1 Local WordPress GUI Tool) from AUR...${NC}"

if command -v localwp &>/dev/null || [ -f "/opt/Local/local" ] || [ -f "/usr/bin/localwp" ]; then
    echo -e "${GREEN}[OK] LocalWP is already installed on your system!${NC}"
else
    echo -e "${CYAN}[*] Running $AUR_HELPER -S localwp...${NC}"
    $AUR_HELPER -S --noconfirm --needed localwp || $AUR_HELPER -S --noconfirm --needed wordpress-studio-git || {
        echo -e "${YELLOW}[!] Fallback: Installing docker & wp-cli for local WordPress...${NC}"
        sudo pacman -S --noconfirm --needed docker docker-compose wp-cli
        sudo systemctl enable --now docker 2>/dev/null || true
        sudo usermod -aG docker "$USER" 2>/dev/null || true
    }
fi

echo -e "\n${CYAN}[2/2] Verifying LocalWP installation...${NC}"
if command -v localwp &>/dev/null || [ -f "/opt/Local/local" ] || [ -f "/usr/bin/localwp" ]; then
    echo -e "${GREEN}${BOLD}[OK] LocalWP installed successfully!${NC}"
    echo -e "${CYAN}[*] You can launch it anytime from your App Launcher (Rofi/Wofi) or run: localwp${NC}"
    
    # Copy script to user bin for quick access
    mkdir -p "$HOME/.local/share/bin"
    cp "$0" "$HOME/.local/share/bin/setup-wordpress-local.sh" 2>/dev/null || true
    chmod +x "$HOME/.local/share/bin/setup-wordpress-local.sh" 2>/dev/null || true
else
    echo -e "${YELLOW}[*] Setup process finished.${NC}"
fi

echo -e "\n${GREEN}${BOLD}[OK] Local WordPress Environment Setup Completed!${NC}\n"
