#!/usr/bin/env bash
# velum-security.sh - Security utilities for velum-vpn
# Provides: validation, credential cleanup, secure curl

# Prevent multiple sourcing
[[ -n "${_VELUM_SECURITY_LOADED:-}" ]] && return 0
readonly _VELUM_SECURITY_LOADED=1

# Source core if not already loaded
source "${BASH_SOURCE%/*}/velum-core.sh"

# ============================================================================
# SECURE CURL
# ============================================================================

# Curl wrapper that enforces TLS 1.2+ and uses provider CA cert
# Usage: secure_curl [curl options] URL
secure_curl() {
  local provider="${VELUM_PROVIDER:-pia}"
  local ca_cert="${VELUM_ROOT}/etc/providers/${provider}/ca.rsa.4096.crt"

  # Build base curl command with security flags
  local curl_args=(
    --tlsv1.2        # Enforce TLS 1.2 minimum
    -s               # Silent mode
  )

  # Add CA cert if exists
  if [[ -f "$ca_cert" ]]; then
    curl_args+=(--cacert "$ca_cert")
  fi

  # Execute with all arguments
  curl "${curl_args[@]}" "$@"
}

# ============================================================================
# INPUT VALIDATION
# ============================================================================

# Validate IPv4 address format
# Usage: validate_ipv4 "192.168.1.1" && echo "valid"
validate_ipv4() {
  local ip="$1"
  local octet="(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)"
  local regex="^${octet}\\.${octet}\\.${octet}\\.${octet}$"

  [[ "$ip" =~ $regex ]]
}

# Validate IPv4 with optional CIDR
# Usage: validate_ipv4_cidr "192.168.1.0/24" && echo "valid"
validate_ipv4_cidr() {
  local ip="$1"

  # Check if it has CIDR notation
  if [[ "$ip" == */* ]]; then
    local addr="${ip%/*}"
    local cidr="${ip#*/}"

    validate_ipv4 "$addr" || return 1
    [[ "$cidr" =~ ^[0-9]+$ ]] && [[ "$cidr" -ge 0 ]] && [[ "$cidr" -le 32 ]]
  else
    validate_ipv4 "$ip"
  fi
}

# Validate port number (1-65535)
# Usage: validate_port 443 && echo "valid"
validate_port() {
  local port="$1"

  [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 ]] && [[ "$port" -le 65535 ]]
}

# Validate WireGuard public key format (base64, 44 chars with = padding)
# Usage: validate_wg_key "key" && echo "valid"
validate_wg_key() {
  local key="$1"

  [[ "$key" =~ ^[A-Za-z0-9+/]{43}=$ ]]
}

# Validate PIA username format (p####### - starts with p, 7 digits)
# Usage: validate_pia_username "p1234567" && echo "valid"
validate_pia_username() {
  local username="$1"

  [[ "$username" =~ ^p[0-9]{7}$ ]]
}

# Validate DNS server (IPv4 address)
validate_dns() {
  validate_ipv4 "$1"
}

# ============================================================================
# API RESPONSE VALIDATION
# ============================================================================

# Validate WireGuard API response has required fields
# Usage: validate_wg_response "$json" || exit 1
validate_wg_response() {
  local json="$1"

  # Check status
  local status
  status=$(echo "$json" | jq -r '.status // empty')
  if [[ "$status" != "OK" ]]; then
    log_error "API did not return OK status"
    return 1
  fi

  # Extract required fields
  local peer_ip server_key server_port

  peer_ip=$(echo "$json" | jq -r '.peer_ip // empty')
  server_key=$(echo "$json" | jq -r '.server_key // empty')
  server_port=$(echo "$json" | jq -r '.server_port // empty')

  # Validate peer_ip
  if [[ -z "$peer_ip" ]]; then
    log_error "API response missing peer_ip"
    return 1
  fi
  if ! validate_ipv4_cidr "$peer_ip"; then
    log_error "Invalid peer_ip format: $peer_ip"
    return 1
  fi

  # Validate server_key
  if [[ -z "$server_key" ]]; then
    log_error "API response missing server_key"
    return 1
  fi
  if ! validate_wg_key "$server_key"; then
    log_error "Invalid server_key format"
    return 1
  fi

  # Validate server_port
  if [[ -z "$server_port" ]]; then
    log_error "API response missing server_port"
    return 1
  fi
  if ! validate_port "$server_port"; then
    log_error "Invalid server_port: $server_port"
    return 1
  fi

  return 0
}

# ============================================================================
# TOKEN MANAGEMENT
# ============================================================================

# Token file location (uses XDG config from velum-core.sh)
VELUM_TOKEN_FILE="${VELUM_TOKENS_DIR}/token"

# Check if token exists and is not expired
# Returns: 0 = valid, 1 = expired/missing, 2 = expiring soon
check_token_expiry() {
  local token_file="${1:-$VELUM_TOKEN_FILE}"

  if [[ ! -f "$token_file" ]]; then
    log_warn "Token file not found: $token_file"
    return 1
  fi

  local token_expiry
  token_expiry=$(sed -n '2p' "$token_file" 2>/dev/null)

  if [[ -z "$token_expiry" ]]; then
    log_warn "Token expiry not found in file"
    return 0  # Can't check, assume OK
  fi

  # Parse expiry date
  local expiry_epoch now_epoch
  if [[ "$(uname)" == "Darwin" ]]; then
    expiry_epoch=$(date -jf "%a %b %d %T %Z %Y" "$token_expiry" "+%s" 2>/dev/null || echo 0)
  else
    expiry_epoch=$(date -d "$token_expiry" "+%s" 2>/dev/null || echo 0)
  fi
  now_epoch=$(date "+%s")

  if [[ "$expiry_epoch" -gt 0 && "$now_epoch" -gt "$expiry_epoch" ]]; then
    log_error "Token has expired! ($token_expiry)"
    return 1
  fi

  # Warn if expiring within 2 hours
  if [[ "$expiry_epoch" -gt 0 ]]; then
    local hours_left=$(( (expiry_epoch - now_epoch) / 3600 ))
    if [[ "$hours_left" -lt 2 ]]; then
      log_warn "Token expires in less than 2 hours"
      return 2
    fi
  fi

  return 0
}

# Read token from file
read_token() {
  local token_file="${1:-$VELUM_TOKEN_FILE}"

  if [[ ! -f "$token_file" ]]; then
    return 1
  fi

  sed -n '1p' "$token_file" 2>/dev/null
}

# Save token to file with expiry
save_token() {
  local token="$1"
  local expiry="$2"
  local token_file="${3:-$VELUM_TOKEN_FILE}"

  # Initialize config directories (creates VELUM_TOKENS_DIR with proper perms)
  init_config_dirs

  # Write with restrictive permissions
  (
    umask 077
    printf '%s\n%s\n' "$token" "$expiry" > "$token_file"
  )
  chmod 600 "$token_file"

  # Fix ownership if running as root via sudo
  if [[ -n "${SUDO_USER:-}" ]]; then
    local sudo_uid sudo_gid
    sudo_uid=$(id -u "$SUDO_USER" 2>/dev/null)
    sudo_gid=$(id -g "$SUDO_USER" 2>/dev/null)
    if [[ -n "$sudo_uid" && -n "$sudo_gid" ]]; then
      chown "$sudo_uid:$sudo_gid" "$token_file"
    fi
  fi
}

# ============================================================================
# CREDENTIAL CLEANUP
# ============================================================================

# List of sensitive variables to clean up
_sensitive_vars=()

# Mark a variable for cleanup
mark_sensitive() {
  _sensitive_vars+=("$1")
}

# Clear all sensitive variables
cleanup_credentials() {
  local var
  # Check if array has elements before iterating (avoids unbound variable with set -u)
  if [[ ${#_sensitive_vars[@]} -gt 0 ]]; then
    for var in "${_sensitive_vars[@]}"; do
      unset "$var"
    done
  fi
  _sensitive_vars=()

  # Always clean these common ones
  unset PIA_USER PIA_PASS privKey wireguard_json
}

# Register cleanup on exit
register_cleanup cleanup_credentials

# ============================================================================
# FILE SECURITY
# ============================================================================

# Create file with secure permissions
# Usage: secure_write "/path/to/file" "content"
secure_write() {
  local path="$1"
  local content="$2"
  local mode="${3:-600}"
  local dir_mode="${4:-700}"

  # Create directory
  mkdir -p "$(dirname "$path")"
  chmod "$dir_mode" "$(dirname "$path")"

  # Write with restrictive umask
  (
    umask 077
    printf '%s' "$content" > "$path"
    chmod "$mode" "$path"
  )
}

# Check if file has secure permissions (not world-readable)
check_file_perms() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    return 1
  fi

  local perms
  if [[ "$(uname)" == "Darwin" ]]; then
    perms=$(stat -f "%Lp" "$path")
  else
    perms=$(stat -c "%a" "$path")
  fi

  # Check if world or group readable
  local other=$((perms % 10))
  local group=$(((perms / 10) % 10))

  [[ "$other" -eq 0 ]] && [[ "$group" -eq 0 ]]
}

# ============================================================================
# DEAD-MAN SWITCH
# ============================================================================

# Check if script contains insecure patterns
# Usage: security_check "$0" || exit 1
security_check() {
  local script="$1"

  # Check for insecure curl flags
  if grep -qE 'curl[^|]*(-k|--insecure)' "$script" 2>/dev/null; then
    print_error "SECURITY VIOLATION: Insecure curl flag detected in script."
    print_error "Refusing to run."
    return 1
  fi

  # Check for eval with variables (potential injection)
  if grep -qE 'eval\s+"\$' "$script" 2>/dev/null; then
    log_warn "Script uses eval with variables - potential injection risk"
  fi

  return 0
}
