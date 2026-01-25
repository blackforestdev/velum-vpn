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

# Validate killswitch LAN policy
# Allowed values: "detect", "block", or a valid CIDR (e.g., "192.168.1.0/24")
# Usage: validate_killswitch_lan "detect" && echo "valid"
validate_killswitch_lan() {
  local policy="$1"

  # Allow special keywords
  case "$policy" in
    detect|block)
      return 0
      ;;
  esac

  # Otherwise must be a valid CIDR
  validate_ipv4_cidr "$policy"
}

# ============================================================================
# SAFE CONFIG PARSING
# ============================================================================

# Known valid config keys (keep in sync with velum-config save_config)
readonly VELUM_KNOWN_CONFIG_KEYS=(
  "provider"
  "killswitch"
  "killswitch_lan"
  "ipv6_disabled"
  "use_provider_dns"
  "dip_enabled"
  "dip_token"
  "port_forward"
  "allow_geo"
  "server_auto"
  "max_latency"
  "selected_region"
  "selected_ip"
  "selected_hostname"
)

# Check if a key is in the known keys list
_is_known_key() {
  local key="$1"
  local k
  for k in "${VELUM_KNOWN_CONFIG_KEYS[@]}"; do
    [[ "$k" == "$key" ]] && return 0
  done
  return 1
}

# Safely load velum config file without using source
# Parses CONFIG[key]="value" lines and populates the CONFIG associative array
# Validates values per-key type and fails on invalid values
#
# Usage: safe_load_config "/path/to/velum.conf" [options]
# Options:
#   --strict          Error on lines that don't match CONFIG[key]="value"
#   --known-keys-only Error on unknown keys not in VELUM_KNOWN_CONFIG_KEYS
#   --lint            Lint mode: collect all errors/warnings, don't populate CONFIG
#
# Returns: 0 = OK, 1 = errors, 2 = warnings only (lint mode)
# Requires: declare -A CONFIG before calling (except in lint mode)
safe_load_config() {
  local config_file=""
  local strict=false
  local known_keys_only=false
  local lint_mode=false

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --strict) strict=true ;;
      --known-keys-only) known_keys_only=true ;;
      --lint) lint_mode=true; strict=true; known_keys_only=true ;;
      -*) log_error "Unknown option: $1"; return 1 ;;
      *) config_file="$1" ;;
    esac
    shift
  done

  if [[ -z "$config_file" ]]; then
    log_error "No config file specified"
    return 1
  fi

  if [[ ! -f "$config_file" ]]; then
    [[ "$lint_mode" == true ]] && echo "ERROR: Config file not found: $config_file"
    return 1
  fi

  local line_num=0
  local errors=0
  local warnings=0

  # Read config file line by line, extracting CONFIG[key]="value" patterns
  while IFS= read -r line || [[ -n "$line" ]]; do
    ((++line_num))  # Use prefix increment to avoid exit code 1 when line_num=0

    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue

    # Match CONFIG[key]="value" pattern (value cannot contain unescaped quotes)
    if [[ "$line" =~ ^CONFIG\[([a-zA-Z_][a-zA-Z0-9_]*)\]=\"([^\"]*)\"$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"

      # Check if key is known (when strict)
      if [[ "$known_keys_only" == true ]] && ! _is_known_key "$key"; then
        if [[ "$lint_mode" == true ]]; then
          echo "WARNING: Unknown config key '$key' (line $line_num)"
          ((warnings++))
        else
          log_warn "Unknown config key '$key' (line $line_num)"
        fi
        # Continue processing - unknown keys are warnings, not errors
      fi

      # Validate value based on key type
      local validation_error=""
      case "$key" in
        # Boolean keys: must be "true" or "false"
        killswitch|ipv6_disabled|use_provider_dns|port_forward|dip_enabled|server_auto|allow_geo)
          if [[ "$value" != "true" && "$value" != "false" ]]; then
            validation_error="Invalid boolean value for $key: '$value'"
          fi
          ;;
        # LAN policy: detect, block, or CIDR
        killswitch_lan)
          if ! validate_killswitch_lan "$value"; then
            validation_error="Invalid killswitch_lan value: '$value' (must be detect, block, or CIDR)"
          fi
          ;;
        # Provider: must be alphanumeric/underscore only
        provider)
          if [[ ! "$value" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            validation_error="Invalid provider value: '$value'"
          fi
          ;;
        # IP addresses
        selected_ip)
          if [[ -n "$value" ]] && ! validate_ipv4 "$value"; then
            validation_error="Invalid IP address for $key: '$value'"
          fi
          ;;
        # Numeric values (latency threshold)
        max_latency)
          if [[ -n "$value" ]] && ! [[ "$value" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            validation_error="Invalid numeric value for $key: '$value'"
          fi
          ;;
        # Tokens (dip_token, etc): allow base64 charset (alphanumeric, +, /, =)
        dip_token|*_token)
          if [[ -n "$value" ]] && ! [[ "$value" =~ ^[A-Za-z0-9+/=_-]+$ ]]; then
            validation_error="Invalid token format for $key"
          fi
          ;;
        # String values (region, hostname): alphanumeric, dots, hyphens, underscores
        selected_region|selected_hostname)
          if [[ -n "$value" ]] && ! [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]]; then
            validation_error="Invalid string value for $key: '$value'"
          fi
          ;;
        # Default: allow safe characters (no shell metacharacters)
        *)
          if [[ "$value" =~ [\'\"\`\$\(\)\;\&\|\<\>\!] ]]; then
            validation_error="Invalid characters in $key value (shell metacharacters not allowed)"
          fi
          ;;
      esac

      if [[ -n "$validation_error" ]]; then
        if [[ "$lint_mode" == true ]]; then
          echo "ERROR: $validation_error (line $line_num)"
          ((errors++))
        else
          log_error "$validation_error (line $line_num)"
          return 1
        fi
      elif [[ "$lint_mode" != true ]]; then
        CONFIG["$key"]="$value"
      fi
    else
      # Line doesn't match CONFIG pattern
      if [[ "$strict" == true ]]; then
        if [[ "$lint_mode" == true ]]; then
          echo "ERROR: Unrecognized line format (line $line_num): $line"
          ((errors++))
        else
          log_error "Unrecognized line format (line $line_num): $line"
          return 1
        fi
      fi
    fi
  done < "$config_file"

  # Lint mode summary
  if [[ "$lint_mode" == true ]]; then
    echo ""
    if [[ $errors -gt 0 ]]; then
      echo "Lint result: $errors error(s), $warnings warning(s)"
      return 1
    elif [[ $warnings -gt 0 ]]; then
      echo "Lint result: $warnings warning(s)"
      return 2
    else
      echo "Lint result: OK"
      return 0
    fi
  fi

  return 0
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
