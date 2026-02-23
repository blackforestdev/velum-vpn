#!/usr/bin/env bash
# mullvad.sh - Mullvad VPN provider for velum-vpn
# Implements the provider interface for Mullvad

# Prevent multiple sourcing
[[ -n "${_VELUM_PROVIDER_MULLVAD_LOADED:-}" ]] && return 0
readonly _VELUM_PROVIDER_MULLVAD_LOADED=1

# Source dependencies
source "${BASH_SOURCE%/*}/../velum-core.sh"
source "${BASH_SOURCE%/*}/../velum-security.sh"
source "${BASH_SOURCE%/*}/../velum-credential.sh"

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

  # Save token to tmpfs (session storage, cleared on reboot)
  # SECURITY: Account number is NOT stored - user will be prompted on token refresh
  credential_store_token "mullvad" "$access_token" "$expiry"

  # Clean up account number from memory
  unset account_number

  echo "{\"access_token\": \"$access_token\", \"expires_at\": \"$expiry\"}"
}

# Get stored access token from tmpfs
_get_mullvad_token() {
  credential_get_token "mullvad"
}

# NOTE: Account numbers are no longer stored on disk.
# Users are prompted for account number when token refresh is needed.
# This is a security feature to prevent credential theft if device is captured.

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
  response=$(curl -s --tlsv1.2 --connect-timeout 10 --max-time 30 "$MULLVAD_SERVERS_URL")

  if [[ -z "$response" ]]; then
    log_error "Failed to fetch server list: empty response"
    return 1
  fi

  # Validate JSON structure
  if ! printf '%s' "$response" | jq -e '.[0].hostname' >/dev/null 2>&1; then
    log_error "Failed to parse server list"
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
# Usage: provider_wg_exchange "server_ip" "hostname" "public_key" "dip_token" "account_number"
# Note: account_number is required for Mullvad's WG key registration API
# IMPORTANT: This function must only output JSON to stdout (no print_info/echo)
provider_wg_exchange() {
  local server_ip="$1"
  local hostname="$2"
  local public_key="$3"
  local _dip_unused="${4:-}"  # Mullvad doesn't support DIP
  local account_number="${5:-}"  # Account number passed from caller

  # Account number is required for WG key registration
  if [[ -z "$account_number" ]]; then
    log_error "Account number is required for WireGuard key exchange."
    log_error "Caller must provide account number as 5th parameter."
    return 1
  fi

  # Validate format
  if ! provider_validate_creds "$account_number"; then
    return 1
  fi

  # Mark for cleanup
  mark_sensitive account_number

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
    if ! servers=$(provider_get_servers); then
      log_error "Failed to get server list for public key lookup"
      unset account_number
      return 1
    fi

    # Get server public key from server list
    local server_key
    server_key=$(printf '%s' "$servers" | jq -r --arg h "$hostname" \
      '.[] | select(.hostname == $h) | .pubkey // empty')

    if [[ -z "$server_key" || "$server_key" == "null" ]]; then
      log_error "Could not find server public key for $hostname"
      unset account_number
      return 1
    fi

    if [[ -z "$server_key" || "$server_key" == "null" ]]; then
      log_error "Could not find server public key for $hostname"
      unset account_number
      return 1
    fi

    # Clean up account number from memory
    unset account_number

    # Build response in standard provider format
    echo "{\"status\": \"OK\", \"peer_ip\": \"$peer_ip\", \"server_key\": \"$server_key\", \"server_port\": $MULLVAD_WG_PORT, \"dns_servers\": [\"10.64.0.1\"]}"
  else
    # Clean up account number from memory
    unset account_number

    # Error response
    local error_msg
    error_msg=$(echo "$response" | jq -r '.error // .message // empty' 2>/dev/null || echo "$response")
    log_error "WireGuard key registration failed: $error_msg"

    # Detect key limit error - return exit code 2 so callers can offer recovery
    if [[ "$error_msg" == *"KEY_LIMIT"* ]] || [[ "$error_msg" == *"key limit"* ]] || \
       [[ "$error_msg" == *"Too many"* ]] || [[ "$error_msg" == *"too many"* ]] || \
       [[ "$error_msg" == *"max number"* ]]; then
      log_info "Hint: Use 'velum device' to manage registered WireGuard keys"
      return 2
    fi

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

  local response
  response=$(curl -s --tlsv1.2 \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer $token" \
    "${MULLVAD_ACCOUNTS_API}/devices")

  unset token

  # Validate response is a JSON array (not an error object)
  if ! printf '%s' "$response" | jq -e 'type == "array"' >/dev/null 2>&1; then
    local error_msg
    error_msg=$(printf '%s' "$response" | jq -r '.message // .error // empty' 2>/dev/null)
    log_error "Failed to list devices: ${error_msg:-invalid response}"
    return 1
  fi

  echo "$response"
}

# Revoke a WireGuard key
mullvad_revoke_key() {
  local pubkey="$1"

  # Validate pubkey format before sending to API
  if ! validate_wg_key "$pubkey"; then
    log_error "Invalid WireGuard public key format"
    return 1
  fi

  local token
  token=$(_get_mullvad_token)

  if [[ -z "$token" ]]; then
    log_error "No access token. Please authenticate first."
    return 1
  fi

  local response http_code
  http_code=$(curl -s --tlsv1.2 -X POST \
    -o /dev/null -w '%{http_code}' \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $token" \
    -d "{\"pubkey\": \"$pubkey\"}" \
    "https://api.mullvad.net/www/wg-pubkeys/revoke/")

  unset token

  # 204 No Content = success for revocation
  # 200 OK = also success
  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    return 0
  else
    log_error "Key revocation failed (HTTP $http_code)"
    return 1
  fi
}

# ============================================================================
# DEVICE MANAGEMENT INTERFACE
# ============================================================================

provider_supports_device_mgmt() {
  return 0
}

provider_list_devices() {
  mullvad_list_devices
}

provider_revoke_device() {
  local pubkey="$1"
  mullvad_revoke_key "$pubkey"
}
