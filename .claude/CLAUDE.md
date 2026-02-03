# Project Instructions

## Security-First Philosophy

Velum is an **ultra-hardened VPN tool**. Security is not a feature—it is the foundation. Every design decision, code change, and feature addition MUST be evaluated through a security lens.

### Core Principles

1. **Assume Device Capture**
   - Design as if the user's device will be seized by an adversary (LEO, border agents, thieves)
   - Persistent storage of credentials is a liability, not a convenience
   - Minimize forensic footprint on disk

2. **Credentials Are Toxic**
   - Account IDs (Mullvad, IVPN) ARE the authentication—possession = access
   - NEVER store credentials in plaintext by default
   - Short-lived tokens may be cached; permanent credentials require explicit user opt-in with encryption

3. **Fail Closed, Not Open**
   - When in doubt, block traffic rather than leak it
   - Parse errors = reject, not warn-and-continue (for security-critical configs)
   - Missing authentication = refuse to connect, not prompt inline

4. **No Silent Network Calls**
   - Network operations require explicit or configured consent
   - Background refresh without user awareness is a privacy violation

5. **Defense in Depth**
   - Multiple layers: firewall rules + interface config + DNS protection
   - Don't rely on any single mechanism

6. **Minimize Trust Surface**
   - Don't trust API responses blindly—validate and sanitize
   - Don't trust config files—parse safely, never `source`
   - Don't trust environment—validate paths, check permissions

### Security Review Checklist

Before committing ANY code, verify:
- [ ] No plaintext credential storage introduced
- [ ] No new `source` of untrusted files
- [ ] No command injection vectors (unquoted variables in commands)
- [ ] No path traversal vulnerabilities
- [ ] Sensitive data cleared from memory after use (`unset`)
- [ ] File permissions are restrictive (600 for secrets, 700 for dirs)
- [ ] Ownership set correctly under sudo
- [ ] Error messages don't leak sensitive information

### Threat Model Awareness

Velum users may face:
- State-level adversaries
- Device seizure at borders
- Compelled credential disclosure
- Network-level surveillance
- Endpoint compromise

Design for the paranoid user. Convenience features must be opt-in, not default.

---

## Git Commits
- Do NOT include Claude Code attribution in commits
- Do NOT include co-authorship lines
- Claude is a hired developer; hired developers do not receive co-authorship credit

## QA Testing
- Do NOT push changes until functionality has been tested
- After each refactor or hardening change, test the affected scripts before committing
- Commit and push only after user confirms the changes work correctly
- If multiple related changes are made, test incrementally where possible

## Cross-Platform Compatibility
- Velum supports both macOS and Linux (Debian/Ubuntu)
- Code changes MUST NOT break functionality on either platform
- Fixes or corrections for Linux MUST NOT break working macOS functionality
- Fixes or corrections for macOS MUST NOT break working Linux functionality
- Use OS detection (`$VELUM_OS`) to branch platform-specific logic
- Test on both platforms when possible, or clearly document platform-specific changes

## Documentation

**README.md is the source of truth for users.** It MUST stay current with the codebase at all times.

### Mandatory README Updates

Update README.md **before committing** whenever ANY of the following change:

- **Features**: Added, modified, or removed functionality
- **Commands**: New commands, changed syntax, removed commands, new subcommands
- **Configuration**: New config keys, changed defaults, removed options
- **Providers**: Added, modified, or removed provider support
- **Dependencies**: New requirements, changed versions, removed dependencies
- **Security behavior**: Changes to kill switch, DNS, credential handling, etc.
- **Architecture**: New files, renamed modules, changed directory structure
- **Environment variables**: New, changed, or removed variables

### README Sections to Keep Current

| Section | Update When |
|---------|-------------|
| Features list | Any feature added/removed/changed |
| Supported Providers table | Provider support changes |
| Requirements | Dependencies change |
| Commands | Any command or subcommand changes |
| Configuration | Config keys or defaults change |
| Architecture diagram | File structure changes |
| Troubleshooting | New common issues discovered |

### No Documentation Debt

Documentation debt is unacceptable. If a feature exists in code but not in README, users cannot discover it. If README describes something that no longer exists, users are misled.

**Rule:** Every PR/commit that changes user-facing behavior MUST include corresponding README updates.
