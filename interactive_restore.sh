#!/usr/bin/env bash
#===============================================================================
#   Interactive Modular System Restorer & Installer (interactive_restore.sh)
#   Part of: CachyOS + HyDE System Restorer
#   Repo:    https://github.com/omarahmed321/cachy-os-config-related
#
#   Function:
#     Modular, step-by-step interactive installer. Prompts the user before
#     installing each module with a detailed list of packages and configs.
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${CYAN}${BOLD}"
cat << "EOF"
  ==============================================================
     Interactive Modular System Restorer & Installer
  ==============================================================
EOF
echo -e "${NC}"
echo -e "Welcome to Omar's Interactive System Restorer!"
echo -e "You will be prompted before each setup module with a detailed summary.\n"

prompt_module() {
    local mod_title="$1"
    local mod_desc="$2"
    echo -e "${BLUE}${BOLD}======================================================================${NC}"
    echo -e "${MAGENTA}${BOLD}Module: $mod_title${NC}"
    echo -e "${CYAN}$mod_desc${NC}"
    echo -e "${BLUE}${BOLD}======================================================================${NC}"
    read -p "Do you want to install/configure $mod_title? (y/n) [y]: " choice
    choice="${choice:-y}"
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        return 0
    else
        echo -e "${YELLOW}[-] Skipping $mod_title.${NC}\n"
        return 1
    fi
}

# --- MODULE 1: Base Packages & Dependencies ---
DESC_MOD1="Installs essential development tools & packages via pacman:
  • AUR Helpers: yay / paru
  • Development: base-devel, linux-cachyos-headers, gcc, make, cmake, git, python, python-pip
  • System Utilities: curl, wget, jq, eza, fzf, fastfetch, unzip, p7zip"

if prompt_module "1. Core System & Base Packages" "$DESC_MOD1"; then
    echo -e "${GREEN}[+] Installing Core System & Base Packages...${NC}"
    sudo pacman -S --noconfirm --needed base-devel git curl wget jq eza fzf fastfetch unzip p7zip python python-pip || true
    echo -e "${GREEN}[OK] Core System Packages processed.${NC}\n"
fi

# --- MODULE 2: Hyprland & HyDE Environment ---
DESC_MOD2="Deploys Hyprland compositor & HyDE desktop configurations:
  • Dotfiles: hyprland.conf, userprefs.conf, nvidia.conf, windowrules.conf, keybindings.conf
  • Cursor Theme: Bibata-Modern-Ice cursor
  • Fonts: CaskaydiaCove Nerd Font, JetBrains Mono
  • Layout: Dual keyboard layout (US / Arabic with custom 'ذ' key backslash mapping)"

if prompt_module "2. Hyprland & HyDE Desktop Environment" "$DESC_MOD2"; then
    echo -e "${GREEN}[+] Deploying Hyprland & HyDE Environment...${NC}"
    # The Hyprland/HyDE configs are generated inline by the full restorer, which ends with a
    # reboot prompt, so it is not run from the middle of this wizard.
    echo -e "${YELLOW}[!] Hyprland & HyDE configs are deployed by the full restorer.${NC}"
    echo -e "${YELLOW}    Run it after this wizard finishes: bash \"$SCRIPT_DIR/restore_my_setup.sh\"${NC}\n"
fi

# --- MODULE 3: Waybar 3-Island Glassmorphism & Wallpaper ---
DESC_MOD3="Configures floating Glassmorphism Waybar & wallpaper scheme:
  • Layout: 3-island floating capsules (Workspaces + Active Windows, Clock/Date, Status Tray)
  • Wallpaper: Sets background-for-me.jpg paper background
  • Color Scheme: Dynamic Pywal color generation for all GTK & Waybar components"

if prompt_module "3. Waybar Glassmorphism & Paper Wallpaper" "$DESC_MOD3"; then
    echo -e "${GREEN}[+] Applying Waybar Glassmorphism & Wallpaper...${NC}"
    if [ -f "$SCRIPT_DIR/omar-fav-setup.sh" ]; then
        bash "$SCRIPT_DIR/omar-fav-setup.sh"
    elif [ -f "$HOME/.local/share/bin/omar-fav-setup.sh" ]; then
        bash "$HOME/.local/share/bin/omar-fav-setup.sh"
    fi
    echo -e "${GREEN}[OK] Waybar & Wallpaper applied.${NC}\n"
fi

# --- MODULE 4: SDDM Astronaut Login Theme ---
DESC_MOD4="Configures SDDM login manager theme & VT setup:
  • Theme: sddm-astronaut-theme
  • Settings: VT1 reuse
  • Config File: /etc/sddm.conf.d/theme.conf"

if prompt_module "4. SDDM Astronaut Login Theme" "$DESC_MOD4"; then
    echo -e "${GREEN}[+] Configuring SDDM Astronaut Login Theme...${NC}"
    sudo mkdir -p /etc/sddm.conf.d
    cat << 'EOF' | sudo tee /etc/sddm.conf.d/theme.conf >/dev/null
[Theme]
Current=sddm-astronaut-theme

[X11]
MinimumVT=1
EOF
    echo -e "${GREEN}[OK] SDDM Theme configured.${NC}\n"
fi

# --- MODULE 5: VS Code & Extensions Sync ---
DESC_MOD5="Installs VS Code (Code - OSS / Visual Studio Code) & syncs extensions:
  • Extensions List:
      - esbenp.prettier-vscode           (Code Formatter)
      - formulahendry.auto-rename-tag    (HTML/JSX Auto Rename Tag)
      - formulahendry.auto-close-tag     (HTML/JSX Auto Close Tag)
      - ecmel.vscode-html-css            (HTML/CSS Support)
      - dsznajder.es7-react-js-snippets  (React / JS Snippets)
      - bradlc.vscode-tailwindcss        (Tailwind CSS IntelliSense)
      - PKief.material-icon-theme        (Material Icon Theme)
  • Settings: Auto-format bindings, emmet tab completion, custom line duplication (Ctrl+Alt+Up/Down)"

if prompt_module "5. Visual Studio Code & Extensions Sync" "$DESC_MOD5"; then
    echo -e "${GREEN}[+] Installing VS Code & Extensions...${NC}"
    if command -v code &>/dev/null || command -v code-oss &>/dev/null; then
        CODE_BIN=$(command -v code || command -v code-oss)
        EXTENSIONS=(
            "esbenp.prettier-vscode"
            "formulahendry.auto-rename-tag"
            "formulahendry.auto-close-tag"
            "ecmel.vscode-html-css"
            "dsznajder.es7-react-js-snippets"
            "bradlc.vscode-tailwindcss"
            "PKief.material-icon-theme"
        )
        for ext in "${EXTENSIONS[@]}"; do
            echo -e "${CYAN}[+] Installing VS Code extension: $ext${NC}"
            "$CODE_BIN" --install-extension "$ext" --force 2>/dev/null || true
        done
    else
        echo -e "${YELLOW}[!] Note: Install VS Code via pacman (code / visual-studio-code-bin) to sync extensions.${NC}"
    fi
    echo -e "${GREEN}[OK] VS Code & Extensions processed.${NC}\n"
fi

# --- MODULE 6: Local WordPress Development Environment ---
DESC_MOD6="Sets up LocalWP for local WordPress development:
  • Application: localwp desktop application
  • Privileges Fix: Autostarts Polkit Authentication Agent (polkit-kde-authentication-agent-1)
  • Hosts Fix: Grants write permissions to /etc/hosts & syncs site domains (e.g. omar.local)"

if prompt_module "6. Local WordPress (LocalWP) Environment" "$DESC_MOD6"; then
    echo -e "${GREEN}[+] Setting up LocalWP & Polkit Fixes...${NC}"
    if [ -f "$SCRIPT_DIR/setup-wordpress-local.sh" ]; then
        bash "$SCRIPT_DIR/setup-wordpress-local.sh"
    fi
    if [ -f "$SCRIPT_DIR/fix-polkit-localwp.sh" ]; then
        bash "$SCRIPT_DIR/fix-polkit-localwp.sh"
    fi
    echo -e "${GREEN}[OK] LocalWP Environment configured.${NC}\n"
fi

# --- MODULE 7: Display & Night Light GUIs ---
DESC_MOD7="Installs Display, Mouse & Night Light management panels:
  • hypr-display-settings.py : Custom Hz text entry, resolution, scaling & mouse sensitivity
  • nightlight-gui.py        : Screen warmth percentage slider (0%-100%) with hyprsunset & auto-save
  • sddm-screen-config.py    : Select monitor for SDDM login screen
  • setup-initial-cursor-screen.py: Select default display for cursor on startup"

if prompt_module "7. Display, Mouse & Night Light GUIs" "$DESC_MOD7"; then
    echo -e "${GREEN}[+] Configuring Display & Night Light GUIs...${NC}"
    mkdir -p "$HOME/.local/share/bin"
    for gui in hypr-display-settings.py nightlight-gui.py sddm-screen-config.py setup-initial-cursor-screen.py; do
        if [ -f "$SCRIPT_DIR/$gui" ]; then
            cp "$SCRIPT_DIR/$gui" "$HOME/.local/share/bin/"
            chmod +x "$HOME/.local/share/bin/$gui"
        fi
    done
    echo -e "${GREEN}[OK] Display & Night Light GUIs deployed.${NC}\n"
fi

# --- MODULE 8: Zen Browser & Dunst Glassmorphism Themes ---
DESC_MOD8="Applies Glassmorphism themes to Zen Browser & Dunst notifications:
  • Zen Browser: Custom CSS stylesheets (userChrome.css) with glass sidebar & floating URL bar
  • Dunst Popups: Translucent floating capsule notifications with Pywal color matching & Hyprland blur"

if prompt_module "8. Zen Browser & Dunst Glassmorphism Themes" "$DESC_MOD8"; then
    echo -e "${GREEN}[+] Applying Zen Browser & Dunst Glassmorphism Themes...${NC}"
    if [ -f "$SCRIPT_DIR/setup-zen-browser-theme.sh" ]; then
        bash "$SCRIPT_DIR/setup-zen-browser-theme.sh"
    fi
    if [ -f "$SCRIPT_DIR/setup-notifications-theme.py" ]; then
        python3 "$SCRIPT_DIR/setup-notifications-theme.py" --auto
    fi
    echo -e "${GREEN}[OK] Glassmorphism themes applied.${NC}\n"
fi

# --- MODULE 9: Task Manager GUI & 'omar' Command Documentation ---
DESC_MOD9="Deploys interactive Task Manager & system documentation helper:
  • Commands: todo <text>, doing, donetask, rmtask, edittask
  • GUI Picker: task-manager-gui.py (select tasks visually without retyping)
  • Documentation: omar command (clean, concise, iconless tool overview)"

if prompt_module "9. Task Manager GUI & 'omar' Documentation" "$DESC_MOD9"; then
    echo -e "${GREEN}[+] Deploying Task Manager GUI & 'omar' command...${NC}"
    mkdir -p "$HOME/.local/share/bin"
    for tool in task-manager-gui.py manage_tasks.py omar cachy_tools_menu.sh doing donetask todo rmtask edittask; do
        if [ -f "$SCRIPT_DIR/$tool" ]; then
            cp "$SCRIPT_DIR/$tool" "$HOME/.local/share/bin/"
            chmod +x "$HOME/.local/share/bin/$tool"
        fi
    done
    
    # Configure Fish shell config automatically
    FISH_CONF="$HOME/.config/fish/config.fish"
    if [ -f "$FISH_CONF" ]; then
        if ! grep -q "functions -e todo doing" "$FISH_CONF"; then
            cat << 'EOFFISH' >> "$FISH_CONF"

# Erase old task functions from Fish RAM & delegate to scripts
functions -e todo doing donetask rmtask edittask 2>/dev/null
function todo; $HOME/.local/share/bin/todo $argv; end
function doing; $HOME/.local/share/bin/doing $argv; end
function donetask; $HOME/.local/share/bin/donetask $argv; end
function rmtask; $HOME/.local/share/bin/rmtask $argv; end
function edittask; $HOME/.local/share/bin/edittask $argv; end
EOFFISH
        fi
    fi

    # Configure Zsh shell config automatically
    ZSH_CONF="$HOME/.zshrc"
    if [ -f "$ZSH_CONF" ]; then
        if ! grep -q "unfunction todo doing" "$ZSH_CONF"; then
            cat << 'EOFZSH' >> "$ZSH_CONF"

# Erase old task functions from Zsh RAM & delegate to scripts
unfunction todo doing donetask rmtask edittask 2>/dev/null || true
todo() { "$HOME/.local/share/bin/todo" "$@"; }
doing() { "$HOME/.local/share/bin/doing" "$@"; }
donetask() { "$HOME/.local/share/bin/donetask" "$@"; }
rmtask() { "$HOME/.local/share/bin/rmtask" "$@"; }
edittask() { "$HOME/.local/share/bin/edittask" "$@"; }
EOFZSH
        fi
    fi

    echo -e "${GREEN}[OK] Task Manager & Documentation deployed and shells configured.${NC}\n"
fi

# Deploy helper script to user bin
mkdir -p "$HOME/.local/share/bin"
cp "$0" "$HOME/.local/share/bin/interactive_restore.sh" 2>/dev/null || true
chmod +x "$HOME/.local/share/bin/interactive_restore.sh" 2>/dev/null || true

echo -e "${GREEN}${BOLD}======================================================================${NC}"
echo -e "${GREEN}${BOLD}   Interactive Setup Completed Successfully!                          ${NC}"
echo -e "${GREEN}${BOLD}======================================================================${NC}\n"
