#!/bin/bash

# GlueTransPIA: A Gluetun + Transmission + PIA VPN peer port updater
# Please take a look at https://github.com/miklosbagi/gluetranspia for more information.
# Further recommended reading:
# - GlueTun: https://github.com/qdm12/gluetun-wiki
# - PIA VPN: https://github.com/qdm12/gluetun-wiki/blob/main/setup/providers/private-internet-access.md
# - Control server: https://github.com/qdm12/gluetun-wiki/blob/main/setup/advanced/control-server.md
# - Port forwarding: https://github.com/qdm12/gluetun-wiki/blob/main/setup/options/port-forwarding.md

# Mandatory env vars, please set these:
# GLUETUN_CONTROL_ENDPOINT
# GLUETUN_HEALTH_ENDPOINT
# TRANSMISSION_ENDPOINT
# TRANSMISSION_USER
# TRANSMISSION_PASS

GLUETUN_PICK_NEW_SERVER_AFTER=${GLUETUN_PICK_NEW_SERVER_AFTER:-10}
PEERPORT_CHECK_INTERVAL=${PEERPORT_CHECK_INTERVAL:-15}
STANDARD_WAIT_TIME=${STANDARD_WAIT_TIME:-5}

FORCED_COUNTRY_JUMP=${FORCED_COUNTRY_JUMP:-0}
FORCE_JUMP_INTERVAL=$((FORCED_COUNTRY_JUMP * 60))

# constants
tag="gtpia"
country_jump_timer=0
gluetun_port_fail_count=0
transmission_port_fail_count=0

required_vars=(
    GLUETUN_CONTROL_ENDPOINT
    TRANSMISSION_ENDPOINT
    TRANSMISSION_USER
    TRANSMISSION_PASS
    GLUETUN_HEALTH_ENDPOINT
)

# general logging to stdout (docker friendly)
log () {
    stamp=$(date +"%b %d %H:%M:%S")
    echo "$stamp [$tag] $1" >> /proc/1/fd/1
}

# get current connection country
get_connection_country() {
    country=$(curl -s http://ipinfo.io | jq '.country' 2>&1)
    if [[ $country == *"parse error"* ]]; then
        log "Error occurred while fetching the country: $country"
        echo "unknown"
    else
        echo "$country"
    fi
}

# wait for gluetun to become healthy
wait_for_gluetun() {
    until curl -s -m $STANDARD_WAIT_TIME -o /dev/null -w "%{http_code}" $GLUETUN_HEALTH_ENDPOINT | grep -q 200; do
        log "waiting for gluetun to become active..."
        sleep $STANDARD_WAIT_TIME
    done
    country_details=$(get_connection_country)
    log "gluetun is active, country details: $country_details"
}

# get transmission peer port
get_transmission_port() {
    transmission_response=$(transmission-remote "$TRANSMISSION_ENDPOINT" -n "$TRANSMISSION_USER":"$TRANSMISSION_PASS" -si | grep Listenport | awk -F' ' '{print $2}')
    if [ "$transmission_response" == "" ]; then
        log "tramsmission returned '$transmission_response', retrying ($transmission_port_fail_count / $GLUETUN_PICK_NEW_SERVER_AFTER)..."
        return 1
    else
        echo "$transmission_response"
    fi
}

# get peer port from piavpn via gluetun control server
get_gluetun_port() {
    gluetun_response=$(curl -s "$GLUETUN_CONTROL_ENDPOINT/v1/openvpn/portforwarded")
    if [ "$gluetun_response" == "" ] || [ "$gluetun_response" == '{"port":0}' ]; then
        log "gluetun returned $gluetun_response, retrying ($gluetun_port_fail_count / $GLUETUN_PICK_NEW_SERVER_AFTER)..."
        return 1
    else
        echo "$gluetun_response" | jq -r '.port'
    fi
}

# get transmission peer port from rpc endpoint
update_transmission_port() {
    transmission_response=$(transmission-remote "$TRANSMISSION_ENDPOINT" -n "$TRANSMISSION_USER":"$TRANSMISSION_PASS" -p "$1") || return 1
}

# check if transmission port is open
check_transmission_port_open() {
    transmission_response=$(transmission-remote "$TRANSMISSION_ENDPOINT" -n "$TRANSMISSION_USER":"$TRANSMISSION_PASS" -pt) || return 1
    echo "$transmission_response"
}

# pick a new gluetun server
pick_new_gluetun_server() {
    log "asking gluetun to disconnect from $country_details"
    gluetun_server_response=`curl -s -X PUT -d '{"status":"stopped"}' "$GLUETUN_CONTROL_ENDPOINT/v1/openvpn/status"` || log "error instructing gluetun to pick new server ($gluetun_server_response)."
    if [ "$gluetun_server_response" != '{"outcome":"stopped"}' ]; then
        log "bleh, gluetun server response is weird, expected {\"outcome\":\"stopped\"}, got $gluetun_server_response"
        return 1
    fi    
    # this is fixed as ~ around this time it takes for gluetun to reconnect, this avoids some nag in logs
    sleep 15 
    # just in case this takes longer than expected
    wait_for_gluetun
}

# exit of any env var is unset
for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        echo "$var is not set. please set the environment variable." >&2
        exit 1
    fi
done

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
        log "country jump timer: $(( ($FORCE_JUMP_INTERVAL - $country_jump_timer) / 60 )) minute(s) left on this server."

        if [[ $country_jump_timer -ge $FORCE_JUMP_INTERVAL ]]; then
            log "country-jump: forcing gluetun to pick a new server after $FORCED_COUNTRY_JUMP minutes."
            pick_new_gluetun_server
            country_jump_timer=0
            continue;
        fi
    fi

    # check for port change, and instruct transmission to pick enanble new port
    if [ "$gluetun_port" != "$transmission_port" ] || [ "$is_open" != "Port is open: Yes" ]; then
        log "port change detected: gluetun is $gluetun_port, transmission is $transmission_port, updating..."
        update_transmission_port "$gluetun_port"

        # wait for transmission port to update
        attempt=0
        while [ "$attempt" -lt 5 ]; do
            sleep $STANDARD_WAIT_TIME
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
        log "heartbeat: gluetun & transmission ports match ($new_transmission_port), $is_open"
    fi
done
