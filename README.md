# velum-vpn

A hardened fork of [PIA manual-connections](https://github.com/pia-foss/manual-connections) with improved reliability, security, and usability.

## Supported Platforms

- **macOS** (fully tested)
- **Linux/Debian** (in progress)

## What's Different

This fork addresses several issues with the upstream scripts:

| Issue | Fix |
|-------|-----|
| No kill switch | pf firewall blocks traffic if VPN drops |
| DNS leak on 10.0.0.x networks | Explicit route through VPN tunnel |
| Token exposed in console output | Tokens redacted from all output |
| Credentials in world-readable files | Restrictive permissions (700/600) |
| Server mismatch (displayed ≠ connected) | Server list caching |
| Geolocated servers (privacy concern) | Optional geo server filter |
| Credentials in command history | Credential file support |
| No connection validation | `pia-test` validator (16 security checks) |
| Potential command injection (eval) | Safe home directory lookup |
| No curl certificate enforcement | Dead-man switch for insecure flags |

## Quick Start

```bash
git clone git@github.com:blackforestdev/velum-vpn.git
cd velum-vpn
sudo ./run_setup.sh
```

## Tools

### `pia-test` - Connection Validator

Comprehensive VPN security verification:

```bash
sudo ./pia-test
```

**Tests performed (16 checks):**

| Test | Description |
|------|-------------|
| WireGuard Interface | Interface status, handshake, AllowedIPs |
| Handshake Freshness | Warns if handshake is stale |
| Public IP Check | Verifies IP belongs to known VPN provider |
| DNS Leak Test | Tests nslookup, dig, host through PIA DNS |
| DNS Route | Verifies DNS routed through VPN tunnel |
| Route Table | Confirms 0.0.0.0/1 and 128.0.0.0/1 via VPN |
| Traffic Test | Ping and HTTPS connectivity |
| MTU Test | Large packet (1400 byte) verification |
| Kill Switch | Verifies pf firewall rules active |
| IPv6 Leak | Checks all interfaces for IPv6 |
| Remote Access | Detects potential leak processes |
| WebRTC | Reminder for browser-level check |
| Port Forwarding | Status of port forwarding process |
| Reconnection | Shows available reconnection method |

### `pia-killswitch.sh` - Kill Switch Manager

Standalone kill switch control:

```bash
sudo ./pia-killswitch.sh status   # Check status
sudo ./pia-killswitch.sh enable --vpn-ip <IP> --lan-policy detect
sudo ./pia-killswitch.sh disable
```

## Configuration

### Credential File

Create credentials file (two lines: username, then password):

**Option 1 - Text editor (most secure):**
```bash
nano ~/.pia_credentials
# Enter username on line 1, password on line 2, save and exit
chmod 600 ~/.pia_credentials
```

**Option 2 - Secure prompt (password hidden):**
```bash
read -p "Username: " user && read -sp "Password: " pass && printf "%s\n%s\n" "$user" "$pass" > ~/.pia_credentials && chmod 600 ~/.pia_credentials && unset user pass
```

**Warning:** Avoid using `echo` with passwords - they appear in shell history.

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PIA_USER` | PIA username | - |
| `PIA_PASS` | PIA password | - |
| `VPN_PROTOCOL` | `wireguard` or `openvpn*` | prompted |
| `PIA_PF` | Enable port forwarding | `true` |
| `PIA_DNS` | Use PIA DNS servers | `true` |
| `PIA_KILLSWITCH` | Enable kill switch | prompted |
| `PIA_KILLSWITCH_LAN` | LAN policy: `block`, `detect`, or CIDR | `detect` |
| `PREFERRED_REGION` | Region ID (e.g., `panama`) | auto-select |
| `ALLOW_GEO_SERVERS` | Include geolocated servers | `true` |
| `MAX_LATENCY` | Server response timeout (seconds) | `0.05` |
| `DISABLE_IPV6` | Disable IPv6 | `yes` |

### One-liner Connection

```bash
sudo PIA_USER=p1234567 PIA_PASS=xxx VPN_PROTOCOL=wireguard PIA_KILLSWITCH=true ./run_setup.sh
```

## Kill Switch

The kill switch blocks ALL internet traffic if the VPN connection drops, preventing your real IP from being exposed. This is critical for privacy-sensitive use cases.

### How It Works

- Uses macOS pf (packet filter) firewall
- Blocks all traffic except through the VPN tunnel
- Auto-detects your local subnet for LAN access
- Sends macOS notification if VPN drops unexpectedly
- Automatically enabled/disabled via WireGuard PostUp/PostDown

### LAN Policies

| Policy | Description | Use Case |
|--------|-------------|----------|
| `block` | Block all LAN traffic | Public WiFi, maximum security |
| `detect` | Auto-detect and allow local subnet | Home/office with printers, NAS |
| `10.0.1.0/24` | Allow specific CIDR | Custom network configuration |

### Manual Control

```bash
# Check kill switch status
sudo ./pia-killswitch.sh status

# Manually enable (if not using run_setup.sh)
sudo ./pia-killswitch.sh enable --vpn-ip 158.173.21.201 --lan-policy detect

# Manually disable
sudo ./pia-killswitch.sh disable
```

### Verify Kill Switch

Run `pia-test` to verify the kill switch is active:

```
[6] Kill Switch
    pf status:  Enabled
    Kill switch: PASS - Active (1 block, 8 pass rules)
    LAN allowed: 10.0.0.0/24
```

## Dependencies

### macOS

```bash
brew install wireguard-tools curl jq
```

### Debian/Ubuntu

```bash
sudo apt install wireguard-tools curl jq
```

## Platform Notes

### IPv6

Disable IPv6 to prevent leaks:

**macOS:**
```bash
networksetup -setv6off "Wi-Fi"
networksetup -setv6off "Ethernet"
```

**Linux:**
```bash
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
```

### DNS Routing

If your local network uses 10.0.0.0/24, PIA's DNS (10.0.0.243) may route locally instead of through the VPN. This fork automatically adds an explicit route through the tunnel.

**Note:** PIA's use of 10.0.0.x for internal DNS is problematic for users with home networks in this range. We've implemented workarounds, but recommend PIA implement signed server lists with non-conflicting DNS IPs.

### Connect / Disconnect

After initial setup, the WireGuard config is saved to `/etc/wireguard/pia.conf`. You can reconnect without re-running setup:

```bash
# Connect
sudo wg-quick up pia

# Disconnect
sudo wg-quick down pia
pkill -f port_forwarding.sh
```

**Note:** Port forwarding requires re-running `./run_setup.sh` or manually starting `./port_forwarding.sh`.

## Geolocated Servers

Some PIA servers are "geolocated" - physically located in a different country than advertised. This may have privacy or legal implications.

To exclude geolocated servers:

```bash
ALLOW_GEO_SERVERS=false sudo ./run_setup.sh
```

The setup script will also prompt you.

## Port Forwarding

Port forwarding is enabled by default (`PIA_PF=true`). The forwarded port is displayed after connection and refreshed automatically every 15 minutes.

**Note:** Port forwarding is disabled on US servers.

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `run_setup.sh` | Interactive setup (prompts for options) |
| `pia-test` | Connection security validator (16 checks) |
| `pia-killswitch.sh` | Kill switch management (enable/disable/status) |
| `get_region.sh` | Server selection and latency testing |
| `get_token.sh` | Authentication token retrieval |
| `connect_to_wireguard_with_token.sh` | WireGuard connection |
| `connect_to_openvpn_with_token.sh` | OpenVPN connection |
| `port_forwarding.sh` | Port forwarding management |

## Security Considerations

### What This Fork Fixes

- **Token exposure**: Tokens no longer printed to console
- **File permissions**: All sensitive files use 600/700 permissions
- **Command injection**: Replaced `eval` with safe alternatives
- **Curl security**: Dead-man switch refuses to run if `-k`/`--insecure` flags detected
- **Server list validation**: Basic sanity checks on API responses

### Remaining Limitations

- Credentials in environment variables during session (standard for shell scripts)
- No certificate pinning for auth endpoint (would require PIA to publish pinned certs)
- Server list not cryptographically signed (recommendation sent to PIA)

### For Maximum Security

For the highest security requirements, consider:
- Using the official PIA application
- Running in a dedicated VM or container
- Enabling the kill switch with `block` LAN policy
- Verifying WebRTC leaks in your browser at browserleaks.com/webrtc

## Upstream

Based on [pia-foss/manual-connections](https://github.com/pia-foss/manual-connections).

## License

[MIT License](LICENSE)
