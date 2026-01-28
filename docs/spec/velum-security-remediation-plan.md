# Velum Security Remediation Plan

**Version:** 0.1.0
**Date:** 2026-01-28
**Status:** Active
**Audit Date:** 2026-01-28

---

## Overview

This document tracks the remediation of security findings from the 2026-01-28 audit. Each finding has a dedicated section with:
- Issue description
- Affected files and line numbers
- Remediation steps
- Acceptance criteria
- Status

---

## Phase 1: Immediate Fixes (Memory & Injection)

### 1.1 Memory Handling - Credential Cleanup

**Severity:** CRITICAL
**Finding:** Credentials cleared with `=""` instead of `unset`

**Affected Files:**
| File | Lines | Issue |
|------|-------|-------|
| `bin/velum-config` | 279-280 | `CONFIG[username]=""` does not free memory |
| `bin/velum-config` | 318-319 | Same pattern in account auth |
| `bin/velum-config` | 328-329 | Account number not unset |
| `lib/velum-security.sh` | 469-481 | Hardcoded cleanup list incomplete |

**Remediation:**
```bash
# BEFORE (insecure):
CONFIG[username]=""
CONFIG[password]=""

# AFTER (secure):
unset 'CONFIG[username]' 'CONFIG[password]'
```

**Steps:**
1. [ ] Replace all `CONFIG[credential]=""` with `unset 'CONFIG[credential]'`
2. [ ] Add `mark_sensitive CONFIG[username] CONFIG[password]` immediately after assignment
3. [ ] Verify cleanup function calls `unset` on all marked variables
4. [ ] Add trap handler to cleanup on script exit/error

**Acceptance Criteria:**
- [ ] No credential variables remain in memory after authentication phase
- [ ] `declare -p CONFIG` after auth shows no username/password keys
- [ ] Cleanup runs on both success and error paths

**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

---

### 1.2 Command Injection - Unquoted Variables

**Severity:** CRITICAL
**Finding:** Unquoted variables in shell commands could allow injection

**Affected Files:**
| File | Lines | Variable | Context |
|------|-------|----------|---------|
| `bin/velum-connect` | 237-240 | `${CONFIG[killswitch_lan]}` | WireGuard PostUp |
| `bin/velum-connect` | 258-259 | `$dns_server` | macOS route command |
| `bin/velum-connect` | 263-264 | `$dns_server` | Linux ip route command |
| `lib/os/linux.sh` | 350 | `$vpn_ip`, `$vpn_port` | iptables rules |
| `lib/os/linux.sh` | 368 | `$subnet` | iptables rules |

**Remediation:**
```bash
# BEFORE (vulnerable):
route -q -n add -host $dns_server -interface %i

# AFTER (safe):
route -q -n add -host "$dns_server" -interface %i
```

**Steps:**
1. [ ] Quote all variable expansions in `bin/velum-connect` PostUp/PostDown
2. [ ] Quote all variable expansions in `lib/os/linux.sh` iptables commands
3. [ ] Add shellcheck directive `# shellcheck disable=SC2086` only where intentional word splitting needed
4. [ ] Run `shellcheck` on all modified files

**Acceptance Criteria:**
- [ ] `shellcheck bin/velum-connect lib/os/linux.sh` reports no SC2086 warnings
- [ ] Variables containing spaces/special chars don't break commands
- [ ] Validation still catches malformed input before it reaches commands

**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

---

### 1.3 Input Validation - SUDO_USER

**Severity:** HIGH
**Finding:** `SUDO_USER` environment variable trusted without validation

**Affected Files:**
| File | Lines | Usage |
|------|-------|-------|
| `lib/velum-core.sh` | 51-62 | `_get_config_home()` |
| `lib/velum-core.sh` | 138-143 | Path construction |
| `lib/velum-core.sh` | 448-451 | `chown` operations |

**Remediation:**
```bash
# BEFORE (trusting):
VELUM_REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

# AFTER (validating):
_validate_username() {
  local user="$1"
  # Only alphanumeric, underscore, hyphen; 1-32 chars; starts with letter
  [[ "$user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

if [[ -n "${SUDO_USER:-}" ]]; then
  _validate_username "$SUDO_USER" || {
    log_error "Invalid SUDO_USER value"
    exit 1
  }
  VELUM_REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
fi
```

**Steps:**
1. [ ] Add `_validate_username()` function to `lib/velum-core.sh`
2. [ ] Validate `SUDO_USER` before any use in path construction
3. [ ] Validate before `chown` operations
4. [ ] Fail closed if validation fails

**Acceptance Criteria:**
- [ ] `SUDO_USER='../../../etc'` does not create path traversal
- [ ] `SUDO_USER='$(whoami)'` does not execute command
- [ ] Invalid usernames cause hard failure, not silent fallback

**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

---

## Phase 2: Short-term - Credential Storage

### 2.1 Remove Plaintext Account ID Storage

**Severity:** CRITICAL
**Finding:** Account IDs stored in plaintext files

**Affected Files:**
| File | Current Behavior |
|------|------------------|
| `lib/providers/mullvad.sh` | Writes to `~/.config/velum/tokens/mullvad_account` |
| `lib/providers/ivpn.sh` | Writes to `~/.config/velum/tokens/ivpn_account` |
| `bin/velum-config` | Reads from plaintext credential files |

**Remediation:**
1. **Remove** all plaintext account ID storage
2. **Prompt** user for account ID when token refresh needed
3. **Store** only short-lived tokens (in tmpfs when available)

**Steps:**
1. [ ] Remove account ID write operations from provider modules
2. [ ] Modify `provider_authenticate()` to accept account ID as parameter only
3. [ ] Update `bin/velum-config` to not persist account ID
4. [ ] Implement tmpfs token storage at `/run/user/$UID/velum/`
5. [ ] Add migration to securely delete existing plaintext account files
6. [ ] Update documentation

**Acceptance Criteria:**
- [ ] `find ~/.config/velum -name '*_account'` returns nothing
- [ ] Token refresh prompts for account ID (or uses vault if configured)
- [ ] Tokens stored in tmpfs are cleared on reboot

**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

---

### 2.2 Implement tmpfs Token Storage

**Severity:** HIGH
**Finding:** Tokens persist on disk unnecessarily

**New Files:**
- `lib/velum-credential.sh` - Credential management library

**Implementation:**
```bash
# Determine runtime directory (tmpfs)
_get_runtime_dir() {
  # XDG_RUNTIME_DIR is typically /run/user/$UID (tmpfs)
  if [[ -d "${XDG_RUNTIME_DIR:-}" ]]; then
    echo "${XDG_RUNTIME_DIR}/velum"
  elif [[ -d "/run/user/$(id -u)" ]]; then
    echo "/run/user/$(id -u)/velum"
  else
    # Fallback: use /tmp with restrictive perms (not ideal)
    echo "/tmp/velum-$(id -u)"
  fi
}

VELUM_RUNTIME_DIR="$(_get_runtime_dir)"
mkdir -p "$VELUM_RUNTIME_DIR"
chmod 700 "$VELUM_RUNTIME_DIR"
```

**Steps:**
1. [ ] Create `lib/velum-credential.sh` with runtime dir detection
2. [ ] Implement `credential_store_token()` for tmpfs storage
3. [ ] Implement `credential_get_token()` for retrieval
4. [ ] Update provider modules to use new API
5. [ ] Test on systems without XDG_RUNTIME_DIR

**Acceptance Criteria:**
- [ ] Tokens stored in `/run/user/$UID/velum/` on Linux
- [ ] Tokens cleared automatically on reboot
- [ ] Fallback works on minimal systems

**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

---

### 2.3 Permission Validation

**Severity:** HIGH
**Finding:** Config and token file permissions not validated before use

**Affected Files:**
| File | Lines | Missing Check |
|------|-------|---------------|
| `bin/velum-connect` | 40-51 | Config file perms |
| `bin/velum-config` | 245-251 | Credentials file perms |
| `lib/velum-security.sh` | 376-416 | Token file perms |

**Remediation:**
```bash
# Add to load_config():
_check_file_security() {
  local file="$1"
  local required_mode="${2:-600}"

  [[ ! -f "$file" ]] && return 0  # File doesn't exist yet

  local perms
  perms=$(stat -c %a "$file" 2>/dev/null || stat -f %Lp "$file" 2>/dev/null)

  if [[ "$perms" != "$required_mode" && "$perms" != "400" ]]; then
    log_warn "Insecure permissions on $file (found: $perms, expected: $required_mode)"
    return 1
  fi

  # Check ownership
  local owner
  owner=$(stat -c %U "$file" 2>/dev/null || stat -f %Su "$file" 2>/dev/null)
  local expected_owner="${SUDO_USER:-$USER}"

  if [[ "$owner" != "$expected_owner" && "$owner" != "root" ]]; then
    log_warn "Unexpected owner on $file (found: $owner, expected: $expected_owner)"
    return 1
  fi

  return 0
}
```

**Steps:**
1. [ ] Add `_check_file_security()` to `lib/velum-security.sh`
2. [ ] Call before loading config file
3. [ ] Call before reading credential files
4. [ ] Call before reading token files
5. [ ] Warn but continue for non-critical files; fail for credentials

**Acceptance Criteria:**
- [ ] Config file with 644 perms triggers warning
- [ ] Token file with 644 perms triggers error
- [ ] Files owned by other users trigger error

**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

---

## Phase 3: Medium-term - Encrypted Vault

### 3.1 Implement Argon2id Key Derivation

**Severity:** N/A (new feature)
**Purpose:** Derive encryption key from user passphrase

**New Files:**
- `lib/velum-vault.sh` - Encrypted storage implementation

**Implementation:**
```bash
# Requires: argon2 CLI tool
_derive_key() {
  local passphrase="$1"
  local salt="$2"

  # Argon2id with recommended parameters
  # Memory: 64 MiB, Iterations: 3, Parallelism: 4
  echo -n "$passphrase" | argon2 "$salt" -id -t 3 -m 16 -p 4 -l 32 -r | xxd -p
}
```

**Steps:**
1. [ ] Add argon2 to dependency check
2. [ ] Implement `_derive_key()` function
3. [ ] Implement salt generation and storage
4. [ ] Test key derivation consistency across platforms

**Acceptance Criteria:**
- [ ] Same passphrase + salt produces same key
- [ ] Different salts produce different keys
- [ ] Key derivation completes in < 3 seconds on target hardware

**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

---

### 3.2 Implement AES-256-GCM Encryption

**Severity:** N/A (new feature)
**Purpose:** Encrypt credentials at rest

**Implementation:**
```bash
_encrypt_credential() {
  local plaintext="$1"
  local key_hex="$2"
  local output_file="$3"

  local nonce
  nonce=$(openssl rand -hex 12)

  echo -n "$plaintext" | openssl enc -aes-256-gcm \
    -K "$key_hex" \
    -iv "$nonce" \
    -out "$output_file.tmp"

  # Prepend nonce to ciphertext
  echo -n "$nonce" | xxd -r -p > "$output_file"
  cat "$output_file.tmp" >> "$output_file"
  rm -f "$output_file.tmp"
}

_decrypt_credential() {
  local input_file="$1"
  local key_hex="$2"

  # Extract nonce (first 12 bytes)
  local nonce
  nonce=$(head -c 12 "$input_file" | xxd -p)

  # Decrypt remainder
  tail -c +13 "$input_file" | openssl enc -d -aes-256-gcm \
    -K "$key_hex" \
    -iv "$nonce"
}
```

**Steps:**
1. [ ] Implement `_encrypt_credential()` function
2. [ ] Implement `_decrypt_credential()` function
3. [ ] Add authentication tag verification
4. [ ] Test round-trip encryption/decryption
5. [ ] Handle decryption failures gracefully (wrong passphrase)

**Acceptance Criteria:**
- [ ] Encrypted file is not readable without passphrase
- [ ] Wrong passphrase fails with clear error, not garbage output
- [ ] Encryption uses unique nonce each time

**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

---

### 3.3 Vault CLI Interface

**Severity:** N/A (new feature)
**Purpose:** User interface for credential storage

**New Files:**
- `bin/velum-credential` - Credential management CLI

**Commands:**
```bash
velum credential status              # Show stored credentials (masked)
velum credential store --encrypt     # Enable encrypted storage
velum credential clear               # Remove all stored credentials
velum credential migrate             # Migrate from plaintext to vault
```

**Steps:**
1. [ ] Create `bin/velum-credential` script
2. [ ] Implement `status` subcommand
3. [ ] Implement `store` subcommand with passphrase prompt
4. [ ] Implement `clear` subcommand with secure deletion
5. [ ] Implement `migrate` subcommand
6. [ ] Add to main `velum` dispatcher

**Acceptance Criteria:**
- [ ] `velum credential status` shows credential presence without revealing values
- [ ] `velum credential store --encrypt` prompts for passphrase twice
- [ ] `velum credential clear` securely deletes all credential files

**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

---

## Phase 4: Optional - External Credential Source

### 4.1 Credential Source Hook

**Severity:** N/A (new feature)
**Purpose:** Allow users to fetch credentials from their preferred secret management tool

**Design Principle:** Velum does not mandate any specific solution. Users choose based on their own threat model.

**Supported Sources:**
| Source | Description |
|--------|-------------|
| `prompt` | Ask user each time (default, most secure) |
| `vault` | Velum's built-in encrypted vault |
| `command` | User-defined external command |

**Configuration:**
```bash
# In tokenizer.conf:
TOKENIZER[credential_source]="command"
TOKENIZER[credential_command]="/path/to/user/script"
```

**Example user commands (not velum's responsibility to implement):**
```bash
# Password managers
"bw get password mullvad-vpn"                    # Bitwarden
"op read 'op://Vault/Mullvad/account'"           # 1Password
"pass show vpn/mullvad"                          # pass/gopass
"keepassxc-cli show -s db.kdbx mullvad"          # KeePassXC

# Hardware tokens
"yubico-piv-tool -a verify-pin -a decrypt < ~/.secrets/cred.enc"

# Custom scripts
"$HOME/.local/bin/get-vpn-credential mullvad"
```

**Implementation:**
```bash
_get_credential_from_source() {
  local vendor="$1"
  local source="${_TOKENIZER_CONFIG[credential_source]:-prompt}"

  case "$source" in
    prompt)
      ask_password "Account ID"
      ;;
    command)
      local cmd="${_TOKENIZER_CONFIG[credential_command]}"
      [[ -z "$cmd" ]] && { log_error "credential_command not configured"; return 1; }

      # Execute user's command, capture stdout
      local result
      if ! result=$(eval "$cmd" 2>/dev/null); then
        log_error "Credential command failed"
        return 1
      fi

      # Trim whitespace, return credential
      echo "$result" | tr -d '[:space:]'
      ;;
    vault)
      _decrypt_credential_from_vault "$vendor"
      ;;
    *)
      log_error "Unknown credential source: $source"
      return 1
      ;;
  esac
}
```

**Steps:**
1. [ ] Add `credential_source` config option to tokenizer
2. [ ] Implement `prompt` source (already exists, formalize)
3. [ ] Implement `command` source with proper error handling
4. [ ] Implement `vault` source (requires Phase 3)
5. [ ] Document configuration options
6. [ ] Test with various user command examples

**Acceptance Criteria:**
- [ ] `credential_source=prompt` asks user interactively
- [ ] `credential_source=command` executes user's configured command
- [ ] `credential_source=vault` decrypts from velum vault
- [ ] Command failures (non-zero exit) prevent connection with clear error
- [ ] No credential logging regardless of source

**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

---

## Tracking Summary

| Phase | Item | Severity | Status |
|-------|------|----------|--------|
| 1.1 | Memory cleanup (unset) | CRITICAL | [x] Complete |
| 1.2 | Quote variables | CRITICAL | [x] Complete |
| 1.3 | SUDO_USER validation | HIGH | [x] Complete |
| 2.1 | Remove plaintext storage | CRITICAL | [ ] |
| 2.2 | tmpfs token storage | HIGH | [ ] |
| 2.3 | Permission validation | HIGH | [ ] |
| 3.1 | Argon2id KDF | N/A | [ ] |
| 3.2 | AES-256-GCM encryption | N/A | [ ] |
| 3.3 | Vault CLI | N/A | [ ] |
| 4.1 | Credential source hook (user's choice) | N/A | [ ] |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.1.0 | 2026-01-28 | Initial remediation plan |

---

*End of Remediation Plan*
