# Velum Credential Security Specification

**Version:** 0.4.0
**Date:** 2026-01-29
**Status:** Implemented (Phase 1-4 Complete, External Sources Removed)
**Classification:** Security-Critical

---

## Table of Contents

1. [Problem Statement](#1-problem-statement)
2. [Threat Model](#2-threat-model)
3. [Credential Classification](#3-credential-classification)
4. [Storage Architecture](#4-storage-architecture)
5. [Credential Lifecycle](#5-credential-lifecycle)
6. [Implementation Requirements](#6-implementation-requirements)
7. [Migration Path](#7-migration-path)
8. [Audit Findings](#8-audit-findings)

---

## 1. Problem Statement

### 1.1 Current Flaw

Velum currently stores VPN account credentials in plaintext:

```
~/.config/velum/tokens/
├── mullvad_account    # Plaintext: 16-digit account number
├── mullvad_token      # Plaintext: JWT access token
├── ivpn_account       # Plaintext: i-XXXX-XXXX-XXXX
└── ivpn_token         # Plaintext: JWT access token
```

**Why this is catastrophic:**

For Mullvad and IVPN, the account ID **is** the credential. Unlike username/password systems:
- Account IDs cannot be changed
- Account IDs cannot be revoked without closing the account
- Possession of the account ID = full account access
- Anyone with the file can impersonate the user

### 1.2 Attack Scenarios

| Scenario | Impact |
|----------|--------|
| Device seizure (LEO) | Account ID → API queries → subscription dates, payment method, connection metadata |
| Border crossing inspection | Same as above; may be compelled to unlock device |
| Device theft | Attacker gains full account access |
| Malware/RAT | Exfiltrate credentials silently |
| Shared system | Other users can read tokens directory |
| Backup exposure | Credentials included in system backups, cloud sync |

### 1.3 Design Goal

**Default behavior:** Credentials are not persisted across reboots. User enters account ID when needed; short-lived tokens may be stored in tmpfs for the current session only.

**Opt-in behavior:** User can enable encrypted storage for convenience, understanding the tradeoff.

---

## 2. Threat Model

### 2.1 Adversary Capabilities

Velum assumes users may face adversaries with:

| Capability | Examples |
|------------|----------|
| Physical device access | Law enforcement, border agents, thieves |
| Disk forensics | Deleted file recovery, swap analysis |
| Live system access | Malware, compromised accounts |
| Network surveillance | ISP, state actors |
| Compelled disclosure | Legal orders, coercion |

### 2.2 Assets to Protect

| Asset | Sensitivity | Current Protection | Required Protection |
|-------|-------------|-------------------|---------------------|
| Account ID | **CRITICAL** | Plaintext file | No storage OR encrypted |
| Access Token | HIGH | Plaintext file | Encrypted OR memory-only |
| WireGuard Private Key | HIGH | Plaintext file | Encrypted OR ephemeral |
| Config preferences | LOW | Plaintext file | Plaintext acceptable |

### 2.3 Security Boundaries

```
┌─────────────────────────────────────────────────────────────────┐
│  TRUST BOUNDARY: User's encrypted home directory                │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  CRITICAL: Never store permanently                       │   │
│  │  - Account IDs (mullvad, ivpn)                          │   │
│  │  - Plaintext passwords                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  HIGH: Store encrypted OR ephemeral                      │   │
│  │  - Access tokens (short-lived, but reveals provider)    │   │
│  │  - WireGuard private keys                               │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  MEDIUM: Plaintext acceptable with restrictive perms     │   │
│  │  - Connection preferences                                │   │
│  │  - Server selection                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Credential Classification

### 3.1 Classification Levels

| Level | Definition | Storage Policy |
|-------|------------|----------------|
| **CRITICAL** | Permanent credential; possession = account access | Never persist by default |
| **HIGH** | Sensitive but time-limited or revocable | Encrypted or memory-only |
| **MEDIUM** | Reveals usage patterns but not credentials | Plaintext with permissions |
| **LOW** | Non-sensitive preferences | Plaintext acceptable |

### 3.2 Credential Inventory

| Credential | Classification | Justification |
|------------|----------------|---------------|
| Mullvad account number | CRITICAL | 16 digits = full account access forever |
| IVPN account ID | CRITICAL | i-XXXX-XXXX-XXXX = full account access forever |
| PIA username | HIGH | Can be changed; requires password |
| PIA password | CRITICAL | Combined with username = access |
| Access token (any) | HIGH | Time-limited; reveals provider choice |
| WireGuard private key | HIGH | Cryptographic material; can be regenerated |
| Selected server | MEDIUM | Reveals geographic preferences |
| Kill switch setting | LOW | Non-sensitive preference |

---

## 4. Storage Architecture

### 4.1 Default Mode: No Persistence

**Principle:** By default, CRITICAL credentials are never written to persistent disk.

```
User Flow (Default):
1. User runs `velum connect`
2. Velum checks for valid token in memory/tmpfs
3. If missing/expired: prompt for account ID
4. Authenticate, store token in memory/tmpfs only
5. Connect
6. On disconnect or failure: delete tmpfs token immediately
7. On reboot: tmpfs is cleared automatically
```

**Storage locations (session-only):**
```
/run/user/$UID/velum/           # tmpfs, cleared on reboot
├── mullvad_token               # Access token only, no account ID
├── ivpn_token
├── pia_token
└── wg_private_key              # WireGuard private key (regenerated each session)
```

### 4.2 Opt-In Mode: Encrypted Storage

**Principle:** User explicitly enables credential storage with encryption (opt-in only).

```bash
velum credential init           # First-time vault setup
velum credential store mullvad  # Store credential (prompts for vault password)
velum credential store ivpn     # Store another credential
```

**Encrypted storage structure:**
```
~/.config/velum/
├── vault/                      # Mode 700
│   ├── credentials.enc         # AES-256-CBC encrypted JSON blob
│   └── salt                    # Argon2 salt for KDF (hex-encoded)
└── velum.conf                  # VPN preferences (no credentials)
```

**Encryption scheme:**
- KDF: Argon2id (memory-hard, resists GPU attacks)
  - Memory: 64 MiB, Iterations: 3, Parallelism: 4
  - Output: 64 bytes (32 for AES key, 32 for HMAC key)
- Cipher: AES-256-CBC with HMAC-SHA256 (encrypt-then-MAC)
- **Inline unlock model**: Vault password required for EVERY operation, never cached
- No derived key stored anywhere (not even in tmpfs)

### 4.3 External Credential Sources: REMOVED (Security Risk)

**Status:** ~~Alternative: External Credential Source~~ → **REMOVED**

**Date Removed:** 2026-01-29

**Reason:** Security audit revealed that external credential tools create forensic artifacts that violate velum's threat model. On device seizure, adversaries can extract identifying information even without decrypting the credential itself.

**Forensic Exposure by Tool:**

| Tool | Forensic Artifact | Risk Level |
|------|-------------------|------------|
| Bitwarden CLI | Plaintext email address, KDF parameters, org membership | **CRITICAL** |
| 1Password CLI | Account metadata, team memberships, email | **CRITICAL** |
| pass/gopass | GPG key IDs (traceable via public keyservers) | **HIGH** |
| KeePassXC CLI | Database path, metadata, access timestamps | **HIGH** |
| GNOME Keyring | Session-tied, persists across reboots, identity-linked | **HIGH** |
| macOS Keychain | Apple ID integration, identity-tied, cloud sync exposure | **HIGH** |

**Comparison with Velum's Vault:**

| Artifact | External Tools | Velum Vault |
|----------|----------------|-------------|
| User email | Exposed | Not stored |
| Account ID | External storage | Encrypted only |
| KDF parameters | Exposed | Salt only (no identity) |
| Access timestamps | Logged | Not logged |
| Identity correlation | Possible | Not possible |

**Supported credential sources (hardened):**

| Source | Configuration | Description |
|--------|---------------|-------------|
| `prompt` | (default) | Ask user for credential each time - **most secure** |
| `vault` | Built-in | Velum's encrypted vault (Argon2id + AES-256-CBC/HMAC) - **no identifying metadata** |

**Migration for existing users:**

Users with `credential_source=command` in their config will receive a hard error:
```
SECURITY: External credential sources are no longer supported

Your configuration uses credential_source=command

Reason: External tools (Bitwarden, 1Password, pass, keychains)
store identifying metadata that exposes you on device seizure.

Velum now only supports:
  1) prompt - Enter credential each time (most secure)
  2) vault  - Velum's encrypted vault (no identifying metadata)

To reconfigure: velum config
```

**Design principle:** Velum's threat model assumes device seizure by sophisticated adversaries (LEO, border agents, state actors). Any storage mechanism that leaves identifying artifacts - even encrypted ones with metadata - violates this threat model. Security must be 100% or it provides false assurance.

### 4.4 Storage Mode Comparison

| Mode | Device Seizure | Forensic Exposure | UX |
|------|----------------|-------------------|-----|
| **No persistence** (default) | Safe | None | Enter ID each session |
| **Encrypted vault** | Safe (if passphrase not compelled) | Salt only (no identity) | Enter passphrase each time |
| ~~Hardware key (YubiKey)~~ | ~~Safe~~ | **GPG key ID exposed** | REMOVED |
| ~~Password manager~~ | ~~Safe~~ | **Email/identity exposed** | REMOVED |
| ~~Plaintext~~ | **VULNERABLE** | **Full exposure** | REMOVED |

**Note:** External tools (YubiKey via GPG, password managers) were removed in v0.4.0 due to forensic metadata exposure that violates velum's threat model.

---

## 5. Credential Lifecycle

### 5.1 Credential Entry

```
┌─────────────────────────────────────────────────────────────────┐
│  User enters account ID                                         │
│                                                                 │
│  1. Mask input (never echo)                                    │
│  2. Validate format before any storage                         │
│  3. Authenticate with provider API                             │
│  4. Clear account ID from memory immediately after auth        │
│  5. Store only the resulting token (if storage enabled)        │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Token Refresh

```
┌─────────────────────────────────────────────────────────────────┐
│  Token expired, refresh needed                                  │
│                                                                 │
│  Default mode:                                                  │
│    → Prompt user for account ID                                │
│    → Re-authenticate                                           │
│    → Store new token in tmpfs                                  │
│                                                                 │
│  Encrypted vault mode:                                          │
│    → Prompt for vault passphrase                               │
│    → Decrypt account ID                                        │
│    → Re-authenticate                                           │
│    → Clear account ID from memory                              │
│    → Store new token (encrypted)                               │
└─────────────────────────────────────────────────────────────────┘
```

### 5.3 Credential Removal

```bash
velum credential clear [--provider mullvad|ivpn|all]

# Actions:
# 1. Overwrite file contents with random data (best-effort)
# 2. Delete files
# 3. Clear any in-memory copies
# 4. Warn about backup/sync exposure
# 5. Clear tmpfs tokens (if present)
```

### 5.4 Memory Handling

```bash
# After using sensitive data, ALWAYS clear from memory
local account_id
account_id=$(ask_password "Account ID")

# ... use account_id for authentication ...

# IMMEDIATELY after use:
unset account_id

# For arrays:
unset CREDENTIALS
declare -A CREDENTIALS=()  # Re-declare empty
```

---

## 6. Implementation Requirements

### 6.1 MUST Requirements

| ID | Requirement |
|----|-------------|
| SEC-01 | Account IDs MUST NOT be stored in plaintext by default |
| SEC-02 | All credential input MUST be masked (no echo) |
| SEC-03 | Credentials MUST be cleared from memory after use |
| SEC-04 | Storage directories MUST have mode 700 |
| SEC-05 | Credential files MUST have mode 600 |
| SEC-06 | Encrypted storage MUST use authenticated encryption (AES-256-CBC + HMAC-SHA256) |
| SEC-07 | KDF MUST be memory-hard (Argon2id) |
| SEC-08 | Credential operations MUST work correctly under sudo and target the real user context (SUDO_USER) |

### 6.2 SHOULD Requirements

| ID | Requirement |
|----|-------------|
| SEC-09 | Token storage SHOULD use tmpfs when available |
| SEC-10 | Deletion SHOULD attempt secure overwrite before unlink |
| SEC-11 | Error messages SHOULD NOT reveal credential values |
| SEC-12 | Logs SHOULD NOT contain credentials (even in debug mode) |

### 6.3 Implementation Notes

**Argon2id parameters:**
```bash
# Parameters used (stored with vault metadata):
# - Memory: 64 MiB (-k 65536)
# - Iterations: 3 (-t 3)
# - Parallelism: 4 (-p 4)
# - Output: 64 bytes (32 for AES key, 32 for HMAC key)
```

**AES-256-CBC + HMAC-SHA256 implementation (encrypt-then-MAC):**
```bash
# Encryption:
# 1. Generate random 16-byte IV
# 2. Encrypt plaintext with AES-256-CBC using first 32 bytes of derived key
# 3. Compute HMAC-SHA256(IV || ciphertext) using second 32 bytes of derived key
# 4. Store: IV, HMAC, ciphertext (all hex-encoded)

# Decryption:
# 1. Verify HMAC first (reject if mismatch = wrong password or tampering)
# 2. Decrypt ciphertext with AES-256-CBC
```

---

## 7. Migration Path

### 7.1 Phase 1: Deprecate Plaintext Storage

1. Add warning when plaintext credentials detected
2. Implement tmpfs-only token storage
3. Remove account ID persistence (prompt each time)
4. Update documentation

### 7.2 Phase 2: Encrypted Vault

1. Implement Argon2id + AES-256-GCM vault
2. Add `velum credential` subcommand
3. Migration tool for existing credentials
4. Update tokenizer spec to use vault

### 7.3 Phase 3: External Secret Management (Optional)

1. Bitwarden CLI integration
2. YubiKey PIV integration
3. Generic "credential command" hook for custom sources
4. User preference for credential source in tokenizer.conf

### 7.4 Migration Command

```bash
velum credential migrate

# Detects:
# - Plaintext credentials in old locations
# - Offers to:
#   a) Delete them (no storage)
#   b) Migrate to encrypted vault
#   c) Migrate to external credential source (command/keychain/etc.)
# - Securely deletes old files after migration
```

---

## 8. Audit Findings

### 8.1 Current Codebase Audit

| File | Issue | Severity | Status |
|------|-------|----------|--------|
| `lib/providers/mullvad.sh` | Stores account ID in plaintext | CRITICAL | **Resolved** - No plaintext storage; vault opt-in |
| `lib/providers/ivpn.sh` | Stores account ID in plaintext | CRITICAL | **Resolved** - No plaintext storage; vault opt-in |
| `bin/velum-config` | Reads plaintext credentials | HIGH | **Resolved** - Uses vault API with inline unlock |
| `lib/velum-security.sh` | Token stored in plaintext | HIGH | **Resolved** - Tokens in tmpfs only |
| `lib/velum-core.sh` | VELUM_TOKENS_DIR used for plaintext credentials | MEDIUM | **Resolved** - Session material in VELUM_RUNTIME_DIR (tmpfs) |

### 8.2 Files Changed

| File | Change | Status |
|------|--------|--------|
| `lib/velum-credential.sh` | NEW: Credential management library (tmpfs, migration, credential_get_from_source API) | Complete |
| `lib/velum-vault.sh` | NEW: Encrypted storage (Argon2id + AES-256-CBC/HMAC-SHA256) | Complete |
| `bin/velum-credential` | NEW: Credential CLI (init, store, clear, migrate) | Complete |
| `lib/providers/pia.sh` | MODIFY: Tokens to tmpfs (`--runtime` flag) | Complete |
| `bin/velum-config` | MODIFY: Uses credential_get_from_source() for unified credential retrieval | Complete |
| `bin/velum-connect` | MODIFY: Uses credential_get_from_source(), WG keys to tmpfs | Complete |
| `lib/velum-security.sh` | MODIFY: Added credential_source + credential_command validation | Complete |

---

## Appendix A: Encryption Implementation Reference

### A.1 Key Derivation (Argon2id)

```bash
# Using argon2 CLI tool:
echo -n "$passphrase" | argon2 "$salt" -id -t 3 -m 16 -p 4 -l 32 -r

# Parameters:
# -id    : Argon2id variant
# -t 3   : 3 iterations
# -m 16  : 2^16 KiB = 64 MiB memory
# -p 4   : 4 parallel lanes
# -l 32  : 32 byte (256 bit) output
# -r     : Raw output (no encoding)
```

### A.2 Encryption (AES-256-CBC with HMAC-SHA256)

**Note:** Changed from AES-256-GCM to AES-256-CBC with HMAC-SHA256 (encrypt-then-MAC) because OpenSSL's `enc` command doesn't support AEAD ciphers. The encrypt-then-MAC pattern provides equivalent authenticated encryption.

```bash
# Key derivation produces 64 bytes (512 bits):
# - First 32 bytes: AES-256 encryption key
# - Second 32 bytes: HMAC-SHA256 authentication key

# Encrypt:
iv=$(openssl rand -hex 16)
ciphertext=$(echo -n "$plaintext" | openssl enc -aes-256-cbc -K "$enc_key" -iv "$iv" | xxd -p | tr -d '\n')
hmac=$(echo -n "${iv}${ciphertext}" | xxd -r -p | openssl dgst -sha256 -mac HMAC -macopt hexkey:"$mac_key" | awk '{print $2}')

# Output format (credentials.enc):
# Line 1: IV (hex)
# Line 2: HMAC (hex)
# Line 3: Ciphertext (hex)

# Decrypt:
# 1. Read IV, HMAC, ciphertext from file
# 2. Verify HMAC: compute HMAC(IV || ciphertext), compare to stored HMAC
# 3. If HMAC matches, decrypt ciphertext with AES-256-CBC
# 4. If HMAC fails, reject (wrong password or tampering)
```

### A.3 Secure Random Generation

```bash
# Always use /dev/urandom or openssl rand:
salt=$(openssl rand -hex 16)
nonce=$(openssl rand 12)

# NEVER use $RANDOM, date, or predictable sources
```

---

## Appendix B: Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.1.0-draft | 2026-01-28 | Initial specification |
| 0.2.0 | 2026-01-28 | Implementation complete: Argon2id KDF, AES-256-CBC/HMAC-SHA256 encryption, inline unlock model, tmpfs session storage, vault CLI, migration tools. All audit findings resolved. |
| 0.4.0 | 2026-01-29 | **SECURITY HARDENING**: Removed all external credential source support (Bitwarden, 1Password, pass, keychains). Forensic metadata exposure violates threat model. Only prompt and vault sources remain. |

---

*End of Specification - Security-Critical Document*
