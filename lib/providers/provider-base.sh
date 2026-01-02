#!/usr/bin/env bash
# provider-base.sh - Base interface for VPN providers
# All providers must implement these functions

# Prevent multiple sourcing
[[ -n "${_VELUM_PROVIDER_BASE_LOADED:-}" ]] && return 0
readonly _VELUM_PROVIDER_BASE_LOADED=1

# ============================================================================
# PROVIDER INTERFACE
# ============================================================================

# These functions must be implemented by each provider.
# The base implementations here return errors to catch unimplemented functions.

# Provider metadata
provider_name() {
  echo "ERROR: provider_name() not implemented" >&2
  return 1
}

provider_version() {
  echo "1.0.0"
}

# Authentication
provider_auth_type() {
  # Return: "username_password" | "account_number"
  echo "ERROR: provider_auth_type() not implemented" >&2
  return 1
}

provider_authenticate() {
  # Takes credentials, returns token or session
  echo "ERROR: provider_authenticate() not implemented" >&2
  return 1
}

provider_validate_creds() {
  # Validate credential format before auth
  echo "ERROR: provider_validate_creds() not implemented" >&2
  return 1
}

# Server list
provider_get_servers() {
  # Fetch and return server list (normalized JSON)
  echo "ERROR: provider_get_servers() not implemented" >&2
  return 1
}

provider_test_latency() {
  # Test latency to a server
  echo "ERROR: provider_test_latency() not implemented" >&2
  return 1
}

provider_filter_servers() {
  # Filter by criteria (geo, port_forward, etc.)
  echo "ERROR: provider_filter_servers() not implemented" >&2
  return 1
}

# WireGuard connection
provider_wg_exchange() {
  # Exchange WireGuard keys with provider
  echo "ERROR: provider_wg_exchange() not implemented" >&2
  return 1
}

provider_wg_config() {
  # Return WireGuard config parameters
  echo "ERROR: provider_wg_config() not implemented" >&2
  return 1
}

provider_wg_endpoint() {
  # Return server endpoint (IP:port)
  echo "ERROR: provider_wg_endpoint() not implemented" >&2
  return 1
}

# Features (optional)
provider_supports_pf() {
  # Port forwarding supported?
  return 1
}

provider_enable_pf() {
  # Enable port forwarding
  echo "ERROR: provider_enable_pf() not implemented" >&2
  return 1
}

provider_refresh_pf() {
  # Refresh port forwarding (keepalive)
  echo "ERROR: provider_refresh_pf() not implemented" >&2
  return 1
}

provider_supports_dip() {
  # Dedicated IP supported?
  return 1
}

provider_get_dip() {
  # Get dedicated IP info
  echo "ERROR: provider_get_dip() not implemented" >&2
  return 1
}

# Provider-specific
provider_get_dns() {
  # Return provider's DNS servers
  echo "ERROR: provider_get_dns() not implemented" >&2
  return 1
}

provider_get_ca_cert() {
  # Return path to CA certificate
  echo "ERROR: provider_get_ca_cert() not implemented" >&2
  return 1
}

# ============================================================================
# PROVIDER LOADING
# ============================================================================

# Directory containing providers
_PROVIDER_DIR="${BASH_SOURCE%/*}"

# Currently loaded provider
VELUM_PROVIDER=""

# Load a provider module
load_provider() {
  local provider="$1"
  local provider_path="${_PROVIDER_DIR}/${provider}.sh"

  if [[ ! -f "$provider_path" ]]; then
    echo "ERROR: Provider not found: $provider" >&2
    echo "Available providers: $(ls -1 "$_PROVIDER_DIR"/*.sh 2>/dev/null | xargs -I{} basename {} .sh | grep -v provider-base | tr '\n' ' ')" >&2
    return 1
  fi

  # Source the provider
  # shellcheck source=/dev/null
  source "$provider_path"

  VELUM_PROVIDER="$provider"
  export VELUM_PROVIDER
}

# List available providers
list_providers() {
  local providers=()
  local file

  for file in "$_PROVIDER_DIR"/*.sh; do
    [[ "$(basename "$file")" == "provider-base.sh" ]] && continue
    providers+=("$(basename "$file" .sh)")
  done

  printf '%s\n' "${providers[@]}"
}
