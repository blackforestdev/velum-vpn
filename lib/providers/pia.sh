#!/usr/bin/env bash
# pia.sh - Private Internet Access provider for velum-vpn
# Implements the provider interface for PIA

# Prevent multiple sourcing
[[ -n "${_VELUM_PROVIDER_PIA_LOADED:-}" ]] && return 0
readonly _VELUM_PROVIDER_PIA_LOADED=1

# Source dependencies
source "${BASH_SOURCE%/*}/../velum-core.sh"
source "${BASH_SOURCE%/*}/../velum-security.sh"

# ============================================================================
# CONSTANTS
# ============================================================================

readonly PIA_API_BASE="https://www.privateinternetaccess.com/api/client/v2"
readonly PIA_SERVERS_URL="https://serverlist.piaservers.net/vpninfo/servers/v6"

# ============================================================================
# PROVIDER METADATA
# ============================================================================

provider_name() {
  echo "PIA"
}

provider_version() {
  echo "1.0.0"
}

# ============================================================================
# AUTHENTICATION
# ============================================================================

provider_auth_type() {
  echo "username_password"
}

# Validate PIA credential format
# Usage: provider_validate_creds "p1234567" "password"
provider_validate_creds() {
  local username="$1"
  local password="$2"

  # Username must be p followed by 7 digits
  if ! [[ "$username" =~ ^p[0-9]{7}$ ]]; then
    log_error "Invalid PIA username format. Expected: p####### (p followed by 7 digits)"
    return 1
  fi

  # Password must not be empty
  if [[ -z "$password" ]]; then
    log_error "Password cannot be empty"
    return 1
  fi

  return 0
}

# Authenticate with PIA and get token
# Usage: provider_authenticate "p1234567" "password"
# Returns: JSON with token and expiry
provider_authenticate() {
  local username="$1"
  local password="$2"

  # Mark credentials as sensitive for cleanup
  mark_sensitive username
  mark_sensitive password

  # Validate credentials format
  provider_validate_creds "$username" "$password" || return 1

  log_info "Authenticating with PIA..."

  local response
  response=$(curl -s --tlsv1.2 --location --request POST \
    "${PIA_API_BASE}/token" \
    --form "username=$username" \
    --form "password=$password")

  # Check for empty response (network/API error)
  if [[ -z "$response" ]]; then
    log_error "Authentication failed: No response from PIA API (network error?)"
    return 1
  fi

  # Validate response
  local token
  token=$(echo "$response" | jq -r '.token // empty' 2>/dev/null)

  if [[ -z "$token" ]]; then
    local error_msg
    # Try to extract error message from JSON, handle parse failures
    if echo "$response" | jq -e . >/dev/null 2>&1; then
      error_msg=$(echo "$response" | jq -r '.message // "Unknown error"')
    else
      # Response is not valid JSON (HTML error page, etc.)
      error_msg="Invalid response from API (check credentials)"
    fi
    log_error "Authentication failed: $error_msg"
    return 1
  fi

  # Token is valid for 24 hours
  local expiry
  if [[ "$(uname)" == "Darwin" ]]; then
    expiry=$(date -v+24H "+%a %b %d %T %Z %Y")
  else
    expiry=$(date --date="+24 hours" "+%a %b %d %T %Z %Y")
  fi

  # Save token
  save_token "$token" "$expiry"

  # Clean up credentials from memory
  unset username password

  # Return token info
  echo "{\"token\": \"$token\", \"expires_at\": \"$expiry\"}"
}

# ============================================================================
# SERVER LIST
# ============================================================================

# Cache for server list
_PIA_SERVER_CACHE=""
_PIA_SERVER_CACHE_TIME=0
readonly PIA_CACHE_TTL=300  # 5 minutes

# Fetch server list from PIA
provider_get_servers() {
  local now
  now=$(date +%s)

  # Return cached if still valid
  if [[ -n "$_PIA_SERVER_CACHE" ]] && [[ $((now - _PIA_SERVER_CACHE_TIME)) -lt $PIA_CACHE_TTL ]]; then
    echo "$_PIA_SERVER_CACHE"
    return 0
  fi

  log_info "Fetching PIA server list..."

  local response
  # PIA returns JSON on first line, followed by a signature on subsequent lines
  # Extract only the first line (the JSON data)
  response=$(curl -s --tlsv1.2 "$PIA_SERVERS_URL" | head -1)

  if [[ -z "$response" ]]; then
    log_error "Failed to fetch server list: empty response"
    return 1
  fi

  if ! echo "$response" | jq -e '.regions' >/dev/null 2>&1; then
    log_error "Failed to fetch server list: invalid JSON"
    return 1
  fi

  # Cache the response
  _PIA_SERVER_CACHE="$response"
  _PIA_SERVER_CACHE_TIME=$now

  echo "$response"
}

# Filter servers by criteria
# Usage: provider_filter_servers [--geo true|false] [--port-forward true|false]
provider_filter_servers() {
  local allow_geo="true"
  local require_pf="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --geo) allow_geo="$2"; shift 2 ;;
      --port-forward) require_pf="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  local servers
  servers=$(provider_get_servers) || return 1

  local jq_filter=".regions"

  # Filter by geo
  if [[ "$allow_geo" != "true" ]]; then
    jq_filter="$jq_filter | map(select(.geo == false))"
  fi

  # Filter by port forwarding
  if [[ "$require_pf" == "true" ]]; then
    jq_filter="$jq_filter | map(select(.port_forward == true))"
  fi

  echo "$servers" | jq "$jq_filter"
}

# Test latency to a server
# Usage: provider_test_latency "region_id" [timeout_ms]
provider_test_latency() {
  local region_id="$1"
  local timeout="${2:-1000}"  # Default 1 second

  local servers
  servers=$(provider_get_servers) || return 1

  # Get first WireGuard server IP for this region
  local server_ip
  server_ip=$(echo "$servers" | jq -r --arg id "$region_id" \
    '.regions[] | select(.id == $id) | .servers.wg[0].ip // empty')

  if [[ -z "$server_ip" ]]; then
    echo "999999"  # Very high latency means unreachable
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

# Exchange WireGuard keys with PIA server
# Usage: provider_wg_exchange "server_ip" "hostname" "public_key" [dip_token]
provider_wg_exchange() {
  local server_ip="$1"
  local hostname="$2"
  local public_key="$3"
  local dip_token="${4:-}"

  local token
  token=$(read_token)
  if [[ -z "$token" ]]; then
    log_error "No authentication token. Please authenticate first."
    return 1
  fi

  local ca_cert
  ca_cert=$(provider_get_ca_cert)

  log_info "Exchanging WireGuard keys with $hostname..."

  local response
  if [[ -z "$dip_token" ]]; then
    response=$(curl -s --tlsv1.2 -G \
      --connect-to "$hostname::$server_ip:" \
      --cacert "$ca_cert" \
      --data-urlencode "pt=$token" \
      --data-urlencode "pubkey=$public_key" \
      "https://${hostname}:1337/addKey")
  else
    response=$(curl -s --tlsv1.2 -G \
      --connect-to "$hostname::$server_ip:" \
      --cacert "$ca_cert" \
      --user "dedicated_ip_$dip_token:$server_ip" \
      --data-urlencode "pubkey=$public_key" \
      "https://${hostname}:1337/addKey")
  fi

  # Validate response
  if ! validate_wg_response "$response"; then
    log_error "WireGuard key exchange failed"
    return 1
  fi

  echo "$response"
}

# ============================================================================
# PORT FORWARDING
# ============================================================================

provider_supports_pf() {
  return 0  # PIA supports port forwarding
}

# Get port forwarding signature
# Usage: provider_enable_pf "server_ip" "hostname"
provider_enable_pf() {
  local server_ip="$1"
  local hostname="$2"
  local wg_interface="${3:-}"

  local token
  token=$(read_token)
  if [[ -z "$token" ]]; then
    log_error "No authentication token"
    return 1
  fi

  local ca_cert
  ca_cert=$(provider_get_ca_cert)

  # Auto-detect WireGuard interface if not provided
  if [[ -z "$wg_interface" ]] && command -v os_detect_vpn_interface >/dev/null 2>&1; then
    wg_interface=$(os_detect_vpn_interface)
  fi

  log_info "Getting port forwarding signature..."

  local response
  if [[ -n "$wg_interface" ]]; then
    response=$(curl -s --tlsv1.2 -m 10 \
      --interface "$wg_interface" \
      --connect-to "$hostname::$server_ip:" \
      --cacert "$ca_cert" \
      -G --data-urlencode "token=$token" \
      "https://${hostname}:19999/getSignature")
  else
    response=$(curl -s --tlsv1.2 -m 10 \
      --connect-to "$hostname::$server_ip:" \
      --cacert "$ca_cert" \
      -G --data-urlencode "token=$token" \
      "https://${hostname}:19999/getSignature")
  fi

  # Validate response
  if [[ $(echo "$response" | jq -r '.status // empty') != "OK" ]]; then
    log_error "Failed to get port forwarding signature"
    return 1
  fi

  echo "$response"
}

# Bind/refresh port forwarding
# Usage: provider_refresh_pf "server_ip" "hostname" "payload" "signature"
provider_refresh_pf() {
  local server_ip="$1"
  local hostname="$2"
  local payload="$3"
  local signature="$4"
  local wg_interface="${5:-}"

  local ca_cert
  ca_cert=$(provider_get_ca_cert)

  # Auto-detect interface if not provided
  if [[ -z "$wg_interface" ]] && command -v os_detect_vpn_interface >/dev/null 2>&1; then
    wg_interface=$(os_detect_vpn_interface)
  fi

  local response
  if [[ -n "$wg_interface" ]]; then
    response=$(curl -s --tlsv1.2 -m 5 -G \
      --interface "$wg_interface" \
      --connect-to "$hostname::$server_ip:" \
      --cacert "$ca_cert" \
      --data-urlencode "payload=$payload" \
      --data-urlencode "signature=$signature" \
      "https://${hostname}:19999/bindPort")
  else
    response=$(curl -s --tlsv1.2 -m 5 -G \
      --connect-to "$hostname::$server_ip:" \
      --cacert "$ca_cert" \
      --data-urlencode "payload=$payload" \
      --data-urlencode "signature=$signature" \
      "https://${hostname}:19999/bindPort")
  fi

  if [[ $(echo "$response" | jq -r '.status // empty') != "OK" ]]; then
    log_error "Failed to bind port"
    return 1
  fi

  echo "$response"
}

# ============================================================================
# DEDICATED IP
# ============================================================================

provider_supports_dip() {
  return 0  # PIA supports dedicated IP
}

# Validate and get DIP info
# Usage: provider_get_dip "DIP_TOKEN"
provider_get_dip() {
  local dip_token="$1"

  log_info "Validating Dedicated IP token..."

  local response
  response=$(curl -s --tlsv1.2 \
    --data-urlencode "token=$dip_token" \
    "${PIA_API_BASE}/dedicated_ip")

  local status
  status=$(echo "$response" | jq -r '.status // empty')

  if [[ "$status" != "active" ]]; then
    local error
    error=$(echo "$response" | jq -r '.message // "Invalid or expired DIP token"')
    log_error "$error"
    return 1
  fi

  echo "$response"
}

# ============================================================================
# PROVIDER-SPECIFIC
# ============================================================================

provider_get_dns() {
  echo "10.0.0.243"
  echo "10.0.0.242"
}

provider_get_ca_cert() {
  echo "${VELUM_ROOT}/etc/providers/pia/ca.rsa.4096.crt"
}
