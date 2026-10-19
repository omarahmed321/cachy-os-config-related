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
