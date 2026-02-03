# Velum Specification Index

**Last Updated:** 2026-02-03

This document is the single source of truth for specification status across the Velum project.

---

## Quick Reference

| Spec | Status | Version | Blocks | Blocked By |
|------|--------|---------|--------|------------|
| [v1.0](velum-v1.0-spec.md) | Reference | 1.0.0 | - | - |
| [credential-security](velum-credential-security-spec.md) | Implemented | 0.4.0 | - | - |
| [server-selection](velum-server-selection-spec.md) | Complete | 1.0.0 | - | - |
| [security-remediation](velum-security-remediation-plan.md) | Complete | 0.6.0 | - | - |
| [profiles](velum-profiles-spec.md) | Draft | 0.1.0 | multihop | - |
| [multihop](velum-multihop-spec.md) | Design | 0.2.0 | - | profiles |
| [tokenizer](velum-tokenizer-spec.md) | Design | 0.2.2 | - | - |
| [secure-server-cache](velum-secure-server-cache-spec.md) | Concept | 0.1.0 | - | - |

---

## Status Definitions

| Status | Description |
|--------|-------------|
| **Reference** | Foundation document describing current architecture |
| **Implemented** | Code complete and tested |
| **Complete** | Spec finalized, code merged |
| **Draft** | Ready for implementation review |
| **Design** | Still evolving, not ready for implementation |
| **Concept** | Future exploration, not committed |

---

## Dependency Graph

```
                    ┌─────────────┐
                    │  profiles   │
                    │   (Draft)   │
                    └──────┬──────┘
                           │
                           │ blocks
                           ▼
                    ┌─────────────┐
                    │  multihop   │
                    │  (Design)   │
                    └─────────────┘
```

All other specs are independent.

---

## Spec Summaries

### velum-v1.0-spec.md
**Status:** Reference | **Version:** 1.0.0

Comprehensive specification of Velum's current architecture. Documents the command structure, provider system, OS abstraction layer, security model, and configuration system. Serves as the canonical reference for how Velum works today.

### velum-credential-security-spec.md
**Status:** Implemented | **Version:** 0.4.0

Defines credential storage architecture with security-first principles. Covers threat model, credential classification, encrypted vault implementation (Argon2id + AES-256-CBC/HMAC-SHA256), and tmpfs session storage. External credential sources removed in v0.4.0 due to forensic metadata exposure.

### velum-server-selection-spec.md
**Status:** Complete | **Version:** 1.0.0

Specifies the Phase 4 server selection engine. Manual-only selection (no auto mode), quality/speed/detectability sorting, jurisdiction detection, and provider normalization. All implementation complete.

### velum-security-remediation-plan.md
**Status:** Complete | **Version:** 0.6.0

Tracks remediation of security findings from the 2026-01-28 audit. All phases complete: memory cleanup, variable quoting, SUDO_USER validation, plaintext storage removal, tmpfs tokens, encrypted vault, and hardened credential sources.

### velum-profiles-spec.md
**Status:** Draft | **Version:** 0.1.0

Defines named profile system for saving multiple VPN configurations. Covers directory structure, profile file format, safe parsing security, CLI commands, and migration from legacy single-config model. Foundation for multi-hop feature.

### velum-multihop-spec.md
**Status:** Design | **Version:** 0.2.0

Specifies multi-hop (cascading VPN) feature for routing traffic through two servers. Depends on profiles spec. Covers chained WireGuard tunnels, cross-provider support, phased kill switch, and security model for nested tunnels.

### velum-tokenizer-spec.md
**Status:** Design | **Version:** 0.2.2

Defines independent token management subsystem. Multi-account support per vendor, token lifecycle management, configurable auto-refresh behavior, and secure storage. Operational terminology for account naming.

### velum-secure-server-cache-spec.md
**Status:** Concept | **Version:** 0.1.0

Future exploration of ultra-secure server list caching. Opt-in only, minimal metadata, encrypted at rest, RAM-only option. Designed to minimize forensic footprint while improving UX.

---

## Maintenance

When updating specs:
1. Update the spec's header fields (Version, Status, Last Updated)
2. Update this index's Quick Reference table
3. Update dependency information if relationships change

---

*End of Index*
