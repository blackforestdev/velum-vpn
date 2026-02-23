# Velum Tokenizer Subsystem Specification

**Version:** 0.2.2
**Status:** Design
**Last Updated:** 2026-01-27
**Depends On:** None
**Required By:** None
**Last Audit:** 2026-01-27 (naming conventions, operational terminology)

---

## Table of Contents

1. [Overview & Goals](#1-overview--goals)
2. [Architecture](#2-architecture)
3. [Token Storage](#3-token-storage)
4. [Tokenizer Library](#4-tokenizer-library)
5. [CLI Interface](#5-cli-interface)
6. [Configuration](#6-configuration)
7. [Integration Points](#7-integration-points)
8. [Security Model](#8-security-model)
9. [Migration](#9-migration)
10. [Implementation Plan](#10-implementation-plan)

---

## 1. Overview & Goals

### 1.1 Purpose

The tokenizer is an independent subsystem responsible for managing authentication tokens across all supported VPN providers. It provides:

- Token lifecycle management (create, refresh, expire, delete)
- Health monitoring (valid, expiring, expired status)
- Multi-account support per vendor
- Secure credential storage
- Configurable auto-refresh behavior

### 1.2 Design Principles

| Principle | Description |
|-----------|-------------|
| **Security First** | Secure storage, no credential leakage, proper permissions |
| **Explicit Network Consent** | No network calls without user awareness; configurable consent model |
| **Separation of Concerns** | Independent from config wizard; used as tooling |
| **Vendor Parity** | Identical features for all supported vendors |
| **User Control** | Configurable behavior, no surprises, no silent operations |
| **Multi-Account** | Support users with multiple accounts per vendor |
| **Real User Context** | Always operate as real user, never as root for token storage |

### 1.3 Supported Vendors

| Vendor | Auth Type | Token Lifetime | Account Storage |
|--------|-----------|----------------|-----------------|
| **Mullvad** | Account number (16 digits) | ~Days | Persistent |
| **IVPN** | Account ID (i-XXXX-XXXX-XXXX) | ~Days | Persistent |

**Note:** Only account-number-based providers are supported.

### 1.4 Relationship to Other Components

```
┌─────────────────────────────────────────────────────────────────┐
│                        User Commands                             │
├─────────────────┬─────────────────┬─────────────────────────────┤
│  velum config   │  velum connect  │  velum token                │
└────────┬────────┴────────┬────────┴──────────────┬──────────────┘
         │                 │                       │
         │    Uses         │    Uses               │  Direct
         │                 │                       │
         ▼                 ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                   TOKENIZER SUBSYSTEM                            │
│                   lib/velum-tokenizer.sh                         │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │ Token       │  │ Account     │  │ Health      │              │
│  │ Management  │  │ Management  │  │ Monitoring  │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                   TOKEN STORAGE                                  │
│                   ~/.config/velum/tokens/                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Architecture

### 2.1 Component Overview

| Component | Location | Purpose |
|-----------|----------|---------|
| Tokenizer Library | `lib/velum-tokenizer.sh` | Core token management functions |
| Token CLI | `bin/velum-token` | User-facing token commands |
| Token Storage | `~/.config/velum/tokens/` | Persistent token/account storage |
| Tokenizer Config | `~/.config/velum/tokenizer.conf` | User preferences |

### 2.2 Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  Token Lifecycle                                                 │
│                                                                  │
│  1. Account Creation                                             │
│     User provides account ID → Stored in tokens/{vendor}/{name}/│
│                                                                  │
│  2. Token Acquisition                                            │
│     Account ID → Provider API → Token + Expiry → Stored         │
│                                                                  │
│  3. Token Usage                                                  │
│     velum-connect → Check status → Use if valid                 │
│                          │                                       │
│                          ▼                                       │
│                     Expired/Expiring?                            │
│                          │                                       │
│                    ┌─────┴─────┐                                │
│                    ▼           ▼                                │
│               Auto-refresh   Prompt user                        │
│               (if enabled)   (if confirm mode)                  │
│                                                                  │
│  4. Token Refresh                                                │
│     Stored Account ID → Provider API → New Token → Stored       │
│                                                                  │
│  5. Token Expiry                                                 │
│     Expired token → Refresh or block connection                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Token Storage

### 3.1 Directory Structure

```
~/.config/velum/
├── tokens/                           # Mode 700, user-owned
│   ├── mullvad/                      # Mullvad accounts
│   │   ├── default/                  # Default account
│   │   │   ├── account               # Account number (16 digits)
│   │   │   └── token                 # Line 1: token, Line 2: expiry
│   │   ├── secondary/                # Named account "secondary"
│   │   │   ├── account
│   │   │   └── token
│   │   └── eu_egress/                # Named account "eu_egress"
│   │       ├── account
│   │       └── token
│   │
│   ├── ivpn/                         # IVPN accounts
│   │   ├── default/                  # Default account
│   │   │   ├── account               # Account ID (i-XXXX-XXXX-XXXX)
│   │   │   └── token                 # Line 1: token, Line 2: expiry
│   │   ├── secondary/                # Named account "secondary"
│   │   │   ├── account
│   │   │   └── token
│   │   └── backup/                   # Named account "backup"
│   │       ├── account
│   │       └── token
│   │
│   └── wg_keys/                      # WireGuard keys (shared)
│       ├── default.key               # Single-hop private key
│       ├── entry.key                 # Multi-hop entry key
│       └── exit.key                  # Multi-hop exit key
│
├── tokenizer.conf                    # Tokenizer settings
└── profiles/                         # Profile configs (separate)
```

### 3.2 File Formats

**Account File:** `tokens/{vendor}/{account}/account`
```
1234567890123456
```
Single line containing the account identifier.

**Token File:** `tokens/{vendor}/{account}/token`
```
eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9...
1738160400
```
- Line 1: Access token (opaque string from provider)
- Line 2: Expiry timestamp as **Unix epoch seconds** (integer)

**Rationale:** Epoch seconds are locale-independent, timezone-agnostic, and trivially parseable across macOS/Linux. Human-readable format is generated only for display.

**WireGuard Key File:** `tokens/wg_keys/{name}.key`
```
cPrivateKeyBase64Here=
```
Single line containing WireGuard private key.

### 3.3 Permissions

| Path | Mode | Owner |
|------|------|-------|
| `~/.config/velum/tokens/` | 700 | User |
| `~/.config/velum/tokens/{vendor}/` | 700 | User |
| `~/.config/velum/tokens/{vendor}/{account}/` | 700 | User |
| `~/.config/velum/tokens/{vendor}/{account}/account` | 600 | User |
| `~/.config/velum/tokens/{vendor}/{account}/token` | 600 | User |
| `~/.config/velum/tokens/wg_keys/` | 700 | User |
| `~/.config/velum/tokens/wg_keys/*.key` | 600 | User |

### 3.4 Account Naming Rules

| Rule | Constraint |
|------|------------|
| Characters | Lowercase alphanumeric, underscore, hyphen |
| Length | 1-32 characters |
| Reserved | `default` is the default account name |
| Start | Must start with letter |
| No dots | Prevents path traversal |

**Valid examples:**
- `default` - primary account
- `secondary`, `backup` - redundant accounts
- `eu_egress`, `us_ops` - jurisdictional separation
- `alpha`, `bravo` - phonetic identifiers
- `acct-01`, `acct-02` - numbered accounts

**Invalid:** `Primary` (uppercase), `my.account` (dot), `123acct` (starts with number)

**Naming Convention Rationale:** Account names should reflect operational purpose, not personal context. Velum is a security-focused tool; naming should communicate threat model separation, jurisdictional requirements, or operational redundancy—not consumer use patterns.

---

## 4. Tokenizer Library

### 4.1 File Location

`lib/velum-tokenizer.sh`

### 4.2 Core Functions

```bash
# ============================================================================
# PATH HELPERS
# ============================================================================

# Validate vendor + account input before path usage
# Usage: _validate_vendor_account mullvad secondary
_validate_vendor_account() {
  local vendor="$1"
  local account="${2:-default}"

  token_vendor_supported "$vendor" || return 1
  [[ "$account" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || return 1

  return 0
}

# Get base path for vendor
# Usage: _vendor_path mullvad
_vendor_path() {
  local vendor="$1"
  echo "${VELUM_TOKENS_DIR}/${vendor}"
}

# Get path for specific account
# Usage: _account_path mullvad secondary
_account_path() {
  local vendor="$1"
  local account="${2:-default}"
  echo "${VELUM_TOKENS_DIR}/${vendor}/${account}"
}

# Get account file path
# Usage: _account_file mullvad secondary
_account_file() {
  echo "$(_account_path "$1" "$2")/account"
}

# Get token file path
# Usage: _token_file mullvad secondary
_token_file() {
  echo "$(_account_path "$1" "$2")/token"
}

# ============================================================================
# ACCOUNT MANAGEMENT
# ============================================================================

# Check if vendor is supported
# Usage: token_vendor_supported mullvad
token_vendor_supported() {
  local vendor="$1"
  [[ "$vendor" == "mullvad" || "$vendor" == "ivpn" ]]
}

# Check if account exists
# Usage: token_account_exists mullvad secondary
token_account_exists() {
  local vendor="$1"
  local account="${2:-default}"
  _validate_vendor_account "$vendor" "$account" || return 1
  [[ -f "$(_account_file "$vendor" "$account")" ]]
}

# List all accounts for a vendor
# Usage: token_list_accounts mullvad
token_list_accounts() {
  local vendor="$1"
  local vendor_dir="$(_vendor_path "$vendor")"

  [[ ! -d "$vendor_dir" ]] && return 0

  find "$vendor_dir" -mindepth 1 -maxdepth 1 -type d \
    -exec basename {} \; 2>/dev/null | sort
}

# List all vendors with accounts
# Usage: token_list_vendors
token_list_vendors() {
  local tokens_dir="$VELUM_TOKENS_DIR"

  for vendor in mullvad ivpn; do
    [[ -d "${tokens_dir}/${vendor}" ]] && echo "$vendor"
  done
}

# Add new account
# Usage: token_add_account mullvad secondary "1234567890123456"
token_add_account() {
  local vendor="$1"
  local account="$2"
  local account_id="$3"

  # Validate vendor
  token_vendor_supported "$vendor" || {
    log_error "Unsupported vendor: $vendor"
    return 1
  }

  # Validate account name
  [[ ! "$account" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] && {
    log_error "Invalid account name: $account"
    return 1
  }

  # Validate account ID format (vendor-specific)
  _validate_account_format "$vendor" "$account_id" || {
    log_error "Invalid account ID format for $vendor"
    return 1
  }

  # Create directory structure
  local account_dir="$(_account_path "$vendor" "$account")"
  mkdir -p "$account_dir"
  chmod 700 "$account_dir"

  # Write account file
  local account_file="$(_account_file "$vendor" "$account")"
  (
    umask 077
    printf '%s\n' "$account_id" > "$account_file"
  )
  chmod 600 "$account_file"

  # Fix ownership for sudo
  _fix_token_ownership "$account_dir"

  return 0
}

# Remove account
# Usage: token_remove_account mullvad secondary
token_remove_account() {
  local vendor="$1"
  local account="${2:-default}"

  local account_dir="$(_account_path "$vendor" "$account")"

  [[ ! -d "$account_dir" ]] && {
    log_error "Account not found: $vendor/$account"
    return 1
  }

  # Secure delete
  local account_file="$(_account_file "$vendor" "$account")"
  local token_file="$(_token_file "$vendor" "$account")"

  [[ -f "$account_file" ]] && shred -u "$account_file" 2>/dev/null || rm -f "$account_file"
  [[ -f "$token_file" ]] && shred -u "$token_file" 2>/dev/null || rm -f "$token_file"
  rmdir "$account_dir" 2>/dev/null

  return 0
}

# Get stored account ID
# Usage: token_get_account_id mullvad secondary
token_get_account_id() {
  local vendor="$1"
  local account="${2:-default}"
  _validate_vendor_account "$vendor" "$account" || return 1
  local account_file="$(_account_file "$vendor" "$account")"

  [[ -f "$account_file" ]] && cat "$account_file" 2>/dev/null
}

# ============================================================================
# TOKEN STATUS
# ============================================================================

# Get token status
# Returns: valid | expiring | expired | missing
# Exit codes: 0=valid, 1=missing, 2=expired, 3=expiring
# Usage: token_status mullvad secondary
token_status() {
  local vendor="$1"
  local account="${2:-default}"
  _validate_vendor_account "$vendor" "$account" || {
    echo "missing"
    return 1
  }
  local token_file="$(_token_file "$vendor" "$account")"

  # Check if token file exists
  [[ ! -f "$token_file" ]] && {
    echo "missing"
    return 1
  }

  # Read expiry (stored as epoch seconds - locale/timezone independent)
  local expiry_epoch now_epoch
  expiry_epoch=$(sed -n '2p' "$token_file" 2>/dev/null)

  # Validate expiry is numeric
  [[ ! "$expiry_epoch" =~ ^[0-9]+$ ]] && {
    echo "missing"
    return 1
  }

  now_epoch=$(date +%s)

  # Check if expired
  if [[ "$expiry_epoch" -le "$now_epoch" ]]; then
    echo "expired"
    return 2
  fi

  # Check if expiring soon
  local threshold_seconds
  threshold_seconds=$(_get_expiry_threshold_seconds)

  if [[ "$((expiry_epoch - now_epoch))" -lt "$threshold_seconds" ]]; then
    echo "expiring"
    return 3
  fi

  echo "valid"
  return 0
}

# Get token expiry as epoch seconds
# Usage: token_get_expiry mullvad secondary
token_get_expiry() {
  local vendor="$1"
  local account="${2:-default}"
  _validate_vendor_account "$vendor" "$account" || return 1
  local token_file="$(_token_file "$vendor" "$account")"

  [[ -f "$token_file" ]] && sed -n '2p' "$token_file" 2>/dev/null
}

# Get expiry as formatted date string (for display only)
# Usage: token_get_expiry_formatted mullvad secondary
token_get_expiry_formatted() {
  local vendor="$1"
  local account="${2:-default}"
  local expiry_epoch
  expiry_epoch=$(token_get_expiry "$vendor" "$account")

  [[ ! "$expiry_epoch" =~ ^[0-9]+$ ]] && echo "N/A" && return

  # Format for display (locale-aware output is fine here)
  if [[ "$OSTYPE" == "darwin"* ]]; then
    date -r "$expiry_epoch" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "N/A"
  else
    date -d "@$expiry_epoch" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "N/A"
  fi
}

# Get time until expiry (human readable)
# Usage: token_get_expiry_human mullvad secondary
token_get_expiry_human() {
  local vendor="$1"
  local account="${2:-default}"
  local expiry_epoch now_epoch diff

  expiry_epoch=$(token_get_expiry "$vendor" "$account")

  [[ ! "$expiry_epoch" =~ ^[0-9]+$ ]] && echo "N/A" && return

  now_epoch=$(date +%s)
  diff=$((expiry_epoch - now_epoch))

  if [[ "$diff" -lt 0 ]]; then
    echo "EXPIRED"
  elif [[ "$diff" -lt 3600 ]]; then
    echo "$((diff / 60)) minutes"
  elif [[ "$diff" -lt 86400 ]]; then
    echo "$((diff / 3600)) hours"
  else
    echo "$((diff / 86400)) days"
  fi
}

# Get stored token
# Usage: token_get_token mullvad secondary
token_get_token() {
  local vendor="$1"
  local account="${2:-default}"
  _validate_vendor_account "$vendor" "$account" || return 1
  local token_file="$(_token_file "$vendor" "$account")"

  [[ -f "$token_file" ]] && sed -n '1p' "$token_file" 2>/dev/null
}

# ============================================================================
# TOKEN REFRESH
# ============================================================================

# Check if token needs refresh based on auto_refresh_threshold
# Returns: 0=needs refresh, 1=still valid
# This is SEPARATE from token_status "expiring" which uses expiry_warning_threshold
# Usage: token_needs_refresh mullvad secondary
token_needs_refresh() {
  local vendor="$1"
  local account="${2:-default}"
  local token_file="$(_token_file "$vendor" "$account")"

  [[ ! -f "$token_file" ]] && return 0  # missing = needs refresh

  local expiry_epoch now_epoch
  expiry_epoch=$(sed -n '2p' "$token_file" 2>/dev/null)
  [[ ! "$expiry_epoch" =~ ^[0-9]+$ ]] && return 0  # invalid = needs refresh

  now_epoch=$(date +%s)

  # Already expired
  [[ "$expiry_epoch" -le "$now_epoch" ]] && return 0

  # Within auto-refresh threshold
  local threshold_seconds
  threshold_seconds=$(_get_auto_refresh_threshold_seconds)

  [[ "$((expiry_epoch - now_epoch))" -lt "$threshold_seconds" ]]
}

# Refresh token for account
# Usage: token_refresh mullvad secondary [--force]
token_refresh() {
  local vendor="$1"
  local account="${2:-default}"
  local force="${3:-}"

  # Check if refresh needed (unless forced)
  if [[ "$force" != "--force" ]]; then
    local status
    status=$(token_status "$vendor" "$account")
    [[ "$status" == "valid" ]] && {
      log_debug "Token still valid, skipping refresh"
      return 0
    }
  fi

  # Get stored account ID
  local account_id
  account_id=$(token_get_account_id "$vendor" "$account")

  [[ -z "$account_id" ]] && {
    log_error "No account ID stored for $vendor/$account"
    return 1
  }

  # Load provider module
  load_provider "$vendor" || {
    log_error "Failed to load provider: $vendor"
    return 1
  }

  # Authenticate (provider saves token automatically)
  log_info "Refreshing $vendor/$account token..."

  if provider_authenticate "$account_id" "" >/dev/null 2>&1; then
    # Move token to correct location if provider saved elsewhere
    _relocate_token_if_needed "$vendor" "$account"
    log_info "Token refreshed successfully"
    return 0
  else
    log_error "Failed to refresh token"
    return 1
  fi
}

# Auto-refresh with user preference handling
# Usage: token_auto_refresh mullvad secondary
# Auto-refresh with user consent handling
# SECURITY: Network calls require explicit or configured consent
# Usage: token_auto_refresh mullvad secondary [--non-interactive]
token_auto_refresh() {
  local vendor="$1"
  local account="${2:-default}"
  local non_interactive="${3:-}"

  local behavior
  behavior=$(_get_refresh_behavior)

  # In non-interactive mode (scripts, cron), only silent mode proceeds
  # This prevents hanging on confirmation prompts
  if [[ "$non_interactive" == "--non-interactive" ]]; then
    if [[ "$behavior" -ne 2 ]]; then
      log_warn "Token refresh skipped: non-interactive mode requires silent refresh"
      log_warn "Set auto_refresh_behavior=2 to enable non-interactive refresh"
      return 1
    fi
    token_refresh "$vendor" "$account"
    return $?
  fi

  case "$behavior" in
    0)  # confirm - explicit consent required for network call
      echo
      print_warn "Token for $vendor/$account has expired or is expiring soon."
      print_info "Refresh requires network connection to $vendor API."
      if ask_yn "Refresh token now?" "y"; then
        token_refresh "$vendor" "$account"
        return $?
      else
        print_info "Token refresh declined. Connection may fail."
        return 1
      fi
      ;;
    1)  # notify - proceed with notification
      print_info "Refreshing $vendor/$account token (connecting to $vendor API)..."
      if token_refresh "$vendor" "$account"; then
        print_ok "Token refreshed successfully."
        return 0
      else
        print_error "Token refresh failed."
        return 1
      fi
      ;;
    2)  # silent - proceed without notification
      # Note: Silent mode should only be enabled by explicit user configuration
      token_refresh "$vendor" "$account"
      return $?
      ;;
  esac
}

# Refresh all expired/expiring tokens
# Usage: token_refresh_all [--force]
token_refresh_all() {
  local force="${1:-}"
  local refreshed=0
  local failed=0

  for vendor in $(token_list_vendors); do
    for account in $(token_list_accounts "$vendor"); do
      local status
      status=$(token_status "$vendor" "$account")

      if [[ "$status" == "expired" || "$status" == "expiring" || "$force" == "--force" ]]; then
        if token_refresh "$vendor" "$account" "$force"; then
          ((refreshed++))
        else
          ((failed++))
        fi
      fi
    done
  done

  echo "Refreshed: $refreshed, Failed: $failed"
  [[ "$failed" -eq 0 ]]
}

# ============================================================================
# CONFIGURATION HELPERS
# ============================================================================

# Tokenizer config uses safe_load_config with TOKENIZER[] allowlist
# This is loaded once at tokenizer init and cached

declare -A _TOKENIZER_CONFIG=()
_TOKENIZER_CONFIG_LOADED=0

# Load tokenizer config using safe parser
# MUST use safe_load_config - no grep|sed on untrusted input
_load_tokenizer_config() {
  [[ "$_TOKENIZER_CONFIG_LOADED" -eq 1 ]] && return 0

  local config_file="${VELUM_CONFIG_DIR}/tokenizer.conf"

  if [[ -f "$config_file" ]]; then
    # Use safe parser with strict allowlist
    # Only TOKENIZER[...] keys are permitted
    if safe_load_config "$config_file" --strict --arrays "TOKENIZER"; then
      # Copy parsed values to local cache
      for key in "${!TOKENIZER[@]}"; do
        _TOKENIZER_CONFIG["$key"]="${TOKENIZER[$key]}"
      done
    else
      log_warn "Failed to parse tokenizer.conf, using defaults"
    fi
  fi

  _TOKENIZER_CONFIG_LOADED=1
}

# Get refresh behavior setting
# Returns: 0=confirm, 1=notify, 2=silent
_get_refresh_behavior() {
  _load_tokenizer_config

  local value="${_TOKENIZER_CONFIG[auto_refresh_behavior]:-1}"

  case "$value" in
    0|confirm) echo 0 ;;
    1|notify)  echo 1 ;;
    2|silent)  echo 2 ;;
    *)         echo 1 ;;  # default: notify
  esac
}

# Get expiry WARNING threshold in seconds (for status display)
# Used by token_status to determine "expiring" status
_get_expiry_threshold_seconds() {
  _load_tokenizer_config

  local value="${_TOKENIZER_CONFIG[expiry_warning_threshold]:-24h}"
  _parse_duration "$value" 86400
}

# Get auto-refresh threshold in seconds (for connect-time refresh)
# Used by token_auto_refresh to decide when to refresh on connect
_get_auto_refresh_threshold_seconds() {
  _load_tokenizer_config

  local value="${_TOKENIZER_CONFIG[auto_refresh_threshold]:-24h}"
  _parse_duration "$value" 86400
}

# Parse duration string to seconds
# Usage: _parse_duration "24h" [default]
_parse_duration() {
  local value="$1"
  local default="${2:-86400}"

  # Validate format before arithmetic
  case "$value" in
    [0-9]*h) echo $(( ${value%h} * 3600 )) ;;
    [0-9]*d) echo $(( ${value%d} * 86400 )) ;;
    [0-9]*m) echo $(( ${value%m} * 60 )) ;;
    *)       echo "$default" ;;
  esac
}

# Check if network operations require explicit consent
# Returns: 0=network allowed, 1=network requires confirmation
_network_requires_consent() {
  _load_tokenizer_config

  local behavior
  behavior=$(_get_refresh_behavior)

  # In confirm mode (0), network always requires consent
  # In notify mode (1), network allowed with notification
  # In silent mode (2), network allowed silently
  [[ "$behavior" -eq 0 ]]
}

# ============================================================================
# INTERNAL HELPERS
# ============================================================================

# Fix ownership for sudo operations
_fix_token_ownership() {
  local path="$1"

  if [[ -n "${SUDO_USER:-}" ]]; then
    local sudo_uid sudo_gid
    sudo_uid=$(id -u "$SUDO_USER" 2>/dev/null)
    sudo_gid=$(id -g "$SUDO_USER" 2>/dev/null)

    if [[ -n "$sudo_uid" && -n "$sudo_gid" ]]; then
      chown -R "$sudo_uid:$sudo_gid" "$path" 2>/dev/null || true
    fi
  fi
}

# Relocate token if provider saved to legacy location
_relocate_token_if_needed() {
  local vendor="$1"
  local account="${2:-default}"

  # Legacy locations
  local legacy_token="${VELUM_TOKENS_DIR}/${vendor}_token"
  local legacy_account="${VELUM_TOKENS_DIR}/${vendor}_account"

  local new_dir="$(_account_path "$vendor" "$account")"
  local new_token="$(_token_file "$vendor" "$account")"
  local new_account="$(_account_file "$vendor" "$account")"

  # Create directory if needed
  mkdir -p "$new_dir"
  chmod 700 "$new_dir"

  # Move token if saved to legacy location
  if [[ -f "$legacy_token" && ! -f "$new_token" ]]; then
    mv "$legacy_token" "$new_token"
    chmod 600 "$new_token"
  fi

  # Move account if saved to legacy location
  if [[ -f "$legacy_account" && ! -f "$new_account" ]]; then
    mv "$legacy_account" "$new_account"
    chmod 600 "$new_account"
  fi

  _fix_token_ownership "$new_dir"
}
```

---

## 5. CLI Interface

### 5.1 Command Structure

```
velum token <subcommand> [options]

Subcommands:
  status    Show token status for all or specific vendor/account
  add       Add a new account
  remove    Remove an account
  refresh   Refresh tokens
  config    Show or set tokenizer configuration
```

### 5.2 Command Details

**`velum token status`**
```bash
velum token status                    # All vendors and accounts
velum token status mullvad            # All Mullvad accounts
velum token status mullvad default    # Specific account
velum token status --json             # JSON output for scripting
```

**`velum token add`**
```bash
velum token add mullvad                      # Add default account (interactive)
velum token add mullvad --name secondary     # Add named account (interactive)
velum token add ivpn --name eu_egress        # Add IVPN named account
```
**Note:** Account ID input is masked (not echoed) for security. Account IDs grant full account access and are treated as sensitive credentials.

**`velum token remove`**
```bash
velum token remove mullvad --name secondary  # Remove named account
velum token remove ivpn --name backup        # Remove IVPN account
# Note: Cannot remove 'default' if it's the only account
```

**`velum token refresh`**
```bash
velum token refresh                          # Refresh all expired/expiring
velum token refresh mullvad                  # Refresh Mullvad default
velum token refresh mullvad --name secondary # Refresh specific account
velum token refresh --all                    # Refresh all (even valid)
velum token refresh --force                  # Force refresh (even valid)
```

**`velum token config`**
```bash
velum token config                       # Show current settings
velum token config --set auto_refresh_behavior=notify
velum token config --set expiry_warning_threshold=48h
velum token config --reset               # Reset to defaults
```

### 5.3 Example Output

```
$ velum token status

MULLVAD
───────────────────────────────────────────────────────────────
  Account     Status      Expires              Time Left
  default     ✓ Valid     2026-01-29 14:30     2 days
  secondary   ⚠ Expiring  2026-01-28 09:00     12 hours

IVPN
───────────────────────────────────────────────────────────────
  Account     Status      Expires              Time Left
  default     ✓ Valid     2026-02-15 09:00     19 days
  backup      ✗ Expired   2026-01-26 18:00     -1 day

SETTINGS
───────────────────────────────────────────────────────────────
  Auto-refresh behavior:     notify
  Expiry warning threshold:  24h

⚠ 1 token expiring soon, 1 token expired.
Run 'velum token refresh' to refresh.
```

---

## 6. Configuration

### 6.1 Configuration File

**Location:** `~/.config/velum/tokenizer.conf`

```bash
# Velum Tokenizer Configuration
# Generated: 2026-01-27

# Auto-refresh behavior when token is expired/expiring
# 0 = confirm (ask user before refresh)
# 1 = notify  (refresh and show message)
# 2 = silent  (refresh without notification)
TOKENIZER[auto_refresh_behavior]="1"

# Threshold for "expiring soon" warning
# Tokens expiring within this window show warning
# Format: Nh (hours), Nd (days), Nm (minutes)
TOKENIZER[expiry_warning_threshold]="24h"

# Auto-refresh threshold
# Tokens expiring within this window auto-refresh on connect
# (Only applies when auto_refresh_behavior != 0)
TOKENIZER[auto_refresh_threshold]="24h"
```

### 6.2 Default Values

| Setting | Default | Description |
|---------|---------|-------------|
| `auto_refresh_behavior` | `1` (notify) | Refresh and notify user |
| `expiry_warning_threshold` | `24h` | Warn if expiring within 24 hours |
| `auto_refresh_threshold` | `24h` | Auto-refresh if expiring within 24 hours |

### 6.3 Configuration Parsing

Tokenizer config uses safe parsing: no `source`, regex-based, strict key whitelist.

**On parse failure:** Falls back to safe defaults (notify mode, 24h thresholds). Tokenizer config is non-critical operational preference, so safe defaults are acceptable. This differs from profile parsing which is fail-closed since profiles control connection behavior.

**Rationale:** A user with a malformed `tokenizer.conf` should still be able to connect; they just get conservative defaults (explicit consent for refresh).

---

## 7. Integration Points

### 7.1 Integration with velum-connect

```bash
# In velum-connect, before establishing connection:

source "$VELUM_ROOT/lib/velum-tokenizer.sh"

# Get provider and account from profile
provider="${CONFIG[provider]}"
account="${PROFILE[account]:-default}"

# First check if token exists
status=$(token_status "$provider" "$account")

if [[ "$status" == "missing" ]]; then
  print_error "No token found for $provider/$account"
  print_error "Run: velum token add $provider"
  [[ "$account" != "default" ]] && \
    print_error "     --name $account"
  exit 1
fi

# Note: Missing tokens are fatal. Refresh logic only applies when a token exists.

# Check if refresh needed using auto_refresh_threshold
# (This is separate from expiry_warning_threshold used for display)
if token_needs_refresh "$provider" "$account"; then
  log_info "Token needs refresh for $provider/$account (status: $status)"
  # Detect non-interactive context for consent handling
  non_interactive=""
  [[ ! -t 0 ]] && non_interactive="--non-interactive"

  token_auto_refresh "$provider" "$account" "$non_interactive" || {
    if [[ "$status" == "expired" ]]; then
      print_error "Cannot connect: token expired and refresh failed"
      exit 1
    else
      print_warn "Token refresh failed, attempting connection with existing token"
    fi
  }
fi

# Get the valid token for API calls
TOKEN=$(token_get_token "$provider" "$account")
```

**Threshold Distinction:**
- `expiry_warning_threshold`: Used by `token_status` to return "expiring" for display/warnings
- `auto_refresh_threshold`: Used by `token_needs_refresh` to decide when to refresh on connect

Both default to 24h but can be configured independently (e.g., warn at 48h, refresh at 12h).

### 7.2 Integration with velum-config

```bash
# In phase_authentication():

source "$VELUM_ROOT/lib/velum-tokenizer.sh"

provider="${CONFIG[provider]}"

# List existing accounts for this provider
accounts=$(token_list_accounts "$provider")

if [[ -n "$accounts" ]]; then
  print_section "EXISTING ACCOUNTS"

  echo "Found existing $provider accounts:"
  echo

  local options=()
  local i=1

  while IFS= read -r acc; do
    local status expiry_human
    status=$(token_status "$provider" "$acc")
    expiry_human=$(token_get_expiry_human "$provider" "$acc")

    local status_icon
    case "$status" in
      valid)    status_icon="✓" ;;
      expiring) status_icon="⚠" ;;
      expired)  status_icon="✗" ;;
      *)        status_icon="?" ;;
    esac

    printf "  %d. %s (%s %s, %s)\n" "$i" "$acc" "$status_icon" "$status" "$expiry_human"
    options+=("$acc")
    ((i++))
  done <<< "$accounts"

  echo "  $i. Add new account"
  echo

  local choice
  read -r -p "Select account [1-$i]: " choice

  if [[ "$choice" == "$i" ]]; then
    # Add new account flow
    _add_new_account "$provider"
  elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -lt "$i" ]]; then
    # Use existing account
    local selected="${options[$((choice-1))]}"
    PROFILE[account]="$selected"

    # Check if token needs refresh
    local status
    status=$(token_status "$provider" "$selected")
    if [[ "$status" != "valid" ]]; then
      if ask_yn "Token is $status. Refresh now?" "y"; then
        token_refresh "$provider" "$selected"
      fi
    fi
  fi
else
  # No accounts, must add one
  _add_new_account "$provider"
fi
```

### 7.3 Integration with Profiles

```bash
# Profile file format with account reference:

PROFILE[type]="standard"
PROFILE[name]="mullvad_eu_brussels"
PROFILE[provider]="mullvad"
PROFILE[account]="secondary"         # References mullvad/secondary/

CONFIG[selected_region]="be-bru"
CONFIG[selected_ip]="185.213.154.68"
# ... rest of config
```

### 7.4 Integration with Multi-Hop

```bash
# Multi-hop profile with different accounts:

PROFILE[type]="multihop"
PROFILE[name]="cross_jurisdiction"

ENTRY[provider]="mullvad"
ENTRY[account]="eu_egress"           # Uses mullvad/eu_egress/

EXIT[provider]="ivpn"
EXIT[account]="default"              # Uses ivpn/default/

CONFIG[killswitch]="true"
```

At connect time, velum-connect validates BOTH tokens:
```bash
# Check entry token
entry_status=$(token_status "${ENTRY[provider]}" "${ENTRY[account]:-default}")
# Check exit token
exit_status=$(token_status "${EXIT[provider]}" "${EXIT[account]:-default}")

# Both must be valid (or refreshable) to proceed
```

---

## 8. Security Model

### 8.1 Credential Protection

| Asset | Protection |
|-------|------------|
| Account IDs | File mode 600, user-owned |
| Tokens | File mode 600, user-owned |
| WireGuard keys | File mode 600, user-owned |
| Directories | Mode 700, user-owned |

### 8.2 Secure Deletion

When removing accounts, use best-effort secure deletion:
```bash
# Best-effort secure deletion
# Note: shred is unreliable on journaling filesystems and SSDs
# This is defense-in-depth, not guaranteed secure erasure
if command -v shred >/dev/null 2>&1; then
  shred -u "$file" 2>/dev/null || rm -f "$file"
else
  rm -f "$file"
fi

# ALSO clear in-memory variables
unset account_id token
```

**Limitations:** On modern SSDs with wear-leveling and journaling filesystems, secure deletion is not guaranteed. This is best-effort only. For high-security scenarios, recommend full-disk encryption.

### 8.3 No Credential Leakage

- Account IDs never logged (even in debug mode)
- Tokens never logged
- Clear sensitive variables immediately after use with `unset`

### 8.4 Masked Input for Account IDs

Account IDs are treated as sensitive credentials (possession = account access). All interactive input MUST be masked:

```bash
# In velum token add:
# ALWAYS use masked input for account IDs
echo "Enter your Mullvad account number (16 digits)."
echo "Input will be hidden for security."

# Use ask_password (not ask_input) - no echo
account_id=$(ask_password "Account ID")

# Validate format BEFORE storing
if ! _validate_account_format "$vendor" "$account_id"; then
  print_error "Invalid account ID format"
  unset account_id
  exit 1
fi
```

### 8.5 Path Validation

All path operations validate:
- No `..` in account names (prevents traversal)
- Account names match `^[a-z][a-z0-9_-]{0,31}$`
- Vendor names are whitelist-checked (`mullvad`, `ivpn`)
- Paths resolved with `realpath` and validated within allowed directory

### 8.6 Sudo and User Context Handling

**Critical Rule:** Tokenizer ALWAYS operates as the real user, never as root for token storage.

```bash
# At tokenizer init, determine real user
_init_user_context() {
  if [[ -n "${SUDO_USER:-}" ]]; then
    # Running under sudo - use real user
    VELUM_REAL_USER="$SUDO_USER"
    VELUM_REAL_HOME=$(_resolve_user_home_or_fail "$SUDO_USER") || exit 1
  else
    VELUM_REAL_USER="$USER"
    VELUM_REAL_HOME="$HOME"
  fi

  # Token directory is ALWAYS under real user's home
  VELUM_TOKENS_DIR="${VELUM_REAL_HOME}/.config/velum/tokens"
}

# Cross-platform home directory resolution
# macOS: no getent, use dscl or eval
# Linux: use getent
_get_user_home() {
  local user="$1"

  if [[ "$VELUM_OS" == "macos" ]]; then
    # macOS: dscl is the standard tool
    dscl . -read "/Users/$user" NFSHomeDirectory 2>/dev/null | awk '{print $2}'
  else
    # Linux: getent is standard
    getent passwd "$user" 2>/dev/null | cut -d: -f6
  fi
}

# Resolve home directory with fallback and hard failure if unknown
_resolve_user_home_or_fail() {
  local user="$1"
  local home

  home=$(_get_user_home "$user")
  [[ -z "$home" ]] && home=$(eval echo "~$user" 2>/dev/null)

  if [[ -z "$home" ]]; then
    print_error "Cannot determine home directory for user: $user"
    return 1
  fi

  echo "$home"
}

# File creation always sets correct ownership
_create_token_file() {
  local file="$1"
  local content="$2"

  # Write with restrictive umask
  (umask 077; printf '%s\n' "$content" > "$file")
  chmod 600 "$file"

  # MUST set ownership to real user if running as root
  if [[ "$(id -u)" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    chown "$SUDO_USER:$(id -g "$SUDO_USER")" "$file"
  fi
}
```

**Error Handling:**
```bash
# If running as root without SUDO_USER, refuse to operate on user tokens
if [[ "$(id -u)" -eq 0 && -z "${SUDO_USER:-}" ]]; then
  print_error "Cannot manage user tokens as root without SUDO_USER"
  print_error "Run as regular user or via 'sudo -E'"
  exit 1
fi
```

### 8.7 Network Consent Model

Token refresh requires network calls to provider APIs. The tokenizer enforces explicit consent:

| Mode | Behavior | Use Case |
|------|----------|----------|
| `confirm` (0) | Ask before any network call | High-security, paranoid |
| `notify` (1) | Proceed with notification | Default, balanced |
| `silent` (2) | Proceed without notification | Automation, scripts |

**Non-interactive contexts:** In non-interactive mode (no TTY), only `silent` mode proceeds. Other modes return error rather than hang.

```bash
# Detect non-interactive context
if [[ ! -t 0 ]]; then
  # No TTY - stdin is not a terminal
  NON_INTERACTIVE=1
fi

# In token_auto_refresh:
if [[ "$NON_INTERACTIVE" -eq 1 && "$behavior" -ne 2 ]]; then
  log_error "Token refresh requires interaction but running non-interactively"
  return 1
fi
```

### 8.8 Configuration Security

Tokenizer config (`tokenizer.conf`) uses the same safe parsing as all velum configs:
- No `source` command
- Regex-based parsing
- Strict key whitelist (`TOKENIZER[auto_refresh_behavior]`, `TOKENIZER[expiry_warning_threshold]`, etc.)
- Safe defaults on parse errors (see §6.3)

---

## 9. Migration

### 9.1 Migration from Legacy Structure

**Old structure:**
```
~/.config/velum/tokens/
├── mullvad_token
├── mullvad_account
├── ivpn_token
├── ivpn_account
└── wg_private_key
```

**New structure:**
```
~/.config/velum/tokens/
├── mullvad/
│   └── default/
│       ├── account
│       └── token
├── ivpn/
│   └── default/
│       ├── account
│       └── token
└── wg_keys/
    └── default.key
```

### 9.2 Migration Function

```bash
# In lib/velum-tokenizer.sh

token_migrate_legacy() {
  local tokens_dir="$VELUM_TOKENS_DIR"
  local migrated=0

  for vendor in mullvad ivpn; do
    local old_token="${tokens_dir}/${vendor}_token"
    local old_account="${tokens_dir}/${vendor}_account"
    local new_dir="${tokens_dir}/${vendor}/default"

    # Skip if already migrated
    [[ -d "$new_dir" ]] && continue

    # Skip if nothing to migrate
    [[ ! -f "$old_token" && ! -f "$old_account" ]] && continue

    # Create new structure
    mkdir -p "$new_dir"
    chmod 700 "$new_dir"

    # Move files
    [[ -f "$old_token" ]] && mv "$old_token" "$new_dir/token"
    [[ -f "$old_account" ]] && mv "$old_account" "$new_dir/account"

    # Set permissions
    chmod 600 "$new_dir"/* 2>/dev/null

    _fix_token_ownership "$new_dir"

    ((migrated++))
    log_info "Migrated $vendor tokens to new structure"
  done

  # Migrate WireGuard key
  local old_wg_key="${tokens_dir}/wg_private_key"
  local new_wg_dir="${tokens_dir}/wg_keys"

  if [[ -f "$old_wg_key" && ! -d "$new_wg_dir" ]]; then
    mkdir -p "$new_wg_dir"
    chmod 700 "$new_wg_dir"
    mv "$old_wg_key" "$new_wg_dir/default.key"
    chmod 600 "$new_wg_dir/default.key"
    _fix_token_ownership "$new_wg_dir"
    ((migrated++))
    log_info "Migrated WireGuard key to new structure"
  fi

  return 0
}
```

### 9.3 Migration Trigger

Migration runs automatically on first use of tokenizer:
```bash
# At top of lib/velum-tokenizer.sh

# Auto-migrate on load
if [[ -f "${VELUM_TOKENS_DIR}/mullvad_token" || \
      -f "${VELUM_TOKENS_DIR}/ivpn_token" ]]; then
  token_migrate_legacy
fi
```

---

## 10. Implementation Plan

### 10.1 Phase 1: Core Library

**Deliverables:**
- [ ] Create `lib/velum-tokenizer.sh`
- [ ] Implement path helpers
- [ ] Implement account management functions
- [ ] Implement token status functions
- [ ] Implement token refresh functions
- [ ] Implement configuration helpers
- [ ] Add migration function

**Testing:**
- Unit test each function
- Test migration from legacy structure
- Test multi-account scenarios

### 10.2 Phase 2: CLI Interface

**Deliverables:**
- [ ] Create `bin/velum-token`
- [ ] Implement `status` subcommand
- [ ] Implement `add` subcommand
- [ ] Implement `remove` subcommand
- [ ] Implement `refresh` subcommand
- [ ] Implement `config` subcommand
- [ ] Add to main `velum` dispatcher

**Testing:**
- Test each subcommand
- Test error handling
- Test output formatting

### 10.3 Phase 3: Integration

**Deliverables:**
- [ ] Integrate with `velum-connect`
- [ ] Integrate with `velum-config`
- [ ] Update profile format for account reference
- [ ] Update `velum-status` to show token info

**Testing:**
- End-to-end connection with token refresh
- Config wizard with existing accounts
- Multi-profile token sharing

### 10.4 Phase 4: Multi-Hop Integration

**Deliverables:**
- [ ] Support dual-token validation for multi-hop
- [ ] Refresh both tokens before multi-hop connection
- [ ] Handle partial token failure gracefully

---

## Appendix: Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.2.2-draft | 2026-01-27 | Naming convention overhaul: operational terminology (secondary, backup, eu_egress) replaces casual naming |
| 0.2.1-draft | 2026-01-27 | Final audit fixes: config parse policy clarified, auto_refresh_threshold implemented, macOS home resolution, CLI masking note |
| 0.2.0-draft | 2026-01-27 | Security audit fixes: epoch timestamps, safe config parsing, network consent model, masked input, sudo handling |
| 0.1.0-draft | 2026-01-27 | Initial specification |

---

*End of Specification - Living Document*
