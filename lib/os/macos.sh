#!/usr/bin/env bash
# macos.sh - macOS-specific implementations for velum-vpn
# Implements the OS interface for macOS (Darwin)

# Prevent multiple sourcing
[[ -n "${_VELUM_OS_MACOS_LOADED:-}" ]] && return 0
readonly _VELUM_OS_MACOS_LOADED=1

# Verify we're on macOS
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: macos.sh sourced on non-macOS system" >&2
  return 1
fi

# ============================================================================
# CONSTANTS
# ============================================================================

# Kill switch configuration
readonly VELUM_PF_ANCHOR="velum_killswitch"
readonly VELUM_PF_RULES_FILE="/etc/pf.anchors/$VELUM_PF_ANCHOR"

# ============================================================================
# NETWORK DETECTION
# ============================================================================

# Detect default gateway IP
os_detect_gateway() {
  route -n get default 2>/dev/null | grep "gateway:" | awk '{print $2}'
}

# Detect primary network interface (e.g., en0, en1)
os_detect_interface() {
  route -n get default 2>/dev/null | grep "interface:" | awk '{print $2}'
}

# Detect VPN tunnel interface (utunX for WireGuard)
os_detect_vpn_interface() {
  # Find utun interface with WireGuard-like routing (0/1 route)
  netstat -rn 2>/dev/null | grep "^0/1" | awk '{print $NF}' | grep "^utun" | head -1
}

# Detect local subnet in CIDR notation
os_detect_subnet() {
  local interface local_ip netmask

  interface=$(os_detect_interface)
  [[ -z "$interface" ]] && return 1

  local_ip=$(ipconfig getifaddr "$interface" 2>/dev/null)
  netmask=$(ipconfig getoption "$interface" subnet_mask 2>/dev/null)

  [[ -z "$local_ip" || -z "$netmask" ]] && return 1

  # Calculate network address and CIDR
  local i1 i2 i3 i4 m1 m2 m3 m4
  IFS='.' read -r i1 i2 i3 i4 <<< "$local_ip"
  IFS='.' read -r m1 m2 m3 m4 <<< "$netmask"

  local n1=$((i1 & m1))
  local n2=$((i2 & m2))
  local n3=$((i3 & m3))
  local n4=$((i4 & m4))

  # Calculate CIDR prefix from netmask
  local cidr=0
  local octet
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

# Get local IP address on primary interface
os_get_local_ip() {
  local interface
  interface=$(os_detect_interface)
  [[ -z "$interface" ]] && return 1

  ipconfig getifaddr "$interface" 2>/dev/null
}

# ============================================================================
# IPv6 MANAGEMENT
# ============================================================================

# Get list of all network services
_get_network_services() {
  networksetup -listallnetworkservices 2>/dev/null | tail -n +2
}

# Disable IPv6 on all network interfaces
os_disable_ipv6() {
  local service
  local disabled=0

  while IFS= read -r service; do
    if networksetup -setv6off "$service" 2>/dev/null; then
      ((disabled++))
    fi
  done < <(_get_network_services)

  [[ $disabled -gt 0 ]]
}

# Enable IPv6 on all network interfaces
os_enable_ipv6() {
  local service
  local enabled=0

  while IFS= read -r service; do
    if networksetup -setv6automatic "$service" 2>/dev/null; then
      ((enabled++))
    fi
  done < <(_get_network_services)

  [[ $enabled -gt 0 ]]
}

# Check if any interface has IPv6 enabled
os_ipv6_enabled() {
  local service
  while IFS= read -r service; do
    if networksetup -getinfo "$service" 2>/dev/null | grep -q "IPv6: Automatic"; then
      return 0
    fi
  done < <(_get_network_services)

  return 1
}

# ============================================================================
# DNS MANAGEMENT
# ============================================================================

# Backup of original DNS servers (uses VELUM_LIB_DIR from velum-core.sh)
_VELUM_DNS_BACKUP_FILE="$VELUM_LIB_DIR/dns_backup"

# Set DNS servers for all interfaces
# Usage: os_set_dns "10.0.0.243" "10.0.0.242"
os_set_dns() {
  local dns_servers=("$@")
  local service
  local set_count=0

  # Backup current DNS first
  os_backup_dns

  while IFS= read -r service; do
    if networksetup -setdnsservers "$service" "${dns_servers[@]}" 2>/dev/null; then
      ((set_count++))
    fi
  done < <(_get_network_services)

  # Flush DNS cache
  dscacheutil -flushcache 2>/dev/null || true
  killall -HUP mDNSResponder 2>/dev/null || true

  [[ $set_count -gt 0 ]]
}

# Backup current DNS settings
os_backup_dns() {
  # Ensure lib directory exists before writing backup (from velum-core.sh)
  ensure_lib_dir

  local service dns_line

  : > "$_VELUM_DNS_BACKUP_FILE"

  while IFS= read -r service; do
    dns_line=$(networksetup -getdnsservers "$service" 2>/dev/null | tr '\n' ' ')
    echo "${service}:${dns_line}" >> "$_VELUM_DNS_BACKUP_FILE"
  done < <(_get_network_services)

  chmod 600 "$_VELUM_DNS_BACKUP_FILE"
}

# Restore DNS settings from backup
os_restore_dns() {
  [[ ! -f "$_VELUM_DNS_BACKUP_FILE" ]] && return 1

  local line service dns_servers
  while IFS= read -r line; do
    service="${line%%:*}"
    dns_servers="${line#*:}"

    if [[ "$dns_servers" == *"any DNS"* || -z "$dns_servers" ]]; then
      # No custom DNS was set, use empty to get DHCP
      networksetup -setdnsservers "$service" "Empty" 2>/dev/null || true
    else
      # shellcheck disable=SC2086
      networksetup -setdnsservers "$service" $dns_servers 2>/dev/null || true
    fi
  done < "$_VELUM_DNS_BACKUP_FILE"

  rm -f "$_VELUM_DNS_BACKUP_FILE"

  # Flush DNS cache
  dscacheutil -flushcache 2>/dev/null || true
  killall -HUP mDNSResponder 2>/dev/null || true
}

# Get current DNS servers
os_get_dns() {
  local interface
  interface=$(os_detect_interface)
  [[ -z "$interface" ]] && return 1

  scutil --dns 2>/dev/null | grep "nameserver\[" | head -3 | awk -F: '{print $2}' | tr -d ' '
}

# ============================================================================
# KILL SWITCH (pf firewall)
# ============================================================================

# Generate pf rules for kill switch
_generate_pf_rules() {
  local vpn_ip="$1"
  local vpn_port="$2"
  local vpn_iface="$3"
  local lan_policy="$4"
  local physical_iface

  physical_iface=$(os_detect_interface)

  cat << EOF
# Velum VPN Kill Switch Rules
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
      subnet=$(os_detect_subnet)
    fi

    if [[ -n "$subnet" ]]; then
      cat << EOF
# Allow local network access ($subnet)
pass quick on $physical_iface from $subnet to $subnet
EOF
    fi
  fi

  # Add link-local for Bonjour/AirDrop
  cat << EOF

# Allow link-local (Bonjour, AirDrop)
pass quick on $physical_iface proto udp from any to 224.0.0.0/4
pass quick on $physical_iface from 169.254.0.0/16 to 169.254.0.0/16
EOF
}

# Enable kill switch
# Usage: os_killswitch_enable --vpn-ip IP --vpn-port PORT --vpn-iface IFACE --lan-policy POLICY
os_killswitch_enable() {
  local vpn_ip=""
  local vpn_port="1337"
  local vpn_iface=""
  local lan_policy="detect"

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
    log_error "--vpn-ip is required"
    return 1
  fi

  # Auto-detect VPN interface if not specified
  if [[ -z "$vpn_iface" ]]; then
    vpn_iface=$(os_detect_vpn_interface)
    if [[ -z "$vpn_iface" ]]; then
      log_error "Could not detect VPN interface. Specify with --vpn-iface"
      return 1
    fi
  fi

  # Handle lan_policy=detect
  if [[ "$lan_policy" == "detect" ]]; then
    local detected_subnet
    detected_subnet=$(os_detect_subnet)
    if [[ -z "$detected_subnet" ]]; then
      log_warn "Could not detect local subnet, LAN will be blocked"
      lan_policy="block"
    fi
  fi

  # Create anchor directory
  mkdir -p /etc/pf.anchors

  # Generate and write rules
  _generate_pf_rules "$vpn_ip" "$vpn_port" "$vpn_iface" "$lan_policy" > "$VELUM_PF_RULES_FILE"
  chmod 600 "$VELUM_PF_RULES_FILE"

  # Add anchor to pf.conf if not present
  if ! grep -q "anchor \"$VELUM_PF_ANCHOR\"" /etc/pf.conf 2>/dev/null; then
    # Backup original
    cp /etc/pf.conf "/etc/pf.conf.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true

    # Add anchor reference
    {
      echo "anchor \"$VELUM_PF_ANCHOR\""
      echo "load anchor \"$VELUM_PF_ANCHOR\" from \"$VELUM_PF_RULES_FILE\""
    } >> /etc/pf.conf
  fi

  # Load the rules
  pfctl -a "$VELUM_PF_ANCHOR" -f "$VELUM_PF_RULES_FILE" 2>/dev/null

  # Enable pf
  pfctl -e 2>/dev/null || true

  return 0
}

# Disable kill switch
os_killswitch_disable() {
  # Flush the anchor rules
  pfctl -a "$VELUM_PF_ANCHOR" -F all 2>/dev/null || true

  # Remove rules file
  rm -f "$VELUM_PF_RULES_FILE"

  return 0
}

# Get kill switch status
# Returns: "active" | "inactive" | "error"
os_killswitch_status() {
  local pf_status anchor_rules

  # Check if pf is enabled
  pf_status=$(pfctl -s info 2>/dev/null | grep "Status:" | awk '{print $2}')
  if [[ "$pf_status" != "Enabled" ]]; then
    echo "inactive"
    return 0
  fi

  # Check if our anchor has rules
  anchor_rules=$(pfctl -a "$VELUM_PF_ANCHOR" -s rules 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$anchor_rules" -gt 0 ]]; then
    echo "active"
  else
    echo "inactive"
  fi
}

# Get number of kill switch rules
os_killswitch_rule_count() {
  pfctl -a "$VELUM_PF_ANCHOR" -s rules 2>/dev/null | wc -l | tr -d ' '
}

# ============================================================================
# NOTIFICATIONS
# ============================================================================

# Get the console user (the user logged into the GUI)
# Works even when SUDO_USER is not set (e.g., from PostDown scripts)
_get_console_user() {
  # Method 1: Check SUDO_USER (set when using sudo)
  # Validate format before using
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    echo "$SUDO_USER"
    return 0
  fi

  # Method 2: Get owner of /dev/console (the logged-in GUI user)
  local console_user
  console_user=$(stat -f "%Su" /dev/console 2>/dev/null)
  if [[ -n "$console_user" && "$console_user" != "root" ]]; then
    echo "$console_user"
    return 0
  fi

  # Method 3: Check who is logged into console
  console_user=$(who 2>/dev/null | grep console | head -1 | awk '{print $1}')
  if [[ -n "$console_user" ]]; then
    echo "$console_user"
    return 0
  fi

  return 1
}

# Send system notification
# Usage: os_notify "Title" "Message" ["sound"]
# Note: Sound plays via osascript notification sound (depends on System Settings)
# For guaranteed audio alerts, use the say command separately
os_notify() {
  local title="$1"
  local message="$2"
  local sound="${3:-}"

  local script="display notification \"$message\" with title \"$title\""
  if [[ -n "$sound" ]]; then
    script="$script sound name \"$sound\""
  fi

  # When running as root, notifications need to run as the console user
  # to show in their notification center (not root's)
  if [[ $EUID -eq 0 ]]; then
    local notify_user
    notify_user=$(_get_console_user)

    if [[ -n "$notify_user" ]]; then
      sudo -u "$notify_user" osascript -e "$script" 2>/dev/null || true
    else
      # Fallback: try running as root (probably won't show notification)
      osascript -e "$script" 2>/dev/null || true
    fi
  else
    osascript -e "$script" 2>/dev/null || true
  fi
}

# ============================================================================
# HOME DIRECTORY
# ============================================================================

# Get user's home directory (works with sudo)
os_get_home() {
  # Validate SUDO_USER format before using in system calls
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}'
  else
    echo "$HOME"
  fi
}

# ============================================================================
# DATE UTILITIES
# ============================================================================

# Parse date string to epoch
# Usage: os_date_to_epoch "Mon Jan 01 12:00:00 UTC 2024"
os_date_to_epoch() {
  local date_str="$1"
  date -jf "%a %b %d %T %Z %Y" "$date_str" "+%s" 2>/dev/null
}

# Parse ISO8601 date to epoch
# Usage: os_iso_to_epoch "2024-01-01T12:00:00"
os_iso_to_epoch() {
  local date_str="$1"
  date -jf "%Y-%m-%dT%H:%M:%S" "${date_str%%.*}" "+%s" 2>/dev/null
}

# Add days to current date
# Usage: os_date_add_days 7
os_date_add_days() {
  local days="$1"
  date -v"+${days}d" "+%Y-%m-%d"
}
