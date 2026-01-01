#!/usr/bin/env bash
# PIA VPN Kill Switch using macOS pf (packet filter)
# Blocks all traffic if VPN drops, preventing IP leaks

set -uo pipefail

# Colors
if [[ -t 1 ]]; then
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  NC=$(tput sgr0)
else
  RED='' GREEN='' YELLOW='' NC=''
fi

# Kill switch anchor name
PF_ANCHOR="pia_killswitch"
PF_RULES_FILE="/etc/pf.anchors/$PF_ANCHOR"

usage() {
  echo "Usage: $0 <command> [options]"
  echo ""
  echo "Commands:"
  echo "  enable    Enable kill switch (blocks non-VPN traffic)"
  echo "  disable   Disable kill switch (restore normal traffic)"
  echo "  status    Show kill switch status"
  echo ""
  echo "Options for 'enable':"
  echo "  --vpn-ip <IP>         VPN server IP (required)"
  echo "  --vpn-port <PORT>     VPN server port (default: 1337)"
  echo "  --vpn-iface <IFACE>   VPN interface (default: auto-detect utun)"
  echo "  --lan-policy <POLICY> LAN policy: block|detect|<CIDR>"
  echo "                        block  = block all LAN traffic"
  echo "                        detect = auto-detect and allow local subnet"
  echo "                        <CIDR> = allow specific subnet (e.g., 10.0.1.0/24)"
  echo ""
  echo "Environment variables:"
  echo "  PIA_KILLSWITCH_LAN    Same as --lan-policy"
  echo ""
  echo "Examples:"
  echo "  sudo $0 enable --vpn-ip 158.173.21.201 --lan-policy detect"
  echo "  sudo $0 disable"
  echo "  sudo $0 status"
}

# Auto-detect local subnet from default route
detect_local_subnet() {
  local gateway interface local_ip netmask subnet

  # Get default gateway and interface
  gateway=$(route -n get default 2>/dev/null | grep "gateway:" | awk '{print $2}')
  interface=$(route -n get default 2>/dev/null | grep "interface:" | awk '{print $2}')

  if [[ -z "$interface" ]]; then
    echo ""
    return 1
  fi

  # Get local IP and netmask for this interface
  local_ip=$(ipconfig getifaddr "$interface" 2>/dev/null)
  netmask=$(ipconfig getoption "$interface" subnet_mask 2>/dev/null)

  if [[ -z "$local_ip" || -z "$netmask" ]]; then
    echo ""
    return 1
  fi

  # Convert IP and netmask to subnet CIDR
  # This is a simplified calculation - works for common subnets
  IFS='.' read -r i1 i2 i3 i4 <<< "$local_ip"
  IFS='.' read -r m1 m2 m3 m4 <<< "$netmask"

  # Calculate network address
  n1=$((i1 & m1))
  n2=$((i2 & m2))
  n3=$((i3 & m3))
  n4=$((i4 & m4))

  # Calculate CIDR prefix from netmask
  cidr=0
  for octet in $m1 $m2 $m3 $m4; do
    case $octet in
      255) cidr=$((cidr + 8)) ;;
      254) cidr=$((cidr + 7)) ;;
      252) cidr=$((cidr + 6)) ;;
      248) cidr=$((cidr + 5)) ;;
      240) cidr=$((cidr + 4)) ;;
      224) cidr=$((cidr + 3)) ;;
      192) cidr=$((cidr + 2)) ;;
      128) cidr=$((cidr + 1)) ;;
      0) ;;
    esac
  done

  echo "$n1.$n2.$n3.$n4/$cidr"
}

# Auto-detect VPN interface (utunX)
detect_vpn_interface() {
  # Find utun interface with WireGuard-like routing (0/1 route)
  netstat -rn 2>/dev/null | grep "^0/1" | awk '{print $NF}' | grep "^utun" | head -1
}

# Generate pf rules
generate_pf_rules() {
  local vpn_ip="$1"
  local vpn_port="$2"
  local vpn_iface="$3"
  local lan_policy="$4"
  local physical_iface

  # Get physical interface (en0, en1, etc.)
  physical_iface=$(route -n get default 2>/dev/null | grep "interface:" | awk '{print $2}')

  cat << EOF
# PIA VPN Kill Switch Rules
# Generated: $(date)
# VPN Server: $vpn_ip:$vpn_port
# VPN Interface: $vpn_iface
# LAN Policy: $lan_policy

# Default: block all traffic (IPv4)
block all

# Block ALL IPv6 traffic (prevents leaks)
block quick inet6 all

# Allow loopback
pass quick on lo0 all

# Allow VPN tunnel interface (all traffic through VPN is OK)
pass quick on $vpn_iface all

# Allow traffic TO VPN server (to establish/maintain connection)
pass quick on $physical_iface proto udp from any to $vpn_ip port $vpn_port

# Allow DHCP (needed to get/renew IP address)
pass quick on $physical_iface proto udp from any port 68 to any port 67
pass quick on $physical_iface proto udp from any port 67 to any port 68

EOF

  # Add LAN rules based on policy
  if [[ "$lan_policy" != "block" ]]; then
    local subnet="$lan_policy"
    if [[ "$lan_policy" == "detect" ]]; then
      subnet=$(detect_local_subnet)
    fi

    if [[ -n "$subnet" ]]; then
      cat << EOF
# Allow local network access ($subnet)
pass quick on $physical_iface from $subnet to $subnet
EOF
    fi
  fi

  # Add link-local for Bonjour/AirDrop (always useful on macOS)
  cat << EOF

# Allow link-local (Bonjour, AirDrop)
pass quick on $physical_iface proto udp from any to 224.0.0.0/4
pass quick on $physical_iface from 169.254.0.0/16 to 169.254.0.0/16
EOF
}

# Enable kill switch
enable_killswitch() {
  local vpn_ip=""
  local vpn_port="1337"
  local vpn_iface=""
  local lan_policy="${PIA_KILLSWITCH_LAN:-detect}"

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --vpn-ip) vpn_ip="$2"; shift 2 ;;
      --vpn-port) vpn_port="$2"; shift 2 ;;
      --vpn-iface) vpn_iface="$2"; shift 2 ;;
      --lan-policy) lan_policy="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  # Validate required params
  if [[ -z "$vpn_ip" ]]; then
    echo "${RED}Error: --vpn-ip is required${NC}"
    exit 1
  fi

  # Auto-detect VPN interface if not specified
  if [[ -z "$vpn_iface" ]]; then
    vpn_iface=$(detect_vpn_interface)
    if [[ -z "$vpn_iface" ]]; then
      echo "${RED}Error: Could not detect VPN interface. Specify with --vpn-iface${NC}"
      exit 1
    fi
  fi

  echo "${GREEN}Enabling PIA kill switch...${NC}"
  echo "  VPN Server:    $vpn_ip:$vpn_port"
  echo "  VPN Interface: $vpn_iface"
  echo "  LAN Policy:    $lan_policy"

  if [[ "$lan_policy" == "detect" ]]; then
    local detected_subnet=$(detect_local_subnet)
    if [[ -n "$detected_subnet" ]]; then
      echo "  Detected LAN:  $detected_subnet"
    else
      echo "  ${YELLOW}Warning: Could not detect local subnet, LAN will be blocked${NC}"
      lan_policy="block"
    fi
  fi

  # Create anchor directory if needed
  mkdir -p /etc/pf.anchors

  # Generate and write rules
  generate_pf_rules "$vpn_ip" "$vpn_port" "$vpn_iface" "$lan_policy" > "$PF_RULES_FILE"
  chmod 600 "$PF_RULES_FILE"

  # Check if anchor is already in pf.conf
  if ! grep -q "anchor \"$PF_ANCHOR\"" /etc/pf.conf 2>/dev/null; then
    # Backup original pf.conf
    cp /etc/pf.conf /etc/pf.conf.backup.$(date +%Y%m%d%H%M%S) 2>/dev/null || true

    # Add anchor reference to pf.conf
    echo "anchor \"$PF_ANCHOR\"" >> /etc/pf.conf
    echo "load anchor \"$PF_ANCHOR\" from \"$PF_RULES_FILE\"" >> /etc/pf.conf
  fi

  # Load the rules
  pfctl -a "$PF_ANCHOR" -f "$PF_RULES_FILE" 2>/dev/null

  # Enable pf if not already enabled
  pfctl -e 2>/dev/null || true

  echo "${GREEN}Kill switch enabled!${NC}"
  echo ""
  echo "Traffic is now blocked unless it goes through the VPN."
  echo "IPv6 is blocked at the firewall level."
  echo "Run 'sudo $0 status' to verify."
}

# Disable kill switch
disable_killswitch() {
  echo "${YELLOW}Disabling PIA kill switch...${NC}"

  # Flush the anchor rules
  pfctl -a "$PF_ANCHOR" -F all 2>/dev/null || true

  # Remove rules file
  rm -f "$PF_RULES_FILE"

  echo "${GREEN}Kill switch disabled.${NC}"
  echo "Normal network traffic restored."
}

# Show status
show_status() {
  echo "${GREEN}PIA Kill Switch Status${NC}"
  echo "========================"
  echo ""

  # Check if pf is enabled
  pf_status=$(pfctl -s info 2>/dev/null | grep "Status:" | awk '{print $2}')
  if [[ "$pf_status" == "Enabled" ]]; then
    echo "pf Firewall:     ${GREEN}Enabled${NC}"
  else
    echo "pf Firewall:     ${RED}Disabled${NC}"
  fi

  # Check if our anchor has rules
  anchor_rules=$(pfctl -a "$PF_ANCHOR" -s rules 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$anchor_rules" -gt 0 ]]; then
    echo "Kill Switch:     ${GREEN}Active ($anchor_rules rules)${NC}"
    echo ""
    echo "Active rules:"
    pfctl -a "$PF_ANCHOR" -s rules 2>/dev/null | head -20
  else
    echo "Kill Switch:     ${YELLOW}Inactive${NC}"
  fi

  # Show detected network info
  echo ""
  echo "Network Detection:"
  local vpn_iface=$(detect_vpn_interface)
  if [[ -n "$vpn_iface" ]]; then
    echo "  VPN Interface: ${GREEN}$vpn_iface${NC}"
  else
    echo "  VPN Interface: ${RED}Not found${NC}"
  fi

  local subnet=$(detect_local_subnet)
  if [[ -n "$subnet" ]]; then
    echo "  Local Subnet:  ${GREEN}$subnet${NC}"
  else
    echo "  Local Subnet:  ${YELLOW}Unknown${NC}"
  fi
}

# Send macOS notification
notify_vpn_drop() {
  osascript -e 'display notification "VPN connection dropped! Kill switch is blocking all traffic." with title "PIA VPN Alert" sound name "Basso"' 2>/dev/null || true
}

# Main
if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

# Require root for enable/disable
if [[ "$1" == "enable" || "$1" == "disable" ]]; then
  if [[ $EUID -ne 0 ]]; then
    echo "${RED}This command requires root. Run with sudo.${NC}"
    exit 1
  fi
fi

case "$1" in
  enable)
    shift
    enable_killswitch "$@"
    ;;
  disable)
    disable_killswitch
    ;;
  status)
    show_status
    ;;
  notify)
    notify_vpn_drop
    ;;
  *)
    usage
    exit 1
    ;;
esac
