# Velum Credential Security Specification

**Version:** 0.1.0-draft
**Date:** 2026-01-28
**Status:** Design Phase - Living Document
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
/run/user/$UID/velum/           # tmpfs, cleared on reboot and on disconnect
├── mullvad_token               # Access token only, no account ID
└── ivpn_token
```

### 4.2 Opt-In Mode: Encrypted Storage

**Principle:** User explicitly enables credential storage with encryption (opt-in only).

```bash
velum credential store --encrypt
# Prompts for storage passphrase
# Stores encrypted credentials in ~/.config/velum/vault/
```

**Encrypted storage structure:**
```
~/.config/velum/
├── vault/                      # Mode 700
│   ├── credentials.enc         # AES-256-GCM encrypted blob
│   └── salt                    # Argon2 salt for KDF
└── vault.conf                  # Storage preferences (not encrypted)
```

**Encryption scheme:**
- KDF: Argon2id (memory-hard, resists GPU attacks)
- Cipher: AES-256-GCM (authenticated encryption)
- Key derivation: passphrase → Argon2id → 256-bit key
- No key stored; derived from passphrase each time

### 4.3 Alternative: External Credential Source (User's Choice)

**Principle:** Velum does not mandate any specific secret management solution. Users choose their own tooling based on their threat model and preferences (opt-in only).

**Supported credential sources:**

| Source | Configuration | Description |
|--------|---------------|-------------|
| `prompt` | (default) | Ask user for credential each time |
| `vault` | Built-in | Velum's encrypted vault (Argon2id + AES-256-GCM) |
| `command` | User-defined | Execute user's command to retrieve credential |

**The `command` source enables any external tool:**
- Password managers (Bitwarden, 1Password, KeePassXC, pass, gopass)
- Hardware tokens (YubiKey, Nitrokey, OnlyKey)
- Custom scripts
- Enterprise secret management (Vault, AWS Secrets Manager)

**Configuration:**
```bash
# In tokenizer.conf:

# Option 1: Prompt every time (default, most secure)
TOKENIZER[credential_source]="prompt"

# Option 2: Use velum's encrypted vault
TOKENIZER[credential_source]="vault"

# Option 3: External command (user's choice of tooling)
TOKENIZER[credential_source]="command"
TOKENIZER[credential_command]="/path/to/your/script"
# OR
TOKENIZER[credential_command]="bw get password mullvad-vpn"
# OR
TOKENIZER[credential_command]="pass show vpn/mullvad"
# OR
TOKENIZER[credential_command]="yubico-piv-tool -a verify-pin -a decrypt < ~/.secrets/mullvad.enc"
```

**Security considerations for `command` source:**
- User accepts responsibility for their command's security
- Command output is treated as the credential (stdout, trimmed)
- Command errors (non-zero exit) prevent connection
- Velum does not log or store the command output

**Why this approach:**
- No vendor lock-in
- Respects user's existing security infrastructure
- Supports air-gapped and enterprise environments
- Users control their own threat model tradeoffs

### 4.4 Storage Mode Comparison

| Mode | Device Seizure | Live System Attack | UX |
|------|----------------|-------------------|-----|
| **No persistence** (default) | Safe | Safe | Enter ID each session |
| **Encrypted vault** | Safe (if passphrase not compelled) | Safe (locked) | Enter passphrase once |
| **Hardware key (YubiKey)** | Safe (requires physical key) | Safe (requires touch) | Key + PIN |
| **Password manager** | Safe (external storage) | Depends on manager | Manager unlock |
| **Plaintext** (current) | **VULNERABLE** | **VULNERABLE** | Convenient |

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
| SEC-06 | Encrypted storage MUST use authenticated encryption (AES-GCM) |
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

**Argon2id parameters (balance security vs. UX):**
```bash
# Recommended parameters for interactive use (tunable; stored with vault metadata):
# - Memory: 64 MiB
# - Iterations: 3
# - Parallelism: 4
# - Output: 32 bytes (256 bits)
```

**AES-256-GCM implementation:**
```bash
# Use OpenSSL for encryption:
# - Generate random 12-byte nonce for each encryption
# - Prepend nonce to ciphertext
# - Tag is appended automatically by OpenSSL
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
| `lib/providers/mullvad.sh` | Stores account ID in plaintext | CRITICAL | Open |
| `lib/providers/ivpn.sh` | Stores account ID in plaintext | CRITICAL | Open |
| `bin/velum-config` | Reads plaintext credentials | HIGH | Open |
| `lib/velum-security.sh` | Token stored in plaintext | HIGH | Open |
| `lib/velum-core.sh` | VELUM_TOKENS_DIR used for plaintext credentials (must route through credential API) | MEDIUM | Open |

### 8.2 Files Requiring Changes

```
lib/velum-credential.sh      # NEW: Credential management library
lib/velum-vault.sh           # NEW: Encrypted storage implementation
bin/velum-credential         # NEW: Credential CLI
lib/providers/mullvad.sh     # MODIFY: Use credential API
lib/providers/ivpn.sh        # MODIFY: Use credential API
bin/velum-config             # MODIFY: Use credential API
bin/velum-connect            # MODIFY: Use credential API
lib/velum-security.sh        # MODIFY: Remove plaintext token functions
lib/velum-core.sh            # MODIFY: Update paths for new storage
```

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

### A.2 Encryption (AES-256-GCM)

```bash
# Encrypt:
nonce=$(openssl rand 12)
echo -n "$nonce" > output.enc
echo -n "$plaintext" | openssl enc -aes-256-gcm -K "$key_hex" -iv "$nonce_hex" >> output.enc

# Decrypt:
nonce=$(head -c 12 input.enc)
tail -c +13 input.enc | openssl enc -d -aes-256-gcm -K "$key_hex" -iv "$nonce_hex"
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

---

*End of Specification - Security-Critical Document*
