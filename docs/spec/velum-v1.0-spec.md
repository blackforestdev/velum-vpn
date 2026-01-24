# Velum VPN v1.0 Specification

**Version:** 1.0.0
**Date:** 2026-01-05
**Status:** Current Implementation

---

## Table of Contents

1. [Overview & Vision](#1-overview--vision)
2. [Architecture](#2-architecture)
3. [Commands Reference](#3-commands-reference)
4. [Provider System](#4-provider-system)
5. [OS Abstraction Layer](#5-os-abstraction-layer)
6. [Security Model](#6-security-model)
7. [Jurisdiction & Detection](#7-jurisdiction--detection)
8. [Configuration System](#8-configuration-system)
9. [Future Direction: Go/Rust Port](#9-future-direction-gorust-port)
10. [Appendices](#10-appendices)

---

## 1. Overview & Vision

### 1.1 Project Description

Velum VPN is a security-focused, provider-agnostic VPN management suite for macOS and Linux. It provides unified control for multiple VPN providers with defense-in-depth security features, using WireGuard exclusively for all connections.

### 1.2 Design Philosophy

**WireGuard Only**

Velum uses WireGuard exclusively. This is a deliberate security decision:

| Aspect | WireGuard | OpenVPN |
|--------|-----------|---------|
| Code size | ~4,000 lines | ~100,000+ lines |
| Attack surface | Minimal | Large |
| Cryptography | Fixed modern suite | Negotiable (downgrade risk) |
| Implementation | Kernel-level | Userspace daemon |
| Auditability | Formally verified | Too large to audit |

WireGuard's cryptographic suite is non-negotiable:
- ChaCha20 (symmetric encryption)
- Poly1305 (message authentication)
- Curve25519 (key exchange)
- BLAKE2s (hashing)
- HKDF (key derivation)

**Defense in Depth**

Multiple layers of protection:
- Kill switch at firewall level (pf/iptables/nftables)
- IPv6 blocked at both interface AND firewall level
- DNS routed through VPN with encrypted fallback
- Credential cleanup after use
- TLS 1.2+ enforced on all API calls

**Provider Agnostic**

Pluggable provider architecture allows supporting multiple VPN services through a standard interface. Currently supported: PIA, Mullvad, IVPN.

### 1.3 Target Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS (Darwin) | Primary | Fully tested on macOS 12+ |
| Debian/Ubuntu Linux | Secondary | Core features implemented, testing ongoing |
| Other Linux distros | Experimental | Should work with iptables/nftables |

### 1.4 Current Version

**v0.1.0-dev** - Development release with all core features implemented.

---

## 2. Architecture

### 2.1 Directory Structure

```
velum-vpn/
├── bin/                              # User-facing commands (9 scripts)
│   ├── velum                         # Main CLI dispatcher
│   ├── velum-config                  # Interactive configuration wizard
│   ├── velum-connect                 # Establish VPN connection
│   ├── velum-disconnect              # Tear down VPN connection
│   ├── velum-status                  # Show connection status
│   ├── velum-test                    # Comprehensive connection validator
│   ├── velum-killswitch              # Kill switch management
│   ├── velum-monitor                 # Background health monitoring
│   └── velum-webrtc                  # WebRTC leak test launcher
│
├── lib/                              # Core libraries
│   ├── velum-core.sh                 # Shared utilities, logging, paths
│   ├── velum-security.sh             # Security validation, credential cleanup
│   ├── velum-jurisdiction.sh         # Country alliance classification
│   ├── velum-detection.sh            # VPN detection checking
│   │
│   ├── os/                           # OS abstraction layer
│   │   ├── detect.sh                 # OS detection and module loader
│   │   ├── macos.sh                  # macOS implementations
│   │   └── linux.sh                  # Linux implementations
│   │
│   └── providers/                    # VPN provider plugins
│       ├── provider-base.sh          # Standard interface definition
│       ├── pia.sh                    # Private Internet Access
│       ├── mullvad.sh                # Mullvad VPN
│       └── ivpn.sh                   # IVPN
│
├── etc/                              # Static assets
│   └── providers/
│       └── pia/
│           └── ca.rsa.4096.crt       # PIA CA certificate
│
└── docs/                             # Documentation
    └── spec/
        └── velum-v1.0-spec.md        # This specification
```

### 2.2 Component Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                           USER INTERFACE                             │
│  velum    velum-config    velum-connect    velum-status    velum-test│
│           velum-disconnect    velum-killswitch    velum-monitor      │
└─────────────────────────────────┬───────────────────────────────────┘
                                  │
┌─────────────────────────────────▼───────────────────────────────────┐
│                           CORE LIBRARIES                             │
│  velum-core.sh        velum-security.sh                              │
│  velum-jurisdiction.sh    velum-detection.sh                         │
└─────────────────────────────────┬───────────────────────────────────┘
                                  │
          ┌───────────────────────┼───────────────────────┐
          │                       │                       │
┌─────────▼─────────┐   ┌─────────▼─────────┐   ┌─────────▼─────────┐
│    OS LAYER       │   │  PROVIDER LAYER   │   │  WIREGUARD        │
│                   │   │                   │   │                   │
│  os/detect.sh     │   │  providers/       │   │  wg-quick         │
│  os/macos.sh      │   │    pia.sh         │   │  wg (tools)       │
│  os/linux.sh      │   │    mullvad.sh     │   │  wireguard-go     │
│                   │   │    ivpn.sh        │   │    (macOS)        │
│  Functions:       │   │                   │   │                   │
│  - os_disable_ipv6│   │  Interface:       │   │  Config:          │
│  - os_set_dns     │   │  - authenticate   │   │  - [Interface]    │
│  - os_killswitch_*│   │  - get_servers    │   │  - [Peer]         │
│  - os_detect_*    │   │  - wg_exchange    │   │  - PostUp/Down    │
│  - os_notify      │   │  - port_forward   │   │                   │
└───────────────────┘   └───────────────────┘   └───────────────────┘
```

### 2.3 Data Flow

**Configuration Flow:**
```
velum-config
    │
    ├─► Load existing config (if present)
    ├─► Phase 1: Provider selection → load provider module
    ├─► Phase 2: Authentication → validate credentials, get token
    ├─► Phase 3: Security profile → kill switch, IPv6, DNS
    ├─► Phase 4: Features → port forwarding, dedicated IP
    ├─► Phase 5: Server selection → latency test, jurisdiction info
    └─► Save to ~/.config/velum/velum.conf
```

**Connection Flow:**
```
velum-connect
    │
    ├─► Load config from ~/.config/velum/velum.conf
    ├─► Validate token expiry
    ├─► Select server (auto or from config)
    ├─► Generate/load WireGuard keypair
    ├─► Exchange keys with provider API
    ├─► Create /etc/wireguard/velum.conf
    ├─► Enable kill switch (if configured)
    ├─► Disable IPv6 (if configured)
    ├─► Start WireGuard via wg-quick
    ├─► Enable port forwarding (if configured)
    └─► Start background monitor
```

**Monitoring Flow:**
```
velum-monitor daemon
    │
    └─► Loop every 10 seconds:
        ├─► Check WireGuard interface status
        ├─► Check kill switch rules
        ├─► Check handshake freshness (stale if >180s)
        └─► Send notifications on state changes
```

---

## 3. Commands Reference

### 3.1 velum (Main Dispatcher)

**Synopsis:**
```
velum <command> [options]
velum -h | --help
velum -v | --version
```

**Commands:**
| Command | Description |
|---------|-------------|
| config | Configure VPN settings interactively |
| connect | Connect to VPN |
| disconnect | Disconnect from VPN |
| status | Show connection status |
| test | Test VPN connection for leaks |
| killswitch (ks) | Manage kill switch |
| webrtc | Open browser for WebRTC leak test |
| monitor | VPN health monitoring daemon |

**Exit Codes:**
- `0` - Success
- `1` - Unknown command

**Privileges:** None required (delegates to subcommands)

---

### 3.2 velum-config (Interactive Configuration)

**Synopsis:**
```
velum config
```

**Description:** Interactive 5-phase configuration wizard for provider selection, authentication, security settings, features, and server selection.

**Phases:**
1. Provider Selection (PIA, Mullvad, IVPN)
2. Authentication (username/password or account number)
3. Security Profile (kill switch, IPv6, DNS)
4. Connection Features (Dedicated IP, port forwarding)
5. Server Selection (auto or manual with latency/jurisdiction info)

**Exit Codes:**
- `0` - Configuration saved successfully
- `1` - Fatal error (missing provider, auth failure, OS requirements not met)
- `130` - User cancelled (Ctrl+C)

**Dependencies:**
- curl, jq, wg
- velum-core.sh, velum-security.sh
- velum-jurisdiction.sh, velum-detection.sh
- lib/os/detect.sh, lib/providers/*

**State Files Written:**
| File | Permissions | Content |
|------|-------------|---------|
| ~/.config/velum/velum.conf | 600 | Configuration array |
| ~/.config/velum/tokens/* | 600 | Auth tokens |

**Privileges:** User (creates files in user's home)

---

### 3.3 velum-connect (Establish Connection)

**Synopsis:**
```
sudo velum connect
```

**Description:** Establishes VPN connection using saved configuration. Generates WireGuard keys, exchanges with provider, creates tunnel, enables security features.

**Exit Codes:**
- `0` - Connected successfully
- `1` - Fatal error (missing config, expired token, WG setup failed)

**Dependencies:**
- sudo, wg-quick, wg, curl, jq
- route (macOS) or ip (Linux)
- velum-core.sh, velum-security.sh
- lib/os/detect.sh, lib/providers/*

**State Files:**
| File | Operation | Content |
|------|-----------|---------|
| ~/.config/velum/velum.conf | Read | Configuration |
| ~/.config/velum/tokens/* | Read/Write | Auth tokens, WG private key |
| /etc/wireguard/velum.conf | Write | WireGuard configuration |
| $VELUM_RUN_DIR/pf.pid | Write | Port forwarding daemon PID |
| $VELUM_RUN_DIR/pf.port | Write | Forwarded port number |

**Privileges:** Root required (WireGuard, firewall, DNS)

---

### 3.4 velum-disconnect (Tear Down Connection)

**Synopsis:**
```
sudo velum disconnect
```

**Description:** Cleanly tears down VPN connection, stops monitoring, restores network settings.

**Sequence:**
1. Stop background monitor
2. Stop port forwarding daemon
3. Set intentional disconnect flag
4. Bring down WireGuard (triggers PostDown)
5. Clear disconnect flag
6. Restore IPv6
7. Restore DNS

**Exit Codes:**
- `0` - Disconnected successfully
- `1` - Root check failed

**State Files:**
| File | Operation |
|------|-----------|
| $VELUM_RUN_DIR/pf.pid | Read (kill PF daemon) |
| $VELUM_RUN_DIR/intentional-disconnect | Create/Delete |
| /etc/wireguard/velum.conf | Read (for wg-quick down) |

**Privileges:** Root required

---

### 3.5 velum-status (Connection Status)

**Synopsis:**
```
velum status
sudo velum status  # For complete info
```

**Description:** Displays current connection status including IP, endpoint, data transfer, kill switch, DNS, and token validity.

**Output Fields:**
- Connection status (connected/disconnected)
- VPN interface name
- Public IP address
- VPN server endpoint
- Data transfer (RX/TX)
- Last handshake time
- Kill switch status
- IPv6 status
- DNS servers
- Port forwarding status
- Token validity

**Exit Codes:**
- `0` - Always (informational only)

**Dependencies:**
- curl, wg, netstat/ip
- velum-core.sh, velum-security.sh, lib/os/detect.sh

**Privileges:** User (partial info) or Root (complete info)

---

### 3.6 velum-test (Connection Validator)

**Synopsis:**
```
sudo velum test
```

**Description:** Comprehensive VPN connection validation with 17 test categories.

**Test Categories:**
1. WireGuard Interface - Status, handshake, transfer, AllowedIPs
2. Public IP Check - IP lookup, geolocation, provider detection
3. DNS Leak Test - Resolution through VPN, fallback routes
4. Route Table Check - Verify 0.0.0.0/0 routing
5. Traffic Test - Ping, HTTPS connectivity, MTU
6. Kill Switch - Firewall rules verification
7. Leak Sources - IPv6, remote access tools, WebRTC risks
8. Port Forwarding - Status and port verification
9. VPN Detection - Check if IP flagged as VPN/proxy
10. Reconnection - Config age and reconnect info

**Exit Codes:**
- `0` - All tests passed
- `1` - Any tests failed
- `2` - Tests passed but warnings present

**External APIs Used:**
- api.ipify.org, icanhazip.com (public IP)
- ipinfo.io (geolocation)
- ip-api.com, scamalytics.com (VPN detection)

**Privileges:** Root required

---

### 3.7 velum-killswitch (Kill Switch Management)

**Synopsis:**
```
velum killswitch <command> [options]
velum ks <command> [options]  # Alias

Commands:
  enable    Enable kill switch
  disable   Disable kill switch
  status    Show kill switch status
  notify    Send VPN drop notification

Options (enable):
  --vpn-ip <IP>         VPN server IP (required)
  --vpn-port <PORT>     Server port (default: 1337)
  --vpn-iface <IFACE>   VPN interface (default: auto-detect)
  --lan-policy <POLICY> LAN policy: block|detect|<CIDR>
```

**Exit Codes:**
- `0` - Success
- `1` - Root check failed or error

**Privileges:**
- enable/disable: Root required
- status/notify: User

---

### 3.8 velum-monitor (Health Monitoring)

**Synopsis:**
```
velum monitor <command>

Commands:
  start   Start background monitoring daemon
  stop    Stop monitoring daemon
  status  Show monitor status
```

**Monitoring Checks (every 10 seconds):**
- VPN interface status
- Kill switch rule verification
- Handshake freshness (stale if >180 seconds)

**Notifications Sent:**
- Monitor start: "VPN Monitor Active"
- VPN connects: "VPN Connected"
- VPN disconnects: "VPN Disconnected" (critical + audio)
- Kill switch disabled: "Kill Switch Disabled" (critical)
- Stale handshake: "VPN Connection Stale"

**State Files:**
| File | Content |
|------|---------|
| $VELUM_RUN_DIR/monitor.pid | Daemon PID |
| $VELUM_RUN_DIR/monitor.state | started, vpn_up, ks_active, handshake_age |
| $VELUM_RUN_DIR/monitor.log | Activity log |

**Privileges:** Root required for start and status (runtime files are 0600)

**Known Issue:** Desktop notifications currently broken - should use `os_notify()` from lib/os/macos.sh instead of local `notify()` function.

---

### 3.9 velum-webrtc (WebRTC Leak Test)

**Synopsis:**
```
velum webrtc
```

**Description:** Detects default browser, displays current public IP, and opens browserleaks.com/webrtc for WebRTC leak testing.

**Supported Browsers:**
- Firefox, Chrome/Chromium, Safari, Brave
- GNOME Web (Epiphany), Falkon, Konqueror

**Exit Codes:**
- `0` - Browser opened
- `1` - Could not open browser (displays manual URL)

**Privileges:** User

---

## 4. Provider System

### 4.1 Provider Interface

All providers must implement these functions (defined in `lib/providers/provider-base.sh`):

**Metadata:**
```bash
provider_name()           # Return provider name (e.g., "PIA", "Mullvad")
provider_version()        # Return adapter version
```

**Authentication:**
```bash
provider_auth_type()      # Return: "username_password" | "account_number"
provider_authenticate()   # Authenticate and return token
provider_validate_creds() # Validate credential format
```

**Server Management:**
```bash
provider_get_servers()    # Fetch normalized server list (JSON)
provider_test_latency()   # Test latency to server (ms)
provider_filter_servers() # Filter by geo, port_forward, etc.
```

**WireGuard:**
```bash
provider_wg_exchange()    # Exchange WireGuard keys with provider
provider_wg_config()      # Return WireGuard config parameters
provider_wg_endpoint()    # Return server endpoint (IP:port)
```

**Features (optional):**
```bash
provider_supports_pf()    # Port forwarding supported?
provider_enable_pf()      # Enable port forwarding
provider_refresh_pf()     # Refresh port forwarding keepalive
provider_supports_dip()   # Dedicated IP supported?
provider_get_dip()        # Get dedicated IP info
```

**Provider-Specific:**
```bash
provider_get_dns()        # Return DNS servers
provider_get_ca_cert()    # Return CA certificate path
```

### 4.2 Feature Support Matrix

| Feature | PIA | Mullvad | IVPN |
|---------|-----|---------|------|
| **Auth Type** | username_password | account_number | account_number |
| **Credential Format** | p####### + password | 16 digits | i-XXXX-XXXX-XXXX |
| **Token Lifetime** | 24 hours | Long-lived | Subscription-based |
| **Port Forwarding** | YES | NO | NO |
| **Dedicated IP** | YES | NO | NO |
| **Geo Server Filter** | YES | NO | NO |
| **WireGuard Port** | Dynamic | 51820 | 2049 |
| **CA Certificate** | Required | Not needed | Not needed |
| **Server Cache TTL** | 5 min | 5 min | 5 min |

### 4.3 PIA (Private Internet Access)

**Authentication API:**
```
POST https://www.privateinternetaccess.com/api/client/v2/token
Content-Type: application/x-www-form-urlencoded

username=p1234567&password=secretpassword

Response:
{
  "token": "...",
  "message_type": "login"
}
```

**Server List API:**
```
GET https://serverlist.piaservers.net/vpninfo/servers/v6

Response:
{
  "regions": [
    {
      "id": "de_berlin",
      "name": "DE Berlin",
      "country": "DE",
      "port_forward": true,
      "geo": false,
      "servers": {
        "wg": [
          {
            "ip": "158.173.21.201",
            "cn": "berlin401"
          }
        ]
      }
    }
  ]
}
```

**WireGuard Key Exchange:**
```
GET https://{hostname}:1337/addKey?pt={token}&pubkey={base64_pubkey}

# Uses --connect-to to bypass DNS and connect directly to IP
# CA certificate required: etc/providers/pia/ca.rsa.4096.crt

Response:
{
  "status": "OK",
  "peer_ip": "10.x.x.x",
  "server_key": "[base64_44_chars]=",
  "server_port": 1337,
  "dns_servers": ["10.0.0.243"]
}
```

**Port Forwarding - Get Signature:**
```
GET https://{hostname}:19999/getSignature?token={auth_token}

Response:
{
  "status": "OK",
  "payload": "...",
  "signature": "..."
}
```

**Port Forwarding - Bind Port:**
```
GET https://{hostname}:19999/bindPort?payload={payload}&signature={signature}

Response:
{
  "status": "OK",
  "port": 12345
}
```

**Dedicated IP:**
```
POST https://www.privateinternetaccess.com/api/client/v2/dedicated_ip

# Separate token from main account
# Returns dedicated IP details
```

**DNS Servers:** 10.0.0.243, 10.0.0.242

### 4.4 Mullvad

**Authentication API:**
```
POST https://api.mullvad.net/auth/v1/token
Content-Type: application/json

{"account_number": "1234567890123456"}

Response:
{
  "access_token": "...",
  "expiry": "2026-12-31T23:59:59Z"
}
```

**Server List API:**
```
GET https://api.mullvad.net/www/relays/all/

Response:
[
  {
    "hostname": "se-sto-wg-001",
    "type": "wireguard",
    "active": true,
    "ipv4_addr_in": "185.213.154.68",
    "country_code": "se",
    "city_code": "sto",
    "pubkey": "..."
  }
]
```

**WireGuard Key Registration (Legacy API):**
```
POST https://api.mullvad.net/wg/
Content-Type: application/x-www-form-urlencoded

account={account_number}&pubkey={base64_pubkey}

Response (success):
10.73.101.32/32,fc00:bbbb:bbbb:bb01::a:651f/128

Response (error):
{"error": "..."}
```

**DNS Server:** 10.64.0.1

**Notes:**
- Port forwarding removed July 2023
- No dedicated IP feature
- Uses legacy WireGuard API to avoid device management

### 4.5 IVPN

**Authentication API:**
```
POST https://api.ivpn.net/v4/session/new
Content-Type: application/json

{"username": "i-xxxx-xxxx-xxxx"}

Response:
{
  "token": "...",
  "service_status": {
    "is_active": true,
    "active_until": 1735689599
  }
}
```

**Account ID Formats:**
- New: `i-XXXX-XXXX-XXXX` (alphanumeric with dashes)
- Legacy: `ivpn-XXX-XXX-XXX`

**Server List API:**
```
GET https://api.ivpn.net/v5/servers.json

Response:
{
  "wireguard": [
    {
      "gateway": "ch.gw.ivpn.net",
      "country_code": "CH",
      "country": "Switzerland",
      "city": "Zurich",
      "hosts": [
        {
          "hostname": "ch1.wg.ivpn.net",
          "host": "185.212.170.139",
          "public_key": "..."
        }
      ]
    }
  ]
}
```

**WireGuard Key Setting:**
```
POST https://api.ivpn.net/v4/session/wg/set
Content-Type: application/json

{
  "session_token": "...",
  "public_key": "..."
}

Response:
{
  "status": 200,
  "ip_address": "10.x.x.x/32"
}
```

**Session Logout:**
```
POST https://api.ivpn.net/v4/session/delete
```

**DNS Server:** 10.0.254.1

**WireGuard Port:** 2049

**Notes:**
- Session tied to subscription status
- Captcha protection on auth (status code 70011)
- No port forwarding or dedicated IP

### 4.6 Adding New Providers

To add a new provider:

1. Create `lib/providers/{provider}.sh`
2. Implement all required interface functions
3. Add provider to selection list in `velum-config`
4. Create CA certificate file if required (in `etc/providers/{provider}/`)
5. Document API endpoints and auth mechanism

---

## 5. OS Abstraction Layer

### 5.1 OS Interface

All OS modules implement these functions (defined in `lib/os/detect.sh`):

**Detection:**
```bash
detect_os()               # Return: "macos" | "linux" | "unsupported"
detect_distro()           # Return Linux distro ID
detect_package_manager()  # Return: apt | dnf | yum | pacman | brew
```

**Network Detection:**
```bash
os_detect_gateway()       # Get default gateway IP
os_detect_interface()     # Get primary network interface
os_detect_vpn_interface() # Detect WireGuard tunnel interface
os_detect_subnet()        # Calculate local subnet (CIDR)
os_get_local_ip()         # Get local IP on primary interface
```

**IPv6 Management:**
```bash
os_disable_ipv6()         # System-wide IPv6 disable
os_enable_ipv6()          # System-wide IPv6 enable
os_ipv6_enabled()         # Check if IPv6 enabled
```

**DNS Management:**
```bash
os_set_dns()              # Set DNS servers
os_backup_dns()           # Backup current DNS config
os_restore_dns()          # Restore DNS from backup
os_get_dns()              # Get current DNS servers
```

**Kill Switch:**
```bash
os_killswitch_enable()    # Enable firewall kill switch
os_killswitch_disable()   # Disable firewall kill switch
os_killswitch_status()    # Get status: active | inactive | error
os_killswitch_rule_count()# Get number of active rules
```

**Utilities:**
```bash
os_notify()               # Send system notification
os_get_home()             # Get user home (respects sudo)
os_date_to_epoch()        # Date parsing
os_date_add_days()        # Date arithmetic
```

### 5.2 macOS Implementation

**File:** `lib/os/macos.sh`

**Network Detection:**
- Gateway: `route -n get default`
- Interface: From route output
- VPN interface: `netstat -rn` looking for `0/1` routes to utun*
- Subnet: Manual netmask-to-CIDR conversion

**IPv6 Management:**
- Disable: `networksetup -setv6off` on all services
- Enable: `networksetup -setv6automatic` on all services
- Enumerates via `networksetup -listallnetworkservices`

**DNS Management:**
- Set: `networksetup -setdnsservers`
- Backup: Parse to `$VELUM_LIB_DIR/dns_backup` (root-only, 0600)
- Restore: Per-service from backup file
- Flush: `dscacheutil -flushcache && killall -HUP mDNSResponder`

**Kill Switch (pf):**
- Anchor: `velum_killswitch`
- Rules file: `/etc/pf.anchors/velum_killswitch`

Rules structure:
```
block all
block quick inet6 all
pass on lo0 all
pass on $vpn_iface all
pass on $phys_iface udp to $vpn_ip port $vpn_port
pass on $phys_iface udp port 67-68
pass on $phys_iface from $subnet to $subnet  # if LAN allowed
pass on $phys_iface to 224.0.0.0/4           # Multicast
pass on $phys_iface from 169.254.0.0/16      # AirDrop
```

**Notifications:**
- Method: osascript (AppleScript)
- Runs as console user for proper notification center
- Fallback: `afplay` for audio alerts

### 5.3 Linux Implementation

**File:** `lib/os/linux.sh`

**Network Detection:**
- Gateway: `ip route show default`
- Interface: From route output
- VPN interface: `ip link show type wireguard`
- Subnet: CIDR from `ip -4 addr show`

**IPv6 Management:**
- Disable: `sysctl net.ipv6.conf.all.disable_ipv6=1`
- Also per-interface via `/proc/sys/net/ipv6/conf/*/disable_ipv6`
- Enable: Set to 0

**DNS Management (auto-detects backend):**

1. **systemd-resolved** (modern):
   - `resolvectl` or `systemd-resolve`
   - Per-interface configuration

2. **resolvconf** (legacy Debian):
   - Interface stanza management
   - `resolvconf -a/-d`

3. **Direct /etc/resolv.conf** (fallback):
   - Write directly
   - `chattr +i` to prevent overwriting

**Kill Switch (auto-detects firewall):**

**nftables (preferred):**
- Table: `velum_killswitch` (inet family)
- Chains: input/output with priority -100

```
table inet velum_killswitch {
  chain input {
    type filter hook input priority -100; policy drop;
    iif lo accept
    ct state established,related accept
    iifname $vpn_iface accept
    udp sport 67 dport 68 accept
  }
  chain output {
    type filter hook output priority -100; policy drop;
    oif lo accept
    ct state established,related accept
    oifname $vpn_iface accept
    oifname $phys_iface udp dport $vpn_port ip daddr $vpn_ip accept
    udp sport 68 dport 67 accept
  }
}
```

**iptables (fallback):**
- Chain: `VELUM_KILLSWITCH`
- Separate rules for IPv4 and IPv6 (DROP all inet6)

**Notifications:**
- Method: `notify-send` (freedesktop.org)
- Urgency levels: critical | normal

### 5.4 Cross-Platform Status

| Feature | macOS | Linux | Notes |
|---------|-------|-------|-------|
| Network detection | Tested | Tested | |
| IPv6 disable/enable | Tested | Tested | |
| DNS management | Tested | Implemented | Linux multi-backend untested |
| Kill switch (pf) | Tested | N/A | macOS only |
| Kill switch (nftables) | N/A | Implemented | Needs testing |
| Kill switch (iptables) | N/A | Implemented | Needs testing |
| Notifications | Tested | Implemented | Linux untested |
| Home directory | Tested | Tested | |

---

## 6. Security Model

### 6.1 Kill Switch Design

The kill switch blocks ALL non-VPN traffic at the firewall level, preventing IP leaks if the VPN drops.

**Allowed Traffic:**
- Loopback (lo0/lo)
- VPN tunnel interface (all traffic)
- UDP to VPN server endpoint (tunnel establishment)
- DHCP (UDP ports 67-68)
- LAN subnet (if configured)
- Multicast/Bonjour (macOS only)

**Blocked Traffic:**
- All IPv6 (no exceptions)
- All other IPv4 traffic

**Implementation:**
- macOS: pf anchor with explicit rules
- Linux: nftables table or iptables chain
- PostUp/PostDown hooks in WireGuard config

### 6.2 IPv6 Protection (Dual Layer)

Layer 1 - Interface Level:
- macOS: `networksetup -setv6off`
- Linux: `sysctl net.ipv6.conf.all.disable_ipv6=1`

Layer 2 - Firewall Level:
- macOS: `block quick inet6 all`
- Linux: DROP policy for ip6tables or inet6 in nftables

Both layers active when kill switch enabled.

### 6.3 DNS Leak Prevention

**Primary DNS:** Provider's DNS servers (routed through VPN)
- PIA: 10.0.0.243
- Mullvad: 10.64.0.1
- IVPN: 10.0.254.1

**Fallback DNS:** Quad9 (9.9.9.9) via VPN tunnel

**Implementation:**
- DNS servers set in WireGuard config
- OS-level DNS configured to use VPN DNS
- Kill switch ensures DNS can only reach VPN DNS

### 6.4 Credential Handling

**Password/Token Security:**
- Never saved to disk in plaintext config
- Cleared from memory after authentication
- `mark_sensitive()` registers for cleanup
- Cleanup via `unset` on script exit

**Token Storage:**
- Location: `~/.config/velum/tokens/`
- Permissions: 600 (owner read/write only)
- Directory: 700 (owner only)

**WireGuard Private Key:**
- Persisted to avoid hitting provider key limits
- Location: `~/.config/velum/tokens/wg_private_key`
- Permissions: 600

### 6.5 TLS Requirements

All API calls enforce:
- TLS 1.2 minimum (`--tlsv1.2`)
- CA verification (no `-k` flag)
- PIA uses custom CA certificate

**Security Check:**
- `security_check()` validates no insecure flags present
- Dead-man switch refuses to run if compromised

### 6.6 File Permissions

| Path | Permissions | Owner |
|------|-------------|-------|
| ~/.config/velum/ | 700 | User |
| ~/.config/velum/velum.conf | 600 | User |
| ~/.config/velum/tokens/ | 700 | User |
| ~/.config/velum/tokens/* | 600 | User |
| /etc/wireguard/velum.conf | 600 | Root |

---

## 7. Jurisdiction & Detection

### 7.1 Intelligence Alliance Classification

Servers are classified by their country's intelligence sharing agreements:

**5-Eyes (UKUSA Agreement 1946):**
- US, GB, CA, AU, NZ
- Highest surveillance cooperation

**9-Eyes (5-Eyes + 4):**
- Additional: DK, FR, NL, NO
- Extended intelligence sharing

**14-Eyes (SIGINT Seniors Europe):**
- Additional: DE, BE, IT, SE, ES
- Broad European intelligence network

**Blind (Non-member):**
- All others (CH, IS, RO, PA, etc.)
- Not in known intelligence sharing agreements

### 7.2 Privacy Rating System

Countries rated 1-5 based on privacy law strength:

| Rating | Description | Examples |
|--------|-------------|----------|
| 5 (Strong) | Strong privacy laws | CH, IS, PA |
| 4 (Good) | Good protections | RO, FI, EE, CZ, AT |
| 3 (Moderate) | Moderate protections | DE, NL, NO, DK, FR |
| 2 (Fair) | Fair protections | CA, NZ, AE, MY |
| 1 (Weak) | Weak/mandatory cooperation | US, GB, AU |

### 7.3 VPN Detection Checking

Three independent APIs check if an IP is flagged as VPN/datacenter:

1. **ip-api.com** - Checks `hosting`, `proxy` flags
2. **ipapi.is** - Checks `is_vpn`, `is_proxy`, `is_datacenter`
3. **ipinfo.io** - ASN organization matching against known providers

**Status Classification:**
- **clean** (0 flags): Not detected as VPN
- **partial** (1-2 flags): Some detection
- **flagged** (3+ flags): Confirmed VPN/datacenter

**Caching:**
- Location: `~/.cache/velum/detection-cache.json`
- TTL: 24 hours
- Permissions: 600

### 7.4 Recommendation Scoring

Combines three factors (0-3 points each):

| Factor | 0 pts | 1 pt | 2 pts | 3 pts |
|--------|-------|------|-------|-------|
| Alliance | 5-Eyes | 9-Eyes | 14-Eyes | Blind |
| Privacy | 1-2 | 3 | 4 | 5 |
| Detection | flagged | - | partial | clean |

**Total (0-9) to Recommendation (0-3):**
- 7-9: ★★★ Recommended
- 5-6: ★★☆ Acceptable
- 3-4: ★☆☆ Caution
- 0-2: ☆☆☆ Avoid

---

## 8. Configuration System

### 8.1 Configuration File

**Location:** `~/.config/velum/velum.conf`

**Format:** Bash associative array declarations
```bash
# velum-vpn configuration
CONFIG[provider]="pia"
CONFIG[killswitch]="true"
CONFIG[killswitch_lan]="detect"
# ...
```

### 8.2 Configuration Keys

| Key | Values | Description |
|-----|--------|-------------|
| provider | pia, mullvad, ivpn | Selected VPN provider |
| killswitch | true, false | Enable kill switch |
| killswitch_lan | block, detect, CIDR | LAN traffic policy |
| ipv6_disabled | true, false | Disable IPv6 |
| use_provider_dns | true, false | Use provider's DNS |
| dip_enabled | true, false | Dedicated IP enabled (PIA) |
| dip_token | string | DIP token (PIA) |
| port_forward | true, false | Port forwarding (PIA) |
| allow_geo | true, false | Allow geo servers (PIA) |
| server_auto | true, false | Auto server selection |
| max_latency | number | Max latency threshold (ms) |
| selected_region | string | Server region ID |
| selected_ip | IP address | Server IP |
| selected_hostname | string | Server hostname |

### 8.3 Token Storage

| Provider | Token File | Account File |
|----------|------------|--------------|
| PIA | tokens/pia_token | - |
| Mullvad | tokens/mullvad_token | tokens/mullvad_account |
| IVPN | tokens/ivpn_token | tokens/ivpn_account |
| WireGuard | tokens/wg_private_key | - |

### 8.4 State Files

**Runtime Directory:** `$VELUM_RUN_DIR` (Linux: `/run/velum/`, macOS: `/var/run/velum/`)
**Persistent Directory:** `$VELUM_LIB_DIR` (`/var/lib/velum/`)

Both directories are root-owned (0700) with files at 0600 for security hardening.

| File | Purpose | Lifetime |
|------|---------|----------|
| /etc/wireguard/velum.conf | WireGuard config | Until disconnect |
| $VELUM_RUN_DIR/pf.pid | Port forwarding PID | Until disconnect |
| $VELUM_RUN_DIR/pf.port | Forwarded port number | Until disconnect |
| $VELUM_RUN_DIR/monitor.pid | Monitor daemon PID | Until monitor stop |
| $VELUM_RUN_DIR/monitor.state | Monitor state | Until monitor stop |
| $VELUM_RUN_DIR/monitor.log | Monitor activity log | Until monitor stop |
| $VELUM_RUN_DIR/intentional-disconnect | Disconnect flag | Momentary |
| $VELUM_LIB_DIR/dns_backup | DNS settings backup | Until restore |
| $VELUM_LIB_DIR/resolv.conf.backup | Linux resolv.conf backup | Until restore |

### 8.5 Cache Files

| File | Purpose | TTL |
|------|---------|-----|
| ~/.cache/velum/detection-cache.json | VPN detection results | 24 hours |

---

## 9. Future Direction: Go/Rust Port

### 9.1 Architecture Mapping

The current bash architecture maps cleanly to Go/Rust:

| Bash Component | Go/Rust Equivalent |
|----------------|-------------------|
| bin/* scripts | CLI commands (cobra/clap) |
| lib/velum-core.sh | Core package/crate |
| lib/velum-security.sh | Security package/crate |
| lib/os/*.sh | Platform-specific modules |
| lib/providers/*.sh | Provider trait implementations |
| CONFIG[] array | Typed config struct |

### 9.2 Module Structure

```
velum/
├── cmd/                    # CLI entry points
│   └── velum/
│       ├── main.go
│       └── commands/
│           ├── config.go
│           ├── connect.go
│           └── ...
│
├── internal/
│   ├── config/            # Configuration management
│   ├── security/          # Credential handling, validation
│   ├── providers/         # Provider implementations
│   │   ├── provider.go    # Interface definition
│   │   ├── pia/
│   │   ├── mullvad/
│   │   └── ivpn/
│   ├── platform/          # OS abstraction
│   │   ├── platform.go    # Interface
│   │   ├── darwin/
│   │   └── linux/
│   ├── wireguard/         # WireGuard management
│   └── monitor/           # Health monitoring
│
└── pkg/
    ├── jurisdiction/      # Alliance/privacy data
    └── detection/         # VPN detection APIs
```

### 9.3 Key Considerations

**Type Safety:**
- Credentials as distinct types (not raw strings)
- Config validation at compile time where possible
- Provider interface as trait/interface

**Concurrency:**
- Provider API calls can be concurrent
- Server latency testing parallelized
- Monitor runs as separate goroutine/thread

**Cross-Platform:**
- Build tags for platform-specific code
- Abstract firewall, DNS, IPv6 behind interfaces
- Test on both platforms in CI

**Security:**
- Zeroing sensitive memory (Rust: zeroize crate)
- No credential logging
- TLS configuration hardening

### 9.4 Migration Path

1. **Phase 1:** Core library (config, security, types)
2. **Phase 2:** Provider abstraction + PIA implementation
3. **Phase 3:** OS abstraction (macOS first)
4. **Phase 4:** CLI commands (config, connect, disconnect)
5. **Phase 5:** Remaining commands + Linux support
6. **Phase 6:** Monitor daemon, full feature parity
7. **Phase 7:** Testing, documentation, release

---

## 10. Appendices

### 10.1 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-05 | Comprehensive v1.0 specification |
| 0.2-draft | 2026-01-01 | Original velum_config spec (superseded) |
| 0.1-draft | 2026-01-01 | Original architecture spec (superseded) |

### 10.2 Changelog from Original Specs

**New in v1.0:**
- IVPN provider (not in original spec)
- velum-monitor command (background health monitoring)
- velum-killswitch command (standalone kill switch management)
- velum-webrtc command (WebRTC leak testing)
- Jurisdiction classification system
- VPN detection checking with caching
- Server recommendation scoring
- WireGuard key persistence
- Comprehensive 17-test validation suite

**Removed:**
- OpenVPN references (WireGuard only)
- Phase-based implementation plan (completed)
- Legacy PIA script references

### 10.3 External References

**Provider Documentation:**
- PIA: https://www.privateinternetaccess.com/
- Mullvad: https://mullvad.net/en/help/
- IVPN: https://www.ivpn.net/knowledgebase/

**WireGuard:**
- Protocol: https://www.wireguard.com/
- Tools: https://git.zx2c4.com/wireguard-tools/

**Intelligence Alliances:**
- Five Eyes: https://en.wikipedia.org/wiki/Five_Eyes
- Fourteen Eyes: https://en.wikipedia.org/wiki/UKUSA_Agreement

---

*End of Specification*
