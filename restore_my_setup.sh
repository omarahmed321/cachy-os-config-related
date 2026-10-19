#!/usr/bin/env bash
#===============================================================================
#   CachyOS + HyDE (Hyprdots) Complete System Replicator & Restorer
#   Target System: CachyOS + Hyprland
#   Created by Antigravity AI Pair Programmer
#===============================================================================

# Color definitions for gorgeous feedback
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -z "$SCRIPT_DIR" ] || [ "$SCRIPT_DIR" = "/bin" ]; then
    SCRIPT_DIR="$HOME/cachy-os-config-related"
fi

# Header block
echo -e "${CYAN}${BOLD}"
cat << "EOF"
  ==============================================================
   CachyOS + Hyprland Setup Cloner & Complete System Restorer
  ==============================================================
EOF
echo -e "${NC}"

# Self-healing helper: check and fix pacman database lock
fix_pacman_lock() {
    if [ -f "/var/lib/pacman/db.lck" ]; then
        echo -e "${YELLOW}[!] Pacman database is locked. Attempting self-healing...${NC}"
        # Check if any pacman/yay/paru process is actually running
        if ! pgrep -x "pacman" >/dev/null && ! pgrep -x "yay" >/dev/null && ! pgrep -x "paru" >/dev/null; then
            echo -e "${GREEN}[+] Removing stale lock file /var/lib/pacman/db.lck...${NC}"
            sudo rm -f /var/lib/pacman/db.lck
        else
            echo -e "${YELLOW}[*] Waiting for other package manager process to finish...${NC}"
            while pgrep -x "pacman" >/dev/null || pgrep -x "yay" >/dev/null || pgrep -x "paru" >/dev/null; do
                sleep 2
            done
            sudo rm -f /var/lib/pacman/db.lck 2>/dev/null || true
        fi
    fi
}

# Self-healing helper: verify and start systemd services with auto-recovery fallbacks
verify_and_start_service() {
    local service_name="$1"
    echo -e "${CYAN}[*] Enabling and starting service: $service_name...${NC}"
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl reset-failed "$service_name" 2>/dev/null || true
    if sudo systemctl enable --now "$service_name" 2>/dev/null; then
        echo -e "  - ${GREEN}[Active]${NC} $service_name service started successfully."
    else
        echo -e "${RED}[!] Failed to enable $service_name. Retrying with explicit restart...${NC}"
        if sudo systemctl restart "$service_name" 2>/dev/null; then
            echo -e "  - ${GREEN}[Active]${NC} $service_name service started after retry."
        else
            echo -e "${RED}[WARNING] Service $service_name failed to start. Running self-diagnostic...${NC}"
            # Check journalctl for hints or print warning
            sudo journalctl -u "$service_name" -n 5 --no-pager 2>/dev/null || true
        fi
    fi
}

# Ensure script is NOT run directly as root, but can elevate when needed
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}${BOLD}[ERROR] Please do NOT run this script as root directly. Use your normal user account. It will ask for sudo when required.${NC}"
    exit 1
fi

# Detect CachyOS/Arch base
if [ ! -f /etc/arch-release ]; then
    echo -e "${YELLOW}[WARNING] This script is designed for Arch Linux / CachyOS. Proceed with caution on other distributions!${NC}"
    read -p " :: Press Enter to continue anyway, or Ctrl+C to abort..."
fi

# Detect other Desktop Environments
if [ -n "$XDG_CURRENT_DESKTOP" ] && [ "$XDG_CURRENT_DESKTOP" != "Hyprland" ]; then
    echo -e "${YELLOW}[WARNING] You are currently running the '$XDG_CURRENT_DESKTOP' desktop environment.${NC}"
    read -p "Wanna start the setup? (This setup will change your desktop environment to Hyprland + HyDE) (y/n): " confirm_setup
    if [[ ! "$confirm_setup" =~ ^[Yy]$ ]]; then
        echo -e "${RED}[INFO] Installation aborted by user.${NC}"
        exit 0
    fi
fi

# --- INTERACTIVE USER PREFERENCES & CONFIRMATIONS ---
echo -e "\n${BLUE}${BOLD}==============================================================${NC}"
echo -e "${BLUE}${BOLD}           CachyOS + Hyprland Installation Manager            ${NC}"
echo -e "${BLUE}${BOLD}==============================================================${NC}"

# 1. Confirm overall installation
read -p "Do you want to run the full system restoration setup? (y/n) [y]: " main_confirm
main_confirm="${main_confirm:-y}"
if [[ ! "$main_confirm" =~ ^[Yy]$ ]]; then
    echo -e "${RED}[INFO] Setup aborted by user.${NC}"
    exit 0
fi

# 2. Package installation preference
read -p "Do you want to install/upgrade required system packages? (y/n) [y]: " opt_install_pkgs
opt_install_pkgs="${opt_install_pkgs:-y}"

# 3. HyDE Desktop Environment framework deployment preference
read -p "Do you want to deploy/upgrade the HyDE Desktop Environment framework? (y/n) [y]: " opt_deploy_hyde
opt_deploy_hyde="${opt_deploy_hyde:-y}"

# 4. Desktop Custom Dotfiles deployment preference
read -p "Do you want to write/overwrite customized dotfiles (Hyprland, Waybar, Zsh, Kitty, Cava, VS Code, Zen)? (y/n) [y]: " opt_deploy_dots
opt_deploy_dots="${opt_deploy_dots:-y}"

# 5. Helper scripts (hotspot, nightlight, etc.) installation preference
read -p "Do you want to write/overwrite custom helper scripts (starthotspot.sh, nightlight-gui, display settings)? (y/n) [y]: " opt_helper_scripts
opt_helper_scripts="${opt_helper_scripts:-y}"

# 1. Detect/Install AUR Helper (yay/paru)
echo -e "\n${BLUE}${BOLD}[1/5] Checking for AUR helper (yay/paru)...${NC}"
AUR_HELPER=""
if command -v yay &>/dev/null; then
    AUR_HELPER="yay"
    echo -e "${GREEN}[OK] Found yay as AUR helper.${NC}"
elif command -v paru &>/dev/null; then
    AUR_HELPER="paru"
    echo -e "${GREEN}[OK] Found paru as AUR helper.${NC}"
else
    echo -e "${YELLOW}[INFO] No AUR helper found. Installing yay...${NC}"
    fix_pacman_lock
    sudo pacman -S --needed --noconfirm base-devel git
    git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
    cd /tmp/yay-bin || exit
    makepkg -si --noconfirm
    cd - || exit
    AUR_HELPER="yay"
    echo -e "${GREEN}[OK] Successfully installed yay.${NC}"
fi

if [[ "$opt_install_pkgs" =~ ^[Yy]$ ]]; then
# Synchronize package databases to prevent 404 download errors
echo -e "\n${BLUE}${BOLD}[1.5/5] Synchronizing package databases...${NC}"
fix_pacman_lock
sudo pacman -Sy

# Update Arch Linux and CachyOS keyrings first to prevent signature verification errors
echo -e "${CYAN}Updating package keyrings to prevent signature errors...${NC}"
fix_pacman_lock
sudo pacman -S --needed --noconfirm archlinux-keyring 2>/dev/null || true
if pacman -Si cachyos-keyring &>/dev/null; then
    sudo pacman -S --needed --noconfirm cachyos-keyring 2>/dev/null || true
fi

# Ensure git and zsh are installed
echo -e "\n${BLUE}${BOLD}[2/5] Ensuring Core packages (git, zsh) are installed...${NC}"

if ! pacman -Qi git &>/dev/null || ! pacman -Qi zsh &>/dev/null; then
    fix_pacman_lock
    sudo pacman -S --needed --noconfirm git zsh
else
    echo -e "${GREEN}[OK] Core packages (git, zsh) are already installed.${NC}"
fi

# Ensure kernel headers matching the running kernel are installed (critical for DKMS driver compilation)
echo -e "\n${BLUE}${BOLD}[2.5/5] Detecting and installing matching kernel headers...${NC}"
KERNEL_NAME=$(uname -r)
HEADERS_PKG=""

if [[ "$KERNEL_NAME" == *"-cachyos"* ]]; then
    if [[ "$KERNEL_NAME" == *"-lts"* ]]; then
        HEADERS_PKG="linux-cachyos-lts-headers"
    elif [[ "$KERNEL_NAME" == *"-rc"* ]]; then
        HEADERS_PKG="linux-cachyos-rc-headers"
    elif [[ "$KERNEL_NAME" == *"-server"* ]]; then
        HEADERS_PKG="linux-cachyos-server-headers"
    elif [[ "$KERNEL_NAME" == *"-hardened"* ]]; then
        HEADERS_PKG="linux-cachyos-hardened-headers"
    else
        HEADERS_PKG="linux-cachyos-headers"
    fi
elif [[ "$KERNEL_NAME" == *"-lts"* ]]; then
    HEADERS_PKG="linux-lts-headers"
elif [[ "$KERNEL_NAME" == *"-zen"* ]]; then
    HEADERS_PKG="linux-zen-headers"
elif [[ "$KERNEL_NAME" == *"-hardened"* ]]; then
    HEADERS_PKG="linux-hardened-headers"
elif [[ "$KERNEL_NAME" == *"-rt"* ]]; then
    HEADERS_PKG="linux-rt-headers"
else
    HEADERS_PKG="linux-headers"
fi

echo -e "Running kernel: ${CYAN}$KERNEL_NAME${NC}, selected headers package: ${CYAN}$HEADERS_PKG${NC}"
if ! pacman -Qi "$HEADERS_PKG" &>/dev/null; then
    echo -e "Installing ${YELLOW}$HEADERS_PKG${NC}..."
    fix_pacman_lock
    sudo pacman -S --needed --noconfirm "$HEADERS_PKG"
    echo -e "${GREEN}[OK] Installed kernel headers successfully.${NC}"
else
    echo -e "${GREEN}[OK] Kernel headers ($HEADERS_PKG) are already installed.${NC}"
fi

# 2. Check and Install Required Packages
echo -e "\n${BLUE}${BOLD}[3/5] Checking and installing required packages...${NC}"
# Detect GPU Vendor dynamically with interactive override option
GPU_VENDOR="unknown"
AUTO_GPU="unknown"
gpu_info=$(lspci | grep -Ei "vga|3d")
if echo "$gpu_info" | grep -iq "nvidia"; then
    AUTO_GPU="nvidia"
elif echo "$gpu_info" | grep -iq "amd"; then
    AUTO_GPU="amd"
elif echo "$gpu_info" | grep -iq "intel"; then
    AUTO_GPU="intel"
fi

echo -e "\nAutomatically detected GPU Vendor: ${CYAN}${AUTO_GPU}${NC}"
echo -e "Which graphics driver configuration would you like to use?"
echo -e "1) Automatically detected (${AUTO_GPU})"
echo -e "2) Nvidia proprietary drivers"
echo -e "3) AMD open-source drivers"
echo -e "4) Intel open-source drivers"
echo -e "5) Skip GPU-specific drivers"
read -p "Select choice [1-5] (Default 1): " gpu_choice
gpu_choice="${gpu_choice:-1}"

GPU_VENDOR="$AUTO_GPU"
if [ "$gpu_choice" = "2" ]; then
    GPU_VENDOR="nvidia"
elif [ "$gpu_choice" = "3" ]; then
    GPU_VENDOR="amd"
elif [ "$gpu_choice" = "4" ]; then
    GPU_VENDOR="intel"
elif [ "$gpu_choice" = "5" ]; then
    GPU_VENDOR="skip"
fi
echo -e "Using GPU driver configuration for: ${CYAN}${GPU_VENDOR}${NC}"

REQUIRED_PACKAGES=(
    hyprland waybar dunst rofi-wayland kitty firefox zen-browser-bin code dolphin yazi sddm-astronaut-theme
    swaylock-effects-git wlogout cliphist hyprpicker hyprsunset hyprlock
    grimblast-git slurp jq polkit-kde-agent eza awesome-terminal-fonts
    ttf-meslo-nerd ttf-jetbrains-mono-nerd blueman bluez bluez-utils
    network-manager-applet brightnessctl pamixer playerctl udiskie
    nwg-look kvantum kvantum-qt5 qt5ct qt6ct qt5-wayland qt6-wayland qt6-5compat qt6-virtualkeyboard qt6-multimedia
    awww parallel pacman-contrib imagemagick ffmpegthumbs kde-cli-tools
    bc 8188eu-dkms-git antigravity antigravity-ide antigravity-cli prismlauncher cava tk python-gobject libadwaita
    wtype gnome-keyring ttf-cascadia-code-nerd python-pywal
    oh-my-zsh-git zsh-theme-powerlevel10k zsh-autosuggestions
    zsh-syntax-highlighting zsh-completions
    wl-clipboard qt5-graphicaleffects qt5-quickcontrols qt5-quickcontrols2
    seahorse networkmanager zenity fastfetch bibata-cursor-theme-bin fzf cachyos-fish-config
    psmisc python dnsmasq hostapd iw sddm ananicy-cpp gammastep
)

# Dynamically add GPU drivers based on detected hardware
if [ "$GPU_VENDOR" = "nvidia" ]; then
    echo -e "${CYAN}Adding Nvidia proprietary drivers and Wayland support packages...${NC}"
    REQUIRED_PACKAGES+=(nvidia-dkms nvidia-utils lib32-nvidia-utils egl-wayland libva-nvidia-driver)
elif [ "$GPU_VENDOR" = "amd" ]; then
    echo -e "${CYAN}Adding AMD open-source graphics and Vulkan driver packages...${NC}"
    REQUIRED_PACKAGES+=(mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon libva-mesa-driver lib32-libva-mesa-driver)
elif [ "$GPU_VENDOR" = "intel" ]; then
    echo -e "${CYAN}Adding Intel open-source graphics and Vulkan driver packages...${NC}"
    REQUIRED_PACKAGES+=(mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver)
fi

# Install packages
echo -e "${CYAN}Checking ${#REQUIRED_PACKAGES[@]} essential packages...${NC}"
TO_INSTALL=()
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if [ "$pkg" = "8188eu-dkms-git" ]; then
        if pacman -Qq | grep -qE '^8188eu-' &>/dev/null; then
            INSTALLED_8188EU_PKG=$(pacman -Qq | grep -E '^8188eu-' | head -n 1)
            echo -e "  - ${GREEN}[Installed]${NC} 8188eu-dkms (provided by $INSTALLED_8188EU_PKG)"
            continue
        fi
    fi
    if pacman -Qi "$pkg" &>/dev/null; then
        echo -e "  - ${GREEN}[Installed]${NC} $pkg"
    else
        echo -e "  - ${YELLOW}[Missing]${NC} $pkg (queued)"
        TO_INSTALL+=("$pkg")
    fi
done

if [ ${#TO_INSTALL[@]} -gt 0 ]; then
    echo -e "${YELLOW}\nInstalling missing packages using $AUR_HELPER...${NC}"
    fix_pacman_lock
    if ! $AUR_HELPER -S --noconfirm "${TO_INSTALL[@]}"; then
        echo -e "${YELLOW}[WARNING] Batch installation failed. Falling back to installing packages individually to ensure maximum coverage...${NC}"
        FAILED_PACKAGES=()
        for pkg in "${TO_INSTALL[@]}"; do
            echo -e "${CYAN}Installing $pkg...${NC}"
            fix_pacman_lock
            if ! $AUR_HELPER -S --noconfirm "$pkg"; then
                echo -e "${RED}[ERROR] Failed to install $pkg${NC}"
                FAILED_PACKAGES+=("$pkg")
            fi
        done
        
        if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
            echo -e "${YELLOW}[WARNING] The following packages failed to install: ${FAILED_PACKAGES[*]}${NC}"
            echo -e "${YELLOW}The setup will proceed with the remaining components.${NC}"
        else
            echo -e "${GREEN}[OK] All packages installed successfully after fallback!${NC}"
        fi
    else
        echo -e "${GREEN}[OK] All packages installed successfully!${NC}"
    fi
else
    echo -e "${GREEN}[OK] All required packages are already installed.${NC}"
fi

# Enable system services
echo -e "\n${BLUE}${BOLD}[4/5] Enabling and starting system services (bluetooth, NetworkManager, sddm, ananicy-cpp)...${NC}"
for svc in bluetooth NetworkManager sddm ananicy-cpp; do
    verify_and_start_service "$svc"
done
fi



if [[ "$opt_helper_scripts" =~ ^[Yy]$ ]]; then
# --- CONFIGURE NETWORKMANAGER TO MANAGE WLAN0 (Required for native Hotspot) ---
if [ -f /etc/NetworkManager/NetworkManager.conf ]; then
    if grep -q "unmanaged-devices=interface-name:wlan0" /etc/NetworkManager/NetworkManager.conf; then
        echo -e "${CYAN}Removing wlan0 block from NetworkManager.conf to allow native Hotspot...${NC}"
        sudo sed -i 's/unmanaged-devices=interface-name:wlan0/# unmanaged-devices=interface-name:wlan0/' /etc/NetworkManager/NetworkManager.conf
        if systemctl is-active --quiet NetworkManager; then
            sudo systemctl restart NetworkManager
        fi
    fi
fi
fi

if [[ "$opt_deploy_hyde" =~ ^[Yy]$ ]]; then
# 3. Clone and Run HyDE (Hyprdots) Installer
echo -e "\n${BLUE}${BOLD}[5/5] Deploying HyDE Desktop Environment Framework...${NC}"
if [ -d "$HOME/hyde" ]; then
    echo -e "${GREEN}[OK] HyDE directory already exists at $HOME/hyde.${NC}"
else
    echo -e "${CYAN}Cloning prasanthrangan/hyprdots repository to $HOME/hyde...${NC}"
    git clone https://github.com/prasanthrangan/hyprdots.git "$HOME/hyde"
    echo -e "${GREEN}[OK] Successfully cloned HyDE repository.${NC}"
fi

# Run the HyDE installer in default/non-interactive mode
echo -e "${CYAN}Running the HyDE installer...${NC}"
echo -e "${YELLOW}Note: Automating inputs for installer prompts (Grub theme, SDDM theme, and Flatpaks)...${NC}"
cd "$HOME/hyde/Scripts" || exit

# Run install.sh with pre-seeded inputs to skip/default prompt timers
# Enter/Skip Grub theme, Enter/Skip SDDM theme, and Answer 'n' to Flatpak apps
export aurhlpr="$AUR_HELPER"
export myShell="zsh"
echo -e "\n\n\nn" | ./install.sh

echo -e "${GREEN}[OK] HyDE base configuration installed successfully!${NC}"

# Ensure swww/swww-daemon compatibility symlinks exist if awww is installed instead
if command -v awww &>/dev/null && ! command -v swww &>/dev/null; then
    echo -e "${BLUE}[INFO] Creating swww compatibility symlinks for awww...${NC}"
    mkdir -p "$HOME/.local/bin"
    ln -sf /usr/bin/awww "$HOME/.local/bin/swww"
    ln -sf /usr/bin/awww-daemon "$HOME/.local/bin/swww-daemon"
    mkdir -p "$HOME/.local/share/bin"
    ln -sf /usr/bin/awww "$HOME/.local/share/bin/swww"
    ln -sf /usr/bin/awww-daemon "$HOME/.local/share/bin/swww-daemon"
fi
fi

if [[ "$opt_deploy_dots" =~ ^[Yy]$ ]]; then
# 4. Deploy EXACT Customized Dotfiles
echo -e "\n${MAGENTA}${BOLD}==============================================================${NC}"
echo -e "${MAGENTA}${BOLD}   Deploying Custom System Settings, Keybinds, & Fonts...    ${NC}"
echo -e "${MAGENTA}${BOLD}==============================================================${NC}"

# Create required config directories
mkdir -p "$HOME/.config/hypr/themes"
mkdir -p "$HOME/.config/kitty"
mkdir -p "$HOME/.config/waybar"
mkdir -p "$HOME/.config/hyde"
mkdir -p "$HOME/.config/cava"

# Move default CachyOS Hyprland Lua config out of the way if it exists,
# so Hyprland falls back to the legacy hyprland.conf/hyprdots format.
if [ -f "$HOME/.config/hypr/hyprland.lua" ]; then
    echo -e "${YELLOW}[INFO] Found default CachyOS hyprland.lua. Moving it to hyprland.lua.bak to allow hyprland.conf to load...${NC}"
    mv "$HOME/.config/hypr/hyprland.lua" "$HOME/.config/hypr/hyprland.lua.bak"
fi

# Deploy custom Arabic keyboard layout
echo -e "${CYAN}Writing custom Arabic layout to /usr/share/X11/xkb/symbols/ara...${NC}"
sudo bash -c 'if ! grep -q "xkb_symbols \"thal_bksl\"" /usr/share/X11/xkb/symbols/ara; then tee -a /usr/share/X11/xkb/symbols/ara >/dev/null << "XKBEOF"

// Custom Arabic layout variant with ذ (Arabic_thal) on the backslash key
partial alphanumeric_keys
xkb_symbols "thal_bksl" {
    include "ara(basic)"

    name[Group1]= "Arabic (Thal on backslash)";

    // Put ذ on the backslash key, with \ on AltGr
    key <BKSL> {[     Arabic_thal,        Arabic_shadda,           backslash,             bar ]};
};
XKBEOF
fi'
fi

if [[ "$opt_helper_scripts" =~ ^[Yy]$ ]]; then
# --- WRITE ~/.local/bin/double-pageup.sh ---
echo -e "${CYAN}Writing ~/.local/bin/double-pageup.sh...${NC}"
mkdir -p "$HOME/.local/bin"
cat << 'DPEOF' > "$HOME/.local/bin/double-pageup.sh"
#!/bin/bash
LAST_FILE="/tmp/.pageup_last"
NOW=$(date +%s%N)

if [ -f "$LAST_FILE" ]; then
    LAST=$(cat "$LAST_FILE")
    DIFF=$(( (NOW - LAST) / 1000000 ))
    if [ "$DIFF" -lt 500 ]; then
        rm -f "$LAST_FILE"
        wtype -M ctrl -k grave
        exit 0
    fi
fi

echo "$NOW" > "$LAST_FILE"
sleep 0.6
[ -f "$LAST_FILE" ] && rm -f "$LAST_FILE"
DPEOF
chmod +x "$HOME/.local/bin/double-pageup.sh"

# --- WRITE ~/start_hotspot.sh ---
echo -e "${CYAN}Writing ~/start_hotspot.sh...${NC}"
cat << 'HOTEOF' > "$HOME/start_hotspot.sh"
#!/usr/bin/env bash
#===============================================================================
#   Universal Native Wi-Fi Hotspot Controller
#   Uses native NetworkManager (nmcli) for absolute stability & zero dependencies
#   Fallback to create_ap / linux-wifi-hotspot if NetworkManager is inactive
#===============================================================================

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Root Check & Auto-Sudo ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}[!] This script needs root privileges. Rerunning with sudo...${NC}"
    exec sudo "$0" "$@"
fi

# --- Dynamic Interface Detection (Self-Healing / Device Independent) ---
echo -e "${CYAN}[*] Auto-detecting network interfaces...${NC}"

# Detect Wi-Fi interface
WIFI_INT=$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}' | head -n 1)
if [ -z "$WIFI_INT" ]; then
    # Fallback 1: ip link pattern
    WIFI_INT=$(ip -o link show | awk -F': ' '$2 ~ /^w/ {print $2}' | head -n 1)
fi

# Detect active internet interface (used for fallback routing)
INTERNET_INT=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -n 1)
if [ -z "$INTERNET_INT" ]; then
    # Fallback to first ethernet interface if no default route
    INTERNET_INT=$(ip -o link show | awk -F': ' '$2 ~ /^e/ {print $2}' | head -n 1)
fi

if [ -z "$WIFI_INT" ]; then
    echo -e "${RED}[ERROR] No Wi-Fi interface detected on this machine!${NC}"
    echo -e "${YELLOW}Available interfaces on this system:${NC}"
    ip -o link show | awk -F': ' '{print " - " $2}'
    exit 1
fi

echo -e "Detected Wi-Fi:      ${GREEN}${WIFI_INT}${NC}"
echo -e "Detected Internet:    ${GREEN}${INTERNET_INT:-None}${NC}"

# --- Load / Save Configuration ---
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME="$HOME"
fi
CONFIG_DIR="${USER_HOME}/.config"
CONFIG_FILE="${CONFIG_DIR}/hotspot_config"

DEFAULT_SSID="tplink-7825"
DEFAULT_PASS="bolbol123*#"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE" 2>/dev/null
fi

SSID="${SAVED_SSID:-$DEFAULT_SSID}"
PASSPHRASE="${SAVED_PASS:-$DEFAULT_PASS}"

# --- Setup Dialog ---
echo -e "\n${CYAN}${BOLD}====================================================${NC}"
echo -e "${MAGENTA}${BOLD}         Native Wi-Fi Hotspot Controller            ${NC}"
echo -e "${CYAN}${BOLD}====================================================${NC}"
echo -e "Saved Default: SSID: ${YELLOW}${SSID}${NC} | Password: ${YELLOW}${PASSPHRASE}${NC}"
echo -e "1) Start with default settings"
echo -e "2) Configure new SSID and Password"
read -p "Choose option [1-2] (Default 1): " choice
choice="${choice:-1}"

if [ "$choice" = "2" ]; then
    read -p "Enter new SSID (Press Enter for default '$SSID'): " new_ssid
    SSID="${new_ssid:-$SSID}"
    while true; do
        read -p "Enter new Password (min 8 chars, Press Enter for default): " new_pass
        new_pass="${new_pass:-$PASSPHRASE}"
        if [ ${#new_pass} -lt 8 ]; then
            echo -e "${RED}[!] Password must be at least 8 characters long.${NC}"
        else
            PASSPHRASE="$new_pass"
            break
        fi
    done

    read -p "Save this configuration as default? (y/n) [y]: " save_choice
    save_choice="${save_choice:-y}"
    if [[ "$save_choice" =~ ^[Yy]$ ]]; then
        mkdir -p "$CONFIG_DIR"
        printf 'SAVED_SSID=%q\nSAVED_PASS=%q\n' "$SSID" "$PASSPHRASE" > "$CONFIG_FILE"
        if [ -n "$SUDO_USER" ]; then
            chown "$SUDO_USER:" "$CONFIG_DIR" "$CONFIG_FILE" 2>/dev/null || true
        fi
        echo -e "${GREEN}[+] Configuration saved!${NC}"
        sleep 1
    fi
fi

# --- Display QR Code ---
clear
echo -e "${CYAN}${BOLD}====================================================${NC}"
echo -e "${MAGENTA}${BOLD}             Hotspot Active Connection              ${NC}"
echo -e "${CYAN}${BOLD}====================================================${NC}"
echo -e "SSID:       ${GREEN}${SSID}${NC}"
echo -e "Password:   ${GREEN}${PASSPHRASE}${NC}"
echo -e "Interface:  ${GREEN}${WIFI_INT}${NC}"
echo -e "${CYAN}----------------------------------------------------${NC}"

if command -v qrencode &>/dev/null; then
    echo -e "${GREEN}[+] Scan this QR Code to connect instantly:${NC}"
    qrencode -t utf8 "WIFI:S:${SSID};T:WPA;P:${PASSPHRASE};;"
    echo -e "${CYAN}----------------------------------------------------${NC}"
else
    # Automatically install qrencode if missing
    if command -v pacman &>/dev/null; then
        echo -e "${YELLOW}[*] Installing qrencode for QR code display...${NC}"
        pacman -S --needed --noconfirm qrencode &>/dev/null && {
            echo -e "${GREEN}[+] Scan this QR Code to connect instantly:${NC}"
            qrencode -t utf8 "WIFI:S:${SSID};T:WPA;P:${PASSPHRASE};;"
            echo -e "${CYAN}----------------------------------------------------${NC}"
        }
    fi
fi

# --- Cleanup Trap ---
cleanup() {
    echo -e "\n${YELLOW}[*] Shutting down hotspot and restoring interface...${NC}"
    if systemctl is-active NetworkManager &>/dev/null; then
        nmcli connection down Hotspot 2>/dev/null || true
        nmcli connection delete Hotspot 2>/dev/null || true
        nmcli device disconnect "$WIFI_INT" 2>/dev/null || true
    else
        killall -9 hostapd dnsmasq create_ap haveged 2>/dev/null || true
    fi
    # Re-enable Wi-Fi Power Saving for power efficiency
    iw dev "$WIFI_INT" set power_save on 2>/dev/null || true
    echo -e "${GREEN}[+] Hotspot stopped successfully.${NC}"
    exit 0
}
trap cleanup SIGINT SIGTERM SIGHUP EXIT

# --- Optimize Wi-Fi Driver for Maximum Range / Power ---
echo -e "${CYAN}[*] Disabling Wi-Fi Power Saving and setting txpower to MAX...${NC}"
iw dev "$WIFI_INT" set power_save off 2>/dev/null || true
iw dev "$WIFI_INT" set txpower limit 3000 2>/dev/null || true
# Set country code to Egypt (EG) for maximum signal power allowance
iw reg set EG 2>/dev/null || true

# --- Launch Hotspot ---
if systemctl is-active NetworkManager &>/dev/null; then
    echo -e "${GREEN}[+] Launching Native NetworkManager Hotspot...${NC}"
    # Delete old hotspot connection profile if exists to prevent profile pollution
    nmcli connection delete Hotspot &>/dev/null || true
    # Start hotspot using native NetworkManager command
    if nmcli device wifi hotspot ifname "$WIFI_INT" ssid "$SSID" password "$PASSPHRASE"; then
        echo -e "\n${GREEN}[OK] Hotspot is running natively via NetworkManager!${NC}"
        echo -e "${YELLOW}[*] Press Ctrl+C to stop it and exit...${NC}"
        # Keep process running to listen for traps/cancellation
        while true; do
            sleep 2
        done
    else
        echo -e "${RED}[!] Native NetworkManager hotspot failed. Falling back to create_ap...${NC}"
    fi
fi

# --- Fallback to create_ap / linux-wifi-hotspot ---
if ! command -v create_ap &>/dev/null; then
    echo -e "${YELLOW}[*] 'create_ap' helper is missing. Attempting auto-installation...${NC}"
    if command -v pacman &>/dev/null; then
        # Try to install dependency chain
        pacman -S --needed --noconfirm dnsmasq hostapd iw psmisc haveged iptables || true
        if [ -n "$SUDO_USER" ] && sudo -u "$SUDO_USER" bash -c 'command -v yay' &>/dev/null; then
            sudo -u "$SUDO_USER" yay -S --needed --noconfirm linux-wifi-hotspot || true
        fi
    fi
fi

if command -v create_ap &>/dev/null; then
    echo -e "${GREEN}[+] Launching fallback create_ap hotspot...${NC}"
    # Terminate conflicting hostapd/dnsmasq instances
    killall -9 hostapd dnsmasq create_ap haveged 2>/dev/null || true
    create_ap --no-virt --ieee80211n "$WIFI_INT" "$INTERNET_INT" "$SSID" "$PASSPHRASE"
else
    echo -e "${RED}[ERROR] Neither NetworkManager Hotspot nor create_ap fallback could be executed.${NC}"
    echo -e "${YELLOW}[*] Please make sure NetworkManager or linux-wifi-hotspot is installed.${NC}"
    exit 1
fi
HOTEOF
chmod +x "$HOME/start_hotspot.sh"
fi

if [[ "$opt_deploy_dots" =~ ^[Yy]$ ]]; then
# --- Configure Antigravity IDE Flags & Keyring ---
echo -e "${CYAN}Writing ~/.config/antigravity-ide-flags.conf...${NC}"
mkdir -p "$HOME/.config"
echo "--password-store=gnome-libsecret" > "$HOME/.config/antigravity-ide-flags.conf"

# --- Configure Cava & Write default config with Green-Blue Gradient theme ---
echo -e "${CYAN}Writing ~/.config/cava/config...${NC}"
mkdir -p "$HOME/.config/cava"
cat << 'EOF' > "$HOME/.config/cava/config"
[general]
bars = 0
bar_width = 3
bar_spacing = 1

[input]
method = pulse
source = auto

[output]
method = noncurses

[color]
gradient = 1
gradient_color_1 = '#2af598'
gradient_color_2 = '#15e3b6'
gradient_color_3 = '#00c9ff'
gradient_color_4 = '#00f2fe'
gradient_color_5 = '#0072ff'
EOF
fi

if [[ "$opt_helper_scripts" =~ ^[Yy]$ ]]; then
# --- Write ~/.local/share/bin/hypr-display-settings.py ---
echo -e "${CYAN}Writing ~/.local/share/bin/hypr-display-settings.py...${NC}"
mkdir -p "$HOME/.local/share/bin"
cat << 'DYEOF' > "$HOME/.local/share/bin/hypr-display-settings.py"
#!/usr/bin/env python3
import os
import re
import sys
import subprocess
import tkinter as tk
from tkinter import ttk, messagebox

# --- CONFIG PATHS ---
MONITORS_CONF = os.path.expanduser('~/.config/hypr/monitors.conf')
USERPREFS_CONF = os.path.expanduser('~/.config/hypr/userprefs.conf')

# --- HELPERS ---
def get_monitor_info():
    try:
        output = subprocess.check_output(['hyprctl', 'monitors'], text=True)
    except Exception as e:
        messagebox.showerror("Error", f"Failed to run 'hyprctl monitors': {e}")
        sys.exit(1)

    monitors = {}
    chunks = output.split('Monitor ')[1:]
    for chunk in chunks:
        lines = chunk.strip().split('\n')
        if not lines:
            continue
        
        match_name = re.match(r'^(\S+)\s+\(ID', lines[0])
        if not match_name:
            continue
        name = match_name.group(1)
        
        info = {
            'name': name,
            'model': 'Unknown',
            'current_mode': '',
            'position': '0x0',
            'scale': '1.00',
            'available_modes': {},
            'extra': ''
        }
        
        if len(lines) > 1:
            match_mode = re.search(r'(\d+x\d+@\d+\.\d+)\s+at\s+(\d+x\d+)', lines[1])
            if match_mode:
                info['current_mode'] = match_mode.group(1)
                info['position'] = match_mode.group(2)
        
        for line in lines:
            line_str = line.strip()
            if line_str.startswith('model:'):
                info['model'] = line_str.split('model:')[1].strip()
            elif line_str.startswith('scale:'):
                info['scale'] = line_str.split('scale:')[1].strip()
            elif line_str.startswith('availableModes:'):
                modes_str = line_str.split('availableModes:')[1].strip()
                modes_list = modes_str.split()
                
                # Group modes by resolution
                grouped = {}
                for mode in modes_list:
                    m = re.match(r'^(\d+x\d+)@([\d\.]+(?:Hz)?)$', mode)
                    if m:
                        res = m.group(1)
                        hz = m.group(2).replace('Hz', '')
                        try:
                            hz_float = float(hz)
                            hz_str = str(int(hz_float)) if hz_float.is_integer() else f"{hz_float:.2f}"
                        except ValueError:
                            hz_str = hz
                        
                        if res not in grouped:
                            grouped[res] = []
                        if hz_str not in grouped[res]:
                            grouped[res].append(hz_str)
                
                # Sort resolutions and refresh rates descending
                sorted_res = sorted(grouped.keys(), key=lambda r: [int(x) for x in r.split('x')], reverse=True)
                sorted_grouped = {}
                for r in sorted_res:
                    sorted_grouped[r] = sorted(grouped[r], key=float, reverse=True)
                
                info['available_modes'] = sorted_grouped
                
        monitors[name] = info
    
    # Parse existing monitors.conf to preserve extra options (like transform, mirror, etc.)
    if os.path.exists(MONITORS_CONF):
        try:
            with open(MONITORS_CONF, 'r') as f:
                content = f.read()
            for name in monitors:
                match_line = re.search(r'^\s*monitor\s*=\s*' + re.escape(name) + r'\s*,\s*[^,\n]+\s*,\s*[^,\n]+\s*,\s*[^,\n]+(.*)$', content, re.MULTILINE)
                if match_line:
                    monitors[name]['extra'] = match_line.group(1).strip()
        except Exception:
            pass

    return monitors

def get_mouse_sensitivity():
    if not os.path.exists(USERPREFS_CONF):
        return 0.0
    try:
        with open(USERPREFS_CONF, 'r') as f:
            content = f.read()
        match = re.search(r'^\s*sensitivity\s*=\s*([-\d\.]+)', content, re.MULTILINE)
        if match:
            return float(match.group(1))
    except Exception:
        pass
    return 0.0

def set_mouse_sensitivity(value):
    try:
        os.makedirs(os.path.dirname(USERPREFS_CONF), exist_ok=True)
        if not os.path.exists(USERPREFS_CONF):
            with open(USERPREFS_CONF, 'w') as f:
                f.write("# User Preferences\ninput {\n    sensitivity = 0.00\n}\n")
        
        with open(USERPREFS_CONF, 'r') as f:
            content = f.read()
        
        pattern = r'^(\s*sensitivity\s*=\s*)[-\d\.]+'
        if re.search(pattern, content, re.MULTILINE):
            new_content = re.sub(pattern, rf'\g<1>{value:.2f}', content, flags=re.MULTILINE)
        else:
            match = re.search(r'input\s*\{', content)
            if match:
                start_idx = match.end()
                brace_count = 1
                end_idx = -1
                for i in range(start_idx, len(content)):
                    if content[i] == '{':
                        brace_count += 1
                    elif content[i] == '}':
                        brace_count -= 1
                        if brace_count == 0:
                            end_idx = i
                            break
                if end_idx != -1:
                    before = content[:end_idx]
                    after = content[end_idx:]
                    if before and not before.endswith('\n'):
                        before += '\n'
                    new_content = before + f"    sensitivity = {value:.2f}\n" + after
                else:
                    new_content = content + f"\ninput {{\n    sensitivity = {value:.2f}\n}}\n"
            else:
                new_content = content + f"\ninput {{\n    sensitivity = {value:.2f}\n}}\n"
                
        with open(USERPREFS_CONF, 'w') as f:
            f.write(new_content)
        return True
    except Exception:
        return False

def get_touchpad_natural_scroll():
    if not os.path.exists(USERPREFS_CONF):
        return True
    try:
        with open(USERPREFS_CONF, 'r') as f:
            content = f.read()
        match = re.search(r'natural_scroll\s*=\s*(true|false)', content)
        if match:
            return match.group(1) == 'true'
    except Exception:
        pass
    return True

def set_touchpad_natural_scroll(enabled):
    try:
        os.makedirs(os.path.dirname(USERPREFS_CONF), exist_ok=True)
        if not os.path.exists(USERPREFS_CONF):
            with open(USERPREFS_CONF, 'w') as f:
                f.write("# User Preferences\n")
        
        with open(USERPREFS_CONF, 'r') as f:
            content = f.read()
        
        touchpad_pattern = r'(touchpad\s*\{[^}]*natural_scroll\s*=\s*)(true|false)'
        if re.search(touchpad_pattern, content):
            new_content = re.sub(touchpad_pattern, rf'\g<1>{"true" if enabled else "false"}', content)
        else:
            touchpad_block_pattern = r'touchpad\s*\{'
            match_tp = re.search(touchpad_block_pattern, content)
            if match_tp:
                start_idx = match_tp.end()
                brace_count = 1
                end_idx = -1
                for i in range(start_idx, len(content)):
                    if content[i] == '{':
                        brace_count += 1
                    elif content[i] == '}':
                        brace_count -= 1
                        if brace_count == 0:
                            end_idx = i
                            break
                if end_idx != -1:
                    before = content[:end_idx]
                    after = content[end_idx:]
                    if before and not before.endswith('\n'):
                        before += '\n'
                    new_content = before + f"        natural_scroll = {'true' if enabled else 'false'}\n" + after
                else:
                    new_content = content + f"\ninput {{\n    touchpad {{\n        natural_scroll = {'true' if enabled else 'false'}\n    }}\n}}\n"
            else:
                match_in = re.search(r'input\s*\{', content)
                if match_in:
                    start_idx = match_in.end()
                    brace_count = 1
                    end_idx = -1
                    for i in range(start_idx, len(content)):
                        if content[i] == '{':
                            brace_count += 1
                        elif content[i] == '}':
                            brace_count -= 1
                            if brace_count == 0:
                                end_idx = i
                                break
                    if end_idx != -1:
                        before = content[:end_idx]
                        after = content[end_idx:]
                        if before and not before.endswith('\n'):
                            before += '\n'
                        tp_block = f"    touchpad {{\n        natural_scroll = {'true' if enabled else 'false'}\n    }}\n"
                        new_content = before + tp_block + after
                    else:
                        new_content = content + f"\ninput {{\n    touchpad {{\n        natural_scroll = {'true' if enabled else 'false'}\n    }}\n}}\n"
                else:
                    new_content = content + f"\ninput {{\n    touchpad {{\n        natural_scroll = {'true' if enabled else 'false'}\n    }}\n}}\n"
                
        with open(USERPREFS_CONF, 'w') as f:
            f.write(new_content)
        return True
    except Exception:
        return False

def update_monitor_config(name, resolution, hz, scale, pos, transform_val=0):
    try:
        os.makedirs(os.path.dirname(MONITORS_CONF), exist_ok=True)
        if not os.path.exists(MONITORS_CONF):
            with open(MONITORS_CONF, 'w') as f:
                f.write("# Monitor Rules\n")
                
        with open(MONITORS_CONF, 'r') as f:
            lines = f.readlines()
        
        position = pos if pos and pos != 'auto' else '0x0'
        res_hz = f"{resolution}@{hz}"
        extra_str = f",transform,{transform_val}" if transform_val > 0 else ""
        new_line = f"monitor = {name},{res_hz},{position},{scale}{extra_str}\n"
        
        updated = False
        for i, line in enumerate(lines):
            match = re.match(r'^\s*monitor\s*=\s*([\w\-]+)\s*,', line)
            if match and match.group(1) == name:
                lines[i] = new_line
                updated = True
                break
                
        if not updated:
            insert_idx = len(lines)
            for idx, line in enumerate(lines):
                if 'Workspace Rules' in line:
                    insert_idx = idx
                    break
            lines.insert(insert_idx, new_line)
            
        with open(MONITORS_CONF, 'w') as f:
            f.writelines(lines)
        return True
    except Exception:
        return False

# --- GUI APP ---
class DisplaySettingsApp(tk.Tk):
    def __init__(self):
        super().__init__()
        
        self.title("CachyOS Display & Mouse Settings")
        self.geometry("450x450")
        self.configure(bg='#272727')
        
        # Load data
        self.monitors = get_monitor_info()
        self.current_sens = get_mouse_sensitivity()
        
        # Style
        self.setup_styles()
        
        # Build UI
        self.build_ui()
        
    def setup_styles(self):
        style = ttk.Style()
        style.theme_use('clam')
        
        style.configure('.', background='#272727', foreground='#ebdbb2', font=('JetBrains Mono', 10))
        style.configure('TLabel', background='#272727', foreground='#ebdbb2')
        style.configure('TFrame', background='#272727')
        
        style.configure('TNotebook', background='#272727', borderwidth=0)
        style.configure('TNotebook.Tab', background='#3c3836', foreground='#a89984', padding=[12, 6])
        style.map('TNotebook.Tab', background=[('selected', '#272727')], foreground=[('selected', '#ebdbb2')])
        
        style.configure('TCombobox', fieldbackground='#3c3836', background='#504945', foreground='#ebdbb2')
        style.map('TCombobox', fieldbackground=[('readonly', '#3c3836')], foreground=[('readonly', '#ebdbb2')])
        
        style.configure('TButton', background='#3c3836', foreground='#ebdbb2', borderwidth=1, focuscolor='none', padding=[10, 5])
        style.map('TButton', background=[('active', '#504945')])

    def build_ui(self):
        # Notebook for Tabs
        notebook = ttk.Notebook(self)
        notebook.pack(fill='both', expand=True, padx=15, pady=15)
        
        # --- TAB 1: DISPLAY ---
        display_frame = ttk.Frame(notebook)
        notebook.add(display_frame, text="Display Settings")
        
        # Monitor Select
        ttk.Label(display_frame, text="Monitor:").grid(row=0, column=0, sticky='w', pady=10, padx=10)
        self.monitor_names = list(self.monitors.keys())
        self.monitor_display_names = [f"{name} ({self.monitors[name]['model']})" for name in self.monitor_names]
        
        self.monitor_combo = ttk.Combobox(display_frame, values=self.monitor_display_names, state="readonly", width=30)
        self.monitor_combo.grid(row=0, column=1, sticky='w', pady=10, padx=10)
        self.monitor_combo.bind("<<ComboboxSelected>>", self.on_monitor_select)
        
        # Resolution Select
        ttk.Label(display_frame, text="Resolution:").grid(row=1, column=0, sticky='w', pady=10, padx=10)
        self.res_combo = ttk.Combobox(display_frame, state="readonly", width=20)
        self.res_combo.grid(row=1, column=1, sticky='w', pady=10, padx=10)
        self.res_combo.bind("<<ComboboxSelected>>", self.on_res_select)
        
        # Refresh Rate Input (Direct Custom Text Entry + Detected Presets Dropdown)
        ttk.Label(display_frame, text="Refresh Rate (Hz):").grid(row=2, column=0, sticky='w', pady=10, padx=10)
        hz_input_frame = ttk.Frame(display_frame)
        hz_input_frame.grid(row=2, column=1, sticky='w', pady=10, padx=10)

        self.hz_entry = ttk.Entry(hz_input_frame, width=10, font=('JetBrains Mono', 10))
        self.hz_entry.pack(side='left', padx=(0, 10))
        self.hz_entry.insert(0, "60")

        self.hz_preset_combo = ttk.Combobox(hz_input_frame, state="readonly", width=14)
        self.hz_preset_combo.pack(side='left', padx=2)
        self.hz_preset_combo.bind("<<ComboboxSelected>>", self.on_hz_preset_select)

        # Scaling Select (Direct Custom Text Entry + Preset Selector)
        ttk.Label(display_frame, text="System Zoom (Scale):").grid(row=3, column=0, sticky='w', pady=10, padx=10)
        scale_input_frame = ttk.Frame(display_frame)
        scale_input_frame.grid(row=3, column=1, sticky='w', pady=10, padx=10)

        self.scale_entry = ttk.Entry(scale_input_frame, width=10, font=('JetBrains Mono', 10))
        self.scale_entry.pack(side='left', padx=(0, 10))
        self.scale_entry.insert(0, "1")

        self.scale_preset_combo = ttk.Combobox(
            scale_input_frame,
            values=["1 (100%)", "1.25 (125%)", "1.5 (150%)", "1.67 (167%)", "1.75 (175%)", "2 (200%)"],
            state="readonly", width=14
        )
        self.scale_preset_combo.pack(side='left', padx=2)
        self.scale_preset_combo.bind("<<ComboboxSelected>>", self.on_scale_preset_select)

        # Orientation Select
        ttk.Label(display_frame, text="Orientation:").grid(row=4, column=0, sticky='w', pady=10, padx=10)
        self.rot_values = ["Landscape (Normal)", "Portrait (90°)", "Flipped Landscape (180°)", "Flipped Portrait (270°)"]
        self.rot_combo = ttk.Combobox(display_frame, values=self.rot_values, state="readonly", width=25)
        self.rot_combo.grid(row=4, column=1, sticky='w', pady=10, padx=10)
        
        # --- TAB 2: MOUSE ---
        mouse_frame = ttk.Frame(notebook)
        notebook.add(mouse_frame, text="Mouse Sensitivity")
        
        ttk.Label(mouse_frame, text="Adjust Pointer Sensitivity:", font=('JetBrains Mono', 11, 'bold')).pack(anchor='w', pady=15, padx=15)
        ttk.Label(mouse_frame, text="Slide left to slow down, right to speed up (-1.00 to +1.00):").pack(anchor='w', pady=5, padx=15)
        
        # Sens Slider Frame
        slider_frame = ttk.Frame(mouse_frame)
        slider_frame.pack(fill='x', padx=15, pady=20)
        
        self.sens_val_var = tk.StringVar(value=f"{self.current_sens:.2f}")
        
        self.sens_slider = tk.Scale(
            slider_frame, from_=-1.0, to=1.0, resolution=0.05, orient='horizontal',
            bg='#3c3836', fg='#ebdbb2', troughcolor='#272727', highlightbackground='#272727',
            activebackground='#504945', showvalue=False, command=self.on_slider_move
        )
        self.sens_slider.set(self.current_sens)
        self.sens_slider.pack(side='left', fill='x', expand=True, padx=5)
        
        sens_label = ttk.Label(slider_frame, textvariable=self.sens_val_var, font=('JetBrains Mono', 12, 'bold'), width=6, anchor='center')
        sens_label.pack(side='right', padx=10)
        
        # Accel Note
        ttk.Label(mouse_frame, text="* Accel profile is forced to 'flat' to ensure raw mouse precision.", foreground='#a89984').pack(anchor='w', padx=15, pady=10)

        # Touchpad Settings Separator
        ttk.Separator(mouse_frame, orient='horizontal').pack(fill='x', padx=15, pady=15)
        
        ttk.Label(mouse_frame, text="Touchpad Settings:", font=('JetBrains Mono', 11, 'bold')).pack(anchor='w', padx=15, pady=5)
        
        self.touchpad_var = tk.BooleanVar(value=not get_touchpad_natural_scroll())
        self.touchpad_check = ttk.Checkbutton(
            mouse_frame, text="Windows-style Touchpad Scrolling (Reverse/Standard)",
            variable=self.touchpad_var
        )
        self.touchpad_check.pack(anchor='w', padx=20, pady=10)

        # --- BOTTOM ACTION PANEL ---
        btn_frame = ttk.Frame(self)
        btn_frame.pack(fill='x', side='bottom', padx=15, pady=15)
        
        cancel_btn = ttk.Button(btn_frame, text="Close", command=self.destroy)
        cancel_btn.pack(side='left', padx=5)
        
        apply_btn = ttk.Button(btn_frame, text="Apply & Save Settings", command=self.apply_settings)
        apply_btn.pack(side='right', padx=5)
        
        # Set defaults if monitors exist
        if self.monitor_names:
            self.monitor_combo.current(0)
            self.on_monitor_select(None)

    def on_hz_preset_select(self, event):
        selected = self.hz_preset_combo.get().replace('Hz', '').strip()
        self.hz_entry.delete(0, tk.END)
        self.hz_entry.insert(0, selected)

    def on_scale_preset_select(self, event):
        selected = self.scale_preset_combo.get().split()[0]
        self.scale_entry.delete(0, tk.END)
        self.scale_entry.insert(0, selected)

    def on_monitor_select(self, event):
        m_idx = self.monitor_combo.current()
        m_name = self.monitor_names[m_idx]
        m_info = self.monitors[m_name]
        
        # Update resolutions
        resolutions = list(m_info['available_modes'].keys())
        self.res_combo.configure(values=resolutions)
        
        # Pre-select current or highest resolution
        current_res = m_info['current_mode'].split('@')[0]
        if current_res in resolutions:
            self.res_combo.set(current_res)
        elif resolutions:
            self.res_combo.current(0)
            
        self.on_res_select(None)
        
        # Pre-select current scale into Entry
        curr_scale = m_info['scale']
        self.scale_entry.delete(0, tk.END)
        self.scale_entry.insert(0, curr_scale)

        # Pre-select current transform/rotation
        extra = m_info['extra']
        match_trans = re.search(r'transform\s*,\s*([0-7])', extra)
        if match_trans:
            trans_val = int(match_trans.group(1))
            if trans_val < len(self.rot_values):
                self.rot_combo.current(trans_val)
            else:
                self.rot_combo.current(0)
        else:
            self.rot_combo.current(0)

    def on_res_select(self, event):
        m_idx = self.monitor_combo.current()
        m_name = self.monitor_names[m_idx]
        m_info = self.monitors[m_name]
        
        selected_res = self.res_combo.get()
        if selected_res in m_info['available_modes']:
            refresh_rates = m_info['available_modes'][selected_res]
            self.hz_preset_combo.configure(values=[f"{r} Hz" for r in refresh_rates])
            
            # Match current refresh rate
            current_hz = m_info['current_mode'].split('@')[1] if '@' in m_info['current_mode'] else ''
            try:
                curr_hz_val = float(current_hz)
                curr_hz_str = str(int(curr_hz_val)) if curr_hz_val.is_integer() else f"{curr_hz_val:.2f}"
            except ValueError:
                curr_hz_str = current_hz
            
            self.hz_entry.delete(0, tk.END)
            self.hz_entry.insert(0, curr_hz_str if curr_hz_str else "60")
            
            if refresh_rates:
                self.hz_preset_combo.current(0)

    def on_slider_move(self, value):
        self.sens_val_var.set(f"{float(value):+.2f}")

    def apply_settings(self):
        m_idx = self.monitor_combo.current()
        if m_idx < 0:
            messagebox.showerror("Error", "No monitor selected.")
            return
            
        m_name = self.monitor_names[m_idx]
        m_info = self.monitors[m_name]
        
        selected_res = self.res_combo.get()
        selected_hz = self.hz_entry.get().strip()
        
        selected_scale = self.scale_entry.get().strip()
        try:
            scale_val = float(selected_scale)
            if scale_val <= 0:
                raise ValueError
        except ValueError:
            messagebox.showerror("Error", "Please enter a valid positive number for scaling (e.g., 1, 1.25, 1.5, 1.67).")
            return
            
        try:
            hz_val = float(selected_hz)
            if hz_val <= 0:
                raise ValueError
            selected_hz = str(int(hz_val)) if hz_val.is_integer() else f"{hz_val:.2f}"
        except ValueError:
            messagebox.showerror("Error", "Please enter a valid positive number for refresh rate (e.g., 60, 120, 144, 165, 240).")
            return
        
        if not selected_res or not selected_hz or not selected_scale:
            messagebox.showerror("Error", "Please make sure resolution, refresh rate, and scaling are set.")
            return
            
        # 1. Update Monitor Configuration
        extra = m_info['extra']
        extra_clean = re.sub(r',?\s*transform\s*,\s*\d', '', extra).strip()
        
        selected_rotation = self.rot_combo.current()
        if selected_rotation > 0:
            if extra_clean and not extra_clean.startswith(','):
                extra_clean = ',' + extra_clean
            extra_clean = f",transform,{selected_rotation}" + extra_clean
            
        if extra_clean and not extra_clean.startswith(','):
            extra_clean = ',' + extra_clean
            
        position = m_info['position']
        res_hz = f"{selected_res}@{selected_hz}"
        try:
            subprocess.run(['hyprctl', 'keyword', 'monitor', f"{m_name},{res_hz},{position},{selected_scale}{extra_clean}"], check=True)
            update_monitor_config(m_name, selected_res, selected_hz, selected_scale, extra_clean)
            # Ensure settings are fully applied on legacy/modern Hyprland sessions by triggering a reload
            subprocess.run(['hyprctl', 'reload'], capture_output=True)
        except Exception as e:
            messagebox.showerror("Error", f"Failed to apply display settings: {e}")
            return
            
        # 2. Update Mouse Sensitivity
        sens_value = self.sens_slider.get()
        try:
            subprocess.run(['hyprctl', 'keyword', 'input:sensitivity', f"{sens_value:.2f}"], check=True)
            set_mouse_sensitivity(sens_value)
        except Exception as e:
            messagebox.showerror("Error", f"Failed to apply mouse sensitivity: {e}")
            return

        # 3. Update Touchpad Scrolling Direction
        touchpad_windows_style = self.touchpad_var.get()
        natural_scroll = not touchpad_windows_style
        try:
            subprocess.run(['hyprctl', 'keyword', 'input:touchpad:natural_scroll', 'true' if natural_scroll else 'false'], check=True)
            set_touchpad_natural_scroll(natural_scroll)
        except Exception as e:
            messagebox.showerror("Error", f"Failed to apply touchpad settings: {e}")
            return
            
        messagebox.showinfo("Success", "Settings applied and saved successfully!")
        
        self.monitors = get_monitor_info()
        self.current_sens = get_mouse_sensitivity()
        self.touchpad_var.set(not get_touchpad_natural_scroll())

if __name__ == "__main__":
    if not os.environ.get('WAYLAND_DISPLAY'):
        print("Error: Wayland display not found. This tool is designed for Hyprland.")
        sys.exit(1)
    
    app = DisplaySettingsApp()
    app.mainloop()
DYEOF
chmod +x "$HOME/.local/share/bin/hypr-display-settings.py"

# --- Create Display & Mouse Settings Desktop Entry ---
echo -e "${CYAN}Creating ~/.local/share/applications/hypr-display-settings.desktop...${NC}"
mkdir -p "$HOME/.local/share/applications"
cat << DEEOF > "$HOME/.local/share/applications/hypr-display-settings.desktop"
[Desktop Entry]
Name=Display & Mouse Settings
Comment=Adjust screen resolution, refresh rate, system zoom, and mouse sensitivity
Exec=python3 $HOME/.local/share/bin/hypr-display-settings.py
Icon=video-display
Terminal=false
Type=Application
Categories=Settings;HardwareSettings;
DEEOF
chmod +x "$HOME/.local/share/applications/hypr-display-settings.desktop"

# --- Write ~/.local/share/bin/nightlight-gui.py ---
echo -e "${CYAN}Writing ~/.local/share/bin/nightlight-gui.py...${NC}"
mkdir -p "$HOME/.local/share/bin"
cat << 'NLEOF' > "$HOME/.local/share/bin/nightlight-gui.py"
#!/usr/bin/env python3
# =============================================================================
#   Night Light GUI for Hyprland (hyprsunset)
#   Part of: CachyOS + HyDE Complete System Restorer
#   Repo:    https://github.com/omarahmed321/cachy-os-config-related
#
#   Two modes:
#     python3 nightlight-gui.py           → normal settings panel
#     python3 nightlight-gui.py --setup   → first-run wizard (used by
#                                           restore_my_setup.sh mid-install)
#
#   Installed to: ~/.local/share/bin/nightlight-gui.py
#   Launched via: Super + Alt + N  (Hyprland keybind)
#   Config saved: ~/.config/hypr/nightlight.conf
# =============================================================================

import gi
import subprocess
import os
import re
import sys
import threading

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, GLib, Gdk, Gio

HYPRLAND_CONF = os.path.expanduser("~/.config/hypr/hyprland.conf")
CONFIG_FILE   = os.path.expanduser("~/.config/hypr/nightlight.conf")

SETUP_MODE = "--setup" in sys.argv   # True when called from restore_my_setup.sh

TEMP_MIN     = 1000
TEMP_MAX     = 6500
TEMP_DEFAULT = 3500
GAMMA_MIN    = 10
GAMMA_MAX    = 100

CSS = """
/* ── Window / Card ──────────────────────────────────────────────────── */
window.nightlight-window { background-color: transparent; }

.nightlight-card {
    background: alpha(@window_bg_color, 0.95);
    border-radius: 24px;
    border: 1px solid alpha(@window_fg_color, 0.08);
    padding: 28px 24px 24px 24px;
    box-shadow: 0 12px 40px rgba(0, 0, 0, 0.45);
}

/* ── Setup-mode banner ──────────────────────────────────────────────── */
.setup-banner {
    background: linear-gradient(135deg, alpha(#ff9240, 0.12), alpha(#ff5722, 0.05));
    border-radius: 14px;
    border: 1px solid alpha(#ff9240, 0.25);
    padding: 14px 18px;
    margin-bottom: 20px;
}
.setup-banner-title {
    font-size: 13px;
    font-weight: 800;
    color: #ff9240;
    letter-spacing: 0.3px;
}
.setup-banner-body {
    font-size: 11px;
    opacity: 0.7;
    margin-top: 4px;
    line-height: 1.4;
}

/* ── Typography ─────────────────────────────────────────────────────── */
.header-icon    { font-size: 44px; margin-right: 4px; }
.title-label    { font-size: 24px; font-weight: 800; letter-spacing: -0.5px; }
.subtitle-label { font-size: 12px; opacity: 0.6; margin-top: -2px; }
.section-label  { font-size: 11px; font-weight: 800; letter-spacing: 1.5px;
                  color: @accent_color; opacity: 0.85; margin-top: 18px; margin-bottom: 8px; }
.value-badge    { font-size: 30px; font-weight: 900;
                  font-variant-numeric: tabular-nums; }
.unit-label     { font-size: 14px; opacity: 0.6; font-weight: 600;
                  margin-bottom: 4px; }
.desc-label     { font-size: 11px; opacity: 0.7; font-style: italic; }

/* ── Temperature colours ────────────────────────────────────────────── */
.temp-warm { color: #ff7043; }
.temp-mid  { color: #ffca28; }
.temp-cool { color: #29b6f6; }

/* ── Sliders ────────────────────────────────────────────────────────── */
scale {
    padding: 10px 0;
}

scale trough {
    border-radius: 8px;
    min-height: 14px;
    border: 1px solid alpha(@window_fg_color, 0.05);
    box-shadow: inset 0 1px 3px rgba(0, 0, 0, 0.2);
}

.temp-scale trough { 
    background: linear-gradient(to right, #ff3d00, #ff9100, #ffea00, #ffffff, #80d8ff, #29b6f6); 
}

.gamma-scale trough { 
    background: linear-gradient(to right, #1a1a1a, #555555, #aaaaaa, #ffffff); 
}

scale highlight {
    background: transparent;
    border: none;
    box-shadow: none;
}

scale slider {
    background-color: #ffffff;
    border: 3px solid @accent_color;
    border-radius: 50%;
    min-width: 20px;
    min-height: 20px;
    margin-top: -4px;
    margin-bottom: -4px;
    box-shadow: 0 3px 8px rgba(0, 0, 0, 0.45);
    transition: background-color 0.15s, border-color 0.15s, transform 0.1s;
}

scale slider:hover {
    background-color: #f5f5f5;
    border-color: @accent_bg_color;
    transform: scale(1.15);
}

scale slider:focus {
    border-color: @accent_bg_color;
}

scale slider:active {
    background-color: @accent_color;
    border-color: #ffffff;
    transform: scale(1.25);
    box-shadow: 0 1px 4px rgba(0, 0, 0, 0.3);
}

/* ── Preset grid buttons ────────────────────────────────────────────── */
.preset-btn {
    background-color: alpha(@window_fg_color, 0.04);
    border: 1px solid alpha(@window_fg_color, 0.08);
    border-radius: 12px;
    padding: 12px 8px;
    font-size: 13px;
    font-weight: 600;
    color: @window_fg_color;
    transition: background-color 0.2s, border-color 0.2s, transform 0.1s;
}

.preset-btn:hover {
    background-color: alpha(@window_fg_color, 0.08);
    border-color: alpha(@window_fg_color, 0.15);
    transform: translateY(-1px);
}

.preset-btn:active {
    background-color: alpha(@window_fg_color, 0.12);
    transform: translateY(1px);
}

.preset-btn.active-preset {
    background: linear-gradient(135deg, alpha(@accent_color, 0.25), alpha(@accent_color, 0.15));
    border: 2px solid @accent_color;
    color: @accent_color;
    font-weight: 800;
    box-shadow: 0 4px 12px alpha(@accent_color, 0.18);
}

/* ── Action buttons ─────────────────────────────────────────────────── */
.suggested-action {
    background: linear-gradient(135deg, @accent_bg_color, alpha(@accent_bg_color, 0.85));
    border-radius: 14px;
    padding: 14px 20px;
    font-size: 14px;
    font-weight: 800;
    color: @accent_fg_color;
    border: none;
    box-shadow: 0 4px 15px alpha(@accent_bg_color, 0.35);
    transition: background-color 0.2s, transform 0.1s, box-shadow 0.2s;
}

.suggested-action:hover {
    background: @accent_bg_color;
    box-shadow: 0 6px 20px alpha(@accent_bg_color, 0.45);
    transform: translateY(-1px);
}

.suggested-action:active {
    transform: translateY(1px);
    box-shadow: 0 2px 8px alpha(@accent_bg_color, 0.25);
}

.skip-btn {
    background-color: alpha(@window_fg_color, 0.04);
    border: 1px solid alpha(@window_fg_color, 0.08);
    border-radius: 14px;
    padding: 14px 20px;
    font-size: 13px;
    font-weight: 700;
    color: alpha(@window_fg_color, 0.8);
    transition: background-color 0.2s, border-color 0.2s, transform 0.1s;
}

.skip-btn:hover {
    background-color: alpha(@window_fg_color, 0.08);
    border-color: alpha(@window_fg_color, 0.15);
    transform: translateY(-1px);
}

.skip-btn:active {
    transform: translateY(1px);
}

.status-label {
    font-size: 12px;
    font-weight: 700;
    color: #4caf50;
}
"""

PRESETS = [
    # (label,           temp,  gamma, description)
    ("🌙  Night Mode",  2700,  100,   "Warm amber — perfect for late night"),
    ("🌆  Evening",     3200,  100,   "Soft warm tone for the evening"),
    ("🏠  Home Comfort",4000,  100,   "Balanced warm-neutral light"),
    ("☀️  Daytime",     5500,  100,   "Natural daylight color"),
    ("❄️  Cool Blue",   6500,  100,   "Crisp cool tone for focus"),
    ("🔅  Dim Night",   2700,   70,   "Dimmed warm — great for sleeping"),
]


# ── Config I/O ────────────────────────────────────────────────────────────────

def _read_conf():
    """Return (temp, gamma, enabled) from saved config or hyprland.conf."""
    if os.path.exists(CONFIG_FILE):
        try:
            txt = open(CONFIG_FILE).read()
            t = int(re.search(r"temperature=(\d+)", txt).group(1)) \
                if re.search(r"temperature=(\d+)", txt) else TEMP_DEFAULT
            g = int(re.search(r"gamma=(\d+)",       txt).group(1)) \
                if re.search(r"gamma=(\d+)",       txt) else GAMMA_MAX
            e = re.search(r"enabled=(\w+)", txt).group(1) == "true" \
                if re.search(r"enabled=(\w+)", txt) else True
            return t, g, e
        except Exception:
            pass
    try:
        txt = open(HYPRLAND_CONF).read()
        m = re.search(r"hyprsunset\s+-t\s+(\d+)", txt)
        return (int(m.group(1)) if m else TEMP_DEFAULT), GAMMA_MAX, True
    except Exception:
        return TEMP_DEFAULT, GAMMA_MAX, True


def _save_conf(t, g, e):
    """Write settings to nightlight.conf."""
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    with open(CONFIG_FILE, "w") as f:
        f.write(f"temperature={t}\ngamma={g}\n"
                f"enabled={'true' if e else 'false'}\n")


def _patch_hyprland(t, e):
    """Disable patching hyprland.conf as we use nightlight-start.sh"""
    pass


def _apply_live(t, g, e):
    """Kill existing hyprsunset and restart with new settings."""
    subprocess.run(["pkill", "-x", "hyprsunset"], capture_output=True)
    if e:
        subprocess.Popen(
            ["hyprsunset", "-t", str(t), "-g", str(g)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )


# ── Application ───────────────────────────────────────────────────────────────

class NightLightApp(Adw.Application):
    def __init__(self):
        super().__init__(
            application_id="com.hyde.nightlight",
            flags=Gio.ApplicationFlags.FLAGS_NONE,
        )
        self.connect("activate", self._on_activate)

    def _on_activate(self, app):
        win = NightLightWindow(application=app)
        win.present()


class NightLightWindow(Adw.ApplicationWindow):
    def __init__(self, **kw):
        super().__init__(**kw)
        self.set_title("Night Light — Setup" if SETUP_MODE else "Night Light")
        self.set_default_size(450, -1)
        self.set_resizable(False)
        self.add_css_class("nightlight-window")

        self._t, self._g, self._en = _read_conf()
        self._timer        = None
        self._preset_btns  = []   # kept to highlight active preset
        self._active_preset_idx = None

        # Load CSS
        p = Gtk.CssProvider()
        p.load_from_string(CSS)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), p,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )
        self._build()

    # ── UI ────────────────────────────────────────────────────────────────────

    def _build(self):
        # We put outer box directly in content instead of a ScrolledWindow to prevent scrollbars and clipping
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        outer.set_margin_top(22);  outer.set_margin_bottom(22)
        outer.set_margin_start(22); outer.set_margin_end(22)
        self.set_content(outer)

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        card.add_css_class("nightlight-card")
        outer.append(card)

        # ── Setup-mode banner ────────────────────────────────────────────────
        if SETUP_MODE:
            banner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            banner.add_css_class("setup-banner")
            card.append(banner)

            btitle = Gtk.Label(label="⚙️  Installation Step: Night Light Setup")
            btitle.set_halign(Gtk.Align.START)
            btitle.add_css_class("setup-banner-title")
            banner.append(btitle)

            bbody = Gtk.Label(
         cat << 'NLEOF' > "$HOME/.local/share/bin/nightlight-gui.py"
#!/usr/bin/env python3
# =============================================================================
#   Night Light & Brightness GUI Panel (Hyprland / hyprsunset)
#   Part of: CachyOS + HyDE System Restorer
#   Repo:    https://github.com/omarahmed321/cachy-os-config-related
# =============================================================================

import gi
import subprocess
import os
import re
import sys
import threading

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, GLib, Gdk, Gio

HYPRLAND_CONF = os.path.expanduser("~/.config/hypr/hyprland.conf")
CONFIG_FILE   = os.path.expanduser("~/.config/hypr/nightlight.conf")

# --- Temperature / Percentage Mapping ---
# 0% Night Light Warmth   = 6500K (Daylight / Off)
# 100% Night Light Warmth = 2000K (Max Warm Amber)
def pct_to_temp(pct):
    pct = max(0, min(100, pct))
    return int(6500 - (pct / 100.0) * 4500)

def temp_to_pct(temp):
    temp = max(2000, min(6500, temp))
    return int(round(((6500 - temp) / 4500.0) * 100))

def get_warmth_desc(pct):
    if pct <= 0:
        return "⚪ Off · Normal Daylight (6500K)"
    elif pct <= 35:
        return f"🟡 Soft Warmth ({pct_to_temp(pct)}K)"
    elif pct <= 70:
        return f"🟠 Balanced Night Warmth ({pct_to_temp(pct)}K)"
    else:
        return f"🔴 Deep Amber Night Mode ({pct_to_temp(pct)}K)"

# --- Backend Config Functions ---
def _load_conf():
    t, en = 3500, True
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r") as f:
                c = f.read()
            m_t = re.search(r"^\s*(?:ENABLE_NIGHTLIGHT|temperature)=(\d+)", c, re.M)
            m_e = re.search(r"^\s*(?:HYPRSUNSET_ENABLED|enabled)=(true|false)", c, re.M)
            if m_t: t = int(m_t.group(1))
            if m_e: en = (m_e.group(1) == "true")
        except Exception:
            pass
    return t, en

def _save_conf(t, en):
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    en_str = "true" if en else "false"
    with open(CONFIG_FILE, "w") as f:
        f.write(f"""# Night Light Configuration — managed by nightlight-gui.py
temperature={t}
enabled={en_str}
ENABLE_NIGHTLIGHT={t}
HYPRSUNSET_ENABLED={en_str}
""")

def _apply_live(t, en):
    # Kill any existing hyprsunset daemon instances
    subprocess.run(["pkill", "-9", "-x", "hyprsunset"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    if not en or t >= 6400:
        return

    try:
        # Spawn hyprsunset as a persistent background daemon
        subprocess.Popen(
            ["hyprsunset", "-t", str(t)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True
        )
    except Exception as e:
        print(f"[!] Failed to run hyprsunset: {e}")

def _patch_hyprland(t, en):
    if not os.path.exists(HYPRLAND_CONF):
        return
    try:
        with open(HYPRLAND_CONF, "r") as f:
            lines = f.readlines()
        exec_line = "exec-once = bash ~/.local/share/bin/nightlight-start.sh\n"
        has_exec = any("nightlight-start.sh" in l for l in lines)
        if not has_exec:
            lines.append("\n# Auto-start Night Light\n" + exec_line)
            with open(HYPRLAND_CONF, "w") as f:
                f.writelines(lines)
    except Exception:
        pass

# --- Clean & Modern UI Window ---
CSS = """
window { background-color: transparent; }

.main-card {
    background: alpha(@window_bg_color, 0.95);
    border-radius: 20px;
    border: 1px solid alpha(@window_fg_color, 0.1);
    padding: 24px;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.4);
}

.title-label {
    font-size: 17px;
    font-weight: 800;
}

.slider-label {
    font-size: 13px;
    font-weight: 700;
    margin-top: 10px;
}

.val-badge {
    font-size: 16px;
    font-weight: 800;
    color: @accent_color;
}

.desc-label {
    font-size: 11px;
    opacity: 0.75;
    margin-top: 2px;
}

.status-label {
    font-size: 12px;
    font-weight: 700;
    color: #2ecc71;
}

scale trough {
    border-radius: 8px;
    min-height: 12px;
}
"""

class NightLightApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id="org.cachyos.nightlight")
        self.connect("activate", self.on_activate)

    def on_activate(self, app):
        p = Gtk.CssProvider()
        p.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        win = Adw.ApplicationWindow(application=app, title="Night Light Control")
        win.set_default_size(380, 240)

        t, en = _load_conf()
        self._t = t
        self._en = en
        self._timer = None

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        card.add_css_class("main-card")

        # Header Row with Switch Toggle
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        title = Gtk.Label(label="🌙 Night Light Control")
        title.add_css_class("title-label")
        title.set_hexpand(True)
        title.set_halign(Gtk.Align.START)
        header.append(title)

        self.toggle = Gtk.Switch()
        self.toggle.set_active(self._en)
        self.toggle.connect("state-set", self._on_toggle)
        header.append(self.toggle)
        card.append(header)

        # Divider
        card.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        # Slider: Night Light Warmth (Percentage 0% - 100%)
        initial_pct = temp_to_pct(self._t)

        row_nl = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        lbl_nl = Gtk.Label(label="Night Light Warmth")
        lbl_nl.add_css_class("slider-label")
        lbl_nl.set_hexpand(True)
        lbl_nl.set_halign(Gtk.Align.START)
        row_nl.append(lbl_nl)

        self.val_nl = Gtk.Label(label=f"{initial_pct}%")
        self.val_nl.add_css_class("val-badge")
        row_nl.append(self.val_nl)
        card.append(row_nl)

        self.desc_nl = Gtk.Label(label=get_warmth_desc(initial_pct))
        self.desc_nl.add_css_class("desc-label")
        self.desc_nl.set_halign(Gtk.Align.START)
        card.append(self.desc_nl)

        self.scale_nl = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
        self.scale_nl.set_value(initial_pct)
        self.scale_nl.set_sensitive(self._en)
        self.scale_nl.connect("value-changed", self._on_temp_pct_changed)
        card.append(self.scale_nl)


        self.status_lbl = Gtk.Label(label="✓ Auto-saved")
        self.status_lbl.add_css_class("status-label")
        self.status_lbl.set_margin_top(4)
        card.append(self.status_lbl)

        win.set_content(card)
        win.present()

    def _on_toggle(self, sw, state):
        self._en = state
        self.scale_nl.set_sensitive(state)
        self._debounce()
        return False

    def _on_temp_pct_changed(self, sc):
        pct = int(sc.get_value())
        self.val_nl.set_label(f"{pct}%")
        self.desc_nl.set_label(get_warmth_desc(pct))
        self._t = pct_to_temp(pct)
        self._debounce()

    def _debounce(self):
        if self._timer:
            GLib.source_remove(self._timer)
        self._timer = GLib.timeout_add(250, self._do_apply_and_save)

    def _do_apply_and_save(self):
        self._timer = None
        def _do():
            _save_conf(self._t, self._en)
            _patch_hyprland(self._t, self._en)
            _apply_live(self._t, self._en)
        threading.Thread(target=_do, daemon=True).start()
        return False

    def _set_sens(self, e):
        self.ts.set_sensitive(e)
        self.gs.set_sensitive(e)

    def _upd_temp(self, t):
        self.tv.set_label(str(t))
        for c in ["temp-warm", "temp-mid", "temp-cool"]:
            self.tv.remove_css_class(c)
        if t <= 3500:
            self.tv.add_css_class("temp-warm"); d = "🔴 Very warm · amber"
        elif t <= 4500:
            self.tv.add_css_class("temp-mid");  d = "🟡 Warm neutral · balanced"
        elif t <= 5500:
            d = "⚪ Natural · daylight"
        else:
            self.tv.add_css_class("temp-cool"); d = "🔵 Cool · blue-white"
        self.td.set_label(d)

    def _highlight_matching_preset(self, t, g):
        """Highlight the preset button whose (temp, gamma) matches current."""
        for i, btn in enumerate(self._preset_btns):
            _, pt, pg, _ = PRESETS[i]
            if pt == t and pg == g:
                btn.add_css_class("active-preset")
            else:
                btn.remove_css_class("active-preset")

    def _show_status(self, msg):
        self.sl.set_label(msg)
        GLib.timeout_add_seconds(4, lambda: self.sl.set_label("") or False)


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    NightLightApp().run(None)

NLEOF
chmod +x "$HOME/.local/share/bin/nightlight-gui.py"

# --- Write ~/.local/share/bin/nightlight-start.sh ---
echo -e "${CYAN}Writing ~/.local/share/bin/nightlight-start.sh...${NC}"
cat << 'NLSEOF' > "$HOME/.local/share/bin/nightlight-start.sh"
#!/usr/bin/env bash
# Night Light startup script — launched by Hyprland exec-once
# Reads ~/.config/hypr/nightlight.conf for saved settings, falls back to 3500K

CONF="$HOME/.config/hypr/nightlight.conf"

TEMP=3500
GAMMA=100
ENABLED=true

if [ -f "$CONF" ]; then
    t=$(grep -oP 'temperature=\K\d+' "$CONF" 2>/dev/null)
    g=$(grep -oP 'gamma=\K\d+'       "$CONF" 2>/dev/null)
    e=$(grep -oP 'enabled=\K\w+'     "$CONF" 2>/dev/null)
    [ -n "$t" ] && TEMP=$t
    [ -n "$g" ] && GAMMA=$g
    [ "$e" = "false" ] && ENABLED=false
fi

pkill -x hyprsunset 2>/dev/null || true

if [ "$ENABLED" = "true" ]; then
    exec hyprsunset -t "$TEMP" -g "$GAMMA"
fi
NLSEOF
chmod +x "$HOME/.local/share/bin/nightlight-start.sh"

# --- Create Night Light Desktop Entry ---
echo -e "${CYAN}Creating ~/.local/share/applications/nightlight-gui.desktop...${NC}"
mkdir -p "$HOME/.local/share/applications"
cat << NLDEEOF > "$HOME/.local/share/applications/nightlight-gui.desktop"
[Desktop Entry]
Name=Night Light
Comment=Adjust display color temperature and brightness (hyprsunset)
Exec=python3 $HOME/.local/share/bin/nightlight-gui.py
Icon=night-light
Terminal=false
Type=Application
Categories=Settings;HardwareSettings;
NLDEEOF
chmod +x "$HOME/.local/share/applications/nightlight-gui.desktop"
fi

if [[ "$opt_deploy_dots" =~ ^[Yy]$ ]]; then
echo -e "${CYAN}Ensuring gnome-keyring-daemon systemd services are unmasked...${NC}"
systemctl --user unmask gnome-keyring-daemon.service gnome-keyring-daemon.socket 2>/dev/null || true
systemctl --user enable gnome-keyring-daemon.service gnome-keyring-daemon.socket 2>/dev/null || true

# --- VS Code Configurations & Extensions ---
echo -e "\n${BLUE}${BOLD}Configuring Visual Studio Code...${NC}"
mkdir -p "$HOME/.config/Code/User"

echo -e "${CYAN}Writing VS Code settings.json...${NC}"
cat << 'EOF' > "$HOME/.config/Code/User/settings.json"
{
  "workbench.colorTheme": "Gruvbox Dark Medium",
  "window.menuBarVisibility": "toggle",
  "editor.fontSize": 12,
  "editor.scrollbar.vertical": "hidden",
  "editor.scrollbar.verticalScrollbarSize": 0,
  "security.workspace.trust.untrustedFiles": "newWindow",
  "security.workspace.trust.startupPrompt": "never",
  "security.workspace.trust.enabled": false,
  "editor.minimap.side": "left",
  "editor.fontFamily": "'JetBrainsMono Nerd Font', 'monospace'",
  "extensions.autoUpdate": false,
  "workbench.statusBar.visible": false,
  "terminal.external.linuxExec": "kitty",
  "terminal.explorerKind": "both",
  "terminal.sourceControlRepositoriesKind": "both",
  "telemetry.telemetryLevel": "off",
  "terminal.integrated.foreground": "#ebdbb2",
  "terminal.integrated.background": "#272727",
  "terminal.integrated.selectionBackground": "#655b53",
  "terminal.integrated.cursorStyle": "block",
  "terminal.integrated.fontFamily": "'JetBrainsMono Nerd Font', 'monospace'",
  "terminal.integrated.ansiBlack": "#272727",
  "terminal.integrated.ansiRed": "#cc231c",
  "terminal.integrated.ansiGreen": "#989719",
  "terminal.integrated.ansiYellow": "#d79920",
  "terminal.integrated.ansiBlue": "#448488",
  "terminal.integrated.ansiMagenta": "#b16185",
  "terminal.integrated.ansiCyan": "#689d69",
  "terminal.integrated.ansiWhite": "#a89983",
  "terminal.integrated.ansiBrightBlack": "#928373",
  "terminal.integrated.ansiBrightRed": "#fb4833",
  "terminal.integrated.ansiBrightGreen": "#b8ba25",
  "terminal.integrated.ansiBrightYellow": "#fabc2e",
  "terminal.integrated.ansiBrightBlue": "#83a597",
  "terminal.integrated.ansiBrightMagenta": "#d3859a",
  "terminal.integrated.ansiBrightCyan": "#8ec07b",
  "terminal.integrated.ansiBrightWhite": "#ebdbb2",
  "emmet.includeLanguages": {
    "javascript": "javascriptreact",
    "typescript": "typescriptreact"
  },
  "emmet.triggerExpansionOnTab": true,
  "emmet.showExpandedAbbreviation": "always",
  "emmet.showSuggestionsAsSnippets": true,
  "editor.snippetSuggestions": "top",
  "editor.quickSuggestionsDelay": 0,
  "editor.wordBasedSuggestions": "off",
  "editor.inlineSuggest.enabled": false,
  "github.copilot.editor.enableAutoCompletions": false,
  "editor.quickSuggestions": {
    "other": "on",
    "comments": "off",
    "strings": "off"
  },
  "editor.suggestOnTriggerCharacters": true,
  "tailwindCSS.includeLanguages": {
    "javascript": "javascriptreact",
    "typescript": "typescriptreact"
  },
  "editor.formatOnSave": false,
  "editor.defaultFormatter": "esbenp.prettier-vscode"
}
EOF

echo -e "${CYAN}Writing VS Code keybindings.json...${NC}"
cat << 'EOF' > "$HOME/.config/Code/User/keybindings.json"
[
    {
        "key": "ctrl+shift+i",
        "command": "editor.action.formatDocument",
        "when": "editorHasDocumentFormattingProvider && editorTextFocus && !editorReadonly"
    },
    {
        "key": "ctrl+alt+down",
        "command": "editor.action.copyLinesDownAction",
        "when": "editorTextFocus && !editorReadonly"
    },
    {
        "key": "ctrl+alt+up",
        "command": "editor.action.copyLinesUpAction",
        "when": "editorTextFocus && !editorReadonly"
    }
]
EOF

echo -e "${CYAN}Writing Code - OSS configurations...${NC}"
mkdir -p "$HOME/.config/Code - OSS/User"
cp "$HOME/.config/Code/User/settings.json" "$HOME/.config/Code - OSS/User/settings.json"
cat << 'EOF' > "$HOME/.config/Code - OSS/User/keybindings.json"
// Place your key bindings in this file to override the defaults
[
    {
        "key": "ctrl+pageup ctrl+pageup",
        "command": "workbench.action.terminal.toggleTerminal",
        "when": "terminal.active"
    },
    {
        "key": "ctrl+`",
        "command": "-workbench.action.terminal.toggleTerminal",
        "when": "terminal.active"
    },
    {
        "key": "ctrl+shift+i",
        "command": "editor.action.formatDocument",
        "when": "editorHasDocumentFormattingProvider && editorTextFocus && !editorReadonly"
    },
    {
        "key": "ctrl+alt+down",
        "command": "editor.action.copyLinesDownAction",
        "when": "editorTextFocus && !editorReadonly"
    },
    {
        "key": "ctrl+alt+up",
        "command": "editor.action.copyLinesUpAction",
        "when": "editorTextFocus && !editorReadonly"
    }
]
EOF

# Install extensions if code CLI is available
if command -v code &>/dev/null; then
    echo -e "${CYAN}Installing VS Code extensions...${NC}"
    VSCODE_EXTS=(
        bradlc.vscode-tailwindcss
        brandonkirbyson.vscode-animations
        drcika.apc-extension
        dsznajder.es7-react-js-snippets
        esbenp.prettier-vscode
        formulahendry.auto-close-tag
        jdinhlife.gruvbox
        pkief.material-icon-theme
        prettier.prettier-vscode
        undefined_publisher.wallbash
    )
    for ext in "${VSCODE_EXTS[@]}"; do
        echo -e "  - Installing extension: ${CYAN}$ext${NC}..."
        code --install-extension "$ext" --force &>/dev/null || true
    done
    echo -e "${GREEN}[OK] VS Code extensions installed successfully!${NC}"
else
    echo -e "${YELLOW}[WARNING] VS Code command line 'code' not found. Skipping extension installation.${NC}"
fi

# Robustly copy all default configurations, scripts, and dotfiles from the cloned HyDE repo if they exist
if [ -d "$HOME/hyde/Configs" ]; then
    echo -e "${CYAN}Deploying default configurations and scripts from HyDE...${NC}"
    
    # Create required destination folders
    mkdir -p "$HOME/.config"
    mkdir -p "$HOME/.local/share/bin"
    mkdir -p "$HOME/.icons"
    
    # Copy all configurations and scripts (no-clobber to preserve custom configs)
    cp -rn "$HOME/hyde/Configs/.config/"* "$HOME/.config/"
    cp -rn "$HOME/hyde/Configs/.local/share/bin/"* "$HOME/.local/share/bin/"
    
    # Copy dotfiles (no-clobber)
    cp -rn "$HOME/hyde/Configs/.gtkrc-2.0" "$HOME/"
    cp -rn "$HOME/hyde/Configs/.p10k.zsh" "$HOME/"
    cp -rn "$HOME/hyde/Configs/.icons/"* "$HOME/.icons/"
    
    # Copy animations.conf and fix outdated layerrule syntax for newer Hyprland versions
    if [ -f "$HOME/hyde/Configs/.config/hypr/animations.conf" ]; then
        cp "$HOME/hyde/Configs/.config/hypr/animations.conf" "$HOME/.config/hypr/"
        sed -i 's/layerrule = noanim, hyprpicker/layerrule = no_anim 1, match:namespace hyprpicker/g' "$HOME/.config/hypr/animations.conf"
        sed -i 's/layerrule = noanim, selection/layerrule = no_anim 1, match:namespace selection/g' "$HOME/.config/hypr/animations.conf"
    else
        echo -e "${YELLOW}[WARNING] animations.conf not found in HyDE Configs. Writing a default fallback...${NC}"
        cat << 'EOF' > "$HOME/.config/hypr/animations.conf"
# ▄▀█ █▄░█ █ █▀▄▀█ ▄▀█ ▀█▀ █ █▀█ █▄░█
# █▀█ █░▀█ █ █░▀░█ █▀█ ░█░ █ █▄█ █░▀█
#
# See https://wiki.hyprland.org/Configuring/Animations/
# this file can be edited manually or use animation selector to select animations

# disable animations while in hyprpicker and selection screenshot
layerrule = no_anim 1, match:namespace hyprpicker
layerrule = no_anim 1, match:namespace selection

source = $HOME/.config/hypr/animations/animations-default.conf
EOF
    fi
fi

# Deploy Bibata-Modern-Ice cursor theme locally (passwordless and robust)
if [ ! -d "$HOME/.icons/Bibata-Modern-Ice" ]; then
    echo -e "${CYAN}Installing Bibata-Modern-Ice cursor theme locally...${NC}"
    mkdir -p "$HOME/.icons"
    curl -sSL -o /tmp/Bibata-Modern-Ice.tar.xz https://github.com/ful1e5/Bibata_Cursor/releases/download/v2.0.7/Bibata-Modern-Ice.tar.xz
    tar -xf /tmp/Bibata-Modern-Ice.tar.xz -C "$HOME/.icons/"
    rm -f /tmp/Bibata-Modern-Ice.tar.xz
fi

# --- WRITE ~/.config/hypr/hyprland.conf ---
echo -e "${CYAN}Writing ~/.config/hypr/hyprland.conf...${NC}"
cat << 'EOF' > "$HOME/.config/hypr/hyprland.conf"

#      ░▒▒▒░░░░░▓▓          ___________
#    ░░▒▒▒░░░░░▓▓        //___________/
#   ░░▒▒▒░░░░░▓▓     _   _ _    _ _____
#   ░░▒▒░░░░░▓▓▓▓▓▓ | | | | |  | |  __/
#    ░▒▒░░░░▓▓   ▓▓ | |_| | |_/ /| |___
#     ░▒▒░░▓▓   ▓▓   \__  |____/ |____/
#       ░▒▓▓   ▓▓  //____/


$scrPath = $HOME/.local/share/bin # set scripts path

# Default cursor theme and size
$CURSOR_THEME = Bibata-Modern-Ice
$CURSOR_SIZE = 20


# █▀▄▀█ █▀█ █▄░█ █ ▀█▀ █▀█ █▀█
# █░▀░█ █▄█ █░▀█ █ ░█░ █▄█ █▀▄

# See https://wiki.hyprland.org/Configuring/Monitors/

# monitor configured in monitors.conf


# █░░ ▄▀█ █░█ █▄░█ █▀▀ █░█
# █▄▄ █▀█ █▄█ █░▀█ █▄▄ █▀█

# See https://wiki.hyprland.org/Configuring/Keywords/

exec-once = $scrPath/resetxdgportal.sh # reset XDPH for screenshare
exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP # for XDPH
exec-once = dbus-update-activation-environment --systemd --all # for XDPH
exec-once = systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP # for XDPH
exec-once = $scrPath/polkitkdeauth.sh # authentication dialogue for GUI apps
exec-once = sleep 2 && env reload_flag=1 $scrPath/wbarconfgen.sh # launch the system bar
exec-once = blueman-applet # systray app for Bluetooth
exec-once = udiskie --no-automount --smart-tray # front-end that allows to manage removable media
exec-once = nm-applet --indicator # systray app for Network/Wifi
exec-once = dunst # start notification demon
exec-once = wl-paste --type text --watch cliphist store # clipboard store text data
exec-once = wl-paste --type image --watch cliphist store # clipboard store image data
exec-once = $scrPath/swwwallpaper.sh # start wallpaper daemon
exec-once = $scrPath/batterynotify.sh # battery notification
exec-once = $scrPath/nightlight-start.sh # night light — reads ~/.config/hypr/nightlight.conf


# █▀▀ █▄░█ █░█
# ██▄ █░▀█ ▀▄▀

# See https://wiki.hyprland.org/Configuring/Environment-variables/

env = PATH,$PATH:$scrPath
env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland
env = XDG_SESSION_DESKTOP,Hyprland
env = QT_QPA_PLATFORM,wayland;xcb
env = QT_QPA_PLATFORMTHEME,qt6ct
env = QT_WAYLAND_DISABLE_WINDOWDECORATION,1
env = QT_AUTO_SCREEN_SCALE_FACTOR,1
env = MOZ_ENABLE_WAYLAND,1
env = GDK_SCALE,1


# █ █▄░█ █▀█ █░█ ▀█▀
# █ █░▀█ █▀▀ █▄█ ░█░

# See https://wiki.hyprland.org/Configuring/Variables/

input {
    kb_layout = us,ara
    kb_variant = ,thal_bksl
    kb_options = grp:alt_shift_toggle
    follow_mouse = 1

    touchpad {
        natural_scroll = no
    }

    sensitivity = -1.0
    accel_profile = flat
    force_no_accel = 0
    numlock_by_default = true
}

# See https://wiki.hyprland.org/Configuring/Keywords/#executing

device {
    name = epic mouse V1
    sensitivity = -0.5
}

# See https://wiki.hyprland.org/Configuring/Variables/

gestures {
    gesture = 3, horizontal, workspace
}


# █░░ ▄▀█ █▄█ █▀█ █░█ ▀█▀ █▀
# █▄▄ █▀█ ░█░ █▄█ █▄█ ░█░ ▄█

# See https://wiki.hyprland.org/Configuring/Dwindle-Layout/

dwindle {
    preserve_split = yes
}

# See https://wiki.hyprland.org/Configuring/Master-Layout/

master {
    new_status = master
}


# █▀▄▀█ █ █▀ █▀▀
# █░▀░█ █ ▄█ █▄▄

# See https://wiki.hyprland.org/Configuring/Variables/

misc {
    vrr = 2
    disable_hyprland_logo = true
    disable_splash_rendering = true
    force_default_wallpaper = 0
}

xwayland {
    force_zero_scaling = true
}


# █▀ █▀█ █░█ █▀█ █▀▀ █▀▀
# ▄█ █▄█ █▄█ █▀▄ █▄▄ ██▄

source = ~/.config/hypr/animations.conf
source = ~/.config/hypr/keybindings.conf
source = ~/.config/hypr/windowrules.conf
source = ~/.config/hypr/themes/common.conf # shared theme settings
# hyprlang noerror true
source = ~/.config/hypr/themes/theme.conf # theme specific settings
# hyprlang noerror false

# Dynamically synchronize GTK and default cursor configurations with the active theme
exec = ~/.config/hypr/sync_cursor.sh $CURSOR_THEME $CURSOR_SIZE
source = ~/.config/hypr/themes/colors.conf # wallbash color override
source = ~/.config/hypr/monitors.conf # initially empty, to be configured by user and remains static
source = ~/.config/hypr/userprefs.conf # initially empty, to be configured by user and remains static

# Note: as userprefs.conf is sourced at the end, settings configured in this file will override the defaults
source = ~/.config/hypr/nvidia.conf # auto sourced vars for nvidia
EOF

# --- WRITE ~/.config/hypr/userprefs.conf ---
echo -e "${CYAN}Writing ~/.config/hypr/userprefs.conf...${NC}"
cat << 'EOF' > "$HOME/.config/hypr/userprefs.conf"

# █░█ █▀ █▀▀ █▀█   █▀█ █▀█ █▀▀ █▀▀ █▀
# █▄█ ▄█ ██▄ █▀▄   █▀▀ █▀▄ ██▄ █▀░ ▄█

# Set your personal hyprland configuration here
# For a sample file, please refer to https://github.com/prasanthrangan/hyprdots/blob/main/Configs/.config/hypr/userprefs.t2

decoration {
    shadow {
        enabled = false
        range = 18
        render_power = 4
        offset = 0 0
    }
}

input {
    kb_layout = us,ara
    kb_variant = ,thal_bksl
    kb_options = grp:alt_shift_toggle
    sensitivity = -0.5
    accel_profile = flat
    force_no_accel = 0
}

# --- Game Mouse Cursor Fixes ---
# Confine mouse pointer to game windows (forces mouse capture, essential for dual-monitor setups)
# windowrule = confine_pointer 1, match:class ^(steam_app_2399830)$
# windowrule = confine_pointer 1, match:title ^(ArkAscended)$
# windowrule = confine_pointer 1, match:class ^(steam_app_.*)$

# --- Keyring Fix ---
# Start gnome-keyring-daemon for managing credentials and secrets securely in Electron/VSCode applications
exec-once = gnome-keyring-daemon --start --components=secrets

# Source pywal colors
source = ~/.cache/wal/colors-hyprland.conf

general {
    border_size = 0
}

decoration {
    rounding = 8
}

windowrule = opacity 0.80 0.80, match:class ^(antigravity)$

misc {
    vrr = 1
}

render {
    direct_scanout = false
}

animations {
    animation = workspaces, 1, 3, default, slide
}

# Wipe clipboard history on startup to prevent database bloat
exec-once = cliphist wipe

# Zen Browser - Zero UI / Frameless
windowrule = opacity 0.70 0.70, match:class ^(zen)$
windowrule = border_size 0, match:class ^(zen)$
EOF

# --- WRITE ~/.config/hypr/keybindings.conf ---
echo -e "${CYAN}Writing ~/.config/hypr/keybindings.conf...${NC}"
cat << 'EOF' > "$HOME/.config/hypr/keybindings.conf"

# █▄▀ █▀▀ █▄█ █▄▄ █ █▄░█ █▀▄ █ █▄░█ █▀▀ █▀
# █░█ ██▄ ░█░ █▄█ █ █░▀█ █▄▀ █ █░▀█ █▄█ ▄█

# See https://wiki.hyprland.org/Configuring/Keywords/
#  &  https://wiki.hyprland.org/Configuring/Binds/

# Main modifier
$mainMod = Super # super / meta / windows key

# Assign apps
$term = kitty
$editor = code
$file = kitty -e yazi
$browser = zen-browser

# Window/Session actions
bindd = $mainMod+Shift, P,Color Picker , exec, hyprpicker -a # Pick color (Hex) >> clipboard# 
bind = $mainMod, Q, exec, $scrPath/dontkillsteam.sh # close focused window (close tab/window)
#bind = Ctrl, C, exec, $HOME/.config/hypr/close_kitty_or_copy.sh # close kitty or copy text
bind = Alt, F4, exec, $scrPath/dontkillsteam.sh # close focused window
bind = $mainMod, Delete, exit, # kill hyprland session
bind = $mainMod, W, togglefloating, # toggle the window between focus and float
bind = $mainMod, G, togglegroup, # toggle the window between focus and group
bind = Alt, Return, fullscreen, # toggle the window between focus and fullscreen
bind = $mainMod, L, exec, ~/.local/share/bin/lockscreen.sh # launch lock screen
bind = $mainMod+Shift, F, exec, $scrPath/windowpin.sh # toggle pin on focused window
bind = $mainMod, Backspace, exec, $scrPath/logoutlaunch.sh # launch logout menu
bind = Ctrl+Alt, W, exec, killall waybar || (env reload_flag=1 $scrPath/wbarconfgen.sh) # toggle waybar and reload config
#bind = Ctrl+Alt, W, exec, killall waybar || waybar # toggle waybar without reloading, this is faster

# Application shortcuts
bind = , Page_Up, exec, $HOME/.local/bin/double-pageup.sh # double-press Page_Up to open terminal
bind = $mainMod, T, exec, $term # launch terminal emulator
bind = $mainMod, E, exec, $file # launch file manager
bind = $mainMod, C, exec, $editor # launch text editor
bind = $mainMod, F, exec, $browser # launch web browser
bind = Ctrl+Shift, Escape, exec, $scrPath/sysmonlaunch.sh # launch system monitor (htop/btop or fallback to top)

# Rofi menus
bindr = SUPER, Super_L, exec, pkill -x rofi || $scrPath/rofilaunch.sh d # launch application launcher using Super key alone
bind = $mainMod, A, exec, pkill -x rofi || $scrPath/rofilaunch.sh d # launch application launcher
bind = $mainMod, Tab, exec, pkill -x rofi || $scrPath/rofilaunch.sh w # launch window switcher
bind = $mainMod+Shift, E, exec, pkill -x rofi || $scrPath/rofilaunch.sh f # launch file explorer

# Audio control
bindl  = , F10, exec, $scrPath/volumecontrol.sh -o m # toggle audio mute
bindel = , F11, exec, $scrPath/volumecontrol.sh -o d # decrease volume
bindel = , F12, exec, $scrPath/volumecontrol.sh -o i # increase volume
bindl  = , XF86AudioMute, exec, $scrPath/volumecontrol.sh -o m # toggle audio mute
bindl  = , XF86AudioMicMute, exec, $scrPath/volumecontrol.sh -i m # toggle microphone mute
bindel = , XF86AudioLowerVolume, exec, $scrPath/volumecontrol.sh -o d # decrease volume
bindel = , XF86AudioRaiseVolume, exec, $scrPath/volumecontrol.sh -o i # increase volume

# Media control
bindl  = , XF86AudioPlay, exec, playerctl play-pause # toggle between media play and pause
bindl  = , XF86AudioPause, exec, playerctl play-pause # toggle between media play and pause
bindl  = , XF86AudioNext, exec, playerctl next # media next
bindl  = , XF86AudioPrev, exec, playerctl previous # media previous

# Brightness control
bindel = , XF86MonBrightnessUp, exec, $scrPath/brightnesscontrol.sh i # increase brightness
bindel = , XF86MonBrightnessDown, exec, $scrPath/brightnesscontrol.sh d # decrease brightness

# Move between grouped windows
bind = $mainMod CTRL , H, changegroupactive, b
bind = $mainMod CTRL , L, changegroupactive, f
bind = $mainMod CTRL Shift , H, movegroupwindow, b # move current tab backward in group
bind = $mainMod CTRL Shift , L, movegroupwindow, f # move current tab forward in group


# Screenshot/Screencapture
bind = $mainMod+Shift, S, exec, $scrPath/screenshot.sh s # partial screenshot capture
bind = $mainMod+Ctrl, P, exec, $scrPath/screenshot.sh sf # partial screenshot capture (frozen screen)
bind = $mainMod+Alt, P, exec, $scrPath/screenshot.sh m # monitor screenshot capture
bind = , Print, exec, $scrPath/screenshot.sh p # all monitors screenshot capture

# Custom scripts
bind = $mainMod+Alt, G, exec, $scrPath/gamemode.sh # disable hypr effects for gamemode
bind = $mainMod+Alt, Right, exec, $scrPath/swwwallpaper.sh -n # next wallpaper
bind = $mainMod+Alt, Left, exec, $scrPath/swwwallpaper.sh -p # previous wallpaper
bind = $mainMod+Alt, Up, exec, $scrPath/wbarconfgen.sh n # next waybar mode
bind = $mainMod+Alt, Down, exec, $scrPath/wbarconfgen.sh p # previous waybar mode
bind = $mainMod+Shift, R, exec, pkill -x rofi || $scrPath/wallbashtoggle.sh -m # launch wallbash mode select menu
bind = $mainMod+Shift, T, exec, pkill -x rofi || $scrPath/themeselect.sh # launch theme select menu
bind = $mainMod+Shift, A, exec, pkill -x rofi || $scrPath/rofiselect.sh # launch select menu
bind = $mainMod+Shift, X, exec, pkill -x rofi || $scrPath/themestyle.sh # launch theme style select menu
bind = $mainMod+Shift, W, exec, pkill -x rofi || $scrPath/swwwallselect.sh # launch wallpaper select menu
bind = $mainMod, V, exec, pkill -x rofi || $scrPath/cliphist.sh c # launch clipboard
bind = $mainMod+Shift, V, exec, pkill -x rofi || $scrPath/cliphist.sh # launch clipboard Manager
bind = $mainMod, K, exec, $scrPath/keyboardswitch.sh # switch keyboard layout
bind = $mainMod, slash, exec, pkill -x rofi || $scrPath/keybinds_hint.sh c # launch keybinds hint
bind = $mainMod+Alt, A, exec, pkill -x rofi || $scrPath/animations.sh # launch animations Manager
bind = $mainMod+Alt, D, exec, $HOME/.local/share/bin/hypr-display-settings.py # launch Display & Mouse Settings GUI
bind = $mainMod+Alt, N, exec, python3 $HOME/.local/share/bin/nightlight-gui.py # launch Night Light GUI

# Move/Change window focus
bind = $mainMod, Left, movefocus, l
bind = $mainMod, Right, movefocus, r
bind = $mainMod, Up, movefocus, u
bind = $mainMod, Down, movefocus, d
bind = Alt, Tab, movefocus, d

# Switch workspaces
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod, 6, workspace, 6
bind = $mainMod, 7, workspace, 7
bind = $mainMod, 8, workspace, 8
bind = $mainMod, 9, workspace, 9
bind = $mainMod, 0, workspace, 10

# Switch workspaces to a relative workspace
bind = $mainMod+Ctrl, Right, workspace, r+1
bind = $mainMod+Ctrl, Left, workspace, r-1

# Move to the first empty workspace
bind = $mainMod+Ctrl, Down, workspace, empty 

# Resize windows
binde = $mainMod+Shift, Right, resizeactive, 30 0
binde = $mainMod+Shift, Left, resizeactive, -30 0
binde = $mainMod+Shift, Up, resizeactive, 0 -30
binde = $mainMod+Shift, Down, resizeactive, 0 30

# Move focused window to a workspace
bind = $mainMod+Shift, 1, movetoworkspace, 1
bind = $mainMod+Shift, 2, movetoworkspace, 2
bind = $mainMod+Shift, 3, movetoworkspace, 3
bind = $mainMod+Shift, 4, movetoworkspace, 4
bind = $mainMod+Shift, 5, movetoworkspace, 5
bind = $mainMod+Shift, 6, movetoworkspace, 6
bind = $mainMod+Shift, 7, movetoworkspace, 7
bind = $mainMod+Shift, 8, movetoworkspace, 8
bind = $mainMod+Shift, 9, movetoworkspace, 9
bind = $mainMod+Shift, 0, movetoworkspace, 10

# Move focused window to a relative workspace
bind = $mainMod+Ctrl+Alt, Right, movetoworkspace, r+1
bind = $mainMod+Ctrl+Alt, Left, movetoworkspace, r-1

# Move active window around current workspace with mainMod + SHIFT + CTRL [←→↑↓]
$moveactivewindow=grep -q "true" <<< $(hyprctl activewindow -j | jq -r .floating) && hyprctl dispatch moveactive
bindd = $mainMod SHIFT CTRL, left, Move activewindow left, exec, $moveactivewindow -30 0 || hyprctl dispatch movewindow l
bindd = $mainMod SHIFT CTRL, right, Move activewindow right, exec, $moveactivewindow 30 0 || hyprctl dispatch movewindow r
bindd = $mainMod SHIFT CTRL, up, Move activewindow up, exec, $moveactivewindow  0 -30 || hyprctl dispatch movewindow u
bindd = $mainMod SHIFT CTRL, down, Move activewindow down, exec, $moveactivewindow 0 30 || hyprctl dispatch movewindow d

# Scroll through existing workspaces
bind = $mainMod, mouse_down, workspace, e+1
bind = $mainMod, mouse_up, workspace, e-1

# Move/Resize focused window
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow
bindm = $mainMod, Z, movewindow
bindm = $mainMod, X, resizewindow

# Move/Switch to special workspace (scratchpad)
bind = $mainMod+Alt, S, movetoworkspacesilent, special
bind = $mainMod, S, togglespecialworkspace,

# Toggle focused window split
bind = $mainMod, J, layoutmsg, togglesplit

# Move focused window to a workspace silently
bind = $mainMod+Alt, 1, movetoworkspacesilent, 1
bind = $mainMod+Alt, 2, movetoworkspacesilent, 2
bind = $mainMod+Alt, 3, movetoworkspacesilent, 3
bind = $mainMod+Alt, 4, movetoworkspacesilent, 4
bind = $mainMod+Alt, 5, movetoworkspacesilent, 5
bind = $mainMod+Alt, 6, movetoworkspacesilent, 6
bind = $mainMod+Alt, 7, movetoworkspacesilent, 7
bind = $mainMod+Alt, 8, movetoworkspacesilent, 8
bind = $mainMod+Alt, 9, movetoworkspacesilent, 9
bind = $mainMod+Alt, 0, movetoworkspacesilent, 10
EOF

# --- WRITE ~/.config/hypr/windowrules.conf ---
echo -e "${CYAN}Writing ~/.config/hypr/windowrules.conf...${NC}"
cat << 'EOF' > "$HOME/.config/hypr/windowrules.conf"

# █░█░█ █ █▄░█ █▀▄ █▀█ █░█░█   █▀█ █░█ █░░ █▀▀ █▀
# ▀▄▀▄▀ █ █░▀█ █▄▀ █▄█ ▀▄▀▄▀   █▀▄ █▄█ █▄▄ ██▄ ▄█

# See https://wiki.hyprland.org/Configuring/Window-Rules/

windowrule = opacity 0.90 0.90, match:class ^(firefox)$
windowrule = opacity 0.90 0.90, match:class ^(Google-chrome)$
windowrule = opacity 0.90 0.90, match:class ^(Brave-browser)$
windowrule = opacity 0.80 0.80, match:class ^(code-oss)$
windowrule = opacity 0.80 0.80, match:class ^([Cc]ode)$
windowrule = opacity 0.80 0.80, match:class ^(code-url-handler)$
windowrule = opacity 0.80 0.80, match:class ^(code-insiders-url-handler)$
windowrule = opacity 0.80 0.80, match:class ^(kitty)$
windowrule = opacity 0.80 0.80, match:class ^(org.kde.dolphin)$
windowrule = opacity 0.80 0.80, match:class ^(org.kde.ark)$
windowrule = opacity 0.80 0.80, match:class ^(nwg-look)$
windowrule = opacity 0.80 0.80, match:class ^(qt5ct)$
windowrule = opacity 0.80 0.80, match:class ^(qt6ct)$
windowrule = opacity 0.80 0.80, match:class ^(kvantummanager)$
windowrule = opacity 0.80 0.70, match:class ^(org.pulseaudio.pavucontrol)$
windowrule = opacity 0.80 0.70, match:class ^(blueman-manager)$
windowrule = opacity 0.80 0.70, match:class ^(nm-applet)$
windowrule = opacity 0.80 0.70, match:class ^(nm-connection-editor)$
windowrule = opacity 0.80 0.70, match:class ^(org.kde.polkit-kde-authentication-agent-1)$
windowrule = opacity 0.80 0.70, match:class ^(polkit-gnome-authentication-agent-1)$
windowrule = opacity 0.80 0.70, match:class ^(org.freedesktop.impl.portal.desktop.gtk)$
windowrule = opacity 0.80 0.70, match:class ^(org.freedesktop.impl.portal.desktop.hyprland)$
windowrule = opacity 0.70 0.70, match:class ^([Ss]team)$
windowrule = opacity 0.70 0.70, match:class ^(steamwebhelper)$
windowrule = opacity 0.70 0.70, match:class ^([Ss]potify)$
windowrule = opacity 0.70 0.70, match:initial_title ^(Spotify Free)$
windowrule = opacity 0.70 0.70, match:initial_title ^(Spotify Premium)$

windowrule = opacity 0.90 0.90, match:class ^(com.github.rafostar.Clapper)$ # Clapper-Gtk
windowrule = opacity 0.80 0.80, match:class ^(com.github.tchx84.Flatseal)$ # Flatseal-Gtk
windowrule = opacity 0.80 0.80, match:class ^(hu.kramo.Cartridges)$ # Cartridges-Gtk
windowrule = opacity 0.80 0.80, match:class ^(com.obsproject.Studio)$ # Obs-Qt
windowrule = opacity 0.80 0.80, match:class ^(gnome-boxes)$ # Boxes-Gtk
windowrule = opacity 0.80 0.80, match:class ^(vesktop)$ # Vesktop
windowrule = opacity 0.80 0.80, match:class ^(discord)$ # Discord-Electron
windowrule = opacity 0.80 0.80, match:class ^(WebCord)$ # WebCord-Electron
windowrule = opacity 0.80 0.80, match:class ^(ArmCord)$ # ArmCord-Electron
windowrule = opacity 0.80 0.80, match:class ^(app.drey.Warp)$ # Warp-Gtk
windowrule = opacity 0.80 0.80, match:class ^(net.davidotek.pupgui2)$ # ProtonUp-Qt
windowrule = opacity 0.80 0.80, match:class ^(yad)$ # Protontricks-Gtk
windowrule = opacity 0.80 0.80, match:class ^(Signal)$ # Signal-Gtk
windowrule = opacity 0.80 0.80, match:class ^(io.github.alainm23.planify)$ # planify-Gtk
windowrule = opacity 0.80 0.80, match:class ^(io.gitlab.theevilskeleton.Upscaler)$ # Upscaler-Gtk
windowrule = opacity 0.80 0.80, match:class ^(com.github.unrud.VideoDownloader)$ # VideoDownloader-Gtk
windowrule = opacity 0.80 0.80, match:class ^(io.gitlab.adhami3310.Impression)$ # Impression-Gtk
windowrule = opacity 0.80 0.80, match:class ^(io.missioncenter.MissionCenter)$ # MissionCenter-Gtk
windowrule = opacity 0.95 0.95, match:class ^(com.hyde.nightlight)$ # Night Light GUI
windowrule = float 1,          match:class ^(com.hyde.nightlight)$ # Night Light GUI — float
windowrule = center 1,         match:class ^(com.hyde.nightlight)$ # Night Light GUI — center
windowrule = size 450 600,     match:class ^(com.hyde.nightlight)$ # Night Light GUI — size
windowrule = opacity 0.80 0.80, match:class ^(io.github.flattool.Warehouse)$ # Warehouse-Gtk

windowrule = float 1, match:class ^(org.kde.dolphin)$, match:title ^(Progress Dialog — Dolphin)$
windowrule = float 1, match:class ^(org.kde.dolphin)$, match:title ^(Copying — Dolphin)$
windowrule = float 1, match:title ^(About Mozilla Firefox)$
windowrule = float 1, match:class ^(firefox)$, match:title ^(Picture-in-Picture)$
windowrule = float 1, match:class ^(firefox)$, match:title ^(Library)$
windowrule = float 1, match:class ^(kitty)$, match:title ^(top)$
windowrule = float 1, match:class ^(kitty)$, match:title ^(btop)$
windowrule = float 1, match:class ^(kitty)$, match:title ^(htop)$
windowrule = float 1, match:class ^(vlc)$
windowrule = float 1, match:class ^(kvantummanager)$
windowrule = float 1, match:class ^(qt5ct)$
windowrule = float 1, match:class ^(qt6ct)$
windowrule = float 1, match:class ^(nwg-look)$
windowrule = float 1, match:class ^(org.kde.ark)$
windowrule = float 1, match:class ^(org.pulseaudio.pavucontrol)$
windowrule = float 1, match:class ^(blueman-manager)$
windowrule = float 1, match:class ^(nm-applet)$
windowrule = float 1, match:class ^(nm-connection-editor)$
windowrule = float 1, match:class ^(org.kde.polkit-kde-authentication-agent-1)$

windowrule = float 1, match:class ^(Signal)$ # Signal-Gtk
windowrule = float 1, match:class ^(com.github.rafostar.Clapper)$ # Clapper-Gtk
windowrule = float 1, match:class ^(app.drey.Warp)$ # Warp-Gtk
windowrule = float 1, match:class ^(net.davidotek.pupgui2)$ # ProtonUp-Qt
windowrule = float 1, match:class ^(yad)$ # Protontricks-Gtk
windowrule = float 1, match:class ^(eog)$ # Imageviewer-Gtk
windowrule = float 1, match:class ^(io.github.alainm23.planify)$ # planify-Gtk
windowrule = float 1, match:class ^(io.gitlab.theevilskeleton.Upscaler)$ # Upscaler-Gtk
windowrule = float 1, match:class ^(com.github.unrud.VideoDownloader)$ # VideoDownloader-Gkk
windowrule = float 1, match:class ^(io.gitlab.adhami3310.Impression)$ # Impression-Gtk
windowrule = float 1, match:class ^(io.missioncenter.MissionCenter)$ # MissionCenter-Gtk

# common modals
windowrule = float 1, match:title ^(Open)$
windowrule = float 1, match:title ^(Choose Files)$
windowrule = float 1, match:title ^(Save As)$
windowrule = float 1, match:title ^(Confirm to replace files)$
windowrule = float 1, match:title ^(File Operation Progress)$
windowrule = float 1, match:class ^(xdg-desktop-portal-gtk)$

# █░░ ▄▀█ █▄█ █▀▀ █▀█   █▀█ █░█ █░░ █▀▀ █▀
# █▄▄ █▀█ ░█░ ██▄ █▀▄   █▀▄ █▄█ █▄▄ ██▄ ▄█

layerrule = blur 1, match:namespace rofi
layerrule = ignore_alpha 1, match:namespace rofi
layerrule = blur 1, match:namespace notifications
layerrule = ignore_alpha 1, match:namespace notifications
layerrule = blur 1, match:namespace swaync-notification-window
layerrule = ignore_alpha 1, match:namespace swaync-notification-window
layerrule = blur 1, match:namespace swaync-control-center
layerrule = ignore_alpha 1, match:namespace swaync-control-center
layerrule = blur 1, match:namespace logout_dialog
EOF



# --- WRITE ~/.config/hypr/monitors.conf (DYNAMIC DETECTION) ---
echo -e "${CYAN}Dynamically detecting connected monitors...${NC}"

# Initialize arrays/variables
MONITOR_CONFIGS=""
WORKSPACE_RULES=""
MAIN_NAME=""
MAIN_WIDTH=1920
MAIN_HEIGHT=1080
MAIN_HZ=60
SIDE_NAME=""
SIDE_WIDTH=1920
SIDE_HEIGHT=1080
SIDE_HZ=60
SIDE_TRANSFORM=1
MAIN_TRANSFORM=0
OFFSET_X=0
OFFSET_Y=0

# Check if hyprctl is available and running
if command -v hyprctl &>/dev/null && hyprctl monitors &>/dev/null; then
    echo -e "${GREEN}Hyprland is running. Using hyprctl for dynamic monitor detection...${NC}"
    MONITORS_JSON=$(hyprctl monitors -j)
    
    SORTED_MONITORS=$(echo "$MONITORS_JSON" | jq 'map(. + {maxHz: ([.availableModes[] | capture("@(?<rate>[0-9.]+)Hz") | .rate | tonumber] | max | round)}) | sort_by(.maxHz)')
    NUM_MONITORS=$(echo "$SORTED_MONITORS" | jq '. | length')
    
    if [ "$NUM_MONITORS" -gt 0 ]; then
        if [ "$NUM_MONITORS" -gt 1 ]; then
            # Build list of connected monitors for user prompt
            MONITOR_LIST_ARGS=()
            for i in $(seq 0 $((NUM_MONITORS - 1))); do
                m_name=$(echo "$MONITORS_JSON" | jq -r ".[$i].name")
                m_w=$(echo "$MONITORS_JSON" | jq -r ".[$i].width")
                m_h=$(echo "$MONITORS_JSON" | jq -r ".[$i].height")
                m_hz=$(echo "$MONITORS_JSON" | jq -r ".[$i].refreshRate" | cut -d'.' -f1)
                m_model=$(echo "$MONITORS_JSON" | jq -r ".[$i].model // \"Display\"")
                MONITOR_LIST_ARGS+=("$m_name" "${m_w}x${m_h}@${m_hz}Hz ($m_model)")
            done

            SELECTED_PRIMARY=""
            if command -v zenity &>/dev/null && { [ -n "$WAYLAND_DISPLAY" ] || [ -n "$DISPLAY" ]; }; then
                SELECTED_PRIMARY=$(zenity --list \
                    --title="Primary Screen Selection" \
                    --text="Multiple monitors detected.\nWhich display is your PRIMARY screen?" \
                    --column="Monitor Port" \
                    --column="Details & Resolution" \
                    "${MONITOR_LIST_ARGS[@]}" \
                    --width=480 --height=320 2>/dev/null)
            fi

            if [ -n "$SELECTED_PRIMARY" ]; then
                MAIN_NAME="$SELECTED_PRIMARY"
                SIDE_NAME=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name != \"$MAIN_NAME\") | .name" | head -n 1)
            else
                # Default to highest refresh rate monitor
                MAIN_NAME=$(echo "$SORTED_MONITORS" | jq -r 'last | .name')
                SIDE_NAME=$(echo "$SORTED_MONITORS" | jq -r '.[0] | .name')
            fi

            # Ask position relative to secondary monitor (RIGHT or LEFT)
            PRIMARY_POSITION="RIGHT"
            if command -v zenity &>/dev/null && { [ -n "$WAYLAND_DISPLAY" ] || [ -n "$DISPLAY" ]; }; then
                POS_CHOICE=$(zenity --list \
                    --title="Primary Screen Placement" \
                    --text="Where is your PRIMARY screen ($MAIN_NAME) positioned relative to your secondary screen ($SIDE_NAME)?" \
                    --column="Position Option" \
                    "RIGHT (Primary screen is on the right of secondary screen)" \
                    "LEFT (Primary screen is on the left of secondary screen)" \
                    --width=520 --height=250 2>/dev/null)
                if [[ "$POS_CHOICE" =~ "LEFT" ]]; then
                    PRIMARY_POSITION="LEFT"
                fi
            fi

            # Ask SDDM Screen Target
            SELECTED_SDDM=""
            if command -v zenity &>/dev/null && { [ -n "$WAYLAND_DISPLAY" ] || [ -n "$DISPLAY" ]; }; then
                SELECTED_SDDM=$(zenity --list \
                    --title="SDDM Login Screen Display" \
                    --text="Which monitor should the SDDM Login Screen appear on?" \
                    --column="Display Port" \
                    --column="Details" \
                    "${MONITOR_LIST_ARGS[@]}" \
                    --width=480 --height=320 2>/dev/null)
            else
                echo -e "\n${YELLOW}Select which monitor should display the SDDM Login Screen:${NC}"
                for idx in "${!MONITOR_LIST_ARGS[@]}"; do
                    if [ $((idx % 2)) -eq 0 ]; then
                        echo -e "  [$((idx/2 + 1))] ${MONITOR_LIST_ARGS[idx]} - ${MONITOR_LIST_ARGS[idx+1]}"
                    fi
                done
                read -p "Enter choice [1-$NUM_MONITORS] (Default: 1): " sddm_choice
                sddm_choice="${sddm_choice:-1}"
                sel_idx=$(( (sddm_choice - 1) * 2 ))
                SELECTED_SDDM="${MONITOR_LIST_ARGS[sel_idx]}"
            fi

            if [ -n "$SELECTED_SDDM" ]; then
                sudo mkdir -p /etc/sddm.conf.d 2>/dev/null
                echo "$SELECTED_SDDM" | sudo tee /etc/sddm.conf.d/target_monitor >/dev/null 2>&1
                sudo chmod 644 /etc/sddm.conf.d/target_monitor 2>/dev/null

                if [ -f "$SCRIPT_DIR/sddm-screen-config.py" ]; then
                    python3 "$SCRIPT_DIR/sddm-screen-config.py" --set "$SELECTED_SDDM" &>/dev/null || true
                fi
                echo -e "${GREEN}[OK] SDDM login screen primary output set to $SELECTED_SDDM${NC}"
            fi

            # Ask Initial Boot Cursor Screen Target
            SELECTED_CURSOR=""
            if command -v zenity &>/dev/null && { [ -n "$WAYLAND_DISPLAY" ] || [ -n "$DISPLAY" ]; }; then
                SELECTED_CURSOR=$(zenity --list \
                    --title="Initial Boot Cursor Screen" \
                    --text="Which display should the mouse cursor default to on initial boot?" \
                    --column="Display Port" \
                    --column="Details" \
                    "${MONITOR_LIST_ARGS[@]}" \
                    --width=480 --height=320 2>/dev/null)
            else
                echo -e "\n${YELLOW}Select which display the mouse cursor should default to on boot:${NC}"
                for idx in "${!MONITOR_LIST_ARGS[@]}"; do
                    if [ $((idx % 2)) -eq 0 ]; then
                        echo -e "  [$((idx/2 + 1))] ${MONITOR_LIST_ARGS[idx]} - ${MONITOR_LIST_ARGS[idx+1]}"
                    fi
                done
                read -p "Enter choice [1-$NUM_MONITORS] (Default: 1): " cursor_choice
                cursor_choice="${cursor_choice:-1}"
                sel_idx=$(( (cursor_choice - 1) * 2 ))
                SELECTED_CURSOR="${MONITOR_LIST_ARGS[sel_idx]}"
            fi

            if [ -n "$SELECTED_CURSOR" ]; then
                if [ -f "$SCRIPT_DIR/setup-initial-cursor-screen.py" ]; then
                    python3 "$SCRIPT_DIR/setup-initial-cursor-screen.py" --set "$SELECTED_CURSOR" &>/dev/null || true
                fi
                echo -e "${GREEN}[OK] Boot cursor default screen set to $SELECTED_CURSOR${NC}"
            fi

            MAIN_HZ=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$MAIN_NAME\") | .refreshRate" | cut -d'.' -f1)
            MAIN_WIDTH=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$MAIN_NAME\") | .width")
            MAIN_HEIGHT=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$MAIN_NAME\") | .height")
            MAIN_TRANSFORM=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$MAIN_NAME\") | .transform // 0")

            SIDE_HZ=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$SIDE_NAME\") | .refreshRate" | cut -d'.' -f1)
            SIDE_WIDTH=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$SIDE_NAME\") | .width")
            SIDE_HEIGHT=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$SIDE_NAME\") | .height")
            SIDE_TRANSFORM=$(echo "$MONITORS_JSON" | jq -r ".[] | select(.name == \"$SIDE_NAME\") | .transform // 0")

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
            
            OFFSET_Y=$(( (ROTATED_SIDE_HEIGHT - ROTATED_MAIN_HEIGHT) / 2 ))
            [ $OFFSET_Y -lt 0 ] && OFFSET_Y=0

            if [ "$PRIMARY_POSITION" = "RIGHT" ]; then
                OFFSET_X=${ROTATED_SIDE_WIDTH}
                MONITOR_CONFIGS="monitor = ${MAIN_NAME},${MAIN_WIDTH}x${MAIN_HEIGHT}@${MAIN_HZ},${OFFSET_X}x${OFFSET_Y},1,transform,${MAIN_TRANSFORM}\n"
                MONITOR_CONFIGS="${MONITOR_CONFIGS}monitor = ${SIDE_NAME},${SIDE_WIDTH}x${SIDE_HEIGHT}@${SIDE_HZ},0x0,1,transform,${SIDE_TRANSFORM}"
            else
                OFFSET_X=${ROTATED_MAIN_WIDTH}
                MONITOR_CONFIGS="monitor = ${MAIN_NAME},${MAIN_WIDTH}x${MAIN_HEIGHT}@${MAIN_HZ},0x${OFFSET_Y},1,transform,${MAIN_TRANSFORM}\n"
                MONITOR_CONFIGS="${MONITOR_CONFIGS}monitor = ${SIDE_NAME},${SIDE_WIDTH}x${SIDE_HEIGHT}@${SIDE_HZ},${OFFSET_X}x0,1,transform,${SIDE_TRANSFORM}"
            fi
            
            # Workspace rules for dual-monitor
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
        else
            # Single monitor setup
            MAIN_NAME=$(echo "$SORTED_MONITORS" | jq -r 'last | .name')
            MAIN_HZ=$(echo "$SORTED_MONITORS" | jq -r 'last | .maxHz')
            MAIN_WIDTH=$(echo "$SORTED_MONITORS" | jq -r 'last | .width')
            MAIN_HEIGHT=$(echo "$SORTED_MONITORS" | jq -r 'last | .height')
            MONITOR_CONFIGS="monitor = ${MAIN_NAME},${MAIN_WIDTH}x${MAIN_HEIGHT}@${MAIN_HZ},0x0,1"
            WORKSPACE_RULES="# Workspace Rules\n"
            for w in {1..10}; do
                WORKSPACE_RULES="${WORKSPACE_RULES}workspace = ${w}, monitor:${MAIN_NAME}"
                [ $w -eq 1 ] && WORKSPACE_RULES="${WORKSPACE_RULES}, default:true"
                WORKSPACE_RULES="${WORKSPACE_RULES}\n"
            done
        fi
    fi
fi

# Fallback: If no monitor configs were generated (e.g. hyprctl not running), use DRM sysfs
if [ -z "$MONITOR_CONFIGS" ]; then
    echo -e "${YELLOW}Hyprland is not running or no monitors detected via hyprctl. Scanning /sys/class/drm/...${NC}"
    CONNECTED_DEVS=()
    for card in /sys/class/drm/card*-*; do
        if [ -f "$card/status" ] && [ "$(cat "$card/status")" = "connected" ]; then
            dev_name=$(basename "$card" | cut -d'-' -f2-)
            CONNECTED_DEVS+=("$dev_name")
        fi
    done
    
    NUM_DEVS=${#CONNECTED_DEVS[@]}
    if [ "$NUM_DEVS" -gt 0 ]; then
        # Take the first one as main
        MAIN_NAME="${CONNECTED_DEVS[0]}"
        MAIN_WIDTH=1920
        MAIN_HEIGHT=1080
        MAIN_HZ=60
        
        if [ "$NUM_DEVS" -gt 1 ]; then
            SIDE_NAME="${CONNECTED_DEVS[1]}"
            SIDE_HZ=60
            
            # Read native resolution for the side monitor to calculate offsets
            # Fallback to default if files are missing
            SIDE_MODE=$(head -n 1 /sys/class/drm/card*-${SIDE_NAME}/modes 2>/dev/null)
            SIDE_WIDTH=$(echo "$SIDE_MODE" | cut -d'x' -f1)
            SIDE_HEIGHT=$(echo "$SIDE_MODE" | cut -d'x' -f2)
            
            SIDE_WIDTH=${SIDE_WIDTH:-1920}
            SIDE_HEIGHT=${SIDE_HEIGHT:-1080}
            
            if [ "$SIDE_TRANSFORM" -eq 1 ] || [ "$SIDE_TRANSFORM" -eq 3 ]; then
                ROTATED_SIDE_WIDTH=${SIDE_HEIGHT}
                ROTATED_SIDE_HEIGHT=${SIDE_WIDTH}
            else
                ROTATED_SIDE_WIDTH=${SIDE_WIDTH}
                ROTATED_SIDE_HEIGHT=${SIDE_HEIGHT}
            fi
            
            if [ "$MAIN_TRANSFORM" -eq 1 ] || [ "$MAIN_TRANSFORM" -eq 3 ]; then
                ROTATED_MAIN_WIDTH=1080
                ROTATED_MAIN_HEIGHT=1920
            else
                ROTATED_MAIN_WIDTH=1920
                ROTATED_MAIN_HEIGHT=1080
            fi
            
            OFFSET_X=${ROTATED_SIDE_WIDTH}
            OFFSET_Y=$(( (ROTATED_SIDE_HEIGHT - ROTATED_MAIN_HEIGHT) / 2 ))
            [ $OFFSET_Y -lt 0 ] && OFFSET_Y=0
            
            MONITOR_CONFIGS="monitor = ${MAIN_NAME},preferred,${OFFSET_X}x${OFFSET_Y},1,transform,${MAIN_TRANSFORM}\n"
            MONITOR_CONFIGS="${MONITOR_CONFIGS}monitor = ${SIDE_NAME},preferred,0x0,1,transform,${SIDE_TRANSFORM}"
            
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
        else
            # Single monitor fallback
            MONITOR_CONFIGS="monitor = ${MAIN_NAME},preferred,auto,1"
            WORKSPACE_RULES="# Workspace Rules\n"
            for w in {1..10}; do
                WORKSPACE_RULES="${WORKSPACE_RULES}workspace = ${w}, monitor:${MAIN_NAME}"
                [ $w -eq 1 ] && WORKSPACE_RULES="${WORKSPACE_RULES}, default:true"
                WORKSPACE_RULES="${WORKSPACE_RULES}\n"
            done
        fi
    else
        # Extreme fallback
        MONITOR_CONFIGS="monitor = ,preferred,auto,1"
        WORKSPACE_RULES="# Workspace Rules\nworkspace = 1, monitor:, default:true"
    fi
fi

# Override offsets and transforms if they already exist in the user's config (so we don't reset them)
if [ -n "$SIDE_NAME" ] && [ -f "$HOME/.config/hypr/monitors.conf" ]; then
    # Match the side monitor config line to extract transform value if it exists
    EXISTING_SIDE_LINE=$(grep -E "^\s*monitor\s*=\s*${SIDE_NAME}\s*," "$HOME/.config/hypr/monitors.conf" | head -n 1)
    if [ -n "$EXISTING_SIDE_LINE" ]; then
        if [[ "$EXISTING_SIDE_LINE" =~ transform,([0-7]) ]]; then
            SIDE_TRANSFORM="${BASH_REMATCH[1]}"
            echo -e "${GREEN}[INFO] Preserving existing monitor transform: ${SIDE_TRANSFORM}${NC}"
        fi
    fi

    # Match the main monitor config line to extract transform value if it exists
    EXISTING_MAIN_LINE=$(grep -E "^\s*monitor\s*=\s*${MAIN_NAME}\s*," "$HOME/.config/hypr/monitors.conf" | head -n 1)
    if [ -n "$EXISTING_MAIN_LINE" ]; then
        if [[ "$EXISTING_MAIN_LINE" =~ transform,([0-7]) ]]; then
            MAIN_TRANSFORM="${BASH_REMATCH[1]}"
            echo -e "${GREEN}[INFO] Preserving existing main monitor transform: ${MAIN_TRANSFORM}${NC}"
        fi
    fi

    # Match the main monitor config line to extract XxY coordinates
    EXISTING_LINE=$(grep -E "^\s*monitor\s*=\s*${MAIN_NAME}\s*," "$HOME/.config/hypr/monitors.conf" | head -n 1)
    if [ -n "$EXISTING_LINE" ]; then
        POS_FIELD=$(echo "$EXISTING_LINE" | cut -d',' -f3 | tr -d '[:space:]')
        if [[ "$POS_FIELD" =~ ^([0-9]+)x([0-9]+)$ ]]; then
            EXISTING_X="${BASH_REMATCH[1]}"
            EXISTING_Y="${BASH_REMATCH[2]}"
            echo -e "${GREEN}[INFO] Preserving existing monitor offset: ${EXISTING_X}x${EXISTING_Y}${NC}"
            OFFSET_X=$EXISTING_X
            OFFSET_Y=$EXISTING_Y
            
            # Recalculate dimensions based on the transform
            if [ "$SIDE_TRANSFORM" -eq 1 ] || [ "$SIDE_TRANSFORM" -eq 3 ]; then
                ROTATED_SIDE_WIDTH=${SIDE_HEIGHT}
            else
                ROTATED_SIDE_WIDTH=${SIDE_WIDTH}
            fi
            OFFSET_X=${ROTATED_SIDE_WIDTH}
            
            MONITOR_CONFIGS="monitor = ${MAIN_NAME},${MAIN_WIDTH}x${MAIN_HEIGHT}@${MAIN_HZ},${OFFSET_X}x${OFFSET_Y},1,transform,${MAIN_TRANSFORM}\n"
            MONITOR_CONFIGS="${MONITOR_CONFIGS}monitor = ${SIDE_NAME},${SIDE_WIDTH}x${SIDE_HEIGHT}@${SIDE_HZ},0x0,1,transform,${SIDE_TRANSFORM}"
        fi
    fi
fi

# Write to file
mkdir -p "$HOME/.config/hypr"
cat << MONEOF > "$HOME/.config/hypr/monitors.conf"
# █▀▄▀█ █▀█ █▄░█ █ ▀█▀ █▀█ █▀█ █▀
# █░▀░█ █▄█ █░▀█ █ ░█░ █▄█ █▀▄ ▄█
# Dynamically generated by restore_my_setup.sh

$(echo -e "$MONITOR_CONFIGS")

$(echo -e "$WORKSPACE_RULES")
MONEOF
echo -e "${GREEN}[OK] Dynamic monitors.conf generated successfully!${NC}"

# Calibrate monitor alignment if dual monitor detected
if [ -n "$SIDE_NAME" ]; then
    # Ensure scripts are copied to local bin first
    mkdir -p "$HOME/.local/share/bin"
    if [ -f "$SCRIPT_DIR/monitor-alignment.sh" ]; then
        cp "$SCRIPT_DIR/monitor-alignment.sh" "$HOME/.local/share/bin/" 2>/dev/null || true
        chmod +x "$HOME/.local/share/bin/monitor-alignment.sh" 2>/dev/null || true
    fi

    # Only run calibration if display environment is active (GUI mode)
    if [ -n "$WAYLAND_DISPLAY" ] || [ -n "$DISPLAY" ]; then
        echo -e "${BLUE}${BOLD}Dual monitors detected. Prompting for mouse alignment calibration...${NC}"
        
        # Prompt the user if they want to calibrate
        if zenity --question \
            --title="Mouse Path Alignment Calibration" \
            --text="Dual monitors detected.\nWould you like to calibrate the vertical alignment of the mouse path or control screen orientations now?" \
            --ok-label="Calibrate Now" \
            --cancel-label="Skip" \
            --width=400 2>/dev/null; then
            
            ALIGN_SCRIPT=""
            if [ -f "$SCRIPT_DIR/monitor-alignment.sh" ]; then
                ALIGN_SCRIPT="$SCRIPT_DIR/monitor-alignment.sh"
            elif [ -f "$HOME/cachy-os-config-related/monitor-alignment.sh" ]; then
                ALIGN_SCRIPT="$HOME/cachy-os-config-related/monitor-alignment.sh"
            elif [ -f "$HOME/.local/share/bin/monitor-alignment.sh" ]; then
                ALIGN_SCRIPT="$HOME/.local/share/bin/monitor-alignment.sh"
            fi

            if [ -n "$ALIGN_SCRIPT" ]; then
                bash "$ALIGN_SCRIPT"
            else
                echo -e "${RED}[ERROR] monitor-alignment.sh not found!${NC}"
            fi
        fi
    fi
fi

# Touchpad scrolling behavior setup (Windows vs Linux default)
IS_LAPTOP=false
if [ -f /sys/class/dmi/id/chassis_type ]; then
    CHASSIS=$(cat /sys/class/dmi/id/chassis_type)
    if [[ "$CHASSIS" =~ ^(8|9|10|11|14)$ ]]; then
        IS_LAPTOP=true
    fi
fi
if [ -d /sys/class/power_supply ] && ls /sys/class/power_supply/ | grep -q "^BAT"; then
    IS_LAPTOP=true
fi

HAS_TOUCHPAD=false
if grep -iq "touchpad" /proc/bus/input/devices 2>/dev/null; then
    HAS_TOUCHPAD=true
fi

if [ "$IS_LAPTOP" = "true" ] || [ "$HAS_TOUCHPAD" = "true" ]; then
    echo -e "\n${YELLOW}[PROMPT] Laptop/Touchpad detected on this device.${NC}"
    read -p "Touch pad like windows? (y/n): " tp_windows_choice
    if [[ "$tp_windows_choice" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Configuring touchpad to behave like Windows (Standard Scrolling)...${NC}"
        mkdir -p "$HOME/.config/hypr"
        touch "$HOME/.config/hypr/userprefs.conf"
        if grep -q "touchpad" "$HOME/.config/hypr/userprefs.conf"; then
            if grep -q "natural_scroll" "$HOME/.config/hypr/userprefs.conf"; then
                sed -i 's/natural_scroll.*/natural_scroll = false/' "$HOME/.config/hypr/userprefs.conf"
            else
                sed -i '/touchpad {/a \ \ \ \ \ \ \ \ natural_scroll = false' "$HOME/.config/hypr/userprefs.conf"
            fi
        else
            cat << 'EOF' >> "$HOME/.config/hypr/userprefs.conf"

input {
    touchpad {
        natural_scroll = false
    }
}
EOF
        fi
        hyprctl keyword input:touchpad:natural_scroll false &>/dev/null || true
        echo -e "${GREEN}[OK] Touchpad scrolling configured like Windows successfully!${NC}"
    else
        echo -e "${BLUE}[INFO] Keeping Linux natural scrolling default.${NC}"
    fi
fi

# --- WRITE ~/.config/hypr/nvidia.conf ---
echo -e "${CYAN}Writing ~/.config/hypr/nvidia.conf...${NC}"
if [ "$GPU_VENDOR" = "nvidia" ]; then
    cat << 'EOF' > "$HOME/.config/hypr/nvidia.conf"

# █▄░█ █░█ █ █▀▄ █ ▄▀█
# █░▀█ ▀▄▀ █ █▄▀ █ █▀█

# See https://wiki.hyprland.org/Nvidia/

env = LIBVA_DRIVER_NAME,nvidia
env = GBM_BACKEND,nvidia-drm
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = __GL_VRR_ALLOWED,1
env = NVD_BACKEND,direct

cursor {
    no_hardware_cursors = true
}
EOF
else
    cat << 'EOF' > "$HOME/.config/hypr/nvidia.conf"
# Sourced for AMD/Intel GPU - No Nvidia environment variables needed.
EOF
fi

# --- WRITE ~/.config/hypr/sync_cursor.sh ---
echo -e "${CYAN}Writing ~/.config/hypr/sync_cursor.sh...${NC}"
cat << 'EOF' > "$HOME/.config/hypr/sync_cursor.sh"
#!/usr/bin/env bash

THEME="$1"
SIZE="${2:-20}"

if [ -z "$THEME" ]; then
    exit 0
fi

# Update GTK 3 settings.ini
GTK3_FILE="$HOME/.config/gtk-3.0/settings.ini"
if [ -f "$GTK3_FILE" ]; then
    # Ensure [Settings] header exists
    if ! grep -q "\[Settings\]" "$GTK3_FILE"; then
        echo -e "[Settings]\n" > "$GTK3_FILE"
    fi
    # Update theme name
    if grep -q "gtk-cursor-theme-name=" "$GTK3_FILE"; then
        sed -i "s/gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$THEME/g" "$GTK3_FILE"
    else
        echo "gtk-cursor-theme-name=$THEME" >> "$GTK3_FILE"
    fi
    # Update size
    if grep -q "gtk-cursor-theme-size=" "$GTK3_FILE"; then
        sed -i "s/gtk-cursor-theme-size=.*/gtk-cursor-theme-size=$SIZE/g" "$GTK3_FILE"
    else
        echo "gtk-cursor-theme-size=$SIZE" >> "$GTK3_FILE"
    fi
fi

# Update GTK 4 settings.ini
GTK4_FILE="$HOME/.config/gtk-4.0/settings.ini"
mkdir -p "$HOME/.config/gtk-4.0"
if [ ! -f "$GTK4_FILE" ]; then
    echo -e "[Settings]\n" > "$GTK4_FILE"
fi
# Update theme name
if grep -q "gtk-cursor-theme-name=" "$GTK4_FILE"; then
    sed -i "s/gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$THEME/g" "$GTK4_FILE"
else
    echo "gtk-cursor-theme-name=$THEME" >> "$GTK4_FILE"
fi
# Update size
if grep -q "gtk-cursor-theme-size=" "$GTK4_FILE"; then
    sed -i "s/gtk-cursor-theme-size=.*/gtk-cursor-theme-size=$SIZE/g" "$GTK4_FILE"
else
    echo "gtk-cursor-theme-size=$SIZE" >> "$GTK4_FILE"
fi

# Update index.theme
INDEX_FILE="$HOME/.icons/default/index.theme"
mkdir -p "$HOME/.icons/default"
if [ ! -f "$INDEX_FILE" ]; then
    echo -e "[Icon Theme]\nName=Default\nComment=Default Cursor Theme" > "$INDEX_FILE"
fi
if grep -q "Inherits=" "$INDEX_FILE"; then
    sed -i "s/Inherits=.*/Inherits=$THEME/g" "$INDEX_FILE"
else
    echo "Inherits=$THEME" >> "$INDEX_FILE"
fi
EOF
chmod +x "$HOME/.config/hypr/sync_cursor.sh"

# --- WRITE ~/.config/hypr/close_kitty_or_copy.sh ---
echo -e "${CYAN}Writing ~/.config/hypr/close_kitty_or_copy.sh...${NC}"
cat << 'EOF' > "$HOME/.config/hypr/close_kitty_or_copy.sh"
#!/bin/bash

# Fetch the active window details in JSON format
ACTIVE_WINDOW=$(hyprctl activewindow -j)

# Extract class and address
CLASS=$(echo "$ACTIVE_WINDOW" | jq -r '.class')
ADDRESS=$(echo "$ACTIVE_WINDOW" | jq -r '.address')

# If the active window is Kitty, close it. Otherwise, pass the Ctrl+C shortcut through.
if [ "$CLASS" = "kitty" ]; then
    hyprctl dispatch closewindow address:"$ADDRESS"
else
    hyprctl dispatch sendshortcut "CTRL, C, address:$ADDRESS"
fi
EOF
chmod +x "$HOME/.config/hypr/close_kitty_or_copy.sh"

# --- WRITE ~/.config/kitty/kitty.conf ---
echo -e "${CYAN}Writing ~/.config/kitty/kitty.conf...${NC}"
cat << 'EOF' > "$HOME/.config/kitty/kitty.conf"
font_family      CaskaydiaCove Nerd Font Mono
bold_font        auto
italic_font      auto
bold_italic_font auto
enable_audio_bell no
font_size 11.0
text_composition_strategy legacy
window_padding_width 25
include ~/.cache/wal/colors-kitty.conf
cursor_trail 1
background_opacity 0.40
#hide_window_decorations yes
#confirm_os_window_close 0

# initially empty, to be configured by user and remains static
include userprefs.conf

# Note: as userprefs.conf is included at the end, settings configured in this file will override the defaults
EOF

# --- WRITE ~/.config/kitty/userprefs.conf ---
echo -e "${CYAN}Writing ~/.config/kitty/userprefs.conf...${NC}"
cat << 'EOF' > "$HOME/.config/kitty/userprefs.conf"
# Ctrl+Shift+C/V for copy/paste in terminal (default)
# Ctrl+C copies if text selected, otherwise sends interrupt
map ctrl+c copy_or_interrupt
map ctrl+v paste_from_clipboard

# Ctrl+Backspace to delete the whole word like Windows
map ctrl+backspace send_text all \x17

# Smooth Cursor Trail Animations
cursor_trail 10
cursor_trail_decay 0.1 0.45
cursor_trail_start_threshold 0

font_size 13.0
EOF

# --- WRITE ~/.config/waybar/config.jsonc ---
echo -e "${CYAN}Writing ~/.config/waybar/config.jsonc...${NC}"
cat << 'EOF' > "$HOME/.config/waybar/config.jsonc"
//   --// waybar config generated by wbarconfgen.sh //--   //

{
// sourced from header module //

    "layer": "top",
    "output": [ "*" ],
    "position": "top",
    "mod": "dock",
    "height": 30,
    "exclusive": true,
    "passthrough": false,
    "gtk-layer-shell": true,
    "reload_style_on_change": true,


// positions generated based on config.ctl //

	"modules-left": ["custom/padd","hyprland/workspaces","custom/padd"],
	"modules-center": ["custom/padd","clock","custom/separator","custom/prayer","custom/padd"],
	"modules-right": ["custom/padd","pulseaudio","custom/separator","memory","custom/separator","cpu","custom/padd"],


// sourced from modules based on config.ctl //

    "hyprland/workspaces": {
        "disable-scroll": true,
        "rotate": 0,
        "all-outputs": true,
        "active-only": false,
        "on-click": "activate",
        "disable-scroll": false,
        "on-scroll-up": "hyprctl dispatch workspace -1",
        "on-scroll-down": "hyprctl dispatch workspace +1",
        "format": "{name} {windows}",
        "format-window-separator": " ",
        "window-rewrite-default": "",
        "window-rewrite": {
            "class<kitty>": "",
            "class<firefox>": "",
            "class<chromium>": "",
            "class<google-chrome>": "",
            "class<dolphin>": "󰉋",
            "class<thunar>": "󰉋",
            "class<vs-code-oss>": "󰨞",
            "class<code-oss>": "󰨞",
            "class<vscode>": "󰨞",
            "class<discord>": "󰙯",
            "class<spotify>": "",
            "class<steam>": "",
            "class<vlc>": "󰕼",
            "class<mpv>": "󰕼"
        },
        "persistent-workspaces": {
            "1": [],
            "2": [],
            "3": []
        }
    },
    "clock": {
        "format": "{:%I:%M %p}",
        "rotate": 0,
        "format-alt": "{:%R 󰃭 %d·%m·%y}",
        "tooltip-format": "<span>{calendar}</span>",
        "calendar": {
            "mode": "month",
            "mode-mon-col": 3,
            "on-scroll": 1,
            "on-click-right": "mode",
            "format": {
                "months": "<span color='#ffead3'><b>{}</b></span>",
                "weekdays": "<span color='#ffcc66'><b>{}</b></span>",
                "today": "<span color='#ff6699'><b>{}</b></span>"
            }
        },
        "actions": {
            "on-click-right": "mode",
            "on-click-forward": "tz_up",
            "on-click-backward": "tz_down",
            "on-scroll-up": "shift_up",
            "on-scroll-down": "shift_down"
        }
    },

    "custom/prayer": {
        "format": "{}",
        "exec": "$HOME/.local/share/bin/prayer_times.py",
        "interval": 1,
        "tooltip": false
    },

"pulseaudio": {
    "format": "{icon} {volume}",
    "rotate": 0,
    "format-muted": "婢",
    "on-click": "pavucontrol -t 3",
    "on-click-right": "volumecontrol.sh -s ''",
    "on-click-middle": "volumecontrol.sh -o m",
    "on-scroll-up": "volumecontrol.sh -o i",
    "on-scroll-down": "volumecontrol.sh -o d",
    "tooltip-format": "{icon} {desc} // {volume}%",
    "scroll-step": 5,
    "format-icons": {
        "headphone": "",
        "hands-free": "",
        "headset": "",
        "phone": "",
        "portable": "",
        "car": "",
        "default": ["", "", ""]
    }
},

"pulseaudio#microphone": {
    "format": "{format_source}",
    "rotate": 0,
    "format-source": "",
    "format-source-muted": "",
    "on-click": "pavucontrol -t 4",
    "on-click-middle": "volumecontrol.sh -i m",
    "on-scroll-up": "volumecontrol.sh -i i",
    "on-scroll-down": "volumecontrol.sh -i d",
    "tooltip-format": "{format_source} {source_desc} // {source_volume}%",
    "scroll-step": 5
},

    "custom/separator": {
        "format": "|",
        "interval": "once",
        "tooltip": false
    },
    "memory": {
        "states": {
            "c": 90, // critical
            "h": 60, // high
            "m": 30, // medium
        },
        "interval": 30,
        "format": "󰾆 {used}GB",
        "rotate": 0,
        "format-m": "󰾅 {used}GB",
        "format-h": "󰓅 {used}GB",
        "format-c": " {used}GB",
        "format-alt": "󰾆 {percentage}%",
        "max-length": 10,
        "tooltip": true,
        "tooltip-format": "󰾆 {percentage}%\n {used:0.1f}GB/{total:0.1f}GB"
    },

    "cpu": {
        "interval": 10,
        "format": "󰍛 {usage}%",
        "rotate": 0,
        "format-alt": "{icon0}{icon1}{icon2}{icon3}",
        "format-icons": ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    },


// modules for padding //

    "custom/l_end": {
        "format": " ",
        "interval" : "once",
        "tooltip": false
    },

    "custom/r_end": {
        "format": " ",
        "interval" : "once",
        "tooltip": false
    },

    "custom/sl_end": {
        "format": " ",
        "interval" : "once",
        "tooltip": false
    },

    "custom/sr_end": {
        "format": " ",
        "interval" : "once",
        "tooltip": false
    },

    "custom/rl_end": {
        "format": " ",
        "interval" : "once",
        "tooltip": false
    },

    "custom/rr_end": {
        "format": " ",
        "interval" : "once",
        "tooltip": false
    },

    "custom/padd": {
        "format": "  ",
        "interval" : "once",
        "tooltip": false
    }

}


EOF

# --- WRITE ~/.config/waybar/style.css ---
echo -e "${CYAN}Writing ~/.config/waybar/style.css...${NC}"
cat << 'EOF' > "$HOME/.config/waybar/style.css"
* {
    border: none;
    border-radius: 0px;
    font-family: "JetBrainsMono Nerd Font";
    font-weight: bold;
    font-size: 12px;
    min-height: 10px;
}

@import "theme.css";

window#waybar {
    background: @main-bg;
}

.modules-left {
    margin-left: 45px;
}

.modules-right {
    margin-right: 45px;
}

tooltip {
    background: @main-bg;
    color: @main-fg;
    border-radius: 0px;
    border-width: 0px;
}

#workspaces button {
    box-shadow: none;
	text-shadow: none;
    padding: 0px;
    border-radius: 0px;
    margin-top: 3px;
    margin-bottom: 3px;
    margin-left: 0px;
    padding-left: 3px;
    padding-right: 3px;
    margin-right: 0px;
    color: @main-fg;
    animation: ws_normal 20s ease-in-out 1;
}

#workspaces button.active {
    background: @wb-act-bg;
    color: @wb-act-fg;
    margin-left: 3px;
    padding-left: 8px;
    padding-right: 8px;
    margin-right: 3px;
    animation: ws_active 20s ease-in-out 1;
    transition: all 0.4s cubic-bezier(.55,-0.68,.48,1.682);
}

#workspaces button:hover {
    background: @wb-hvr-bg;
    color: @wb-hvr-fg;
    animation: ws_hover 20s ease-in-out 1;
    transition: all 0.3s cubic-bezier(.55,-0.68,.48,1.682);
}

#taskbar button {
    box-shadow: none;
	text-shadow: none;
    padding: 0px;
    border-radius: 0px;
    margin-top: 3px;
    margin-bottom: 3px;
    margin-left: 0px;
    padding-left: 3px;
    padding-right: 3px;
    margin-right: 0px;
    color: @wb-color;
    animation: tb_normal 20s ease-in-out 1;
}

#taskbar button.active {
    background: @wb-act-bg;
    color: @wb-act-color;
    margin-left: 3px;
    padding-left: 15px;
    padding-right: 15px;
    margin-right: 3px;
    animation: tb_active 20s ease-in-out 1;
    transition: all 0.4s cubic-bezier(.55,-0.68,.48,1.682);
}

#taskbar button:hover {
    background: @wb-hvr-bg;
    color: @wb-hvr-color;
    animation: tb_hover 20s ease-in-out 1;
    transition: all 0.3s cubic-bezier(.55,-0.68,.48,1.682);
}

#tray menu * {
    min-height: 16px
}

#tray menu separator {
    min-height: 10px
}

#backlight,
#battery,
#bluetooth,
#custom-cava,
#custom-cliphist,
#clock,
#custom-prayer,
#custom-cpuinfo,
#cpu,
#custom-github_hyprdots,
#custom-gpuinfo,
#idle_inhibitor,
#custom-keybindhint,
#language,
#memory,
#mpris,
#network,
#custom-notifications,
#custom-power,
#privacy,
#pulseaudio,
#custom-spotify,
#taskbar,
#custom-theme,
#tray,
#custom-updates,
#custom-wallchange,
#custom-wbar,
#window,
#workspaces,
#custom-l_end,
#custom-r_end,
#custom-sl_end,
#custom-sr_end,
#custom-rl_end,
#custom-rr_end {
    color: @main-fg;
    background: transparent;
    opacity: 1;
    margin: 5px 0px 5px 0px;
    padding-left: 12px;
    padding-right: 12px;
}

#workspaces,
#taskbar {
    padding: 0px;
}

#custom-r_end {
    border-radius: 0px;
    margin-right: 11px;
    padding-right: 3px;
}

#custom-l_end {
    border-radius: 0px;
    margin-left: 11px;
    padding-left: 3px;
}

#custom-sr_end {
    border-radius: 0px;
    margin-right: 11px;
    padding-right: 3px;
}

#custom-sl_end {
    border-radius: 0px;
    margin-left: 11px;
    padding-left: 3px;
}

#custom-rr_end {
    border-radius: 0px;
    margin-right: 11px;
    padding-right: 3px;
}

#custom-rl_end {
    border-radius: 0px;
    margin-left: 11px;
    padding-left: 3px;
}


EOF
cp "$HOME/.config/waybar/style.css" "$HOME/.config/waybar/modules/style.css"

# --- WRITE ~/.config/waybar/theme.css ---
echo -e "${CYAN}Writing ~/.config/waybar/theme.css...${NC}"
cat << 'EOF' > "$HOME/.config/waybar/theme.css"
/* To enable blur please make sure alpha is greater than 0 */
@define-color bar-bg rgba(0, 0, 0, 0.1); 

@define-color main-bg #475437;
@define-color main-fg #b5cc97;

@define-color wb-act-bg #668f31;
@define-color wb-act-fg #c2d89c;

@define-color wb-hvr-bg #c6eb6f;
@define-color wb-hvr-fg #c0fc47;
EOF

# --- WRITE ~/.config/waybar/config.ctl ---
echo -e "${CYAN}Writing ~/.config/waybar/config.ctl...${NC}"
cat << 'EOF' > "$HOME/.config/waybar/config.ctl"
0|28|bottom|( cpu memory custom/cpuinfo custom/gpuinfo ) ( idle_inhibitor clock custom/prayer )|( hyprland/workspaces hyprland/window )|( backlight network pulseaudio pulseaudio#microphone custom/updates custom/keybindhint ) ( privacy tray battery ) ( custom/wallchange custom/theme custom/wbar custom/cliphist custom/power )
0|28|top|( cpu memory custom/cpuinfo custom/gpuinfo ) ( idle_inhibitor clock custom/prayer )|( hyprland/workspaces hyprland/window )|( backlight network pulseaudio pulseaudio#microphone custom/updates custom/keybindhint ) ( privacy tray battery ) ( custom/wallchange custom/theme custom/wbar custom/cliphist custom/power )
0|28|bottom|( cpu memory custom/cpuinfo custom/gpuinfo ) ( idle_inhibitor clock custom/prayer ) ( hyprland/workspaces )|( hyprland/window )|( backlight network pulseaudio pulseaudio#microphone custom/updates custom/keybindhint ) ( privacy tray battery ) ( custom/wallchange custom/theme custom/wbar custom/cliphist custom/power )
0|28|top|( cpu memory custom/cpuinfo ) ( idle_inhibitor clock custom/prayer ) ( hyprland/workspaces )|( hyprland/window )|( backlight network pulseaudio pulseaudio#microphone custom/updates custom/keybindhint ) ( privacy tray battery ) ( custom/wallchange custom/theme custom/wbar custom/cliphist custom/power )
0| 0|bottom|( hyprland/workspaces hyprland/window )|( idle_inhibitor clock )|( cpu memory custom/cpuinfo custom/gpuinfo ) ( backlight network pulseaudio pulseaudio#microphone custom/updates custom/keybindhint ) ( privacy tray battery ) ( custom/wallchange custom/theme custom/wbar custom/cliphist custom/power )
0| 0|top|( hyprland/workspaces hyprland/window )|( idle_inhibitor clock )|( cpu memory custom/cpuinfo custom/gpuinfo ) ( backlight network pulseaudio pulseaudio#microphone custom/updates custom/keybindhint ) ( privacy tray battery ) ( custom/wallchange custom/theme custom/wbar custom/cliphist custom/power )
0|31|bottom|( custom/power custom/cliphist custom/wbar custom/theme custom/wallchange ) ( wlr/taskbar custom/spotify ) |( idle_inhibitor clock )|( privacy tray battery ) ( backlight network pulseaudio pulseaudio#microphone custom/notifications custom/keybindhint )
0|31|left|( custom/power custom/cliphist custom/wbar custom/theme custom/wallchange ) ( wlr/taskbar custom/spotify ) |( idle_inhibitor clock )|( privacy tray battery ) ( backlight network pulseaudio pulseaudio#microphone custom/keybindhint )
0|38|top|( custom/power custom/cliphist custom/wbar custom/theme custom/wallchange ) ( hyprland/workspaces wlr/taskbar custom/spotify )|( idle_inhibitor clock )|( privacy tray battery ) ( backlight network pulseaudio pulseaudio#microphone custom/keybindhint )
0|31|right|( custom/power custom/cliphist custom/wbar custom/theme custom/wallchange ) ( wlr/taskbar custom/spotify ) |( idle_inhibitor clock )|( privacy tray battery ) ( backlight network pulseaudio pulseaudio#microphone custom/keybindhint )
0|32|bottom||( custom/power ) ( privacy tray battery ) ( wlr/taskbar idle_inhibitor clock ) ( custom/cliphist ) ( custom/wbar ) ( custom/wallchange ) ( custom/theme )|
0|32|left||( custom/power ) ( privacy tray battery ) ( wlr/taskbar idle_inhibitor clock ) ( custom/cliphist ) ( custom/wbar ) ( custom/wallchange ) ( custom/theme )|
0|32|top||( custom/power ) ( privacy tray battery ) ( wlr/taskbar idle_inhibitor clock ) ( custom/cliphist ) ( custom/wbar ) ( custom/wallchange ) ( custom/theme )|
0|32|right||( custom/power ) ( privacy tray battery ) ( wlr/taskbar idle_inhibitor clock ) ( custom/cliphist ) ( custom/wbar ) ( custom/wallchange ) ( custom/theme )|
0|31|bottom|( cpu memory custom/cpuinfo custom/gpuinfo ) ( idle_inhibitor clock custom/prayer ) ( hyprland/workspaces )|( wlr/taskbar )|( backlight network pulseaudio pulseaudio#microphone custom/updates custom/keybindhint ) ( privacy tray battery ) ( custom/wallchange custom/theme custom/wbar custom/cliphist custom/power )
0|31|top|( cpu memory custom/cpuinfo custom/gpuinfo ) ( idle_inhibitor clock custom/prayer ) ( hyprland/workspaces )|( wlr/taskbar )|( backlight network pulseaudio pulseaudio#microphone custom/updates custom/keybindhint ) ( privacy tray battery ) ( custom/wallchange custom/theme custom/wbar custom/cliphist custom/power )
0|29|bottom|( wlr/taskbar mpris )|( idle_inhibitor clock )|( backlight network pulseaudio pulseaudio#microphone custom/updates ) ( privacy tray battery ) ( custom/wallchange custom/theme custom/wbar custom/cliphist custom/power )
0|29|left|( wlr/taskbar mpris )|( idle_inhibitor clock )|( backlight network pulseaudio pulseaudio#microphone custom/updates ) ( privacy tray battery ) ( custom/wallchange custom/theme custom/wbar custom/cliphist custom/power )
0|29|top|( wlr/taskbar mpris )|( idle_inhibitor clock )|( backlight network pulseaudio pulseaudio#microphone custom/updates ) ( privacy tray battery ) ( custom/wallchange custom/theme custom/wbar custom/cliphist custom/power )
0|29|right|( wlr/taskbar mpris )|( idle_inhibitor clock )|( backlight network pulseaudio pulseaudio#microphone custom/updates ) ( privacy tray battery ) ( custom/wallchange custom/theme custom/wbar custom/cliphist custom/power )
0|28|bottom|( custom/power custom/cliphist custom/wbar custom/theme custom/wallchange ) ( idle_inhibitor clock custom/prayer custom/spotify )|( wlr/taskbar )|( privacy tray ) ( backlight network pulseaudio pulseaudio#microphone )
0|28|left|( custom/power custom/cliphist custom/wbar custom/theme custom/wallchange ) ( idle_inhibitor clock custom/prayer custom/spotify )|( wlr/taskbar )|( privacy tray ) ( backlight network pulseaudio pulseaudio#microphone )
0|28|top|( custom/power custom/cliphist custom/wbar custom/theme custom/wallchange ) ( idle_inhibitor clock custom/prayer custom/spotify )|( wlr/taskbar )|( privacy tray ) ( backlight network pulseaudio pulseaudio#microphone )
0|28|right|( custom/power custom/cliphist custom/wbar custom/theme custom/wallchange ) ( idle_inhibitor clock custom/prayer custom/spotify )|( wlr/taskbar )|( privacy tray ) ( backlight network pulseaudio pulseaudio#microphone )
0|40|top|( hyprland/workspaces )|( custom/cava idle_inhibitor clock )|( backlight pulseaudio pulseaudio#microphone tray battery custom/keybindhint custom/cliphist custom/power )
1|30|top|hyprland/workspaces|clock custom/prayer|pulseaudio custom/separator memory custom/separator cpu
EOF

# --- WRITE ~/.config/waybar/modules/workspaces.jsonc ---
echo -e "${CYAN}Writing ~/.config/waybar/modules/workspaces.jsonc...${NC}"
mkdir -p "$HOME/.config/waybar/modules"
cat << 'EOF' > "$HOME/.config/waybar/modules/workspaces.jsonc"
    "hyprland/workspaces": {
        "disable-scroll": true,
        "rotate": ${r_deg},
        "all-outputs": true,
        "active-only": false,
        "on-click": "activate",
        "disable-scroll": false,
        "on-scroll-up": "hyprctl dispatch workspace -1",
        "on-scroll-down": "hyprctl dispatch workspace +1",
        "format": "{name}",
        "format-window-separator": " ",
        "window-rewrite-default": "",
        "window-rewrite": {
            "class<kitty>": "",
            "class<firefox>": "",
            "class<chromium>": "",
            "class<google-chrome>": "",
            "class<dolphin>": "󰉋",
            "class<thunar>": "󰉋",
            "class<vs-code-oss>": "󰨞",
            "class<code-oss>": "󰨞",
            "class<vscode>": "󰨞",
            "class<discord>": "󰙯",
            "class<spotify>": "",
            "class<steam>": "",
            "class<vlc>": "󰕼",
            "class<mpv>": "󰕼"
        },
        "persistent-workspaces": {
            "1": [],
            "2": [],
            "3": []
        }
    },
EOF

# --- WRITE ~/.config/waybar/modules/separator.jsonc ---
echo -e "${CYAN}Writing ~/.config/waybar/modules/separator.jsonc...${NC}"
cat << 'EOF' > "$HOME/.config/waybar/modules/separator.jsonc"
    "custom/separator": {
        "format": "|",
        "interval": "once",
        "tooltip": false
    },
EOF

# --- WRITE ~/.config/waybar/modules/prayer.jsonc ---
echo -e "${CYAN}Writing ~/.config/waybar/modules/prayer.jsonc...${NC}"
cat << 'EOF' > "$HOME/.config/waybar/modules/prayer.jsonc"
    "custom/prayer": {
        "format": "{}",
        "exec": "$HOME/.local/share/bin/prayer_times.py",
        "interval": 1,
        "tooltip": false
    },
EOF

# --- WRITE hyde repository copies of modules ---
if [ -d "$HOME/hyde" ]; then
    echo -e "${CYAN}Writing hyde repository copies of modules...${NC}"
    mkdir -p "$HOME/hyde/Configs/.config/waybar/modules"
    cp "$HOME/.config/waybar/modules/workspaces.jsonc" "$HOME/hyde/Configs/.config/waybar/modules/workspaces.jsonc"
    cp "$HOME/.config/waybar/modules/separator.jsonc" "$HOME/hyde/Configs/.config/waybar/modules/separator.jsonc"
    cp "$HOME/.config/waybar/modules/prayer.jsonc" "$HOME/hyde/Configs/.config/waybar/modules/prayer.jsonc"
fi

# --- WRITE ~/.config/hyde/hyde.conf ---
echo -e "${CYAN}Writing ~/.config/hyde/hyde.conf...${NC}"
cat << 'EOF' > "$HOME/.config/hyde/hyde.conf"
hydeTheme="Gruvbox Retro"
rofiStyle="5"
enableWallDcol="2"
EOF

# --- WRITE ~/.zshrc ---
echo -e "${CYAN}Writing ~/.zshrc...${NC}"
cat << 'EOF' > "$HOME/.zshrc"
# Oh-my-zsh installation path
ZSH=/usr/share/oh-my-zsh/

# Powerlevel10k theme path
source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme

# List of plugins used
plugins=( git sudo zsh-256color zsh-autosuggestions zsh-syntax-highlighting )
source $ZSH/oh-my-zsh.sh

# In case a command is not found, try to find the package that has it
function command_not_found_handler {
    local purple='\e[1;35m' bright='\e[0;1m' green='\e[1;32m' reset='\e[0m'
    printf 'zsh: command not found: %s\n' "$1"
    local entries=( ${(f)"$(/usr/bin/pacman -F --machinereadable -- "/usr/bin/$1")"} )
    if (( ${#entries[@]} )) ; then
        printf "${bright}$1${reset} may be found in the following packages:\n"
        local pkg
        for entry in "${entries[@]}" ; do
            local fields=( ${(0)entry} )
            if [[ "$pkg" != "${fields[2]}" ]]; then
                printf "${purple}%s/${bright}%s ${green}%s${reset}\n" "${fields[1]}" "${fields[2]}" "${fields[3]}"
            fi
            printf '    /%s\n' "${fields[4]}"
            pkg="${fields[2]}"
        done
    fi
    return 127
}

# Detect AUR wrapper
if pacman -Qi yay &>/dev/null; then
   aurhelper="yay"
elif pacman -Qi paru &>/dev/null; then
   aurhelper="paru"
fi

function in {
    local -a inPkg=("$@")
    local -a arch=()
    local -a aur=()

    for pkg in "${inPkg[@]}"; do
        if pacman -Si "${pkg}" &>/dev/null; then
            arch+=("${pkg}")
        else
            aur+=("${pkg}")
        fi
    done

    if [[ ${#arch[@]} -gt 0 ]]; then
        sudo pacman -S "${arch[@]}"
    fi

    if [[ ${#aur[@]} -gt 0 ]]; then
        ${aurhelper} -S "${aur[@]}"
    fi
}

# Helpful aliases
alias c='clear' # clear terminal
alias l='eza -lh --icons=auto --no-permissions --no-user --no-filesize --time-style="+%Y/%-m/%-d %I:%M %p"' # long list
alias ls='eza -1 --icons=auto' # short list
alias ll='eza -lha --icons=auto --sort=name --group-directories-first --no-permissions --no-user --no-filesize --time-style="+%Y/%-m/%-d %I:%M %p"' # long list all
alias ld='eza -lhD --icons=auto --no-permissions --no-user --no-filesize --time-style="+%Y/%-m/%-d %I:%M %p"' # long list dirs
alias la='eza -lha --icons=auto --no-permissions --no-user --no-filesize --time-style="+%Y/%-m/%-d %I:%M %p"'
alias lsa='eza -lha --icons=auto --no-permissions --no-user --no-filesize --time-style="+%Y/%-m/%-d %I:%M %p"'
alias lt='eza --icons=auto --tree' # list folder as tree
alias un='$aurhelper -Rns' # uninstall package
alias up='$aurhelper -Syu' # update system/package/aur
alias pl='$aurhelper -Qs' # list installed package
alias pa='$aurhelper -Ss' # list available package
alias pc='$aurhelper -Sc' # remove unused cache
alias po='$aurhelper -Qtdq | $aurhelper -Rns -' # remove unused packages, also try > $aurhelper -Qqd | $aurhelper -Rsu --print -
alias vc='code' # gui code editor

# Directory navigation shortcuts
alias ..='cd ..'
alias ...='cd ../..'
alias .3='cd ../../..'
alias .4='cd ../../../..'
alias .5='cd ../../../../..'

# Always mkdir a path (this doesn't inhibit functionality to make a single dir)
alias mkdir='mkdir -p'

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh


# Added by Antigravity CLI installer
export PATH="$HOME/.local/bin:$PATH"

# opencode
export PATH=$HOME/.opencode/bin:$PATH

# Make Ctrl+Backspace / Ctrl+W behave like Windows/bash (delete until space or slash)
autoload -U select-word-style
select-word-style bash

# Make Ctrl+A select all typed text on the command line (like Windows)
select-all-line() {
    if [[ -z "$BUFFER" ]]; then
        return
    fi
    CURSOR=0
    zle set-mark-command
    CURSOR=$#BUFFER
}
zle -N select-all-line
bindkey '^A' select-all-line

# Task management aliases & delegation
unfunction todo doing donetask rmtask edittask 2>/dev/null || true
todo() { "$HOME/.local/share/bin/todo" "$@"; }
doing() { "$HOME/.local/share/bin/doing" "$@"; }
donetask() { "$HOME/.local/share/bin/donetask" "$@"; }
rmtask() { "$HOME/.local/share/bin/rmtask" "$@"; }
edittask() { "$HOME/.local/share/bin/edittask" "$@"; }
EOF

# --- WRITE ~/.config/fish/config.fish ---
echo -e "${CYAN}Writing ~/.config/fish/config.fish...${NC}"
mkdir -p "$HOME/.config/fish"
cat << 'EOF' > "$HOME/.config/fish/config.fish"
source /usr/share/cachyos-fish-config/cachyos-config.fish

# overwrite greeting
# potentially disabling fastfetch
function fish_greeting
end
set -gx EDITOR vim

# Custom eza aliases to hide metadata
alias l='eza -lh --icons=auto --no-permissions --no-user --no-filesize --time-style="+%Y/%-m/%-d %I:%M %p"'
alias ls='eza -1 --icons=auto'
alias ll='eza -lha --icons=auto --sort=name --group-directories-first --no-permissions --no-user --no-filesize --time-style="+%Y/%-m/%-d %I:%M %p"'
alias ld='eza -lhD --icons=auto --no-permissions --no-user --no-filesize --time-style="+%Y/%-m/%-d %I:%M %p"'
alias la='eza -lha --icons=auto --no-permissions --no-user --no-filesize --time-style="+%Y/%-m/%-d %I:%M %p"'
alias lsa='eza -lha --icons=auto --no-permissions --no-user --no-filesize --time-style="+%Y/%-m/%-d %I:%M %p"'

# Erase old task functions from Fish RAM
functions -e todo doing donetask rmtask edittask 2>/dev/null

# Task management functions delegating to executable scripts
function todo; $HOME/.local/share/bin/todo $argv; end
function doing; $HOME/.local/share/bin/doing $argv; end
function donetask; $HOME/.local/share/bin/donetask $argv; end
function rmtask; $HOME/.local/share/bin/rmtask $argv; end
function edittask; $HOME/.local/share/bin/edittask $argv; end
EOF

# --- WRITE ~/.config/yazi/yazi.toml ---
echo -e "${CYAN}Writing ~/.config/yazi/yazi.toml...${NC}"
mkdir -p "$HOME/.config/yazi"
cat << 'EOF' > "$HOME/.config/yazi/yazi.toml"
[opener]
edit = [
    { run = 'vim "%s"', block = true, for = "unix" }
]
code = [
    { run = 'code "%s"', orphan = true, for = "unix" }
]

[open]
prepend_rules = [
    { mime = "text/*", use = [ "edit", "code" ] },
    { url = "*.conf", use = [ "edit", "code" ] },
    { url = "*.json", use = [ "edit", "code" ] },
    { url = "*.toml", use = [ "edit", "code" ] },
    { url = "*.sh", use = [ "edit", "code" ] },
    { url = "*.lua", use = [ "edit", "code" ] }
]
EOF

# --- WRITE ~/.config/fastfetch/logo.txt ---
echo -e "${CYAN}Writing ~/.config/fastfetch/logo.txt...${NC}"
mkdir -p "$HOME/.config/fastfetch"
cat << 'EOF' > "$HOME/.config/fastfetch/logo.txt"
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣀⠀⠀⠀⠀⠀⠀⣀⣠⡄⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⣀⣤⣴⣿⣽⠟⢁⣠⣤⣤⣶⣿⣽⣿⠟⠁⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⣀⣶⣿⣟⢿⣟⣿⣷⢞⢻⡻⣫⡻⣖⣾⣻⠏⠀⠀⠀⠀⠀⣀⣴⣾
⠀⠀⢀⠀⣸⣿⢻⣍⣷⢽⢿⢹⣪⣗⣽⣹⢽⡫⣿⣽⠏⢀⣀⣤⣴⣫⣿⣯⡟⠁
⠀⠀⣾⣿⢿⡣⢷⢼⣷⣿⢧⢿⢮⡷⡽⡵⣽⢎⣿⣯⠶⣿⡿⣛⢯⣫⣿⡿⠁⠀
⠀⢸⣿⡏⣾⢳⢟⢇⣿⢿⡳⡻⡕⣯⢪⡞⣾⣷⡟⣕⢗⡿⡸⣇⢯⡾⣻⠁⠀⠀
⢠⣿⣿⣷⣺⢕⣿⣾⠟⠚⠛⠛⠚⢓⣿⢾⣺⡳⡟⣾⢱⢻⡞⣷⢻⣿⡟⠀⠀⠀
⢻⣿⢏⣿⣽⣾⢿⡀⠀⠀⠀⠀⣐⣿⢝⠈⠓⣕⣽⣹⣏⣺⢕⣿⣿⣭⣤⣤⣤⣀
⢸⣿⢵⠷⣽⣯⣼⣧⠀⠀⣠⣼⠗⠁⢸⠀⠀⠘⡷⣽⢮⣼⠷⠿⠽⢾⣾⡿⠋⠀
⠀⠻⣷⡗⣽⣿⣿⣋⡗⣾⢿⣿⠀⠀⢨⠤⢭⡑⡟⡾⢝⢟⠶⣗⢟⣾⡿⠁⠀⠀
⠈⠻⣙⣛⠛⠋⠉⣁⣈⣿⣿⣿⡠⠾⢣⠀⠨⢸⢿⣹⡪⣿⣝⣝⣽⡟⠁⠀⠀⠀
⠀⠀⠀⠑⣿⣝⣿⡘⢇⡀⠄⢡⠀⡇⠈⢢⣸⣱⡏⣾⢬⣺⣪⣿⠏⠀⠀⠀⠀⠀
⠀⠀⠀⢀⣼⠷⢽⢾⣣⣽⣤⢤⣵⣧⢼⢭⢿⣾⣷⣿⡾⠟⠋⠁⠀⠀⠀⠀⠀⠀
⠀⢠⣶⡟⢾⣿⣷⠿⠛⢻⣿⣿⢟⢕⢿⢷⣿⣖⢟⢿⣳⣦⠀⠀⠀⠀⠀⠀⠀⠀
⠀⢀⣿⣿⣿⣿⣷⣴⠮⠟⠻⣿⣿⣿⣽⣫⣻⡉⠻⣯⣿⣿⣷⡄⠀⠀⠀⠀⠀⠀
⠀⠸⣿⡿⣿⣿⠤⠤⠤⢤⣀⣰⣯⣿⣽⣿⢻⢿⣆⣿⣽⣿⣽⣇⣠⠀⠀⠀⠀⠀
⠀⣶⣚⣗⢹⣿⠉⠉⠑⠲⣙⣿⣽⣿⣾⣿⢘⣿⡝⣿⣿⣿⣋⠟⡿⠀⠀⠀⠀⠀
⠀⠨⢳⡷⣽⣿⡇⠀⠀⢠⡾⣿⣷⣿⣾⡟⣾⢻⡷⣿⣟⠛⠒⠺⢅⠀⠀⠀⠀⠀
⠀⠀⠿⠟⢿⠟⠛⠙⣿⣿⣯⣻⠟⠋⢉⡭⠿⠼⡏⠉⠉⠉⠉⠢⢄⡑⣦⠀⠀⠀
⠀⠀⠀⠀⠀⠀⢀⢴⠯⠥⣴⠏⠀⡴⠋⠀⠀⠀⡗⡦⢤⣄⣀⠀⠀⠉⠛⠷⣤⣀
⠀⠀⠀⠀⠀⠀⠚⠙⠓⢲⠋⡠⠊⠀⢀⣤⠴⠚⠁⠀⠀⠈⠉⠉⠉⠉⠉⠉⠉⠁
⠀⠀⠀⠀⠀⠀⠀⠀⢴⠷⠽⠶⠒⠋⠉⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
EOF

# --- WRITE ~/.config/fastfetch/config.jsonc ---
echo -e "${CYAN}Writing ~/.config/fastfetch/config.jsonc...${NC}"
cat << 'EOF' > "$HOME/.config/fastfetch/config.jsonc"
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": {
    "source": "~/.config/fastfetch/logo.txt",
    "width": 1,
    "padding": {
      "top": 2
    }
  },
  "display": {
    "separator": " : "
  },
  "modules": [
    {
      "type": "custom",
      "format": "\u001b[36m   󰄛  コンピューター"
    },
    {
      "type": "custom",
      "format": "┌──────────────────────────────────────────┐"
    },
    {
      "type": "chassis",
      "key": "  󰇺 Chassis",
      "format": "{3}"
    },
    {
      "type": "os",
      "key": "  󰣇 OS",
      "format": "{2}",
      "keyColor": "red"
    },
    {
      "type": "kernel",
      "key": "   Kernel",
      "format": "{2}",
      "keyColor": "red"
    },
    {
      "type": "packages",
      "key": "  󰏗 Packages",
      "keyColor": "green"
    },
    {
      "type": "display",
      "key": "  󰍹 Display",
      "format": "{1}x{2} @ {3}Hz [{7}]",
      "keyColor": "green"
    },
    {
      "type": "terminal",
      "key": "  >_ Terminal",
      "keyColor": "yellow"
    },
    {
      "type": "wm",
      "key": "  󱗃 WM",
      "format": "{2}",
      "keyColor": "yellow"
    },
    {
      "type": "custom",
      "format": "└──────────────────────────────────────────┘"
    },
    "break",
    {
      "type": "title",
      "key": "  ",
      "format": "{6} {7} {8}"
    },
    {
      "type": "custom",
      "format": "┌──────────────────────────────────────────┐"
    },
    {
      "type": "cpu",
      "format": "{1} @ {7}",
      "key": "   CPU",
      "keyColor": "blue"
    },
    {
      "type": "gpu",
      "format": "{1} {2}",
      "key": "  󰊴 GPU",
      "keyColor": "blue"
    },
    {
      "type": "gpu",
      "format": "{3}",
      "key": "   GPU Driver",
      "keyColor": "magenta"
    },
    {
      "type": "memory",
      "key": "    Memory",
      "keyColor": "magenta"
    },
    {
      "type": "command",
      "key": "  󱦟 OS Age ",
      "keyColor": "red",
      "text": "birth_install=$(stat -c %W /); current=$(date +%s); time_progression=$((current - birth_install)); days_difference=$((time_progression / 86400)); echo $days_difference days"
    },
    {
      "type": "uptime",
      "key": "  󱫐 Uptime ",
      "keyColor": "red"
    },
    {
      "type": "custom",
      "format": "└──────────────────────────────────────────┘"
    },
    "break",
    {
      "type": "custom",
      "format": "┌───────────────   Tasks ────────────────┐"
    },
    {
      "type": "command",
      "key": "  Todo",
      "keyColor": "cyan",
      "text": "cat ~/.config/fastfetch/tasks.txt 2>/dev/null | sed '2,99s/^/                                     /'"
    },
    {
      "type": "custom",
      "format": "└──────────────────────────────────────────┘"
    },
    {
      "type": "colors",
      "paddingLeft": 2,
      "symbol": "circle"
    }
  ]
}
EOF

# --- WRITE ~/.config/fastfetch/tasks.txt ---
echo -e "${CYAN}Writing ~/.config/fastfetch/tasks.txt...${NC}"
mkdir -p "$HOME/.config/fastfetch"
if [ ! -f "$HOME/.config/fastfetch/tasks.txt" ]; then
    cat << 'EOF' > "$HOME/.config/fastfetch/tasks.txt"
- Finish system setup
- niceRiceOmar
─────────────────────────────────
todo <task> / doing / donetask
rmtask / edittask
EOF
fi

# --- SDDM Theme & VT Optimization Configuration ---
echo -e "\n${BLUE}${BOLD}Configuring SDDM Astronaut theme & VT1 Reuse...${NC}"
if [ -f /etc/sddm.conf ]; then
    if ! grep -q "^Current=" /etc/sddm.conf; then
        echo -e "\n[Theme]\nCurrent=sddm-astronaut-theme" | sudo tee -a /etc/sddm.conf >/dev/null
    else
        sudo sed -i 's/^Current=.*/Current=sddm-astronaut-theme/' /etc/sddm.conf
    fi
    
    if ! grep -q "^MinimumVT=" /etc/sddm.conf; then
        if grep -q "^\[X11\]" /etc/sddm.conf; then
            sudo sed -i '/^\[X11\]/a MinimumVT=1' /etc/sddm.conf
        else
            echo -e "\n[X11]\nMinimumVT=1" | sudo tee -a /etc/sddm.conf >/dev/null
        fi
    else
        sudo sed -i 's/^MinimumVT=.*/MinimumVT=1/' /etc/sddm.conf
    fi
else
    echo -e "[Theme]\nCurrent=sddm-astronaut-theme\n\n[X11]\nMinimumVT=1" | sudo tee /etc/sddm.conf >/dev/null
fi


# Set SDDM Astronaut theme configuration to Jake the Dog variant
if [ -d "/usr/share/sddm/themes/sddm-astronaut-theme" ]; then
    echo -e "${CYAN}Setting SDDM theme variant to Jake the Dog...${NC}"
    if [ -f "/usr/share/sddm/themes/sddm-astronaut-theme/metadata.desktop" ]; then
        sudo sed -i 's/^ConfigFile=.*/ConfigFile=Themes\/jake_the_dog.conf/' /usr/share/sddm/themes/sddm-astronaut-theme/metadata.desktop
    fi
fi
echo -e "${GREEN}[OK] SDDM Astronaut theme (Jake the Dog variant) configured successfully!${NC}"

# --- RTL8188EUS USB Wi-Fi Hotspot driver configuration ---
echo -e "\n${BLUE}${BOLD}Configuring RTL8188EUS USB Wi-Fi driver and blacklisting conflicting drivers...${NC}"

# Blacklist default rtl8xxxu driver
if [ ! -f /etc/modprobe.d/rtl8xxxu.conf ] || ! grep -q "blacklist rtl8xxxu" /etc/modprobe.d/rtl8xxxu.conf; then
    echo -e "${CYAN}Creating blacklisting rule for default rtl8xxxu driver...${NC}"
    echo "blacklist rtl8xxxu" | sudo tee /etc/modprobe.d/rtl8xxxu.conf >/dev/null
    echo -e "${GREEN}[OK] Blacklisted rtl8xxxu driver successfully!${NC}"
else
    echo -e "${GREEN}[OK] rtl8xxxu driver is already blacklisted.${NC}"
fi

# Blacklist staging r8188eu driver
if [ ! -f /etc/modprobe.d/r8188eu.conf ] || ! grep -q "blacklist r8188eu" /etc/modprobe.d/r8188eu.conf; then
    echo -e "${CYAN}Creating blacklisting rule for staging r8188eu driver...${NC}"
    echo "blacklist r8188eu" | sudo tee /etc/modprobe.d/r8188eu.conf >/dev/null
    echo -e "${GREEN}[OK] Blacklisted staging r8188eu driver successfully!${NC}"
else
    echo -e "${GREEN}[OK] staging r8188eu driver is already blacklisted.${NC}"
fi

# Compile and Patch the RTL8188EUS USB Wi-Fi driver if needed
echo -e "\n${BLUE}${BOLD}Checking and patching RTL8188EUS USB Wi-Fi driver for modern kernels...${NC}"
# Find driver directory in /usr/src/
SRC_DIRS=(/usr/src/8188eu-*)
if [ -d "${SRC_DIRS[0]}" ]; then
    DRIVER_DIR="${SRC_DIRS[0]}"
    DRIVER_VER=$(basename "$DRIVER_DIR" | sed 's/8188eu-//')
    echo -e "Found driver source directory: ${CYAN}$DRIVER_DIR${NC} (Version: ${CYAN}$DRIVER_VER${NC})"
    
    # Locate patch_driver.py
    PATCH_SCRIPT=""
    if [ -f "$SCRIPT_DIR/patch_driver.py" ]; then
        PATCH_SCRIPT="$SCRIPT_DIR/patch_driver.py"
    else
        # If script is run via curl or in a temp location, fetch patch_driver.py from remote repo
        echo -e "${CYAN}Downloading patch_driver.py from GitHub repository...${NC}"
        PATCH_URL="https://raw.githubusercontent.com/omarahmed321/cachy-os-config-related/main/patch_driver.py"
        PATCH_TMP="$(mktemp --suffix=.py)"
        if curl -fsSL -o "$PATCH_TMP" "$PATCH_URL" || wget -q -O "$PATCH_TMP" "$PATCH_URL"; then
            PATCH_SCRIPT="$PATCH_TMP"
        fi
    fi
    
    # Run patch script
    if [ -f "$PATCH_SCRIPT" ]; then
        echo -e "${CYAN}Running driver source patch script on $DRIVER_DIR...${NC}"
        sudo python3 "$PATCH_SCRIPT" "$DRIVER_DIR"
        
        # Trigger DKMS to rebuild and reinstall the patched driver
        echo -e "${CYAN}Rebuilding and reinstalling patched 8188eu driver using DKMS...${NC}"
        sudo dkms remove -m 8188eu -v "$DRIVER_VER" --all || true
        sudo dkms add -m 8188eu -v "$DRIVER_VER" || true
        if sudo dkms install -m 8188eu -v "$DRIVER_VER"; then
            echo -e "${GREEN}[OK] RTL8188EUS USB Wi-Fi driver patched and installed successfully via DKMS!${NC}"
        else
            echo -e "${RED}[ERROR] Failed to compile and install RTL8188EUS USB Wi-Fi driver via DKMS.${NC}"
        fi
    else
        echo -e "${YELLOW}[WARNING] Could not locate or download patch_driver.py. Skipping patch step.${NC}"
    fi
else
    echo -e "${YELLOW}[WARNING] No RTL8188EUS driver source found in /usr/src/8188eu-*. Skipping driver patch.${NC}"
fi

# --- Nvidia DRM Configuration ---
if [ "$GPU_VENDOR" = "nvidia" ]; then
    echo -e "\n${BLUE}${BOLD}Configuring Nvidia DRM modesetting...${NC}"
    echo -e "${CYAN}Setting clean default in /etc/modprobe.d/nvidia.conf...${NC}"
    sudo tee /etc/modprobe.d/nvidia.conf >/dev/null << 'NVIEOF'
options nvidia_drm modeset=1
options nvidia NVreg_RegistryDwords="PerfLevelSrc=0x2222"
NVIEOF
    echo -e "${GREEN}[OK] Nvidia DRM configured successfully!${NC}"
else
    if [ -f /etc/modprobe.d/nvidia.conf ]; then
        echo -e "\n${BLUE}${BOLD}Removing Nvidia DRM configuration (non-Nvidia system detected)...${NC}"
        sudo rm -f /etc/modprobe.d/nvidia.conf
    fi
fi

# Robustly clone and patch preset HyDE themes to ensure Waybar theme switches work perfectly out-of-the-box
if [ -f "$HOME/hyde/Scripts/themepatcher.lst" ] && [ -f "$HOME/hyde/Scripts/themepatcher.sh" ]; then
    echo -e "\n${BLUE}${BOLD}Installing and patching missing preset HyDE themes...${NC}"
    while IFS='"' read -r null1 themeName null2 themeRepo; do
        if [ -n "$themeName" ] && [ -n "$themeRepo" ]; then
            if [ ! -d "$HOME/.config/hyde/themes/$themeName" ]; then
                echo -e "  - Patching missing theme: ${CYAN}$themeName${NC}..."
                "$HOME/hyde/Scripts/themepatcher.sh" "$themeName" "$themeRepo" --skipcaching false &>/dev/null || true
            else
                echo -e "  - Theme ${GREEN}$themeName${NC} is already installed. Skipping patch."
            fi
        fi
    done < "$HOME/hyde/Scripts/themepatcher.lst"
    echo -e "${GREEN}[OK] All preset HyDE themes checked successfully!${NC}"
fi

# Clean up hardcoded cursor theme lines in common.conf to prevent theme conflicts
if [ -f "$HOME/.config/hypr/themes/common.conf" ]; then
    echo -e "${CYAN}Removing hardcoded cursor settings from common.conf...${NC}"
    sed -i '/exec = hyprctl setcursor/d' "$HOME/.config/hypr/themes/common.conf"
    sed -i '/exec = gsettings set org.gnome.desktop.interface cursor-theme/d' "$HOME/.config/hypr/themes/common.conf"
    sed -i '/exec = gsettings set org.gnome.desktop.interface cursor-size/d' "$HOME/.config/hypr/themes/common.conf"
fi




# --- CONFIGURE GLASSY ZEN BROWSER CUSTOM THEME ---
echo -e "\n${BLUE}${BOLD}Configuring Glassy/Transparent Zen Browser profile UI...${NC}"

# Pre-seed default Zen Browser profiles if they don't exist yet (ensures theme files are always created on clean installations)
mkdir -p "$HOME/.config/zen"
if [ ! -f "$HOME/.config/zen/profiles.ini" ]; then
    echo -e "${CYAN}Pre-seeding Zen Browser profiles.ini and default profile directories...${NC}"
    cat << 'EOF' > "$HOME/.config/zen/profiles.ini"
[Profile1]
Name=Default Profile
IsRelative=1
Path=081dvyif.Default Profile
Default=1

[Profile0]
Name=Default (release)
IsRelative=1
Path=l1u1cimb.Default (release)

[General]
StartWithLastProfile=1
Version=2

[Install15B76BAA26BA15E7]
Default=l1u1cimb.Default (release)
Locked=1
EOF
    mkdir -p "$HOME/.config/zen/081dvyif.Default Profile"
    mkdir -p "$HOME/.config/zen/l1u1cimb.Default (release)"
fi

ZEN_PROFILES=()
while IFS= read -r -d '' dir; do
    ZEN_PROFILES+=("$dir")
done < <(find "$HOME/.config/zen" -maxdepth 1 -type d -name "*Default*" -print0 2>/dev/null)

if [ ${#ZEN_PROFILES[@]} -gt 0 ]; then
    for profile in "${ZEN_PROFILES[@]}"; do
        echo -e "Configuring Zen Browser profile: ${CYAN}$(basename "$profile")${NC}"
        mkdir -p "$profile/chrome"
        
        # Write userChrome.css
        cat << 'ZENCHROME' > "$profile/chrome/userChrome.css"
/*
 * Zen Browser - Terminal Style (Transparent & Borderless)
 */

/* Enable transparency on the main window and all content wrappers */
:root,
#main-window,
#browser,
#appcontent,
browser,
.browserSidebarContainer,
#content-deck,
#tabbrowser-deck,
#tabbrowser-tabbox {
    background-color: transparent !important;
    background: transparent !important;
    border: none !important;
    border-top: none !important;
    border-bottom: none !important;
    border-left: none !important;
    border-right: none !important;
    box-shadow: none !important;
    outline: none !important;
}

/* Completely remove any default borders or separator lines */
#navigator-toolbox,
#nav-bar,
#titlebar,
#TabsToolbar,
#zen-appcontent-navbar-container {
    border: none !important;
    border-top: none !important;
    border-bottom: none !important;
    border-left: none !important;
    border-right: none !important;
    box-shadow: none !important;
    outline: none !important;
}

/* Remove default splitters and frames */
#zen-sidebar-splitter,
#appcontent-splitter {
    display: none !important;
    width: 0 !important;
    max-width: 0 !important;
    min-width: 0 !important;
    visibility: collapse !important;
}

/* Hide status panels */
#statuspanel,
#browser-bottombox {
    display: none !important;
    visibility: collapse !important;
}
ZENCHROME

        # Write userContent.css
        cat << 'ZENCONTENT' > "$profile/chrome/userContent.css"
/*
 * Zen Browser - Web Content Font & Color Optimization
 */

/* Force the exact terminal background color on all pages */
@-moz-document url-prefix(http), url-prefix(https), url-prefix(about:) {
    :root, body, html {
        background-color: #090a09 !important;
    }
    body, p, span, a, li, h1, h2, h3, h4, h5, h6, input, textarea, button {
        -webkit-font-smoothing: antialiased !important;
        -moz-osx-font-smoothing: grayscale !important;
        text-rendering: optimizeLegibility !important;
    }
}
ZENCONTENT

        # Write user.js
        # Write user.js
        cat << 'ZENUSERJS' > "$profile/user.js"
// Enable userChrome.css customizations
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Enable native Linux window transparency in Zen Browser
user_pref("browser.tabs.allow_transparent_browser", true);
user_pref("widget.transparent-windows", true);
user_pref("zen.widget.linux.transparency", true);

// Enable Compact Mode
user_pref("zen.view.compact.enable-at-startup", true);
user_pref("zen.view.compact.toolbar-flash-popup", false);
user_pref("zen.view.compact.hide-toolbar", true);

// Disable the hover-to-reveal sidebar and toolbar in compact mode
user_pref("zen.view.compact.show-sidebar-and-toolbar-on-hover", false);

// Remove the default 8px frame/borders around the browser content
user_pref("zen.theme.content-element-separation", 0);

// Collapse sidebar and hide tabs
user_pref("zen.view.sidebar-expanded", false);
user_pref("zen.view.use-single-toolbar", true);
user_pref("zen.tabs.show-newtab-vertical", false);
user_pref("zen.view.show-newtab-button-top", false);

// Floating URL bar behavior
user_pref("zen.urlbar.behavior", "float");

// Hide navbar mod preferences
user_pref("mod.devdinc.hide-navbar.animation.enabled", true);
user_pref("mod.devdinc.hide-navbar.element-seperation", "var(--zen-element-separation)");

// New tab = blank page
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.startup.homepage", "about:blank");
user_pref("browser.startup.page", 1);
user_pref("zen.urlbar.replace-newtab", false);

// Disable session restore
user_pref("browser.sessionstore.resume_session_once", false);
user_pref("browser.sessionstore.resume_from_crash", false);

// Font optimizations - increase default/minimum size for better visibility
user_pref("font.size.variable.x-western", 18);
user_pref("font.size.fixed.x-western", 15);
user_pref("font.minimum-size.x-western", 13);
ZENUSERJS

        # Create themes directories
        mkdir -p "$profile/chrome/zen-themes/e34745fd-2b7f-4c16-b03a-6e29e5c3f20a"

        # Write zen-themes.css
        cat << 'ZENTHEMESCSS' > "$profile/chrome/zen-themes.css"
/* Zen Mods - Generated by ZenMods.
* FILE GENERATED AT: Tuesday, July 7, 2026 at 2:02:18 AM Eastern European Summer Time
* DO NOT EDIT THIS FILE DIRECTLY!
* Your changes will be overwritten.
* Instead, go to the preferences and edit the mods there.
*/

/* Name: Hide Toolbar */
/* Description: Allows you to hide the toolbar/navbar, including in *single toolbar mode*. */
/* Author: @devdinc */
#zen-context-menu-compact-mode-hide-toolbar[disabled="true"] {
  display: block; /* or flex-direction: column if using flex */
  
  & label, 
  & img {
    display: none !important;
  }
  
  &::before, &::after {
    content: "Native Hide Toolbar mode is disabled.\A\A\
To achieve a similar effect, try:";
    /* Style for readability */
    font-size: 0.95rem;
    line-height: 1.0;
    width: 100%;
    display: block;
    color: rgba(200, 200, 0, 0.8);
    
    /* Preserve newlines and wrap nicely */
    white-space: pre-wrap;
  }
  
  &::after {
    content: "Toggling the 'enable the mod' setting in Hide Toolbar mod settings\
 off then on\A\A\
Enabling 'Hide both' below here with compact mode disabled.";
    padding-left: 5px;
    margin-top: 10px;
    border-left: rgba(0,0,0,0.4) solid 2px;
    color: inherit;
  }
}

@media (-moz-bool-pref: "zen.view.compact.hide-toolbar") { /* zen default hide toolbar */
  @media (-moz-bool-pref: "mod.devdinc.hide-navbar.animation.enabled") {
    /* Transition defaults for all toolbar elements */
    #nav-bar,
    #zen-sidebar-top-buttons,
    #PersonalToolbar,
    #navigator-toolbox,
    #TabsToolbar,
    #titlebar{
      transition:
        all var(--zen-hidden-toolbar-transition) !important;
        /* adding will change makes urlbar open not centered anymore */
    }
  }
  /* backup hiding styles */
  :root {
    --margin-top-fix-hide: calc((var(--zen-toolbar-height) + 50px) + var(--mod-devdinc-hide-navbar-element-seperation));
    --margin-top-fix-hide-reverse: calc(((var(--zen-toolbar-height) + 50px) * -1));
    
    &:not([zen-compact-mode="true"]):not([zen-single-toolbar="true"]) .browserContainer { /* only on non single toolbar */
      margin-top: calc(var(--zen-toolbar-height) * -1);
    }
  }
  
  :root:not([zen-compact-mode="true"]):not([zen-single-toolbar="true"]):has(> body #zen-main-app-wrapper #browser #zen-appcontent-wrapper #zen-appcontent-navbar-wrapper:not([zen-has-hover])),
  
  :root[zen-compact-mode="true"][zen-single-toolbar="true"] #navigator-toolbox:has(> #titlebar:not(:hover), > #titlebar > #TabsToolbar:hover),
  :root:not([zen-compact-mode="true"])[zen-single-toolbar="true"] #navigator-toolbox:is(:not(:hover), :has(> #titlebar > #TabsToolbar:hover)) {
    
    #nav-bar,
    #zen-sidebar-top-buttons {
      margin-top: var(--margin-top-fix-hide-reverse) !important;
      --zen-toolbar-height: var(--margin-top-fix-hide) !important;
    }
    #PersonalToolbar { /* only on non single toolbar */
      height: 0 !important;
      min-height: 0 !important;
    }
    /* transition tabs only on non single toolbar, this element make it so we need :has */
    /* hides the padding between top of browser and tabs */
    #titlebar, #navigator-toolbox  {
      --zen-toolbar-height: 0 !important;
    }
    .browserContainer { /* only on non single toolbar */
      margin-top: calc(var(--mod-devdinc-hide-navbar-element-seperation) * -1);
    }
  }
}

/* End of Zen Mods */
ZENTHEMESCSS

        # Write e34745fd-2b7f-4c16-b03a-6e29e5c3f20a/chrome.css
        cat << 'ZENMODCSS' > "$profile/chrome/zen-themes/e34745fd-2b7f-4c16-b03a-6e29e5c3f20a/chrome.css"
#zen-context-menu-compact-mode-hide-toolbar[disabled="true"] {
  display: block; /* or flex-direction: column if using flex */
  
  & label, 
  & img {
    display: none !important;
  }
  
  &::before, &::after {
    content: "Native Hide Toolbar mode is disabled.\A\A\
To achieve a similar effect, try:";
    /* Style for readability */
    font-size: 0.95rem;
    line-height: 1.0;
    width: 100%;
    display: block;
    color: rgba(200, 200, 0, 0.8);
    
    /* Preserve newlines and wrap nicely */
    white-space: pre-wrap;
  }
  
  &::after {
    content: "Toggling the 'enable the mod' setting in Hide Toolbar mod settings\
 off then on\A\A\
Enabling 'Hide both' below here with compact mode disabled.";
    padding-left: 5px;
    margin-top: 10px;
    border-left: rgba(0,0,0,0.4) solid 2px;
    color: inherit;
  }
}

@media (-moz-bool-pref: "zen.view.compact.hide-toolbar") { /* zen default hide toolbar */
  @media (-moz-bool-pref: "mod.devdinc.hide-navbar.animation.enabled") {
    /* Transition defaults for all toolbar elements */
    #nav-bar,
    #zen-sidebar-top-buttons,
    #PersonalToolbar,
    #navigator-toolbox,
    #TabsToolbar,
    #titlebar{
      transition:
        all var(--zen-hidden-toolbar-transition) !important;
        /* adding will change makes urlbar open not centered anymore */
    }
  }
  /* backup hiding styles */
  :root {
    --margin-top-fix-hide: calc((var(--zen-toolbar-height) + 50px) + var(--mod-devdinc-hide-navbar-element-seperation));
    --margin-top-fix-hide-reverse: calc(((var(--zen-toolbar-height) + 50px) * -1));
    
    &:not([zen-compact-mode="true"]):not([zen-single-toolbar="true"]) .browserContainer { /* only on non single toolbar */
      margin-top: calc(var(--zen-toolbar-height) * -1);
    }
  }
  
  :root:not([zen-compact-mode="true"]):not([zen-single-toolbar="true"]):has(> body #zen-main-app-wrapper #browser #zen-appcontent-wrapper #zen-appcontent-navbar-wrapper:not([zen-has-hover])),
  
  :root[zen-compact-mode="true"][zen-single-toolbar="true"] #navigator-toolbox:has(> #titlebar:not(:hover), > #titlebar > #TabsToolbar:hover),
  :root:not([zen-compact-mode="true"])[zen-single-toolbar="true"] #navigator-toolbox:is(:not(:hover), :has(> #titlebar > #TabsToolbar:hover)) {
    
    #nav-bar,
    #zen-sidebar-top-buttons {
      margin-top: var(--margin-top-fix-hide-reverse) !important;
      --zen-toolbar-height: var(--margin-top-fix-hide) !important;
    }
    #PersonalToolbar { /* only on non single toolbar */
      height: 0 !important;
      min-height: 0 !important;
    }
    /* transition tabs only on non single toolbar, this element make it so we need :has */
    /* hides the padding between top of browser and tabs */
    #titlebar, #navigator-toolbox  {
      --zen-toolbar-height: 0 !important;
    }
    .browserContainer { /* only on non single toolbar */
      margin-top: calc(var(--mod-devdinc-hide-navbar-element-seperation) * -1);
    }
  }
}
ZENMODCSS

        # Write e34745fd-2b7f-4c16-b03a-6e29e5c3f20a/preferences.json
        cat << 'ZENMODPREFS' > "$profile/chrome/zen-themes/e34745fd-2b7f-4c16-b03a-6e29e5c3f20a/preferences.json"
[
    {
        "property": "zen.view.compact.hide-toolbar",
        "label": "Enable the mod",
        "type": "checkbox",
        "defaultValue": true
    },
    {
        "property": "mod.devdinc.hide-navbar.animation.enabled",
        "label": "Enable animations",
        "type": "checkbox",
        "defaultValue": true
    },
    {
        "property": "mod.devdinc.hide-navbar.element-seperation",
        "label": "Change the top border at the top of the page",
        "type": "string",
        "defaultValue": "var(--zen-element-separation)"
    }
]
ZENMODPREFS

        # Write e34745fd-2b7f-4c16-b03a-6e29e5c3f20a/readme.md
        cat << 'ZENMODREADME' > "$profile/chrome/zen-themes/e34745fd-2b7f-4c16-b03a-6e29e5c3f20a/readme.md"
# Hide Toolbar
Allows you to hide the toolbar/navbar, including in *single toolbar mode*.
ZENMODREADME

        # Also force legacy stylesheets option in prefs.js if it exists
        PREFS_FILE="$profile/prefs.js"
        if [ -f "$PREFS_FILE" ]; then
            if grep -q "toolkit.legacyUserProfileCustomizations.stylesheets" "$PREFS_FILE"; then
                sed -i 's/user_pref("toolkit.legacyUserProfileCustomizations.stylesheets",.*/user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);/' "$PREFS_FILE"
            else
                echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' >> "$PREFS_FILE"
            fi
        fi
    done
    echo -e "${GREEN}[OK] Glassy Zen Browser profile configurations applied successfully to all profiles!${NC}"
else
    echo -e "${YELLOW}[INFO] No Zen Browser profile found in ~/.config/zen/. Skipping configuration.${NC}"
fi

# 5. Apply Settings and Refresh
echo -e "\n${BLUE}${BOLD}Refreshing themes, icon caches, and font caches...${NC}"
fc-cache -f

# Switch theme using HyDE's built-in tool
if [ -f "$HOME/.local/share/bin/themeswitch.sh" ]; then
    echo -e "${CYAN}Switching HyDE theme to 'Gruvbox Retro'...${NC}"
    # Run in background or with suppressions
    "$HOME/.local/share/bin/themeswitch.sh" "Gruvbox Retro" &>/dev/null || true
fi

# Copy default wallpaper from script directory to the theme wallpapers directory
if [ -f "$SCRIPT_DIR/wallpapers/background_for_me.jpg" ]; then
    echo -e "${CYAN}Deploying custom wallpaper background_for_me.jpg...${NC}"
    mkdir -p "$HOME/.config/hyde/themes/Gruvbox Retro/wallpapers"
    cp "$SCRIPT_DIR/wallpapers/background_for_me.jpg" "$HOME/.config/hyde/themes/Gruvbox Retro/wallpapers/background_for_me.jpg"
fi

# Ensure default wallpaper is set to 'background_for_me.jpg' and cache is fully generated
if [ -f "$HOME/.config/hyde/themes/Gruvbox Retro/wallpapers/background_for_me.jpg" ]; then
    echo -e "${CYAN}Setting default wallpaper to 'background_for_me.jpg'...${NC}"
    # Ensure the theme's default wallpaper symlink is set to background_for_me.jpg
    mkdir -p "$HOME/.config/hyde/themes/Gruvbox Retro"
    ln -sf "$HOME/.config/hyde/themes/Gruvbox Retro/wallpapers/background_for_me.jpg" "$HOME/.config/hyde/themes/Gruvbox Retro/wall.set"
    
    # Initialize the wallpaper using HyDE's wallpaper daemon script
    if [ -f "$HOME/.local/share/bin/swwwallpaper.sh" ]; then
        "$HOME/.local/share/bin/swwwallpaper.sh" -s "$HOME/.config/hyde/themes/Gruvbox Retro/wallpapers/background_for_me.jpg" &>/dev/null || true
    fi
fi

# Launch Display & Mouse Settings Manager GUI if running in a graphical session
if [ -n "$WAYLAND_DISPLAY" ] || [ -n "$DISPLAY" ]; then
    echo -e "\n${BLUE}${BOLD}Launching Display & Mouse Settings GUI...${NC}"
    python3 "$HOME/.local/share/bin/hypr-display-settings.py" || true
fi

# Launch Night Light Setup Wizard if running in a graphical session
if [ -n "$WAYLAND_DISPLAY" ] || [ -n "$DISPLAY" ]; then
    echo -e "\n${MAGENTA}${BOLD}┌──────────────────────────────────────────────────────────┐${NC}"
    echo -e "${MAGENTA}${BOLD}│  🌙  Night Light Setup                                    │${NC}"
    echo -e "${MAGENTA}${BOLD}├──────────────────────────────────────────────────────────┤${NC}"
    echo -e "${MAGENTA}│  A settings window is opening on your screen.            ${MAGENTA}│${NC}"
    echo -e "${MAGENTA}│                                                           ${MAGENTA}│${NC}"
    echo -e "${MAGENTA}│  → Pick a color temperature preset that suits you.       ${MAGENTA}│${NC}"
    echo -e "${MAGENTA}│  → Fine-tune temperature (K) and brightness if needed.   ${MAGENTA}│${NC}"
    echo -e "${MAGENTA}│  → Click  💾 Apply & Continue  when you're happy.        ${MAGENTA}│${NC}"
    echo -e "${MAGENTA}│  → Or click  Skip  to use the default (3500K warm).     ${MAGENTA}│${NC}"
    echo -e "${MAGENTA}│                                                           ${MAGENTA}│${NC}"
    echo -e "${MAGENTA}│  You can always reopen it later with:  Super + Alt + N   ${MAGENTA}│${NC}"
    echo -e "${MAGENTA}${BOLD}└──────────────────────────────────────────────────────────┘${NC}"
    python3 "$HOME/.local/share/bin/nightlight-gui.py" --setup || true
fi



# Optional: Permanently disable pam_faillock account lockout policy on the system
DISABLE_FAILLOCK_OPTION="n"
echo -e "\n${YELLOW}[INFO] Entering a wrong sudo password multiple times can trigger user lockout (pam_faillock)"
echo -e "which locks your account for 10 minutes. You can permanently disable this policy.${NC}"
read -p "Do you want to permanently disable account lockouts on this system? (y/n) [n]: " faillock_choice
if [[ "$faillock_choice" =~ ^[Yy]$ ]]; then
    DISABLE_FAILLOCK_OPTION="y"
fi

if [ "$DISABLE_FAILLOCK_OPTION" = "y" ]; then
    echo -e "\n${BLUE}${BOLD}Permanently disabling pam_faillock lockout policy (setting deny = 0)...${NC}"
    FAILLOCK_CONF="/etc/security/faillock.conf"
    if [ -f "$FAILLOCK_CONF" ]; then
        if [ ! -f "${FAILLOCK_CONF}.bak" ]; then
            echo "Creating backup of $FAILLOCK_CONF..."
            sudo cp "$FAILLOCK_CONF" "${FAILLOCK_CONF}.bak"
        fi
        echo "Updating $FAILLOCK_CONF..."
        if grep -qE '^\s*#?\s*deny\s*=' "$FAILLOCK_CONF"; then
            sudo sed -i -E 's/^\s*#?\s*deny\s*=\s*[0-9]+/deny = 0/' "$FAILLOCK_CONF"
        else
            echo "deny = 0" | sudo tee -a "$FAILLOCK_CONF" >/dev/null
        fi
    fi
    PAM_FILES=("/etc/pam.d/system-auth" "/etc/pam.d/common-auth" "/etc/pam.d/password-auth")
    for PAM_FILE in "${PAM_FILES[@]}"; do
        if [ -f "$PAM_FILE" ]; then
            if grep -q "pam_faillock.so" "$PAM_FILE" && grep -q "deny=" "$PAM_FILE"; then
                if [ ! -f "${PAM_FILE}.bak" ]; then
                    echo "Creating backup of $PAM_FILE..."
                    sudo cp "$PAM_FILE" "${PAM_FILE}.bak"
                fi
                echo "Updating inline 'deny' parameter in $PAM_FILE..."
                sudo sed -i -E '/pam_faillock.so/s/deny=[0-9]+/deny=0/' "$PAM_FILE"
            fi
        fi
    done
    echo -e "${GREEN}[OK] pam_faillock lockout policy disabled successfully.${NC}"
fi

# --- CONFIGURE PYWAL INTEGRATION ---
echo -e "\n${BLUE}${BOLD}Configuring pywal templates and hooks...${NC}"
mkdir -p "$HOME/.config/wal/templates"

cat << 'EOF' > "$HOME/.config/wal/templates/colors-hyprland.conf"
general {{
    col.active_border = rgba({color4.strip}ff) rgba({color2.strip}ff) 45deg
    col.inactive_border = rgba({color1.strip}ff) rgba({color0.strip}ff) 45deg
}}

decoration {{
    shadow {{
        color = rgba({color4.strip}ff)
        color_inactive = rgba({color0.strip}55)
    }}
}}
EOF

cat << 'EOF' > "$HOME/.config/wal/templates/theme.css"
@define-color bar-bg rgba({color0.rgb}, 0.45);
@define-color main-bg rgba({color0.rgb}, 0.4);
@define-color main-fg {foreground};
@define-color wb-act-bg rgba({color1.rgb}, 0.4);
@define-color wb-act-fg {foreground};
@define-color wb-hvr-bg rgba({color2.rgb}, 0.4);
@define-color wb-hvr-fg {foreground};
EOF

cat << 'EOF' > "$HOME/.config/wal/templates/colors-hyprlock.conf"
$background = rgb({background.strip})
$foreground = rgb({foreground.strip})
$color0 = rgb({color0.strip})
$color1 = rgb({color1.strip})
$color2 = rgb({color2.strip})
$color3 = rgb({color3.strip})
$color4 = rgb({color4.strip})
$color5 = rgb({color5.strip})
$color6 = rgb({color6.strip})
$color7 = rgb({color7.strip})
$color8 = rgb({color8.strip})
$color9 = rgb({color9.strip})
$color10 = rgb({color10.strip})
$color11 = rgb({color11.strip})
$color12 = rgb({color12.strip})
$color13 = rgb({color13.strip})
$color14 = rgb({color14.strip})
$color15 = rgb({color15.strip})
EOF

# --- WRITE HYPRLOCK CONFIG ---
echo -e "${CYAN}Writing ~/.config/hypr/hyprlock.conf...${NC}"
mkdir -p "$HOME/.config/hypr"
cat << 'EOF' > "$HOME/.config/hypr/hyprlock.conf"
source = ~/.cache/wal/colors-hyprlock.conf

general {
    hide_cursor = true
}

background {
    monitor =
    path = ~/.cache/hyde/wall.blur
    blur_passes = 0
    blur_size = 0
    noise = 0.0117
    contrast = 0.8916
    brightness = 0.8172
    vibrancy = 0.1696
    vibrancy_darkness = 0.0
}


# Time (Clock)
label {
    monitor =
    text = cmd[update:1000] echo -e "$(env LC_ALL=en_US.UTF-8 date +"%I:%M %p")"
    color = $color3
    font_size = 94
    font_family = CaskaydiaCove Nerd Font Mono Bold
    position = 0, -100
    halign = center
    valign = top
}

# Date
label {
    monitor =
    text = cmd[update:1000] echo -e "$(env LC_ALL=en_US.UTF-8 date +"%A, %d %B")"
    color = $foreground
    font_size = 22
    font_family = CaskaydiaCove Nerd Font Mono
    position = 0, -260
    halign = center
    valign = top
}

# Greeting
label {
    monitor =
    text = cmd[update:3600000] echo "Hello, $USER"
    color = $foreground
    font_size = 20
    font_family = CaskaydiaCove Nerd Font Mono
    position = 0, -380
    halign = center
    valign = top
}

# Input Field (Password Box)
input-field {
    monitor =
    size = 260, 50
    outline_thickness = 1
    dots_size = 0.28
    dots_spacing = 0.15
    dots_center = true
    outer_color = rgba(255, 255, 255, 0.1)
    inner_color = rgba(255, 255, 255, 0.1)
    font_color = rgba(255, 255, 255, 0.8)
    check_color = rgba(255, 255, 255, 0.1)
    fail_color = rgba(255, 255, 255, 0.1)
    fade_on_empty = false
    placeholder_text = Use Me
    hide_input = false
    position = 0, -140
    halign = center
    valign = center
}
EOF



# --- WRITE TASKS MANAGER SCRIPT ---
echo -e "${CYAN}Writing ~/.local/share/bin/manage_tasks.py...${NC}"
mkdir -p "$HOME/.local/share/bin"
cat << 'EOF' > "$HOME/.local/share/bin/manage_tasks.py"
#!/usr/bin/env python3
import sys
import os

TASKS_FILE = os.path.expanduser("~/.config/fastfetch/tasks.txt")

def read_tasks():
    if not os.path.exists(TASKS_FILE):
        return []
    with open(TASKS_FILE, 'r') as f:
        return [line.strip() for line in f if line.strip()]

def write_tasks(tasks):
    os.makedirs(os.path.dirname(TASKS_FILE), exist_ok=True)
    with open(TASKS_FILE, 'w') as f:
        for t in tasks:
            f.write(t + "\n")

def add_or_update(task_text, new_prefix):
    tasks = read_tasks()
    found = False
    new_tasks = []
    
    cleaned_query = task_text.strip().lower()
    
    for t in tasks:
        content = t
        for pfx in ["[ ]", "[/]", "[x]", "- "]:
            if t.startswith(pfx):
                content = t[len(pfx):].strip()
                break
        
        if content.lower() == cleaned_query:
            new_tasks.append(f"{new_prefix} {content}")
            found = True
        else:
            new_tasks.append(t)
            
    if not found:
        new_tasks.append(f"{new_prefix} {task_text.strip()}")
        
    write_tasks(new_tasks)

def main():
    if len(sys.argv) < 3:
        print("Usage: manage_tasks.py <todo|doing|done> <task_text>")
        sys.exit(1)
        
    action = sys.argv[1]
    task_text = sys.argv[2]
    
    if action == "todo":
        add_or_update(task_text, "[ ]")
    elif action == "doing":
        add_or_update(task_text, "[/]")
    elif action == "done":
        add_or_update(task_text, "[x]")

if __name__ == "__main__":
    main()
EOF
chmod +x "$HOME/.local/share/bin/manage_tasks.py"

# --- WRITE BGAPPS SCRIPTS (window switcher helper) ---
echo -e "${CYAN}Writing ~/.local/share/bin/bgapps.sh...${NC}"
mkdir -p "$HOME/.local/share/bin"
cat << 'EOF' > "$HOME/.local/share/bin/bgapps.sh"
#!/usr/bin/env python3
"""Shows running Hyprland windows as icons for waybar."""
import json, subprocess

ICONS = {
    "firefox": "󰈹", "firefox-esr": "󰈹", "chromium": "󰊯",
    "google-chrome": "󰊯", "brave-browser": "󰖟", "antigravity": "󱪞",
    "code": "󰨞", "code-oss": "󰨞", "vscodium": "󰨞", "discord": "󰙯",
    "telegram-desktop": "󰔁", "spotify": "󰓇", "steam": "󰓓",
    "nautilus": "󰉋", "thunar": "󰉋", "dolphin": "󰉋",
    "kitty": "", "alacritty": "", "foot": "", "wezterm": "",
    "obsidian": "󰂺", "gimp": "", "vlc": "󰕼", "mpv": "󰎁",
    "pavucontrol": "󰕾", "libreoffice": "󰻫", "soffice": "󰻫",
    "zoom": "󰹿", "slack": "󰒱", "bitwarden": "󰌾",
}
DEFAULT_ICON = "󰣆"

try:
    result = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=2)
    clients = json.loads(result.stdout)
except Exception:
    print(""); exit(0)

if not clients:
    print(""); exit(0)

icons = [ICONS.get(c.get("class", "").lower(), DEFAULT_ICON) for c in clients]
print(" ".join(icons))
EOF

cat << 'EOF' > "$HOME/.local/share/bin/bgapps_pick.sh"
#!/usr/bin/env python3
"""Rofi picker for running Hyprland windows. Use: Super+Tab"""
import json, subprocess, sys

ICONS = {
    "firefox": "󰈹", "firefox-esr": "󰈹", "chromium": "󰊯",
    "google-chrome": "󰊯", "brave-browser": "󰖟", "antigravity": "󱪞",
    "code": "󰨞", "code-oss": "󰨞", "vscodium": "󰨞", "discord": "󰙯",
    "telegram-desktop": "󰔁", "spotify": "󰓇", "steam": "󰓓",
    "nautilus": "󰉋", "thunar": "󰉋", "dolphin": "󰉋",
    "kitty": "", "alacritty": "", "foot": "", "wezterm": "",
    "obsidian": "󰂺", "gimp": "", "vlc": "󰕼", "mpv": "󰎁",
    "pavucontrol": "󰕾", "libreoffice": "󰻫", "soffice": "󰻫",
    "zoom": "󰹿", "slack": "󰒱", "bitwarden": "󰌾",
}
DEFAULT_ICON = "󰣆"

try:
    result = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=2)
    clients = json.loads(result.stdout)
except Exception:
    sys.exit(0)

if not clients:
    sys.exit(0)

entries, addresses = [], []
for c in clients:
    cls = c.get("class", "")
    title = c.get("title", cls)[:50]
    icon = ICONS.get(cls.lower(), DEFAULT_ICON)
    entries.append(f"{icon}  {cls}  —  {title}")
    addresses.append(c.get("address", ""))

result = subprocess.run(
    ["rofi", "-dmenu", "-i", "-p", "Switch to",
     "-theme-str", "window { width: 50%; } listview { lines: 8; }",
     "-font", "JetBrainsMono Nerd Font 12"],
    input="\n".join(entries), capture_output=True, text=True
)

chosen = result.stdout.strip()
for i, entry in enumerate(entries):
    if entry == chosen:
        subprocess.run(["hyprctl", "dispatch", "focuswindow", f"address:{addresses[i]}"])
        break
EOF

chmod +x "$HOME/.local/share/bin/bgapps.sh" "$HOME/.local/share/bin/bgapps_pick.sh"
echo -e "${GREEN}bgapps scripts written.${NC}"
echo -e "${YELLOW}TIP: Use Super+Tab to switch between background apps via rofi${NC}"

# --- WRITE PRAYER TIMES SCRIPT ---
echo -e "${CYAN}Writing ~/.local/share/bin/prayer_times.py...${NC}"
mkdir -p "$HOME/.local/share/bin"
cat << 'EOF' > "$HOME/.local/share/bin/prayer_times.py"
#!/usr/bin/env python3
import urllib.request
import json
import datetime
import os
import sys

CACHE_FILE = "/tmp/prayer_times.json"

def get_location():
    try:
        req = urllib.request.Request(
            "http://ip-api.com/json",
            headers={"User-Agent": "Mozilla/5.0"}
        )
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode())
            return data.get("lat"), data.get("lon"), data.get("city")
    except Exception:
        return 30.0444, 31.2357, "Cairo"

def get_prayer_timings(lat, lon):
    today = datetime.date.today().isoformat()
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, 'r') as f:
                cached = json.load(f)
                if cached.get("date") == today:
                    return cached.get("timings")
        except Exception:
            pass

    try:
        url = f"http://api.aladhan.com/v1/timings?latitude={lat}&longitude={lon}&method=5"
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=5) as response:
            res = json.loads(response.read().decode())
            timings = res["data"]["timings"]
            with open(CACHE_FILE, 'w') as f:
                json.dump({"date": today, "timings": timings}, f)
            return timings
    except Exception:
        if os.path.exists(CACHE_FILE):
            try:
                with open(CACHE_FILE, 'r') as f:
                    return json.load(f).get("timings")
            except Exception:
                pass
        return None

def parse_time(time_str):
    parts = time_str.split(":")
    return int(parts[0]), int(parts[1])

def main():
    lat, lon, city = get_location()
    timings = get_prayer_timings(lat, lon)
    if not timings:
        print("No timings")
        sys.exit(0)

    prayers = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    now = datetime.datetime.now()
    
    prayer_times = []
    for p in prayers:
        t_str = timings.get(p)
        if not t_str:
            continue
        h, m = parse_time(t_str)
        p_time = now.replace(hour=h, minute=m, second=0, microsecond=0)
        prayer_times.append((p, p_time))

    next_p = None
    next_p_time = None

    for name, p_time in prayer_times:
        if p_time > now:
            next_p = name
            next_p_time = p_time
            break

    if not next_p:
        next_p = "Fajr"
        f_str = timings.get("Fajr")
        h, m = parse_time(f_str)
        next_p_time = now.replace(hour=h, minute=m, second=0, microsecond=0) + datetime.timedelta(days=1)

    diff = next_p_time - now
    diff_seconds = diff.total_seconds()
    hours = int(diff_seconds // 3600)
    minutes = int((diff_seconds % 3600) // 60)
    seconds = int(diff_seconds % 60)

    next_p_time_str = next_p_time.strftime("%I:%M %p").lstrip('0')
    print(f"{next_p} in {hours}:{minutes:02d}:{seconds:02d} ({next_p_time_str})")

if __name__ == "__main__":
    main()
EOF
chmod +x "$HOME/.local/share/bin/prayer_times.py"

# --- WRITE SDDM XSETUP SCRIPT ---
echo -e "${CYAN}Writing /usr/share/sddm/scripts/Xsetup...${NC}"
sudo mkdir -p /usr/share/sddm/scripts
sudo tee /usr/share/sddm/scripts/Xsetup >/dev/null << 'XSEOF'
#!/bin/sh
# Xsetup - run as root before the login dialog appears

# 1. Configure monitors dynamically (keep primary monitor and position secondary screens)
CONNECTED_MONITORS=$(xrandr | grep " connected" | awk '{print $1}')
MONITOR_COUNT=$(echo "$CONNECTED_MONITORS" | wc -l)
if [ "$MONITOR_COUNT" -gt 1 ]; then
    TARGET_MON=$(cat /etc/sddm.conf.d/target_monitor 2>/dev/null | tr -d '[:space:]')
    PRIMARY_MONITOR=""
    if [ -n "$TARGET_MON" ] && echo "$CONNECTED_MONITORS" | grep -qx "$TARGET_MON"; then
        PRIMARY_MONITOR="$TARGET_MON"
    fi
    
    if [ -z "$PRIMARY_MONITOR" ]; then
        PRIMARY_MONITOR=$(echo "$CONNECTED_MONITORS" | head -n 1)
    fi

    if [ -n "$PRIMARY_MONITOR" ]; then
        xrandr --output "$PRIMARY_MONITOR" --auto --primary 2>/dev/null || true
        for mon in $CONNECTED_MONITORS; do
            if [ "$mon" != "$PRIMARY_MONITOR" ]; then
                xrandr --output "$mon" --auto --right-of "$PRIMARY_MONITOR" 2>/dev/null || true
            fi
        done
    fi
fi

# 2. Set mouse sensitivity and flat acceleration profile
for id in $(xinput list --id-only 2>/dev/null); do
    xinput set-prop "$id" "libinput Accel Profile Enabled" 0 1 0 2>/dev/null || true
    xinput set-prop "$id" "libinput Accel Speed" -0.5 2>/dev/null || true
done

# 3. Start gammastep for SDDM night light
PRIMARY_USER=$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd | head -n 1)
PRIMARY_HOME=$(getent passwd "$PRIMARY_USER" | cut -d: -f6)
CONF="$PRIMARY_HOME/.config/hypr/nightlight.conf"
TEMP=3500
ENABLED=true

if [ -f "$CONF" ]; then
    t=$(grep -oP 'temperature=\K\d+' "$CONF" 2>/dev/null)
    e=$(grep -oP 'enabled=\K\w+'     "$CONF" 2>/dev/null)
    [ -n "$t" ] && TEMP=$t
    [ "$e" = "false" ] && ENABLED=false
fi

if [ "$ENABLED" = "true" ]; then
    pkill -x gammastep 2>/dev/null || true
    gammastep -O "$TEMP" -P &
fi
XSEOF
sudo chmod +x /usr/share/sddm/scripts/Xsetup

# Patch swwwallbash.sh if not already patched
SWWWALLBASH_BIN="$HOME/.local/share/bin/swwwallbash.sh"
if [ -f "$SWWWALLBASH_BIN" ]; then
    if ! grep -q "wal -i" "$SWWWALLBASH_BIN"; then
        echo -e "${CYAN}Adding pywal automatic hook to swwwallbash.sh...${NC}"
        echo "" >> "$SWWWALLBASH_BIN"
        echo "# Trigger pywal automatically on wallpaper change" >> "$SWWWALLBASH_BIN"
        echo "wal -i \"\${wallbashImg}\"" >> "$SWWWALLBASH_BIN"
    fi
fi

# --- WRITE ADDWALLPAPER SCRIPT ---
echo -e "${CYAN}Writing ~/.local/share/bin/addwallpaper...${NC}"
mkdir -p "$HOME/.local/share/bin"
cat << 'EOF' > "$HOME/.local/share/bin/addwallpaper"
#!/usr/bin/env bash
# addwallpaper - Add wallpapers to the active theme

# Get current theme
hydeTheme=$(grep '^hydeTheme=' "$HOME/.config/hyde/hyde.conf" | cut -d'"' -f2)
if [ -z "$hydeTheme" ]; then
    hydeTheme="Nordic Blue"
fi

DEST_DIR="$HOME/.config/hyde/themes/${hydeTheme}/wallpapers"
mkdir -p "$DEST_DIR"

files=()

if [ $# -gt 0 ]; then
    for arg in "$@"; do
        if [ -f "$arg" ]; then
            files+=("$arg")
        else
            echo "Error: File '$arg' does not exist."
        fi
    done
else
    # Use zenity to pick files
    picked=$(zenity --file-selection --multiple --file-filter="Images (png, jpg, jpeg, gif) | *.png *.jpg *.jpeg *.gif" --title="Select Wallpapers to Add" 2>/dev/null)
    if [ -n "$picked" ]; then
        # Zenity returns files separated by '|'
        IFS='|' read -ra ADDR <<< "$picked"
        for file in "${ADDR[@]}"; do
            if [ -f "$file" ]; then
                files+=("$file")
            fi
        done
    fi
fi

if [ ${#files[@]} -eq 0 ]; then
    echo "No wallpapers selected."
    exit 0
fi

for f in "${files[@]}"; do
    filename=$(basename "$f")
    cp "$f" "$DEST_DIR/$filename"
    echo "Added '$filename' to $hydeTheme wallpapers."
    last_added="$DEST_DIR/$filename"
done
EOF
chmod +x "$HOME/.local/share/bin/addwallpaper"
echo -e "${GREEN}addwallpaper utility script written.${NC}"

# --- WRITE LOCKSCREEN WRAPPER SCRIPT ---
echo -e "${CYAN}Writing ~/.local/share/bin/lockscreen.sh...${NC}"
mkdir -p "$HOME/.local/share/bin"
cat << 'EOF' > "$HOME/.local/share/bin/lockscreen.sh"
#!/usr/bin/env bash
# lockscreen.sh - Helper script to dynamically identify the active/focused monitor 
# and lock the system showing the widgets only on that monitor.

mkdir -p "$HOME/.cache/hypr"

# Get active/focused monitor name
focused_mon=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name' 2>/dev/null)

# Fallback to first monitor in list if not found
if [ -z "$focused_mon" ]; then
    focused_mon=$(hyprctl monitors -j | jq -r '.[0].name' 2>/dev/null)
fi

# Fallback to default if everything else fails
if [ -z "$focused_mon" ]; then
    focused_mon="DP-2"
fi

# Write monitor variable to be sourced by hyprlock.conf
echo "\$main_monitor = $focused_mon" > "$HOME/.cache/hypr/lock_monitor.conf"

# Launch hyprlock
hyprlock
EOF
chmod +x "$HOME/.local/share/bin/lockscreen.sh"
echo -e "${GREEN}lockscreen wrapper script written.${NC}"


# --- WRITE OMAR CUSTOM DOCUMENTATION TOOL ---
echo -e "${CYAN}Writing ~/.local/share/bin/omar custom documentation helper...${NC}"
mkdir -p "$HOME/.local/share/bin"
cat << 'EOF' > "$HOME/.local/share/bin/omar"
#!/usr/bin/env bash
#===============================================================================
#   Omar's CachyOS + Hyprland Tools & Documentation Command (Iconless & Concise)
#   Part of: CachyOS + HyDE System Restorer
#===============================================================================

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

cat << "OEOF"
  ==============================================================
            OMAR'S CACHYOS & HYPRLAND CONTROL CENTER
  ==============================================================
OEOF

echo -e "\n${CYAN}${BOLD}Control Panel:${NC}"
echo -e "  ${GREEN}cachy_tools_menu.sh${NC}          : Launch interactive CLI / Rofi GUI control panel"

echo -e "\n${MAGENTA}${BOLD}Appearance & Theme:${NC}"
echo -e "  ${YELLOW}omar-fav-setup.sh${NC}            : Apply Glassmorphism Waybar & wallpaper"
echo -e "  ${YELLOW}setup-waybar-glassmorphism.sh${NC}: Configure 3-island floating Waybar"
echo -e "  ${YELLOW}setup-notifications-theme.py${NC} : Customize Dunst notification popups"

echo -e "\n${BLUE}${BOLD}Display, Screen & Cursor:${NC}"
echo -e "  ${CYAN}hypr-display-settings.py${NC}     : Resolution, custom Hz text entry, scaling & mouse"
echo -e "  ${CYAN}sddm-screen-config.py${NC}        : Select monitor for SDDM login screen"
echo -e "  ${CYAN}setup-initial-cursor-screen.py${NC}: Select default screen for cursor on boot"
echo -e "  ${CYAN}monitor-alignment.sh${NC}         : Dual monitor cursor alignment calibration"
echo -e "  ${CYAN}nightlight-gui.py${NC}            : Screen warmth slider (0%-100%) with auto-save"

echo -e "\n${GREEN}${BOLD}Development & WordPress:${NC}"
echo -e "  ${GREEN}setup-wordpress-local.sh${NC}     : Install LocalWP tool"
echo -e "  ${GREEN}fix-polkit-localwp.sh${NC}        : Fix Polkit auth & sync site domains to /etc/hosts"

echo -e "\n${YELLOW}${BOLD}Todo Task Manager:${NC}"
echo -e "  ${MAGENTA}todo <text>${NC}                  : Add new task to list"
echo -e "  ${MAGENTA}doing${NC}                        : Pick task via GUI/CLI & mark in-progress [/]"
echo -e "  ${MAGENTA}donetask${NC}                     : Pick task via GUI/CLI & mark completed [x]"
echo -e "  ${MAGENTA}rmtask${NC}                       : Pick task via GUI/CLI & remove from list"
echo -e "  ${MAGENTA}edittask${NC}                     : Pick task via GUI/CLI & edit description"
echo -e "  ${MAGENTA}task-manager-gui.py${NC}          : Launch interactive Task Manager GUI"

echo -e "\n${CYAN}${BOLD}Shortcuts & Utilities:${NC}"
echo -e "  ${CYAN}double-pageup.sh${NC}             : Trigger double PageUp keybinding"
echo -e "  ${CYAN}start_hotspot.sh${NC}             : Launch Wi-Fi hotspot with QR code"
echo -e "  ${CYAN}addwallpaper${NC}                 : Add wallpapers to current theme folder"

echo -e "\n${CYAN}--------------------------------------------------------------${NC}"
echo -e " Tip: Run ${YELLOW}cachy_tools_menu.sh --gui${NC} for graphical launcher menu"
echo -e "${CYAN}--------------------------------------------------------------${NC}\n"
EOF
chmod +x "$HOME/.local/share/bin/omar"
echo -e "${GREEN}omar custom documentation script written.${NC}"





# Execute Task Manager Setup (deploys task commands, fastfetch tasks.txt & zsh/fish integration)
if [ -f "$SCRIPT_DIR/setup-task-manager.sh" ]; then
    echo -e "${CYAN}Executing setup-task-manager.sh (deploying todo, doing, donetask, rmtask, edittask, GUI)...${NC}"
    bash "$SCRIPT_DIR/setup-task-manager.sh" || true
fi

# Deploy all unified repo scripts to user bin
if [ -d "$SCRIPT_DIR" ]; then
    mkdir -p "$HOME/.local/share/bin"
    for tool in cachy_tools_menu.sh omar-fav-setup.sh setup-wordpress-local.sh fix-polkit-localwp.sh setup-waybar-glassmorphism.sh hypr-display-settings.py nightlight-gui.py sddm-screen-config.py setup-sddm-screen.sh setup_clipboard.sh setup_arabic_keyboard.sh setup-task-manager.sh task-manager-gui.py setup-notifications-theme.py setup-zen-browser-theme.sh setup-initial-cursor-screen.py interactive_restore.sh doing donetask todo rmtask edittask manage_tasks.py omar; do
        if [ -f "$SCRIPT_DIR/$tool" ]; then
            cp "$SCRIPT_DIR/$tool" "$HOME/.local/share/bin/"
            chmod +x "$HOME/.local/share/bin/$tool"
        fi
    done
fi

fi # End of opt_deploy_dots

echo -e "\n${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}${BOLD}   CONGRATULATIONS! System Restoration is Complete!                  ${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}"
read -p "Would you like to reboot the system now to apply all changes? (y/n) [y]: " reboot_confirm
reboot_confirm="${reboot_confirm:-y}"
if [[ "$reboot_confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Rebooting the system in 5 seconds...${NC}"
    for i in {5..1}; do
        echo -e "  Rebooting in ${CYAN}$i${NC} seconds..."
        sleep 1
    done
    echo -e "${BLUE}Rebooting now...${NC}"
    sudo reboot
else
    echo -e "${GREEN}[OK] Done! Please reboot manually later to apply all configurations.${NC}"
fi
