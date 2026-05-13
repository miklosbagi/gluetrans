#!/bin/bash

echo 'GlueTrans starting...'
sleep 5

# GlueTrans: A Gluetun + Transmission + VPN peer port updater
# Please take a look at https://github.com/miklosbagi/gluetrans for more information.
# Further recommended reading:
# - GlueTun: https://github.com/qdm12/gluetun-wiki
# - PIA VPN: https://github.com/qdm12/gluetun-wiki/blob/main/setup/providers/private-internet-access.md
# - ProtonVPN: https://github.com/qdm12/gluetun-wiki/blob/main/setup/providers/protonvpn.md
# - Control server: https://github.com/qdm12/gluetun-wiki/blob/main/setup/advanced/control-server.md
# - Port forwarding: https://github.com/qdm12/gluetun-wiki/blob/main/setup/options/port-forwarding.md

# Mandatory env vars, please set these:
# GLUETUN_CONTROL_ENDPOINT
# GLUETUN_HEALTH_ENDPOINT
# TRANSMISSION_ENDPOINT
# Plus either inline or *_FILE (see below):
#   GLUETUN_CONTROL_API_KEY  OR  GLUETUN_CONTROL_API_KEY_FILE
#   TRANSMISSION_USER        OR  TRANSMISSION_USER_FILE
#   TRANSMISSION_PASS        OR  TRANSMISSION_PASS_FILE
#
# Optional security/debugging env vars:
# DEBUG: Set to 1 to keep sensitive env vars visible for debugging (default: 0)
# SANITIZE_LOGS: Set to 1 to omit sensitive information from logs (default: 0)
#
# Secrets and `docker exec … env` (issue #88): many runtimes inject **create-time**
# container env into `exec` sessions, so values passed as `-e GLUETUN_CONTROL_API_KEY=…`
# can still appear there even after `unset` in PID 1. To avoid **secret values** in
# `exec env`, pass only the path variables below (no inline secrets in compose):
#   GLUETUN_CONTROL_API_KEY_FILE, TRANSMISSION_USER_FILE, TRANSMISSION_PASS_FILE
#
# Optional timeouts (issue #89): avoid long blocks when Gluetun/Transmission are slow
# CURL_API_TIMEOUT: max seconds for curl to Gluetun API and country endpoints (default: 10)
# RPC_TIMEOUT: max seconds for transmission-remote RPC calls (default: 15)
GLUETUN_PICK_NEW_SERVER_AFTER=${GLUETUN_PICK_NEW_SERVER_AFTER:-10}
PEERPORT_CHECK_INTERVAL=${PEERPORT_CHECK_INTERVAL:-15}
STANDARD_WAIT_TIME=${STANDARD_WAIT_TIME:-5}
# Timeouts for external calls to avoid long blocks (issue #89)
CURL_API_TIMEOUT=${CURL_API_TIMEOUT:-10}
RPC_TIMEOUT=${RPC_TIMEOUT:-15}

FORCED_COUNTRY_JUMP=${FORCED_COUNTRY_JUMP:-0}
FORCE_JUMP_INTERVAL=$((FORCED_COUNTRY_JUMP * 60))

# For secure run
SANITIZE_LOGS=${SANITIZE_LOGS:-0}
DEBUG=${DEBUG:-0}

# Country detection
COUNTRY_DETECT_ENDPOINTS="http://ipinfo.io,http://ifconfig.co/json"

# constants
tag="gt"
country_jump_timer=0
gluetun_port_fail_count=0
transmission_port_fail_count=0

required_vars=(
    GLUETUN_CONTROL_ENDPOINT
    TRANSMISSION_ENDPOINT
    GLUETUN_HEALTH_ENDPOINT
)

# general logging to stdout (docker friendly)
log () {
    stamp=$(date +"%b %d %H:%M:%S")
    # handle log sanitization
    if [[ "$SANITIZE_LOGS" -ne 0 ]] && [[ "$2" != "" ]]; then
        echo "$stamp [$tag] $1" | sed -E "$2" >> /proc/1/fd/1
    else
        echo "$stamp [$tag] $1" >> /proc/1/fd/1
    fi
}

# get current connection country
get_connection_country() {
    IFS=',' read -ra endpoints <<< "${COUNTRY_DETECT_ENDPOINTS}"
    retries=3
    for endpoint in "${endpoints[@]}"; do
        for ((i=0; i<retries; i++)); do
            country=$(curl -s -m "$CURL_API_TIMEOUT" "$endpoint" | jq -r '.timezone' 2>&1) || country=$(curl -s -m "$CURL_API_TIMEOUT" "$endpoint" | jq -r '.time_zone' 2>&1)
            if [[ $country != *"parse error"* ]]; then
                echo "$country"
                return 0
            fi
            log "Error occurred while fetching the country from $endpoint, attempt $((i + 1)) of $retries"
            sleep 1
        done
    done
    log "Unable to retrieve country information from any of the endpoints."
    echo "unknown"
}

# hash sensitive info
hash_sensitive_info() {
    echo "${RANDOM}${1}${RANDOM}" | sha256sum | awk '{print $1}'
}

# wait for gluetun to become healthy
wait_for_gluetun() {
    until curl -s -m "$STANDARD_WAIT_TIME" -o /dev/null -w "%{http_code}" "$GLUETUN_HEALTH_ENDPOINT" | grep -q 200; do
        log "waiting for gluetun to establish connection..."
        sleep "$STANDARD_WAIT_TIME"
    done
    country_details=$(get_connection_country)
    hashed_country_details=$(hash_sensitive_info "$country_details")
    log "gluetun is active, country details: $country_details", "s#$country_details#$hashed_country_details#"
}

# get transmission peer port
get_transmission_port() {
    transmission_response=$(timeout "$RPC_TIMEOUT" transmission-remote "$TRANSMISSION_ENDPOINT" -n "$_transmission_user":"$_transmission_pass" -si | grep Listenport | awk -F' ' '{print $2}')
    if [ "$transmission_response" == "" ]; then
        log "tramsmission returned '$transmission_response', waiting for $gluetun_port to be picked up, retrying ($transmission_port_fail_count / $GLUETUN_PICK_NEW_SERVER_AFTER)...", "s#$gluetun_port#* OMITTED *#g"
        return 1
    else
        echo "$transmission_response"
    fi
}

# get peer port from vpn via gluetun control server
get_gluetun_port() {
    # Try new API endpoint first (v3.41.0+)
    gluetun_response=$(curl -s -m "$CURL_API_TIMEOUT" -H "X-API-Key: $_gluetun_api_key" "$GLUETUN_CONTROL_ENDPOINT/v1/portforward")

    # Check if new endpoint failed - fallback to old API for backward compatibility
    # Conditions: contains "not found", "Unauthorized", or doesn't have valid .port field
    if echo "$gluetun_response" | grep -iq "not found\|unauthorized" || ! echo "$gluetun_response" | jq -e '.port' >/dev/null 2>&1; then
        # Fallback to old API endpoint (v3.40.0 and older)
        gluetun_response=$(curl -s -m "$CURL_API_TIMEOUT" -H "X-API-Key: $_gluetun_api_key" "$GLUETUN_CONTROL_ENDPOINT/v1/openvpn/portforwarded")
    fi
    
    if [ "$gluetun_response" == "" ] || [ "$gluetun_response" == '{"port":0}' ]; then
        log "gluetun returned $gluetun_response, retrying ($gluetun_port_fail_count / $GLUETUN_PICK_NEW_SERVER_AFTER)..."
        return 1
    else
        echo "$gluetun_response" | jq -r '.port'
    fi
}

# get transmission peer port from rpc endpoint
update_transmission_port() {
    transmission_response=$(timeout "$RPC_TIMEOUT" transmission-remote "$TRANSMISSION_ENDPOINT" -n "$_transmission_user":"$_transmission_pass" -p "$1") || return 1
}

# check if transmission port is open
check_transmission_port_open() {
    transmission_response=$(timeout "$RPC_TIMEOUT" transmission-remote "$TRANSMISSION_ENDPOINT" -n "$_transmission_user":"$_transmission_pass" -pt) || return 1
    echo "$transmission_response"
}

# pick a new gluetun server
pick_new_gluetun_server() {
    log "asking gluetun to disconnect from $country_details", "s#$country_details#* OMITTED *#"
    
    # Try new API endpoint first (v3.41.0+)
    gluetun_server_response=$(curl -s -m "$CURL_API_TIMEOUT" -H "X-API-Key: $_gluetun_api_key" -X PUT -d '{"status":"stopped"}' "$GLUETUN_CONTROL_ENDPOINT/v1/vpn/status") || log "error instructing gluetun to pick new server ($gluetun_server_response)."

    # Check if new endpoint failed - fallback to old API for backward compatibility
    if echo "$gluetun_server_response" | grep -iq "not found\|unauthorized" || ! echo "$gluetun_server_response" | grep -qE '\{"outcome":"(stopping|stopped)"\}'; then
        # Fallback to old API endpoint (v3.40.0 and older)
        gluetun_server_response=$(curl -s -m "$CURL_API_TIMEOUT" -H "X-API-Key: $_gluetun_api_key" -X PUT -d '{"status":"stopped"}' "$GLUETUN_CONTROL_ENDPOINT/v1/openvpn/status") || log "error instructing gluetun to pick new server ($gluetun_server_response)."
        
        if ! echo "$gluetun_server_response" | grep -qE '\{"outcome":"(stopping|stopped)"\}'; then
            log "bleh, gluetun server response is weird, expected one of {\"outcome\":\"stopping\"} or {\"outcome\":\"stopped\"}, got $gluetun_server_response"
            return 1
        fi
    fi
    
    # this is fixed as ~ around this time it takes for gluetun to reconnect, this avoids some nag in logs
    sleep 15 
    # just in case this takes longer than expected
    wait_for_gluetun
}

# exit if any required (non-secret) env var is unset
for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        echo "$var is not set. please set the environment variable." >&2
        exit 1
    fi
done

# --- Credentials: load from *_FILE (recommended for issue #88) or inline env ---
if [[ -n "${GLUETUN_CONTROL_API_KEY_FILE:-}" && -n "${GLUETUN_CONTROL_API_KEY:-}" ]]; then
    echo "Set only one of GLUETUN_CONTROL_API_KEY or GLUETUN_CONTROL_API_KEY_FILE" >&2
    exit 1
fi
if [[ -n "${GLUETUN_CONTROL_API_KEY_FILE:-}" ]]; then
    if [[ ! -f "${GLUETUN_CONTROL_API_KEY_FILE}" || ! -r "${GLUETUN_CONTROL_API_KEY_FILE}" ]]; then
        echo "GLUETUN_CONTROL_API_KEY_FILE is not a readable file" >&2
        exit 1
    fi
    _gluetun_api_key=$(tr -d '\r\n' < "${GLUETUN_CONTROL_API_KEY_FILE}")
    unset GLUETUN_CONTROL_API_KEY_FILE
    unset GLUETUN_CONTROL_API_KEY 2>/dev/null || true
elif [[ -n "${GLUETUN_CONTROL_API_KEY:-}" ]]; then
    _gluetun_api_key="$GLUETUN_CONTROL_API_KEY"
    unset GLUETUN_CONTROL_API_KEY
else
    echo "GLUETUN_CONTROL_API_KEY or GLUETUN_CONTROL_API_KEY_FILE must be set" >&2
    exit 1
fi

if [[ -n "${TRANSMISSION_USER_FILE:-}" && -n "${TRANSMISSION_USER:-}" ]]; then
    echo "Set only one of TRANSMISSION_USER or TRANSMISSION_USER_FILE" >&2
    exit 1
fi
if [[ -n "${TRANSMISSION_USER_FILE:-}" ]]; then
    if [[ ! -f "${TRANSMISSION_USER_FILE}" || ! -r "${TRANSMISSION_USER_FILE}" ]]; then
        echo "TRANSMISSION_USER_FILE is not a readable file" >&2
        exit 1
    fi
    _transmission_user=$(tr -d '\r\n' < "${TRANSMISSION_USER_FILE}")
    unset TRANSMISSION_USER_FILE
    unset TRANSMISSION_USER 2>/dev/null || true
elif [[ -n "${TRANSMISSION_USER:-}" ]]; then
    _transmission_user="$TRANSMISSION_USER"
    unset TRANSMISSION_USER
else
    echo "TRANSMISSION_USER or TRANSMISSION_USER_FILE must be set" >&2
    exit 1
fi

if [[ -n "${TRANSMISSION_PASS_FILE:-}" && -n "${TRANSMISSION_PASS:-}" ]]; then
    echo "Set only one of TRANSMISSION_PASS or TRANSMISSION_PASS_FILE" >&2
    exit 1
fi
if [[ -n "${TRANSMISSION_PASS_FILE:-}" ]]; then
    if [[ ! -f "${TRANSMISSION_PASS_FILE}" || ! -r "${TRANSMISSION_PASS_FILE}" ]]; then
        echo "TRANSMISSION_PASS_FILE is not a readable file" >&2
        exit 1
    fi
    _transmission_pass=$(tr -d '\r\n' < "${TRANSMISSION_PASS_FILE}")
    unset TRANSMISSION_PASS_FILE
    unset TRANSMISSION_PASS 2>/dev/null || true
elif [[ -n "${TRANSMISSION_PASS:-}" ]]; then
    _transmission_pass="$TRANSMISSION_PASS"
    unset TRANSMISSION_PASS
else
    echo "TRANSMISSION_PASS or TRANSMISSION_PASS_FILE must be set" >&2
    exit 1
fi

# Unset / re-export for DEBUG; keep secrets in _vars unless DEBUG=1
if [[ "$DEBUG" == "1" ]]; then
    export GLUETUN_CONTROL_API_KEY="$_gluetun_api_key"
    export TRANSMISSION_USER="$_transmission_user"
    export TRANSMISSION_PASS="$_transmission_pass"
    log "debug: DEBUG=1, sensitive environment variables re-exported for visibility"
else
    log "security: sensitive environment variables removed from environment (stored in memory only)"
    if [[ -z "${GLUETUN_CONTROL_API_KEY:-}" && -z "${TRANSMISSION_USER:-}" && -z "${TRANSMISSION_PASS:-}" ]]; then
        log "security: verified - sensitive vars are not accessible in main process environment"
    else
        log "warning: unset may not have worked as expected"
    fi
fi

# wait for gluetun to wake up
wait_for_gluetun
log "monitoring..."

# main loop
while true; do
    sleep "$PEERPORT_CHECK_INTERVAL"
    
    # get gluetun port, and handle too many failures
    gluetun_port=$(get_gluetun_port) && gluetun_port_fail_count=0

    # get gluetun port, and handle too many failures
    if [ -z "$gluetun_port" ]; then 
        if [ "$gluetun_port_fail_count" == "$GLUETUN_PICK_NEW_SERVER_AFTER" ]; then
            log "gluetun port check failed $GLUETUN_PICK_NEW_SERVER_AFTER times, instructing gluetun to pick a new server."
            pick_new_gluetun_server
            gluetun_port_fail_count=0; 
        fi
        gluetun_port_fail_count=$((gluetun_port_fail_count + 1)); 
        continue; 
    fi

    # get transmission port
    transmission_port=$(get_transmission_port) && transmission_port_fail_count=0
    if [ -z "$transmission_port" ]; then 
        if [ "$transmission_port_fail_count" == "$GLUETUN_PICK_NEW_SERVER_AFTER" ]; then
            log "transmission port check failed $GLUETUN_PICK_NEW_SERVER_AFTER times, instructing gluetun to pick a new server."
            pick_new_gluetun_server
            gluetun_port_fail_count=0;
            transmission_port_fail_count=0;
        fi
        transmission_port_fail_count=$((transmission_port_fail_count + 1)); 
        continue; 
    fi

    # check if forced country jump is needed
    if [[ $FORCED_COUNTRY_JUMP -ne 0 ]]; then
        # increment country jump timer
        country_jump_timer=$((country_jump_timer + PEERPORT_CHECK_INTERVAL))
        log "country jump timer: $(( (FORCE_JUMP_INTERVAL - country_jump_timer) / 60 )) minute(s) left on this server."

        if [[ $country_jump_timer -ge $FORCE_JUMP_INTERVAL ]]; then
            log "countryjump: forcing gluetun to pick a new server after $FORCED_COUNTRY_JUMP minute(s)."
            pick_new_gluetun_server
            country_jump_timer=0
            continue;
        fi
    fi

    # check for port change, and instruct transmission to pick enanble new port
    if [ "$gluetun_port" != "$transmission_port" ] || [ "$is_open" != "Port is open: Yes" ]; then
        log "port change detected: gluetun is $gluetun_port, transmission is $transmission_port, $is_open updating..." "s#$gluetun_port, transmission is $transmission_port#* OMITTED *, transmission is * OMITTED *#"
        update_transmission_port "$gluetun_port"

        # wait for transmission port to update
        attempt=0
        while [ "$attempt" -lt 5 ]; do
            sleep "$STANDARD_WAIT_TIME"
            is_open=$(check_transmission_port_open)
            if [ "$is_open" == "Port is open: Yes" ]; then
                break
            fi
            log "waiting for transmission port to update ($attempt/5)..."
            update_transmission_port "$gluetun_port"
            attempt=$((attempt + 1))
        done

        # check if transmission port updated successfully
        new_transmission_port=$(get_transmission_port)
        if [ "$new_transmission_port" != "$gluetun_port" ]; then
            log "error: transmission port update failed."
        else
            log "success: transmission port updated successfully."
            # reset country jump timer
            country_jump_timer=0
        fi

    else
        is_open=$(check_transmission_port_open)
        log "heartbeat: gluetun & transmission ports match ($new_transmission_port), $is_open" "s#\([0-9]+\)#\(* OMITTED *\)#"
    fi
done
