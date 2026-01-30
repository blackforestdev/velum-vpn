# Velum Secure Server Cache Specification

**Status:** Draft - Concept Proposal  
**Version:** 0.1.0  
**Created:** 2026-01-30  
**Last Updated:** 2026-01-30  

## Overview

Velum currently fetches provider server lists on each configuration run. This is slow and creates unnecessary API traffic. A cache would improve UX, but any on‑disk metadata can expose users during device seizure. This spec documents a future **ultra‑secure server list cache** that minimizes forensic footprint and preserves Velum’s security‑first model.

This is **not** an implementation plan for immediate release. It documents requirements and a safe path for a future, hardened cache mechanism.

---

## Threat Model

Assume:
- Device seizure by state‑level adversary
- Forensic recovery of deleted files
- Credential correlation by timestamps and usage patterns

Non‑assumptions:
- Server lists are not secrets, but **metadata about access is**.

Design goal: **No stored evidence of when or how the list was fetched** beyond what is required for safe operation.

---

## Requirements

### R1: Opt‑in Only
Caching MUST be opt‑in. Default is **no server list cache**.

### R2: Minimal Metadata
If cached, only store:
- Provider identifier (e.g., `mullvad`, `ivpn`)
- Data payload (server list subset or full list)

Do **not** store:
- Fetch timestamps
- User IPs
- HTTP headers
- URLs or request logs
- Hostnames of the fetching machine

### R3: Encrypted at Rest
Cache must be encrypted with an explicit user‑supplied key. No implicit system keychains.

### R4: Ephemeral Option
Offer **RAM‑only cache** (tmpfs) as first‑class mode for highly sensitive users.

### R5: Explicit Lifecycle Controls
User must be able to:
- View cache status (enabled/disabled, provider count)
- Purge cache immediately
- Disable caching permanently

---

## Proposed Architecture (Future)

### Option A: Stand‑Alone Secure Cache Tool
- Separate binary or script: `velum-cache`
- Minimal JSON interface
- No dependency on system keychains
- Encryption: `libsodium` (secretbox) or AES‑256‑GCM

### Option B: Integrated Secure Cache Module
Add a `lib/velum-cache.sh` module:
- Interface: `cache_get provider`, `cache_put provider payload`, `cache_clear`
- Requires explicit user password per session
- Keys stored only in memory

### Preferred Mode: RAM‑Only "Goldfish" DB (gfdb)
**Default recommendation:** a short‑lived, RAM‑resident cache that is cleared on reboot or process exit.

Key properties:
- **RAM‑only** (tmpfs or in‑process map)
- **No disk writes**
- **Safe data reduction** (store only required fields)
- **Short‑lived** (expires quickly; “goldfish memory”)

Suggested name: **gfdb** (Goldfish DB).

---

## Storage Format (Encrypted)

**Encrypted Blob Content (plaintext):**
```json
{
  "provider": "mullvad",
  "payload": { ... server list ... }
}
```

**Encryption Metadata (outside plaintext):**
```
salt
nonce
ciphertext
```

No timestamps. No headers. No external metadata.

---

## Safe Data Reduction (Optional)

To further minimize stored data, the cache may store only fields required by Velum:
- hostname
- ip
- country_code / country_name
- city
- provider / owned
- public key (if required)

All other fields should be dropped.

---

## UX Requirements

- Default: **No caching**
- Explicit prompt: “Enable encrypted server list cache?” (off by default)
- Reminder on shutdown: “Cache still enabled”
- CLI:
  - `velum cache status`
  - `velum cache clear`
  - `velum cache disable`

---

## Security Notes

- **Do not use OS keychains** (metadata leaks identity).
- **Do not log fetch times**.
- **Do not store request URLs**.
- **Do not store provider responses raw** unless necessary.
- If integrated into a future multi‑hop workflow, the cache should support **multiple providers** without cross‑linking.

---

## Open Questions

1. Should the cache be per‑provider or global?
2. Should cache be invalidated on provider API version change?
3. For multi‑hop, should entry/exit lists be stored separately?

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1.0 | 2026-01-30 | Claude | Initial draft for secure server cache concept |
