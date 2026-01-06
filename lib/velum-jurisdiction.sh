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
    COUNTRY_ALLIANCE["GB"]="5-Eyes"
    COUNTRY_ALLIANCE["UK"]="5-Eyes"
    COUNTRY_ALLIANCE["CA"]="5-Eyes"
    COUNTRY_ALLIANCE["Canada"]="5-Eyes"
    COUNTRY_ALLIANCE["AU"]="5-Eyes"
    COUNTRY_ALLIANCE["Australia"]="5-Eyes"
    COUNTRY_ALLIANCE["NZ"]="5-Eyes"

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
    COUNTRY_PRIVACY["GB"]="1"
    COUNTRY_PRIVACY["UK"]="1"
    COUNTRY_PRIVACY["AU"]="1"
    COUNTRY_PRIVACY["Australia"]="1"
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
get_alliance() {
    local country="$1"
    local alliance="${COUNTRY_ALLIANCE[$country]:-}"

    # If not found, try uppercase
    if [[ -z "$alliance" ]]; then
        alliance="${COUNTRY_ALLIANCE[${country^^}]:-}"
    fi

    # Default to Blind if unknown (conservative assumption)
    echo "${alliance:-Blind}"
}

# Get privacy rating for a country (by code or name)
get_privacy() {
    local country="$1"
    local privacy="${COUNTRY_PRIVACY[$country]:-}"

    # If not found, try uppercase
    if [[ -z "$privacy" ]]; then
        privacy="${COUNTRY_PRIVACY[${country^^}]:-}"
    fi

    # Default to 3 (Moderate) if unknown
    echo "${privacy:-3}"
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
# DISPLAY HELPERS
# ============================================================================

# Print the legend for server selection table
print_jurisdiction_legend() {
    echo "Legend:"
    echo "  Alliance: 5-Eyes | 9-Eyes | 14-Eyes | Blind (non-ISN)"
    echo "  Privacy:  █████ Strong | ████░ Good | ███░░ Moderate | ██░░░ Fair | █░░░░ Weak"
    echo "  Detect:   ✓ clean | ⚠ partial | ✗ flagged | … pending"
    echo "  Rec:      ★★★ Recommended | ★★☆ Acceptable | ★☆☆ Caution | ☆☆☆ Avoid"
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
