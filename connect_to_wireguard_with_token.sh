#!/usr/bin/env bash
# Copyright (C) 2020 Private Internet Access, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# SECURITY: Dead-man switch - refuse to run if insecure curl flags detected
if grep -qE 'curl[^|]*(-k|--insecure)' "$0"; then
  echo "SECURITY VIOLATION: Insecure curl flag detected in script. Refusing to run."
  exit 1
fi

# This function allows you to check if the required tools have been installed.
check_tool() {
  cmd=$1
  pkg=$2
  if ! command -v "$cmd" >/dev/null; then
    echo "$cmd could not be found"
    echo "Please install $pkg"
    exit 1
  fi
}

# Now we call the function to make sure we can use wg-quick, curl and jq.
check_tool wg-quick wireguard-tools
check_tool curl curl
check_tool jq jq

# Check if terminal allows output, if yes, define colors for output
if [[ -t 1 ]]; then
  ncolors=$(tput colors)
  if [[ -n $ncolors && $ncolors -ge 8 ]]; then
    red=$(tput setaf 1) # ANSI red
    green=$(tput setaf 2) # ANSI green
    nc=$(tput sgr0) # No Color
  else
    red=''
    green=''
    nc='' # No Color
  fi
fi

: "${PIA_CONNECT=true}"

DEFAULT_PIA_CONF_PATH=/etc/wireguard/pia.conf
: "${PIA_CONF_PATH:=$DEFAULT_PIA_CONF_PATH}"

# PIA currently does not support IPv6. In order to be sure your VPN
# connection does not leak, it is best to disabled IPv6 altogether.
# IPv6 can also be disabled via kernel commandline param, so we must
# first check if this is the case.
if [[ "$(uname)" == "Darwin" ]]; then
  # macOS: check if any interface has IPv6 enabled
  if networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | while read -r svc; do
    networksetup -getinfo "$svc" 2>/dev/null | grep -q "IPv6: Automatic" && exit 0
  done; then
    echo -e "${red}You should consider disabling IPv6 by running:"
    echo "networksetup -setv6off \"Wi-Fi\""
    echo -e "networksetup -setv6off \"Ethernet\"${nc}"
  fi
elif [[ -f /proc/net/if_inet6 ]] &&
  [[ $(sysctl -n net.ipv6.conf.all.disable_ipv6) -ne 1 ||
     $(sysctl -n net.ipv6.conf.default.disable_ipv6) -ne 1 ]]
then
  echo -e "${red}You should consider disabling IPv6 by running:"
  echo "sysctl -w net.ipv6.conf.all.disable_ipv6=1"
  echo -e "sysctl -w net.ipv6.conf.default.disable_ipv6=1${nc}"
fi

# SECURITY: Warn about token expiry
# Token file format: line 1 = token, line 2 = expiry timestamp
token_file="/opt/piavpn-manual/token"
if [[ -f "$token_file" ]]; then
  token_expiry=$(sed -n '2p' "$token_file" 2>/dev/null)
  if [[ -n "$token_expiry" ]]; then
    # Parse expiry date and compare to now
    if [[ "$(uname)" == "Darwin" ]]; then
      expiry_epoch=$(date -jf "%a %b %d %T %Z %Y" "$token_expiry" "+%s" 2>/dev/null || echo 0)
    else
      expiry_epoch=$(date -d "$token_expiry" "+%s" 2>/dev/null || echo 0)
    fi
    now_epoch=$(date "+%s")
    if [[ "$expiry_epoch" -gt 0 && "$now_epoch" -gt "$expiry_epoch" ]]; then
      echo -e "${red}WARNING: Authentication token has expired!${nc}"
      echo -e "${red}Token expired: $token_expiry${nc}"
      echo -e "${red}Please re-run ./run_setup.sh to get a new token.${nc}"
      exit 1
    elif [[ "$expiry_epoch" -gt 0 ]]; then
      hours_left=$(( (expiry_epoch - now_epoch) / 3600 ))
      if [[ "$hours_left" -lt 2 ]]; then
        echo -e "${red}WARNING: Token expires in less than 2 hours!${nc}"
        echo "Consider running ./run_setup.sh soon to refresh."
        echo
      fi
    fi
  fi
fi

# Check if the mandatory environment variables are set.
if [[ -z $WG_SERVER_IP ||
      -z $WG_HOSTNAME ||
      -z $PIA_TOKEN ]]; then
  echo -e "${red}This script requires 3 env vars:"
  echo "WG_SERVER_IP - IP that you want to connect to"
  echo "WG_HOSTNAME  - name of the server, required for ssl"
  echo "PIA_TOKEN    - your authentication token"
  echo
  echo "You can also specify optional env vars:"
  echo "PIA_PF                - enable port forwarding"
  echo "PAYLOAD_AND_SIGNATURE - In case you already have a port."
  echo
  echo "An easy solution is to just run get_region_and_token.sh"
  echo "as it will guide you through getting the best server and"
  echo "also a token. Detailed information can be found here:"
  echo -e "https://github.com/pia-foss/manual-connections${nc}"
  exit 1
fi

# Create ephemeral WireGuard keys for this session.
# SECURITY NOTE: Private key is generated fresh each time run_setup.sh is called.
# The key is saved to /etc/wireguard/pia.conf (mode 600, directory mode 700).
# This allows reconnection via 'wg-quick up pia' without full re-authentication.
# For maximum security, re-run ./run_setup.sh periodically to rotate keys.
privKey=$(wg genkey)
export privKey
pubKey=$( echo "$privKey" | wg pubkey)
export pubKey

# Authenticate via the PIA WireGuard RESTful API.
# This will return a JSON with data required for authentication.
# The certificate is required to verify the identity of the VPN server.
# In case you didn't clone the entire repo, get the certificate from:
# https://github.com/pia-foss/manual-connections/blob/master/ca.rsa.4096.crt
# In case you want to troubleshoot the script, replace -s with -v.
echo "Trying to connect to the PIA WireGuard API on $WG_SERVER_IP..."
if [[ -z $DIP_TOKEN ]]; then
  wireguard_json="$(curl -s --tlsv1.2 -G \
    --connect-to "$WG_HOSTNAME::$WG_SERVER_IP:" \
    --cacert "ca.rsa.4096.crt" \
    --data-urlencode "pt=${PIA_TOKEN}" \
    --data-urlencode "pubkey=$pubKey" \
    "https://${WG_HOSTNAME}:1337/addKey" )"
else
  wireguard_json="$(curl -s --tlsv1.2 -G \
    --connect-to "$WG_HOSTNAME::$WG_SERVER_IP:" \
    --cacert "ca.rsa.4096.crt" \
    --user "dedicated_ip_$DIP_TOKEN:$WG_SERVER_IP" \
    --data-urlencode "pubkey=$pubKey" \
    "https://$WG_HOSTNAME:1337/addKey" )"
fi
export wireguard_json

# Check if the API returned OK and stop this script if it didn't.
if [[ $(echo "$wireguard_json" | jq -r '.status') != "OK" ]]; then
  >&2 echo -e "${red}Server did not return OK. Stopping now.${nc}"
  exit 1
fi

# SECURITY: Validate API response has all required fields
peer_ip=$(echo "$wireguard_json" | jq -r '.peer_ip // empty')
server_key=$(echo "$wireguard_json" | jq -r '.server_key // empty')
server_port=$(echo "$wireguard_json" | jq -r '.server_port // empty')
dns_server=$(echo "$wireguard_json" | jq -r '.dns_servers[0] // empty')

if [[ -z "$peer_ip" || -z "$server_key" || -z "$server_port" ]]; then
  >&2 echo -e "${red}API response missing required fields (peer_ip, server_key, or server_port).${nc}"
  exit 1
fi

# Validate IP address format (basic check)
if ! [[ "$peer_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
  >&2 echo -e "${red}Invalid peer_ip format: $peer_ip${nc}"
  exit 1
fi

# Validate server port is numeric and in valid range
if ! [[ "$server_port" =~ ^[0-9]+$ ]] || [[ "$server_port" -lt 1 || "$server_port" -gt 65535 ]]; then
  >&2 echo -e "${red}Invalid server_port: $server_port${nc}"
  exit 1
fi

# Validate WireGuard public key format (base64, 44 chars with = padding)
if ! [[ "$server_key" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
  >&2 echo -e "${red}Invalid server_key format${nc}"
  exit 1
fi

if [[ $PIA_CONNECT == "true" ]]; then
  # Ensure config file path is set to default used for WG connection
  PIA_CONF_PATH=$DEFAULT_PIA_CONF_PATH
  # Multi-hop is out of the scope of this repo, but you should be able to
  # get multi-hop running with both WireGuard and OpenVPN by playing with
  # these scripts. Feel free to fork the project and test it out.
  echo
  echo "Trying to disable a PIA WG connection in case it exists..."
  wg-quick down pia && echo -e "${green}\nPIA WG connection disabled!${nc}"
  echo
fi

# Create the WireGuard config based on the JSON received from the API
# In case you want this section to also add the DNS setting, please
# start the script with PIA_DNS=true.
# This uses a PersistentKeepalive of 25 seconds to keep the NAT active
# on firewalls. You can remove that line if your network does not
# require it.
if [[ $PIA_DNS == "true" ]]; then
  dnsServer=$(echo "$wireguard_json" | jq -r '.dns_servers[0]')
  if [[ "$(uname)" == "Darwin" ]]; then
    echo "Trying to set up DNS to $dnsServer using macOS networksetup."
  else
    echo "Trying to set up DNS to $dnsServer. In case you do not have resolvconf,"
    echo "this operation will fail and you will not get a VPN. If you have issues,"
    echo "start this script without PIA_DNS."
  fi
  echo
  dnsSettingForVPN="DNS = $dnsServer"
fi
echo -n "Trying to write ${PIA_CONF_PATH}..."
mkdir -p "$(dirname "$PIA_CONF_PATH")"
chmod 700 "$(dirname "$PIA_CONF_PATH")"
# Create config file with restrictive permissions (private key inside)
umask 077

# Get the script directory for kill switch path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Build PostUp commands
postUpCmds=""
# DNS route fix (macOS only)
if [[ "$(uname)" == "Darwin" && -n "$dnsServer" ]]; then
  postUpCmds="PostUp = route -q -n add -host $dnsServer -interface %i 2>/dev/null || true"
fi
# Kill switch enable (macOS only)
if [[ "$(uname)" == "Darwin" && "$PIA_KILLSWITCH" == "true" ]]; then
  ks_vpn_port=$(echo "$wireguard_json" | jq -r '.server_port')
  ks_cmd="$SCRIPT_DIR/pia-killswitch.sh enable --vpn-ip $WG_SERVER_IP --vpn-port $ks_vpn_port --vpn-iface %i --lan-policy ${PIA_KILLSWITCH_LAN:-detect}"
  if [[ -n "$postUpCmds" ]]; then
    postUpCmds="$postUpCmds
PostUp = $ks_cmd"
  else
    postUpCmds="PostUp = $ks_cmd"
  fi
fi

# Build PostDown commands
postDownCmds=""
# Kill switch disable + notification (macOS only)
if [[ "$(uname)" == "Darwin" && "$PIA_KILLSWITCH" == "true" ]]; then
  # Disable kill switch and notify user
  postDownCmds="PostDown = $SCRIPT_DIR/pia-killswitch.sh disable
PostDown = $SCRIPT_DIR/pia-killswitch.sh notify"
fi

echo "
[Interface]
Address = $(echo "$wireguard_json" | jq -r '.peer_ip')
PrivateKey = $privKey
$dnsSettingForVPN
$postUpCmds
$postDownCmds
[Peer]
PersistentKeepalive = 25
PublicKey = $(echo "$wireguard_json" | jq -r '.server_key')
AllowedIPs = 0.0.0.0/0
Endpoint = ${WG_SERVER_IP}:$(echo "$wireguard_json" | jq -r '.server_port')
" > ${PIA_CONF_PATH} || exit 1
chmod 600 ${PIA_CONF_PATH}

# SECURITY: Clear sensitive data from memory (private key is now in config file)
unset privKey wireguard_json

echo -e "${green}OK!${nc}"


if [[ $PIA_CONNECT == "true" ]]; then
  # Start the WireGuard interface.
  # If something failed, stop this script.
  # If you get DNS errors because you miss some packages,
  # just hardcode /etc/resolv.conf to "nameserver 10.0.0.242".
  echo
  echo "Trying to create the wireguard interface..."
  wg-quick up pia || exit 1

  # Fix DNS routing conflict: PIA's DNS (10.0.0.243) may be in the same
  # subnet as the user's local network, causing DNS to route locally
  # instead of through the VPN tunnel. Add explicit route through tunnel.
  if [[ "$(uname)" == "Darwin" ]]; then
    # Find the WireGuard interface (utunX on macOS)
    wg_iface=$(netstat -rn | grep "^0/1" | awk '{print $NF}' | head -1)
    if [[ -n "$wg_iface" && -n "$dnsServer" ]]; then
      echo "Adding route for PIA DNS ($dnsServer) through $wg_iface..."
      route -q -n add -host "$dnsServer" -interface "$wg_iface" 2>/dev/null || true
    fi
  fi

  echo
  echo -e "${green}The WireGuard interface got created.${nc}

  At this point, internet should work via VPN.

  To disconnect the VPN, run:

  --> ${green}wg-quick down pia${nc} <--
  "

  # This section will stop the script if PIA_PF is not set to "true".
  if [[ $PIA_PF != "true" ]]; then
    echo "If you want to also enable port forwarding, you can start the script:"
    echo -e "$ ${green}PIA_TOKEN=<token>" \
      "PF_GATEWAY=$WG_SERVER_IP" \
      "PF_HOSTNAME=$WG_HOSTNAME" \
      "./port_forwarding.sh${nc}"
    echo
    echo "The location used must be port forwarding enabled, or this will fail."
    echo "Calling the ./get_region script with PIA_PF=true will provide a filtered list."
    exit 1
  fi

  echo -ne "This script got started with ${green}PIA_PF=true${nc}.

  Starting port forwarding in "
  for i in {5..1}; do
    echo -n "$i..."
    sleep 1
  done
  echo
  echo

  # Use WG_SERVER_IP for port forwarding - we bind to VPN interface to bypass the route table
  PF_GW="$WG_SERVER_IP"

  echo -e "Starting procedure to enable port forwarding by running the following command:
  $ ${green}PIA_TOKEN=<token> \\
    PF_GATEWAY=$PF_GW \\
    PF_HOSTNAME=$WG_HOSTNAME \\
    ./port_forwarding.sh${nc}"

  PIA_TOKEN=$PIA_TOKEN \
    PF_GATEWAY=$PF_GW \
    PF_HOSTNAME=$WG_HOSTNAME \
    WG_SERVER_IP=$WG_SERVER_IP \
    ./port_forwarding.sh
fi
