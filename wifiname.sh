#!/usr/bin/env bash
#
# Wi-Fi over Ethernet ICS Toggle for Linux
# ----------------------------------------
# See README for usage and mac.txt format.
#

# --- Logging setup ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/logps.txt"
MAC_FILE="$SCRIPT_DIR/mac.txt"

log() {
  echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ')  $*" >> "$LOG_FILE"
}

log "=== Run at $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="

# --- Elevate if needed ---
if [[ $EUID -ne 0 ]]; then
  log "Not root; re-launching via sudo."
  exec sudo bash "$0" "$@"
fi
log "Running as root."

# --- Load MAC priority lists ---
declare -a WIFI_MACS ETH_MACS
_load_mac_list(){
  WIFI_MACS=(); ETH_MACS=()
  [[ -f $MAC_FILE ]] || touch "$MAC_FILE"
  while IFS= read -r line; do
    if [[ $line =~ ^wifi:[[:space:]]*([0-9A-Fa-f:\-]{17}) ]]; then
      WIFI_MACS+=("${BASH_REMATCH[1]//[-:]/}" )
    elif [[ $line =~ ^ethernet:[[:space:]]*([0-9A-Fa-f:\-]{17}) ]]; then
      ETH_MACS+=("${BASH_REMATCH[1]//[-:]/}" )
    fi
  done < "$MAC_FILE"
}
_load_mac_list

# --- Save MAC to file ---
_add_mac_manual(){
  local type=$1
  read -p "Enter $type MAC (AA:BB:CC:DD:EE:FF): " mac
  if [[ $mac =~ ^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}$ ]]; then
    echo "$type: $mac" >> "$MAC_FILE"
    log "Added $type MAC (manual): $mac"
    echo "$type MAC added."
    _load_mac_list
  else
    echo "Invalid format."
    log "Invalid manual MAC: $mac"
  fi
}

# --- Auto-scan & add MAC ---
_add_mac_auto(){
  local type=$1
  declare -a ifs
  if [[ $type == wifi ]]; then
    # common Wi-Fi interface patterns: wlan*, wlp*
    mapfile -t ifs < <(ip -o link show | awk -F': ' '/^[0-9]+: (wlan|wlp)/{print $2}')
  else
    # common Ethernet patterns: eth*, enp*
    mapfile -t ifs < <(ip -o link show | awk -F': ' '/^[0-9]+: (eth|enp)/{print $2}')
  fi

  if [[ ${#ifs[@]} -eq 0 ]]; then
    echo "No $type adapters found."
    return
  fi

  echo
  for i in "${!ifs[@]}"; do
    local name=${ifs[i]}
    local mac=$(cat /sys/class/net/"$name"/address)
    local state=$(cat /sys/class/net/"$name"/operstate)
    local speed=$(ethtool "$name" 2>/dev/null | awk '/Speed:/{print $2}')
    printf "[%d] %-8s MAC:%s STATE:%s SPEED:%s\n" "$i" "$name" "$mac" "$state" "${speed:-n/a}"
  done

  read -p $'\nEnter number or Q to cancel: ' sel
  if [[ $sel =~ ^[0-9]+$ && $sel -lt ${#ifs[@]} ]]; then
    local pick=${ifs[sel]}
    local mac=$(cat /sys/class/net/"$pick"/address)
    echo "$type: $mac" >> "$MAC_FILE"
    log "Added $type MAC (auto): $mac ($pick)"
    echo "$type MAC $mac added."
    _load_mac_list
  else
    echo "Cancelled."
    log "Auto-add $type cancelled: $sel"
  fi
}

# --- Identify interfaces by priority ---
_match_iface(){
  local -n macs=$1
  for m in "${macs[@]}"; do
    # normalize no separators, uppercase
    local norm=${m^^}
    norm=${norm//:/}; norm=${norm//-/}
    for iface in $(ls /sys/class/net); do
      local hw=$(cat /sys/class/net/"$iface"/address)
      hw=${hw^^}; hw=${hw//:/}
      [[ $hw == "$norm" ]] && echo "$iface" && return
    done
  done
}

# --- Enable / Disable sharing ---
enable_sharing(){
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  iptables -t nat -C POSTROUTING -o "$ETH_IFACE" -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING -o "$ETH_IFACE" -j MASQUERADE
  iptables -C FORWARD -i "$ETH_IFACE" -o "$WIFI_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
    || iptables -A FORWARD -i "$ETH_IFACE" -o "$WIFI_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
  iptables -C FORWARD -i "$WIFI_IFACE" -o "$ETH_IFACE" -j ACCEPT 2>/dev/null \
    || iptables -A FORWARD -i "$WIFI_IFACE" -o "$ETH_IFACE" -j ACCEPT
  echo "Sharing ENABLED"
  log "Enabled sharing: $WIFI_IFACE -> $ETH_IFACE"
}

disable_sharing(){
  sysctl -w net.ipv4.ip_forward=0 >/dev/null
  iptables -t nat -D POSTROUTING -o "$ETH_IFACE" -j MASQUERADE 2>/dev/null
  iptables -D FORWARD -i "$ETH_IFACE" -o "$WIFI_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
  iptables -D FORWARD -i "$WIFI_IFACE" -o "$ETH_IFACE" -j ACCEPT 2>/dev/null
  echo "Sharing DISABLED"
  log "Disabled sharing"
}

# --- Main startup: pick interfaces ---
WIFI_IFACE=$(_match_iface WIFI_MACS) || true
ETH_IFACE=$(_match_iface ETH_MACS) || true

if [[ -z $WIFI_IFACE || -z $ETH_IFACE ]]; then
  echo "ERROR: could not match interfaces by MAC list."
  log "ERROR: interface matching failed (wifi=$WIFI_IFACE eth=$ETH_IFACE)"
  exit 1
fi

echo
echo "Wi-Fi iface:    $WIFI_IFACE"
echo "Ethernet iface: $ETH_IFACE"
# check current state
if [[ $(sysctl -n net.ipv4.ip_forward) -eq 1 ]]; then
  echo "ICS is currently: ENABLED"
  SHARE_ON=true
else
  echo "ICS is currently: DISABLED"
  SHARE_ON=false
fi
log "Interfaces: wifi=$WIFI_IFACE eth=$ETH_IFACE shared=$SHARE_ON"

# --- Menu loop ---
while :; do
  cat <<-EOF

  Menu:
    1) Enable sharing
    2) Disable sharing
    3) Add Wi-Fi MAC (manual)
    4) Add Ethernet MAC (manual)
    5) Auto-add Wi-Fi MAC
    6) Auto-add Ethernet MAC
    Q) Quit

EOF
  read -p "Choose an option: " choice
  log "User chose: $choice"
  case "${choice^^}" in
    1) enable_sharing; SHARE_ON=true ;;
    2) disable_sharing; SHARE_ON=false ;;
    3) _add_mac_manual wifi ;;
    4) _add_mac_manual ethernet ;;
    5) _add_mac_auto wifi ;;
    6) _add_mac_auto ethernet ;;
    Q) log "Exiting"; break ;;
    *) echo "Invalid choice." ;;
  esac
done

echo
read -n1 -r -p "Press any key to exit..."
log "Script end"
