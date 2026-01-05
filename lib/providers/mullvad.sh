#!/usr/bin/env bash
# mullvad.sh - Mullvad VPN provider for velum-vpn
# Implements the provider interface for Mullvad

# Prevent multiple sourcing
[[ -n "${_VELUM_PROVIDER_MULLVAD_LOADED:-}" ]] && return 0
readonly _VELUM_PROVIDER_MULLVAD_LOADED=1

# Source dependencies
source "${BASH_SOURCE%/*}/../velum-core.sh"
source "${BASH_SOURCE%/*}/../velum-security.sh"

# ============================================================================
# CONSTANTS
# ============================================================================

readonly MULLVAD_AUTH_API="https://api.mullvad.net/auth/v1"
readonly MULLVAD_ACCOUNTS_API="https://api.mullvad.net/accounts/v1"
readonly MULLVAD_SERVERS_URL="https://api.mullvad.net/www/relays/all/"
readonly MULLVAD_LEGACY_WG_API="https://api.mullvad.net/wg/"

# Default WireGuard port for Mullvad
readonly MULLVAD_WG_PORT=51820

# ============================================================================
# PROVIDER METADATA
# ============================================================================

provider_name() {
  echo "Mullvad"
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

# Validate Mullvad account number format (16 digits)
# Usage: provider_validate_creds "1234567890123456"
provider_validate_creds() {
  local account_number="$1"
  local _unused="${2:-}"  # No password for Mullvad

  # Account number must be exactly 16 digits
  if ! [[ "$account_number" =~ ^[0-9]{16}$ ]]; then
    log_error "Invalid Mullvad account number. Expected: 16 digits"
    return 1
  fi

  return 0
}

# Authenticate with Mullvad and get access token
# Usage: provider_authenticate "1234567890123456"
# Returns: JSON with access_token and expiry
provider_authenticate() {
  local account_number="$1"
  local _unused="${2:-}"  # No password

  # Mark for cleanup
  mark_sensitive account_number

  # Validate format
  provider_validate_creds "$account_number" || return 1

  log_info "Authenticating with Mullvad..."

  local response
  response=$(curl -s --tlsv1.2 -X POST \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{\"account_number\": \"$account_number\"}" \
    "${MULLVAD_AUTH_API}/token")

  # Check for access_token
  local access_token
  access_token=$(echo "$response" | jq -r '.access_token // empty')

  if [[ -z "$access_token" ]]; then
    local error_msg
    error_msg=$(echo "$response" | jq -r '.message // .error // "Unknown error"')
    log_error "Authentication failed: $error_msg"
    return 1
  fi

  # Extract expiry
  local expiry
  expiry=$(echo "$response" | jq -r '.expiry // empty')

  # Save token (Mullvad tokens are longer-lived than PIA)
  save_token "$access_token" "$expiry" "${VELUM_TOKENS_DIR}/mullvad_token"

  # Store account number for WireGuard key operations
  init_config_dirs
  (
    umask 077
    echo "$account_number" > "${VELUM_TOKENS_DIR}/mullvad_account"
  )
  chmod 600 "${VELUM_TOKENS_DIR}/mullvad_account"

  # Fix ownership if running as root via sudo
  if [[ -n "${SUDO_USER:-}" ]]; then
    local sudo_uid sudo_gid
    sudo_uid=$(id -u "$SUDO_USER" 2>/dev/null)
    sudo_gid=$(id -g "$SUDO_USER" 2>/dev/null)
    if [[ -n "$sudo_uid" && -n "$sudo_gid" ]]; then
      chown "$sudo_uid:$sudo_gid" "${VELUM_TOKENS_DIR}/mullvad_account"
    fi
  fi

  # Clean up
  unset account_number

  echo "{\"access_token\": \"$access_token\", \"expires_at\": \"$expiry\"}"
}

# Get stored access token
_get_mullvad_token() {
  local token_file="${VELUM_TOKENS_DIR}/mullvad_token"
  [[ -f "$token_file" ]] && sed -n '1p' "$token_file" 2>/dev/null
}

# Get stored account number
_get_mullvad_account() {
  local account_file="${VELUM_TOKENS_DIR}/mullvad_account"
  [[ -f "$account_file" ]] && cat "$account_file" 2>/dev/null
}

# ============================================================================
# SERVER LIST
# ============================================================================

# Cache for server list
_MULLVAD_SERVER_CACHE=""
_MULLVAD_SERVER_CACHE_TIME=0
readonly MULLVAD_CACHE_TTL=300  # 5 minutes

# Fetch server list from Mullvad
provider_get_servers() {
  local now
  now=$(date +%s)

  # Return cached if still valid
  if [[ -n "$_MULLVAD_SERVER_CACHE" ]] && [[ $((now - _MULLVAD_SERVER_CACHE_TIME)) -lt $MULLVAD_CACHE_TTL ]]; then
    echo "$_MULLVAD_SERVER_CACHE"
    return 0
  fi

  log_info "Fetching Mullvad server list..."

  local response
  response=$(curl -s --tlsv1.2 "$MULLVAD_SERVERS_URL")

  if [[ -z "$response" ]] || ! echo "$response" | jq -e '.[0].hostname' >/dev/null 2>&1; then
    log_error "Failed to fetch server list"
    return 1
  fi

  # Cache the response
  _MULLVAD_SERVER_CACHE="$response"
  _MULLVAD_SERVER_CACHE_TIME=$now

  echo "$response"
}

# Filter servers by criteria
# Usage: provider_filter_servers [--type wireguard] [--country XX]
provider_filter_servers() {
  local server_type="wireguard"
  local country=""
  local city=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type) server_type="$2"; shift 2 ;;
      --country) country="$2"; shift 2 ;;
      --city) city="$2"; shift 2 ;;
      --geo) shift 2 ;;  # Mullvad doesn't have geo servers concept
      --port-forward) shift 2 ;;  # Mullvad removed port forwarding
      *) shift ;;
    esac
  done

  local servers
  servers=$(provider_get_servers) || return 1

  # Build jq filter
  local jq_filter="[.[] | select(.type == \"$server_type\" and .active == true)"

  if [[ -n "$country" ]]; then
    jq_filter="$jq_filter | select(.country_code == \"$country\")"
  fi

  if [[ -n "$city" ]]; then
    jq_filter="$jq_filter | select(.city_code == \"$city\")"
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

  # Get server IP
  local server_ip
  server_ip=$(echo "$servers" | jq -r --arg h "$hostname" \
    '.[] | select(.hostname == $h) | .ipv4_addr_in // empty')

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

# Exchange WireGuard keys with Mullvad
# Uses the legacy API which is simpler (no device management needed)
# Usage: provider_wg_exchange "server_ip" "hostname" "public_key"
provider_wg_exchange() {
  local server_ip="$1"
  local hostname="$2"
  local public_key="$3"
  local _dip_unused="$4"  # Mullvad doesn't support DIP

  local account_number
  account_number=$(_get_mullvad_account)

  if [[ -z "$account_number" ]]; then
    log_error "No Mullvad account number found. Please authenticate first."
    return 1
  fi

  log_info "Registering WireGuard key with Mullvad..."

  # Use legacy API - simpler and doesn't require device management
  local response
  response=$(curl -s --tlsv1.2 -X POST \
    -d "account=$account_number" \
    --data-urlencode "pubkey=$public_key" \
    "$MULLVAD_LEGACY_WG_API")

  # Legacy API returns IP addresses on success (IPv4,IPv6 or just IPv4), or error JSON
  # Example success: "10.73.101.32/32,fc00:bbbb:bbbb:bb01::a:651f/128" or "10.73.101.32/32"
  if [[ "$response" =~ ^10\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+ ]]; then
    # Success - extract IPv4 peer IP (first part before comma if present)
    local peer_ip
    peer_ip=$(echo "$response" | cut -d',' -f1)

    # Get server public key from server list
    local servers
    servers=$(provider_get_servers)
    local server_key
    server_key=$(echo "$servers" | jq -r --arg h "$hostname" \
      '.[] | select(.hostname == $h) | .pubkey // empty')

    if [[ -z "$server_key" ]]; then
      log_error "Could not find server public key for $hostname"
      return 1
    fi

    # Build response in PIA-compatible format
    echo "{\"status\": \"OK\", \"peer_ip\": \"$peer_ip\", \"server_key\": \"$server_key\", \"server_port\": $MULLVAD_WG_PORT, \"dns_servers\": [\"10.64.0.1\"]}"
  else
    # Error response
    local error_msg
    error_msg=$(echo "$response" | jq -r '.error // .message // empty' 2>/dev/null || echo "$response")
    log_error "WireGuard key registration failed: $error_msg"
    return 1
  fi
}

# ============================================================================
# PORT FORWARDING - NOT SUPPORTED
# ============================================================================

provider_supports_pf() {
  return 1  # Mullvad removed port forwarding in July 2023
}

provider_enable_pf() {
  log_error "Mullvad does not support port forwarding (removed July 2023)"
  return 1
}

provider_refresh_pf() {
  return 1
}

# ============================================================================
# DEDICATED IP - NOT SUPPORTED
# ============================================================================

provider_supports_dip() {
  return 1  # Mullvad doesn't offer dedicated IPs
}

provider_get_dip() {
  log_error "Mullvad does not support dedicated IP addresses"
  return 1
}

# ============================================================================
# PROVIDER-SPECIFIC
# ============================================================================

provider_get_dns() {
  # Mullvad's DNS server
  echo "10.64.0.1"
}

provider_get_ca_cert() {
  # Mullvad doesn't require a CA cert for API calls (uses public TLS)
  echo ""
}

# ============================================================================
# MULLVAD-SPECIFIC FEATURES
# ============================================================================

# List available countries
mullvad_list_countries() {
  local servers
  servers=$(provider_get_servers) || return 1

  echo "$servers" | jq -r '[.[] | select(.type == "wireguard" and .active == true) | {country_code, country_name}] | unique_by(.country_code) | .[] | "\(.country_code)\t\(.country_name)"' | sort
}

# List cities in a country
mullvad_list_cities() {
  local country="$1"
  local servers
  servers=$(provider_get_servers) || return 1

  echo "$servers" | jq -r --arg c "$country" \
    '[.[] | select(.type == "wireguard" and .active == true and .country_code == $c) | {city_code, city_name}] | unique_by(.city_code) | .[] | "\(.city_code)\t\(.city_name)"' | sort
}

# Get best server in a location
mullvad_get_best_server() {
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
    local hostname ip latency
    hostname=$(echo "$server" | jq -r '.hostname')
    ip=$(echo "$server" | jq -r '.ipv4_addr_in')

    echo -n "  Testing $hostname... " >&2
    latency=$(provider_test_latency "$hostname" 2>/dev/null || echo "999999")
    echo "${latency}ms" >&2

    local latency_int=${latency%.*}
    local best_int=${best_latency%.*}

    if [[ "$latency_int" -lt "$best_int" ]]; then
      best_hostname="$hostname"
      best_ip="$ip"
      best_latency="$latency"
    fi

    # Test max 10 servers
    [[ $(echo "$servers" | jq -r --arg h "$hostname" 'map(select(.hostname == $h)) | length') -gt 10 ]] && break
  done < <(echo "$servers" | jq -c '.[:10][]')

  if [[ -n "$best_hostname" ]]; then
    echo "{\"hostname\": \"$best_hostname\", \"ip\": \"$best_ip\", \"latency\": $best_latency}"
  else
    return 1
  fi
}

# List registered WireGuard keys (devices) on account
mullvad_list_devices() {
  local token
  token=$(_get_mullvad_token)

  if [[ -z "$token" ]]; then
    log_error "No access token. Please authenticate first."
    return 1
  fi

  curl -s --tlsv1.2 \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer $token" \
    "${MULLVAD_ACCOUNTS_API}/devices"
}

# Revoke a WireGuard key
mullvad_revoke_key() {
  local pubkey="$1"
  local token
  token=$(_get_mullvad_token)

  if [[ -z "$token" ]]; then
    log_error "No access token. Please authenticate first."
    return 1
  fi

  curl -s --tlsv1.2 -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $token" \
    -d "{\"pubkey\": \"$pubkey\"}" \
    "https://api.mullvad.net/www/wg-pubkeys/revoke/"
}
