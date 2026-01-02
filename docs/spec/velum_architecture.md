# velum-vpn Architecture Specification

## Project Vision

velum-vpn is a security-focused, VPN-agnostic, cross-platform VPN management toolkit.

**Goals:**
1. Work on macOS and Linux
2. Support multiple VPN providers (PIA today, Mullvad next, extensible to others)
3. Security-first design with defense in depth
4. Clean separation of concerns
5. Excellent user experience

---

## Protocol Decision: WireGuard Only

velum-vpn uses **WireGuard exclusively**. This is a deliberate security decision.

### Rationale

| Aspect | WireGuard | OpenVPN |
|--------|-----------|---------|
| Code size | ~4,000 lines | ~100,000+ lines |
| Attack surface | Minimal | Large |
| Cryptography | Fixed modern suite | Negotiable (downgrade risk) |
| Implementation | Kernel-level | Userspace daemon |
| Auditability | Formally verified | Too large to audit |
| Performance | Excellent | Good |

### WireGuard Cryptographic Suite (Non-negotiable)

```
- ChaCha20        (symmetric encryption)
- Poly1305        (message authentication)
- Curve25519      (key exchange)
- BLAKE2s         (hashing)
- SipHash24       (hashtable keys)
- HKDF            (key derivation)
```

No cipher negotiation = no downgrade attacks possible.

### OpenVPN Status

OpenVPN is **not supported** in velum-vpn. The only use case where OpenVPN
has an advantage (TCP over port 443 for firewall bypass) does not justify
the security tradeoffs for a security-focused tool.

If TCP tunneling is needed, consider:
- WireGuard over UDP with port hopping
- Running WireGuard over a TCP tunnel (udp2raw, etc.)
- Using a different tool for that specific use case

---

## Current State: PIA Script Audit

### Script Inventory

| PIA Script | Purpose | Lines | Velum Status |
|------------|---------|-------|--------------|
| `run_setup.sh` | Main entry, user prompts | 658 | Replace → `velum-config` |
| `get_token.sh` | Authentication | 127 | Extract → `providers/pia.sh` |
| `get_region.sh` | Server list, latency test | 326 | Extract → `providers/pia.sh` |
| `get_dip.sh` | Dedicated IP | 112 | Extract → `providers/pia.sh` |
| `connect_to_wireguard_with_token.sh` | WireGuard connection | 293 | Replace → `velum-connect` |
| `connect_to_openvpn_with_token.sh` | OpenVPN connection | 284 | **DROP** (WireGuard only) |
| `port_forwarding.sh` | Port forwarding | 223 | Extract → `providers/pia.sh` |
| `pia-killswitch.sh` | Kill switch | 337 | Extract → `os/{macos,linux}.sh` |
| `pia-test` | Connection validator | 447 | Replace → `velum-test` |

### Provider-Specific Code (PIA)

```
┌─────────────────────────────────────────────────────────────────┐
│ PIA-SPECIFIC APIs                                               │
├─────────────────────────────────────────────────────────────────┤
│ Auth API:                                                       │
│   POST https://www.privateinternetaccess.com/api/client/v2/token│
│   Form: username=p#######, password=xxx                         │
│   Returns: { token: "..." }                                     │
│                                                                 │
│ Server List API:                                                │
│   GET https://serverlist.piaservers.net/vpninfo/servers/v6      │
│   Returns: { regions: [...] }                                   │
│                                                                 │
│ WireGuard Key Exchange:                                         │
│   GET https://{hostname}:1337/addKey?pt={token}&pubkey={key}    │
│   Returns: { peer_ip, server_key, server_port, dns_servers }    │
│                                                                 │
│ Port Forwarding:                                                │
│   GET https://{hostname}:19999/getSignature?token={token}       │
│   GET https://{hostname}:19999/bindPort                         │
│                                                                 │
│ Dedicated IP:                                                   │
│   POST https://www.privateinternetaccess.com/api/client/v2/dedicated_ip │
│                                                                 │
│ CA Certificate: ca.rsa.4096.crt                                 │
│ DNS Servers: 10.0.0.243, 10.0.0.242                             │
│ Username Format: p####### (8 chars)                             │
└─────────────────────────────────────────────────────────────────┘
```

### Mullvad Differences (Target Provider #2)

```
┌─────────────────────────────────────────────────────────────────┐
│ MULLVAD APIs (preliminary - needs verification with account)   │
├─────────────────────────────────────────────────────────────────┤
│ Auth:                                                           │
│   Account number only (16 digits), no password                  │
│   No token generation - account number IS the auth              │
│                                                                 │
│ Server List:                                                    │
│   GET https://api.mullvad.net/www/relays/all/                   │
│   Different JSON structure                                      │
│                                                                 │
│ WireGuard Key Exchange:                                         │
│   POST https://api.mullvad.net/wg/                              │
│   Different mechanism - upload public key to account            │
│                                                                 │
│ Port Forwarding:                                                │
│   Different mechanism or not available on all servers           │
│                                                                 │
│ No Dedicated IP equivalent                                      │
│                                                                 │
│ DNS Servers: 10.64.0.1 (or custom)                              │
└─────────────────────────────────────────────────────────────────┘
```

### OS-Specific Code

```
┌─────────────────────────────────────────────────────────────────┐
│ macOS                          │ Linux                          │
├────────────────────────────────┼────────────────────────────────┤
│ IPv6 disable:                  │ IPv6 disable:                  │
│   networksetup -setv6off       │   sysctl -w net.ipv6...=1      │
│                                │                                │
│ DNS setup:                     │ DNS setup:                     │
│   networksetup -setdnsservers  │   resolvconf                   │
│   scutil --dns                 │   /etc/resolv.conf             │
│                                │                                │
│ Firewall (kill switch):        │ Firewall (kill switch):        │
│   pf / pfctl                   │   iptables / nftables          │
│                                │                                │
│ Interface detection:           │ Interface detection:           │
│   netstat -rn                  │   ip route                     │
│   route -n get default         │   ip addr                      │
│                                │                                │
│ Home directory:                │ Home directory:                │
│   dscl . -read /Users/...      │   getent passwd                │
│                                │                                │
│ Date math:                     │ Date math:                     │
│   date -v+1d                   │   date --date='1 day'          │
│                                │                                │
│ Notifications:                 │ Notifications:                 │
│   osascript                    │   notify-send                  │
│                                │                                │
│ WireGuard interface:           │ WireGuard interface:           │
│   utunX (via wireguard-go)     │   wgX or custom name           │
└────────────────────────────────┴────────────────────────────────┘
```

---

## Velum Architecture

### Directory Structure

```
velum-vpn/
├── bin/                          # User-facing commands
│   ├── velum                     # Main CLI entry point
│   ├── velum-config              # Interactive configuration
│   ├── velum-connect             # Connect to VPN
│   ├── velum-disconnect          # Disconnect from VPN
│   ├── velum-status              # Connection status
│   └── velum-test                # Connection validator
│
├── lib/                          # Core libraries
│   ├── velum-core.sh             # Shared functions, colors, logging
│   ├── velum-security.sh         # Security utilities (validation, cleanup)
│   │
│   ├── os/                       # OS abstraction layer
│   │   ├── detect.sh             # OS detection
│   │   ├── macos.sh              # macOS-specific implementations
│   │   └── linux.sh              # Linux-specific implementations
│   │
│   └── providers/                # VPN provider adapters
│       ├── provider-base.sh      # Base provider interface
│       ├── pia.sh                # PIA implementation
│       └── mullvad.sh            # Mullvad implementation (future)
│
├── etc/                          # Configuration
│   ├── velum.conf.example        # Example config file
│   └── providers/                # Provider-specific assets
│       ├── pia/
│       │   └── ca.rsa.4096.crt   # PIA CA certificate
│       └── mullvad/
│           └── (future)
│
├── docs/                         # Documentation
│   └── spec/                     # Specifications
│
└── legacy/                       # Original PIA scripts (reference only)
    ├── run_setup.sh
    ├── get_token.sh
    └── ...
```

### Component Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         USER INTERFACE                          │
│  velum-config    velum-connect    velum-status    velum-test    │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
┌─────────────────────────────────▼───────────────────────────────┐
│                         CORE LIBRARY                            │
│  velum-core.sh (logging, colors, utils)                         │
│  velum-security.sh (validation, credential cleanup)             │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
          ┌───────────────────────┼───────────────────────┐
          │                       │                       │
┌─────────▼─────────┐   ┌─────────▼─────────┐   ┌─────────▼─────────┐
│   OS LAYER        │   │  PROVIDER LAYER   │   │  WIREGUARD LAYER  │
│                   │   │                   │   │                   │
│  os/detect.sh     │   │  providers/       │   │  wg-quick         │
│  os/macos.sh      │   │    pia.sh         │   │  wg (tools)       │
│  os/linux.sh      │   │    mullvad.sh     │   │  wireguard-go     │
│                   │   │    (future...)    │   │    (macOS)        │
│  Functions:       │   │                   │   │                   │
│  - disable_ipv6   │   │  Interface:       │   │  Config:          │
│  - set_dns        │   │  - authenticate   │   │  - [Interface]    │
│  - killswitch_*   │   │  - get_servers    │   │  - [Peer]         │
│  - detect_subnet  │   │  - wg_exchange    │   │  - PostUp/Down    │
│  - notify         │   │  - port_forward   │   │                   │
└───────────────────┘   └───────────────────┘   └───────────────────┘
```

### Provider Interface

Each provider must implement these functions:

```bash
# lib/providers/provider-base.sh

# Provider metadata
provider_name()           # Return provider name (e.g., "PIA", "Mullvad")
provider_version()        # Return adapter version

# Authentication
provider_auth_type()      # Return: "username_password" | "account_number"
provider_authenticate()   # Authenticate and return token/session
provider_validate_creds() # Validate credential format before auth

# Server list
provider_get_servers()    # Fetch and return server list (normalized JSON)
provider_test_latency()   # Test latency to a server
provider_filter_servers() # Filter by criteria (geo, port_forward, etc.)

# WireGuard Connection
provider_wg_exchange()    # Exchange WireGuard keys with provider
provider_wg_config()      # Return WireGuard config parameters
provider_wg_endpoint()    # Return server endpoint (IP:port)

# Features (optional - provider may not support)
provider_supports_pf()    # Port forwarding supported?
provider_enable_pf()      # Enable port forwarding
provider_refresh_pf()     # Refresh port forwarding (keepalive)
provider_supports_dip()   # Dedicated IP supported?

# Provider-specific
provider_get_dns()        # Return provider's DNS servers
provider_get_ca_cert()    # Return path to CA certificate (for API auth)
```

### OS Interface

Each OS module must implement these functions:

```bash
# lib/os/detect.sh
detect_os()               # Return: "macos" | "linux"
detect_distro()           # Return distro name (for Linux)

# lib/os/{macos,linux}.sh

# IPv6
os_disable_ipv6()         # Disable IPv6 on all interfaces
os_enable_ipv6()          # Re-enable IPv6

# DNS
os_set_dns()              # Set DNS servers
os_restore_dns()          # Restore original DNS

# Firewall / Kill Switch
os_killswitch_enable()    # Enable kill switch
os_killswitch_disable()   # Disable kill switch
os_killswitch_status()    # Return kill switch status

# Network detection
os_detect_gateway()       # Detect default gateway
os_detect_interface()     # Detect primary network interface
os_detect_subnet()        # Detect local subnet (CIDR)
os_detect_vpn_interface() # Detect VPN tunnel interface

# Notifications
os_notify()               # Send system notification

# Home directory
os_get_home()             # Get user's home directory (even under sudo)
```

---

## Implementation Phases

### Phase 1: Foundation + Config
**Goal:** Core infrastructure and configuration tool (macOS)

- [ ] Create directory structure (`bin/`, `lib/`, `lib/os/`, `lib/providers/`)
- [ ] Implement `lib/velum-core.sh` (logging, colors, utils, security)
- [ ] Implement `lib/os/detect.sh` (OS detection)
- [ ] Implement `lib/os/macos.sh` (IPv6, DNS, kill switch, network detection)
- [ ] Implement `bin/velum-config` (replaces run_setup.sh with new UX)
- [ ] Test on macOS

### Phase 2: Provider Abstraction + Connect
**Goal:** VPN provider abstraction and WireGuard connection (macOS + PIA)

- [ ] Implement `lib/providers/provider-base.sh` (interface definition)
- [ ] Implement `lib/providers/pia.sh` (auth, servers, WG exchange, port forward)
- [ ] Implement `bin/velum-connect` (WireGuard connection)
- [ ] Implement `bin/velum-disconnect` (clean disconnect)
- [ ] Integrate with velum-config
- [ ] Test full workflow on macOS with PIA

### Phase 3: Linux Support
**Goal:** Cross-platform (Debian/Ubuntu focus)

- [ ] Implement `lib/os/linux.sh` (IPv6, DNS, kill switch, network detection)
- [ ] Handle iptables/nftables for kill switch
- [ ] Handle resolvconf/systemd-resolved for DNS
- [ ] Test all components on Debian/Ubuntu
- [ ] Verify feature parity with macOS

### Phase 4: Mullvad Support
**Goal:** Prove provider abstraction works

- [ ] Research Mullvad API (requires account purchase)
- [ ] Implement `lib/providers/mullvad.sh`
- [ ] Test provider switching in velum-config
- [ ] Document multi-provider workflow

### Phase 5: Polish + Release
**Goal:** Production-ready tool

- [ ] Implement `bin/velum` (unified CLI wrapper)
- [ ] Implement `bin/velum-status` (connection status)
- [ ] Implement `bin/velum-test` (replaces pia-test, provider-agnostic)
- [ ] Configuration file support (`~/.config/velum/velum.conf`)
- [ ] Man pages / comprehensive documentation
- [ ] Release v1.0

---

## Configuration File Format

```ini
# ~/.config/velum/velum.conf

[default]
provider = pia
protocol = wireguard

[security]
killswitch = true
killswitch_lan = detect
ipv6 = disabled
dns = provider    # provider | custom | system

[pia]
credentials_file = ~/.pia_credentials
# username and password read from file, never stored here
port_forwarding = false
allow_geo_servers = false

[mullvad]
credentials_file = ~/.mullvad_credentials
# account number read from file

[connection]
max_latency = 0.05
preferred_region = auto
```

---

## Naming Conventions

| PIA Script | Velum Equivalent |
|------------|------------------|
| `run_setup.sh` | `bin/velum-config` |
| `get_token.sh` | `lib/providers/pia.sh::provider_authenticate()` |
| `get_region.sh` | `lib/providers/pia.sh::provider_get_servers()` |
| `connect_to_wireguard_with_token.sh` | `bin/velum-connect` |
| `connect_to_openvpn_with_token.sh` | **DROPPED** (WireGuard only) |
| `port_forwarding.sh` | `lib/providers/pia.sh::provider_enable_pf()` |
| `pia-killswitch.sh` | `lib/os/{macos,linux}.sh::os_killswitch_*()` |
| `pia-test` | `bin/velum-test` |

---

## Security Principles (Carried Forward)

1. **TLS 1.2+ enforced** on all HTTPS connections
2. **Credential cleanup** - unset sensitive variables after use
3. **File permissions** - 700 for directories, 600 for sensitive files
4. **Dead-man switch** - refuse to run if insecure flags detected
5. **API validation** - validate all API responses before use
6. **Token expiry** - check and warn about expired tokens
7. **Defense in depth** - IPv6 disabled at interface AND firewall level
8. **No eval** - safe command construction

---

## Success Criteria

1. `velum-config` provides same functionality as `run_setup.sh` with better UX
2. Same security level or better
3. Works on both macOS and Linux (Debian first)
4. Provider-agnostic architecture proven by adding Mullvad
5. Clean, maintainable codebase
6. Comprehensive documentation

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.1-draft | 2026-01-01 | Initial architecture spec |
