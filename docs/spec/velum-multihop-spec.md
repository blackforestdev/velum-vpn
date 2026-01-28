# Velum VPN Multi-Hop Specification

**Version:** 0.2.0-draft
**Date:** 2026-01-27
**Status:** Design Phase - Living Document
**Last Audit:** 2026-01-27 (routing, security, state paths)

---

## Table of Contents

1. [Overview & Goals](#1-overview--goals)
2. [Named Profiles System](#2-named-profiles-system)
   - 2.6 Profile Parsing Security (NEW)
3. [Multi-Hop Architecture](#3-multi-hop-architecture)
   - 3.4 Exit API Routing Enforcement (NEW)
   - 3.5 Connection Sequence (updated with phases)
   - 3.7 MTU Considerations (updated with discovery)
4. [Cross-Provider Multi-Hop](#4-cross-provider-multi-hop)
5. [Security Model](#5-security-model)
   - 5.1 Kill Switch (updated with Phase 1/Phase 2)
   - 5.4 DNS Failure Policy (NEW)
   - 5.5 Monitoring Enhancements (updated with daemon policy)
6. [CLI Design](#6-cli-design)
7. [Configuration Schema](#7-configuration-schema)
8. [Implementation Plan](#8-implementation-plan)
9. [Open Questions](#9-open-questions) (Q3, Q8 RESOLVED)
10. [Appendices](#10-appendices)
    - 10.2 Audit Log (NEW)

---

## 1. Overview & Goals

### 1.1 Feature Description

Multi-hop (also known as "cascading VPN" or "double VPN") routes traffic through two or more VPN servers in sequence, providing additional layers of anonymity and protection against traffic correlation attacks.

```
┌─────────────────────────────────────────────────────────────────┐
│  Single-Hop (Current)                                           │
│                                                                 │
│  You ───────────────────────────► VPN Server ───────► Internet  │
│       VPN sees: your IP + destination                           │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  Multi-Hop (This Feature)                                       │
│                                                                 │
│  You ──► Entry Server ──► Exit Server ──► Internet              │
│          Sees: your IP    Sees: entry IP                        │
│          Knows: exit IP   Knows: destination                    │
│          Doesn't know:    Doesn't know:                         │
│          destination      your real IP                          │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Design Goals

| Priority | Goal | Rationale |
|----------|------|-----------|
| P0 | Cross-provider support | Maximum isolation - no single provider sees full path |
| P0 | No provider premium fees | DIY implementation using standard WireGuard |
| P0 | Maintain kill switch integrity | Both tunnels must be protected |
| P1 | Named profiles foundation | Required infrastructure for multi-hop |
| P1 | Simple UX | Complex feature, simple interface |
| P2 | Latency-aware selection | Help users understand performance tradeoffs |

### 1.3 Non-Goals (v1)

- Three or more hops (theoretically possible, but diminishing returns)
- Automatic hop rotation (can be added later)
- Mobile platform support (desktop focus)
- Provider-native multi-hop integration (IVPN charges premium; we bypass this)

### 1.4 Threat Model

**What multi-hop protects against:**

| Threat | Single-hop | Multi-hop |
|--------|------------|-----------|
| ISP sees VPN IP | Yes, they see VPN server | Yes, they see entry server |
| VPN provider logs | Provider sees your IP + destinations | Entry sees your IP only; Exit sees destinations only |
| Provider compromise/subpoena | Full traffic correlation possible | Need both providers to correlate |
| Destination sees VPN IP | Yes | Yes (exit server IP) |
| Traffic timing attacks | Vulnerable | More resistant (2 hops to correlate) |

**What multi-hop does NOT protect against:**

- End-to-end timing attacks by global adversary
- Compromised endpoints (your device or destination)
- Both providers cooperating with same adversary
- Application-level leaks (WebRTC, etc.)

### 1.5 Why DIY vs Provider Multi-Hop

| Aspect | Provider Multi-Hop (IVPN) | DIY Multi-Hop (Velum) |
|--------|---------------------------|----------------------|
| Cost | Premium subscription required | Standard subscription |
| Trust | Single provider controls both hops | Split trust across providers |
| Verification | Trust provider's claim | User controls routing |
| Cross-provider | Not possible | Core feature |
| Flexibility | Provider's server pairs only | Any server combination |

---

## 2. Named Profiles System

### 2.1 Overview

Named profiles are a prerequisite for multi-hop. They allow users to save multiple VPN configurations and reference them by name.

**Current state:** Single config at `~/.config/velum/velum.conf`

**Proposed state:** Multiple configs in `~/.config/velum/profiles/`

### 2.2 Profile Types

```
┌─────────────────────────────────────────────────────────────────┐
│  Profile Types                                                  │
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ Standard        │  │ Multi-Hop       │  │ Default         │ │
│  │                 │  │                 │  │                 │ │
│  │ Single server   │  │ Entry + Exit    │  │ Symlink to a    │ │
│  │ configuration   │  │ references      │  │ standard or     │ │
│  │                 │  │                 │  │ multi-hop       │ │
│  │ e.g., mullvad_  │  │ e.g., secure_   │  │ profile         │ │
│  │ brussels.conf   │  │ route.conf      │  │                 │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 2.3 Directory Structure

```
~/.config/velum/                  # User config (mode 700)
├── velum.conf                    # Legacy location (deprecated, migrated)
├── default_profile               # Plain text file containing default profile name
├── profiles/                     # Profile storage (mode 700)
│   ├── mullvad_zurich.conf       # Standard profile (mode 600)
│   ├── mullvad_brussels.conf     # Standard profile
│   ├── ivpn_geneva.conf          # Standard profile
│   └── secure_route.conf         # Multi-hop profile
└── tokens/                       # Credentials (mode 700)
    ├── mullvad_token
    ├── mullvad_account
    ├── ivpn_token
    ├── ivpn_account
    ├── wg_private_key_entry      # Entry tunnel key (multi-hop)
    └── wg_private_key_exit       # Exit tunnel key (multi-hop)

$VELUM_RUN_DIR/                   # Runtime state (root-owned, mode 700)
├── active_profile                # Currently connected profile name
├── connection_type               # "standard" or "multihop"
├── entry_server                  # Entry server IP
├── exit_server                   # Exit server IP (multi-hop only)
├── monitor.pid                   # Monitor daemon PID
├── monitor.state                 # Monitor state
└── monitor.log                   # Monitor activity log
```

**Note:** Default profile is stored as plain text file (`default_profile`) containing the profile name, NOT as a symlink. Symlinks pose security risks (traversal, race conditions) when running with elevated privileges.

### 2.4 Profile Naming Convention

**Auto-generated format:** `{provider}_{location}.conf`

Examples:
- `mullvad_brussels.conf`
- `ivpn_zurich.conf`

**User can override:** Profile name is user-editable during creation.

**Restrictions:**
- Alphanumeric, underscore, hyphen only
- No spaces or special characters
- Max 64 characters
- **Lowercase only** (normalized on save to avoid case-sensitivity issues across filesystems)
- `.conf` extension required
- Must not start with `.` or contain `..`

**Latency:** Stored as metadata inside profile (`PROFILE[latency_ms]`), not in filename. Latency changes; filenames should be stable.

### 2.5 Profile File Format

**Standard Profile:**
```bash
# Velum VPN Profile
# Type: standard
# Created: 2026-01-27T14:30:00Z
# Provider: mullvad

PROFILE[type]="standard"
PROFILE[name]="mullvad_brussels"
PROFILE[provider]="mullvad"
PROFILE[created]="2026-01-27T14:30:00Z"

# Provider settings
CONFIG[selected_region]="be-bru"
CONFIG[selected_ip]="185.213.154.68"
CONFIG[selected_hostname]="be-bru-wg-001"

# Security settings
CONFIG[killswitch]="true"
CONFIG[killswitch_lan]="detect"
CONFIG[ipv6_disabled]="true"
CONFIG[use_provider_dns]="true"

# Features
CONFIG[port_forward]="false"
CONFIG[dip_enabled]="false"
```

**Multi-Hop Profile:**
```bash
# Velum VPN Profile
# Type: multihop
# Created: 2026-01-27T15:00:00Z

PROFILE[type]="multihop"
PROFILE[name]="secure_route"
PROFILE[created]="2026-01-27T15:00:00Z"

# Entry hop (first tunnel - sees your real IP)
ENTRY[profile]="mullvad_brussels"
# OR inline definition:
# ENTRY[provider]="mullvad"
# ENTRY[selected_region]="be-bru"
# ENTRY[selected_ip]="185.213.154.68"

# Exit hop (second tunnel - sees destinations)
EXIT[profile]="ivpn_zurich"
# OR inline definition:
# EXIT[provider]="ivpn"
# EXIT[selected_region]="ch-zur"
# EXIT[selected_ip]="185.212.170.139"

# Security settings (apply to both tunnels)
CONFIG[killswitch]="true"
CONFIG[killswitch_lan]="detect"
CONFIG[ipv6_disabled]="true"

# DNS (use exit provider's DNS by default)
CONFIG[use_provider_dns]="true"
CONFIG[dns_provider]="exit"  # "entry" | "exit" | "custom"
```

### 2.6 Profile Parsing Security

**CRITICAL: Profile files MUST NOT be sourced.** Use `safe_load_profile()` (extension of `safe_load_config()`).

**Parsing Requirements:**

1. **Regex-based parsing only** - No `source`, `eval`, or `.` commands
2. **Known keys whitelist** - Reject unknown array names (only `PROFILE`, `CONFIG`, `ENTRY`, `EXIT`)
3. **Value validation per key** - Profiles are stricter than runtime config:
   - Boolean keys: must be `"true"` or `"false"`
   - IP addresses: RFC-compliant validation
   - Profile references: must exist and be readable
   - Shell metacharacters rejected: `'`, `"`, `` ` ``, `$`, `(`, `)`, `;`, `&`, `|`, `<`, `>`, `!`
4. **Fail-closed on parse errors** - Any validation failure aborts with error
5. **File permission check** - Reject world-readable or group-readable profiles

**Profile Reference Resolution:**

When `ENTRY[profile]` or `EXIT[profile]` references another profile:
1. Resolve path: `$VELUM_CONFIG_DIR/profiles/<name>.conf`
2. Validate path is within profiles directory (no `..` traversal)
3. Check file exists and has correct permissions (mode 600)
4. Parse referenced profile with same safety rules
5. Circular reference detection (A→B→A)

```bash
# Example safe_load_profile() pseudocode
safe_load_profile() {
  local file="$1"

  # Verify file is within allowed directory
  local realpath=$(realpath "$file")
  [[ "$realpath" != "$VELUM_CONFIG_DIR/profiles/"* ]] && return 1

  # Check permissions
  check_file_perms "$file" || return 1

  # Parse with strict validation
  safe_load_config "$file" --strict --known-keys-only \
    --arrays "PROFILE,CONFIG,ENTRY,EXIT"
}
```

### 2.7 Migration from Legacy Config

On first run after update:
1. Check for `~/.config/velum/velum.conf`
2. If exists, migrate to `~/.config/velum/profiles/default.conf`
3. Write `~/.config/velum/default_profile` with `default` (or migrated profile name)
4. Rename legacy file to `velum.conf.migrated`

---

## 3. Multi-Hop Architecture

### 3.1 Chained WireGuard Tunnels

Multi-hop uses nested WireGuard tunnels. The exit tunnel's traffic routes through the entry tunnel.

```
┌─────────────────────────────────────────────────────────────────┐
│  Network Stack                                                  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  velum1 (exit tunnel)                                    │   │
│  │  Peer: Exit Server (e.g., IVPN Zurich)                  │   │
│  │  AllowedIPs: 0.0.0.0/0                                  │   │
│  │  Endpoint: routed through velum0                        │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  velum0 (entry tunnel)                                   │   │
│  │  Peer: Entry Server (e.g., Mullvad Brussels)            │   │
│  │  AllowedIPs: 0.0.0.0/0, ::/0                            │   │
│  │  Endpoint: physical interface                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  eth0/wlan0 (physical interface)                        │   │
│  │  To: Entry Server IP via gateway                        │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Interface Naming

| Interface | Purpose | WireGuard Config |
|-----------|---------|------------------|
| `velum0` | Entry tunnel (to entry server) | `/etc/wireguard/velum0.conf` |
| `velum1` | Exit tunnel (to exit server) | `/etc/wireguard/velum1.conf` |

For single-hop connections, continue using `velum` interface for backwards compatibility.

### 3.3 Routing Strategy

**Chosen Model: Entry catches all, Exit overrides via routing table priority.**

This model uses `0.0.0.0/0` on both tunnels, with Linux/macOS routing table precedence ensuring exit tunnel handles general traffic while entry tunnel handles exit server traffic.

**Entry Tunnel (`velum0`):**
```
[Interface]
Address = 10.64.x.x/32
PrivateKey = <entry_private_key>
Table = 51820
# DNS not set here - DNS set on exit tunnel only

[Peer]
PublicKey = <entry_server_pubkey>
Endpoint = <entry_server_ip>:<port>
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25

PostUp = ip rule add to <exit_server_ip>/32 table 51820 priority 100
PostDown = ip rule del to <exit_server_ip>/32 table 51820 priority 100
```

**Exit Tunnel (`velum1`):**
```
[Interface]
Address = 10.0.x.x/32
PrivateKey = <exit_private_key>
DNS = <exit_dns>

[Peer]
PublicKey = <exit_server_pubkey>
Endpoint = <exit_server_ip>:<port>
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

**Routing Table Explanation:**

| Destination | Route | Why |
|-------------|-------|-----|
| Exit server IP | Entry tunnel (policy route, priority 100) | Exit handshakes go through entry |
| Entry server IP | Physical interface (explicit route) | Entry handshakes bypass tunnels |
| 0.0.0.0/0 | Exit tunnel (main table) | All other traffic exits via exit server |

**macOS Equivalent:**
Uses wrapper commands in `velum-connect`/`velum-disconnect` (not WireGuard `PostUp`) to add/remove routes.

### 3.4 Exit API Routing Enforcement

**CRITICAL: Exit provider API calls MUST route through entry tunnel.**

This is a security-critical property. Without enforcement, exit API calls leak via physical interface, defeating cross-provider isolation.

**Enforcement Mechanism: `--interface` flag on curl**

```bash
# Exit provider key exchange - MUST use entry tunnel interface
secure_curl --interface velum0 \
  --tlsv1.2 \
  "https://api.ivpn.net/v4/session/wg/set" \
  --data '{"session_token":"...","public_key":"..."}'
```

**DNS During Exit Setup:**

Before exit tunnel is up, DNS must resolve through entry tunnel:
1. Entry tunnel is up with its DNS configured temporarily
2. Exit provider hostname resolves via entry DNS
3. Exit API call uses `--interface velum0`
4. After exit tunnel up, switch DNS to exit provider

**Fallback: IP-based API calls**

If provider API supports direct IP access, prefer IP over hostname to avoid DNS dependency:
```bash
# Use IP directly if known
secure_curl --interface velum0 "https://185.212.170.139/v4/session/wg/set"
```

### 3.5 Connection Sequence

```
Phase 1: Pre-Connection (no tunnels)
  1. Load multi-hop profile
  2. Validate both entry and exit configurations
  3. Authenticate with entry provider (if token expired) - uses physical interface
  4. Authenticate with exit provider (if token expired) - uses physical interface
  5. Exchange WireGuard keys with entry provider - uses physical interface

Phase 2: Entry Tunnel Up
  6. Enable kill switch (Phase 1 rules - entry server only)
  7. Disable IPv6
  8. Bring up entry tunnel (velum0)
  9. Verify entry handshake successful
  10. Set temporary DNS to entry provider (for exit API resolution)

Phase 3: Exit Tunnel Setup (through entry)
  11. Exchange WireGuard keys with exit provider - MUST use --interface velum0
  12. Update kill switch (Phase 2 rules - add exit traffic through velum0)
  13. Bring up exit tunnel (velum1)
  14. Verify exit handshake successful

Phase 4: Finalization
  15. Set DNS to exit provider (default) or configured provider
  16. Remove temporary entry DNS
  17. Start monitoring (both tunnels)
  18. Write state files to $VELUM_RUN_DIR
```

### 3.6 Disconnection Sequence

```
1. Set intentional disconnect flag
2. Stop monitoring
3. Bring down exit tunnel (velum1)
4. Bring down entry tunnel (velum0)
5. Disable kill switch
6. Restore DNS
7. Restore IPv6
8. Cleanup state files from $VELUM_RUN_DIR
9. Clear intentional disconnect flag
```

### 3.7 MTU Considerations

WireGuard overhead varies by platform and IPv4/IPv6:
- IPv4: ~60 bytes (20 IP + 8 UDP + 32 WG)
- IPv6: ~80 bytes (40 IP + 8 UDP + 32 WG)

**Conservative defaults for multi-hop:**

| Layer | MTU | Calculation |
|-------|-----|-------------|
| Physical interface | 1500 | Standard Ethernet |
| Entry tunnel (velum0) | 1420 | 1500 - 80 (worst case) |
| Exit tunnel (velum1) | 1320 | 1420 - 100 (extra margin for nested) |

**MTU Discovery (recommended):**

Rather than assuming, discover actual MTU:

```bash
# After tunnels are up, test MTU
ping -M do -s 1292 -c 1 <destination>  # 1292 + 28 = 1320

# If fails, reduce and retry
# Find largest that works, set as exit tunnel MTU
```

**Platform-Specific Notes:**

| Platform | Entry MTU | Exit MTU | Notes |
|----------|-----------|----------|-------|
| Linux | 1420 | 1320 | Tested on Debian 12 |
| macOS | 1420 | 1320 | wireguard-go may differ |

**Implementation:** Add `velum test --mtu` command to validate MTU during connection test.

---

## 4. Cross-Provider Multi-Hop

### 4.1 Provider Combinations

Supported combinations (all permutations):

| Entry Provider | Exit Provider | Notes |
|----------------|---------------|-------|
| Mullvad | IVPN | Recommended: different jurisdictions |
| IVPN | Mullvad | Alternative direction |
| Mullvad | Mullvad | Same provider, different servers |
| IVPN | IVPN | Same provider, different servers |

PIA support deferred (removal planned).

### 4.2 Authentication Handling

Each provider authenticates independently:

```
┌─────────────────────────────────────────────────────────────────┐
│  Token Storage                                                  │
│                                                                 │
│  ~/.config/velum/tokens/                                        │
│  ├── mullvad_token          # Mullvad access token              │
│  ├── mullvad_account        # Account number (for refresh)      │
│  ├── ivpn_token             # IVPN session token                │
│  ├── ivpn_account           # Account ID (for refresh)          │
│  ├── wg_private_key_entry   # Entry tunnel private key          │
│  └── wg_private_key_exit    # Exit tunnel private key           │
└─────────────────────────────────────────────────────────────────┘
```

### 4.3 Key Management

Each tunnel requires separate WireGuard keypair:

| Tunnel | Private Key Location | Provider Registration |
|--------|---------------------|----------------------|
| Entry | `tokens/wg_private_key_entry` | Entry provider API |
| Exit | `tokens/wg_private_key_exit` | Exit provider API (through entry tunnel) |

### 4.4 DNS Handling

**Options:**

| Setting | Behavior |
|---------|----------|
| `dns_provider="exit"` (default) | Use exit provider's DNS |
| `dns_provider="entry"` | Use entry provider's DNS |
| `dns_provider="custom"` | Use custom DNS servers |

**Recommendation:** Use exit DNS. DNS queries exit through the exit tunnel, so exit provider's DNS is the logical choice.

---

## 5. Security Model

### 5.1 Kill Switch for Multi-Hop

The kill switch evolves through connection phases:

**Phase 1: Entry Only (before exit tunnel)**
```
┌─────────────────────────────────────────────────────────────────┐
│  Kill Switch Rules - Phase 1 (Entry Setup)                      │
│                                                                 │
│  ALLOW:                                                         │
│  - Loopback (lo)                                                │
│  - Entry tunnel interface (velum0) - all traffic                │
│  - Physical interface → Entry server IP:port (UDP)              │
│  - DHCP (UDP 67-68)                                             │
│  - LAN (if configured)                                          │
│                                                                 │
│  BLOCK:                                                         │
│  - All IPv6                                                     │
│  - Everything else                                              │
│                                                                 │
│  Note: Exit API calls go through velum0, so they're allowed     │
│  Note: Entry DNS is temporarily set and resolves via velum0     │
└─────────────────────────────────────────────────────────────────┘
```

**Phase 2: Full Multi-Hop (both tunnels up)**
```
┌─────────────────────────────────────────────────────────────────┐
│  Kill Switch Rules - Phase 2 (Full Multi-Hop)                   │
│                                                                 │
│  ALLOW:                                                         │
│  - Loopback (lo)                                                │
│  - Exit tunnel interface (velum1) - all traffic                 │
│  - Entry tunnel interface (velum0) - all traffic                │
│  - Physical interface → Entry server IP:port (UDP)              │
│  - DHCP (UDP 67-68)                                             │
│  - LAN (if configured)                                          │
│                                                                 │
│  BLOCK:                                                         │
│  - All IPv6                                                     │
│  - Everything else                                              │
│                                                                 │
│  Note: Exit server traffic routes through velum0 (policy route) │
│  Note: Physical → Exit server directly is BLOCKED               │
└─────────────────────────────────────────────────────────────────┘
```

**Implementation Note:** Kill switch does NOT allow physical interface → exit server. Exit traffic MUST go through entry tunnel. The policy routing table (Section 3.3) ensures this.

### 5.2 Failure Modes

| Failure | Kill Switch Behavior | User Impact |
|---------|---------------------|-------------|
| Exit tunnel drops | Traffic blocked (no direct internet) | Must reconnect |
| Entry tunnel drops | Traffic blocked (exit unreachable) | Must reconnect |
| Both tunnels drop | Traffic blocked | Must reconnect |
| Entry tunnel only (no exit) | Invalid state - prevented | N/A |

**Key principle:** If either tunnel fails, ALL traffic is blocked. No degraded mode where traffic bypasses a tunnel.

### 5.3 IPv6 Handling

Same as single-hop:
1. Disable at interface level (sysctl/networksetup)
2. Block at firewall level (belt and suspenders)

### 5.4 DNS Failure Policy

**Fail-closed behavior for DNS:**

| Scenario | Behavior |
|----------|----------|
| Exit DNS unreachable | Connection fails, do not fall back to entry DNS |
| Entry DNS unreachable (during setup) | Connection fails, do not fall back to physical DNS |
| DNS resolution fails after connected | Traffic blocked (no DNS = no destinations) |

**Rationale:** Falling back to a less-secure DNS defeats the purpose of multi-hop. Users who want multi-hop privacy should accept connection failure over DNS leakage.

**Exception:** If user explicitly configures `dns_provider="entry"`, then entry DNS is intentional (not a fallback).

**Implementation:**
```bash
# During connection, test DNS before finalizing
if ! timeout 5 dig @$exit_dns example.com >/dev/null 2>&1; then
  log_error "Exit DNS unreachable, aborting connection"
  # Tear down tunnels, restore network
  exit 1
fi
```

### 5.5 Monitoring Enhancements

`velum-monitor` must check both tunnels:

```bash
# Check entry tunnel
wg show velum0 latest-handshakes

# Check exit tunnel
wg show velum1 latest-handshakes

# Both must be fresh (<180 seconds)
```

Alert conditions:
- Entry tunnel stale → "Entry tunnel connection stale"
- Exit tunnel stale → "Exit tunnel connection stale"
- Entry tunnel down → "Entry tunnel disconnected" (critical)
- Exit tunnel down → "Exit tunnel disconnected" (critical)
- Kill switch disabled → "Kill switch disabled" (critical)

**Daemon Policy:** Monitor runs only when user initiates via `velum connect` or `velum monitor start`. No persistent background daemons. Monitor stops on `velum disconnect` or `velum monitor stop`.

---

## 6. CLI Design

### 6.1 Profile Management Commands

```bash
# List all profiles
velum profiles list
velum profiles ls

# Show profile details
velum profiles show <name>
velum profiles show mullvad_brussels

# Create new profile (interactive)
velum config --profile <name>
velum config --profile work_vpn

# Create multi-hop profile (interactive)
velum config --multihop --profile <name>
velum config --multihop --profile secure_route

# Delete profile
velum profiles delete <name>
velum profiles rm <name>

# Set default profile
velum profiles default <name>

# Rename profile
velum profiles rename <old> <new>

# Duplicate profile
velum profiles copy <source> <dest>
```

### 6.2 Connection Commands

```bash
# Connect using default profile
velum connect

# Connect using named profile
velum connect --profile <name>
velum connect -p <name>
velum connect --profile mullvad_brussels

# Connect multi-hop with inline specification
velum connect --multihop --entry <profile> --exit <profile>
velum connect --multihop --entry mullvad_brussels --exit ivpn_zurich

# Shorthand for above (if profiles exist)
velum connect -m -e mullvad_brussels -x ivpn_zurich
```

### 6.3 Status Commands

```bash
# Show connection status
velum status

# Output for multi-hop:
# ┌─────────────────────────────────────────┐
# │ Velum VPN Status                        │
# ├─────────────────────────────────────────┤
# │ Connection: Multi-Hop (2 tunnels)       │
# │                                         │
# │ Entry Tunnel (velum0):                  │
# │   Provider:  Mullvad                    │
# │   Server:    be-bru-wg-001 (Brussels)   │
# │   Endpoint:  185.213.154.68:51820       │
# │   Handshake: 12 seconds ago             │
# │                                         │
# │ Exit Tunnel (velum1):                   │
# │   Provider:  IVPN                       │
# │   Server:    ch1.wg.ivpn.net (Zurich)   │
# │   Endpoint:  185.212.170.139:2049       │
# │   Handshake: 8 seconds ago              │
# │                                         │
# │ Public IP:  185.212.170.139 (Zurich)    │
# │ Kill Switch: Active (14 rules)          │
# │ IPv6:        Disabled                   │
# │ DNS:         10.0.254.1 (IVPN)          │
# └─────────────────────────────────────────┘
```

### 6.4 Test Commands

```bash
# Test multi-hop connection
velum test

# Additional multi-hop specific tests:
# - Entry tunnel handshake
# - Exit tunnel handshake
# - Traffic path verification (traceroute shows 2 hops)
# - Both tunnels protected by kill switch
```

---

## 7. Configuration Schema

### 7.1 New Configuration Keys

| Key | Type | Values | Description |
|-----|------|--------|-------------|
| `PROFILE[type]` | string | "standard", "multihop" | Profile type |
| `PROFILE[name]` | string | alphanumeric | Profile identifier |
| `PROFILE[created]` | string | ISO8601 | Creation timestamp |
| `ENTRY[profile]` | string | profile name | Reference to entry profile |
| `ENTRY[provider]` | string | provider name | Inline entry provider |
| `EXIT[profile]` | string | profile name | Reference to exit profile |
| `EXIT[provider]` | string | provider name | Inline exit provider |
| `CONFIG[dns_provider]` | string | "entry", "exit", "custom" | DNS source for multi-hop |

### 7.2 State Files

All runtime state lives in `$VELUM_RUN_DIR` (root-owned, mode 700):

| File | Purpose | Permissions |
|------|---------|-------------|
| `$VELUM_RUN_DIR/active_profile` | Currently connected profile name | 600 |
| `$VELUM_RUN_DIR/connection_type` | "standard" or "multihop" | 600 |
| `$VELUM_RUN_DIR/entry_server` | Entry server IP (for kill switch reference) | 600 |
| `$VELUM_RUN_DIR/exit_server` | Exit server IP (multi-hop only) | 600 |
| `$VELUM_RUN_DIR/entry_endpoint` | Full entry endpoint (IP:port) | 600 |
| `$VELUM_RUN_DIR/exit_endpoint` | Full exit endpoint (IP:port) | 600 |
| `$VELUM_RUN_DIR/monitor.pid` | Monitor daemon PID | 600 |
| `$VELUM_RUN_DIR/monitor.state` | Monitor state variables | 600 |
| `$VELUM_RUN_DIR/monitor.log` | Monitor activity log | 600 |
| `$VELUM_RUN_DIR/intentional-disconnect` | Flag for clean disconnect | 600 |

**Path Values:**
- Linux: `$VELUM_RUN_DIR = /run/velum`
- macOS: `$VELUM_RUN_DIR = /var/run/velum`

**Note:** NO state files in `~/.config/velum/state/`. All runtime state is in `$VELUM_RUN_DIR`.

### 7.3 WireGuard Config Files

| File | Purpose |
|------|---------|
| `/etc/wireguard/velum.conf` | Single-hop (backwards compat) |
| `/etc/wireguard/velum0.conf` | Multi-hop entry tunnel |
| `/etc/wireguard/velum1.conf` | Multi-hop exit tunnel |

---

## 8. Implementation Plan

### 8.1 Phase 1: Named Profiles (Foundation)

**Deliverables:**
- [ ] Profile directory structure
- [ ] Profile file format (standard type only)
- [ ] `velum profiles list` command
- [ ] `velum profiles show <name>` command
- [ ] `velum config --profile <name>` (create/edit)
- [ ] `velum profiles delete <name>` command
- [ ] `velum profiles default <name>` command
- [ ] `velum connect --profile <name>` support
- [ ] Legacy config migration
- [ ] Update `velum-security.sh` for profile parsing

**Testing:**
- Create multiple profiles
- Switch between profiles
- Verify migration from legacy config
- Verify file permissions

### 8.2 Phase 2: Multi-Interface Support

**Deliverables:**
- [ ] Support for `velum0`, `velum1` interfaces
- [ ] Update `os_detect_vpn_interface()` for multiple interfaces
- [ ] Update kill switch for multiple tunnel protection
- [ ] Update WireGuard config generation for numbered interfaces
- [ ] MTU configuration for nested tunnels

**Testing:**
- Bring up two WireGuard interfaces manually
- Verify routing through nested tunnels
- Verify kill switch protects both

### 8.3 Phase 3: Multi-Hop Connection Logic

**Deliverables:**
- [ ] Multi-hop profile type
- [ ] `velum config --multihop` wizard
- [ ] Connection sequence (entry first, then exit)
- [ ] Disconnection sequence (exit first, then entry)
- [ ] Key exchange through entry tunnel
- [ ] `velum connect --multihop` command
- [ ] DNS handling for multi-hop

**Testing:**
- Same-provider multi-hop (Mullvad → Mullvad)
- Cross-provider multi-hop (Mullvad → IVPN)
- Verify traffic path (exit IP visible externally)
- Verify kill switch on tunnel failure

### 8.4 Phase 4: Monitoring & Status

**Deliverables:**
- [ ] Update `velum-status` for multi-hop display
- [ ] Update `velum-monitor` for dual tunnel monitoring
- [ ] Update `velum-test` for multi-hop validation
- [ ] Add multi-hop specific tests

**Testing:**
- Verify status shows both tunnels
- Verify monitor alerts on either tunnel failure
- Verify test suite covers multi-hop scenarios

### 8.5 Phase 5: Polish & Documentation

**Deliverables:**
- [ ] Update README.md
- [ ] Update velum-v1.0-spec.md
- [ ] Error handling and edge cases
- [ ] User-facing help text
- [ ] Profile management polish (rename, copy)

---

## 9. Open Questions

### 9.1 Profile Storage

**Q1: Composite vs Inline Multi-Hop Profiles**

Should multi-hop profiles reference other profiles, or embed the configuration?

| Option | Pros | Cons |
|--------|------|------|
| **Reference** (`ENTRY[profile]="mullvad_brussels"`) | DRY, update once | Broken if referenced profile deleted |
| **Inline** (embed full config) | Self-contained, portable | Duplication, harder to update |
| **Both** | Maximum flexibility | More complex parsing |

**Current proposal:** Support both, with reference as default.

---

**Q2: Profile Naming**

Should profile names include latency?

| Option | Example | Pros | Cons |
|--------|---------|------|------|
| Without latency | `mullvad_brussels.conf` | Stable name | No performance hint |
| With latency | `mullvad_brussels_45ms.conf` | Performance visible | Stale if latency changes |

**Current proposal:** Without latency in filename; latency stored as metadata inside profile.

---

**Q3: Default Profile Handling**

How should `velum connect` (no args) work?

| Option | Behavior |
|--------|----------|
| ~~**Symlink**~~ | ~~`profiles/default` symlinks to a profile~~ |
| **Plain text file** | `default_profile` contains profile name |
| **Config key** | `velum.conf` contains `default_profile=name` |

**RESOLVED:** Plain text file approach. Symlinks pose security risks with sudo (traversal, TOCTOU race conditions). A simple file containing the profile name is safer and sufficient.

File: `~/.config/velum/default_profile` contains just the profile name (e.g., `mullvad_brussels`).

---

### 9.2 Multi-Hop Behavior

**Q4: Tunnel Failure Behavior**

If exit tunnel fails but entry remains up, should we:

| Option | Behavior | Rationale |
|--------|----------|-----------|
| **A: Block all** | Kill switch blocks everything | Fail-closed, safest |
| **B: Allow entry only** | Traffic can use entry tunnel | Graceful degradation |
| **C: User choice** | Config option | Flexibility |

**Current proposal:** Option A (block all). Multi-hop users want maximum security; degraded mode defeats the purpose.

---

**Q5: Key Persistence**

Should we use one WireGuard keypair or two for multi-hop?

| Option | Keys | Pros | Cons |
|--------|------|------|------|
| **One key** | Same key for both tunnels | Simpler | Linkable across providers |
| **Two keys** | Separate key per tunnel | Unlinkable | More state to manage |

**Current proposal:** Two keys. Cross-provider unlinkability is a core goal.

---

**Q6: Latency Display**

Should `velum config --multihop` show combined latency?

| Option | Display |
|--------|---------|
| **Individual** | "Entry: 45ms, Exit: 62ms" |
| **Combined** | "Total: ~107ms" |
| **Both** | "Entry: 45ms + Exit: 62ms = ~107ms" |

**Current proposal:** Both - users should understand the tradeoff.

---

### 9.3 Implementation Details

**Q7: Interface Naming**

For multi-hop, should we use:

| Option | Entry | Exit | Single-hop |
|--------|-------|------|------------|
| **Numbered** | velum0 | velum1 | velum (unchanged) |
| **Named** | velum-entry | velum-exit | velum (unchanged) |
| **Always numbered** | velum0 | velum1 | velum0 |

**Current proposal:** Numbered for multi-hop, keep `velum` for single-hop (backwards compat).

---

**Q8: Entry Tunnel AllowedIPs**

The entry tunnel needs to route exit server traffic. Options:

| Option | AllowedIPs | Behavior |
|--------|------------|----------|
| ~~**Exit IP only**~~ | ~~`<exit_server_ip>/32`~~ | ~~Minimal, but breaks if exit server has multiple IPs~~ |
| ~~**Exit subnet**~~ | ~~`<exit_server_subnet>/24`~~ | ~~More permissive~~ |
| **All traffic** | `0.0.0.0/0` | Entry handles all, exit overrides |

**RESOLVED:** All traffic on entry (`0.0.0.0/0`), with policy routing to direct exit server IP through entry tunnel. See Section 3.3 for full routing strategy.

Key insight: Using exit-IP-only AllowedIPs creates complexity with DNS and API routing. The `0.0.0.0/0` + policy routing approach is cleaner and more robust.

---

## 10. Appendices

### 10.1 Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.2.0-draft | 2026-01-27 | Security audit fixes: routing model, exit handshake enforcement, state paths, profile parsing safety, symlink removal, phased kill switch, MTU discovery, DNS failure policy |
| 0.1.0-draft | 2026-01-27 | Initial specification |

### 10.2 Audit Log

**2026-01-27 Audit (v0.2.0):**

| Finding | Severity | Resolution |
|---------|----------|------------|
| Routing strategy inconsistent (Section 3.3 vs Q8) | High | Unified to 0.0.0.0/0 + policy routing |
| No exit handshake enforcement | High | Added `--interface velum0` requirement (Section 3.4) |
| State file path inconsistent | High | All state in $VELUM_RUN_DIR (Section 7.2) |
| Profile parsing safety undefined | High | Added Section 2.6 with safe_load_profile() |
| Symlink security risk | Medium | Replaced symlink with plain text file |
| Kill switch incomplete for phases | Medium | Added Phase 1/Phase 2 rules (Section 5.1) |
| MTU unverified | Medium | Added discovery step, platform notes (Section 3.7) |
| DNS failure policy undefined | Medium | Added fail-closed policy (Section 5.4) |
| Case-sensitivity issues | Low | Normalized to lowercase (Section 2.4) |
| Monitor daemon policy unclear | Low | Added daemon policy note (Section 5.5) |

### 10.3 References

**WireGuard Routing:**
- https://www.wireguard.com/netns/
- https://www.procustodibus.com/blog/2022/09/wireguard-through-wireguard/

**Multi-Hop Concepts:**
- https://www.ivpn.net/knowledgebase/general/what-is-multi-hop/
- https://mullvad.net/en/help/how-use-multihop-mullvad/

### 10.4 Glossary

| Term | Definition |
|------|------------|
| Entry server | First VPN server; sees your real IP |
| Exit server | Second VPN server; your traffic exits here |
| Nested tunnel | WireGuard tunnel running inside another WireGuard tunnel |
| Profile | Saved VPN configuration that can be referenced by name |

---

*End of Specification - Living Document*
