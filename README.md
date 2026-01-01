# velum-vpn

A hardened fork of [PIA manual-connections](https://github.com/pia-foss/manual-connections) with improved reliability, security, and usability.

## Supported Platforms

- **macOS** (tested)
- **Linux/Debian** (in progress)

## What's Different

This fork addresses several issues with the upstream scripts:

| Issue | Fix |
|-------|-----|
| DNS leak on 10.0.0.x networks | Explicit route through VPN tunnel |
| Server mismatch (displayed ≠ connected) | Server list caching |
| Geolocated servers (privacy concern) | Optional geo server filter |
| Credentials in command history | Credential file support |
| No connection validation | `pia-test` validator |

## Quick Start

```bash
git clone git@github.com:blackforestdev/velum-vpn.git
cd velum-vpn
sudo ./run_setup.sh
```

## Tools

### `pia-test` - Connection Validator

Verifies VPN connection security:

```bash
sudo ./pia-test
```

Tests performed:
- WireGuard interface status and handshake
- Public IP verification (checks against known PIA providers)
- DNS leak detection
- Route table validation
- Traffic connectivity
- Potential leak sources (IPv6, remote access tools)

## Configuration

### Credential File

Store credentials securely (avoids shell history exposure):

```bash
echo "p1234567" > ~/.pia_credentials
echo "your_password" >> ~/.pia_credentials
chmod 600 ~/.pia_credentials
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PIA_USER` | PIA username | - |
| `PIA_PASS` | PIA password | - |
| `VPN_PROTOCOL` | `wireguard` or `openvpn*` | prompted |
| `PIA_PF` | Enable port forwarding | `true` |
| `PIA_DNS` | Use PIA DNS servers | `true` |
| `PREFERRED_REGION` | Region ID (e.g., `panama`) | auto-select |
| `ALLOW_GEO_SERVERS` | Include geolocated servers | `true` |
| `MAX_LATENCY` | Server response timeout (seconds) | `0.05` |
| `DISABLE_IPV6` | Disable IPv6 | `yes` |

### One-liner Connection

```bash
sudo PIA_USER=p1234567 PIA_PASS=xxx VPN_PROTOCOL=wireguard PIA_PF=true ./run_setup.sh
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
| `pia-test` | Connection security validator |
| `get_region.sh` | Server selection and latency testing |
| `get_token.sh` | Authentication token retrieval |
| `connect_to_wireguard_with_token.sh` | WireGuard connection |
| `connect_to_openvpn_with_token.sh` | OpenVPN connection |
| `port_forwarding.sh` | Port forwarding management |

## Security Considerations

This fork improves security over upstream but is not bulletproof. Known limitations:

- Tokens visible in process list during connection
- Credentials in environment variables during session
- No certificate pinning for auth endpoint

For maximum security, use the official PIA application.

## Upstream

Based on [pia-foss/manual-connections](https://github.com/pia-foss/manual-connections).

## License

[MIT License](LICENSE)
