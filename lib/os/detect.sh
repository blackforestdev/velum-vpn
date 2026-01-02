#!/usr/bin/env bash
# detect.sh - OS detection and loader for velum-vpn
# Sources the appropriate OS-specific module

# Prevent multiple sourcing
[[ -n "${_VELUM_OS_DETECT_LOADED:-}" ]] && return 0
readonly _VELUM_OS_DETECT_LOADED=1

# ============================================================================
# OS DETECTION
# ============================================================================

# Detect the operating system
# Returns: "macos" | "linux" | "unsupported"
detect_os() {
  case "$(uname -s)" in
    Darwin)
      echo "macos"
      ;;
    Linux)
      echo "linux"
      ;;
    *)
      echo "unsupported"
      ;;
  esac
}

# Detect Linux distribution
# Returns: distro name (lowercase) or "unknown"
detect_distro() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    echo ""
    return
  fi

  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    echo "${ID:-unknown}"
  elif [[ -f /etc/debian_version ]]; then
    echo "debian"
  elif [[ -f /etc/redhat-release ]]; then
    echo "rhel"
  else
    echo "unknown"
  fi
}

# Detect package manager
# Returns: apt | dnf | yum | pacman | brew | unknown
detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  elif command -v pacman >/dev/null 2>&1; then
    echo "pacman"
  elif command -v brew >/dev/null 2>&1; then
    echo "brew"
  else
    echo "unknown"
  fi
}

# ============================================================================
# OS MODULE LOADING
# ============================================================================

# Directory containing OS modules
_OS_MODULE_DIR="${BASH_SOURCE%/*}"

# Current OS
VELUM_OS=$(detect_os)
export VELUM_OS

# Load the appropriate OS module
load_os_module() {
  local os="${1:-$VELUM_OS}"
  local module_path="${_OS_MODULE_DIR}/${os}.sh"

  if [[ ! -f "$module_path" ]]; then
    if [[ "$os" == "unsupported" ]]; then
      echo "ERROR: Unsupported operating system: $(uname -s)" >&2
      return 1
    else
      echo "ERROR: OS module not found: $module_path" >&2
      return 1
    fi
  fi

  # shellcheck source=/dev/null
  source "$module_path"
}

# ============================================================================
# OS CAPABILITY CHECKS
# ============================================================================

# Check if we have WireGuard tools installed
has_wireguard() {
  command -v wg >/dev/null 2>&1 && command -v wg-quick >/dev/null 2>&1
}

# Check if we have the required tools for this OS
check_os_requirements() {
  local os="${1:-$VELUM_OS}"
  local missing=()

  # Common requirements
  if ! command -v curl >/dev/null 2>&1; then
    missing+=("curl")
  fi
  if ! command -v jq >/dev/null 2>&1; then
    missing+=("jq")
  fi
  if ! has_wireguard; then
    missing+=("wireguard-tools")
  fi

  # OS-specific requirements
  case "$os" in
    macos)
      # pf is built-in, but check for wireguard-go
      if ! command -v wireguard-go >/dev/null 2>&1; then
        missing+=("wireguard-go (brew install wireguard-go)")
      fi
      ;;
    linux)
      # Check for iptables or nftables
      if ! command -v iptables >/dev/null 2>&1 && ! command -v nft >/dev/null 2>&1; then
        missing+=("iptables or nftables")
      fi
      # Check for ip command (iproute2)
      if ! command -v ip >/dev/null 2>&1; then
        missing+=("iproute2")
      fi
      ;;
  esac

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing required packages: ${missing[*]}" >&2
    return 1
  fi

  return 0
}

# ============================================================================
# AUTO-LOAD
# ============================================================================

# Automatically load OS module when this file is sourced
if [[ "$VELUM_OS" != "unsupported" ]]; then
  load_os_module "$VELUM_OS" || true
fi
