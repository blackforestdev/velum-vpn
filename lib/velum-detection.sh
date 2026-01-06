#!/usr/bin/env bash
# velum-detection.sh - VPN/proxy detection checking for server IPs
# Checks IPs against detection services and caches results

# Prevent multiple sourcing
[[ -n "${_VELUM_DETECTION_LOADED:-}" ]] && return 0
readonly _VELUM_DETECTION_LOADED=1

# Source dependencies
source "${BASH_SOURCE%/*}/velum-core.sh"

# ============================================================================
# CONFIGURATION
# ============================================================================

# Cache settings
DETECTION_CACHE_DIR="${VELUM_CACHE_DIR:-$HOME/.cache/velum}"
DETECTION_CACHE_FILE="${DETECTION_CACHE_DIR}/detection-cache.json"
DETECTION_CACHE_TTL=$((24 * 60 * 60))  # 24 hours in seconds

# API timeout (seconds)
DETECTION_API_TIMEOUT=5

# ============================================================================
# CACHE MANAGEMENT
# ============================================================================

# Initialize cache directory and file
init_detection_cache() {
    mkdir -p "$DETECTION_CACHE_DIR"
    chmod 700 "$DETECTION_CACHE_DIR"

    if [[ ! -f "$DETECTION_CACHE_FILE" ]]; then
        echo '{}' > "$DETECTION_CACHE_FILE"
        chmod 600 "$DETECTION_CACHE_FILE"
    fi

    # Fix ownership if running as root via sudo
    if [[ -n "${SUDO_USER:-}" ]]; then
        local sudo_uid sudo_gid
        sudo_uid=$(id -u "$SUDO_USER" 2>/dev/null)
        sudo_gid=$(id -g "$SUDO_USER" 2>/dev/null)
        if [[ -n "$sudo_uid" && -n "$sudo_gid" ]]; then
            chown "$sudo_uid:$sudo_gid" "$DETECTION_CACHE_DIR"
            chown "$sudo_uid:$sudo_gid" "$DETECTION_CACHE_FILE"
        fi
    fi
}

# Get cached result for an IP
# Usage: get_cached_detection "1.2.3.4"
# Returns: "clean|partial|flagged" or empty if not cached/expired
get_cached_detection() {
    local ip="$1"
    local now
    now=$(date +%s)

    init_detection_cache

    if [[ ! -f "$DETECTION_CACHE_FILE" ]]; then
        return
    fi

    local entry
    entry=$(jq -r --arg ip "$ip" '.[$ip] // empty' "$DETECTION_CACHE_FILE" 2>/dev/null)

    if [[ -z "$entry" ]]; then
        return
    fi

    local cached_time status
    cached_time=$(echo "$entry" | jq -r '.time // 0')
    status=$(echo "$entry" | jq -r '.status // empty')

    # Check if cache is still valid
    if [[ $((now - cached_time)) -lt $DETECTION_CACHE_TTL ]] && [[ -n "$status" ]]; then
        echo "$status"
    fi
}

# Save detection result to cache
# Usage: save_detection_cache "1.2.3.4" "clean" 2
save_detection_cache() {
    local ip="$1"
    local status="$2"
    local flags="${3:-0}"
    local now
    now=$(date +%s)

    init_detection_cache

    # Create entry
    local entry
    entry=$(jq -n --arg status "$status" --argjson flags "$flags" --argjson time "$now" \
        '{status: $status, flags: $flags, time: $time}')

    # Update cache file
    local tmp_file="${DETECTION_CACHE_FILE}.tmp"
    if jq --arg ip "$ip" --argjson entry "$entry" '.[$ip] = $entry' \
        "$DETECTION_CACHE_FILE" > "$tmp_file" 2>/dev/null; then
        mv "$tmp_file" "$DETECTION_CACHE_FILE"
        chmod 600 "$DETECTION_CACHE_FILE"
    else
        rm -f "$tmp_file"
    fi
}

# Clean expired entries from cache
clean_detection_cache() {
    local now
    now=$(date +%s)
    local cutoff=$((now - DETECTION_CACHE_TTL))

    init_detection_cache

    local tmp_file="${DETECTION_CACHE_FILE}.tmp"
    if jq --argjson cutoff "$cutoff" \
        'to_entries | map(select(.value.time > $cutoff)) | from_entries' \
        "$DETECTION_CACHE_FILE" > "$tmp_file" 2>/dev/null; then
        mv "$tmp_file" "$DETECTION_CACHE_FILE"
        chmod 600 "$DETECTION_CACHE_FILE"
    else
        rm -f "$tmp_file"
    fi
}

# ============================================================================
# DETECTION API CHECKS
# ============================================================================

# Check ip-api.com for hosting/proxy flags
# Returns: number of flags (0, 1, or 2)
_check_ip_api() {
    local ip="$1"
    local flags=0

    local response
    response=$(curl -s --tlsv1.2 --max-time "$DETECTION_API_TIMEOUT" \
        "http://ip-api.com/json/${ip}?fields=status,hosting,proxy" 2>/dev/null)

    if [[ -n "$response" && "$response" == *"status"* ]]; then
        local is_hosting is_proxy
        is_hosting=$(echo "$response" | jq -r '.hosting // false')
        is_proxy=$(echo "$response" | jq -r '.proxy // false')

        [[ "$is_hosting" == "true" ]] && ((flags++))
        [[ "$is_proxy" == "true" ]] && ((flags++))
    fi

    echo "$flags"
}

# Check ipapi.is for VPN/proxy/datacenter flags
# Returns: number of flags (0, 1, 2, or 3)
_check_ipapi_is() {
    local ip="$1"
    local flags=0

    local response
    response=$(curl -s --tlsv1.2 --max-time "$DETECTION_API_TIMEOUT" \
        "https://api.ipapi.is/?q=${ip}" 2>/dev/null)

    if [[ -n "$response" && "$response" == *"is_vpn"* ]]; then
        local is_vpn is_proxy is_datacenter
        is_vpn=$(echo "$response" | jq -r '.is_vpn // false')
        is_proxy=$(echo "$response" | jq -r '.is_proxy // false')
        is_datacenter=$(echo "$response" | jq -r '.is_datacenter // false')

        [[ "$is_vpn" == "true" ]] && ((flags++))
        [[ "$is_proxy" == "true" ]] && ((flags++))
        [[ "$is_datacenter" == "true" ]] && ((flags++))
    fi

    echo "$flags"
}

# Check ipinfo.io for known VPN/datacenter ASNs
# Returns: 1 if known VPN ASN, 0 otherwise
_check_ipinfo_asn() {
    local ip="$1"
    local flags=0

    local response
    response=$(curl -s --tlsv1.2 --max-time "$DETECTION_API_TIMEOUT" \
        "https://ipinfo.io/${ip}/json" 2>/dev/null)

    if [[ -n "$response" ]]; then
        local org
        org=$(echo "$response" | jq -r '.org // empty')

        # Check against known datacenter/VPN providers
        case "$org" in
            *M247*|*Datacamp*|*Leaseweb*|*Choopa*|*Vultr*|*DigitalOcean*)
                flags=1 ;;
            *Linode*|*OVH*|*Hetzner*|*Quadranet*|*Cogent*|*Glesys*)
                flags=1 ;;
            *"Private Internet"*|*Mullvad*|*NordVPN*|*ExpressVPN*|*Surfshark*)
                flags=1 ;;
            *ProtonVPN*|*IVPN*|*31173*|*Arelion*|*DataPacket*|*Servinga*)
                flags=1 ;;
            *xTom*|*FranTech*|*HostHatch*|*BuyVM*|*Privex*)
                flags=1 ;;
        esac
    fi

    echo "$flags"
}

# ============================================================================
# MAIN DETECTION FUNCTION
# ============================================================================

# Check an IP for VPN/proxy detection
# Usage: check_detection "1.2.3.4"
# Returns: "clean" (0 flags), "partial" (1-2 flags), "flagged" (3+ flags)
check_detection() {
    local ip="$1"

    # Check cache first
    local cached
    cached=$(get_cached_detection "$ip")
    if [[ -n "$cached" ]]; then
        echo "$cached"
        return
    fi

    # Run checks (could parallelize but keeping simple for now)
    local total_flags=0
    local ip_api_flags ipapi_is_flags ipinfo_flags

    # Run API checks
    ip_api_flags=$(_check_ip_api "$ip")
    ipapi_is_flags=$(_check_ipapi_is "$ip")
    ipinfo_flags=$(_check_ipinfo_asn "$ip")

    total_flags=$((ip_api_flags + ipapi_is_flags + ipinfo_flags))

    # Determine status
    local status
    if [[ $total_flags -eq 0 ]]; then
        status="clean"
    elif [[ $total_flags -le 2 ]]; then
        status="partial"
    else
        status="flagged"
    fi

    # Cache result
    save_detection_cache "$ip" "$status" "$total_flags"

    echo "$status"
}

# Check multiple IPs in parallel (using background jobs)
# Usage: check_detection_batch "ip1" "ip2" "ip3" ...
# Results are cached and can be retrieved with get_cached_detection
check_detection_batch() {
    local ips=("$@")
    local pids=()
    local max_parallel=5

    # Start background checks for uncached IPs (limited parallelism)
    local running=0
    for ip in "${ips[@]}"; do
        local cached
        cached=$(get_cached_detection "$ip")
        if [[ -z "$cached" ]]; then
            # Run check in background
            (check_detection "$ip" >/dev/null 2>&1) &
            pids+=($!)
            ((running++))

            # Limit parallelism
            if [[ $running -ge $max_parallel ]]; then
                # Wait for any one to finish
                wait -n 2>/dev/null || wait "${pids[0]}" 2>/dev/null || true
                running=$((running - 1))
            fi
        fi
    done

    # Wait for remaining jobs with timeout
    local timeout_end=$(($(date +%s) + 15))
    for pid in "${pids[@]}"; do
        if [[ $(date +%s) -lt $timeout_end ]]; then
            wait "$pid" 2>/dev/null || true
        else
            kill "$pid" 2>/dev/null || true
        fi
    done
}

# ============================================================================
# DISPLAY HELPERS
# ============================================================================

# Convert detection status to display symbol
# Usage: detection_to_symbol "clean" -> "✓"
detection_to_symbol() {
    local status="$1"
    case "$status" in
        "clean")   echo "✓" ;;
        "partial") echo "⚠" ;;
        "flagged") echo "✗" ;;
        *)         echo "?" ;;
    esac
}

# Convert detection status to colored display
# Usage: detection_to_display "clean" -> colored "✓ clean"
detection_to_display() {
    local status="$1"

    # Source colors if available
    local green="${C_GREEN:-}"
    local yellow="${C_YELLOW:-}"
    local red="${C_RED:-}"
    local reset="${C_RESET:-}"

    case "$status" in
        "clean")   echo "${green}✓${reset}" ;;
        "partial") echo "${yellow}⚠${reset}" ;;
        "flagged") echo "${red}✗${reset}" ;;
        "checking") echo "…" ;;
        *)         echo "?" ;;
    esac
}

# Get detection status with fallback for checking state
# Usage: get_detection_display "1.2.3.4"
get_detection_display() {
    local ip="$1"

    local status
    status=$(get_cached_detection "$ip")

    if [[ -n "$status" ]]; then
        detection_to_display "$status"
    else
        echo "…"  # Still checking
    fi
}
