#!/usr/bin/env bash
# velum-core.sh - Core library for velum-vpn
# Provides: logging, colors, utilities, path detection

# Prevent multiple sourcing
[[ -n "${_VELUM_CORE_LOADED:-}" ]] && return 0
readonly _VELUM_CORE_LOADED=1

# ============================================================================
# PATH DETECTION
# ============================================================================

# Detect VELUM_ROOT (directory containing bin/, lib/, etc/)
_detect_velum_root() {
  local script_path="${BASH_SOURCE[1]:-$0}"
  local dir

  # Resolve symlinks
  while [[ -L "$script_path" ]]; do
    dir="$(cd -P "$(dirname "$script_path")" && pwd)"
    script_path="$(readlink "$script_path")"
    [[ "$script_path" != /* ]] && script_path="$dir/$script_path"
  done

  dir="$(cd -P "$(dirname "$script_path")" && pwd)"

  # Walk up until we find lib/ or bin/
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/lib" && -d "$dir/bin" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  # Fallback: assume we're in lib/
  echo "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
}

: "${VELUM_ROOT:=$(_detect_velum_root)}"
export VELUM_ROOT

# ============================================================================
# CONFIGURATION PATHS (XDG Base Directory Specification)
# ============================================================================

# XDG config directory (default: ~/.config)
_get_config_home() {
  if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
    echo "$XDG_CONFIG_HOME"
  elif [[ -n "${SUDO_USER:-}" ]]; then
    # Running as root via sudo - get real user's home
    local real_home
    if [[ "$(uname)" == "Darwin" ]]; then
      real_home=$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    else
      real_home=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
    fi
    echo "${real_home:-.}/.config"
  else
    echo "${HOME:-.}/.config"
  fi
}

# Velum config directory
VELUM_CONFIG_DIR="$(_get_config_home)/velum"
export VELUM_CONFIG_DIR

# Configuration file paths
VELUM_CONFIG_FILE="${VELUM_CONFIG_DIR}/velum.conf"
VELUM_TOKENS_DIR="${VELUM_CONFIG_DIR}/tokens"
VELUM_STATE_DIR="${VELUM_CONFIG_DIR}/state"

export VELUM_CONFIG_FILE VELUM_TOKENS_DIR VELUM_STATE_DIR

# Ensure config directory exists with proper permissions
ensure_config_dir() {
  local dir="$1"
  local mode="${2:-700}"

  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
    chmod "$mode" "$dir"

    # If running as root via sudo, fix ownership
    if [[ -n "${SUDO_USER:-}" ]]; then
      local sudo_uid sudo_gid
      sudo_uid=$(id -u "$SUDO_USER" 2>/dev/null)
      sudo_gid=$(id -g "$SUDO_USER" 2>/dev/null)
      if [[ -n "$sudo_uid" && -n "$sudo_gid" ]]; then
        chown "$sudo_uid:$sudo_gid" "$dir"
      fi
    fi
  fi
}

# Initialize all config directories
init_config_dirs() {
  ensure_config_dir "$VELUM_CONFIG_DIR" 700
  ensure_config_dir "$VELUM_TOKENS_DIR" 700
  ensure_config_dir "$VELUM_STATE_DIR" 700
}

# Legacy config path (for migration)
VELUM_LEGACY_CONFIG_DIR="/opt/piavpn-manual"

# Migrate from legacy location to XDG config
# Usage: migrate_legacy_config
migrate_legacy_config() {
  local legacy_dir="$VELUM_LEGACY_CONFIG_DIR"
  local migrated=false

  # Skip if no legacy directory
  [[ ! -d "$legacy_dir" ]] && return 0

  # Initialize new config directories
  init_config_dirs

  # Migrate velum.conf
  if [[ -f "$legacy_dir/velum.conf" && ! -f "$VELUM_CONFIG_FILE" ]]; then
    log_info "Migrating config from $legacy_dir/velum.conf..."
    cp "$legacy_dir/velum.conf" "$VELUM_CONFIG_FILE"
    chmod 600 "$VELUM_CONFIG_FILE"
    migrated=true
  fi

  # Migrate token
  if [[ -f "$legacy_dir/token" && ! -f "$VELUM_TOKENS_DIR/token" ]]; then
    log_info "Migrating token..."
    cp "$legacy_dir/token" "$VELUM_TOKENS_DIR/token"
    chmod 600 "$VELUM_TOKENS_DIR/token"
    migrated=true
  fi

  # Migrate Mullvad token/account
  if [[ -f "$legacy_dir/mullvad_token" && ! -f "$VELUM_TOKENS_DIR/mullvad_token" ]]; then
    log_info "Migrating Mullvad token..."
    cp "$legacy_dir/mullvad_token" "$VELUM_TOKENS_DIR/mullvad_token"
    chmod 600 "$VELUM_TOKENS_DIR/mullvad_token"
    migrated=true
  fi

  if [[ -f "$legacy_dir/mullvad_account" && ! -f "$VELUM_TOKENS_DIR/mullvad_account" ]]; then
    log_info "Migrating Mullvad account..."
    cp "$legacy_dir/mullvad_account" "$VELUM_TOKENS_DIR/mullvad_account"
    chmod 600 "$VELUM_TOKENS_DIR/mullvad_account"
    migrated=true
  fi

  # Fix ownership if running as root via sudo
  if [[ "$migrated" == "true" && -n "${SUDO_USER:-}" ]]; then
    local sudo_uid sudo_gid
    sudo_uid=$(id -u "$SUDO_USER" 2>/dev/null)
    sudo_gid=$(id -g "$SUDO_USER" 2>/dev/null)
    if [[ -n "$sudo_uid" && -n "$sudo_gid" ]]; then
      chown -R "$sudo_uid:$sudo_gid" "$VELUM_CONFIG_DIR"
    fi
  fi

  if [[ "$migrated" == "true" ]]; then
    print_ok "Configuration migrated to $VELUM_CONFIG_DIR"
    print_info "Legacy files in $legacy_dir can be removed."
  fi
}

# ============================================================================
# COLOR DEFINITIONS
# ============================================================================

# Initialize colors if terminal supports them
_init_colors() {
  if [[ -t 1 ]]; then
    local ncolors
    ncolors=$(tput colors 2>/dev/null || echo 0)
    if [[ -n "$ncolors" && "$ncolors" -ge 8 ]]; then
      C_RED=$(tput setaf 1)
      C_GREEN=$(tput setaf 2)
      C_YELLOW=$(tput setaf 3)
      C_BLUE=$(tput setaf 4)
      C_MAGENTA=$(tput setaf 5)
      C_CYAN=$(tput setaf 6)
      C_WHITE=$(tput setaf 7)
      C_BOLD=$(tput bold)
      C_DIM=$(tput dim)
      C_RESET=$(tput sgr0)
    fi
  fi

  # Set empty values if colors not initialized
  : "${C_RED:=}"
  : "${C_GREEN:=}"
  : "${C_YELLOW:=}"
  : "${C_BLUE:=}"
  : "${C_MAGENTA:=}"
  : "${C_CYAN:=}"
  : "${C_WHITE:=}"
  : "${C_BOLD:=}"
  : "${C_DIM:=}"
  : "${C_RESET:=}"

  export C_RED C_GREEN C_YELLOW C_BLUE C_MAGENTA C_CYAN C_WHITE
  export C_BOLD C_DIM C_RESET
}

_init_colors

# ============================================================================
# LOGGING
# ============================================================================

# Log levels: DEBUG=0, INFO=1, WARN=2, ERROR=3
: "${VELUM_LOG_LEVEL:=1}"

# Internal log function
_log() {
  local level="$1"
  local level_num="$2"
  local color="$3"
  local message="$4"

  [[ "$level_num" -lt "$VELUM_LOG_LEVEL" ]] && return 0

  local timestamp
  timestamp=$(date '+%H:%M:%S')

  if [[ -n "$color" ]]; then
    echo -e "${C_DIM}[${timestamp}]${C_RESET} ${color}${level}${C_RESET} ${message}" >&2
  else
    echo "[$timestamp] $level $message" >&2
  fi
}

log_debug() { _log "DEBUG" 0 "$C_DIM" "$*"; }
log_info()  { _log "INFO" 1 "$C_BLUE" "$*"; }
log_warn()  { _log "WARN" 2 "$C_YELLOW" "$*"; }
log_error() { _log "ERROR" 3 "$C_RED" "$*"; }

# ============================================================================
# USER INTERACTION
# ============================================================================

# Print section header
print_section() {
  local title="$1"
  echo
  echo "${C_BOLD}${C_CYAN}== $title ==${C_RESET}"
  echo
}

# Print info message (not a log, direct to user)
print_info() {
  echo "${C_BLUE}$*${C_RESET}"
}

# Print success message
print_ok() {
  echo "${C_GREEN}$*${C_RESET}"
}

# Print warning message
print_warn() {
  echo "${C_YELLOW}$*${C_RESET}"
}

# Print error message
print_error() {
  echo "${C_RED}$*${C_RESET}" >&2
}

# Print a boxed message
print_box() {
  local message="$1"
  local width=${#message}
  local border
  border=$(printf '%.0s-' $(seq 1 $((width + 4))))

  echo "+${border}+"
  echo "|  ${message}  |"
  echo "+${border}+"
}

# ============================================================================
# USER INPUT
# ============================================================================

# Ask yes/no question with default
# Usage: ask_yn "Enable kill switch?" "y" && echo "Enabled"
ask_yn() {
  local prompt="$1"
  local default="${2:-y}"
  local yn_hint
  local response

  if [[ "${default,,}" == "y" ]]; then
    yn_hint="[Y/n]"
  else
    yn_hint="[y/N]"
  fi

  if ! read -r -p "${prompt} ${yn_hint}: " response; then
    echo -e "\n\nCancelled." >&2
    exit 130
  fi
  response="${response:-$default}"

  [[ "${response,,}" == "y" || "${response,,}" == "yes" ]]
}

# Ask for input with default
# Usage: value=$(ask_input "Enter username" "default_user")
ask_input() {
  local prompt="$1"
  local default="${2:-}"
  local response

  if [[ -n "$default" ]]; then
    if ! read -r -p "${prompt} [${default}]: " response; then
      echo -e "\n\nCancelled." >&2
      exit 130
    fi
    response="${response:-$default}"
  else
    if ! read -r -p "${prompt}: " response; then
      echo -e "\n\nCancelled." >&2
      exit 130
    fi
  fi

  echo "$response"
}

# Ask for password (hidden input)
# Usage: password=$(ask_password "Enter password")
ask_password() {
  local prompt="$1"
  local password

  if ! read -r -s -p "${prompt}: " password; then
    echo -e "\n\nCancelled." >&2
    exit 130
  fi
  echo >&2  # Newline after hidden input
  echo "$password"
}

# Ask for selection from list
# Usage: choice=$(ask_choice "Select option" "Option A" "Option B" "Option C")
ask_choice() {
  local prompt="$1"
  shift
  local options=("$@")
  local i

  echo "$prompt"
  for i in "${!options[@]}"; do
    echo "  $((i + 1)). ${options[$i]}"
  done

  local choice
  while true; do
    if ! read -r -p "Enter number [1-${#options[@]}]: " choice; then
      echo -e "\n\nCancelled." >&2
      exit 130
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#options[@]}" ]]; then
      echo "${options[$((choice - 1))]}"
      return 0
    fi
    echo "Invalid choice. Please enter a number between 1 and ${#options[@]}."
  done
}

# ============================================================================
# UTILITIES
# ============================================================================

# Check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Require a command or exit
require_cmd() {
  local cmd="$1"
  local pkg="${2:-$cmd}"

  if ! command_exists "$cmd"; then
    print_error "$cmd could not be found"
    print_error "Please install $pkg"
    exit 1
  fi
}

# Check if running as root
is_root() {
  [[ "$(id -u)" -eq 0 ]]
}

# Require root or exit
require_root() {
  if ! is_root; then
    print_error "This operation requires root privileges."
    print_error "Please run with sudo."
    exit 1
  fi
}

# Get real home directory (works with sudo)
get_home() {
  if [[ -n "${SUDO_USER:-}" ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
      dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}'
    else
      getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6
    fi
  else
    echo "$HOME"
  fi
}

# Get real username (works with sudo)
get_user() {
  echo "${SUDO_USER:-$USER}"
}

# ============================================================================
# PROCESS CONTROL
# ============================================================================

# Trap handler for cleanup
_cleanup_handlers=()

# Register a cleanup handler
register_cleanup() {
  _cleanup_handlers+=("$1")
}

# Run all cleanup handlers
_run_cleanup() {
  local handler
  # Check if array has elements before iterating (avoids unbound variable with set -u)
  if [[ ${#_cleanup_handlers[@]} -gt 0 ]]; then
    for handler in "${_cleanup_handlers[@]}"; do
      "$handler" 2>/dev/null || true
    done
  fi
}

# Handle cleanup on exit
trap _run_cleanup EXIT

# Handle Ctrl+C and termination - cleanup then exit
trap 'echo -e "\n\nCancelled."; _run_cleanup; exit 130' INT
trap '_run_cleanup; exit 143' TERM

# ============================================================================
# VERSION INFO
# ============================================================================

VELUM_VERSION="0.1.0-dev"
export VELUM_VERSION

print_version() {
  echo "velum-vpn version $VELUM_VERSION"
}
