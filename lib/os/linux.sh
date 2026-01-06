#!/usr/bin/env bash
# linux.sh - Linux-specific implementations for velum-vpn
# Implements the OS interface for Linux (Debian/Ubuntu focus)

# Prevent multiple sourcing
[[ -n "${_VELUM_OS_LINUX_LOADED:-}" ]] && return 0
readonly _VELUM_OS_LINUX_LOADED=1

# Verify we're on Linux
if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: linux.sh sourced on non-Linux system" >&2
  return 1
fi

# ============================================================================
# CONSTANTS
# ============================================================================

# Kill switch configuration
readonly VELUM_IPTABLES_CHAIN="VELUM_KILLSWITCH"
readonly VELUM_NFT_TABLE="velum_killswitch"

# DNS backup location
readonly VELUM_DNS_BACKUP="/var/tmp/velum_dns_backup"
readonly VELUM_RESOLV_BACKUP="/var/tmp/velum_resolv.conf.backup"

# ============================================================================
# FIREWALL DETECTION
# ============================================================================

# Detect which firewall is available
# Returns: "nftables" | "iptables" | "none"
_detect_firewall() {
  if command -v nft >/dev/null 2>&1; then
    echo "nftables"
  elif command -v iptables >/dev/null 2>&1; then
    echo "iptables"
  else
    echo "none"
  fi
}

# ============================================================================
# NETWORK DETECTION
# ============================================================================

# Detect default gateway IP
os_detect_gateway() {
  ip route show default 2>/dev/null | awk '/default/ {print $3; exit}'
}

# Detect primary network interface
os_detect_interface() {
  ip route show default 2>/dev/null | awk '/default/ {print $5; exit}'
}

# Detect VPN tunnel interface (wg0, wg-pia, etc.)
os_detect_vpn_interface() {
  # First try: look for WireGuard interfaces
  local wg_iface
  wg_iface=$(ip link show type wireguard 2>/dev/null | grep -oP '^\d+:\s+\K[^:@]+' | head -1)

  if [[ -n "$wg_iface" ]]; then
    echo "$wg_iface"
    return 0
  fi

  # Fallback: look for interface with 0.0.0.0/1 route (WireGuard routing)
  ip route 2>/dev/null | grep "^0.0.0.0/1" | awk '{print $3}' | head -1
}

# Detect local subnet in CIDR notation
os_detect_subnet() {
  local interface
  interface=$(os_detect_interface)
  [[ -z "$interface" ]] && return 1

  # Get IP and prefix length
  local ip_cidr
  ip_cidr=$(ip -4 addr show "$interface" 2>/dev/null | grep -oP 'inet \K[\d.]+/\d+' | head -1)

  if [[ -z "$ip_cidr" ]]; then
    return 1
  fi

  # Calculate network address from IP/CIDR
  local ip="${ip_cidr%/*}"
  local prefix="${ip_cidr#*/}"

  # Convert to network address
  local IFS='.'
  read -r i1 i2 i3 i4 <<< "$ip"

  # Create netmask from prefix
  local mask=$((0xFFFFFFFF << (32 - prefix) & 0xFFFFFFFF))
  local m1=$(((mask >> 24) & 0xFF))
  local m2=$(((mask >> 16) & 0xFF))
  local m3=$(((mask >> 8) & 0xFF))
  local m4=$((mask & 0xFF))

  # Calculate network
  local n1=$((i1 & m1))
  local n2=$((i2 & m2))
  local n3=$((i3 & m3))
  local n4=$((i4 & m4))

  echo "$n1.$n2.$n3.$n4/$prefix"
}

# Get local IP address on primary interface
os_get_local_ip() {
  local interface
  interface=$(os_detect_interface)
  [[ -z "$interface" ]] && return 1

  ip -4 addr show "$interface" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1
}

# ============================================================================
# IPv6 MANAGEMENT
# ============================================================================

# Disable IPv6 system-wide via sysctl
os_disable_ipv6() {
  # Disable for all interfaces
  sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || return 1
  sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || return 1

  # Disable for each specific interface
  local iface
  for iface in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
    echo 1 > "$iface" 2>/dev/null || true
  done

  return 0
}

# Enable IPv6 system-wide
os_enable_ipv6() {
  sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1 || return 1
  sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1 || return 1

  # Enable for each specific interface
  local iface
  for iface in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
    echo 0 > "$iface" 2>/dev/null || true
  done

  return 0
}

# Check if IPv6 is enabled
os_ipv6_enabled() {
  local all_disabled default_disabled

  all_disabled=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo 0)
  default_disabled=$(sysctl -n net.ipv6.conf.default.disable_ipv6 2>/dev/null || echo 0)

  # IPv6 is enabled if either is 0
  [[ "$all_disabled" -eq 0 || "$default_disabled" -eq 0 ]]
}

# ============================================================================
# DNS MANAGEMENT
# ============================================================================

# Detect DNS management system
# Returns: "systemd-resolved" | "resolvconf" | "direct"
_detect_dns_system() {
  if [[ -L /etc/resolv.conf ]] && readlink /etc/resolv.conf | grep -q "systemd"; then
    echo "systemd-resolved"
  elif command -v resolvconf >/dev/null 2>&1; then
    echo "resolvconf"
  else
    echo "direct"
  fi
}

# Set DNS servers
# Usage: os_set_dns "10.0.0.243" "10.0.0.242"
os_set_dns() {
  local dns_servers=("$@")
  local dns_system
  dns_system=$(_detect_dns_system)

  # Backup current DNS first
  os_backup_dns

  case "$dns_system" in
    systemd-resolved)
      _set_dns_systemd "${dns_servers[@]}"
      ;;
    resolvconf)
      _set_dns_resolvconf "${dns_servers[@]}"
      ;;
    direct)
      _set_dns_direct "${dns_servers[@]}"
      ;;
  esac
}

# Set DNS via systemd-resolved
_set_dns_systemd() {
  local dns_servers=("$@")
  local interface
  interface=$(os_detect_vpn_interface)

  if [[ -z "$interface" ]]; then
    interface=$(os_detect_interface)
  fi

  # Use resolvectl if available (newer systemd)
  if command -v resolvectl >/dev/null 2>&1; then
    resolvectl dns "$interface" "${dns_servers[@]}" 2>/dev/null || true
    resolvectl domain "$interface" "~." 2>/dev/null || true
  else
    # Fallback to systemd-resolve
    systemd-resolve --interface="$interface" --set-dns="${dns_servers[0]}" 2>/dev/null || true
  fi
}

# Set DNS via resolvconf
_set_dns_resolvconf() {
  local dns_servers=("$@")
  local interface
  interface=$(os_detect_vpn_interface)
  [[ -z "$interface" ]] && interface="velum"

  # Create resolvconf entry
  {
    for dns in "${dns_servers[@]}"; do
      echo "nameserver $dns"
    done
  } | resolvconf -a "$interface.velum" 2>/dev/null
}

# Set DNS by directly writing resolv.conf
_set_dns_direct() {
  local dns_servers=("$@")

  # Write new resolv.conf
  {
    echo "# Generated by velum-vpn"
    for dns in "${dns_servers[@]}"; do
      echo "nameserver $dns"
    done
  } > /etc/resolv.conf

  # Make immutable to prevent overwriting
  chattr +i /etc/resolv.conf 2>/dev/null || true
}

# Backup current DNS settings
os_backup_dns() {
  local dns_system
  dns_system=$(_detect_dns_system)

  case "$dns_system" in
    systemd-resolved)
      # Save current DNS config
      resolvectl status 2>/dev/null > "$VELUM_DNS_BACKUP" || true
      ;;
    resolvconf|direct)
      # Save resolv.conf
      cp /etc/resolv.conf "$VELUM_RESOLV_BACKUP" 2>/dev/null || true
      ;;
  esac

  chmod 600 "$VELUM_DNS_BACKUP" 2>/dev/null || true
  chmod 600 "$VELUM_RESOLV_BACKUP" 2>/dev/null || true
}

# Restore DNS settings from backup
os_restore_dns() {
  local dns_system
  dns_system=$(_detect_dns_system)

  case "$dns_system" in
    systemd-resolved)
      # Revert systemd-resolved
      local interface
      interface=$(os_detect_vpn_interface)
      [[ -z "$interface" ]] && interface=$(os_detect_interface)

      if command -v resolvectl >/dev/null 2>&1; then
        resolvectl revert "$interface" 2>/dev/null || true
      fi
      ;;
    resolvconf)
      # Remove our resolvconf entry
      resolvconf -d "velum.velum" 2>/dev/null || true
      resolvconf -d "*.velum" 2>/dev/null || true
      ;;
    direct)
      # Remove immutable flag and restore
      chattr -i /etc/resolv.conf 2>/dev/null || true
      if [[ -f "$VELUM_RESOLV_BACKUP" ]]; then
        cp "$VELUM_RESOLV_BACKUP" /etc/resolv.conf
        rm -f "$VELUM_RESOLV_BACKUP"
      fi
      ;;
  esac

  rm -f "$VELUM_DNS_BACKUP"
}

# Get current DNS servers
os_get_dns() {
  grep "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | head -3
}

# ============================================================================
# KILL SWITCH (iptables)
# ============================================================================

# Generate iptables rules for kill switch
_generate_iptables_rules() {
  local vpn_ip="$1"
  local vpn_port="$2"
  local vpn_iface="$3"
  local lan_policy="$4"
  local physical_iface

  physical_iface=$(os_detect_interface)

  cat << EOF
# Velum VPN Kill Switch Rules (iptables)
# Flush existing chain if exists
-F $VELUM_IPTABLES_CHAIN 2>/dev/null || true
-X $VELUM_IPTABLES_CHAIN 2>/dev/null || true

# Create chain
-N $VELUM_IPTABLES_CHAIN

# Allow loopback
-A $VELUM_IPTABLES_CHAIN -i lo -j ACCEPT
-A $VELUM_IPTABLES_CHAIN -o lo -j ACCEPT

# Allow established connections
-A $VELUM_IPTABLES_CHAIN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow VPN tunnel interface
-A $VELUM_IPTABLES_CHAIN -o $vpn_iface -j ACCEPT
-A $VELUM_IPTABLES_CHAIN -i $vpn_iface -j ACCEPT

# Allow traffic TO VPN server
-A $VELUM_IPTABLES_CHAIN -o $physical_iface -p udp -d $vpn_ip --dport $vpn_port -j ACCEPT

# Allow DHCP
-A $VELUM_IPTABLES_CHAIN -o $physical_iface -p udp --sport 68 --dport 67 -j ACCEPT
-A $VELUM_IPTABLES_CHAIN -i $physical_iface -p udp --sport 67 --dport 68 -j ACCEPT

EOF

  # Add LAN rules based on policy
  if [[ "$lan_policy" != "block" ]]; then
    local subnet="$lan_policy"
    if [[ "$lan_policy" == "detect" ]]; then
      subnet=$(os_detect_subnet)
    fi

    if [[ -n "$subnet" ]]; then
      cat << EOF
# Allow local network ($subnet)
-A $VELUM_IPTABLES_CHAIN -s $subnet -d $subnet -j ACCEPT

EOF
    fi
  fi

  cat << EOF
# Block everything else
-A $VELUM_IPTABLES_CHAIN -j DROP

# Insert chain into OUTPUT and INPUT
-I OUTPUT 1 -j $VELUM_IPTABLES_CHAIN
-I INPUT 1 -j $VELUM_IPTABLES_CHAIN
EOF
}

# Enable kill switch using iptables
_enable_iptables_killswitch() {
  local vpn_ip="$1"
  local vpn_port="$2"
  local vpn_iface="$3"
  local lan_policy="$4"

  # Create the chain
  iptables -N "$VELUM_IPTABLES_CHAIN" 2>/dev/null || iptables -F "$VELUM_IPTABLES_CHAIN"
  ip6tables -N "$VELUM_IPTABLES_CHAIN" 2>/dev/null || ip6tables -F "$VELUM_IPTABLES_CHAIN"

  local physical_iface
  physical_iface=$(os_detect_interface)

  # IPv4 rules
  iptables -A "$VELUM_IPTABLES_CHAIN" -i lo -j ACCEPT
  iptables -A "$VELUM_IPTABLES_CHAIN" -o lo -j ACCEPT
  iptables -A "$VELUM_IPTABLES_CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -A "$VELUM_IPTABLES_CHAIN" -o "$vpn_iface" -j ACCEPT
  iptables -A "$VELUM_IPTABLES_CHAIN" -i "$vpn_iface" -j ACCEPT
  # Allow traffic to/from VPN server (WireGuard handshake)
  iptables -A "$VELUM_IPTABLES_CHAIN" -o "$physical_iface" -p udp -d "$vpn_ip" --dport "$vpn_port" -j ACCEPT
  iptables -A "$VELUM_IPTABLES_CHAIN" -i "$physical_iface" -p udp -s "$vpn_ip" --sport "$vpn_port" -j ACCEPT
  # Allow DHCP
  iptables -A "$VELUM_IPTABLES_CHAIN" -o "$physical_iface" -p udp --sport 68 --dport 67 -j ACCEPT
  iptables -A "$VELUM_IPTABLES_CHAIN" -i "$physical_iface" -p udp --sport 67 --dport 68 -j ACCEPT

  # LAN policy
  if [[ "$lan_policy" != "block" ]]; then
    local subnet="$lan_policy"
    [[ "$lan_policy" == "detect" ]] && subnet=$(os_detect_subnet)
    if [[ -n "$subnet" ]]; then
      iptables -A "$VELUM_IPTABLES_CHAIN" -s "$subnet" -d "$subnet" -j ACCEPT
    fi
  fi

  # Drop everything else
  iptables -A "$VELUM_IPTABLES_CHAIN" -j DROP

  # Block ALL IPv6
  ip6tables -A "$VELUM_IPTABLES_CHAIN" -j DROP

  # Insert chains into INPUT/OUTPUT
  iptables -I OUTPUT 1 -j "$VELUM_IPTABLES_CHAIN" 2>/dev/null || true
  iptables -I INPUT 1 -j "$VELUM_IPTABLES_CHAIN" 2>/dev/null || true
  ip6tables -I OUTPUT 1 -j "$VELUM_IPTABLES_CHAIN" 2>/dev/null || true
  ip6tables -I INPUT 1 -j "$VELUM_IPTABLES_CHAIN" 2>/dev/null || true

  return 0
}

# Disable iptables kill switch
_disable_iptables_killswitch() {
  # Remove from INPUT/OUTPUT
  iptables -D OUTPUT -j "$VELUM_IPTABLES_CHAIN" 2>/dev/null || true
  iptables -D INPUT -j "$VELUM_IPTABLES_CHAIN" 2>/dev/null || true
  ip6tables -D OUTPUT -j "$VELUM_IPTABLES_CHAIN" 2>/dev/null || true
  ip6tables -D INPUT -j "$VELUM_IPTABLES_CHAIN" 2>/dev/null || true

  # Flush and delete chain
  iptables -F "$VELUM_IPTABLES_CHAIN" 2>/dev/null || true
  iptables -X "$VELUM_IPTABLES_CHAIN" 2>/dev/null || true
  ip6tables -F "$VELUM_IPTABLES_CHAIN" 2>/dev/null || true
  ip6tables -X "$VELUM_IPTABLES_CHAIN" 2>/dev/null || true

  return 0
}

# Get iptables kill switch status
_iptables_killswitch_status() {
  if iptables -L "$VELUM_IPTABLES_CHAIN" -n >/dev/null 2>&1; then
    # Check if chain is referenced in OUTPUT
    if iptables -L OUTPUT -n 2>/dev/null | grep -q "$VELUM_IPTABLES_CHAIN"; then
      echo "active"
      return 0
    fi
  fi
  echo "inactive"
}

# Count iptables rules
_iptables_rule_count() {
  iptables -L "$VELUM_IPTABLES_CHAIN" -n 2>/dev/null | tail -n +3 | wc -l
}

# ============================================================================
# KILL SWITCH (nftables)
# ============================================================================

# Enable kill switch using nftables
_enable_nftables_killswitch() {
  local vpn_ip="$1"
  local vpn_port="$2"
  local vpn_iface="$3"
  local lan_policy="$4"

  local physical_iface
  physical_iface=$(os_detect_interface)

  local subnet=""
  if [[ "$lan_policy" != "block" ]]; then
    subnet="$lan_policy"
    [[ "$lan_policy" == "detect" ]] && subnet=$(os_detect_subnet)
  fi

  # Create nftables ruleset
  local nft_rules="
table inet $VELUM_NFT_TABLE {
  chain input {
    type filter hook input priority -100; policy drop;

    # Allow loopback
    iif lo accept

    # Allow established
    ct state established,related accept

    # Allow VPN interface
    iifname \"$vpn_iface\" accept

    # Allow from VPN server (WireGuard handshake response)
    iifname \"$physical_iface\" udp sport $vpn_port ip saddr $vpn_ip accept

    # Allow DHCP
    udp sport 67 udp dport 68 accept
  }

  chain output {
    type filter hook output priority -100; policy drop;

    # Allow loopback
    oif lo accept

    # Allow established
    ct state established,related accept

    # Allow VPN interface
    oifname \"$vpn_iface\" accept

    # Allow to VPN server
    oifname \"$physical_iface\" udp dport $vpn_port ip daddr $vpn_ip accept

    # Allow DHCP
    udp sport 68 udp dport 67 accept
"

  # Add LAN rule if needed
  if [[ -n "$subnet" ]]; then
    nft_rules="$nft_rules
    # Allow LAN
    ip saddr $subnet ip daddr $subnet accept
"
  fi

  nft_rules="$nft_rules
  }
}
"

  # Apply rules
  echo "$nft_rules" | nft -f -
}

# Disable nftables kill switch
_disable_nftables_killswitch() {
  nft delete table inet "$VELUM_NFT_TABLE" 2>/dev/null || true
  return 0
}

# Get nftables kill switch status
_nftables_killswitch_status() {
  if nft list table inet "$VELUM_NFT_TABLE" >/dev/null 2>&1; then
    echo "active"
  else
    echo "inactive"
  fi
}

# Count nftables rules
_nftables_rule_count() {
  nft list table inet "$VELUM_NFT_TABLE" 2>/dev/null | grep -c "accept\|drop" || echo 0
}

# ============================================================================
# KILL SWITCH (unified interface)
# ============================================================================

# Enable kill switch
# Usage: os_killswitch_enable --vpn-ip IP --vpn-port PORT --vpn-iface IFACE --lan-policy POLICY
os_killswitch_enable() {
  local vpn_ip=""
  local vpn_port="51820"
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

  # Validate
  if [[ -z "$vpn_ip" ]]; then
    echo "ERROR: --vpn-ip is required" >&2
    return 1
  fi

  # Auto-detect VPN interface
  if [[ -z "$vpn_iface" ]]; then
    vpn_iface=$(os_detect_vpn_interface)
    if [[ -z "$vpn_iface" ]]; then
      vpn_iface="wg0"  # Default WireGuard interface name on Linux
    fi
  fi

  # Use appropriate firewall
  local firewall
  firewall=$(_detect_firewall)

  case "$firewall" in
    nftables)
      _enable_nftables_killswitch "$vpn_ip" "$vpn_port" "$vpn_iface" "$lan_policy"
      ;;
    iptables)
      _enable_iptables_killswitch "$vpn_ip" "$vpn_port" "$vpn_iface" "$lan_policy"
      ;;
    *)
      echo "ERROR: No firewall available (install iptables or nftables)" >&2
      return 1
      ;;
  esac
}

# Disable kill switch
os_killswitch_disable() {
  local firewall
  firewall=$(_detect_firewall)

  case "$firewall" in
    nftables)
      _disable_nftables_killswitch
      ;;
    iptables)
      _disable_iptables_killswitch
      ;;
  esac

  return 0
}

# Get kill switch status
os_killswitch_status() {
  local firewall
  firewall=$(_detect_firewall)

  case "$firewall" in
    nftables)
      _nftables_killswitch_status
      ;;
    iptables)
      _iptables_killswitch_status
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

# Get rule count
os_killswitch_rule_count() {
  local firewall
  firewall=$(_detect_firewall)

  case "$firewall" in
    nftables)
      _nftables_rule_count
      ;;
    iptables)
      _iptables_rule_count
      ;;
    *)
      echo "0"
      ;;
  esac
}

# ============================================================================
# NOTIFICATIONS
# ============================================================================

# Send system notification
# Usage: os_notify "Title" "Message" ["urgency"]
os_notify() {
  local title="$1"
  local message="$2"
  local urgency="${3:-normal}"

  # Map macOS sound names to urgency
  case "$urgency" in
    Basso|critical) urgency="critical" ;;
    *) urgency="normal" ;;
  esac

  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u "$urgency" "$title" "$message" 2>/dev/null || true
  fi
}

# ============================================================================
# HOME DIRECTORY
# ============================================================================

# Get user's home directory (works with sudo)
os_get_home() {
  if [[ -n "${SUDO_USER:-}" ]]; then
    getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6
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
  date -d "$date_str" "+%s" 2>/dev/null
}

# Parse ISO8601 date to epoch
os_iso_to_epoch() {
  local date_str="$1"
  date -d "$date_str" "+%s" 2>/dev/null
}

# Add days to current date
os_date_add_days() {
  local days="$1"
  date -d "+${days} days" "+%Y-%m-%d"
}
