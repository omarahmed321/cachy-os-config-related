#!/usr/bin/env bash
#===============================================================================
#   Lightweight CachyOS + Hyprland + HyDE System Restorer
#   Copies modular config files directly from the repository instead of generating
#   them inline. Keep the installation process extremely clean and fast!
#===============================================================================

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Root Check ---
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}[ERROR] Please do NOT run this script as root directly. Use your normal user account. It will elevate via sudo when needed.${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect existing AUR helper at startup
AUR_HELPER=""
if command -v yay &>/dev/null; then
    AUR_HELPER="yay"
elif command -v paru &>/dev/null; then
    AUR_HELPER="paru"
fi

# Self-healing helper: check and fix pacman database lock
fix_pacman_lock() {
    if [ -f "/var/lib/pacman/db.lck" ]; then
        echo -e "${YELLOW}[!] Pacman database is locked. Attempting self-healing...${NC}"
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

verify_and_start_service() {
    local service_name="$1"
    echo -e "${CYAN}[*] Enabling and starting service: $service_name...${NC}"
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl reset-failed "$service_name" 2>/dev/null || true
    if sudo systemctl enable --now "$service_name" 2>/dev/null; then
        echo -e "  - ${GREEN}[Active]${NC} $service_name service started successfully."
    else
        echo -e "${RED}[!] Failed to start $service_name. Retrying...${NC}"
        sudo systemctl restart "$service_name" 2>/dev/null || true
    fi
}

# --- Welcome & Interactive Options ---
clear
echo -e "${BLUE}${BOLD}==============================================================${NC}"
echo -e "${BLUE}${BOLD}         Modular CachyOS + Hyprland Installation Restorer     ${NC}"
echo -e "${BLUE}${BOLD}==============================================================${NC}"

read -p "Proceed with the restoration? (y/n) [y]: " main_confirm
main_confirm="${main_confirm:-y}"
if [[ ! "$main_confirm" =~ ^[Yy]$ ]]; then
    echo -e "${RED}[INFO] Setup aborted by user.${NC}"
    exit 0
fi

read -p "Install/upgrade required system packages? (y/n) [y]: " opt_install_pkgs
opt_install_pkgs="${opt_install_pkgs:-y}"

read -p "Deploy/upgrade the HyDE Desktop Environment framework? (y/n) [y]: " opt_deploy_hyde
opt_deploy_hyde="${opt_deploy_hyde:-y}"

read -p "Copy customized dotfiles (Hyprland, Waybar, Zsh, Kitty, Cava, VS Code)? (y/n) [y]: " opt_deploy_dots
opt_deploy_dots="${opt_deploy_dots:-y}"

read -p "Install helper scripts (start_hotspot, double-pageup, display settings)? (y/n) [y]: " opt_helper_scripts
opt_helper_scripts="${opt_helper_scripts:-y}"

read -p "Permanently disable pam_faillock lockout policy (prevent wrong password lockouts)? (y/n) [y]: " opt_disable_faillock
opt_disable_faillock="${opt_disable_faillock:-y}"

# --- Step 1: Packages ---
if [[ "$opt_install_pkgs" =~ ^[Yy]$ ]]; then
    echo -e "\n${BLUE}${BOLD}[1/4] Checking and installing required packages...${NC}"
    
    # Identify or install AUR helper
    if [ -z "$AUR_HELPER" ]; then
        echo -e "${YELLOW}[INFO] Installing yay AUR helper...${NC}"
        fix_pacman_lock
        sudo pacman -S --needed --noconfirm base-devel git
        rm -rf /tmp/yay-bin
        git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
        if cd /tmp/yay-bin && makepkg -si --noconfirm && cd - &>/dev/null; then
            rm -rf /tmp/yay-bin
        fi
        
        # Verify installation
        if command -v yay &>/dev/null; then
            AUR_HELPER="yay"
        elif command -v paru &>/dev/null; then
            AUR_HELPER="paru"
        else
            echo -e "${RED}[ERROR] Failed to install yay AUR helper. Arch Linux requires an AUR helper to install packages. Exiting...${NC}"
            exit 1
        fi
    fi
    
    # Sync database & perform full system upgrade to prevent partial upgrade dependencies breakage
    fix_pacman_lock
    echo -e "${CYAN}Running full system database sync and update...${NC}"
    sudo pacman -Syu --noconfirm
    
    echo -e "${CYAN}Updating package keyrings to prevent signature errors...${NC}"
    sudo pacman -S --needed --noconfirm archlinux-keyring 2>/dev/null || true
    if pacman -Si cachyos-keyring &>/dev/null; then
        sudo pacman -S --needed --noconfirm cachyos-keyring 2>/dev/null || true
    fi
    
    # GPU detection
    AUTO_GPU="unknown"
    gpu_info=$(lspci | grep -Ei "vga|3d")
    if echo "$gpu_info" | grep -iq "nvidia"; then
        AUTO_GPU="nvidia"
    elif echo "$gpu_info" | grep -iq "amd"; then
        AUTO_GPU="amd"
    elif echo "$gpu_info" | grep -iq "intel"; then
        AUTO_GPU="intel"
    fi

    echo -e "\nDetected GPU Vendor: ${CYAN}${AUTO_GPU}${NC}"
    echo -e "Which graphics driver configuration would you like to use?"
    echo -e "1) Automatically detected (${AUTO_GPU})"
    echo -e "2) Nvidia proprietary drivers"
    echo -e "3) AMD open-source drivers"
    echo -e "4) Intel open-source drivers"
    echo -e "5) Skip GPU-specific drivers"
    read -p "Select choice [1-5] (Default 1): " gpu_choice
    gpu_choice="${gpu_choice:-1}"

    GPU_VENDOR="$AUTO_GPU"
    if [ "$gpu_choice" -eq 2 ]; then
        GPU_VENDOR="nvidia"
    elif [ "$gpu_choice" -eq 3 ]; then
        GPU_VENDOR="amd"
    elif [ "$gpu_choice" -eq 4 ]; then
        GPU_VENDOR="intel"
    elif [ "$gpu_choice" -eq 5 ]; then
        GPU_VENDOR="skip"
    fi
    
    REQUIRED_PACKAGES=(
        hyprland waybar dunst rofi-wayland kitty firefox zen-browser-bin code dolphin yazi sddm-astronaut-theme
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
        seahorse networkmanager zenity fastfetch bibata-cursor-theme-bin fzf cachyos-fish-config
        psmisc python dnsmasq hostapd iw sddm ananicy-cpp gammastep
        pipewire pipewire-pulse pipewire-alsa wireplumber
        xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-user-dirs
    )

    if [ "$GPU_VENDOR" = "nvidia" ]; then
        REQUIRED_PACKAGES+=(nvidia-dkms nvidia-utils lib32-nvidia-utils egl-wayland libva-nvidia-driver)
    elif [ "$GPU_VENDOR" = "amd" ]; then
        REQUIRED_PACKAGES+=(mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon libva-mesa-driver lib32-libva-mesa-driver)
    elif [ "$GPU_VENDOR" = "intel" ]; then
        REQUIRED_PACKAGES+=(mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver)
    fi

    # Install packages
    TO_INSTALL=()
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if pacman -Qi "$pkg" &>/dev/null; then
            echo -e "  - ${GREEN}[Installed]${NC} $pkg"
        else
            TO_INSTALL+=("$pkg")
        fi
    done

    if [ ${#TO_INSTALL[@]} -gt 0 ]; then
        echo -e "${YELLOW}Installing missing packages...${NC}"
        fix_pacman_lock
        $AUR_HELPER -S --noconfirm "${TO_INSTALL[@]}"
    fi

    # Services
    for svc in bluetooth NetworkManager sddm ananicy-cpp; do
        verify_and_start_service "$svc"
    done
fi

# --- Step 2: HyDE Base Deployment ---
if [[ "$opt_deploy_hyde" =~ ^[Yy]$ ]]; then
    echo -e "\n${BLUE}${BOLD}[2/4] Deploying HyDE Desktop Environment Base Framework...${NC}"
    if [ ! -d "$HOME/hyde" ]; then
        git clone https://github.com/prasanthrangan/hyprdots.git "$HOME/hyde"
    fi
    export aurhlpr="$AUR_HELPER"
    export myShell="zsh"
    cd "$HOME/hyde/Scripts" && echo -e "\n\n\nn" | ./install.sh && cd -
fi

# --- Step 3: Copy Customized Dotfiles ---
if [[ "$opt_deploy_dots" =~ ^[Yy]$ ]]; then
    echo -e "\n${BLUE}${BOLD}[3/4] Copying customized configuration files from repository...${NC}"
    
    # Update/create default user directories (Downloads, Documents, etc.)
    if command -v xdg-user-dirs-update &>/dev/null; then
        echo -e "${CYAN}Initializing default user directories (Downloads, Documents, etc.)...${NC}"
        xdg-user-dirs-update
    fi

    # Create directories
    mkdir -p "$HOME/.config" "$HOME/.local/share"
    
    # Move default hyprland.lua if present
    if [ -f "$HOME/.config/hypr/hyprland.lua" ]; then
        mv "$HOME/.config/hypr/hyprland.lua" "$HOME/.config/hypr/hyprland.lua.bak"
    fi

    # Copy configurations directly
    cp -rf "$SCRIPT_DIR/configs/hypr" "$HOME/.config/"
    cp -rf "$SCRIPT_DIR/configs/waybar" "$HOME/.config/"
    
    # Install optimized prayer times script to the correct bin path
    mkdir -p "$HOME/.local/share/bin"
    cp -f "$SCRIPT_DIR/configs/waybar/prayer_times.py" "$HOME/.local/share/bin/prayer_times.py"
    chmod +x "$HOME/.local/share/bin/prayer_times.py"
    rm -f "$HOME/.config/waybar/prayer_times.py"
    
    # Install bgapps and bgapps_pick scripts to the correct bin path
    cp -f "$SCRIPT_DIR/configs/waybar/bgapps.sh" "$HOME/.local/share/bin/bgapps.sh"
    chmod +x "$HOME/.local/share/bin/bgapps.sh"
    rm -f "$HOME/.config/waybar/bgapps.sh"
    
    cp -f "$SCRIPT_DIR/configs/hypr/bgapps_pick.sh" "$HOME/.local/share/bin/bgapps_pick.sh"
    chmod +x "$HOME/.local/share/bin/bgapps_pick.sh"
    rm -f "$HOME/.config/hypr/bgapps_pick.sh"
    
    # Install manage_tasks.py script to the correct bin path
    cp -f "$SCRIPT_DIR/configs/zsh/manage_tasks.py" "$HOME/.local/share/bin/manage_tasks.py"
    chmod +x "$HOME/.local/share/bin/manage_tasks.py"
    
    cp -rf "$SCRIPT_DIR/configs/kitty" "$HOME/.config/"
    cp -rf "$SCRIPT_DIR/configs/cava" "$HOME/.config/"
    
    # VS Code
    mkdir -p "$HOME/.config/Code/User"
    cp -f "$SCRIPT_DIR/configs/vscode/settings.json" "$HOME/.config/Code/User/settings.json"
    cp -f "$SCRIPT_DIR/configs/vscode/keybindings.json" "$HOME/.config/Code/User/keybindings.json"
    
    # Zsh
    cp -f "$SCRIPT_DIR/configs/zsh/zshrc" "$HOME/.zshrc"
    
    # SDDM Login Screen
    REAL_USER=$(awk -F: '$3>=1000 && $3<60000 {print $1; exit}' /etc/passwd)
    sudo mkdir -p /etc/sddm.conf.d
    cat << EOF | sudo tee /etc/sddm.conf.d/theme.conf >/dev/null
[Autologin]
User=$REAL_USER
Session=hyprland

[Theme]
Current=sddm-astronaut-theme
EOF
    sudo mkdir -p /usr/share/sddm/scripts
    sudo cp -f "$SCRIPT_DIR/configs/sddm/Xsetup" "/usr/share/sddm/scripts/Xsetup"
    sudo chmod +x /usr/share/sddm/scripts/Xsetup

    # Keyboard layout (Arabic variant thal_bksl)
    if [ -f "/usr/share/X11/xkb/symbols/ara" ]; then
        if ! grep -q "xkb_symbols \"thal_bksl\"" /usr/share/X11/xkb/symbols/ara; then
            echo -e "\n// Custom Arabic layout variant with ذ (Arabic_thal) on the backslash key\npartial alphanumeric_keys\nxkb_symbols \"thal_bksl\" {\n    include \"ara(basic)\"\n    name[Group1]= \"Arabic (Thal on backslash)\";\n    key <BKSL> {[     Arabic_thal,        Arabic_shadda,           backslash,             bar ]};\n};" | sudo tee -a /usr/share/X11/xkb/symbols/ara >/dev/null
        fi
    fi
    
    # Zen Browser settings
    echo -e "${CYAN}Applying Zen Browser transparent themes & memory settings...${NC}"
    mkdir -p "$HOME/.config/zen"
    if [ ! -f "$HOME/.config/zen/profiles.ini" ]; then
        # Write default profiles.ini
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
    
    # Loop profiles and write files
    while IFS= read -r -d '' dir; do
        mkdir -p "$dir/chrome/zen-themes/e34745fd-2b7f-4c16-b03a-6e29e5c3f20a"
        
        # Write user.js, userChrome.css, userContent.css, mods
        # user.js
        cat << 'EOF' > "$dir/user.js"
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
user_pref("browser.tabs.allow_transparent_browser", true);
user_pref("widget.transparent-windows", true);
user_pref("zen.widget.linux.transparency", true);
user_pref("zen.view.compact.enable-at-startup", true);
user_pref("zen.view.compact.toolbar-flash-popup", false);
user_pref("zen.view.compact.hide-toolbar", true);
user_pref("zen.view.compact.show-sidebar-and-toolbar-on-hover", false);
user_pref("zen.theme.content-element-separation", 0);
user_pref("zen.view.sidebar-expanded", false);
user_pref("zen.view.use-single-toolbar", true);
user_pref("zen.tabs.show-newtab-vertical", false);
user_pref("zen.view.show-newtab-button-top", false);
user_pref("zen.urlbar.behavior", "float");
user_pref("mod.devdinc.hide-navbar.animation.enabled", true);
user_pref("mod.devdinc.hide-navbar.element-seperation", "var(--zen-element-separation)");
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.startup.homepage", "about:blank");
user_pref("browser.startup.page", 1);
user_pref("zen.urlbar.replace-newtab", false);
user_pref("browser.sessionstore.resume_session_once", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("font.size.variable.x-western", 18);
user_pref("font.size.fixed.x-western", 15);
user_pref("font.minimum-size.x-western", 13);
user_pref("browser.tabs.unloadOnLowMemory", true);
user_pref("browser.tabs.unloadOnLowMemory.min_inactive_time", 300000);
user_pref("dom.ipc.processCount.webIsolated", 1);
user_pref("dom.ipc.processCount", 1);
user_pref("browser.cache.memory.enable", true);
user_pref("browser.cache.memory.capacity", 65536);
user_pref("browser.cache.memory.max_entry_size", 5120);
user_pref("image.mem.max_decoded_image_size", 52428800);
user_pref("network.predictor.enabled", false);
user_pref("network.dns.disablePrefetch", true);
user_pref("network.prefetch-next", false);
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("browser.sessionstore.interval", 300000);
user_pref("javascript.options.mem.gc_high_frequency_time_limit", 1000);
user_pref("javascript.options.mem.gc_low_frequency_time_limit", 5000);
EOF

        # userChrome.css
        cat << 'EOF' > "$dir/chrome/userChrome.css"
:root, #main-window, #browser, #appcontent, browser, .browserSidebarContainer, #content-deck, #tabbrowser-deck, #tabbrowser-tabbox {
    background-color: transparent !important;
    background: transparent !important;
    border: none !important;
    box-shadow: none !important;
    outline: none !important;
}
#navigator-toolbox, #nav-bar, #titlebar, #TabsToolbar, #zen-appcontent-navbar-container {
    border: none !important;
    box-shadow: none !important;
    outline: none !important;
}
#zen-sidebar-splitter, #appcontent-splitter {
    display: none !important;
    width: 0 !important;
    visibility: collapse !important;
}
#statuspanel, #browser-bottombox {
    display: none !important;
    visibility: collapse !important;
}
EOF

        # userContent.css
        cat << 'EOF' > "$dir/chrome/userContent.css"
@-moz-document url("about:blank"), url("about:newtab"), url("about:home") {
    :root, body, html {
        background-color: transparent !important;
        background: transparent !important;
    }
}
@-moz-document url-prefix(http), url-prefix(https), url-prefix(about:) {
    body, p, span, a, li, h1, h2, h3, h4, h5, h6, input, textarea, button {
        -webkit-font-smoothing: antialiased !important;
        -moz-osx-font-smoothing: grayscale !important;
        text-rendering: optimizeLegibility !important;
    }
}
EOF

        # Hide Navbar mod
        cat << 'EOF' > "$dir/chrome/zen-themes.css"
@media (-moz-bool-pref: "zen.view.compact.hide-toolbar") {
  @media (-moz-bool-pref: "mod.devdinc.hide-navbar.animation.enabled") {
    #nav-bar, #zen-sidebar-top-buttons, #PersonalToolbar, #navigator-toolbox, #TabsToolbar, #titlebar {
      transition: all var(--zen-hidden-toolbar-transition) !important;
    }
  }
  :root {
    --margin-top-fix-hide: calc((var(--zen-toolbar-height) + 50px) + var(--mod-devdinc-hide-navbar-element-seperation));
    --margin-top-fix-hide-reverse: calc(((var(--zen-toolbar-height) + 50px) * -1));
    &:not([zen-compact-mode="true"]):not([zen-single-toolbar="true"]) .browserContainer {
      margin-top: calc(var(--zen-toolbar-height) * -1);
    }
  }
  :root:not([zen-compact-mode="true"]):not([zen-single-toolbar="true"]):has(> body #zen-main-app-wrapper #browser #zen-appcontent-wrapper #zen-appcontent-navbar-wrapper:not([zen-has-hover])),
  :root[zen-compact-mode="true"][zen-single-toolbar="true"] #navigator-toolbox:has(> #titlebar:not(:hover), > #titlebar > #TabsToolbar:hover),
  :root:not([zen-compact-mode="true"])[zen-single-toolbar="true"] #navigator-toolbox:is(:not(:hover), :has(> #titlebar > #TabsToolbar:hover)) {
    #nav-bar, #zen-sidebar-top-buttons {
      margin-top: var(--margin-top-fix-hide-reverse) !important;
      --zen-toolbar-height: var(--margin-top-fix-hide) !important;
    }
    #PersonalToolbar { height: 0 !important; min-height: 0 !important; }
    #titlebar, #navigator-toolbox  { --zen-toolbar-height: 0 !important; }
    .browserContainer { margin-top: calc(var(--mod-devdinc-hide-navbar-element-seperation) * -1); }
  }
}
EOF
        cp -f "$dir/chrome/zen-themes.css" "$dir/chrome/zen-themes/e34745fd-2b7f-4c16-b03a-6e29e5c3f20a/chrome.css"
        
        # mod metadata
        cat << 'EOF' > "$dir/chrome/zen-themes/e34745fd-2b7f-4c16-b03a-6e29e5c3f20a/preferences.json"
[
    {"property": "zen.view.compact.hide-toolbar", "label": "Enable the mod", "type": "checkbox", "defaultValue": true},
    {"property": "mod.devdinc.hide-navbar.animation.enabled", "label": "Enable animations", "type": "checkbox", "defaultValue": true},
    {"property": "mod.devdinc.hide-navbar.element-seperation", "label": "Change top border seperation", "type": "string", "defaultValue": "var(--zen-element-separation)"}
]
EOF
    done < <(find "$HOME/.config/zen" -maxdepth 1 -type d -name "*Default*" -print0 2>/dev/null)

    # Copy and apply the custom wallpaper
    if [ -d "$SCRIPT_DIR/wallpapers" ]; then
        echo -e "${CYAN}Deploying and setting custom system wallpaper...${NC}"
        mkdir -p "$HOME/.config/hyde/themes/Nordic Blue/wallpapers" "$HOME/Pictures/Wallpapers"
        cp -f "$SCRIPT_DIR/wallpapers/background_for_me.jpg" "$HOME/.config/hyde/themes/Nordic Blue/wallpapers/background-for-me.jpg"
        cp -f "$SCRIPT_DIR/wallpapers/background_for_me.jpg" "$HOME/Pictures/Wallpapers/background-for-me.jpg"
        
        # Resolve swww / awww compatibility symlinks dynamically
        if command -v awww &>/dev/null && ! command -v swww &>/dev/null; then
            echo -e "${CYAN}Creating swww symlinks for awww compatibility...${NC}"
            sudo ln -sf /usr/bin/awww /usr/bin/swww
            sudo ln -sf /usr/bin/awww-daemon /usr/bin/swww-daemon
        fi

        # Apply wallpaper if swww is running or swwwallpaper.sh is available
        if command -v swww &>/dev/null; then
            # Initialize swww daemon if not running
            if ! pgrep -x "swww-daemon" &>/dev/null; then
                swww-daemon --format xrgb &
                sleep 1
            fi
            swww img "$HOME/.config/hyde/themes/Nordic Blue/wallpapers/background-for-me.jpg" --transition-type simple || true
        fi
        if [ -f "$HOME/.local/share/bin/swwwallpaper.sh" ]; then
            "$HOME/.local/share/bin/swwwallpaper.sh" -s "$HOME/.config/hyde/themes/Nordic Blue/wallpapers/background-for-me.jpg" &>/dev/null || true
        fi
    fi
fi

# --- Step 4: Install Helper Scripts ---
if [[ "$opt_helper_scripts" =~ ^[Yy]$ ]]; then
    echo -e "\n${BLUE}${BOLD}[4/4] Deploying helper scripts & settings GUI...${NC}"
    
    mkdir -p "$HOME/.local/bin" "$HOME/.local/share/bin" "$HOME/.local/share/applications"
    
    # 1. Double Pageup Dropdown terminal toggle
    cp -f "$SCRIPT_DIR/double-pageup.sh" "$HOME/.local/bin/double-pageup.sh"
    chmod +x "$HOME/.local/bin/double-pageup.sh"
    
    # 2. Native hotspot script
    cp -f "$SCRIPT_DIR/start_hotspot.sh" "$HOME/start_hotspot.sh"
    chmod +x "$HOME/start_hotspot.sh"
    
    # 3. Display Settings & Nightlight GUI
    cp -f "$SCRIPT_DIR/display_nightlight_settings.py" "$HOME/.local/share/bin/hypr-display-settings.py"
    chmod +x "$HOME/.local/share/bin/hypr-display-settings.py"
    
    # Desktop shortcut for Display Settings
    cat << EOF > "$HOME/.local/share/applications/hypr-display-settings.desktop"
[Desktop Entry]
Name=Display & Nightlight Settings
Comment=Adjust screen resolutions, refresh rates, mouse sensitivity, and nightlight
Exec=python3 $HOME/.local/share/bin/hypr-display-settings.py
Icon=video-display
Terminal=false
Type=Application
Categories=Settings;HardwareSettings;
EOF
    chmod +x "$HOME/.local/share/applications/hypr-display-settings.desktop"

    # Write custom documentation command 'omar'
    cat << 'EOF' > "$HOME/.local/share/bin/omar"
#!/usr/bin/env bash
echo -e "\n========================================= Custom Help Documentation ========================================="
echo -e "1. Double-Press Page_Up: Toggles the dropdown terminal/Quake window."
echo -e "2. Super + F: Launches Zen Browser."
echo -e "3. Super + T: Launches Kitty Terminal."
echo -e "4. Super + L: Lock the session immediately."
echo -e "5. start_hotspot.sh: Script located in your home directory to run a native WiFi hotspot using NetworkManager."
echo -e "=============================================================================================================\n"
EOF
    chmod +x "$HOME/.local/share/bin/omar"
fi

# --- Step 5: Disable pam_faillock Lockout Policy ---
if [[ "$opt_disable_faillock" =~ ^[Yy]$ ]]; then
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

# --- Finished ---
echo -e "\n${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}${BOLD}   CONGRATULATIONS! Installation Completed Successfully!              ${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}"

read -p "Would you like to reboot the system now to apply all changes? (y/n) [y]: " reboot_confirm
reboot_confirm="${reboot_confirm:-y}"
if [[ "$reboot_confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Rebooting the system in 5 seconds...${NC}"
    for i in {5..1}; do
        echo -e "  Rebooting in ${CYAN}$i${NC} seconds..."
        sleep 1
    done
    sudo reboot
else
    echo -e "${GREEN}[OK] Done! Enjoy your fresh setup!${NC}"
fi
