#!/usr/bin/env bash
# velum-jurisdiction.sh - Country privacy and alliance classification
# Provides jurisdiction data for server selection decisions

# Prevent multiple sourcing
[[ -n "${_VELUM_JURISDICTION_LOADED:-}" ]] && return 0
readonly _VELUM_JURISDICTION_LOADED=1

# ============================================================================
# INTELLIGENCE ALLIANCE CLASSIFICATION
# ============================================================================
# 5-Eyes:  Core anglophone intelligence sharing (UKUSA Agreement)
# 9-Eyes:  5-Eyes + Denmark, France, Netherlands, Norway
# 14-Eyes: 9-Eyes + Germany, Belgium, Italy, Sweden, Spain (SIGINT Seniors)
# Blind:   Not member of any known intelligence sharing alliance

declare -A COUNTRY_ALLIANCE
declare -A COUNTRY_PRIVACY

# Initialize alliance data
_init_jurisdiction_data() {
    # 5-Eyes (UKUSA Agreement - 1946)
    COUNTRY_ALLIANCE["US"]="5-Eyes"
    COUNTRY_ALLIANCE["USA"]="5-Eyes"
    COUNTRY_ALLIANCE["United States"]="5-Eyes"
    COUNTRY_ALLIANCE["United States of America"]="5-Eyes"
    COUNTRY_ALLIANCE["GB"]="5-Eyes"
    COUNTRY_ALLIANCE["UK"]="5-Eyes"
    COUNTRY_ALLIANCE["United Kingdom"]="5-Eyes"
    COUNTRY_ALLIANCE["CA"]="5-Eyes"
    COUNTRY_ALLIANCE["Canada"]="5-Eyes"
    COUNTRY_ALLIANCE["AU"]="5-Eyes"
    COUNTRY_ALLIANCE["Australia"]="5-Eyes"
    COUNTRY_ALLIANCE["NZ"]="5-Eyes"
    COUNTRY_ALLIANCE["New Zealand"]="5-Eyes"

    # 9-Eyes (5-Eyes + 4)
    COUNTRY_ALLIANCE["DK"]="9-Eyes"
    COUNTRY_ALLIANCE["Denmark"]="9-Eyes"
    COUNTRY_ALLIANCE["FR"]="9-Eyes"
    COUNTRY_ALLIANCE["France"]="9-Eyes"
    COUNTRY_ALLIANCE["NL"]="9-Eyes"
    COUNTRY_ALLIANCE["Netherlands"]="9-Eyes"
    COUNTRY_ALLIANCE["NO"]="9-Eyes"
    COUNTRY_ALLIANCE["Norway"]="9-Eyes"

    # 14-Eyes (SIGINT Seniors Europe)
    COUNTRY_ALLIANCE["DE"]="14-Eyes"
    COUNTRY_ALLIANCE["Germany"]="14-Eyes"
    COUNTRY_ALLIANCE["BE"]="14-Eyes"
    COUNTRY_ALLIANCE["Belgium"]="14-Eyes"
    COUNTRY_ALLIANCE["IT"]="14-Eyes"
    COUNTRY_ALLIANCE["Italy"]="14-Eyes"
    COUNTRY_ALLIANCE["SE"]="14-Eyes"
    COUNTRY_ALLIANCE["Sweden"]="14-Eyes"
    COUNTRY_ALLIANCE["ES"]="14-Eyes"
    COUNTRY_ALLIANCE["Spain"]="14-Eyes"

    # Blind - Notable privacy jurisdictions (not in any alliance)
    COUNTRY_ALLIANCE["CH"]="Blind"
    COUNTRY_ALLIANCE["Switzerland"]="Blind"
    COUNTRY_ALLIANCE["IS"]="Blind"
    COUNTRY_ALLIANCE["Iceland"]="Blind"
    COUNTRY_ALLIANCE["RO"]="Blind"
    COUNTRY_ALLIANCE["Romania"]="Blind"
    COUNTRY_ALLIANCE["PA"]="Blind"
    COUNTRY_ALLIANCE["Panama"]="Blind"
    COUNTRY_ALLIANCE["VG"]="Blind"
    COUNTRY_ALLIANCE["BVI"]="Blind"
    COUNTRY_ALLIANCE["MY"]="Blind"
    COUNTRY_ALLIANCE["Malaysia"]="Blind"
    COUNTRY_ALLIANCE["SG"]="Blind"
    COUNTRY_ALLIANCE["Singapore"]="Blind"
    COUNTRY_ALLIANCE["JP"]="Blind"
    COUNTRY_ALLIANCE["Japan"]="Blind"
    COUNTRY_ALLIANCE["HK"]="Blind"
    COUNTRY_ALLIANCE["FI"]="Blind"
    COUNTRY_ALLIANCE["Finland"]="Blind"
    COUNTRY_ALLIANCE["EE"]="Blind"
    COUNTRY_ALLIANCE["Estonia"]="Blind"
    COUNTRY_ALLIANCE["LV"]="Blind"
    COUNTRY_ALLIANCE["Latvia"]="Blind"
    COUNTRY_ALLIANCE["LT"]="Blind"
    COUNTRY_ALLIANCE["Lithuania"]="Blind"
    COUNTRY_ALLIANCE["CZ"]="Blind"
    COUNTRY_ALLIANCE["Czechia"]="Blind"
    COUNTRY_ALLIANCE["Czech Republic"]="Blind"
    COUNTRY_ALLIANCE["AT"]="Blind"
    COUNTRY_ALLIANCE["Austria"]="Blind"
    COUNTRY_ALLIANCE["LU"]="Blind"
    COUNTRY_ALLIANCE["Luxembourg"]="Blind"
    COUNTRY_ALLIANCE["BG"]="Blind"
    COUNTRY_ALLIANCE["Bulgaria"]="Blind"
    COUNTRY_ALLIANCE["RS"]="Blind"
    COUNTRY_ALLIANCE["Serbia"]="Blind"
    COUNTRY_ALLIANCE["MD"]="Blind"
    COUNTRY_ALLIANCE["Moldova"]="Blind"
    COUNTRY_ALLIANCE["UA"]="Blind"
    COUNTRY_ALLIANCE["Ukraine"]="Blind"
    COUNTRY_ALLIANCE["PL"]="Blind"
    COUNTRY_ALLIANCE["Poland"]="Blind"
    COUNTRY_ALLIANCE["HU"]="Blind"
    COUNTRY_ALLIANCE["Hungary"]="Blind"
    COUNTRY_ALLIANCE["HR"]="Blind"
    COUNTRY_ALLIANCE["Croatia"]="Blind"
    COUNTRY_ALLIANCE["SI"]="Blind"
    COUNTRY_ALLIANCE["Slovenia"]="Blind"
    COUNTRY_ALLIANCE["SK"]="Blind"
    COUNTRY_ALLIANCE["Slovakia"]="Blind"
    COUNTRY_ALLIANCE["GR"]="Blind"
    COUNTRY_ALLIANCE["Greece"]="Blind"
    COUNTRY_ALLIANCE["PT"]="Blind"
    COUNTRY_ALLIANCE["Portugal"]="Blind"
    COUNTRY_ALLIANCE["IE"]="Blind"
    COUNTRY_ALLIANCE["Ireland"]="Blind"
    COUNTRY_ALLIANCE["CY"]="Blind"
    COUNTRY_ALLIANCE["Cyprus"]="Blind"
    COUNTRY_ALLIANCE["MT"]="Blind"
    COUNTRY_ALLIANCE["Malta"]="Blind"
    COUNTRY_ALLIANCE["AL"]="Blind"
    COUNTRY_ALLIANCE["Albania"]="Blind"
    COUNTRY_ALLIANCE["BA"]="Blind"
    COUNTRY_ALLIANCE["Bosnia"]="Blind"
    COUNTRY_ALLIANCE["ME"]="Blind"
    COUNTRY_ALLIANCE["Montenegro"]="Blind"
    COUNTRY_ALLIANCE["XK"]="Blind"
    COUNTRY_ALLIANCE["Kosovo"]="Blind"
    COUNTRY_ALLIANCE["BR"]="Blind"
    COUNTRY_ALLIANCE["Brazil"]="Blind"
    COUNTRY_ALLIANCE["MX"]="Blind"
    COUNTRY_ALLIANCE["Mexico"]="Blind"
    COUNTRY_ALLIANCE["AR"]="Blind"
    COUNTRY_ALLIANCE["Argentina"]="Blind"
    COUNTRY_ALLIANCE["CL"]="Blind"
    COUNTRY_ALLIANCE["Chile"]="Blind"
    COUNTRY_ALLIANCE["CO"]="Blind"
    COUNTRY_ALLIANCE["Colombia"]="Blind"
    COUNTRY_ALLIANCE["PE"]="Blind"
    COUNTRY_ALLIANCE["Peru"]="Blind"
    COUNTRY_ALLIANCE["CR"]="Blind"
    COUNTRY_ALLIANCE["ZA"]="Blind"
    COUNTRY_ALLIANCE["IL"]="Blind"
    COUNTRY_ALLIANCE["Israel"]="Blind"
    COUNTRY_ALLIANCE["AE"]="Blind"
    COUNTRY_ALLIANCE["UAE"]="Blind"
    COUNTRY_ALLIANCE["IN"]="Blind"
    COUNTRY_ALLIANCE["India"]="Blind"
    COUNTRY_ALLIANCE["KR"]="Blind"
    COUNTRY_ALLIANCE["Korea"]="Blind"
    COUNTRY_ALLIANCE["South Korea"]="Blind"
    COUNTRY_ALLIANCE["Republic of Korea"]="Blind"
    COUNTRY_ALLIANCE["TW"]="Blind"
    COUNTRY_ALLIANCE["Taiwan"]="Blind"
    COUNTRY_ALLIANCE["TH"]="Blind"
    COUNTRY_ALLIANCE["Thailand"]="Blind"
    COUNTRY_ALLIANCE["VN"]="Blind"
    COUNTRY_ALLIANCE["Vietnam"]="Blind"
    COUNTRY_ALLIANCE["PH"]="Blind"
    COUNTRY_ALLIANCE["Philippines"]="Blind"
    COUNTRY_ALLIANCE["ID"]="Blind"
    COUNTRY_ALLIANCE["Indonesia"]="Blind"

    # ============================================================================
    # PRIVACY JURISDICTION RATING (1-5 scale)
    # ============================================================================

    # 5 - Strong: Excellent laws, resists pressure, proven track record
    COUNTRY_PRIVACY["CH"]="5"
    COUNTRY_PRIVACY["Switzerland"]="5"
    COUNTRY_PRIVACY["IS"]="5"
    COUNTRY_PRIVACY["Iceland"]="5"
    COUNTRY_PRIVACY["PA"]="5"
    COUNTRY_PRIVACY["Panama"]="5"
    COUNTRY_PRIVACY["VG"]="5"
    COUNTRY_PRIVACY["BVI"]="5"
    COUNTRY_PRIVACY["MD"]="5"
    COUNTRY_PRIVACY["Moldova"]="5"

    # 4 - Good: Solid protections with minor caveats
    COUNTRY_PRIVACY["RO"]="4"
    COUNTRY_PRIVACY["Romania"]="4"
    COUNTRY_PRIVACY["FI"]="4"
    COUNTRY_PRIVACY["Finland"]="4"
    COUNTRY_PRIVACY["EE"]="4"
    COUNTRY_PRIVACY["Estonia"]="4"
    COUNTRY_PRIVACY["CZ"]="4"
    COUNTRY_PRIVACY["Czechia"]="4"
    COUNTRY_PRIVACY["Czech Republic"]="4"
    COUNTRY_PRIVACY["AT"]="4"
    COUNTRY_PRIVACY["Austria"]="4"
    COUNTRY_PRIVACY["SE"]="4"
    COUNTRY_PRIVACY["Sweden"]="4"
    COUNTRY_PRIVACY["LU"]="4"
    COUNTRY_PRIVACY["Luxembourg"]="4"
    COUNTRY_PRIVACY["BG"]="4"
    COUNTRY_PRIVACY["Bulgaria"]="4"
    COUNTRY_PRIVACY["RS"]="4"
    COUNTRY_PRIVACY["Serbia"]="4"
    COUNTRY_PRIVACY["SI"]="4"
    COUNTRY_PRIVACY["Slovenia"]="4"
    COUNTRY_PRIVACY["LV"]="4"
    COUNTRY_PRIVACY["Latvia"]="4"
    COUNTRY_PRIVACY["LT"]="4"
    COUNTRY_PRIVACY["Lithuania"]="4"
    COUNTRY_PRIVACY["HR"]="4"
    COUNTRY_PRIVACY["Croatia"]="4"
    COUNTRY_PRIVACY["SK"]="4"
    COUNTRY_PRIVACY["Slovakia"]="4"
    COUNTRY_PRIVACY["MT"]="4"
    COUNTRY_PRIVACY["Malta"]="4"
    COUNTRY_PRIVACY["CY"]="4"
    COUNTRY_PRIVACY["Cyprus"]="4"

    # 3 - Moderate: Some protections but known issues or pressure
    COUNTRY_PRIVACY["DE"]="3"
    COUNTRY_PRIVACY["Germany"]="3"
    COUNTRY_PRIVACY["NL"]="3"
    COUNTRY_PRIVACY["Netherlands"]="3"
    COUNTRY_PRIVACY["NO"]="3"
    COUNTRY_PRIVACY["Norway"]="3"
    COUNTRY_PRIVACY["DK"]="3"
    COUNTRY_PRIVACY["Denmark"]="3"
    COUNTRY_PRIVACY["FR"]="3"
    COUNTRY_PRIVACY["France"]="3"
    COUNTRY_PRIVACY["BE"]="3"
    COUNTRY_PRIVACY["Belgium"]="3"
    COUNTRY_PRIVACY["IT"]="3"
    COUNTRY_PRIVACY["Italy"]="3"
    COUNTRY_PRIVACY["ES"]="3"
    COUNTRY_PRIVACY["Spain"]="3"
    COUNTRY_PRIVACY["JP"]="3"
    COUNTRY_PRIVACY["Japan"]="3"
    COUNTRY_PRIVACY["SG"]="3"
    COUNTRY_PRIVACY["Singapore"]="3"
    COUNTRY_PRIVACY["HK"]="3"
    COUNTRY_PRIVACY["IE"]="3"
    COUNTRY_PRIVACY["Ireland"]="3"
    COUNTRY_PRIVACY["PL"]="3"
    COUNTRY_PRIVACY["Poland"]="3"
    COUNTRY_PRIVACY["GR"]="3"
    COUNTRY_PRIVACY["Greece"]="3"
    COUNTRY_PRIVACY["PT"]="3"
    COUNTRY_PRIVACY["Portugal"]="3"
    COUNTRY_PRIVACY["HU"]="3"
    COUNTRY_PRIVACY["Hungary"]="3"
    COUNTRY_PRIVACY["IL"]="3"
    COUNTRY_PRIVACY["Israel"]="3"
    COUNTRY_PRIVACY["KR"]="3"
    COUNTRY_PRIVACY["Korea"]="3"
    COUNTRY_PRIVACY["South Korea"]="3"
    COUNTRY_PRIVACY["Republic of Korea"]="3"
    COUNTRY_PRIVACY["TW"]="3"
    COUNTRY_PRIVACY["Taiwan"]="3"
    COUNTRY_PRIVACY["BR"]="3"
    COUNTRY_PRIVACY["Brazil"]="3"
    COUNTRY_PRIVACY["MX"]="3"
    COUNTRY_PRIVACY["Mexico"]="3"
    COUNTRY_PRIVACY["AR"]="3"
    COUNTRY_PRIVACY["Argentina"]="3"
    COUNTRY_PRIVACY["CL"]="3"
    COUNTRY_PRIVACY["Chile"]="3"
    COUNTRY_PRIVACY["CR"]="3"
    COUNTRY_PRIVACY["ZA"]="3"
    COUNTRY_PRIVACY["IN"]="3"
    COUNTRY_PRIVACY["India"]="3"
    COUNTRY_PRIVACY["TH"]="3"
    COUNTRY_PRIVACY["Thailand"]="3"
    COUNTRY_PRIVACY["AL"]="3"
    COUNTRY_PRIVACY["Albania"]="3"
    COUNTRY_PRIVACY["BA"]="3"
    COUNTRY_PRIVACY["Bosnia"]="3"
    COUNTRY_PRIVACY["ME"]="3"
    COUNTRY_PRIVACY["Montenegro"]="3"
    COUNTRY_PRIVACY["XK"]="3"
    COUNTRY_PRIVACY["Kosovo"]="3"
    COUNTRY_PRIVACY["UA"]="3"
    COUNTRY_PRIVACY["Ukraine"]="3"

    # 2 - Fair: Concerning laws or known compliance
    COUNTRY_PRIVACY["CA"]="2"
    COUNTRY_PRIVACY["Canada"]="2"
    COUNTRY_PRIVACY["NZ"]="2"
    COUNTRY_PRIVACY["AE"]="2"
    COUNTRY_PRIVACY["UAE"]="2"
    COUNTRY_PRIVACY["MY"]="2"
    COUNTRY_PRIVACY["Malaysia"]="2"
    COUNTRY_PRIVACY["VN"]="2"
    COUNTRY_PRIVACY["Vietnam"]="2"
    COUNTRY_PRIVACY["PH"]="2"
    COUNTRY_PRIVACY["Philippines"]="2"
    COUNTRY_PRIVACY["ID"]="2"
    COUNTRY_PRIVACY["Indonesia"]="2"
    COUNTRY_PRIVACY["CO"]="2"
    COUNTRY_PRIVACY["Colombia"]="2"
    COUNTRY_PRIVACY["PE"]="2"
    COUNTRY_PRIVACY["Peru"]="2"

    # 1 - Weak: Known for compliance, mandatory backdoors, mass surveillance
    COUNTRY_PRIVACY["US"]="1"
    COUNTRY_PRIVACY["USA"]="1"
    COUNTRY_PRIVACY["United States"]="1"
    COUNTRY_PRIVACY["United States of America"]="1"
    COUNTRY_PRIVACY["GB"]="1"
    COUNTRY_PRIVACY["UK"]="1"
    COUNTRY_PRIVACY["United Kingdom"]="1"
    COUNTRY_PRIVACY["AU"]="1"
    COUNTRY_PRIVACY["Australia"]="1"
    COUNTRY_PRIVACY["New Zealand"]="2"
}

# Initialize on source
_init_jurisdiction_data

# ============================================================================
# PRIVACY BAR VISUALIZATION
# ============================================================================

# Convert privacy rating (1-5) to visual bar
privacy_to_bar() {
    local rating="${1:-3}"
    case "$rating" in
        5) echo "█████" ;;
        4) echo "████░" ;;
        3) echo "███░░" ;;
        2) echo "██░░░" ;;
        1) echo "█░░░░" ;;
        *) echo "░░░░░" ;;
    esac
}

# Convert privacy rating to text
privacy_to_text() {
    local rating="${1:-3}"
    case "$rating" in
        5) echo "Strong" ;;
        4) echo "Good" ;;
        3) echo "Moderate" ;;
        2) echo "Fair" ;;
        1) echo "Weak" ;;
        *) echo "Unknown" ;;
    esac
}

# ============================================================================
# LOOKUP FUNCTIONS
# ============================================================================

# Get alliance for a country (by code or name)
# Returns: "5-Eyes", "9-Eyes", "14-Eyes", "Blind", or "Unknown"
get_alliance() {
    local country="$1"

    # Empty or null country is explicitly unknown
    if [[ -z "$country" || "$country" == "null" ]]; then
        echo "Unknown"
        return
    fi

    local alliance="${COUNTRY_ALLIANCE[$country]:-}"

    # If not found, try uppercase
    if [[ -z "$alliance" ]]; then
        alliance="${COUNTRY_ALLIANCE[${country^^}]:-}"
    fi

    # Unknown country = Unknown alliance (conservative - don't assume safe)
    echo "${alliance:-Unknown}"
}

# Get privacy rating for a country (by code or name)
# Returns: 1-5 rating, or 2 (Fair) for unknown countries (conservative)
get_privacy() {
    local country="$1"

    # Empty or null country gets conservative rating
    if [[ -z "$country" || "$country" == "null" ]]; then
        echo "2"
        return
    fi

    local privacy="${COUNTRY_PRIVACY[$country]:-}"

    # If not found, try uppercase
    if [[ -z "$privacy" ]]; then
        privacy="${COUNTRY_PRIVACY[${country^^}]:-}"
    fi

    # Default to 2 (Fair) if unknown - conservative, don't assume safe
    echo "${privacy:-2}"
}

# Get full jurisdiction info for a country
get_jurisdiction_info() {
    local country="$1"
    local alliance privacy bar text

    alliance=$(get_alliance "$country")
    privacy=$(get_privacy "$country")
    bar=$(privacy_to_bar "$privacy")
    text=$(privacy_to_text "$privacy")

    echo "${alliance}|${privacy}|${bar}|${text}"
}

# Extract country from location string
extract_country() {
    local location="$1"

    # Try "Country - City" format first
    if [[ "$location" == *" - "* ]]; then
        echo "${location%% - *}"
        return
    fi

    # Try "Country City" format (first word)
    echo "${location%% *}"
}

# ============================================================================
# RECOMMENDATION SCORING
# ============================================================================

# Calculate recommendation score based on all factors
calculate_recommendation() {
    local alliance="$1"
    local privacy="$2"
    local detection="${3:-clean}"

    local score=0

    # Alliance scoring (0-3 points)
    case "$alliance" in
        "Blind")   score=$((score + 3)) ;;
        "14-Eyes") score=$((score + 2)) ;;
        "9-Eyes")  score=$((score + 1)) ;;
        "5-Eyes")  score=$((score + 0)) ;;
    esac

    # Privacy scoring (0-3 points based on 1-5 rating)
    case "$privacy" in
        5) score=$((score + 3)) ;;
        4) score=$((score + 2)) ;;
        3) score=$((score + 1)) ;;
        2|1) score=$((score + 0)) ;;
    esac

    # Detection scoring (0-3 points)
    case "$detection" in
        "clean")   score=$((score + 3)) ;;
        "partial") score=$((score + 1)) ;;
        "flagged") score=$((score + 0)) ;;
    esac

    # Convert total (0-9) to recommendation (0-3)
    if [[ $score -ge 7 ]]; then
        echo "3"
    elif [[ $score -ge 5 ]]; then
        echo "2"
    elif [[ $score -ge 3 ]]; then
        echo "1"
    else
        echo "0"
    fi
}

# Convert recommendation score to stars
recommendation_to_stars() {
    local rec="${1:-0}"
    case "$rec" in
        3) echo "★★★" ;;
        2) echo "★★☆" ;;
        1) echo "★☆☆" ;;
        *) echo "☆☆☆" ;;
    esac
}

# ============================================================================
# HOSTING PROVIDER JURISDICTION
# ============================================================================
# Maps VPN hosting providers to their corporate jurisdiction (AS registration)
# This is critical: a "Brazil" server hosted by a US company may route through US

declare -A PROVIDER_JURISDICTION

_init_provider_jurisdiction() {
    # All keys are lowercase for consistent matching
    # Input should be normalized to lowercase before lookup

    # US-based providers (5-Eyes jurisdiction)
    PROVIDER_JURISDICTION["zenlayer"]="US"
    PROVIDER_JURISDICTION["leaseweb"]="US"      # US/NL but AS in US
    PROVIDER_JURISDICTION["leaseweb us"]="US"
    PROVIDER_JURISDICTION["quadranet"]="US"
    PROVIDER_JURISDICTION["colocrossing"]="US"
    PROVIDER_JURISDICTION["psychz"]="US"
    PROVIDER_JURISDICTION["serverhub"]="US"
    PROVIDER_JURISDICTION["enzu"]="US"
    PROVIDER_JURISDICTION["sharktech"]="US"
    PROVIDER_JURISDICTION["linode"]="US"
    PROVIDER_JURISDICTION["digitalocean"]="US"
    PROVIDER_JURISDICTION["vultr"]="US"
    PROVIDER_JURISDICTION["aws"]="US"
    PROVIDER_JURISDICTION["amazon"]="US"
    PROVIDER_JURISDICTION["google"]="US"
    PROVIDER_JURISDICTION["gcp"]="US"
    PROVIDER_JURISDICTION["microsoft"]="US"
    PROVIDER_JURISDICTION["azure"]="US"
    PROVIDER_JURISDICTION["cloudflare"]="US"
    PROVIDER_JURISDICTION["akamai"]="US"

    # UK-based providers (5-Eyes jurisdiction)
    PROVIDER_JURISDICTION["datapacket"]="GB"
    PROVIDER_JURISDICTION["m247"]="GB"
    PROVIDER_JURISDICTION["iomart"]="GB"
    PROVIDER_JURISDICTION["rapidswitch"]="GB"
    PROVIDER_JURISDICTION["uk2"]="GB"

    # Canada-based providers (5-Eyes jurisdiction)
    PROVIDER_JURISDICTION["ovh"]="CA"           # French but many AS via CA
    PROVIDER_JURISDICTION["ovh ca"]="CA"
    PROVIDER_JURISDICTION["techfutures"]="CA"   # Tech Futures Interactive, BC Canada

    # Australia-based providers (5-Eyes jurisdiction)
    PROVIDER_JURISDICTION["vocus"]="AU"
    PROVIDER_JURISDICTION["aussie broadband"]="AU"

    # Netherlands-based (9-Eyes but privacy-friendly)
    PROVIDER_JURISDICTION["worldstream"]="NL"
    PROVIDER_JURISDICTION["nforce"]="NL"
    PROVIDER_JURISDICTION["leaseweb nl"]="NL"
    PROVIDER_JURISDICTION["i3d"]="NL"
    PROVIDER_JURISDICTION["serverius"]="NL"

    # Germany-based (14-Eyes)
    PROVIDER_JURISDICTION["hetzner"]="DE"
    PROVIDER_JURISDICTION["contabo"]="DE"
    PROVIDER_JURISDICTION["netcup"]="DE"

    # Sweden-based (14-Eyes but Mullvad HQ)
    PROVIDER_JURISDICTION["31173"]="SE"         # Mullvad's own AS
    PROVIDER_JURISDICTION["31173 services ab"]="SE"
    PROVIDER_JURISDICTION["mullvad"]="SE"

    # Privacy-friendly jurisdictions
    PROVIDER_JURISDICTION["creanova"]="FI"
    PROVIDER_JURISDICTION["hostroyale"]="IN"    # India-based
    PROVIDER_JURISDICTION["xtom"]="HK"
    PROVIDER_JURISDICTION["tzulo"]="RO"
    PROVIDER_JURISDICTION["flokinet"]="IS"
    PROVIDER_JURISDICTION["1984"]="IS"          # 1984 Hosting, Iceland
    PROVIDER_JURISDICTION["bahnhof"]="SE"       # Swedish, privacy-focused

    # Singapore (Blind but surveillance concerns)
    PROVIDER_JURISDICTION["singtel"]="SG"
    PROVIDER_JURISDICTION["telin"]="SG"
}

# Initialize provider data
_init_provider_jurisdiction

# Normalize provider string for reliable lookup (SEC-005)
# Strips legal suffixes, punctuation, and normalizes whitespace
# Example: "Zenlayer, Inc." → "zenlayer"
normalize_provider() {
    local p="$1"

    # Handle empty input
    [[ -z "$p" ]] && { echo ""; return; }

    # Step 1: Convert to lowercase
    p="${p,,}"

    # Step 2: Remove commas
    p="${p//,/}"

    # Step 3: Remove periods and parentheses
    p=$(echo "$p" | sed -E 's/[().]//g')

    # Step 4: Strip legal suffixes anywhere in string
    # inc, ltd, llc, bv, gmbh, ab, corp, co (with optional trailing s)
    p=$(echo "$p" | sed -E 's/\b(inc|ltd|llc|bv|gmbh|ab|corp|co|services)\b//g')

    # Step 5: Collapse multiple spaces to single space
    p=$(echo "$p" | tr -s ' ')

    # Step 6: Trim leading/trailing whitespace
    p="${p## }"
    p="${p%% }"

    echo "$p"
}

# Get jurisdiction for a hosting provider
# Returns: country code (US, GB, etc.) or "unknown"
# Uses normalize_provider() for reliable matching (SEC-005)
get_provider_jurisdiction() {
    local provider="$1"

    # Handle empty input
    if [[ -z "$provider" ]]; then
        echo "unknown"
        return
    fi

    # Normalize provider string for reliable lookup
    local provider_normalized
    provider_normalized=$(normalize_provider "$provider")

    # Handle case where normalization results in empty string
    if [[ -z "$provider_normalized" ]]; then
        echo "unknown"
        return
    fi

    local jurisdiction="${PROVIDER_JURISDICTION[$provider_normalized]:-}"

    echo "${jurisdiction:-unknown}"
}

# Check if provider is in a 5-Eyes country
# Returns: 0 (true) if 5-Eyes, 1 (false) otherwise
is_provider_five_eyes() {
    local provider="$1"
    local jurisdiction
    jurisdiction=$(get_provider_jurisdiction "$provider")

    case "$jurisdiction" in
        US|GB|CA|AU|NZ) return 0 ;;
        *) return 1 ;;
    esac
}

# Check for jurisdiction mismatch (server location vs provider jurisdiction)
# Returns: "5-EYES-HOSTED", "JURISDICTION-MISMATCH", "UNKNOWN", or empty string
# owned can be: "true", "false", or "unknown"
check_jurisdiction_mismatch() {
    local server_country="$1"
    local provider="$2"
    local owned="$3"

    # If server is owned by VPN provider, trust the location
    if [[ "$owned" == "true" ]]; then
        echo ""
        return
    fi

    # If ownership is unknown, we can't assess with confidence
    if [[ "$owned" == "unknown" ]]; then
        echo "UNKNOWN"
        return
    fi

    # owned == "false" - check provider jurisdiction
    local provider_jurisdiction
    provider_jurisdiction=$(get_provider_jurisdiction "$provider")

    # If provider jurisdiction unknown, can't assess
    if [[ "$provider_jurisdiction" == "unknown" ]]; then
        echo "UNKNOWN"
        return
    fi

    local server_alliance provider_alliance
    server_alliance=$(get_alliance "$server_country")
    provider_alliance=$(get_alliance "$provider_jurisdiction")

    # Check for dangerous mismatch: server claims non-5-Eyes but provider is 5-Eyes (SEC-006)
    # Also flag Unknown country on 5-Eyes host as suspicious
    if [[ "$server_alliance" == "Blind" || "$server_alliance" == "Unknown" ]] && is_provider_five_eyes "$provider"; then
        echo "5-EYES-HOSTED"
        return
    fi

    # Check for any alliance mismatch
    if [[ "$server_alliance" != "$provider_alliance" ]]; then
        echo "JURISDICTION-MISMATCH"
        return
    fi

    echo ""
}

# Calculate recommendation with provider jurisdiction factored in
# Usage: calculate_recommendation_v2 country privacy detection provider owned
# owned can be: "true", "false", or "unknown"
calculate_recommendation_v2() {
    local country="$1"
    local privacy="$2"
    local detection="${3:-clean}"
    local provider="${4:-}"
    local owned="${5:-unknown}"

    # Get alliance from country
    local alliance
    alliance=$(get_alliance "$country")

    local score=0

    # Alliance scoring (0-3 points)
    # Unknown treated same as 5-Eyes (conservative - don't assume safe)
    case "$alliance" in
        "Blind")   score=$((score + 3)) ;;
        "14-Eyes") score=$((score + 2)) ;;
        "9-Eyes")  score=$((score + 1)) ;;
        "5-Eyes"|"Unknown")  score=$((score + 0)) ;;
    esac

    # Privacy scoring (0-3 points based on 1-5 rating)
    case "$privacy" in
        5) score=$((score + 3)) ;;
        4) score=$((score + 2)) ;;
        3) score=$((score + 1)) ;;
        2|1) score=$((score + 0)) ;;
    esac

    # Detection scoring (0-3 points)
    case "$detection" in
        "clean")   score=$((score + 3)) ;;
        "partial") score=$((score + 1)) ;;
        "flagged") score=$((score + 0)) ;;
    esac

    # Provider jurisdiction penalty (only when we have definite information)
    if [[ "$owned" == "false" ]]; then
        # Definitely rented - check for jurisdiction mismatch
        local mismatch
        mismatch=$(check_jurisdiction_mismatch "$country" "$provider" "$owned")

        if [[ "$mismatch" == "5-EYES-HOSTED" ]]; then
            # Severe penalty: non-5-Eyes location but 5-Eyes hosted
            score=$((score - 4))
        elif [[ "$mismatch" == "JURISDICTION-MISMATCH" ]]; then
            # Moderate penalty
            score=$((score - 2))
        elif [[ "$mismatch" == "UNKNOWN" ]]; then
            # Unknown provider jurisdiction - cannot verify hosting safety (SEC-007)
            # Apply uncertainty penalty (-2) instead of verified safe penalty (-1)
            score=$((score - 2))
        else
            # Provider verified safe - minor rented penalty
            score=$((score - 1))
        fi
    elif [[ "$owned" == "unknown" ]]; then
        # Unknown ownership - apply small uncertainty penalty
        # Don't assume worst case, but don't give full confidence either
        score=$((score - 1))
    fi
    # owned == "true" - no penalty (VPN provider owns the server)

    # Ensure score doesn't go negative
    [[ $score -lt 0 ]] && score=0

    # Convert total to recommendation (0-3)
    if [[ $score -ge 7 ]]; then
        echo "3"
    elif [[ $score -ge 5 ]]; then
        echo "2"
    elif [[ $score -ge 3 ]]; then
        echo "1"
    else
        echo "0"
    fi
}

# ============================================================================
# DISPLAY HELPERS
# ============================================================================

# Print the legend for server selection table
print_jurisdiction_legend() {
    echo "Legend:"
    echo "  Alliance: 5-Eyes | 9-Eyes | 14-Eyes | Blind (non-ISN) | Unknown"
    echo "  Privacy:  █████ Strong | ████░ Good | ███░░ Moderate | ██░░░ Fair | █░░░░ Weak"
    echo "  Host:     ● owned | ○ rented | ? unknown | ⚑ 5-Eyes hosted (jurisdiction mismatch)"
    echo "  Detect:   ✓ clean | ⚠ partial | ✗ flagged | … pending"
    echo "  Rec:      ★★★ Recommended | ★★☆ Acceptable | ★☆☆ Caution | ☆☆☆ Avoid"
    echo "  Sec:      A=Alliance P=Privacy O=Owned bonus U=Unknown ownership penalty M=Mismatch penalty L=Latency penalty"
}

# Convert provider/owned status to symbol
# owned can be: "true", "false", or "unknown"
provider_to_symbol() {
    local provider="$1"
    local owned="$2"
    local server_country="$3"

    # Handle unknown ownership
    if [[ "$owned" == "unknown" ]]; then
        echo "?"  # Unknown ownership - can't assess hosting risk
        return
    fi

    if [[ "$owned" == "true" ]]; then
        echo "●"  # Owned by VPN provider
        return
    fi

    # owned == "false" - check for jurisdiction mismatch
    local server_alliance
    server_alliance=$(get_alliance "$server_country")

    # If server country is unknown, we can't assess mismatch
    if [[ "$server_alliance" == "Unknown" ]]; then
        echo "?"  # Unknown country - can't assess hosting risk
        return
    fi

    local provider_jurisdiction
    provider_jurisdiction=$(get_provider_jurisdiction "$provider")

    # If we don't know the provider's jurisdiction, show unknown
    if [[ "$provider_jurisdiction" == "unknown" ]]; then
        echo "?"  # Unknown provider - can't assess hosting risk
        return
    fi

    # Check for 5-Eyes hosted mismatch (only when server claims non-5-Eyes)
    if [[ "$server_alliance" == "Blind" ]] && is_provider_five_eyes "$provider"; then
        echo "⚑"  # Warning: 5-Eyes jurisdiction mismatch
        return
    fi

    echo "○"  # Rented but no mismatch
}

# Format a single server row for display
format_server_row() {
    local num="$1"
    local latency="$2"
    local location="$3"
    local alliance="$4"
    local privacy_bar="$5"
    local detection="$6"
    local rec="$7"

    printf "%3d.  %6s   %-28s %-8s %s    %s    %s\n" \
        "$num" "$latency" "$location" "$alliance" "$privacy_bar" "$detection" "$rec"
}

# Print table header
print_server_table_header() {
    echo "───────────────────────────────────────────────────────────────────────────────────"
    printf "  %-3s %7s   %-26s %-8s %-5s  %-3s   %s\n" "#" "Latency" "Location" "Alliance" "Priv" "Det" "Rec"
    echo "───────────────────────────────────────────────────────────────────────────────────"
}

# Print table footer
print_server_table_footer() {
    echo "───────────────────────────────────────────────────────────────────────────────────"
}
