#!/usr/bin/env bash
#===============================================================================
#   Standalone Task Manager Setup & Integrator (CLI & GUI)
#   Part of: CachyOS + HyDE System Restorer
#   Repo:    https://github.com/omarahmed321/cachy-os-config-related
#===============================================================================

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${CYAN}${BOLD}"
cat << "EOF"
  ==============================================================
        Task Manager Setup & Shell Integrator (CLI & GUI)
  ==============================================================
EOF
echo -e "${NC}"

BIN_DIR="$HOME/.local/share/bin"
mkdir -p "$BIN_DIR"

echo -e "${CYAN}[1/3] Deploying task executables to $BIN_DIR...${NC}"
TOOLS=(doing donetask todo rmtask edittask manage_tasks.py task-manager-gui.py)

for tool in "${TOOLS[@]}"; do
    if [ -f "$SCRIPT_DIR/$tool" ]; then
        cp "$SCRIPT_DIR/$tool" "$BIN_DIR/"
        chmod +x "$BIN_DIR/$tool"
        echo -e "${GREEN}[+] Deployed: $tool${NC}"
    elif [ -f "$BIN_DIR/$tool" ]; then
        chmod +x "$BIN_DIR/$tool"
    fi
done

# Ensure tasks file exists
mkdir -p "$HOME/.config/fastfetch"
if [ ! -f "$HOME/.config/fastfetch/tasks.txt" ]; then
    cat << 'EOF_TASKS' > "$HOME/.config/fastfetch/tasks.txt"
[ ] Finish system setup
[/] niceRiceOmar
EOF_TASKS
    echo -e "${GREEN}[+] Created default tasks file at ~/.config/fastfetch/tasks.txt${NC}"
fi

echo -e "\n${CYAN}[2/3] Configuring Fish Shell integration...${NC}"
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
        echo -e "${GREEN}[OK] Added task functions to ~/.config/fish/config.fish${NC}"
    else
        echo -e "${YELLOW}[!] Fish shell already configured.${NC}"
    fi
fi

echo -e "\n${CYAN}[3/3] Configuring Zsh Shell integration...${NC}"
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
        echo -e "${GREEN}[OK] Added task functions to ~/.zshrc${NC}"
    else
        echo -e "${YELLOW}[!] Zsh shell already configured.${NC}"
    fi
fi

# Copy this setup script to bin
cp "$0" "$BIN_DIR/setup-task-manager.sh" 2>/dev/null || true
chmod +x "$BIN_DIR/setup-task-manager.sh" 2>/dev/null || true

echo -e "\n${GREEN}${BOLD}[OK] Task Manager Installed & Integrated Successfully!${NC}"
echo -e "${CYAN}[*] Available CLI Commands: todo <text>, doing, donetask, rmtask, edittask${NC}"
echo -e "${CYAN}[*] GUI Panel: task-manager-gui.py${NC}\n"
