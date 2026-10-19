#!/usr/bin/env bash
#===============================================================================
#   Universal Polkit & LocalWP "Files Locked by Antivirus / Hosts" Fixer
#   Part of: CachyOS + HyDE System Restorer & Universal Replicator
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
    Universal LocalWP "Locked Files / Hosts" & Polkit Fixer
  ==============================================================
EOF
echo -e "${NC}"

# 1. Detect & Launch System Polkit Authentication Agent Live
echo -e "${CYAN}[1/4] Detecting & Starting Polkit Authentication Agent...${NC}"

AGENT_BIN=""
POSSIBLE_PATHS=(
    "/usr/lib/polkit-kde-authentication-agent-1"
    "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
    "/usr/libexec/polkit-gnome-authentication-agent-1"
    "/usr/libexec/polkit-kde-authentication-agent-1"
    "/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1"
    "/usr/lib/x86_64-linux-gnu/polkit-mate/polkit-mate-authentication-agent-1"
    "/usr/libexec/polkit-mate-authentication-agent-1"
)

for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        AGENT_BIN="$path"
        break
    fi
done

if [ -z "$AGENT_BIN" ] && command -v hyprpolkitagent &>/dev/null; then
    AGENT_BIN="$(which hyprpolkitagent)"
fi

if [ -n "$AGENT_BIN" ]; then
    AGENT_NAME="$(basename "$AGENT_BIN")"
    if ! pgrep -f "$AGENT_NAME" >/dev/null; then
        nohup "$AGENT_BIN" &>/dev/null & disown
        sleep 1
    fi
    echo -e "${GREEN}[OK] Polkit Authentication Agent is running live! ($AGENT_BIN)${NC}"
else
    echo -e "${YELLOW}[!] Warning: Polkit Agent binary not found.${NC}"
fi

# 2. Grant write permissions on /etc/hosts so LocalWP can append domains seamlessly
echo -e "\n${CYAN}[2/4] Setting write permissions on /etc/hosts...${NC}"
if [ -w "/etc/hosts" ] && [ -z "$(find /etc/hosts -perm -o+w 2>/dev/null)" ]; then
    echo -e "${GREEN}[OK] /etc/hosts is already writable.${NC}"
else
    # Grant write access to this user only via an ACL; chmod 666 would let any
    # process or user on the machine redirect domains through /etc/hosts.
    HOSTS_USER="${SUDO_USER:-$USER}"
    SUDO_CMD=""
    [ "$EUID" -ne 0 ] && SUDO_CMD="sudo"
    $SUDO_CMD chattr -i /etc/hosts 2>/dev/null || true
    # Undo the world-writable mode older versions of this script applied
    $SUDO_CMD chmod 644 /etc/hosts 2>/dev/null || true
    if $SUDO_CMD setfacl -m "u:${HOSTS_USER}:rw" /etc/hosts 2>/dev/null; then
        echo -e "${GREEN}[OK] Granted $HOSTS_USER write access to /etc/hosts.${NC}"
    else
        echo -e "${YELLOW}[!] Could not set an ACL on /etc/hosts (is the 'acl' package installed?).${NC}"
    fi
fi

# 3. Automatically sync existing LocalWP site domains into /etc/hosts
echo -e "\n${CYAN}[3/4] Syncing LocalWP site domains into /etc/hosts...${NC}"
python3 -c "
import json, os

sites_json = os.path.expanduser('~/.config/Local/sites.json')
hosts_path = '/etc/hosts'

domains = []
if os.path.exists(sites_json):
    try:
        with open(sites_json, 'r') as f:
            data = json.load(f)
            for site_id, site in data.items():
                dom = site.get('domain')
                if dom:
                    domains.append(dom)
    except Exception:
        pass

if domains and os.path.exists(hosts_path) and os.access(hosts_path, os.W_OK):
    with open(hosts_path, 'r') as f:
        content = f.read()
    
    new_entries = []
    for d in domains:
        if d not in content:
            new_entries.append(f'127.0.0.1 {d}\n::1 {d}')
            
    if new_entries:
        with open(hosts_path, 'a') as f:
            f.write('\n## LocalWP Site Domains\n' + '\n'.join(new_entries) + '\n')
        print(f'Synced {len(new_entries)} site domains to /etc/hosts')
    else:
        print('All site domains are already configured in /etc/hosts')
" 2>/dev/null || true
echo -e "${GREEN}[OK] Site domain sync complete.${NC}"

# 4. Register Polkit Agent in Hyprland & Autostarts
echo -e "\n${CYAN}[4/4] Registering persistent autostarts...${NC}"

HYPR_CONF="$HOME/.config/hypr/userprefs.conf"
if [ -d "$HOME/.config/hypr" ] && [ -n "$AGENT_BIN" ]; then
    touch "$HYPR_CONF"
    if ! grep -q "polkit" "$HYPR_CONF"; then
        cat << EOF >> "$HYPR_CONF"

# Start Polkit Authentication Agent for LocalWP and elevated privileges dialogs
exec-once = $AGENT_BIN
EOF
    fi
fi

XDG_AUTOSTART="$HOME/.config/autostart/polkit-agent-localwp.desktop"
if [ -n "$AGENT_BIN" ]; then
    mkdir -p "$HOME/.config/autostart"
    cat << EOF > "$XDG_AUTOSTART"
[Desktop Entry]
Type=Application
Name=Polkit Authentication Agent
Comment=Auto-starts Polkit Agent for LocalWP and privilege dialogs
Exec=$AGENT_BIN
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
fi

# Deploy helper script to user bin
mkdir -p "$HOME/.local/share/bin"
cp "$0" "$HOME/.local/share/bin/fix-polkit-localwp.sh" 2>/dev/null || true
chmod +x "$HOME/.local/share/bin/fix-polkit-localwp.sh" 2>/dev/null || true

echo -e "\n${GREEN}${BOLD}[OK] LocalWP Fix Applied & Domain Sync Complete!${NC}"
echo -e "${CYAN}[*] You can now start sites in LocalWP smoothly.${NC}\n"
