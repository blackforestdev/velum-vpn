# velum_config.sh v0.2 Specification

## Overview

This document specifies the redesign of `run_setup.sh` into `velum_config.sh` with improved UX and logical security hierarchy.

## Problem Statement

The current `run_setup.sh` asks configuration questions in the order they were added historically, not in logical security hierarchy:

### Current Flow (run_setup.sh)

| Step | Question | Category |
|------|----------|----------|
| 1 | Credentials | Auth |
| 2 | DIP token? | Feature |
| 3 | Port forwarding? | Feature |
| 4 | **IPv6 disable?** | Security |
| 5 | Server selection | Connection |
| 6 | Geo servers? | Connection |
| 7 | Latency threshold | Connection |
| 8 | Protocol (WG/OVPN) | Connection |
| 9 | **PIA DNS?** | Security |
| 10 | **Kill switch?** | Security |
| 11 | LAN policy | Security |

**Issues:**
- Kill switch (the PRIMARY security decision) is asked LAST
- IPv6 is asked at step 4, but kill switch at step 10 - these are related
- Security decisions scattered across steps 4, 9, 10, 11
- No parent-child relationships (kill switch should influence IPv6/DNS defaults)
- Features mixed with security decisions

---

## Proposed Design

### Design Principles

1. **Security decisions first** - After authentication, establish security posture
2. **Parent-child nesting** - Kill switch is umbrella; IPv6/DNS are children
3. **Smart defaults** - Kill switch=Y implies IPv6=disabled, DNS=PIA
4. **Logical grouping** - Auth → Security → Features → Server → Connect
5. **Reduced questions** - Skip child questions when parent implies them

### New Flow (velum_config.sh)

```
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 1: AUTHENTICATION                                         │
├─────────────────────────────────────────────────────────────────┤
│ 1.1 Load credentials from ~/.pia_credentials (if exists)        │
│ 1.2 Prompt for username (if needed)                             │
│ 1.3 Prompt for password (if needed)                             │
│ 1.4 Generate token via get_token.sh                             │
│ 1.5 Retry loop if authentication fails                          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 2: SECURITY PROFILE                                       │
├─────────────────────────────────────────────────────────────────┤
│ 2.1 KILL SWITCH? (Y/n) ← PRIMARY SECURITY DECISION              │
│     │                                                           │
│     ├─ If YES:                                                  │
│     │   2.1.1 LAN policy: block / detect / custom CIDR          │
│     │   2.1.2 IPv6 AUTO-DISABLED (interface + firewall)         │
│     │   2.1.3 PIA DNS DEFAULT = true (can override in 2.3)      │
│     │   → Skip to 2.3                                           │
│     │                                                           │
│     └─ If NO:                                                   │
│         2.2 IPv6 disable? (Y/n) - standalone question           │
│                                                                 │
│ 2.3 PIA DNS? (Y/n)                                              │
│     - Default: YES if kill switch enabled                       │
│     - Shown regardless, but with smart default                  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 3: CONNECTION FEATURES                                    │
├─────────────────────────────────────────────────────────────────┤
│ 3.1 Dedicated IP? (Y/n)                                         │
│     └─ If YES: DIP token input + validation                     │
│                                                                 │
│ 3.2 Port forwarding? (Y/n)                                      │
│     - Skipped if DIP doesn't support it                         │
│     - Note: Not available on US servers                         │
│                                                                 │
│ 3.3 Protocol: WireGuard / OpenVPN                               │
│     └─ If OpenVPN: UDP/TCP, Standard/Strong encryption          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 4: SERVER SELECTION                                       │
├─────────────────────────────────────────────────────────────────┤
│ (Skipped if DIP is configured - DIP has fixed server)           │
│                                                                 │
│ 4.1 Geo servers allowed? (Y/n)                                  │
│                                                                 │
│ 4.2 Server selection method:                                    │
│     ├─ Auto (lowest latency)                                    │
│     └─ Manual selection                                         │
│         4.2.1 Latency threshold (default 50ms)                  │
│         4.2.2 Display server list                               │
│         4.2.3 User selects server number                        │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ PHASE 5: CONNECT                                                │
├─────────────────────────────────────────────────────────────────┤
│ 5.1 Display configuration summary                               │
│ 5.2 Execute connection (get_region.sh → connect script)         │
│ 5.3 Show post-connection info (pia-test reminder, etc.)         │
└─────────────────────────────────────────────────────────────────┘
```

---

## Detailed Specifications

### Phase 2: Security Profile (Key Changes)

#### 2.1 Kill Switch (Primary Decision)

```
┌─────────────────────────────────────────────────────────────────┐
│ SECURITY CONFIGURATION                                          │
│                                                                 │
│ The kill switch blocks ALL internet traffic if the VPN drops,   │
│ preventing your real IP from being exposed.                     │
│                                                                 │
│ When enabled, the kill switch will also:                        │
│   • Block IPv6 traffic at the firewall level                    │
│   • Disable IPv6 on network interfaces                          │
│   • Default to using PIA's DNS servers                          │
│                                                                 │
│ Enable kill switch? [Y/n]:                                      │
└─────────────────────────────────────────────────────────────────┘
```

**If YES:**
- Automatically set `DISABLE_IPV6=yes` (don't ask)
- Automatically set `PIA_DNS=true` as default (can override)
- Prompt for LAN policy (block/detect)
- Show: "IPv6 protection: Enabled (interface + firewall)"

**If NO:**
- Proceed to ask IPv6 question separately
- DNS question has no default preference

#### 2.2 IPv6 (Only if Kill Switch = NO)

```
┌─────────────────────────────────────────────────────────────────┐
│ IPv6 can leak your real IP even when VPN is connected.          │
│                                                                 │
│ Disable IPv6? [Y/n]:                                            │
└─────────────────────────────────────────────────────────────────┘
```

#### 2.3 PIA DNS

```
┌─────────────────────────────────────────────────────────────────┐
│ Using third-party DNS could allow DNS monitoring.               │
│                                                                 │
│ Use PIA DNS servers? [Y/n]:     (default: Y if kill switch on)  │
└─────────────────────────────────────────────────────────────────┘
```

---

### Environment Variable Presets

Support for non-interactive mode via environment variables:

| Variable | Values | Notes |
|----------|--------|-------|
| `PIA_USER` | p####### | Username |
| `PIA_PASS` | string | Password |
| `PIA_KILLSWITCH` | true/false | Primary security toggle |
| `PIA_KILLSWITCH_LAN` | block/detect/CIDR | LAN policy |
| `DISABLE_IPV6` | yes/no | Auto-set if kill switch=true |
| `PIA_DNS` | true/false | Auto-default if kill switch=true |
| `PIA_PF` | true/false | Port forwarding |
| `VPN_PROTOCOL` | wireguard/openvpn_* | Connection protocol |
| `PREFERRED_REGION` | region-id | Server selection |
| `ALLOW_GEO_SERVERS` | true/false | Geo server filter |
| `MAX_LATENCY` | float | Latency threshold in seconds |
| `DIP_TOKEN` | DIP##... | Dedicated IP token |

**Smart defaults when `PIA_KILLSWITCH=true`:**
- `DISABLE_IPV6` defaults to `yes` (skip prompt)
- `PIA_DNS` defaults to `true` (show prompt with default)

---

### Configuration Summary (New Feature)

Before connecting, display a summary:

```
┌─────────────────────────────────────────────────────────────────┐
│ CONFIGURATION SUMMARY                                           │
├─────────────────────────────────────────────────────────────────┤
│ Security:                                                       │
│   Kill switch:    ENABLED (LAN: detect - 10.0.0.0/24)           │
│   IPv6:           Disabled (interface + firewall)               │
│   DNS:            PIA (10.0.0.243)                              │
│                                                                 │
│ Connection:                                                     │
│   Protocol:       WireGuard                                     │
│   Server:         DE Berlin (191.101.157.70)                    │
│   Port forward:   No                                            │
│                                                                 │
│ Press Enter to connect, or Ctrl+C to abort...                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Notes

### Files to Modify/Create

| File | Action |
|------|--------|
| `velum_config.sh` | NEW - Main velum-vpn configuration script |
| `run_setup.sh` | UNCHANGED - Legacy PIA script remains for compatibility |
| `pia-killswitch.sh` | MODIFY - Add IPv6 interface disable on enable |
| `README.md` | UPDATE - Document velum_config.sh as recommended approach |

### Migration Strategy

This is Phase 1 of the velum-vpn rewrite:

```
┌─────────────────────────────────────────────────────────────────┐
│ PIA manual-connections (upstream)                               │
│         ↓                                                       │
│ velum-vpn fork (current) - security hardening                   │
│         ↓                                                       │
│ velum-vpn rewrite (this spec) - velum_config.sh                 │
│         ↓                                                       │
│ Full velum-vpn (future) - complete script replacement           │
└─────────────────────────────────────────────────────────────────┘
```

**Coexistence approach:**
- `run_setup.sh` remains **untouched** as legacy PIA script
- `velum_config.sh` is the **new velum-vpn implementation**
- Both scripts work independently during transition period
- Users can choose which workflow to use
- All existing environment variables continue to work in both

**Future phases:**
- Phase 2: `velum_connect.sh` (replaces connect_to_wireguard_with_token.sh)
- Phase 3: `velum_region.sh` (replaces get_region.sh)
- Phase 4: Deprecate PIA scripts, velum becomes primary

### Security Improvements Integrated

The following hardening measures from the security audit are integrated:

1. **IPv6 dual protection** - Interface disable + firewall block when kill switch enabled
2. **TLS 1.2+** - Already enforced in all curl calls
3. **Credential cleanup** - Clear PIA_USER/PIA_PASS after token generation
4. **Token expiry** - Check and warn before connection

---

## Question Count Comparison

| Scenario | run_setup.sh | velum_config.sh |
|----------|--------------|-----------------|
| Kill switch ON, auto-server | 10 questions | 6 questions |
| Kill switch OFF, manual server | 12 questions | 10 questions |
| All defaults via env vars | 0 questions | 0 questions |

---

## Success Criteria

1. Kill switch is the FIRST security question (after auth)
2. IPv6 is automatically handled when kill switch enabled
3. Related questions are grouped by phase
4. Configuration summary shown before connect
5. Fewer questions for common secure setup
6. All existing env vars continue to work
7. QA tests pass with same functionality

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.2-draft | 2026-01-01 | Initial spec |
