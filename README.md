# velum-vpn

A security-focused, provider-agnostic VPN management suite for WireGuard.

velum-vpn provides a unified command-line interface for connecting to multiple VPN providers with defense-in-depth security features including kill switch protection, IPv6 leak prevention, and DNS leak protection.

## Features

- **Provider Agnostic**: Support for multiple VPN providers (PIA, Mullvad, IVPN) with a pluggable architecture
- **WireGuard Only**: Modern, fast, and secure - no legacy OpenVPN support
- **Kill Switch**: Firewall-based protection that blocks all traffic if VPN drops
- **IPv6 Protection**: Blocks IPv6 at both interface and firewall level to prevent leaks
- **DNS Leak Protection**: Routes DNS through VPN provider's servers with encrypted fallback
- **DNS Fallback**: Quad9 (9.9.9.9) as secondary DNS, routed through VPN tunnel
- **WebRTC Leak Detection**: Automated risk assessment and browser-based testing
- **VPN Detection Check**: Tests if your IP is flagged by detection services
- **Encrypted Credential Vault**: Optional encrypted storage for account credentials using Argon2id + AES-256
- **Cross-Platform**: Full support for macOS and Linux
- **XDG Compliant**: Configuration stored in `~/.config/velum/` following Linux standards
- **Security Hardened**: TLS 1.2+ enforcement, credential cleanup, input validation

## Supported Providers

| Provider | Authentication | Port Forwarding | Dedicated IP |
|----------|---------------|-----------------|--------------|
| **PIA** (Private Internet Access) | Username + Password | Yes | Yes |
| **Mullvad** | 16-digit Account Number | No (removed 2023) | No |
| **IVPN** | Account ID (i-XXXX-XXXX-XXXX) | No (removed) | No |

## Requirements

### All Platforms
- `curl` - HTTP client
- `jq` - JSON processor
- `wireguard-tools` - WireGuard userspace tools (`wg`, `wg-quick`)

### macOS
- `wireguard-go` - WireGuard userspace implementation
- Install via: `brew install wireguard-tools wireguard-go jq`

### Linux
- `iptables` or `nftables` - Firewall (for kill switch)
- `iproute2` - Network utilities (`ip` command)
- Kernel WireGuard module or `wireguard-go`

### Optional (for Credential Vault)
- `argon2` - Argon2 password hashing (for encrypted vault)
  - Debian/Ubuntu: `sudo apt install argon2`
  - macOS: `brew install argon2`
- `xxd` - Hex encoding (usually pre-installed, part of `vim-common`)

## Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/velum-vpn.git
cd velum-vpn

# Add to PATH (optional)
export PATH="$PATH:$(pwd)/bin"

# Or create symlink
sudo ln -s $(pwd)/bin/velum /usr/local/bin/velum
```

## Quick Start

```bash
# 1. Configure VPN (interactive wizard)
velum config

# 2. Connect to VPN (requires root)
sudo velum connect

# 3. Verify connection
sudo velum test

# 4. Check status
sudo velum status

# 5. Disconnect
sudo velum disconnect
```

## Commands

### `velum`

Main entry point. Dispatches to subcommands.

```bash
velum <command> [options]

Commands:
  config      Configure VPN settings interactively
  connect     Connect to VPN
  disconnect  Disconnect from VPN
  status      Show connection status
  test        Test VPN connection for leaks
  killswitch  Manage kill switch
  webrtc      Open browser for WebRTC leak test
  monitor     Background VPN health monitoring
  credential  Manage encrypted credential vault

Options:
  -h, --help     Show help
  -v, --version  Show version
```

### `velum config`

Interactive configuration wizard with 5 phases:

1. **Provider Selection**: Choose VPN provider (PIA, Mullvad, IVPN)
2. **Authentication**: Enter credentials and authenticate
3. **Security Profile**: Configure kill switch, IPv6, DNS settings
4. **Connection Features**: Port forwarding, Dedicated IP (provider-dependent)
5. **Server Selection**: Auto (lowest latency) or manual selection

Configuration is saved to `~/.config/velum/velum.conf`.

```bash
# Run configuration wizard
velum config

# Validate existing configuration
velum config lint
```

**Subcommands:**
- `velum config` - Interactive configuration wizard
- `velum config lint` - Validate config file (checks for errors, unknown keys, invalid values)

**Exit codes for lint:**
- `0` - Configuration is valid
- `1` - Errors found (invalid values, malformed lines)
- `2` - Warnings only (unknown keys)

### `velum connect`

Establishes VPN connection using saved configuration.

```bash
# Connect to VPN
sudo velum connect
```

**What it does:**
1. Loads configuration from `~/.config/velum/velum.conf`
2. Finds best server by latency (if auto mode)
3. Generates WireGuard keypair
4. Exchanges keys with provider API
5. Creates WireGuard configuration
6. Enables kill switch (if configured)
7. Starts WireGuard interface
8. Sets up port forwarding (if enabled)

### `velum disconnect`

Cleanly disconnects VPN and removes firewall rules.

```bash
# Disconnect from VPN
sudo velum disconnect
```

**What it does:**
1. Stops WireGuard interface
2. Disables kill switch
3. Stops port forwarding keepalive
4. Optionally re-enables IPv6

### `velum status`

Shows current VPN connection status.

```bash
# Check connection status (sudo recommended for full details)
sudo velum status
```

**Output includes:**
- Connection state (connected/disconnected)
- VPN interface and public IP
- Kill switch status
- IPv6 status
- DNS configuration
- Port forwarding status (requires sudo)
- Authentication token validity

**Note:** Some status details (port forwarding) require sudo due to hardened runtime permissions.

### `velum test`

Comprehensive VPN connection validator. Tests for leaks and issues.

```bash
# Run connection tests (requires root for some tests)
sudo velum test
```

**Test categories:**
1. **WireGuard Interface**: Handshake, transfer stats, allowed IPs
2. **Public IP Check**: Verifies IP is from VPN provider
3. **DNS Leak Test**: Tests primary DNS and Quad9 fallback routing
4. **Route Table Check**: Verifies traffic routes through VPN
5. **Traffic Test**: Ping, HTTPS, MTU tests
6. **Kill Switch**: Verifies firewall rules are active
7. **Leak Sources**: IPv6, remote access tools, WebRTC risk assessment
8. **Port Forwarding**: Status if enabled
9. **VPN Detection Check**: Tests if IP is flagged by detection services
10. **Reconnection Info**: Config age, quick reconnect command

### `velum killswitch`

Manage kill switch independently.

```bash
# Enable kill switch
sudo velum killswitch enable --vpn-ip <IP> --vpn-port <PORT> --vpn-iface <IFACE>

# Disable kill switch
sudo velum killswitch disable

# Check status
sudo velum killswitch status
```

### `velum webrtc`

Open browser for WebRTC leak testing. Detects default browser cross-platform.

```bash
# Open browser to WebRTC leak test page
velum webrtc
```

**Features:**
- Cross-platform browser detection (Firefox, Brave, Chrome, Safari, GNOME Web, KDE browsers)
- Displays current VPN IP for easy verification
- Provides guidance on what to check and how to disable WebRTC if needed

**Note:** The `velum test` command includes automated WebRTC risk assessment that checks for non-VPN public IPs and mDNS status without requiring a browser.

### `velum monitor`

Background daemon that monitors VPN health and sends alerts.

```bash
# Start background monitoring
sudo velum monitor start

# Check monitor status (requires sudo - runtime files are root-only)
sudo velum monitor status

# Stop monitoring
sudo velum monitor stop
```

**Features:**
- Automatically starts with `velum connect`, stops with `velum disconnect`
- Monitors VPN interface status, kill switch rules, handshake freshness
- Alerts on VPN disconnect, kill switch disabled, stale connection
- Audio alerts (macOS `say` command) for critical events
- Desktop notifications (requires Terminal notification permissions on macOS)
- Logs: `/run/velum/monitor.log` (Linux), `/var/run/velum/monitor.log` (macOS)

**Note:** Runtime files are root-owned (0600) for security. Status commands require sudo.

**Alerts sent for:**
- VPN disconnected (critical - audio alert)
- VPN reconnected
- Kill switch unexpectedly disabled (critical - audio alert)
- Connection stale (no handshake for 3+ minutes)

### `velum credential`

Optional encrypted vault for storing account credentials at rest. This is an **opt-in** feature - by default, velum prompts for credentials each time and never stores them.

```bash
# Initialize vault (first-time setup)
velum credential init

# Store a credential
velum credential store mullvad

# Show vault status
velum credential status

# Remove a credential
velum credential clear mullvad

# Remove all credentials
velum credential clear

# Check for and clean up plaintext credentials
velum credential migrate
```

**Security:**
- Credentials encrypted with AES-256-CBC + HMAC-SHA256 (encrypt-then-MAC)
- Key derived from vault password using Argon2id (64 MiB memory, 3 iterations)
- Vault password required for **every** operation (never cached)
- Salt stored separately in `~/.config/velum/vault/salt`

**Workflow:**
1. Run `velum credential init` to create the vault (one-time)
2. Run `velum credential store <provider>` to store an account credential
3. During `velum config` or `velum connect`, you'll be prompted to use vault credentials

**Provider-specific validation:**
- Mullvad: 16-digit account number
- IVPN: Account ID format (i-XXXX-XXXX-XXXX or ivpn-XXXX-XXXX-XXXX)
- PIA: Username format (pXXXXXXX)

## Configuration

### Configuration File

Location: `~/.config/velum/velum.conf`

```bash
# velum-vpn configuration

# Provider
CONFIG[provider]="pia"

# Security
CONFIG[killswitch]="true"
CONFIG[killswitch_lan]="detect"
CONFIG[ipv6_disabled]="true"
CONFIG[use_provider_dns]="true"

# Features
CONFIG[dip_enabled]="false"
CONFIG[dip_token]=""
CONFIG[port_forward]="false"

# Server
CONFIG[allow_geo]="false"
CONFIG[max_latency]="0.05"
CONFIG[selected_region]=""
CONFIG[selected_ip]=""
CONFIG[selected_hostname]=""
```

### Token Storage

**Session tokens** are stored in tmpfs (RAM-backed filesystem) for security:
- Location: `/run/user/$UID/velum/` (Linux with systemd)
- Tokens are automatically cleared on system reboot
- No persistent credential storage by default

**Requirements:**
- `XDG_RUNTIME_DIR` must be available (standard on systemd-based Linux)
- If unavailable, token storage will fail (fail-closed for security)

**Note:** Account credentials (Mullvad account number, IVPN account ID) are **never** stored on disk. You will be prompted for your account credential when:
- Authenticating during `velum config`
- Connecting with `velum connect` (Mullvad only, for WireGuard key registration)

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `XDG_CONFIG_HOME` | Base config directory | `~/.config` |
| `XDG_RUNTIME_DIR` | Tmpfs directory for session tokens | `/run/user/$UID` (systemd) |
| `VELUM_LOG_LEVEL` | Log verbosity (0=DEBUG, 1=INFO, 2=WARN, 3=ERROR) | `1` (INFO) |
| `VELUM_RUN_DIR` | Runtime directory (pid, state, logs) | `/run/velum` (Linux), `/var/run/velum` (macOS) |
| `VELUM_LIB_DIR` | Persistent state (DNS backups) | `/var/lib/velum` |

**Note:** `XDG_RUNTIME_DIR` is required for session token storage. If not available, velum will fail-closed (refuse to store tokens) rather than fall back to disk storage.

## Security Features

### Kill Switch

The kill switch uses the native firewall (pf on macOS, iptables/nftables on Linux) to block all traffic except:
- Traffic through the VPN tunnel
- Traffic to the VPN server endpoint
- Local loopback traffic
- Optionally: LAN traffic (configurable)

If the VPN connection drops, all internet traffic is blocked until the VPN reconnects or the kill switch is disabled.

### IPv6 Protection

IPv6 is disabled at two levels:
1. **Interface level**: IPv6 is disabled on network interfaces
2. **Firewall level**: All IPv6 traffic is blocked by kill switch rules

This prevents IPv6 leaks that could expose your real IP address.

### DNS Leak Protection

When enabled, DNS queries are routed through the VPN provider's DNS servers:
- PIA: `10.0.0.243` (primary)
- Mullvad: `10.64.0.1` (primary)
- IVPN: `10.0.254.1` (primary)
- Quad9: `9.9.9.9` (fallback, all providers)

**Encrypted Fallback**: Quad9 is configured as a secondary DNS and routed through the VPN tunnel. If the primary VPN DNS fails, queries fall back to Quad9 while remaining encrypted within the tunnel.

The WireGuard configuration includes DNS settings, and on macOS routes are added to ensure both primary and fallback DNS traffic goes through the tunnel.

### Credential Security

velum-vpn follows a **security-first** architecture designed for device capture scenarios:

**No Plaintext Credential Storage:**
- Account IDs (Mullvad, IVPN) are never stored on disk by default
- Session tokens stored in tmpfs only (cleared on reboot)
- Legacy plaintext files are detected and securely deleted on first run

**Optional Encrypted Vault:**
- Opt-in encrypted storage for account credentials
- AES-256-CBC with HMAC-SHA256 authenticated encryption
- Argon2id key derivation (memory-hard, side-channel resistant)
- Vault password required for every operation - never cached
- Run `velum credential migrate` to detect and clean up any legacy plaintext credentials

**Memory Protection:**
- Credentials cleared from memory immediately after use (`unset`)
- Sensitive variables marked for cleanup on script exit

**File Security:**
- Token files validated for permissions (600) and ownership before reading
- Config directories use mode 700
- Files with insecure permissions are rejected

**Network Security:**
- TLS 1.2+ enforced for all API calls
- Provider CA certificates pinned where available

**Defensive Measures:**
- "Dead-man switch" checks scripts for insecure patterns before execution
- Input validation on all user-provided values (SUDO_USER, IPs, ports)
- Fail-closed behavior when security requirements aren't met

## Architecture

```
velum-vpn/
├── bin/                          # Executable scripts
│   ├── velum                     # Main CLI entry point
│   ├── velum-config              # Configuration wizard
│   ├── velum-connect             # VPN connection
│   ├── velum-credential          # Encrypted vault management
│   ├── velum-disconnect          # VPN disconnection
│   ├── velum-killswitch          # Kill switch management
│   ├── velum-monitor             # Background health monitor
│   ├── velum-status              # Connection status
│   ├── velum-test                # Connection validator
│   └── velum-webrtc              # WebRTC leak test (browser)
│
├── lib/                          # Libraries
│   ├── velum-core.sh             # Core utilities, colors, logging
│   ├── velum-security.sh         # Security utilities, validation
│   ├── velum-credential.sh       # Credential/token management (tmpfs)
│   ├── velum-vault.sh            # Encrypted vault (Argon2id + AES-256)
│   ├── velum-jurisdiction.sh     # Privacy jurisdiction lookups
│   ├── velum-detection.sh        # VPN detection checks
│   ├── os/                       # OS abstraction layer
│   │   ├── detect.sh             # OS detection and loader
│   │   ├── macos.sh              # macOS implementation
│   │   └── linux.sh              # Linux implementation
│   └── providers/                # VPN provider plugins
│       ├── provider-base.sh      # Provider interface
│       ├── pia.sh                # PIA implementation
│       ├── mullvad.sh            # Mullvad implementation
│       └── ivpn.sh               # IVPN implementation
│
├── etc/                          # Static configuration
│   └── providers/
│       └── pia/
│           └── ca.rsa.4096.crt   # PIA CA certificate
│
└── docs/                         # Documentation
    └── spec/                     # Architecture specifications
```

### Provider Interface

Each provider implements the following functions:

```bash
# Metadata
provider_name()              # Provider display name
provider_version()           # Provider module version
provider_auth_type()         # "username_password" or "account_number"

# Authentication
provider_validate_creds()    # Validate credential format
provider_authenticate()      # Authenticate and get token

# Servers
provider_get_servers()       # Fetch server list
provider_filter_servers()    # Filter by criteria
provider_test_latency()      # Test server latency

# WireGuard
provider_wg_exchange()       # Exchange WireGuard keys

# Features
provider_supports_pf()       # Port forwarding support
provider_enable_pf()         # Enable port forwarding
provider_refresh_pf()        # Refresh port forwarding
provider_supports_dip()      # Dedicated IP support
provider_get_dip()           # Get DIP info

# Provider-specific
provider_get_dns()           # Get DNS servers
provider_get_ca_cert()       # Get CA certificate path
```

### OS Abstraction Layer

Each OS module implements:

```bash
# Network
os_get_local_ip()            # Get local IP address
os_get_gateway()             # Get default gateway
os_get_primary_interface()   # Get primary network interface
os_get_dns()                 # Get current DNS servers
os_detect_subnet()           # Detect local subnet
os_detect_vpn_interface()    # Find WireGuard interface

# IPv6
os_ipv6_enabled()            # Check if IPv6 is enabled
os_disable_ipv6()            # Disable IPv6 on interfaces
os_enable_ipv6()             # Re-enable IPv6

# DNS
os_set_dns()                 # Set DNS servers
os_restore_dns()             # Restore original DNS

# Kill Switch
os_killswitch_enable()       # Enable firewall rules
os_killswitch_disable()      # Disable firewall rules
os_killswitch_status()       # Get kill switch status
os_killswitch_rule_count()   # Count firewall rules
```

## Adding a New Provider

1. Create `lib/providers/yourprovider.sh`
2. Implement the provider interface functions
3. The provider will be auto-discovered by `list_providers`

See `lib/providers/pia.sh`, `lib/providers/mullvad.sh`, or `lib/providers/ivpn.sh` for examples.

## Troubleshooting

### Connection Issues

```bash
# Check WireGuard status
sudo wg show

# Check routes
netstat -rn | grep -E "^0|utun"

# Check DNS
scutil --dns | grep nameserver  # macOS
cat /etc/resolv.conf            # Linux

# Run comprehensive test
sudo velum test
```

### Kill Switch Issues

```bash
# Check kill switch status
velum killswitch status

# View firewall rules (macOS)
sudo pfctl -a velum_killswitch -s rules

# View firewall rules (Linux - iptables)
sudo iptables -L VELUM_KILLSWITCH -v

# View firewall rules (Linux - nftables)
sudo nft list table inet velum_killswitch

# Manually disable if stuck
sudo velum killswitch disable
```

### Token Expired or Missing

Session tokens are stored in tmpfs and cleared on reboot. After a reboot:

```bash
# Re-authenticate (you'll need your account credentials)
velum config
# Follow prompts, existing config will be preserved
```

For Mullvad, you'll also be prompted for your account number during `velum connect` (required for WireGuard key registration).

### Session Token Storage Failed

If you see "Cannot create runtime directory" or similar errors:

```bash
# Check if XDG_RUNTIME_DIR is available
echo $XDG_RUNTIME_DIR
ls -la /run/user/$(id -u)

# On non-systemd systems, you may need to create the directory manually
# or use a systemd-based distribution
```

velum-vpn requires `XDG_RUNTIME_DIR` (tmpfs) for secure token storage. This is standard on systemd-based Linux distributions but may not be available on:
- Non-systemd init systems (OpenRC, runit)
- Minimal containers
- Some BSD systems

### Credential Vault Issues

```bash
# Check vault status
velum credential status

# If vault initialization fails, check argon2 is installed
which argon2

# Install argon2 if missing
sudo apt install argon2      # Debian/Ubuntu
brew install argon2          # macOS

# Migrate plaintext credentials (if you have any legacy files)
velum credential migrate
```

**Wrong vault password?**
The vault password is verified during decryption. If you've forgotten it, you'll need to clear the vault and re-store your credentials:
```bash
velum credential clear       # Removes all encrypted credentials
velum credential init        # Re-initialize with new password
velum credential store mullvad
```

### Permission Denied

Most operations require root:
```bash
sudo velum connect
sudo velum disconnect
sudo velum test
```

## License

Copyright (c) 2025. All rights reserved.

This software is proprietary and confidential. Unauthorized copying, modification,
distribution, or use of this software, via any medium, is strictly prohibited.

See [LICENSE](LICENSE) for full terms.

## Version

velum-vpn v0.1.0-dev
