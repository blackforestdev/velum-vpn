#!/usr/bin/env bash
# velum-unit.sh - Offline unit tests for velum-vpn
# Runs without sudo, network, or VPN connection
# Usage: ./tests/velum-unit.sh

set -euo pipefail

# ============================================================================
# SETUP
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VELUM_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export VELUM_ROOT

# Source libraries under test
source "$VELUM_ROOT/lib/velum-jurisdiction.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ============================================================================
# TEST FRAMEWORK
# ============================================================================

assert_eq() {
    local expected="$1"
    local actual="$2"
    local desc="${3:-}"

    ((TESTS_RUN++)) || true

    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++)) || true
        echo -e "  ${GREEN}PASS${NC}: $desc"
        return 0
    else
        ((TESTS_FAILED++)) || true
        echo -e "  ${RED}FAIL${NC}: $desc"
        echo -e "        expected: '$expected'"
        echo -e "        actual:   '$actual'"
        return 1
    fi
}

section() {
    echo
    echo -e "${YELLOW}[$1]${NC}"
}

# ============================================================================
# SANITIZE FIELD TESTS
# ============================================================================

# Mock _sanitize_field from velum-config (can't source full config without dependencies)
_sanitize_field() {
    local value="$1"
    value=$(printf '%s' "$value" | tr -d '[:cntrl:]' | tr '|' '/')
    printf '%s' "$value"
}

test_sanitize_field() {
    section "Sanitize Field Tests"

    # Normal string unchanged
    local result
    result=$(_sanitize_field "Brazil - Fortaleza")
    assert_eq "Brazil - Fortaleza" "$result" "Normal string unchanged"

    # Pipe replaced with slash
    result=$(_sanitize_field "Test|Provider")
    assert_eq "Test/Provider" "$result" "Pipe replaced with slash"

    # Multiple pipes replaced
    result=$(_sanitize_field "A|B|C")
    assert_eq "A/B/C" "$result" "Multiple pipes replaced"

    # Control characters stripped (tab, newline)
    result=$(_sanitize_field $'Test\tName')
    assert_eq "TestName" "$result" "Tab stripped"

    result=$(_sanitize_field $'Test\nName')
    assert_eq "TestName" "$result" "Newline stripped"

    # ANSI escape stripped
    result=$(_sanitize_field $'\e[31mRed\e[0m')
    assert_eq "[31mRed[0m" "$result" "ANSI escape code stripped"

    # Empty string
    result=$(_sanitize_field "")
    assert_eq "" "$result" "Empty string handled"

    # Spaces preserved
    result=$(_sanitize_field "  Leading and trailing  ")
    assert_eq "  Leading and trailing  " "$result" "Spaces preserved"
}

# ============================================================================
# ALLIANCE LOOKUP TESTS
# ============================================================================

test_alliance_lookup() {
    section "Alliance Lookup Tests"

    local result

    # 5-Eyes by code
    result=$(get_alliance "US")
    assert_eq "5-Eyes" "$result" "US -> 5-Eyes"

    result=$(get_alliance "GB")
    assert_eq "5-Eyes" "$result" "GB -> 5-Eyes"

    result=$(get_alliance "CA")
    assert_eq "5-Eyes" "$result" "CA -> 5-Eyes"

    # 5-Eyes by name
    result=$(get_alliance "United States")
    assert_eq "5-Eyes" "$result" "United States -> 5-Eyes"

    result=$(get_alliance "United Kingdom")
    assert_eq "5-Eyes" "$result" "United Kingdom -> 5-Eyes"

    # 9-Eyes
    result=$(get_alliance "NL")
    assert_eq "9-Eyes" "$result" "NL -> 9-Eyes"

    result=$(get_alliance "FR")
    assert_eq "9-Eyes" "$result" "FR -> 9-Eyes"

    # 14-Eyes
    result=$(get_alliance "DE")
    assert_eq "14-Eyes" "$result" "DE -> 14-Eyes"

    result=$(get_alliance "SE")
    assert_eq "14-Eyes" "$result" "SE -> 14-Eyes"

    # Blind
    result=$(get_alliance "CH")
    assert_eq "Blind" "$result" "CH -> Blind"

    result=$(get_alliance "BR")
    assert_eq "Blind" "$result" "BR -> Blind"

    # Unknown (not in map)
    result=$(get_alliance "XX")
    assert_eq "Unknown" "$result" "XX -> Unknown (not in map)"

    result=$(get_alliance "")
    assert_eq "Unknown" "$result" "Empty -> Unknown"

    result=$(get_alliance "null")
    assert_eq "Unknown" "$result" "null -> Unknown"

    # Case insensitivity
    result=$(get_alliance "us")
    assert_eq "5-Eyes" "$result" "us (lowercase) -> 5-Eyes"

    result=$(get_alliance "ch")
    assert_eq "Blind" "$result" "ch (lowercase) -> Blind"
}

# ============================================================================
# PRIVACY LOOKUP TESTS
# ============================================================================

test_privacy_lookup() {
    section "Privacy Lookup Tests"

    local result

    # Strong (5)
    result=$(get_privacy "CH")
    assert_eq "5" "$result" "CH -> 5 (Strong)"

    result=$(get_privacy "IS")
    assert_eq "5" "$result" "IS -> 5 (Strong)"

    # Good (4)
    result=$(get_privacy "RO")
    assert_eq "4" "$result" "RO -> 4 (Good)"

    # Moderate (3)
    result=$(get_privacy "BR")
    assert_eq "3" "$result" "BR -> 3 (Moderate)"

    # Fair (2)
    result=$(get_privacy "NZ")
    assert_eq "2" "$result" "NZ -> 2 (Fair)"

    # Weak (1)
    result=$(get_privacy "US")
    assert_eq "1" "$result" "US -> 1 (Weak)"

    result=$(get_privacy "United States")
    assert_eq "1" "$result" "United States -> 1 (Weak)"

    # Unknown defaults to 2 (conservative)
    result=$(get_privacy "XX")
    assert_eq "2" "$result" "XX -> 2 (unknown defaults to Fair)"

    result=$(get_privacy "")
    assert_eq "2" "$result" "Empty -> 2 (conservative)"
}

# ============================================================================
# PROVIDER JURISDICTION TESTS
# ============================================================================

test_provider_jurisdiction() {
    section "Provider Jurisdiction Tests"

    local result

    # US providers
    result=$(get_provider_jurisdiction "zenlayer")
    assert_eq "US" "$result" "zenlayer -> US"

    result=$(get_provider_jurisdiction "Zenlayer")
    assert_eq "US" "$result" "Zenlayer (caps) -> US"

    result=$(get_provider_jurisdiction "ZENLAYER")
    assert_eq "US" "$result" "ZENLAYER (upper) -> US"

    # UK providers
    result=$(get_provider_jurisdiction "datapacket")
    assert_eq "GB" "$result" "datapacket -> GB"

    result=$(get_provider_jurisdiction "m247")
    assert_eq "GB" "$result" "m247 -> GB"

    # Canada providers
    result=$(get_provider_jurisdiction "techfutures")
    assert_eq "CA" "$result" "techfutures -> CA"

    # Sweden (Mullvad)
    result=$(get_provider_jurisdiction "31173")
    assert_eq "SE" "$result" "31173 -> SE (Mullvad AS)"

    # Multi-word provider
    result=$(get_provider_jurisdiction "leaseweb nl")
    assert_eq "NL" "$result" "leaseweb nl -> NL"

    # Unknown provider
    result=$(get_provider_jurisdiction "unknownprovider")
    assert_eq "unknown" "$result" "unknownprovider -> unknown"

    result=$(get_provider_jurisdiction "")
    assert_eq "unknown" "$result" "Empty -> unknown"
}

# ============================================================================
# FIVE EYES CHECK TESTS
# ============================================================================

test_five_eyes_check() {
    section "Five Eyes Provider Check Tests"

    # US provider
    if is_provider_five_eyes "zenlayer"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "  ${GREEN}PASS${NC}: zenlayer is 5-Eyes"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "  ${RED}FAIL${NC}: zenlayer should be 5-Eyes"
    fi

    # UK provider
    if is_provider_five_eyes "datapacket"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "  ${GREEN}PASS${NC}: datapacket is 5-Eyes"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "  ${RED}FAIL${NC}: datapacket should be 5-Eyes"
    fi

    # Non-5-Eyes provider (NL)
    if is_provider_five_eyes "worldstream"; then
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "  ${RED}FAIL${NC}: worldstream should NOT be 5-Eyes"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "  ${GREEN}PASS${NC}: worldstream is NOT 5-Eyes"
    fi

    # Unknown provider
    if is_provider_five_eyes "unknownprovider"; then
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "  ${RED}FAIL${NC}: unknownprovider should NOT be 5-Eyes (unknown)"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "  ${GREEN}PASS${NC}: unknownprovider is NOT 5-Eyes (unknown)"
    fi
}

# ============================================================================
# PROVIDER SYMBOL TESTS
# ============================================================================

test_provider_symbol() {
    section "Provider Symbol Tests"

    local result

    # Owned
    result=$(provider_to_symbol "anyProvider" "true" "CH")
    assert_eq "●" "$result" "owned=true -> ●"

    # Unknown ownership
    result=$(provider_to_symbol "anyProvider" "unknown" "CH")
    assert_eq "?" "$result" "owned=unknown -> ?"

    # Unknown country
    result=$(provider_to_symbol "zenlayer" "false" "XX")
    assert_eq "?" "$result" "Unknown country -> ?"

    # Unknown provider (rented)
    result=$(provider_to_symbol "unknownprovider" "false" "CH")
    assert_eq "?" "$result" "Unknown provider -> ?"

    # 5-Eyes mismatch (Blind country, 5-Eyes provider)
    result=$(provider_to_symbol "zenlayer" "false" "BR")
    assert_eq "⚑" "$result" "Blind country + 5-Eyes provider -> ⚑"

    result=$(provider_to_symbol "zenlayer" "false" "CH")
    assert_eq "⚑" "$result" "CH (Blind) + zenlayer (US) -> ⚑"

    # No mismatch (5-Eyes country, 5-Eyes provider)
    result=$(provider_to_symbol "zenlayer" "false" "US")
    assert_eq "○" "$result" "US + US provider -> ○ (no mismatch)"

    result=$(provider_to_symbol "datapacket" "false" "CA")
    assert_eq "○" "$result" "CA + UK provider -> ○ (both 5-Eyes)"

    # No mismatch (non-5-Eyes country, non-5-Eyes provider)
    result=$(provider_to_symbol "worldstream" "false" "NL")
    assert_eq "○" "$result" "NL + NL provider -> ○ (no mismatch)"
}

# ============================================================================
# RECOMMENDATION SCORING TESTS
# ============================================================================

test_recommendation_scoring() {
    section "Recommendation Scoring Tests"

    local result

    # Best case: Blind country, strong privacy, clean detection, owned
    result=$(calculate_recommendation_v2 "CH" "5" "clean" "" "true")
    assert_eq "3" "$result" "CH owned clean -> 3 (Recommended)"

    # Worst case: 5-Eyes country, weak privacy, flagged detection
    result=$(calculate_recommendation_v2 "US" "1" "flagged" "" "true")
    assert_eq "0" "$result" "US flagged -> 0 (Avoid)"

    # Unknown country treated conservatively
    result=$(calculate_recommendation_v2 "XX" "2" "clean" "" "true")
    assert_eq "1" "$result" "Unknown country -> lower score"

    # 5-Eyes hosted penalty
    result=$(calculate_recommendation_v2 "BR" "3" "clean" "zenlayer" "false")
    assert_eq "0" "$result" "BR + Zenlayer (5-Eyes mismatch) -> 0"

    # Unknown ownership penalty (small)
    result=$(calculate_recommendation_v2 "CH" "5" "clean" "" "unknown")
    assert_eq "3" "$result" "CH owned=unknown -> still high (small penalty)"

    # Partial detection (CH=3 + privacy5=3 + partial=1 = 7 → score 3)
    result=$(calculate_recommendation_v2 "CH" "5" "partial" "" "true")
    assert_eq "3" "$result" "CH partial detection -> 3 (still high due to excellent country+privacy)"

    # Partial detection on weaker country (DE=2 + privacy3=1 + partial=1 = 4 → score 1)
    result=$(calculate_recommendation_v2 "DE" "3" "partial" "" "true")
    assert_eq "1" "$result" "DE partial detection -> 1 (partial lowers weaker baseline)"
}

# ============================================================================
# JURISDICTION MISMATCH TESTS
# ============================================================================

test_jurisdiction_mismatch() {
    section "Jurisdiction Mismatch Tests"

    local result

    # Owned = no mismatch check
    result=$(check_jurisdiction_mismatch "CH" "zenlayer" "true")
    assert_eq "" "$result" "owned=true -> no mismatch"

    # Unknown ownership
    result=$(check_jurisdiction_mismatch "CH" "zenlayer" "unknown")
    assert_eq "UNKNOWN" "$result" "owned=unknown -> UNKNOWN"

    # 5-Eyes hosted mismatch
    result=$(check_jurisdiction_mismatch "BR" "zenlayer" "false")
    assert_eq "5-EYES-HOSTED" "$result" "BR + Zenlayer -> 5-EYES-HOSTED"

    result=$(check_jurisdiction_mismatch "CH" "zenlayer" "false")
    assert_eq "5-EYES-HOSTED" "$result" "CH + Zenlayer -> 5-EYES-HOSTED"

    # No mismatch (same alliance)
    result=$(check_jurisdiction_mismatch "US" "zenlayer" "false")
    assert_eq "" "$result" "US + Zenlayer -> no mismatch (both 5-Eyes)"

    # Unknown provider
    result=$(check_jurisdiction_mismatch "CH" "unknownprovider" "false")
    assert_eq "UNKNOWN" "$result" "Unknown provider -> UNKNOWN"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo "=============================================="
    echo "       velum-vpn Unit Tests"
    echo "=============================================="

    test_sanitize_field
    test_alliance_lookup
    test_privacy_lookup
    test_provider_jurisdiction
    test_five_eyes_check
    test_provider_symbol
    test_recommendation_scoring
    test_jurisdiction_mismatch

    echo
    echo "=============================================="
    echo "                 SUMMARY"
    echo "=============================================="
    echo
    echo "  Tests run:    $TESTS_RUN"
    echo -e "  ${GREEN}Passed:       $TESTS_PASSED${NC}"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "  ${RED}Failed:       $TESTS_FAILED${NC}"
    else
        echo -e "  Failed:       $TESTS_FAILED"
    fi
    echo

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "${RED}FAILED${NC}"
        exit 1
    else
        echo -e "${GREEN}ALL TESTS PASSED${NC}"
        exit 0
    fi
}

main "$@"
