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
  if ! command -v "$cmd" >/dev/null; then
    echo "$cmd could not be found"
    echo "Please install $cmd"
    exit 1
  fi
}

# Now we call the function to make sure we can use curl and jq.
check_tool curl
check_tool jq

# SECURITY: Check token expiry before making API calls
token_file="/opt/piavpn-manual/token"
if [[ -f "$token_file" ]]; then
  token_expiry=$(sed -n '2p' "$token_file" 2>/dev/null)
  if [[ -n "$token_expiry" ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
      expiry_epoch=$(date -jf "%a %b %d %T %Z %Y" "$token_expiry" "+%s" 2>/dev/null || echo 0)
    else
      expiry_epoch=$(date -d "$token_expiry" "+%s" 2>/dev/null || echo 0)
    fi
    now_epoch=$(date "+%s")
    if [[ "$expiry_epoch" -gt 0 && "$now_epoch" -gt "$expiry_epoch" ]]; then
      echo -e "${red}ERROR: Authentication token has expired!${nc}"
      echo "Port forwarding will fail. Please re-run ./run_setup.sh"
      exit 1
    fi
  fi
fi

# Check if the mandatory environment variables are set.
if [[ -z $PF_GATEWAY || -z $PIA_TOKEN || -z $PF_HOSTNAME ]]; then
  echo "This script requires 3 env vars:"
  echo "PF_GATEWAY  - the IP of your gateway"
  echo "PF_HOSTNAME - name of the host used for SSL/TLS certificate verification"
  echo "PIA_TOKEN   - the token you use to connect to the vpn services"
  echo
  echo "An easy solution is to just run get_region_and_token.sh"
  echo "as it will guide you through getting the best server and"
  echo "also a token. Detailed information can be found here:"
  echo "https://github.com/pia-foss/manual-connections"
exit 1
fi

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

# The port forwarding system has required two variables:
# PAYLOAD: contains the token, the port and the expiration date
# SIGNATURE: certifies the payload originates from the PIA network.

# Basically PAYLOAD+SIGNATURE=PORT. You can use the same PORT on all servers.
# The system has been designed to be completely decentralized, so that your
# privacy is protected even if you want to host services on your systems.

# You can get your PAYLOAD+SIGNATURE with a simple curl request to any VPN
# gateway, no matter what protocol you are using. Considering WireGuard has
# already been automated in this repo, here is a command to help you get
# your gateway if you have an active OpenVPN connection:
# $ ip route | head -1 | grep tun | awk '{ print $3 }'
# This section will get updated as soon as we created the OpenVPN script.

# Get the payload and the signature from the PF API. This will grant you
# access to a random port, which you can activate on any server you connect to.
# If you already have a signature, and you would like to re-use that port,
# save the payload_and_signature received from your previous request
# in the env var PAYLOAD_AND_SIGNATURE, and that will be used instead.
if [[ -z $PAYLOAD_AND_SIGNATURE ]]; then
  echo
  # Detect the WireGuard interface name (utunX on macOS)
  if [[ "$(uname)" == "Darwin" ]]; then
    # On macOS, wireguard-go creates utunX interfaces
    wg_interface=$(ifconfig | grep -B1 "inet 10\." | grep "^utun" | head -1 | cut -d: -f1)
    if [[ -z "$wg_interface" ]]; then
      # Fallback: try to find interface from routing table
      wg_interface=$(netstat -rn | grep "^0/1" | awk '{print $NF}' | grep utun | head -1)
    fi
  else
    wg_interface="pia"
  fi

  max_retries=3
  retry_delay=3
  for ((attempt=1; attempt<=max_retries; attempt++)); do
    echo -n "Getting new signature (attempt $attempt/$max_retries)... "

    # Try using VPN interface to reach WG server directly
    if [[ -n "$wg_interface" && -n "$WG_SERVER_IP" ]]; then
      curl_output=$(curl -s --tlsv1.2 -m 10 -w "\nHTTP_CODE:%{http_code}" \
        --interface "$wg_interface" \
        --connect-to "$PF_HOSTNAME::$WG_SERVER_IP:" \
        --cacert "ca.rsa.4096.crt" \
        -G --data-urlencode "token=${PIA_TOKEN}" \
        "https://${PF_HOSTNAME}:19999/getSignature" 2>&1)
    else
      # Fallback to PF_GATEWAY
      curl_output=$(curl -s --tlsv1.2 -m 10 -w "\nHTTP_CODE:%{http_code}" \
        --connect-to "$PF_HOSTNAME::$PF_GATEWAY:" \
        --cacert "ca.rsa.4096.crt" \
        -G --data-urlencode "token=${PIA_TOKEN}" \
        "https://${PF_HOSTNAME}:19999/getSignature" 2>&1)
    fi

    http_code=$(echo "$curl_output" | grep "HTTP_CODE:" | cut -d: -f2)
    payload_and_signature=$(echo "$curl_output" | grep -v "HTTP_CODE:")

    if [[ $(echo "$payload_and_signature" | jq -r '.status' 2>/dev/null) == "OK" ]]; then
      echo -e "${green}OK!${nc}"
      break
    fi

    echo -e "${red}Failed${nc}"
    if [[ $attempt -lt $max_retries ]]; then
      sleep $retry_delay
    fi
  done
else
  payload_and_signature=$PAYLOAD_AND_SIGNATURE
  echo -n "Checking the payload_and_signature from the env var... "
fi
export payload_and_signature

# Check if the payload and the signature are OK.
# If they are not OK, just stop the script.
if [[ $(echo "$payload_and_signature" | jq -r '.status') != "OK" ]]; then
  echo -e "${red}The payload_and_signature variable does not contain an OK status.${nc}"
  echo -e "${red}Response received: $payload_and_signature${nc}"
  echo -e "${red}This may indicate the token has expired, or the server does not support port forwarding.${nc}"
  exit 1
fi

# SECURITY: Validate response has required fields
pf_signature=$(echo "$payload_and_signature" | jq -r '.signature // empty')
pf_payload=$(echo "$payload_and_signature" | jq -r '.payload // empty')

if [[ -z "$pf_signature" || -z "$pf_payload" ]]; then
  echo -e "${red}API response missing signature or payload.${nc}"
  exit 1
fi

# Validate payload is base64 and contains expected fields
if ! echo "$pf_payload" | base64 -d 2>/dev/null | jq -e '.port' >/dev/null 2>&1; then
  echo -e "${red}Invalid payload format - cannot decode or missing port.${nc}"
  exit 1
fi

# Validate port is in valid range
pf_port=$(echo "$pf_payload" | base64 -d | jq -r '.port')
if ! [[ "$pf_port" =~ ^[0-9]+$ ]] || [[ "$pf_port" -lt 1024 || "$pf_port" -gt 65535 ]]; then
  echo -e "${red}Invalid forwarded port: $pf_port (expected 1024-65535)${nc}"
  exit 1
fi

echo -e "${green}OK!${nc}"

# We need to get the signature out of the previous response.
# The signature will allow the us to bind the port on the server.
signature=$(echo "$payload_and_signature" | jq -r '.signature')

# The payload has a base64 format. We need to extract it from the
# previous response and also get the following information out:
# - port: This is the port you got access to
# - expires_at: this is the date+time when the port expires
payload=$(echo "$payload_and_signature" | jq -r '.payload')
port=$(echo "$payload" | base64 -d | jq -r '.port')

# The port normally expires after 2 months. If you consider
# 2 months is not enough for your setup, please open a ticket.
expires_at=$(echo "$payload" | base64 -d | jq -r '.expires_at')

echo -ne "
Signature ${green}$signature${nc}
Payload   ${green}$payload${nc}

--> The port is ${green}$port${nc} and it will expire on ${red}$expires_at${nc}. <--

Trying to bind the port... "

# Now we have all required data to create a request to bind the port.
# We will repeat this request every 15 minutes, in order to keep the port
# alive. The servers have no mechanism to track your activity, so they
# will just delete the port forwarding if you don't send keepalives.
# Use VPN interface to reach the WG server we're connected to
while true; do
  if [[ -n "$wg_interface" && -n "$WG_SERVER_IP" ]]; then
    bind_port_response="$(curl --tlsv1.2 -Gs -m 5 \
      --interface "$wg_interface" \
      --connect-to "$PF_HOSTNAME::$WG_SERVER_IP:" \
      --cacert "ca.rsa.4096.crt" \
      --data-urlencode "payload=${payload}" \
      --data-urlencode "signature=${signature}" \
      "https://${PF_HOSTNAME}:19999/bindPort")"
  else
    bind_port_response="$(curl --tlsv1.2 -Gs -m 5 \
      --connect-to "$PF_HOSTNAME::$PF_GATEWAY:" \
      --cacert "ca.rsa.4096.crt" \
      --data-urlencode "payload=${payload}" \
      --data-urlencode "signature=${signature}" \
      "https://${PF_HOSTNAME}:19999/bindPort")"
  fi
    echo -e "${green}OK!${nc}"

    # If port did not bind, just exit the script.
    # This script will exit in 2 months, since the port will expire.
    export bind_port_response
    if [[ $(echo "$bind_port_response" | jq -r '.status') != "OK" ]]; then
      echo -e "${red}The API did not return OK when trying to bind port... Exiting.${nc}"
      exit 1
    fi
    echo -e Forwarded port'\t'"${green}$port${nc}"
    echo -e Refreshed on'\t'"${green}$(date)${nc}"
    # macOS date doesn't support --date, use -jf for parsing ISO8601 format
    if [[ "$(uname)" == "Darwin" ]]; then
      expires_formatted=$(date -jf "%Y-%m-%dT%H:%M:%S" "${expires_at%%.*}" "+%c" 2>/dev/null || echo "$expires_at")
    else
      expires_formatted=$(date --date="$expires_at" 2>/dev/null || echo "$expires_at")
    fi
    echo -e Expires on'\t'"${red}$expires_formatted${nc}"
    echo -e "\n${green}This script will need to remain active to use port forwarding, and will refresh every 15 minutes.${nc}\n"

    # sleep 15 minutes
    sleep 900
done
