#!/usr/bin/env bash
# ivpn.sh - IVPN provider for velum-vpn
# Implements the provider interface for IVPN

# Prevent multiple sourcing
[[ -n "${_VELUM_PROVIDER_IVPN_LOADED:-}" ]] && return 0
readonly _VELUM_PROVIDER_IVPN_LOADED=1

# Source dependencies
source "${BASH_SOURCE%/*}/../velum-core.sh"
source "${BASH_SOURCE%/*}/../velum-security.sh"

# ============================================================================
# CONSTANTS
# ============================================================================

readonly IVPN_API_BASE="https://api.ivpn.net"
readonly IVPN_SERVERS_URL="https://api.ivpn.net/v5/servers.json"

# Default WireGuard port for IVPN
readonly IVPN_WG_PORT=2049

# ============================================================================
# PROVIDER METADATA
# ============================================================================

provider_name() {
  echo "IVPN"
}

provider_version() {
  echo "1.0.0"
}

# ============================================================================
# AUTHENTICATION
# ============================================================================

provider_auth_type() {
  echo "account_number"
}

# Validate IVPN account ID format
# Formats: i-XXXX-XXXX-XXXX (new) or ivpn-XXX-XXX-XXX (legacy)
# Usage: provider_validate_creds "i-xxxx-xxxx-xxxx"
provider_validate_creds() {
  local account_id="$1"
  local _unused="${2:-}"  # No password for IVPN

  # New format: i-XXXX-XXXX-XXXX (16 chars total with dashes)
  if [[ "$account_id" =~ ^i-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{4}-[a-zA-Z0-9]{4}$ ]]; then
    return 0
  fi

  # Legacy format: ivpn-XXX-XXX-XXX
  if [[ "$account_id" =~ ^ivpn-[a-zA-Z0-9]{3,4}-[a-zA-Z0-9]{3,4}-[a-zA-Z0-9]{3,4}$ ]]; then
    return 0
  fi

  log_error "Invalid IVPN account ID. Expected: i-XXXX-XXXX-XXXX or ivpn-XXX-XXX-XXX"
  return 1
}

# Authenticate with IVPN and get session token
# Usage: provider_authenticate "i-xxxx-xxxx-xxxx"
# Returns: JSON with session_token and expiry
provider_authenticate() {
  local account_id="$1"
  local _unused="${2:-}"  # No password

  # Mark for cleanup
  mark_sensitive account_id

  # Validate format
  provider_validate_creds "$account_id" || return 1

  log_info "Authenticating with IVPN..."

  local response
  response=$(curl -s --tlsv1.2 -X POST \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{\"username\": \"$account_id\"}" \
    "${IVPN_API_BASE}/v4/session/new")

  # Check for session token
  local session_token
  session_token=$(echo "$response" | jq -r '.token // empty')

  if [[ -z "$session_token" ]]; then
    local error_msg status
    status=$(echo "$response" | jq -r '.status // 0')
    error_msg=$(echo "$response" | jq -r '.message // "Unknown error"')

    # Handle captcha requirement
    if [[ "$status" == "70011" ]]; then
      log_error "IVPN requires captcha verification. Please log in via web first."
      return 1
    fi

    log_error "Authentication failed: $error_msg"
    return 1
  fi

  # Check service status
  local is_active
  is_active=$(echo "$response" | jq -r '.service_status.is_active // false')
  if [[ "$is_active" != "true" ]]; then
    log_error "IVPN account is not active. Please check your subscription."
    return 1
  fi

  # Get expiry from service status
  local active_until expiry
  active_until=$(echo "$response" | jq -r '.service_status.active_until // 0')
  if [[ "$active_until" != "0" && "$active_until" != "null" ]]; then
    # Convert Unix timestamp to date string
    if [[ "$(uname)" == "Darwin" ]]; then
      expiry=$(date -r "$active_until" "+%Y-%m-%dT%H:%M:%S%z" 2>/dev/null || echo "unknown")
    else
      expiry=$(date -d "@$active_until" "+%Y-%m-%dT%H:%M:%S%z" 2>/dev/null || echo "unknown")
    fi
  else
    expiry="unknown"
  fi

  # Save session token
  save_token "$session_token" "$expiry" "${VELUM_TOKENS_DIR}/ivpn_token"

  # Store account ID for later use
  init_config_dirs
  (
    umask 077
    echo "$account_id" > "${VELUM_TOKENS_DIR}/ivpn_account"
  )
  chmod 600 "${VELUM_TOKENS_DIR}/ivpn_account"

  # Fix ownership if running as root via sudo
  if [[ -n "${SUDO_USER:-}" ]] && _validate_username "$SUDO_USER"; then
    local sudo_uid sudo_gid
    sudo_uid=$(id -u "$SUDO_USER" 2>/dev/null)
    sudo_gid=$(id -g "$SUDO_USER" 2>/dev/null)
    if [[ -n "$sudo_uid" && -n "$sudo_gid" ]]; then
      chown "$sudo_uid:$sudo_gid" "${VELUM_TOKENS_DIR}/ivpn_account"
      chown "$sudo_uid:$sudo_gid" "${VELUM_TOKENS_DIR}/ivpn_token"
    fi
  fi

  # Clean up
  unset account_id

  echo "{\"access_token\": \"$session_token\", \"expires_at\": \"$expiry\"}"
}

# Get stored session token
_get_ivpn_token() {
  local token_file="${VELUM_TOKENS_DIR}/ivpn_token"
  [[ -f "$token_file" ]] && sed -n '1p' "$token_file" 2>/dev/null
}

# Get stored account ID
_get_ivpn_account() {
  local account_file="${VELUM_TOKENS_DIR}/ivpn_account"
  [[ -f "$account_file" ]] && cat "$account_file" 2>/dev/null
}

# ============================================================================
# SERVER LIST
# ============================================================================

# Cache for server list
_IVPN_SERVER_CACHE=""
_IVPN_SERVER_CACHE_TIME=0
readonly IVPN_CACHE_TTL=300  # 5 minutes

# Fetch server list from IVPN
provider_get_servers() {
  local now
  now=$(date +%s)

  # Return cached if still valid
  if [[ -n "$_IVPN_SERVER_CACHE" ]] && [[ $((now - _IVPN_SERVER_CACHE_TIME)) -lt $IVPN_CACHE_TTL ]]; then
    echo "$_IVPN_SERVER_CACHE"
    return 0
  fi

  log_info "Fetching IVPN server list..."

  local response
  response=$(curl -s --tlsv1.2 "$IVPN_SERVERS_URL")

  if [[ -z "$response" ]] || ! echo "$response" | jq -e '.wireguard[0].gateway' >/dev/null 2>&1; then
    log_error "Failed to fetch server list"
    return 1
  fi

  # Cache the response
  _IVPN_SERVER_CACHE="$response"
  _IVPN_SERVER_CACHE_TIME=$now

  echo "$response"
}

# Filter servers by criteria
# Usage: provider_filter_servers [--country XX]
provider_filter_servers() {
  local country=""
  local city=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --country) country="$2"; shift 2 ;;
      --city) city="$2"; shift 2 ;;
      --geo) shift 2 ;;  # IVPN doesn't have geo servers concept
      --port-forward) shift 2 ;;  # IVPN removed port forwarding
      *) shift ;;
    esac
  done

  local servers
  servers=$(provider_get_servers) || return 1

  # Build jq filter for WireGuard servers
  local jq_filter="[.wireguard[] | select(.hosts | length > 0)"

  if [[ -n "$country" ]]; then
    jq_filter="$jq_filter | select(.country_code == \"$country\")"
  fi

  if [[ -n "$city" ]]; then
    jq_filter="$jq_filter | select(.city == \"$city\")"
  fi

  jq_filter="$jq_filter]"

  echo "$servers" | jq "$jq_filter"
}

# Test latency to a server
# Usage: provider_test_latency "hostname"
provider_test_latency() {
  local hostname="$1"
  local timeout="${2:-1000}"

  local servers
  servers=$(provider_get_servers) || return 1

  # Get server IP from hosts array
  local server_ip
  server_ip=$(echo "$servers" | jq -r --arg h "$hostname" \
    '.wireguard[] | .hosts[] | select(.hostname == $h) | .host // empty')

  if [[ -z "$server_ip" ]]; then
    echo "999999"
    return 1
  fi

  # Ping the server
  local latency
  if [[ "$(uname)" == "Darwin" ]]; then
    latency=$(ping -c 1 -t 1 "$server_ip" 2>/dev/null | grep "time=" | sed 's/.*time=\([0-9.]*\).*/\1/')
  else
    latency=$(ping -c 1 -W 1 "$server_ip" 2>/dev/null | grep "time=" | sed 's/.*time=\([0-9.]*\).*/\1/')
  fi

  if [[ -z "$latency" ]]; then
    echo "999999"
    return 1
  fi

  echo "$latency"
}

# ============================================================================
# WIREGUARD CONNECTION
# ============================================================================

# Exchange WireGuard keys with IVPN
# Usage: provider_wg_exchange "server_ip" "hostname" "public_key"
provider_wg_exchange() {
  local server_ip="$1"
  local hostname="$2"
  local public_key="$3"
  local _dip_unused="${4:-}"  # IVPN doesn't support DIP

  local session_token
  session_token=$(_get_ivpn_token)

  if [[ -z "$session_token" ]]; then
    log_error "No IVPN session token found. Please authenticate first."
    return 1
  fi

  log_info "Registering WireGuard key with IVPN..."

  local response
  response=$(curl -s --tlsv1.2 -X POST \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{\"session_token\": \"$session_token\", \"public_key\": \"$public_key\"}" \
    "${IVPN_API_BASE}/v4/session/wg/set")

  # Check response status
  local status
  status=$(echo "$response" | jq -r '.status // 0')

  if [[ "$status" != "200" ]]; then
    local error_msg
    error_msg=$(echo "$response" | jq -r '.message // "Unknown error"')
    log_error "WireGuard key registration failed: $error_msg"
    return 1
  fi

  # Get assigned IP address
  local peer_ip
  peer_ip=$(echo "$response" | jq -r '.ip_address // empty')

  if [[ -z "$peer_ip" ]]; then
    log_error "No IP address received from IVPN"
    return 1
  fi

  # Get server public key from server list
  local servers
  servers=$(provider_get_servers)
  local server_key
  server_key=$(echo "$servers" | jq -r --arg h "$hostname" \
    '.wireguard[] | .hosts[] | select(.hostname == $h) | .public_key // empty')

  if [[ -z "$server_key" ]]; then
    log_error "Could not find server public key for $hostname"
    return 1
  fi

  # Build response in common format
  echo "{\"status\": \"OK\", \"peer_ip\": \"$peer_ip\", \"server_key\": \"$server_key\", \"server_port\": $IVPN_WG_PORT, \"dns_servers\": [\"10.0.254.1\"]}"
}

# ============================================================================
# PORT FORWARDING - NOT SUPPORTED
# ============================================================================

provider_supports_pf() {
  return 1  # IVPN removed port forwarding
}

provider_enable_pf() {
  log_error "IVPN does not support port forwarding"
  return 1
}

provider_refresh_pf() {
  return 1
}

# ============================================================================
# DEDICATED IP - NOT SUPPORTED
# ============================================================================

provider_supports_dip() {
  return 1  # IVPN doesn't offer dedicated IPs
}

provider_get_dip() {
  log_error "IVPN does not support dedicated IP addresses"
  return 1
}

# ============================================================================
# PROVIDER-SPECIFIC
# ============================================================================

provider_get_dns() {
  # IVPN's internal DNS server
  echo "10.0.254.1"
}

provider_get_ca_cert() {
  # IVPN doesn't require a CA cert for API calls (uses public TLS)
  echo ""
}

# ============================================================================
# IVPN-SPECIFIC FEATURES
# ============================================================================

# List available countries
ivpn_list_countries() {
  local servers
  servers=$(provider_get_servers) || return 1

  echo "$servers" | jq -r '[.wireguard[] | {country_code, country}] | unique_by(.country_code) | .[] | "\(.country_code)\t\(.country)"' | sort
}

# List cities in a country
ivpn_list_cities() {
  local country="$1"
  local servers
  servers=$(provider_get_servers) || return 1

  echo "$servers" | jq -r --arg c "$country" \
    '[.wireguard[] | select(.country_code == $c) | .city] | unique | .[]' | sort
}

# Get best server in a location
ivpn_get_best_server() {
  local country="${1:-}"
  local city="${2:-}"

  local filters=""
  [[ -n "$country" ]] && filters="--country $country"
  [[ -n "$city" ]] && filters="$filters --city $city"

  local servers
  # shellcheck disable=SC2086
  servers=$(provider_filter_servers $filters) || return 1

  # Test latency and find best
  local best_hostname=""
  local best_ip=""
  local best_latency=999999

  while IFS= read -r server; do
    local gateway hostname ip latency
    gateway=$(echo "$server" | jq -r '.gateway')
    hostname=$(echo "$server" | jq -r '.hosts[0].hostname')
    ip=$(echo "$server" | jq -r '.hosts[0].host')

    [[ -z "$ip" || "$ip" == "null" ]] && continue

    echo -n "  Testing $gateway... " >&2
    latency=$(provider_test_latency "$hostname" 2>/dev/null || echo "999999")
    echo "${latency}ms" >&2

    local latency_int=${latency%.*}
    local best_int=${best_latency%.*}

    if [[ "$latency_int" -lt "$best_int" ]]; then
      best_hostname="$hostname"
      best_ip="$ip"
      best_latency="$latency"
    fi
  done < <(echo "$servers" | jq -c '.[:10][]')

  if [[ -n "$best_hostname" ]]; then
    echo "{\"hostname\": \"$best_hostname\", \"ip\": \"$best_ip\", \"latency\": $best_latency}"
  else
    return 1
  fi
}

# Delete session (logout)
ivpn_logout() {
  local session_token
  session_token=$(_get_ivpn_token)

  if [[ -z "$session_token" ]]; then
    log_warn "No session token found"
    return 0
  fi

  curl -s --tlsv1.2 -X POST \
    -H "Content-Type: application/json" \
    -d "{\"session_token\": \"$session_token\"}" \
    "${IVPN_API_BASE}/v4/session/delete" >/dev/null

  rm -f "${VELUM_TOKENS_DIR}/ivpn_token" "${VELUM_TOKENS_DIR}/ivpn_account"
  log_info "IVPN session deleted"
}
