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
REPO_URL="https://github.com/omarahmed321/cachy-os-config-related.git"

# The installer copies many files that live next to it (monitor engine, GUIs,
# task scripts, Xsetup...). When it was piped in (`curl ... | bash`) or copied
# out of the repo on its own, clone the repo and re-run from there. That also
# gives `read` the terminal: under `curl | bash` stdin is the script itself.
if [ ! -f "$SCRIPT_DIR/hypr-monitor-setup.py" ] || [ ! -t 0 ]; then
    if [ -z "${CACHY_RESTORE_REEXEC:-}" ]; then
        if ! ( : </dev/tty ) 2>/dev/null; then
            echo "No terminal available for the installer's questions. Run instead:" >&2
            echo "  git clone $REPO_URL && bash cachy-os-config-related/restore_my_setup.sh" >&2
            exit 1
        fi
        CLONE_DIR="$HOME/cachy-os-config-related"
        command -v git >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm git </dev/tty || exit 1
        if [ -d "$CLONE_DIR/.git" ]; then
            git -C "$CLONE_DIR" pull --ff-only </dev/tty || true
        else
            git clone --depth 1 "$REPO_URL" "$CLONE_DIR" </dev/tty || exit 1
        fi
        CACHY_RESTORE_REEXEC=1 exec bash "$CLONE_DIR/restore_my_setup.sh" "$@" </dev/tty
    fi
fi

# Detect the GPU up front: later sections (Nvidia modprobe, hypr env) need it
# even when the package step is skipped
GPU_VENDOR="unknown"
if lspci 2>/dev/null | grep -Ei "vga|3d|display" | grep -iq nvidia; then
    GPU_VENDOR="nvidia"
elif lspci 2>/dev/null | grep -Ei "vga|3d|display" | grep -iq "amd\|ati"; then
    GPU_VENDOR="amd"
elif lspci 2>/dev/null | grep -Ei "vga|3d|display" | grep -iq intel; then
    GPU_VENDOR="intel"
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
# Full upgrade: installing after a bare -Sy is an unsupported partial upgrade
sudo pacman -Syu --noconfirm

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
AUTO_GPU="$GPU_VENDOR"

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
    hyprland waybar dunst rofi kitty firefox zen-browser-bin code dolphin yazi sddm-astronaut-theme
    swaylock-effects-git wlogout cliphist hyprpicker hyprsunset hyprlock
    grimblast-git slurp jq polkit-kde-agent eza awesome-terminal-fonts
    ttf-meslo-nerd ttf-jetbrains-mono-nerd blueman bluez bluez-utils
    network-manager-applet brightnessctl pamixer playerctl udiskie
    nwg-look kvantum kvantum-qt5 qt5ct qt6ct qt5-wayland qt6-wayland qt6-5compat qt6-virtualkeyboard qt6-multimedia
    awww parallel pacman-contrib imagemagick ffmpegthumbs kde-cli-tools
    bc antigravity antigravity-ide antigravity-cli prismlauncher cava tk python-gobject libadwaita
    wtype gnome-keyring ttf-cascadia-code-nerd python-pywal
    oh-my-zsh-git zsh-theme-powerlevel10k zsh-autosuggestions
    zsh-syntax-highlighting zsh-completions
    wl-clipboard qt5-graphicaleffects qt5-quickcontrols qt5-quickcontrols2
    seahorse networkmanager zenity fastfetch bibata-cursor-theme-bin fzf
    psmisc python dnsmasq hostapd iw sddm ananicy-cpp gammastep
    pipewire pipewire-pulse pipewire-alsa wireplumber libpulse usbutils pciutils
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-user-dirs
)

# CachyOS-only packages: skipped on plain Arch, where they do not exist
pacman -Si cachyos-fish-config &>/dev/null && REQUIRED_PACKAGES+=(cachyos-fish-config)

# TP-Link TL-WN722N v2/v3 (RTL8188EUS) USB Wi-Fi: out-of-tree driver only when it is plugged in
if lsusb 2>/dev/null | grep -qiE "2357:010c|0bda:8179|0bda:0179"; then
    HAS_RTL8188EUS=true
    REQUIRED_PACKAGES+=(8188eu-dkms)
else
    HAS_RTL8188EUS=false
fi

# Dynamically add GPU drivers based on detected hardware
if [ "$GPU_VENDOR" = "nvidia" ]; then
    echo -e "${CYAN}Adding Nvidia open kernel modules and Wayland support packages...${NC}"
    # CachyOS ships prebuilt modules per kernel (linux-cachyos-nvidia-open, ...);
    # elsewhere use DKMS. nvidia-dkms no longer exists. GTX 10xx and older need a legacy driver.
    NV_MODULES=()
    for kernel in $(pacman -Qq 2>/dev/null | grep -E '^linux-cachyos(-[a-z]+)?$'); do
        pacman -Si "${kernel}-nvidia-open" &>/dev/null && NV_MODULES+=("${kernel}-nvidia-open")
    done
    [ ${#NV_MODULES[@]} -eq 0 ] && NV_MODULES=(nvidia-open-dkms)
    REQUIRED_PACKAGES+=("${NV_MODULES[@]}" nvidia-utils lib32-nvidia-utils egl-wayland libva-nvidia-driver)
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
    if [ "$pkg" = "8188eu-dkms" ]; then
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
for svc in bluetooth NetworkManager ananicy-cpp; do
    verify_and_start_service "$svc"
done
# Enable only: starting a display manager now would take over the current tty
# (or clash with another running DM). It starts on the next boot.
for dm in gdm lightdm lxdm ly greetd; do
    systemctl is-enabled "$dm" &>/dev/null && sudo systemctl disable "$dm" 2>/dev/null
done
sudo systemctl enable sddm && echo -e "  - ${GREEN}[Enabled]${NC} sddm (starts on next boot)"
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
ORIG_LOGIN_SHELL="$(getent passwd "$USER" | cut -d: -f7)"
echo -e "\n\n\nn" | ./install.sh
# HyDE switches the login shell to the first of zsh/fish it finds installed;
# keep fish for users who had it (CachyOS default)
if [[ "$ORIG_LOGIN_SHELL" == */fish ]] && [ "$(getent passwd "$USER" | cut -d: -f7)" != "$ORIG_LOGIN_SHELL" ]; then
    chsh -s "$ORIG_LOGIN_SHELL" </dev/tty || true
fi

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
install -D -m 755 "$SCRIPT_DIR/double-pageup.sh" "$HOME/.local/bin/double-pageup.sh"
chmod +x "$HOME/.local/bin/double-pageup.sh"

# --- WRITE ~/start_hotspot.sh ---
echo -e "${CYAN}Writing ~/start_hotspot.sh...${NC}"
install -D -m 755 "$SCRIPT_DIR/start_hotspot.sh" "$HOME/start_hotspot.sh"
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
install -D -m 755 "$SCRIPT_DIR/hypr-display-settings.py" "$HOME/.local/share/bin/hypr-display-settings.py"
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
install -D -m 755 "$SCRIPT_DIR/nightlight-gui.py" "$HOME/.local/share/bin/nightlight-gui.py"
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

# Move the active window to the screen on the left/right/above/below with mainMod + SHIFT + CTRL [←→↑↓]
bindd = $mainMod SHIFT CTRL, left, Move window to left monitor, movewindow, mon:l
bindd = $mainMod SHIFT CTRL, right, Move window to right monitor, movewindow, mon:r
bindd = $mainMod SHIFT CTRL, up, Move window to upper monitor, movewindow, mon:u
bindd = $mainMod SHIFT CTRL, down, Move window to lower monitor, movewindow, mon:d

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



# --- WRITE ~/.config/hypr/monitors.conf (N-monitor engine) ---
# hypr-monitor-setup.py handles any number of screens: native mode at max Hz,
# VRR only where the EDID advertises Adaptive-Sync, ICC profiles, rotated-width
# offsets and workspaces 1-10 spread over all screens.
echo -e "${CYAN}Detecting connected monitors...${NC}"
mkdir -p "$HOME/.local/share/bin"
MON_ENGINE="$HOME/.local/share/bin/hypr-monitor-setup.py"
cp "$SCRIPT_DIR/hypr-monitor-setup.py" "$MON_ENGINE" && chmod +x "$MON_ENGINE"
python3 "$MON_ENGINE" --list || true
read -r -p "Set screen order, primary screen and rotation now? (y/n) [y]: " mon_choice
mon_choice="${mon_choice:-y}"
if [[ "$mon_choice" =~ ^[Yy]$ ]]; then
    python3 "$MON_ENGINE" --interactive --no-apply || python3 "$MON_ENGINE" --auto --no-apply
else
    python3 "$MON_ENGINE" --auto --no-apply
fi
PRIMARY_MONITOR="$(python3 "$MON_ENGINE" --get-primary 2>/dev/null)"

if [ -n "$PRIMARY_MONITOR" ]; then
    # SDDM shows only on the primary screen (all others are switched off at the greeter)
    python3 "$SCRIPT_DIR/sddm-screen-config.py" --set "$PRIMARY_MONITOR" || true
    # The mouse cursor starts on the primary screen after login
    python3 "$SCRIPT_DIR/setup-initial-cursor-screen.py" --set "$PRIMARY_MONITOR" || true
    echo -e "${GREEN}[OK] Primary screen: $PRIMARY_MONITOR (login screen + boot cursor)${NC}"
    # GPUs with several HDMI/DP screens: send sound to the one on the primary screen
    if command -v pactl &>/dev/null && pactl info &>/dev/null; then
        python3 "$SCRIPT_DIR/setup-hdmi-audio.py" --auto || true
    fi
fi

# Fine-tune alignment live, only inside a running Hyprland session with 2+ screens
cp "$SCRIPT_DIR/monitor-alignment.sh" "$HOME/.local/share/bin/" && chmod +x "$HOME/.local/share/bin/monitor-alignment.sh"
if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && [ "$(hyprctl monitors -j 2>/dev/null | jq 'length' 2>/dev/null || echo 0)" -gt 1 ]; then
    read -r -p "Fine-tune monitor alignment live now? (y/n) [n]: " calib_choice
    if [[ "$calib_choice" =~ ^[Yy]$ ]]; then
        python3 "$MON_ENGINE" --calibrate
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
# Only on machines with a TP-Link TL-WN722N v2/v3 plugged in: blacklisting the
# in-kernel rtl8xxxu driver elsewhere would break other Realtek adapters.
[ -z "${HAS_RTL8188EUS:-}" ] && { lsusb 2>/dev/null | grep -qiE "2357:010c|0bda:8179|0bda:0179" && HAS_RTL8188EUS=true || HAS_RTL8188EUS=false; }
if [ "$HAS_RTL8188EUS" = "true" ]; then
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
elif [ "$GPU_VENDOR" = "amd" ] || [ "$GPU_VENDOR" = "intel" ]; then
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
 * Zen Browser - Web Content Font & Page Optimization
 */

/* Empty / New Tab page background */
@-moz-document url("about:blank"), url("about:newtab"), url("about:home") {
    :root, body, html {
        background-color: #0e0f0e !important;
    }
}

/* Smooth font rendering on all websites */
@-moz-document url-prefix(http), url-prefix(https), url-prefix(about:) {
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
    echo -e "${MAGENTA}│  → Toggle night light and drag the warmth slider.        ${MAGENTA}│${NC}"
    echo -e "${MAGENTA}│  → Changes save automatically.                            ${MAGENTA}│${NC}"
    echo -e "${MAGENTA}│  → Close the window to continue the installation.        ${MAGENTA}│${NC}"
    echo -e "${MAGENTA}│                                                           ${MAGENTA}│${NC}"
    echo -e "${MAGENTA}│  You can always reopen it later with:  Super + Alt + N   ${MAGENTA}│${NC}"
    echo -e "${MAGENTA}${BOLD}└──────────────────────────────────────────────────────────┘${NC}"
    python3 "$HOME/.local/share/bin/nightlight-gui.py" || true
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
install -D -m 755 "$SCRIPT_DIR/manage_tasks.py" "$HOME/.local/share/bin/manage_tasks.py"
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
install -D -m 755 "$SCRIPT_DIR/prayer_times.py" "$HOME/.local/share/bin/prayer_times.py"
chmod +x "$HOME/.local/share/bin/prayer_times.py"

# --- INSTALL SDDM XSETUP SCRIPT (login screen on the primary monitor only) ---
echo -e "${CYAN}Installing /usr/share/sddm/scripts/Xsetup...${NC}"
sudo install -D -m 755 "$SCRIPT_DIR/sddm-Xsetup.sh" /usr/share/sddm/scripts/Xsetup

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
    for tool in cachy_tools_menu.sh omar-fav-setup.sh setup-wordpress-local.sh fix-polkit-localwp.sh setup-waybar-glassmorphism.sh hypr-display-settings.py nightlight-gui.py sddm-screen-config.py sddm-Xsetup.sh hypr-monitor-setup.py setup-hdmi-audio.py setup-sddm-screen.sh setup_clipboard.sh setup_arabic_keyboard.sh setup-task-manager.sh task-manager-gui.py setup-notifications-theme.py setup-zen-browser-theme.sh setup-initial-cursor-screen.py interactive_restore.sh doing donetask todo rmtask edittask manage_tasks.py omar; do
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
