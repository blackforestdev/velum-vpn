#!/usr/bin/env bash
# velum-credential.sh - Secure credential and token management
# Provides: tmpfs storage, session tokens, permission validation
#
# SECURITY DESIGN:
#   - Tokens stored in tmpfs (RAM) - cleared on reboot
#   - Account credentials NEVER stored to disk by default
#   - Users prompted for account ID when token refresh is needed
#   - Optional: encrypted vault or external credential command (Phase 3/4)

# Prevent multiple sourcing
[[ -n "${_VELUM_CREDENTIAL_LOADED:-}" ]] && return 0
readonly _VELUM_CREDENTIAL_LOADED=1

# Source core if not already loaded
source "${BASH_SOURCE%/*}/velum-core.sh"

# ============================================================================
# RUNTIME DIRECTORY (tmpfs)
# ============================================================================

# Get user-accessible tmpfs runtime directory for session tokens
# This is cleared on reboot - tokens don't survive restart
# Returns: path to velum runtime directory
_get_user_runtime_dir() {
  local runtime_dir=""
  local uid

  # Get effective user ID (handle sudo case)
  if [[ -n "${SUDO_USER:-}" ]] && _validate_username "$SUDO_USER"; then
    uid=$(id -u "$SUDO_USER" 2>/dev/null)
  else
    uid=$(id -u)
  fi

  # XDG_RUNTIME_DIR is typically /run/user/$UID (tmpfs on systemd systems)
  if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "${XDG_RUNTIME_DIR}" ]]; then
    runtime_dir="${XDG_RUNTIME_DIR}/velum"
  elif [[ -d "/run/user/${uid}" ]]; then
    runtime_dir="/run/user/${uid}/velum"
  else
    # No safe tmpfs available - fail closed for token storage
    log_error "No tmpfs runtime directory available (XDG_RUNTIME_DIR not set)."
    log_error "Refusing to store session tokens on disk."
    return 1
  fi

  echo "$runtime_dir"
}

# Exported runtime directory for tokens
VELUM_RUNTIME_DIR="$(_get_user_runtime_dir)"
export VELUM_RUNTIME_DIR

# Ensure runtime directory exists with secure permissions
# Usage: ensure_runtime_dir
ensure_runtime_dir() {
  # If runtime dir resolution failed, fail closed
  if [[ -z "${VELUM_RUNTIME_DIR:-}" ]]; then
    return 1
  fi

  if [[ ! -d "$VELUM_RUNTIME_DIR" ]]; then
    mkdir -p "$VELUM_RUNTIME_DIR" 2>/dev/null || {
      log_error "Cannot create runtime directory: $VELUM_RUNTIME_DIR"
      return 1
    }
  fi

  chmod 700 "$VELUM_RUNTIME_DIR"

  # Fix ownership if running as root via sudo
  if [[ -n "${SUDO_USER:-}" ]] && _validate_username "$SUDO_USER"; then
    local sudo_uid sudo_gid
    sudo_uid=$(id -u "$SUDO_USER" 2>/dev/null)
    sudo_gid=$(id -g "$SUDO_USER" 2>/dev/null)
    if [[ -n "$sudo_uid" && -n "$sudo_gid" ]]; then
      chown "$sudo_uid:$sudo_gid" "$VELUM_RUNTIME_DIR" 2>/dev/null || true
    fi
  fi

  return 0
}

# ============================================================================
# SESSION TOKEN STORAGE (tmpfs)
# ============================================================================

# Store a session token in tmpfs
# Usage: credential_store_token "provider" "token" ["expiry"]
credential_store_token() {
  local provider="$1"
  local token="$2"
  local expiry="${3:-}"

  ensure_runtime_dir || return 1

  local token_file="${VELUM_RUNTIME_DIR}/${provider}_token"

  # Write with restrictive permissions
  (
    umask 077
    printf '%s\n%s\n' "$token" "$expiry" > "$token_file"
  )
  chmod 600 "$token_file"

  # Fix ownership if running as root via sudo
  if [[ -n "${SUDO_USER:-}" ]] && _validate_username "$SUDO_USER"; then
    local sudo_uid sudo_gid
    sudo_uid=$(id -u "$SUDO_USER" 2>/dev/null)
    sudo_gid=$(id -g "$SUDO_USER" 2>/dev/null)
    if [[ -n "$sudo_uid" && -n "$sudo_gid" ]]; then
      chown "$sudo_uid:$sudo_gid" "$token_file" 2>/dev/null || true
    fi
  fi

  log_debug "Session token stored: $token_file"
  return 0
}

# Retrieve a session token from tmpfs
# Usage: token=$(credential_get_token "provider")
# Returns: token on stdout, or empty if not found/expired
credential_get_token() {
  local provider="$1"
  local token_file="${VELUM_RUNTIME_DIR}/${provider}_token"

  if [[ ! -f "$token_file" ]]; then
    return 1
  fi

  # Check file security before reading (permissions + ownership)
  if ! check_file_security "$token_file" "error"; then
    log_error "Token file has insecure permissions: $token_file"
    return 1
  fi

  sed -n '1p' "$token_file" 2>/dev/null
}

# Get token expiry from tmpfs storage
# Usage: expiry=$(credential_get_token_expiry "provider")
credential_get_token_expiry() {
  local provider="$1"
  local token_file="${VELUM_RUNTIME_DIR}/${provider}_token"

  if [[ ! -f "$token_file" ]]; then
    return 1
  fi

  sed -n '2p' "$token_file" 2>/dev/null
}

# Check if token exists and is not expired
# Returns: 0 = valid, 1 = missing/expired, 2 = expiring soon
credential_check_token() {
  local provider="$1"
  local token_file="${VELUM_RUNTIME_DIR}/${provider}_token"

  if [[ ! -f "$token_file" ]]; then
    return 1
  fi

  # Validate file security before reading
  if ! check_file_security "$token_file" "error"; then
    log_error "Token file has insecure permissions: $token_file"
    return 1
  fi

  local token_expiry
  token_expiry=$(sed -n '2p' "$token_file" 2>/dev/null)

  if [[ -z "$token_expiry" || "$token_expiry" == "unknown" ]]; then
    return 0  # Can't check, assume OK
  fi

  # Parse expiry as epoch seconds
  local expiry_epoch now_epoch
  if [[ "$token_expiry" =~ ^[0-9]+$ ]]; then
    expiry_epoch="$token_expiry"
  else
    # Legacy format - attempt parse and rewrite
    if [[ "$(uname)" == "Darwin" ]]; then
      expiry_epoch=$(date -jf "%Y-%m-%dT%H:%M:%S%z" "$token_expiry" "+%s" 2>/dev/null || \
                     date -jf "%a %b %d %T %Z %Y" "$token_expiry" "+%s" 2>/dev/null || echo 0)
    else
      expiry_epoch=$(date -d "$token_expiry" "+%s" 2>/dev/null || echo 0)
    fi
    # Rewrite to epoch if parse succeeded
    if [[ "$expiry_epoch" -gt 0 ]]; then
      sed -i.bak "2s/.*/$expiry_epoch/" "$token_file" 2>/dev/null || true
      rm -f "${token_file}.bak" 2>/dev/null || true
    fi
  fi
  now_epoch=$(date "+%s")

  if [[ "$expiry_epoch" -gt 0 && "$now_epoch" -gt "$expiry_epoch" ]]; then
    log_warn "Token has expired ($token_expiry)"
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

# Clear a provider's session token
# Usage: credential_clear_token "provider"
credential_clear_token() {
  local provider="$1"
  local token_file="${VELUM_RUNTIME_DIR}/${provider}_token"

  if [[ -f "$token_file" ]]; then
    # Overwrite before delete for extra safety
    dd if=/dev/urandom of="$token_file" bs=64 count=1 2>/dev/null || true
    rm -f "$token_file"
    log_debug "Token cleared: $token_file"
  fi
}

# Clear all session tokens
# Usage: credential_clear_all_tokens
credential_clear_all_tokens() {
  if [[ -d "$VELUM_RUNTIME_DIR" ]]; then
    find "$VELUM_RUNTIME_DIR" -name '*_token' -type f -exec rm -f {} \; 2>/dev/null
    log_debug "All session tokens cleared"
  fi
}

# ============================================================================
# PERMISSION VALIDATION
# ============================================================================

# Check if a file has secure permissions (not world/group readable)
# Usage: _check_token_file_security "/path/to/file"
# Returns: 0 = secure, 1 = insecure
_check_token_file_security() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    return 0  # Non-existent files are "secure"
  fi

  local perms
  if [[ "$(uname)" == "Darwin" ]]; then
    perms=$(stat -f "%Lp" "$file" 2>/dev/null)
  else
    perms=$(stat -c "%a" "$file" 2>/dev/null)
  fi

  # Only owner should have access (600, 400, 700, 500)
  local other=$((perms % 10))
  local group=$(((perms / 10) % 10))

  if [[ "$other" -ne 0 ]] || [[ "$group" -ne 0 ]]; then
    return 1
  fi

  return 0
}

# Check file ownership
# Usage: _check_file_owner "/path/to/file"
# Returns: 0 = owned by current/sudo user, 1 = wrong owner
_check_file_owner() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  local owner expected_owner
  if [[ "$(uname)" == "Darwin" ]]; then
    owner=$(stat -f "%Su" "$file" 2>/dev/null)
  else
    owner=$(stat -c "%U" "$file" 2>/dev/null)
  fi

  expected_owner="${SUDO_USER:-$USER}"

  # Allow root ownership too
  if [[ "$owner" != "$expected_owner" && "$owner" != "root" ]]; then
    return 1
  fi

  return 0
}

# Comprehensive file security check
# Usage: check_file_security "/path/to/file" ["warn"|"error"]
# Returns: 0 = secure, 1 = insecure
# Second param: "warn" = log warning, "error" = log error (default: error)
check_file_security() {
  local file="$1"
  local severity="${2:-error}"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  local issues=()

  # Check permissions
  if ! _check_token_file_security "$file"; then
    issues+=("insecure permissions (world/group readable)")
  fi

  # Check ownership
  if ! _check_file_owner "$file"; then
    local owner
    if [[ "$(uname)" == "Darwin" ]]; then
      owner=$(stat -f "%Su" "$file" 2>/dev/null)
    else
      owner=$(stat -c "%U" "$file" 2>/dev/null)
    fi
    issues+=("unexpected owner: $owner")
  fi

  if [[ ${#issues[@]} -gt 0 ]]; then
    local msg="File security issue: $file - ${issues[*]}"
    if [[ "$severity" == "warn" ]]; then
      log_warn "$msg"
    else
      log_error "$msg"
    fi
    return 1
  fi

  return 0
}

# ============================================================================
# PLAINTEXT MIGRATION / CLEANUP
# ============================================================================

# Securely delete a file (overwrite then remove)
# Usage: secure_delete "/path/to/file"
secure_delete() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  # Get file size
  local size
  if [[ "$(uname)" == "Darwin" ]]; then
    size=$(stat -f "%z" "$file" 2>/dev/null || echo 64)
  else
    size=$(stat -c "%s" "$file" 2>/dev/null || echo 64)
  fi

  # Overwrite with random data (3 passes)
  if [[ "$size" -le 0 ]]; then
    size=64
  fi
  for _ in 1 2 3; do
    dd if=/dev/urandom of="$file" bs="$size" count=1 2>/dev/null || true
    sync 2>/dev/null || true
  done

  rm -f "$file"
}

# Check for and remove legacy plaintext account files
# Usage: migrate_plaintext_credentials
# Returns: 0 always (to not break set -e scripts)
migrate_plaintext_credentials() {
  local config_dir="${VELUM_CONFIG_DIR:-$HOME/.config/velum}"
  local tokens_dir="${VELUM_TOKENS_DIR:-$config_dir/tokens}"
  local found_files=()
  local seen_paths=""

  # Look for plaintext account files in tokens directory
  # Use a single location to avoid duplicates
  local account_files=(
    "${tokens_dir}/mullvad_account"
    "${tokens_dir}/ivpn_account"
    "${tokens_dir}/pia_account"
  )

  for file in "${account_files[@]}"; do
    if [[ -f "$file" ]]; then
      # Resolve to absolute path for deduplication
      local abs_path
      abs_path=$(cd "$(dirname "$file")" && pwd)/$(basename "$file")

      # Skip if we've already seen this path
      if [[ "$seen_paths" == *"|${abs_path}|"* ]]; then
        continue
      fi
      seen_paths="${seen_paths}|${abs_path}|"
      found_files+=("$file")
    fi
  done

  if [[ ${#found_files[@]} -eq 0 ]]; then
    return 0
  fi

  print_warn "Found ${#found_files[@]} plaintext credential file(s):"
  for file in "${found_files[@]}"; do
    echo "  - $file"
  done
  echo

  print_warn "Plaintext account storage is a security risk."
  print_warn "These files should be securely deleted."
  echo

  if ask_yn "Securely delete these files now?" "y"; then
    for file in "${found_files[@]}"; do
      echo -n "  Deleting $file... "
      secure_delete "$file"
      echo "done"
    done
    print_ok "Plaintext credentials removed."
    echo
    print_info "You will be prompted for your account ID when token refresh is needed."
  else
    print_warn "Leaving plaintext files in place. This is NOT recommended."
  fi

  return 0  # Always return 0 to not break set -e
}

# ============================================================================
# BACKWARD COMPATIBILITY
# ============================================================================

# Check for tokens in legacy location and migrate to tmpfs
# This handles the transition from ~/.config/velum/tokens to /run/user/$UID/velum
migrate_tokens_to_runtime() {
  local legacy_tokens_dir="${VELUM_TOKENS_DIR:-$HOME/.config/velum/tokens}"

  # Look for token files (not account files)
  for provider in mullvad ivpn pia; do
    local legacy_token="${legacy_tokens_dir}/${provider}_token"

    if [[ -f "$legacy_token" ]]; then
      log_info "Migrating $provider token to runtime storage..."

      # Check security before reading
      if ! check_file_security "$legacy_token" "warn"; then
        log_warn "Skipping insecure token file: $legacy_token"
        continue
      fi

      local token expiry
      token=$(sed -n '1p' "$legacy_token" 2>/dev/null)
      expiry=$(sed -n '2p' "$legacy_token" 2>/dev/null)

      if [[ -n "$token" ]]; then
        credential_store_token "$provider" "$token" "$expiry"
        secure_delete "$legacy_token"
        log_info "$provider token migrated to tmpfs"
      fi
    fi
  done
}

# ============================================================================
# CLEANUP REGISTRATION
# ============================================================================

# Register cleanup on disconnect
_credential_cleanup() {
  # Clear all session tokens on script exit
  # Note: In normal operation, tokens persist until reboot (tmpfs)
  # This cleanup is for abnormal exits or explicit disconnect
  : # No-op by default; tokens cleared on reboot or explicit logout
}

# Note: We don't auto-clear tokens on script exit since the user may want
# to reconnect. Tokens are only cleared:
# 1. On system reboot (tmpfs is cleared)
# 2. On explicit logout (credential_clear_token)
# 3. On disconnect if configured (future: credential_source=prompt)
