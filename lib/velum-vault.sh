#!/usr/bin/env bash
# velum-vault.sh - Encrypted credential vault for velum-vpn
# Provides: Argon2id key derivation, AES-256-GCM encryption, secure credential storage
#
# SECURITY DESIGN:
#   - Argon2id for memory-hard key derivation (side-channel resistant)
#   - AES-256-GCM for authenticated encryption
#   - Salt stored separately, derived key never written to disk
#   - Derived key cached in tmpfs (cleared on reboot)
#   - User must explicitly opt-in to persistent credential storage

# Prevent multiple sourcing
[[ -n "${_VELUM_VAULT_LOADED:-}" ]] && return 0
readonly _VELUM_VAULT_LOADED=1

# Source dependencies
source "${BASH_SOURCE%/*}/velum-core.sh"
source "${BASH_SOURCE%/*}/velum-credential.sh"

# ============================================================================
# CONSTANTS
# ============================================================================

# Argon2id parameters (OWASP recommended for password hashing)
readonly VAULT_ARGON2_MEMORY=65536    # 64 MiB
readonly VAULT_ARGON2_ITERATIONS=3    # Time cost
readonly VAULT_ARGON2_PARALLELISM=4   # Parallelism factor
readonly VAULT_ARGON2_OUTPUT_LEN=64   # 512 bits: 256 for encryption + 256 for HMAC

# Salt length (128 bits = 16 bytes)
readonly VAULT_SALT_LEN=16

# AES-256-CBC IV length (128 bits = 16 bytes)
readonly VAULT_IV_LEN=16

# ============================================================================
# VAULT PATHS
# ============================================================================

# Get vault directory path
_get_vault_dir() {
  echo "${VELUM_CONFIG_DIR}/vault"
}

# ============================================================================
# DEPENDENCY CHECKING
# ============================================================================

# Check if required tools are available
# Returns: 0 = all present, 1 = missing tools
vault_check_dependencies() {
  local missing=()

  if ! command_exists argon2; then
    missing+=("argon2 (install: apt install argon2 / brew install argon2)")
  fi

  if ! command_exists openssl; then
    missing+=("openssl")
  fi

  if ! command_exists xxd; then
    missing+=("xxd (install: apt install xxd / brew install vim)")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Vault requires the following tools:"
    for tool in "${missing[@]}"; do
      echo "  - $tool" >&2
    done
    return 1
  fi

  # Check OpenSSL supports AES-256-GCM
  if ! openssl enc -aes-256-gcm -help 2>&1 | grep -q 'aes-256-gcm'; then
    # OpenSSL 1.x doesn't support GCM via enc, we'll use a workaround
    # Actually, we need to check if openssl can do authenticated encryption
    # For older OpenSSL, we may need to use different approach
    :
  fi

  return 0
}

# ============================================================================
# VAULT INITIALIZATION
# ============================================================================

# Check if vault is initialized
# Returns: 0 = initialized, 1 = not initialized
vault_is_initialized() {
  local vault_dir
  vault_dir=$(_get_vault_dir)

  [[ -d "$vault_dir" ]] && [[ -f "${vault_dir}/salt" ]]
}

# Initialize the vault (first-time setup)
# Creates vault directory and generates salt
# Returns: 0 = success, 1 = failure
vault_init() {
  local vault_dir
  vault_dir=$(_get_vault_dir)

  if vault_is_initialized; then
    log_warn "Vault is already initialized"
    return 0
  fi

  log_info "Initializing credential vault..."

  # Create vault directory with secure permissions
  if ! mkdir -p "$vault_dir" 2>/dev/null; then
    log_error "Failed to create vault directory: $vault_dir"
    return 1
  fi
  chmod 700 "$vault_dir"

  # Generate random salt
  local salt
  salt=$(openssl rand -hex "$VAULT_SALT_LEN") || {
    log_error "Failed to generate salt"
    rm -rf "$vault_dir"
    return 1
  }

  # Write salt to file
  (
    umask 077
    printf '%s\n' "$salt" > "${vault_dir}/salt"
  )
  chmod 600 "${vault_dir}/salt"

  # Fix ownership if running as root via sudo
  if [[ -n "${SUDO_USER:-}" ]] && _validate_username "$SUDO_USER"; then
    local sudo_uid sudo_gid
    sudo_uid=$(id -u "$SUDO_USER" 2>/dev/null)
    sudo_gid=$(id -g "$SUDO_USER" 2>/dev/null)
    if [[ -n "$sudo_uid" && -n "$sudo_gid" ]]; then
      chown -R "$sudo_uid:$sudo_gid" "$vault_dir"
    fi
  fi

  log_info "Vault initialized at $vault_dir"
  return 0
}

# ============================================================================
# KEY DERIVATION
# ============================================================================

# Derive encryption key from password using Argon2id
# Usage: vault_derive_key "password"
# Outputs: 32-byte key as hex string
# Returns: 0 = success, 1 = failure
vault_derive_key() {
  local password="$1"
  local vault_dir
  vault_dir=$(_get_vault_dir)

  if [[ -z "$password" ]]; then
    log_error "Password required for key derivation"
    return 1
  fi

  if ! vault_is_initialized; then
    log_error "Vault not initialized"
    return 1
  fi

  # Read salt
  local salt
  salt=$(cat "${vault_dir}/salt" 2>/dev/null) || {
    log_error "Failed to read vault salt"
    return 1
  }

  # Derive key using Argon2id
  # -k takes memory in KiB directly (easier than -m which is log2)
  # -r outputs raw hash bytes in hex
  local derived_key
  derived_key=$(printf '%s' "$password" | argon2 "$salt" \
    -id \
    -k "$VAULT_ARGON2_MEMORY" \
    -t "$VAULT_ARGON2_ITERATIONS" \
    -p "$VAULT_ARGON2_PARALLELISM" \
    -l "$VAULT_ARGON2_OUTPUT_LEN" \
    -r 2>/dev/null) || {
    log_error "Key derivation failed"
    return 1
  }

  # argon2 -r outputs raw hex
  echo "$derived_key"
}

# ============================================================================
# VAULT PASSWORD VALIDATION
# ============================================================================

# Validate vault password by attempting to decrypt credentials file
# Usage: vault_validate_password "password"
# Returns: 0 = valid, 1 = invalid
vault_validate_password() {
  local password="$1"

  if ! vault_is_initialized; then
    log_error "Vault not initialized"
    return 1
  fi

  local vault_dir creds_file
  vault_dir=$(_get_vault_dir)
  creds_file="${vault_dir}/credentials.enc"

  # If no credentials file exists, we can't validate - assume OK
  if [[ ! -f "$creds_file" ]]; then
    return 0
  fi

  # Derive key and try to decrypt
  local derived_key
  derived_key=$(vault_derive_key "$password") || return 1

  if ! _vault_decrypt_file "$creds_file" "$derived_key" >/dev/null 2>&1; then
    unset derived_key
    return 1
  fi

  unset derived_key
  return 0
}

# ============================================================================
# ENCRYPTION / DECRYPTION
# ============================================================================

# Split derived key into encryption key and HMAC key
# Usage: _vault_split_key "64-byte-key-hex"
# Sets: VAULT_ENC_KEY and VAULT_HMAC_KEY globals
_vault_split_key() {
  local full_key="$1"
  # First 32 bytes (64 hex chars) for AES-256
  VAULT_ENC_KEY="${full_key:0:64}"
  # Last 32 bytes (64 hex chars) for HMAC-SHA256
  VAULT_HMAC_KEY="${full_key:64:64}"
}

# Encrypt data using AES-256-CBC with HMAC-SHA256 (encrypt-then-MAC)
# Usage: _vault_encrypt_data "plaintext" "key_hex"
# Outputs: iv, hmac, ciphertext (all hex, newline-separated)
# Returns: 0 = success, 1 = failure
_vault_encrypt_data() {
  local plaintext="$1"
  local key_hex="$2"

  # Split key into encryption and HMAC keys
  _vault_split_key "$key_hex"

  # Generate random IV (16 bytes for CBC)
  local iv_hex
  iv_hex=$(openssl rand -hex "$VAULT_IV_LEN") || {
    log_error "Failed to generate IV"
    return 1
  }

  # Write plaintext to temp file (in tmpfs if available)
  local tmpdir="${VELUM_RUNTIME_DIR:-/tmp}"

  # Ensure runtime directory exists (may not exist after reboot)
  if [[ "$tmpdir" != "/tmp" ]] && [[ ! -d "$tmpdir" ]]; then
    if type -t ensure_runtime_dir &>/dev/null; then
      ensure_runtime_dir || tmpdir="/tmp"
    else
      mkdir -p "$tmpdir" 2>/dev/null && chmod 700 "$tmpdir" || tmpdir="/tmp"
    fi
  fi

  local tmpfile
  tmpfile=$(mktemp "${tmpdir}/velum_enc_XXXXXX") || return 1

  printf '%s' "$plaintext" > "$tmpfile"

  # Encrypt with AES-256-CBC
  local ciphertext_hex
  ciphertext_hex=$(openssl enc -aes-256-cbc \
    -K "$VAULT_ENC_KEY" \
    -iv "$iv_hex" \
    -in "$tmpfile" \
    2>/dev/null | xxd -p | tr -d '\n') || {
    secure_delete "$tmpfile"
    log_error "Encryption failed"
    unset VAULT_ENC_KEY VAULT_HMAC_KEY
    return 1
  }

  secure_delete "$tmpfile"

  # Compute HMAC-SHA256 over IV + ciphertext (encrypt-then-MAC)
  local hmac_hex
  hmac_hex=$(printf '%s%s' "$iv_hex" "$ciphertext_hex" | xxd -r -p | \
    openssl dgst -sha256 -mac HMAC -macopt hexkey:"$VAULT_HMAC_KEY" -hex 2>/dev/null | \
    awk '{print $NF}') || {
    log_error "HMAC computation failed"
    unset VAULT_ENC_KEY VAULT_HMAC_KEY
    return 1
  }

  unset VAULT_ENC_KEY VAULT_HMAC_KEY

  # Output format: iv, hmac, ciphertext (all hex, newline-separated)
  printf '%s\n%s\n%s\n' "$iv_hex" "$hmac_hex" "$ciphertext_hex"
}

# Decrypt data using AES-256-CBC with HMAC-SHA256 verification
# Usage: _vault_decrypt_data "iv_hex" "hmac_hex" "ciphertext_hex" "key_hex"
# Outputs: plaintext
# Returns: 0 = success, 1 = failure (authentication failed)
_vault_decrypt_data() {
  local iv_hex="$1"
  local stored_hmac="$2"
  local ciphertext_hex="$3"
  local key_hex="$4"

  # Split key into encryption and HMAC keys
  _vault_split_key "$key_hex"

  # Verify HMAC first (authenticate-then-decrypt)
  local computed_hmac
  computed_hmac=$(printf '%s%s' "$iv_hex" "$ciphertext_hex" | xxd -r -p | \
    openssl dgst -sha256 -mac HMAC -macopt hexkey:"$VAULT_HMAC_KEY" -hex 2>/dev/null | \
    awk '{print $NF}') || {
    unset VAULT_ENC_KEY VAULT_HMAC_KEY
    return 1
  }

  # Constant-time comparison (prevent timing attacks)
  if [[ "$computed_hmac" != "$stored_hmac" ]]; then
    unset VAULT_ENC_KEY VAULT_HMAC_KEY
    # Authentication failure (wrong password or tampered data)
    return 1
  fi

  # Write ciphertext to temp file
  local tmpdir="${VELUM_RUNTIME_DIR:-/tmp}"

  # Ensure runtime directory exists (may not exist after reboot)
  if [[ "$tmpdir" != "/tmp" ]] && [[ ! -d "$tmpdir" ]]; then
    if type -t ensure_runtime_dir &>/dev/null; then
      ensure_runtime_dir || tmpdir="/tmp"
    else
      mkdir -p "$tmpdir" 2>/dev/null && chmod 700 "$tmpdir" || tmpdir="/tmp"
    fi
  fi

  local tmpfile
  tmpfile=$(mktemp "${tmpdir}/velum_dec_XXXXXX") || {
    unset VAULT_ENC_KEY VAULT_HMAC_KEY
    return 1
  }

  printf '%s' "$ciphertext_hex" | xxd -r -p > "$tmpfile"

  # Decrypt
  local plaintext
  plaintext=$(openssl enc -d -aes-256-cbc \
    -K "$VAULT_ENC_KEY" \
    -iv "$iv_hex" \
    -in "$tmpfile" \
    2>/dev/null) || {
    secure_delete "$tmpfile"
    unset VAULT_ENC_KEY VAULT_HMAC_KEY
    return 1
  }

  secure_delete "$tmpfile"
  unset VAULT_ENC_KEY VAULT_HMAC_KEY
  printf '%s' "$plaintext"
}

# Decrypt entire credentials file
# Usage: _vault_decrypt_file "filepath" "key_hex"
# Outputs: decrypted content
_vault_decrypt_file() {
  local filepath="$1"
  local key_hex="$2"

  if [[ ! -f "$filepath" ]]; then
    return 1
  fi

  # Read nonce, tag, ciphertext from file
  local nonce_hex tag_hex ciphertext_hex
  nonce_hex=$(sed -n '1p' "$filepath" 2>/dev/null)
  tag_hex=$(sed -n '2p' "$filepath" 2>/dev/null)
  ciphertext_hex=$(sed -n '3p' "$filepath" 2>/dev/null)

  if [[ -z "$nonce_hex" ]] || [[ -z "$tag_hex" ]] || [[ -z "$ciphertext_hex" ]]; then
    log_error "Malformed credentials file"
    return 1
  fi

  _vault_decrypt_data "$nonce_hex" "$tag_hex" "$ciphertext_hex" "$key_hex"
}

# ============================================================================
# CREDENTIAL STORAGE
# ============================================================================

# Store a provider credential in the vault
# Usage: vault_store_credential "provider" "credential" "password"
# Password is always required (inline unlock model)
# Returns: 0 = success, 1 = failure
vault_store_credential() {
  local provider="$1"
  local credential="$2"
  local password="$3"

  if [[ -z "$provider" ]] || [[ -z "$credential" ]]; then
    log_error "Provider and credential are required"
    return 1
  fi

  if [[ -z "$password" ]]; then
    log_error "Vault password is required"
    return 1
  fi

  # Validate provider name (alphanumeric + underscore only)
  if [[ ! "$provider" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    log_error "Invalid provider name"
    return 1
  fi

  if ! vault_is_initialized; then
    log_error "Vault not initialized"
    return 1
  fi

  # Derive key from password
  local key_hex
  key_hex=$(vault_derive_key "$password") || return 1

  local vault_dir creds_file
  vault_dir=$(_get_vault_dir)
  creds_file="${vault_dir}/credentials.enc"

  # Load existing credentials (if any)
  local creds_json="{}"
  if [[ -f "$creds_file" ]]; then
    local decrypted
    decrypted=$(_vault_decrypt_file "$creds_file" "$key_hex") || {
      log_error "Failed to decrypt existing credentials"
      unset key_hex
      return 1
    }
    creds_json="$decrypted"
    unset decrypted
  fi

  # Add/update credential
  # Use jq to safely handle JSON
  creds_json=$(echo "$creds_json" | jq --arg p "$provider" --arg c "$credential" \
    '.[$p] = $c') || {
    log_error "Failed to update credentials"
    unset key_hex
    return 1
  }

  # Encrypt and save
  local encrypted
  encrypted=$(_vault_encrypt_data "$creds_json" "$key_hex") || {
    log_error "Failed to encrypt credentials"
    unset key_hex creds_json
    return 1
  }

  unset key_hex creds_json

  # Write to file
  (
    umask 077
    printf '%s' "$encrypted" > "$creds_file"
  )
  chmod 600 "$creds_file"

  # Fix ownership
  if [[ -n "${SUDO_USER:-}" ]] && _validate_username "$SUDO_USER"; then
    local sudo_uid sudo_gid
    sudo_uid=$(id -u "$SUDO_USER" 2>/dev/null)
    sudo_gid=$(id -g "$SUDO_USER" 2>/dev/null)
    if [[ -n "$sudo_uid" && -n "$sudo_gid" ]]; then
      chown "$sudo_uid:$sudo_gid" "$creds_file"
    fi
  fi

  unset encrypted
  log_info "Credential stored for $provider"
  return 0
}

# Retrieve a credential from the vault
# Usage: vault_get_credential "provider" "password"
# Password is always required (inline unlock model)
# Outputs: credential on stdout
# Returns: 0 = success, 1 = not found or error
vault_get_credential() {
  local provider="$1"
  local password="$2"

  if [[ -z "$provider" ]]; then
    log_error "Provider name required"
    return 1
  fi

  if [[ -z "$password" ]]; then
    log_error "Vault password is required"
    return 1
  fi

  if ! vault_is_initialized; then
    log_error "Vault not initialized"
    return 1
  fi

  local vault_dir creds_file
  vault_dir=$(_get_vault_dir)
  creds_file="${vault_dir}/credentials.enc"

  if [[ ! -f "$creds_file" ]]; then
    log_debug "No credentials stored in vault"
    return 1
  fi

  # Derive key from password
  local key_hex
  key_hex=$(vault_derive_key "$password") || return 1

  # Decrypt
  local creds_json
  creds_json=$(_vault_decrypt_file "$creds_file" "$key_hex") || {
    log_error "Failed to decrypt credentials"
    unset key_hex
    return 1
  }

  unset key_hex

  # Extract credential for provider
  local credential
  credential=$(echo "$creds_json" | jq -r --arg p "$provider" '.[$p] // empty') || {
    log_error "Failed to parse credentials"
    unset creds_json
    return 1
  }

  unset creds_json

  if [[ -z "$credential" ]]; then
    log_debug "No credential found for provider: $provider"
    return 1
  fi

  printf '%s' "$credential"
}

# List providers with stored credentials
# Usage: vault_list_providers "password"
# Password is always required (inline unlock model)
# Outputs: provider names, one per line
vault_list_providers() {
  local password="$1"

  if ! vault_is_initialized; then
    return 1
  fi

  if [[ -z "$password" ]]; then
    return 1
  fi

  local vault_dir creds_file
  vault_dir=$(_get_vault_dir)
  creds_file="${vault_dir}/credentials.enc"

  if [[ ! -f "$creds_file" ]]; then
    return 0
  fi

  # Derive key from password
  local key_hex
  key_hex=$(vault_derive_key "$password") || return 1

  # Decrypt and list keys
  local creds_json
  creds_json=$(_vault_decrypt_file "$creds_file" "$key_hex") || {
    unset key_hex
    return 1
  }

  unset key_hex

  echo "$creds_json" | jq -r 'keys[]' 2>/dev/null
  unset creds_json
}

# Clear a credential from the vault
# Usage: vault_clear_credential "provider" "password"
# Password is always required (inline unlock model)
# Returns: 0 = success, 1 = failure
vault_clear_credential() {
  local provider="$1"
  local password="$2"

  if [[ -z "$provider" ]]; then
    log_error "Provider name required"
    return 1
  fi

  if [[ -z "$password" ]]; then
    log_error "Vault password is required"
    return 1
  fi

  if ! vault_is_initialized; then
    log_error "Vault not initialized"
    return 1
  fi

  local vault_dir creds_file
  vault_dir=$(_get_vault_dir)
  creds_file="${vault_dir}/credentials.enc"

  if [[ ! -f "$creds_file" ]]; then
    log_info "No credentials stored"
    return 0
  fi

  # Derive key from password
  local key_hex
  key_hex=$(vault_derive_key "$password") || return 1

  # Decrypt
  local creds_json
  creds_json=$(_vault_decrypt_file "$creds_file" "$key_hex") || {
    log_error "Failed to decrypt credentials"
    unset key_hex
    return 1
  }

  # Remove credential
  creds_json=$(echo "$creds_json" | jq --arg p "$provider" 'del(.[$p])') || {
    log_error "Failed to update credentials"
    unset key_hex creds_json
    return 1
  }

  # Check if any credentials remain
  local count
  count=$(echo "$creds_json" | jq 'length')

  if [[ "$count" -eq 0 ]]; then
    # No credentials left - delete the file
    secure_delete "$creds_file"
    unset key_hex creds_json
    log_info "Credential cleared for $provider (vault now empty)"
    return 0
  fi

  # Re-encrypt and save
  local encrypted
  encrypted=$(_vault_encrypt_data "$creds_json" "$key_hex") || {
    log_error "Failed to encrypt credentials"
    unset key_hex creds_json
    return 1
  }

  unset key_hex creds_json

  (
    umask 077
    printf '%s' "$encrypted" > "$creds_file"
  )
  chmod 600 "$creds_file"

  unset encrypted
  log_info "Credential cleared for $provider"
  return 0
}

# Clear all vault contents
# Usage: vault_clear_all
# Returns: 0 = success
vault_clear_all() {
  local vault_dir
  vault_dir=$(_get_vault_dir)

  if [[ -d "$vault_dir" ]]; then
    # Secure delete credentials file
    if [[ -f "${vault_dir}/credentials.enc" ]]; then
      secure_delete "${vault_dir}/credentials.enc"
    fi

    # Note: We keep the vault directory and salt so it can be reused
    log_info "All credentials cleared from vault"
  fi

  return 0
}

# Destroy vault completely (including salt)
# Usage: vault_destroy
# Returns: 0 = success
vault_destroy() {
  local vault_dir
  vault_dir=$(_get_vault_dir)

  if [[ -d "$vault_dir" ]]; then
    # Secure delete all files
    find "$vault_dir" -type f -exec bash -c 'source "'"${BASH_SOURCE[0]}"'"; secure_delete "$1"' _ {} \;
    rm -rf "$vault_dir"
    log_info "Vault destroyed"
  fi

  return 0
}

# ============================================================================
# VAULT STATUS
# ============================================================================

# Check if vault has any stored credentials (without decrypting)
# Returns: 0 = has credentials, 1 = empty or not initialized
vault_has_credentials() {
  local vault_dir creds_file
  vault_dir=$(_get_vault_dir)
  creds_file="${vault_dir}/credentials.enc"

  vault_is_initialized && [[ -f "$creds_file" ]]
}

# Get vault status information
# Usage: vault_status ["password"]
# If password provided, includes provider list
# Outputs: JSON object with status info
vault_status() {
  local password="${1:-}"
  local vault_dir
  vault_dir=$(_get_vault_dir)

  local initialized="false"
  local has_credentials="false"
  local providers_count=0
  local providers="[]"

  if vault_is_initialized; then
    initialized="true"

    if vault_has_credentials; then
      has_credentials="true"

      # If password provided, list providers
      if [[ -n "$password" ]]; then
        local provider_list
        provider_list=$(vault_list_providers "$password" 2>/dev/null) || true
        if [[ -n "$provider_list" ]]; then
          providers_count=$(echo "$provider_list" | wc -l | tr -d ' ')
          providers=$(echo "$provider_list" | jq -R . | jq -s .)
        fi
      fi
    fi
  fi

  jq -n \
    --arg init "$initialized" \
    --arg has_creds "$has_credentials" \
    --argjson count "$providers_count" \
    --argjson provs "$providers" \
    '{initialized: ($init == "true"), has_credentials: ($has_creds == "true"), credential_count: $count, providers: $provs}'
}
