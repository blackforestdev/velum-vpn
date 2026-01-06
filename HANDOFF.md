# Velum VPN Development Handoff

**Date:** 2026-01-05
**Target Platform:** Linux (Debian/Ubuntu)
**Previous Platform:** macOS (fully working)

---

## Project Overview

Velum is a provider-agnostic VPN management suite for macOS/Linux supporting PIA, Mullvad, and IVPN via WireGuard. The macOS implementation is now complete and tested. This handoff focuses on Linux testing and hardening.

## Documentation

**Specification:** `docs/spec/velum-v1.0-spec.md` - Comprehensive v1.0 specification covering all commands, providers, OS abstraction, and security model. Reference this for implementation details.

---

## macOS Status: COMPLETE

All features working on macOS:
- Configuration wizard with jurisdiction/detection info
- VPN connection with kill switch (pf), IPv6 blocking, DNS
- Background health monitoring with speech notifications
- Comprehensive 17-test validation suite
- All three providers: PIA, Mullvad, IVPN

---

## Linux Status: NEEDS TESTING

The Linux implementation exists in `lib/os/linux.sh` but has NOT been thoroughly tested.

### Implementation Status

| Feature | Implemented | Tested | Notes |
|---------|-------------|--------|-------|
| OS detection | Yes | No | `detect_os()`, `detect_distro()` |
| Network detection | Yes | No | Gateway, interface, subnet via `ip` command |
| IPv6 management | Yes | No | sysctl-based disable/enable |
| DNS management | Yes | No | systemd-resolved, resolvconf, direct |
| Kill switch (nftables) | Yes | No | Preferred on modern distros |
| Kill switch (iptables) | Yes | No | Fallback for older systems |
| Notifications | Yes | No | notify-send via DBus |
| Speech synthesis | Yes | No | spd-say or espeak |

### Linux-Specific Code Locations

| File | Functions to Test |
|------|-------------------|
| `lib/os/linux.sh` | All `os_*` functions |
| `lib/os/detect.sh` | `detect_os()`, `detect_distro()`, `detect_package_manager()` |
| `bin/velum-monitor` | Linux notification path (notify-send, spd-say/espeak) |

---

## Priority Testing on Linux

### 1. Basic Functionality
```bash
# Check OS detection
source lib/os/detect.sh
echo "OS: $VELUM_OS"
echo "Distro: $(detect_distro)"

# Check dependencies
which wg wg-quick curl jq
```

### 2. Kill Switch Testing
```bash
# Test nftables (preferred)
sudo nft list tables

# Test iptables (fallback)
sudo iptables -L

# Test kill switch enable/disable
sudo ./bin/velum-killswitch enable --vpn-ip 1.2.3.4 --lan-policy detect
sudo ./bin/velum-killswitch status
sudo ./bin/velum-killswitch disable
```

### 3. DNS Management
```bash
# Check which DNS backend is in use
systemctl status systemd-resolved  # systemd-resolved
which resolvconf                    # resolvconf
cat /etc/resolv.conf               # direct

# Test DNS functions
# These are called by velum-connect
```

### 4. Full Connection Test
```bash
# Configure (interactive)
sudo ./bin/velum-config

# Connect
sudo ./bin/velum-connect

# Verify
sudo ./bin/velum-status
sudo ./bin/velum-test

# Monitor (in another terminal)
sudo ./bin/velum-monitor start
./bin/velum-monitor status

# Disconnect
sudo ./bin/velum-disconnect
```

### 5. Notification Testing
```bash
# Test notify-send directly
notify-send "Test" "Testing velum notifications"

# Test speech (if available)
spd-say "Test speech"
# or
espeak "Test speech"

# Test via monitor
sudo ./bin/velum-monitor start
# Then disconnect VPN to trigger notification
```

---

## Known Linux Considerations

### DNS Backend Detection

Linux has multiple DNS management systems. The code auto-detects:

1. **systemd-resolved** (Ubuntu 18.04+, Fedora)
   - Uses `resolvectl` or `systemd-resolve`
   - Per-interface DNS configuration

2. **resolvconf** (Older Debian/Ubuntu)
   - Uses `/etc/resolvconf/`
   - Interface stanza management

3. **Direct /etc/resolv.conf** (Fallback)
   - Writes directly to `/etc/resolv.conf`
   - Uses `chattr +i` to prevent overwriting

### Firewall Backend Detection

Kill switch auto-detects:

1. **nftables** (Preferred, modern)
   - Table: `velum_killswitch`
   - Check: `nft list tables`

2. **iptables** (Fallback, legacy)
   - Chain: `VELUM_KILLSWITCH`
   - Check: `iptables -L`

### IPv6 Handling

- Disabled via sysctl: `net.ipv6.conf.all.disable_ipv6=1`
- Also per-interface in `/proc/sys/net/ipv6/conf/*/disable_ipv6`

---

## Potential Issues to Watch

1. **WireGuard not installed** - Package names vary by distro
   - Debian/Ubuntu: `wireguard wireguard-tools`
   - Fedora: `wireguard-tools`

2. **DBus not available** - Headless servers won't have notify-send
   - Speech fallback may also fail
   - Should fail gracefully (already has `|| true`)

3. **nftables vs iptables conflict** - Some systems have both
   - Code prefers nftables if available

4. **systemd-resolved split DNS** - May need interface-specific config

5. **SELinux/AppArmor** - May block some operations on hardened systems

---

## QA Test Commands

```bash
# Prerequisites check
./bin/velum --help
which wg wg-quick curl jq nft iptables

# Configuration
sudo ./bin/velum-config

# Connect and test
sudo ./bin/velum-connect
sudo ./bin/velum-status
sudo ./bin/velum-test

# Kill switch verification
sudo ./bin/velum-killswitch status
sudo nft list table inet velum_killswitch  # or iptables -L VELUM_KILLSWITCH

# Monitor
sudo ./bin/velum-monitor start
./bin/velum-monitor status
sudo ./bin/velum-monitor stop

# Disconnect
sudo ./bin/velum-disconnect
```

---

## Files Modified This Session

| File | Changes |
|------|---------|
| `bin/velum-monitor` | Fixed notifications, added speech, debouncing, proper WG detection |
| `bin/velum-killswitch` | Skip notify if monitor running |
| `lib/os/macos.sh` | Removed duplicate afplay sound |
| `docs/spec/velum-v1.0-spec.md` | NEW - Comprehensive v1.0 specification |
| `docs/spec/velum_architecture.md` | DELETED - Replaced by v1.0 spec |
| `docs/spec/velum_config_v0.2.md` | DELETED - Replaced by v1.0 spec |

---

## Important Context

- User does NOT want new dependencies unless necessary
- Test incrementally after each change
- Commit only after user confirms functionality works
- Do not include Claude attribution in commits
- Reference `docs/spec/velum-v1.0-spec.md` for implementation details
- The v1.0 spec is designed to eventually scaffold a Go/Rust port

---

## Next Steps for Linux Development

1. Test OS detection and dependency checking
2. Test kill switch (nftables first, then iptables)
3. Test DNS management with your specific backend
4. Full connect/disconnect cycle
5. Monitor and notification testing
6. Fix any issues found
7. Update spec if Linux implementation differs significantly
