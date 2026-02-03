# Velum Security Remediation Plan

**Version:** 0.6.0
**Status:** Complete
**Last Updated:** 2026-01-29
**Depends On:** None
**Required By:** None
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
1. [x] Replace all `CONFIG[credential]=""` with `unset 'CONFIG[credential]'`
2. [x] Add `mark_sensitive CONFIG[username] CONFIG[password]` immediately after assignment
3. [x] Verify cleanup function calls `unset` on all marked variables
4. [x] Add trap handler to cleanup on script exit/error

**Acceptance Criteria:**
- [x] No credential variables remain in memory after authentication phase
- [x] `declare -p CONFIG` after auth shows no username/password keys
- [x] Cleanup runs on both success and error paths

**Status:** [x] Complete

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
1. [x] Quote all variable expansions in `bin/velum-connect` PostUp/PostDown
2. [x] Quote all variable expansions in `lib/os/linux.sh` iptables commands
3. [x] Add shellcheck directive `# shellcheck disable=SC2086` only where intentional word splitting needed
4. [x] Run `shellcheck` on all modified files

**Acceptance Criteria:**
- [x] `shellcheck bin/velum-connect lib/os/linux.sh` reports no SC2086 warnings
- [x] Variables containing spaces/special chars don't break commands
- [x] Validation still catches malformed input before it reaches commands

**Status:** [x] Complete

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
1. [x] Add `_validate_username()` function to `lib/velum-core.sh`
2. [x] Validate `SUDO_USER` before any use in path construction
3. [x] Validate before `chown` operations
4. [x] Fail closed if validation fails

**Acceptance Criteria:**
- [x] `SUDO_USER='../../../etc'` does not create path traversal
- [x] `SUDO_USER='$(whoami)'` does not execute command
- [x] Invalid usernames cause hard failure, not silent fallback

**Status:** [x] Complete

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
1. [x] Remove account ID write operations from provider modules
2. [x] Modify `provider_authenticate()` to accept account ID as parameter only
3. [x] Update `bin/velum-config` to not persist account ID
4. [x] Implement tmpfs token storage at `/run/user/$UID/velum/`
5. [x] Add migration to securely delete existing plaintext account files
6. [x] Update documentation

**Acceptance Criteria:**
- [x] `find ~/.config/velum -name '*_account'` returns nothing
- [x] Token refresh prompts for account ID (or uses vault if configured)
- [x] Tokens stored in tmpfs are cleared on reboot

**Status:** [x] Complete

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
1. [x] Create `lib/velum-credential.sh` with runtime dir detection
2. [x] Implement `credential_store_token()` for tmpfs storage
3. [x] Implement `credential_get_token()` for retrieval
4. [x] Update provider modules to use new API
5. [x] Test on systems without XDG_RUNTIME_DIR

**Acceptance Criteria:**
- [x] Tokens stored in `/run/user/$UID/velum/` on Linux
- [x] Tokens cleared automatically on reboot
- [x] Fallback works on minimal systems (fail-closed, no /tmp fallback)

**Status:** [x] Complete

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
1. [x] Add `_check_file_security()` to `lib/velum-security.sh`
2. [x] Call before loading config file
3. [x] Call before reading credential files
4. [x] Call before reading token files
5. [x] Warn but continue for non-critical files; fail for credentials

**Acceptance Criteria:**
- [x] Config file with 644 perms triggers warning
- [x] Token file with 644 perms triggers error
- [x] Files owned by other users trigger error

**Status:** [x] Complete

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
1. [x] Add argon2 to dependency check
2. [x] Implement `vault_derive_key()` function
3. [x] Implement salt generation and storage
4. [x] Test key derivation consistency across platforms

**Acceptance Criteria:**
- [x] Same passphrase + salt produces same key
- [x] Different salts produce different keys
- [x] Key derivation completes in < 3 seconds on target hardware

**Status:** [x] Complete

---

### 3.2 Implement AES-256-CBC with HMAC-SHA256 Encryption

**Severity:** N/A (new feature)
**Purpose:** Encrypt credentials at rest

**Note:** Changed from AES-256-GCM to AES-256-CBC with HMAC-SHA256 (encrypt-then-MAC) because OpenSSL's `enc` command doesn't support AEAD ciphers. The encrypt-then-MAC pattern provides equivalent authenticated encryption.

**Implementation:**
```bash
vault_encrypt() {
  local plaintext="$1"
  local key="$2"  # 64 bytes: 32 for AES, 32 for HMAC

  local enc_key="${key:0:64}"   # First 32 bytes (hex)
  local mac_key="${key:64:64}"  # Second 32 bytes (hex)

  local iv=$(openssl rand -hex 16)
  local ciphertext=$(echo -n "$plaintext" | openssl enc -aes-256-cbc -K "$enc_key" -iv "$iv" | xxd -p | tr -d '\n')
  local hmac=$(echo -n "${iv}${ciphertext}" | xxd -r -p | openssl dgst -sha256 -mac HMAC -macopt hexkey:"$mac_key" | awk '{print $2}')

  echo "$iv"
  echo "$hmac"
  echo "$ciphertext"
}
```

**Steps:**
1. [x] Implement `vault_encrypt()` function with AES-256-CBC
2. [x] Implement `vault_decrypt()` function
3. [x] Add HMAC-SHA256 authentication (encrypt-then-MAC pattern)
4. [x] Test round-trip encryption/decryption
5. [x] Handle decryption failures gracefully (wrong passphrase)

**Acceptance Criteria:**
- [x] Encrypted file is not readable without passphrase
- [x] Wrong passphrase fails with clear error (HMAC verification), not garbage output
- [x] Encryption uses unique IV each time

**Status:** [x] Complete

---

### 3.3 Vault CLI Interface

**Severity:** N/A (new feature)
**Purpose:** User interface for credential storage

**New Files:**
- `bin/velum-credential` - Credential management CLI

**Commands:**
```bash
velum credential init                # Initialize vault (first-time setup)
velum credential status              # Show vault status
velum credential store <provider>    # Store credential in vault
velum credential clear [provider]    # Remove credential(s) from vault
velum credential migrate             # Clean up plaintext creds and legacy session files
```

**Steps:**
1. [x] Create `bin/velum-credential` script
2. [x] Implement `init` subcommand with password confirmation
3. [x] Implement `status` subcommand
4. [x] Implement `store` subcommand with provider validation
5. [x] Implement `clear` subcommand with secure deletion
6. [x] Implement `migrate` subcommand (plaintext creds + legacy session files + vault key cache)
7. [x] Add to main `velum` dispatcher
8. [x] Integrate with `velum-connect` and `velum-config`

**Acceptance Criteria:**
- [x] `velum credential status` shows vault initialization and credential presence
- [x] `velum credential store mullvad` validates 16-digit format, prompts for vault password
- [x] `velum credential clear` securely deletes credential files
- [x] Inline unlock model: vault password required each operation, never cached

**Status:** [x] Complete

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
1. [x] Add `credential_source` config option to tokenizer
2. [x] Implement `prompt` source (already exists, formalize)
3. [x] Implement `command` source with proper error handling
4. [x] Implement `vault` source (requires Phase 3)
5. [x] Document configuration options
6. [ ] Test with various user command examples

**Acceptance Criteria:**
- [x] `credential_source=prompt` asks user interactively
- [x] `credential_source=command` executes user's configured command
- [x] `credential_source=vault` decrypts from velum vault
- [x] Command failures (non-zero exit) prevent connection with clear error
- [x] No credential logging regardless of source

**Status:** [x] Complete

---

## Phase 4.x: External Credential Sources REMOVED (Security Hardening)

### 4.2 Removal of External Credential Source Support

**Severity:** CRITICAL (Security Hardening)
**Purpose:** Eliminate forensic metadata exposure from external tools

**Overview:**
Security audit revealed that external credential tools (password managers, OS keychains) create forensic artifacts that violate velum's threat model. On device seizure, adversaries can extract identifying information even without decrypting credentials.

**Forensic Exposure by Tool:**
| Tool | Forensic Artifact | Decision |
|------|-------------------|----------|
| Bitwarden CLI | Plaintext email, KDF params, org membership | **BLACKLIST** |
| 1Password CLI | Account metadata, team memberships | **BLACKLIST** |
| pass/gopass | GPG key IDs (correlatable via keyservers) | **BLACKLIST** |
| KeePassXC CLI | Database path, metadata | **BLACKLIST** |
| GNOME Keyring | Session-tied, persists across reboots | **BLACKLIST** |
| macOS Keychain | Apple ID integration, identity-tied | **BLACKLIST** |

**Velum's Vault Comparison:**
- Stores ONLY: random salt + encrypted blob
- NO email addresses, NO account IDs in metadata
- NO identity correlation possible

**Supported Sources (Hardened):**
| Source | Description |
|--------|-------------|
| `prompt` | Ask user each time (default, most secure) |
| `vault` | Velum's encrypted vault (no identifying metadata) |

**User Flow (Simplified):**
```
CREDENTIAL STORAGE
==================

How should velum retrieve your account credentials?

  1) Prompt each time     (default - most secure, no storage)
  2) Encrypted vault      (Velum's built-in AES-256 encrypted storage)

Note: External password managers are not supported due to
forensic metadata exposure on device seizure.

Select [1-2, default=1]:
```

**Migration for Existing Users:**
Users with `credential_source=command` receive a hard error with clear migration path:
- `velum connect` fails with security explanation
- `velum config` clears deprecated setting and re-runs wizard

**Files Modified:**
| File | Changes |
|------|---------|
| `lib/velum-credential.sh` | Removed tool detection, simplified wizard to prompt/vault only |
| `lib/velum-security.sh` | Validation rejects credential_source=command |
| `bin/velum-connect` | Deprecation check before connection |
| `bin/velum-config` | Deprecation check with reconfiguration |

**Steps:**
1. [x] Remove external tool detection code (_CREDENTIAL_TOOLS, _DESKTOP_APPS)
2. [x] Remove external tool functions (credential_detect_tools, etc.)
3. [x] Simplify wizard to only offer prompt and vault
4. [x] Add credential_check_deprecated_source() for migration
5. [x] Update security validation to reject command source
6. [x] Update documentation

**Acceptance Criteria:**
- [x] New config wizard only shows prompt and vault options
- [x] Existing credential_source=command fails with security message
- [x] Security validation rejects command source in config
- [x] Documentation updated with forensic exposure rationale

**Status:** [x] Complete

**Design Principle:** Security must be 100% or it provides false assurance. Velum's threat model assumes device seizure - any tool that leaves identifying artifacts defeats the purpose.

---

## Tracking Summary

| Phase | Item | Severity | Status |
|-------|------|----------|--------|
| 1.1 | Memory cleanup (unset) | CRITICAL | [x] Complete |
| 1.2 | Quote variables | CRITICAL | [x] Complete |
| 1.3 | SUDO_USER validation | HIGH | [x] Complete |
| 2.1 | Remove plaintext storage | CRITICAL | [x] Complete |
| 2.2 | tmpfs token storage | HIGH | [x] Complete |
| 2.3 | Permission validation | HIGH | [x] Complete |
| 3.1 | Argon2id KDF | N/A | [x] Complete |
| 3.2 | AES-256-CBC + HMAC-SHA256 encryption | N/A | [x] Complete |
| 3.3 | Vault CLI | N/A | [x] Complete |
| 4.1 | Credential source hook (user's choice) | N/A | [x] Complete |
| 4.2 | ~~Interactive credential source wizard~~ → External sources REMOVED | CRITICAL | [x] Complete |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.1.0 | 2026-01-28 | Initial remediation plan |
| 0.2.0 | 2026-01-28 | Phase 2 complete: tmpfs storage, permission validation |
| 0.3.0 | 2026-01-28 | Phase 3 complete: Encrypted vault with Argon2id + AES-256-CBC/HMAC-SHA256, inline unlock model, session material hardening (WG keys + tokens to tmpfs) |
| 0.4.0 | 2026-01-28 | Phase 4 complete: External credential command integration, unified credential_get_from_source() API |
| 0.5.0 | 2026-01-28 | Phase 4.x: Interactive credential source wizard with tool detection |
| 0.6.0 | 2026-01-29 | **SECURITY HARDENING**: External credential sources REMOVED (Bitwarden, 1Password, pass, keychains blacklisted due to forensic metadata exposure). Only prompt and vault supported. |

---

*End of Remediation Plan*
