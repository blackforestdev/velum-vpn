# Velum Named Profiles Specification

**Version:** 0.1.0
**Status:** Draft
**Last Updated:** 2026-01-30
**Depends On:** None
**Required By:** velum-multihop-spec.md

---

## Table of Contents

1. [Overview & Goals](#1-overview--goals)
2. [Directory Structure](#2-directory-structure)
3. [Profile Types](#3-profile-types)
4. [Profile File Format](#4-profile-file-format)
5. [Profile Naming Convention](#5-profile-naming-convention)
6. [Profile Parsing Security](#6-profile-parsing-security)
7. [Default Profile Handling](#7-default-profile-handling)
8. [CLI Commands](#8-cli-commands)
9. [Migration from Legacy Config](#9-migration-from-legacy-config)
10. [Implementation Plan](#10-implementation-plan)
11. [Nice-to-Haves](#11-nice-to-haves-postmvp)
12. [Open Questions](#12-open-questions)
13. [Appendices](#13-appendices)

---

## 1. Overview & Goals

### 1.1 Feature Description

Named profiles allow users to save multiple VPN configurations and switch between them by name. This replaces the current single-config model with a flexible multi-config system.

```
┌─────────────────────────────────────────────────────────────────┐
│  Current State (Single Config)                                  │
│                                                                 │
│  ~/.config/velum/velum.conf  ←── One config, one server         │
│                                                                 │
│  velum connect               ←── Always uses this config        │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  Proposed State (Named Profiles)                                │
│                                                                 │
│  ~/.config/velum/profiles/                                      │
│  ├── mullvad_sweden.conf     ←── Profile 1                      │
│  ├── mullvad_switzerland.conf ←── Profile 2                     │
│  ├── ivpn_romania.conf       ←── Profile 3                      │
│  └── work_vpn.conf           ←── Profile 4                      │
│                                                                 │
│  velum connect                    ←── Uses default profile      │
│  velum connect -p mullvad_sweden  ←── Uses named profile        │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Design Goals

| Priority | Goal | Rationale |
|----------|------|-----------|
| P0 | Security-first profile parsing | Profiles must not introduce code execution vectors |
| P0 | Backward compatibility | Existing single-config users must not break |
| P1 | Simple UX | Easy to create, list, switch, delete profiles |
| P1 | Foundation for multi-hop | Multi-hop requires referencing profiles by name |
| P2 | Portable profiles | Profiles should be self-contained and exportable |

### 1.3 Non-Goals (v1)

- Profile synchronization across devices
- Profile encryption (credentials use vault; profiles contain no secrets)
- Profile versioning/history
- GUI profile management

### 1.4 Use Cases

| Use Case | Description |
|----------|-------------|
| **Geographic switching** | User has profiles for different countries (streaming, privacy) |
| **Work/Personal separation** | Different VPN configs for different contexts |
| **Provider testing** | Compare Mullvad vs IVPN performance with saved configs |
| **Server pinning** | Save specific server configs that work well |
| **Multi-hop foundation** | Multi-hop profiles reference entry/exit profiles by name |

---

## 2. Directory Structure

### 2.1 User Configuration Directory

```
~/.config/velum/                    # User config root (mode 700)
├── velum.conf                      # DEPRECATED: Legacy config location
├── velum.conf.migrated             # Backup after migration
├── default_profile                 # Plain text: default profile name
├── profiles/                       # Profile storage (mode 700)
│   ├── mullvad_sweden.conf         # Standard profile (mode 600)
│   ├── mullvad_switzerland.conf    # Standard profile (mode 600)
│   ├── ivpn_romania.conf           # Standard profile (mode 600)
│   └── secure_route.conf           # Multi-hop profile (mode 600)
└── vault/                          # Encrypted credentials (existing)
    └── ...
```

### 2.2 Runtime Directory

```
$VELUM_RUN_DIR/                     # Runtime state (root-owned, mode 700)
├── active_profile                  # Currently connected profile name
├── connection_type                 # "standard" or "multihop"
└── ...                             # Other runtime state (unchanged)
```

**Path Values:**
- Linux: `$VELUM_RUN_DIR = /run/velum`
- macOS: `$VELUM_RUN_DIR = /var/run/velum`

### 2.3 Permission Requirements

| Path | Owner | Mode | Notes |
|------|-------|------|-------|
| `~/.config/velum/` | user | 700 | Config root |
| `~/.config/velum/profiles/` | user | 700 | Profile directory |
| `~/.config/velum/profiles/*.conf` | user | 600 | Individual profiles |
| `~/.config/velum/default_profile` | user | 600 | Default profile pointer |
| `$VELUM_RUN_DIR/` | root | 700 | Runtime state |
| `$VELUM_RUN_DIR/active_profile` | root | 600 | Active connection |

---

## 3. Profile Types

### 3.1 Standard Profile

A standard profile configures a single-hop VPN connection to one server.

```
┌─────────────────────────────────────────────────────────────────┐
│  Standard Profile                                               │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  PROFILE[type]="standard"                                │   │
│  │  PROFILE[name]="mullvad_sweden"                          │   │
│  │  PROFILE[provider]="mullvad"                             │   │
│  │                                                          │   │
│  │  CONFIG[selected_region]="se-sto"                        │   │
│  │  CONFIG[selected_ip]="..."                               │   │
│  │  CONFIG[killswitch]="true"                               │   │
│  │  ...                                                     │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Multi-Hop Profile (Future)

Multi-hop profiles are defined in `velum-multihop-spec.md`. They reference standard profiles by name:

```
PROFILE[type]="multihop"
ENTRY[profile]="mullvad_sweden"
EXIT[profile]="ivpn_romania"
```

This specification focuses on standard profiles. Multi-hop profile handling is deferred to the multi-hop implementation phase.

---

## 4. Profile File Format

### 4.1 File Structure

Profiles use a key-value format with namespaced arrays. This is NOT a bash script and must NOT be sourced.

```bash
# Velum VPN Profile
# Type: standard
# Created: 2026-01-30T14:30:00Z
# Provider: mullvad

# ============================================================================
# PROFILE METADATA
# ============================================================================

PROFILE[type]="standard"
PROFILE[name]="mullvad_sweden"
PROFILE[provider]="mullvad"
PROFILE[created]="2026-01-30T14:30:00Z"
PROFILE[description]="Sweden - Stockholm, low latency"

# ============================================================================
# SERVER CONFIGURATION
# ============================================================================

CONFIG[selected_region]="se-sto"
CONFIG[selected_ip]="185.213.154.68"
CONFIG[selected_hostname]="se-sto-wg-001"
CONFIG[selected_name]="Sweden - Stockholm"
CONFIG[selected_country_code]="SE"

# ============================================================================
# SECURITY SETTINGS
# ============================================================================

CONFIG[killswitch]="true"
CONFIG[killswitch_lan]="false"
CONFIG[ipv6_disabled]="true"

# ============================================================================
# DNS SETTINGS
# ============================================================================

CONFIG[use_provider_dns]="true"
CONFIG[custom_dns]=""

# ============================================================================
# PROVIDER-SPECIFIC SETTINGS
# ============================================================================

CONFIG[port_forward]="false"
CONFIG[dip_enabled]="false"
```

### 4.2 Allowed Arrays

Only these array names are permitted:

| Array | Purpose | Required |
|-------|---------|----------|
| `PROFILE` | Profile metadata | Yes |
| `CONFIG` | Connection configuration | Yes |
| `ENTRY` | Multi-hop entry (future) | No |
| `EXIT` | Multi-hop exit (future) | No |

### 4.3 Required Keys

**PROFILE array (required):**

| Key | Type | Description |
|-----|------|-------------|
| `type` | string | `"standard"` or `"multihop"` |
| `name` | string | Profile identifier (matches filename without .conf) |
| `provider` | string | Provider name (`mullvad`, `ivpn`, `pia`) |
| `created` | string | ISO8601 timestamp |

**PROFILE array (optional):**

| Key | Type | Description |
|-----|------|-------------|
| `description` | string | User-provided description |
| `latency_ms` | integer | Last measured latency (informational) |

**CONFIG array (required for standard profiles):**

| Key | Type | Description |
|-----|------|-------------|
| `selected_ip` | IP address | Server IP for connection |
| `selected_hostname` | string | Server hostname/CN |
| `killswitch` | boolean | Kill switch enabled |

**CONFIG array (optional):**

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `selected_region` | string | - | Provider region code |
| `selected_name` | string | - | Human-readable location |
| `selected_country_code` | string | - | ISO country code |
| `killswitch_lan` | boolean | `false` | Allow LAN access |
| `ipv6_disabled` | boolean | `true` | Disable IPv6 |
| `use_provider_dns` | boolean | `true` | Use provider DNS |
| `custom_dns` | IP address | - | Custom DNS server |
| `port_forward` | boolean | `false` | Enable port forwarding |
| `dip_enabled` | boolean | `false` | Dedicated IP enabled |
| `max_latency` | integer | - | Latency threshold (ms) |

### 4.4 Value Types and Validation

| Type | Validation | Examples |
|------|------------|----------|
| `string` | No shell metacharacters | `"mullvad_sweden"` |
| `boolean` | Exactly `"true"` or `"false"` | `"true"` |
| `integer` | Numeric only, no decimals | `"200"` |
| `IP address` | Valid IPv4 or IPv6 | `"185.213.154.68"` |
| `ISO8601` | Valid timestamp | `"2026-01-30T14:30:00Z"` |

**Forbidden Characters in Values:**

```
' " ` $ ( ) ; & | < > ! \ { } [ ]
```

---

## 5. Profile Naming Convention

### 5.1 Auto-Generated Names

When creating a profile via `velum config`, the default name is generated from the
**server selection output** so the name is meaningful and sortable.

```
{provider_short}_{city}_{latency_ms}ms_{yyyymmdd}.conf
```

**Examples:**
- `mv_zurich_192ms_20260130.conf`
- `mv_malmo_176ms_20260130.conf`
- `iv_bucharest_88ms_20260130.conf`

**Generated from:**
- Provider short code (`CONFIG[provider]` → `mv|iv|pia`)
- Selected location (`CONFIG[selected_name]`)
- Last measured latency (ms)
- Current date (UTC)

### 5.2 User Override Prompt

After server selection, `velum config` MUST show the generated name and allow edit:

```
Profile name [mullvad_zurich_192ms_20260130]:
```

**Provider short codes:**
- `mv` = Mullvad
- `iv` = IVPN
- `pia` = Private Internet Access

### 5.3 Optional Naming Tokens (Extended Mode)

If the user opts into **extended naming tokens**, the generator may append short, safe
suffixes that summarize quality or ownership without exposing sensitive details.

**Base name (default, minimal):**
```
mv_zurich_192ms_20260130
```

**Extended tokens (optional, appended):**
- `rec3` / `rec2` / `rec1` / `rec0`   (recommendation tier)
- `own` / `rent` / `unk`             (ownership status)
- `detc` / `detp` / `detf`           (detection: clean/partial/flagged)

**Example (extended):**
```
mv_zurich_192ms_20260130_rec3_own_detc
```

**Rules:**
- Extended tokens are **opt‑in** (default OFF).
- Tokens are short and normalized; no free‑form text.
- Do **not** include IPs, hostnames, provider IDs, or raw API data.
- If name exceeds 64 chars, truncate at the end.

- Empty input accepts default
- Edits are normalized (lowercase, spaces → underscore)
- Invalid names are rejected with a clear error

### 5.4 Naming Rules

| Rule | Requirement |
|------|-------------|
| Characters | Alphanumeric, underscore, hyphen only: `[a-z0-9_-]` |
| Case | Lowercase only (normalized on save) |
| Length | 1-64 characters (excluding `.conf`) |
| Extension | Must end with `.conf` |
| Start | Must start with letter: `[a-z]` |
| Reserved | Must not be `default`, `temp`, `backup` |
| Path safety | Must not contain `..` or start with `.` |

### 5.5 Validation Regex

```bash
^[a-z][a-z0-9_-]{0,63}$
```

### 5.6 Name Collision Handling

If a profile name already exists during creation:

1. Prompt user: "Profile 'mullvad_sweden' already exists. Overwrite? [y/N]"
2. If declined, prompt for alternative name
3. Never silently overwrite

---

## 6. Profile Parsing Security

### 6.1 Core Principle

**CRITICAL: Profile files MUST NEVER be sourced, eval'd, or executed.**

Profiles are data files, not scripts. All parsing must use safe string operations.

### 6.2 Safe Parsing Requirements

| Requirement | Implementation |
|-------------|----------------|
| No `source` | Never use `source`, `.`, or `eval` on profiles |
| Regex parsing | Parse lines with `[[ "$line" =~ pattern ]]` |
| Whitelist arrays | Reject unknown array names |
| Validate values | Type-check each value per key |
| Fail closed | Any parse error aborts with error |
| Permission check | Reject world/group readable files |

### 6.3 Parsing Implementation

```bash
# safe_load_profile() - Parse profile without execution
safe_load_profile() {
  local file="$1"
  local -n profile_ref="$2"
  local -n config_ref="$3"

  # 1. Verify file exists
  [[ ! -f "$file" ]] && { log_error "Profile not found: $file"; return 1; }

  # 2. Verify file is within allowed directory
  local realpath
  realpath=$(realpath "$file")
  [[ "$realpath" != "$VELUM_CONFIG_DIR/profiles/"* ]] && {
    log_error "Profile outside allowed directory"
    return 1
  }

  # 3. Check permissions (must be 600, owned by user)
  local perms owner
  perms=$(stat -c %a "$file" 2>/dev/null || stat -f %Lp "$file" 2>/dev/null)
  owner=$(stat -c %U "$file" 2>/dev/null || stat -f %Su "$file" 2>/dev/null)

  [[ "$perms" != "600" ]] && {
    log_error "Insecure permissions on $file (found: $perms, expected: 600)"
    return 1
  }

  # 4. Parse line by line with strict validation
  local line_num=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    ((line_num++))

    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue

    # Match: ARRAY[key]="value"
    if [[ "$line" =~ ^([A-Z]+)\[([a-z_]+)\]=\"([^\"]*)\"$ ]]; then
      local array="${BASH_REMATCH[1]}"
      local key="${BASH_REMATCH[2]}"
      local value="${BASH_REMATCH[3]}"

      # Validate array name
      case "$array" in
        PROFILE|CONFIG|ENTRY|EXIT) ;;
        *)
          log_error "Unknown array '$array' at line $line_num"
          return 1
          ;;
      esac

      # Validate no shell metacharacters in value
      if [[ "$value" =~ [\'\"\`\$\(\)\;\&\|\<\>\!\\] ]]; then
        log_error "Forbidden character in value at line $line_num"
        return 1
      fi

      # Store in appropriate array
      case "$array" in
        PROFILE) profile_ref["$key"]="$value" ;;
        CONFIG)  config_ref["$key"]="$value" ;;
      esac
    else
      # Line doesn't match expected format
      log_error "Malformed line $line_num: $line"
      return 1
    fi
  done < "$file"

  # 5. Validate required keys
  [[ -z "${profile_ref[type]:-}" ]] && {
    log_error "Missing required key: PROFILE[type]"
    return 1
  }
  [[ -z "${profile_ref[name]:-}" ]] && {
    log_error "Missing required key: PROFILE[name]"
    return 1
  }

  return 0
}
```

### 6.4 Profile Reference Resolution (Multi-Hop)

When a multi-hop profile references another profile:

```bash
ENTRY[profile]="mullvad_sweden"
```

Resolution steps:
1. Construct path: `$VELUM_CONFIG_DIR/profiles/mullvad_sweden.conf`
2. Verify path contains no `..` (traversal attack)
3. Verify file exists and has correct permissions
4. Parse referenced profile with same safety rules
5. Detect circular references (A→B→A)

---

## 7. Default Profile Handling

### 7.1 Default Profile Pointer

The default profile is stored in a plain text file:

```
~/.config/velum/default_profile
```

**Contents:** Just the profile name (without path or `.conf`):

```
mullvad_sweden
```

### 7.2 Why Not Symlinks

Symlinks were considered but rejected due to security concerns:

| Risk | Description |
|------|-------------|
| Traversal | Symlink could point outside profiles directory |
| TOCTOU | Race condition between check and use |
| Sudo complexity | Symlink ownership/permissions under sudo |

Plain text file is simpler and safer.

### 7.3 Default Profile Resolution

```bash
get_default_profile() {
  local default_file="$VELUM_CONFIG_DIR/default_profile"

  # If no default set, return empty
  [[ ! -f "$default_file" ]] && return 1

  # Read profile name
  local profile_name
  profile_name=$(<"$default_file")

  # Validate name format
  [[ ! "$profile_name" =~ ^[a-z][a-z0-9_-]{0,63}$ ]] && {
    log_error "Invalid default profile name"
    return 1
  }

  # Verify profile exists
  local profile_path="$VELUM_CONFIG_DIR/profiles/${profile_name}.conf"
  [[ ! -f "$profile_path" ]] && {
    log_error "Default profile not found: $profile_name"
    return 1
  }

  echo "$profile_name"
}
```

### 7.4 No Default Behavior

If no default profile is set:

| Command | Behavior |
|---------|----------|
| `velum connect` | Error: "No default profile set. Use 'velum profiles default <name>' or 'velum connect -p <name>'" |
| `velum status` | Shows "Not connected" (no change) |
| `velum profiles list` | Works normally, shows all profiles |

---

## 8. CLI Commands

### 8.1 Profile Management

```bash
# List all profiles
velum profiles list
velum profiles ls

# List profiles from connect flow (shortcut)
velum connect --list
velum connect -l

# Output:
#   NAME                  PROVIDER    SERVER                  DEFAULT
#   mullvad_sweden        mullvad     Sweden - Stockholm      *
#   mullvad_switzerland   mullvad     Switzerland - Zurich
#   ivpn_romania          ivpn        Romania - Bucharest

# Show profile details
velum profiles show <name>
velum profiles show mullvad_sweden

# Output:
#   Profile: mullvad_sweden
#   Type: standard
#   Provider: mullvad
#   Created: 2026-01-30T14:30:00Z
#
#   Server:
#     Region: se-sto
#     IP: 185.213.154.68
#     Hostname: se-sto-wg-001
#     Location: Sweden - Stockholm
#
#   Security:
#     Kill Switch: enabled
#     LAN Access: disabled
#     IPv6: disabled
#
#   DNS:
#     Provider DNS: enabled

# Set default profile
velum profiles default <name>
velum profiles default mullvad_sweden

# Delete profile
velum profiles delete <name>
velum profiles rm <name>
velum profiles delete mullvad_sweden

# Rename profile
velum profiles rename <old> <new>
velum profiles mv <old> <new>
velum profiles rename mullvad_sweden mullvad_stockholm

# Duplicate profile
velum profiles copy <source> <dest>
velum profiles cp <source> <dest>
velum profiles copy mullvad_sweden mullvad_sweden_backup
```

### 8.2 Profile Creation

```bash
# Create new profile (interactive wizard)
velum config --profile <name>
velum config -p <name>
velum config --profile work_vpn

# Create profile with provider pre-selected
velum config --profile <name> --provider <provider>
velum config -p sweden --provider mullvad
```

### 8.3 Connection with Profiles

```bash
# Connect using default profile
velum connect

# Connect using named profile
velum connect --profile <name>
velum connect -p <name>
velum connect -p mullvad_sweden

# Shorthand: accept profile as positional argument
velum connect <name>
velum connect mullvad_sweden

# Accept .conf suffix as convenience (normalized internally)
velum connect mullvad_sweden.conf

# Connect and set as default
velum connect --profile <name> --set-default
velum connect -p mullvad_sweden --set-default
```

### 8.4 Status with Profiles

```bash
# Show status (includes active profile)
velum status

# Output when connected:
#   Velum VPN Status
#   ================
#   Profile: mullvad_sweden
#   Status: Connected
#   ...
```

### 8.5 Help Integration

```bash
velum profiles --help

# Output:
#   velum profiles - Manage VPN configuration profiles
#
#   USAGE
#       velum profiles <command> [options]
#
#   COMMANDS
#       list, ls              List all profiles
#       show <name>           Show profile details
#       default <name>        Set default profile
#       delete, rm <name>     Delete a profile
#       rename, mv <old> <new>  Rename a profile
#       copy, cp <src> <dest>   Duplicate a profile
#
#   EXAMPLES
#       velum profiles list
#       velum profiles show mullvad_sweden
#       velum profiles default mullvad_sweden
#       velum profiles delete old_config
```

---

## 9. Migration from Legacy Config

### 9.1 Migration Trigger

Migration runs automatically on first use after upgrade when:
1. `~/.config/velum/velum.conf` exists
2. `~/.config/velum/profiles/` does not exist OR is empty

### 9.2 Migration Process

```
1. Detect legacy config at ~/.config/velum/velum.conf
2. Create profiles directory: mkdir -p ~/.config/velum/profiles
3. Determine profile name:
   - Extract provider and region from config
   - Generate name: {provider}_{region}.conf
   - If extraction fails, use "migrated.conf"
4. Convert config to profile format:
   - Add PROFILE[type]="standard"
   - Add PROFILE[name]="{name}"
   - Add PROFILE[provider]="{provider}"
   - Add PROFILE[created]="{current_timestamp}"
   - Copy existing CONFIG keys
5. Write profile to profiles/{name}.conf
6. Set as default: echo "{name}" > default_profile
7. Backup legacy: mv velum.conf velum.conf.migrated
8. Print migration summary
```

### 9.3 Migration Output

```
Velum Configuration Migration
=============================

Detected legacy configuration at ~/.config/velum/velum.conf

Migrating to named profiles system...
  - Created profile: mullvad_sweden
  - Set as default profile
  - Backed up legacy config to velum.conf.migrated

Migration complete. Your existing configuration is now available as:
  velum connect -p mullvad_sweden

Or simply:
  velum connect  (uses default profile)
```

### 9.4 Migration Failure Handling

If migration fails:
1. Do not delete or modify legacy config
2. Print error with details
3. Allow manual migration:
   ```
   Migration failed: [reason]

   Your original config is unchanged at ~/.config/velum/velum.conf

   To migrate manually:
     1. velum config --profile my_vpn
     2. Re-enter your configuration
     3. rm ~/.config/velum/velum.conf
   ```

---

## 10. Implementation Plan

### 10.1 Phase 1: Core Infrastructure

**Deliverables:**
- [ ] Create `lib/velum-profiles.sh` module
- [ ] Implement `safe_load_profile()` parser
- [ ] Implement profile directory initialization
- [ ] Implement profile validation functions
- [ ] Add profile permission checking

**Testing:**
- Parse valid profiles
- Reject malformed profiles
- Reject profiles with forbidden characters
- Verify permission enforcement

### 10.2 Phase 2: Profile CRUD

**Deliverables:**
- [ ] Implement `profile_list()`
- [ ] Implement `profile_show()`
- [ ] Implement `profile_delete()`
- [ ] Implement `profile_rename()`
- [ ] Implement `profile_copy()`
- [ ] Implement `profile_set_default()`
- [ ] Implement `profile_get_default()`

**Testing:**
- List profiles (empty, single, multiple)
- Show profile details
- Delete profile (confirm prompt)
- Rename profile
- Copy profile
- Set/get default

### 10.3 Phase 3: CLI Integration

**Deliverables:**
- [ ] Create `bin/velum-profiles` command
- [ ] Add to `bin/velum` dispatcher
- [ ] Update `velum config` for `--profile` flag
- [ ] Update `velum connect` for `--profile` flag
- [ ] Update `velum status` to show active profile
- [ ] Update help text

**Testing:**
- All CLI commands work
- Tab completion (if applicable)
- Error messages are clear

### 10.4 Phase 4: Migration

**Deliverables:**
- [ ] Implement legacy config detection
- [ ] Implement config-to-profile conversion
- [ ] Implement migration workflow
- [ ] Add migration tests

**Testing:**
- Migration from various legacy configs
- Migration failure handling
- No data loss

### 10.5 Phase 5: Polish

**Deliverables:**
- [ ] Update README.md
- [ ] Update velum --help
- [ ] Edge case handling
- [ ] Error message improvements
- [ ] Shell completion hooks (tab‑complete profile names)

---

## 11. Nice-to-Haves (Post-MVP)

These are explicitly *non‑blocking* for v1 but should be captured for future work:

- **Tab completion** for `velum connect <profile>` and `velum profiles <cmd>`
- **Profile preview list** in `velum connect --list` (name, provider, location, latency)
- **Fast switch**: `velum connect --last` to reuse last active profile
- **Pinned profiles**: mark favorites and show first
- **Tagging**: `PROFILE[tags]="streaming,work"` for future filters

---

## 12. Open Questions

> **Note:** Q4 is resolved. See Section 5 for the auto-generated naming convention.

### Q1: Profile Export/Import

Should we support exporting profiles for sharing or backup?

| Option | Behavior |
|--------|----------|
| **No export** | Profiles are local only |
| **Export to file** | `velum profiles export <name> > profile.conf` |
| **Export sanitized** | Export without server IP (re-fetch on import) |

**Current proposal:** Defer to v2. Profiles are plain text and can be copied manually.

---

### Q2: Profile Locking

Should we prevent editing a profile while it's actively connected?

| Option | Behavior |
|--------|----------|
| **No locking** | Edit freely, changes apply on next connect |
| **Warn only** | "Profile is active, changes won't apply until reconnect" |
| **Lock file** | Prevent edits while connected |

**Current proposal:** Warn only. Lock files add complexity.

---

### Q3: Profile Validation Strictness

How strict should profile validation be?

| Option | Behavior |
|--------|----------|
| **Strict** | Reject any unknown keys |
| **Permissive** | Ignore unknown keys with warning |
| **Version-aware** | Unknown keys allowed if profile version > current |

**Current proposal:** Strict for security. Unknown keys could be injection attempts.

---

### Q4: Auto-Generated Profile Names (RESOLVED)

**Resolution:** See Section 5.1 for the naming convention. Names are auto-generated as `{provider_short}_{city}_{latency_ms}ms_{yyyymmdd}.conf` with user override prompt.

---

## 13. Appendices

### 13.1 Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.1.0-draft | 2026-01-30 | Initial specification extracted from velum-multihop-spec.md |

### 13.2 Related Specifications

| Spec | Relationship |
|------|--------------|
| `velum-multihop-spec.md` | Depends on this spec; multi-hop profiles reference standard profiles |
| `velum-credential-security-spec.md` | Profiles reference credentials via provider; no secrets in profiles |
| `velum-server-selection-spec.md` | Server selection populates CONFIG keys in profiles |

### 13.3 File Format Example (Complete)

```bash
# Velum VPN Profile
# Type: standard
# Created: 2026-01-30T14:30:00Z
# Provider: mullvad

# ============================================================================
# PROFILE METADATA
# ============================================================================

PROFILE[type]="standard"
PROFILE[name]="mullvad_sweden"
PROFILE[provider]="mullvad"
PROFILE[created]="2026-01-30T14:30:00Z"
PROFILE[description]="Primary VPN - Sweden datacenter"
PROFILE[latency_ms]="45"

# ============================================================================
# SERVER CONFIGURATION
# ============================================================================

CONFIG[selected_region]="se-sto"
CONFIG[selected_ip]="185.213.154.68"
CONFIG[selected_hostname]="se-sto-wg-001"
CONFIG[selected_name]="Sweden - Stockholm"
CONFIG[selected_country_code]="SE"

# ============================================================================
# SECURITY SETTINGS
# ============================================================================

CONFIG[killswitch]="true"
CONFIG[killswitch_lan]="false"
CONFIG[ipv6_disabled]="true"

# ============================================================================
# DNS SETTINGS
# ============================================================================

CONFIG[use_provider_dns]="true"
CONFIG[custom_dns]=""

# ============================================================================
# PROVIDER-SPECIFIC SETTINGS (MULLVAD)
# ============================================================================

CONFIG[port_forward]="false"
CONFIG[dip_enabled]="false"
CONFIG[max_latency]="200"
```

---

*End of Specification - Draft pending audit*
