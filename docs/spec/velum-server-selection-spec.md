# Velum Server Selection Specification

**Status:** Draft - Pending Review
**Version:** 0.4.1
**Created:** 2026-01-29
**Last Updated:** 2026-01-30

## Overview

This specification defines the server selection engine for Velum VPN Phase 4 configuration. The goal is to present users with optimal server choices based on their priority (quality vs speed) while maintaining security-first principles.

**Current Policy:** Auto mode is removed. Server selection is manual only.

---

## 0. Policy Decisions

### SEC-001: Manual-Only Selection (Policy)
**Severity:** Policy
**Status:** Resolved (by design)

**Decision:**
Server selection is manual only. Auto mode is intentionally excluded to preserve user agency and prevent silent selection of 5-Eyes or Unknown jurisdiction exits.

---

## 1. Known Issues (Current Implementation)

### 1.1 Critical Bugs

#### BUG-001: Quality Sort Latency Inversion
**Severity:** Critical
**Status:** Open

**Description:**
When sorting by quality, servers within the same recommendation tier are sorted by latency in **descending** order (highest latency first) instead of ascending (lowest latency first).

**Expected Behavior:**
Within each quality tier (★★★, ★★☆, etc.), servers should be sorted by latency ascending so the user sees the fastest high-quality servers first.

**Observed Behavior:**
```
  1.   272ms   Finland - Helsinki       ★★★  (slowest ★★★ shown first)
  ...
 45.   162ms   Sweden - Malmö           ★★★  (fastest ★★★ shown last)
```

**Root Cause:**
Sort command syntax error:
```bash
# Current (broken):
sort -t'|' -k1 -rn -k2 -n

# Fixed:
sort -t'|' -k1,1rn -k2,2n
```

The `-rn` flags apply ambiguously without explicit field ranges.

---

#### BUG-002: Initial Quality Selection Ignored
**Severity:** Critical
**Status:** Open

**Description:**
When user selects "Quality" priority (option 1), the initial display shows "sorted by latency" and presents servers sorted by speed instead.

**Root Cause:**
The `ask_choice()` function prints its menu to stdout, which gets captured in the variable along with the return value. Pattern matching fails because the variable starts with "Select priority" not "Quality".

**Fix Required:**
Use direct `read` instead of `ask_choice()` for priority selection, or modify `ask_choice()` to print menu to stderr.

---

#### BUG-003: Method Selection Also Affected
**Severity:** Critical
**Status:** Resolved (by removal)

**Description:**
The Auto/Manual method selection at the start of Phase 4 also uses `ask_choice()` and suffers from the same output contamination bug.

**Resolution:**
Method selection menu removed entirely (auto mode eliminated). No longer applicable.

---

### 1.2 UX Issues

#### UX-001: No Progress Indicator During Quality Scoring
**Severity:** Medium
**Status:** Open

**Description:**
After fetching 560 servers, there is a noticeable hang with no feedback while quality scores are calculated.

**Impact:**
User perceives the application as frozen.

---

#### UX-002: Poor Detection Coverage
**Severity:** Medium
**Status:** Open

**Description:**
Only 20 unique IPs were checked for VPN detection status out of 560 servers.

**Root Cause:**
Detection check runs on the first N entries of **unsorted** data before sorting occurs. Should run on top N of **sorted** data to ensure coverage aligns with displayed servers.

**Fix Required:**
1. Move detection check to AFTER initial sorting
2. Check top 100 of sorted results (covers 2 pages of display)
3. On re-sort (q/s toggle), detection cache is already populated so no re-check needed
4. Detection check count = min(100, total_servers)

---

#### SEC-004: Owned Servers Not Favored as Tie-Breaker
**Severity:** Medium
**Status:** Open

**Description:**
When two servers have the same quality score and latency, owned servers should be preferred over rented servers. Currently there is no tertiary sort key.

**Expected Behavior:**
Sort order: score (desc) → owned (desc) → latency (asc)
This ensures VPN-provider-owned infrastructure is preferred when quality and speed are equal.

**Fix Required:**
Add owned status as tertiary sort key.

---

#### UX-003: Redundant Menu Display
**Severity:** Low
**Status:** Open

**Description:**
Custom menu text is displayed, then `ask_choice()` displays its own menu (captured into variable). This creates confusion in the code flow.

---

### 1.3 Jurisdiction Detection Issues

#### SEC-005: Provider String Matching is Brittle
**Severity:** High
**Status:** Open

**Description:**
Provider strings from APIs include legal suffixes and punctuation (e.g., `"Zenlayer, Inc."`, `"Leaseweb B.V."`, `"M247 Ltd"`) that don't match the normalized keys in `PROVIDER_JURISDICTION`. These are treated as "unknown," which under-penalizes risky geo-locations.

**Impact:**
A Brazilian server hosted by "Zenlayer, Inc." won't match "zenlayer" → no 5-Eyes penalty applied → appears as high-quality when it should be flagged.

**Fix Required:**
Normalize provider strings before lookup: lowercase, strip legal suffixes, remove punctuation.

---

#### SEC-006: Unknown Country + 5-Eyes Host Not Flagged
**Severity:** Medium
**Status:** Open

**Description:**
`check_jurisdiction_mismatch()` only flags mismatch when server alliance is "Blind." If server country is "Unknown" but provider is 5-Eyes, no mismatch is detected.

**Impact:**
Servers with unrecognized country codes on 5-Eyes infrastructure get a pass instead of being flagged.

**Fix Required:**
Treat "Unknown" alliance same as "Blind" for mismatch detection purposes.

---

#### SEC-007: Unknown Provider Too Forgiving
**Severity:** Medium
**Status:** Open

**Description:**
When `owned=false` and provider jurisdiction is unknown, only -1 penalty is applied (same as verified safe rented). This is too forgiving for unverifiable hosting.

**Impact:**
Servers on unknown hosting providers appear safer than warranted.

**Fix Required:**
Apply -2 penalty when `owned=false` and provider is unknown. Display `?` symbol.

---

#### DATA-001: Duplicate Privacy Entry
**Severity:** Low
**Status:** Open

**Description:**
`COUNTRY_PRIVACY["NZ"]="2"` appears twice in `velum-jurisdiction.sh`.

**Fix Required:**
Remove duplicate entry.

---

#### DATA-002: Missing Country Aliases
**Severity:** Low
**Status:** Open

**Description:**
Country lookup maps lack common aliases:
- "Czech Republic" (missing, only "Czechia" and "CZ")
- "Republic of Korea" (missing, only "Korea" and "KR")
- "United States of America" (missing)

**Fix Required:**
Add missing aliases to both `COUNTRY_ALLIANCE` and `COUNTRY_PRIVACY` maps.

---

### 1.4 Performance Issues

#### PERF-001: Quality Scores Recalculated on Every Re-sort
**Severity:** Medium
**Status:** Open

**Description:**
When user presses 'q' to switch to quality sort, scores are recalculated for all 560 servers. This is wasteful since the scores don't change.

**Improvement:**
Pre-compute scores once after ping testing completes.

---

## 2. Design Requirements

### 2.1 Security Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| SEC-001 | ~~Never auto-select servers in 5-Eyes or Unknown jurisdictions without user awareness~~ (Resolved: auto mode removed) | ~~Must~~ |
| SEC-002 | Highlight jurisdiction mismatches (e.g., Swiss server on US infrastructure) | Must |
| SEC-003 | Detection status must influence recommendations | Should |
| SEC-004 | Owned servers preferred over rented when quality equal | Should |
| SEC-005 | Provider string normalization required before jurisdiction lookup | Must |
| SEC-006 | Unknown country on 5-Eyes host must be flagged as suspicious | Must |
| SEC-007 | Unknown provider on rented server requires uncertainty penalty | Should |

### 2.2 Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FUNC-001 | Test latency to ALL available servers (no arbitrary limits) | Must |
| FUNC-002 | Support two sort modes: Quality-first and Speed-first | Must |
| FUNC-003 | Allow instant re-sorting without re-pinging | Must |
| FUNC-004 | Paginate results (50 at a time, 'm' for more) | Must |
| FUNC-005 | ~~Allow switching to auto-mode from selection screen~~ (Removed - no auto mode) | ~~Should~~ |
| FUNC-006 | Remember user's sort preference for future sessions | Could |

### 2.3 UX Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| UX-001 | Show progress during all long-running operations | Must |
| UX-002 | Display clear sort mode in table header | Must |
| UX-003 | Use consistent visual indicators (★, ●, ✓, etc.) | Must |
| UX-004 | Provide legend explaining all symbols | Must |
| UX-005 | Color-code rows by recommendation level | Should |

---

## 3. Data Model

### 3.1 Server Entry Format

After ping testing, each server should be stored with pre-computed metadata:

```
Fields (pipe-delimited):
  1. quality_score    - Pre-computed recommendation score (0-3)
  2. owned_sort       - Sort key for owned preference: 1=owned, 2=unknown, 3=rented
  3. latency_ms       - Ping latency in milliseconds (9999 = timeout)
  4. server_id        - Provider's server identifier
  5. display_name     - Human-readable location (e.g., "Switzerland - Zurich")
  6. ip_address       - Server IP for connection
  7. hostname         - Server hostname/CN
  8. country_code     - ISO country code (e.g., "CH", "US")
  9. host_provider    - Infrastructure provider (e.g., "zenlayer", "31173")
 10. owned            - "true", "false", or "unknown"
```

**Note:** `owned_sort` is derived from `owned` during score pre-computation:
- `owned=true` → `owned_sort=1` (sorts first)
- `owned=unknown` → `owned_sort=2` (uncertainty kept separate)
- `owned=false` → `owned_sort=3` (rented, lowest preference)

**Implementation Note:** This adds a new field to the sort record. Update the data format string and any parsing/splitting logic to include `owned_sort`, and ensure it is recomputed on all code paths that build the list.

### 3.2 Quality Score Calculation

Score range: 0-3 (maps to ☆☆☆, ★☆☆, ★★☆, ★★★)

**Scoring Factors:**

| Factor | Points | Notes |
|--------|--------|-------|
| Alliance: Blind | +3 | Not in any intelligence alliance |
| Alliance: 14-Eyes | +2 | SIGINT Seniors Europe |
| Alliance: 9-Eyes | +1 | Extended UKUSA |
| Alliance: 5-Eyes | +0 | Core surveillance alliance |
| Privacy: 5 (Strong) | +3 | |
| Privacy: 4 (Good) | +2 | |
| Privacy: 3 (Moderate) | +1 | |
| Privacy: 1-2 | +0 | |
| Detection: Clean | +3 | Not flagged as VPN |
| Detection: Partial | +1 | Some services detect |
| Detection: Flagged | +0 | Widely detected |
| Owned by provider | +0 | No penalty |
| Rented (no mismatch) | -1 | Minor trust penalty |
| Rented (5-Eyes hosted) | -4 | Severe jurisdiction penalty |

**Score to Recommendation:**
- 7+ points → 3 (★★★ Recommended)
- 5-6 points → 2 (★★☆ Acceptable)
- 3-4 points → 1 (★☆☆ Caution)
- 0-2 points → 0 (☆☆☆ Avoid)

### 3.3 Host Provider Jurisdiction Detection

The jurisdiction detection system identifies when a server's claimed location differs from its hosting infrastructure's jurisdiction. This is critical for detecting "geo-masquerading" (e.g., a server claiming to be in Brazil but actually hosted on US infrastructure).

#### 3.3.1 Provider String Normalization (SEC-005)

**Problem:** Provider strings from APIs contain legal suffixes and punctuation that prevent matching:
- `"Zenlayer, Inc."` → should match `"zenlayer"`
- `"Leaseweb B.V."` → should match `"leaseweb"`
- `"M247 Ltd"` → should match `"m247"`
- `"31173 Services AB"` → should match `"31173"`

**Normalization Steps:**
1. Convert to lowercase
2. Strip punctuation: commas, periods, parentheses
3. Strip legal suffixes anywhere in the string: `Inc.`, `Inc`, `Ltd.`, `Ltd`, `LLC`, `B.V.`, `GmbH`, `AB`, `Corp.`, `Corp`, `Co.`, `Co`
4. Collapse multiple spaces to single space
5. Trim leading/trailing whitespace

**Implementation:**
```bash
normalize_provider() {
  local p="$1"
  p="${p,,}"                                    # lowercase
  p="${p//,/}"                                  # remove commas
  p=$(echo "$p" | sed -E 's/[().]//g')          # remove periods and parentheses
  p=$(echo "$p" | sed -E 's/\\b(inc|ltd|llc|b\\.v|gmbh|ab|corp|co)\\b//ig')  # strip suffixes anywhere
  p=$(echo "$p" | tr -s ' ')                    # collapse spaces
  p="${p## }"; p="${p%% }"                      # trim
  echo "$p"
}
```

#### 3.3.2 Provider Jurisdiction Map

Maps normalized provider names to their corporate jurisdiction:

| Provider | Jurisdiction | Alliance |
|----------|--------------|----------|
| zenlayer | US | 5-Eyes |
| leaseweb | US | 5-Eyes |
| quadranet | US | 5-Eyes |
| m247 | GB | 5-Eyes |
| datapacket | GB | 5-Eyes |
| techfutures | CA | 5-Eyes |
| 31173 | SE | 14-Eyes |
| hetzner | DE | 14-Eyes |
| creanova | FI | Blind |
| flokinet | IS | Blind |

#### 3.3.3 Mismatch Detection Logic

**Current Logic (has gap):**
```
if server_alliance == "Blind" AND provider_alliance == "5-Eyes":
    return "5-EYES-HOSTED"  # -4 penalty
```

**Gap (SEC-006):** Unknown country + 5-Eyes provider gets no flag.

**Fixed Logic:**
```
if (server_alliance == "Blind" OR server_alliance == "Unknown") AND provider_alliance == "5-Eyes":
    return "5-EYES-HOSTED"  # -4 penalty
```

#### 3.3.4 Unknown Provider Penalty (SEC-007)

**Current:** `owned=false` + `provider=unknown` → -1 penalty (same as verified safe)

**Fixed:** Apply additional uncertainty penalty when provider cannot be verified:

| Condition | Penalty | Symbol |
|-----------|---------|--------|
| owned=true | 0 | ● |
| owned=false, provider verified safe | -1 | ○ |
| owned=false, provider 5-Eyes mismatch | -4 | ⚑ |
| owned=false, provider unknown | -2 | ? |
| owned=unknown | -1 | ? |

### 3.4 Country Name Normalization

**Problem:** Country names from APIs may not match lookup keys:
- `"Czech Republic"` vs `"Czechia"` vs `"CZ"`
- `"Republic of Korea"` vs `"Korea"` vs `"KR"`
- `"United States of America"` vs `"United States"` vs `"USA"` vs `"US"`

**Solution:** Add aliases to `COUNTRY_ALLIANCE` and `COUNTRY_PRIVACY` maps, or normalize common variants before lookup.

**Known Missing Aliases:**
- Czech Republic → CZ
- Republic of Korea → KR
- South Korea → KR
- United States of America → US

### 3.5 Data Quality Issues

#### Duplicate Entry
`COUNTRY_PRIVACY["NZ"]="2"` appears twice in `velum-jurisdiction.sh`. Remove duplicate.

---

## 4. Sorting Algorithms

### 4.1 Quality-First Sort

**Purpose:** Show best privacy/security options first, with owned servers preferred, then fastest within each tier.

**Algorithm:**
```
Primary:   quality_score DESCENDING (★★★ before ★★☆)
Secondary: owned_sort ASCENDING (owned=1 before unknown=2 before rented=3)
Tertiary:  latency_ms ASCENDING (19ms before 272ms)
```

**Owned Sort Key:**
To enable owned-first tie-breaking, add an `owned_sort` field:
- `owned=true` → owned_sort=1
- `owned=unknown` → owned_sort=2
- `owned=false` → owned_sort=3

This ensures owned servers sort before rented/unknown when score and latency are equal (SEC-004).

**Implementation:**
```bash
# Data format: score|owned_sort|latency|id|name|ip|hostname|country_code|host_provider|owned
sort -t'|' -k1,1rn -k2,2n -k3,3n
```

**Expected Output:**
```
  1.   162ms   Sweden - Malmö           ★★★  ●  (fastest ★★★, owned)
  2.   165ms   Sweden - Malmö           ★★★  ●  (owned)
  3.   165ms   Sweden - Gothenburg      ★★★  ○  (same latency, rented after owned)
  ...
 45.   272ms   Finland - Helsinki       ★★★  ●  (slowest ★★★)
 46.   167ms   Netherlands - Amsterdam  ★★☆  ●  (fastest ★★☆)
```

### 4.2 Speed-First Sort

**Purpose:** Show fastest servers regardless of quality.

**Algorithm:**
```
Primary: latency_ms ASCENDING (19ms before 272ms)
```

**Implementation:**
```bash
# Data format: score|owned_sort|latency|id|name|ip|hostname|country_code|host_provider|owned
sort -t'|' -k3,3n
```

**Expected Output:**
```
  1.    19ms   USA - San Jose, CA       ☆☆☆  ○
  2.    24ms   USA - Los Angeles, CA    ☆☆☆  ○
  ...
```

---

## 5. User Flow

### 5.1 Phase 4 Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                 PHASE 4: SERVER SELECTION                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                   ┌──────────────────┐
                   │  Priority Mode   │  ◄── Uses direct read, NOT ask_choice()
                   │   1) Quality     │
                   │   2) Speed       │
                   └────────┬─────────┘
                                         │
                                         ▼
                              ┌────────────────────┐
                              │ Fetch Server List  │
                              │ (with progress)    │
                              └──────────┬─────────┘
                                         │
                                         ▼
                              ┌────────────────────┐
                              │ Parallel Ping Test │
                              │ (all servers)      │
                              └──────────┬─────────┘
                                         │
                                         ▼
                              ┌────────────────────┐
                              │ Pre-compute Scores │
                              │ + owned_sort field │
                              │ (with progress)    │
                              └──────────┬─────────┘
                                         │
                                         ▼
                              ┌────────────────────┐
                              │ Initial Sort       │
                              │ (by user priority) │
                              └──────────┬─────────┘
                                         │
                                         ▼
                              ┌────────────────────┐
                              │ Check Detection    │
                              │ (top 100 of sorted │
                              │  results)          │
                              └──────────┬─────────┘
                                         │
                                         ▼
                     ┌────────────────────────────────────┐
                     │         SELECTION LOOP             │
                     │  ┌────────────────────────────┐    │
                     │  │ Display sorted table       │◄───┼──┐
                     │  │ (50 servers, paginated)    │    │  │
                     │  └─────────────┬──────────────┘    │  │
                     │                │                   │  │
                     │                ▼                   │  │
                     │  ┌────────────────────────────┐    │  │
                     │  │ User Input:                │    │  │
                     │  │  [1-N] Select server       │────┼──┼──► Done
                     │  │  [m]   Show more           │────┼──┘
                     │  │  [q]   Quality sort        │────┼──┘
                     │  │  [s]   Speed sort          │────┼──┘
                     │  └────────────────────────────┘    │
                     └────────────────────────────────────┘
```

**Note:** On re-sort (`q`/`s`), run detection for any newly visible rows not already cached.

---

## 6. Implementation Phases

### Phase 1: Bug Fixes (Critical)
- [ ] Fix sort command syntax with explicit field ranges (BUG-001)
- [ ] Fix priority selection - use direct read, not ask_choice (BUG-002)
- [ ] Fix ask_choice() globally - redirect menu to stderr
- [ ] Remove auto mode entirely (SEC-001) - delete method selection menu, `CONFIG[server_auto]`, and auto-selection logic

### Phase 2: Data Flow Refactor
- [ ] Pre-compute quality scores after ping testing
- [ ] Add owned_sort field (1=owned, 2=unknown, 3=rented) for tie-breaking (SEC-004)
- [ ] Store in single array with 10-field format
- [ ] Eliminate redundant score calculations (PERF-001)

### Phase 2.5: Jurisdiction Detection Hardening
- [ ] Implement provider string normalization (SEC-005)
- [ ] Flag Unknown country + 5-Eyes host as mismatch (SEC-006)
- [ ] Apply -2 penalty for unknown provider on rented servers (SEC-007)
- [ ] Remove duplicate NZ privacy entry (DATA-001)
- [ ] Add missing country aliases (DATA-002)

### Phase 3: Detection & UX
- [ ] Move detection check to AFTER initial sort (UX-002)
- [ ] Check top 100 of sorted results
- [ ] On re-sort, check detection for newly visible servers (current page + next page)
- [ ] Add progress indicator for score calculation
- [ ] Clean up menu display code
- [ ] Remove [a] auto mode option from selection loop

### Phase 4: Testing & Validation
- [ ] Test with Mullvad (560 servers)
- [ ] Test with IVPN
- [ ] Test with PIA
- [ ] Verify quality sort: ★★★ first, owned before rented, fastest within tier
- [ ] Verify speed sort: fastest overall first
- [ ] Verify detection symbols appear for displayed servers (not random unsorted ones)
- [ ] Verify no auto mode remnants (search codebase for server_auto)

---

## 7. Test Cases

### TC-001: Quality Sort Order
**Given:** 560 servers with mixed quality scores
**When:** User selects Quality priority
**Then:**
- ★★★ servers appear first
- Within ★★★, lowest latency appears first
- ★★☆ servers appear after all ★★★
- Within ★★☆, lowest latency appears first

### TC-002: Speed Sort Order
**Given:** 560 servers with varied latencies
**When:** User selects Speed priority
**Then:** Servers sorted by latency ascending regardless of quality

### TC-003: Re-sort Without Re-ping
**Given:** User is viewing quality-sorted list
**When:** User presses 's' for speed sort
**Then:** List re-sorts instantly (no network calls)

### TC-004: Pagination
**Given:** 560 servers available
**When:** User presses 'm' multiple times
**Then:** Display shows 50 → 100 → 150 → ... servers

### TC-005: Owned Tie-Breaker
**Given:** Two ★★★ servers with identical latency (e.g., 165ms Sweden)
**When:** User views quality-sorted list
**Then:** Owned server (●) appears before rented server (○)

### TC-006: No Auto Mode
**Given:** User runs velum config
**When:** Reaches Phase 4 server selection
**Then:**
- No Auto/Manual method selection menu appears
- Goes directly to Priority selection (Quality/Speed)
- No [a] option in server selection loop
- `CONFIG[server_auto]` does not exist in saved config

### TC-007: Detection on Sorted Data
**Given:** 560 servers, detection cache empty
**When:** User selects Quality priority
**Then:** Detection checks run on top 100 of quality-sorted servers (not random unsorted servers)

### TC-008: Provider String Normalization (SEC-005)
**Given:** Server with `host_provider = "Zenlayer, Inc."`
**When:** Jurisdiction lookup is performed
**Then:**
- Normalized to "zenlayer"
- Matches US jurisdiction
- If server claims Brazil, shows ⚑ and -4 penalty

### TC-009: Unknown Country + 5-Eyes Host (SEC-006)
**Given:** Server with unknown country code, `host_provider = "quadranet"`, `owned = false`
**When:** Mismatch check is performed
**Then:** Flagged as `5-EYES-HOSTED`, -4 penalty applied, ⚑ symbol shown

### TC-010: Unknown Provider Penalty (SEC-007)
**Given:** Server with `owned = false`, `host_provider = "acme-unknown-host"`
**When:** Score is calculated
**Then:** -2 penalty applied (not -1), `?` symbol shown

### TC-011: Country Alias Resolution (DATA-002)
**Given:** Server with country = "Czech Republic"
**When:** Alliance lookup is performed
**Then:** Resolves to "Blind" (same as "CZ" or "Czechia")

---

## 8. Open Questions

1. **Should we filter out timed-out servers (9999ms)?**
   - Current: Show all, they appear at bottom
   - Alternative: Hide them entirely

2. **Detection check timing:**
   - Current: Check top N before display
   - Alternative: Lazy-check as user pages through

3. **Score persistence:**
   - Should quality scores be cached between sessions?
   - Could avoid recalculation if server list unchanged

4. **Geographic pre-filtering:**
   - Should we offer region filter before ping testing?
   - Would reduce 560 servers to ~50-100 for faster testing

---

## Appendix A: Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1.0 | 2026-01-29 | Claude | Initial draft documenting known issues |
| 0.2.0 | 2026-01-29 | Claude | Spec refinement: added owned_sort tie-breaker (SEC-004), explicit detection coverage (top 100), clarified priority menu uses direct read |
| 0.3.0 | 2026-01-29 | Claude | Removed auto mode entirely (SEC-001 resolved by removal). Security-first users should choose their exit node deliberately. |
| 0.3.1 | 2026-01-29 | Claude | Restored auto mode with mandatory 5-Eyes/Unknown warning, added owned_sort 3-tier tie-breaker, clarified detection on re-sort. |
| 0.3.2 | 2026-01-29 | Claude | Removed auto mode entirely. Security-first users should choose their exit node deliberately. |
| 0.4.0 | 2026-01-29 | Claude | Added jurisdiction detection hardening: SEC-005 (provider normalization), SEC-006 (unknown country + 5-Eyes), SEC-007 (unknown provider penalty), DATA-001/002 (data quality fixes). |
| 0.4.1 | 2026-01-30 | Claude | Clarified manual-only policy, tightened provider normalization, added detection-on-resort note, and documented owned_sort data format migration. |
