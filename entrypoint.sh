#!/bin/bash

# recommended reading
# GlueTun: https://github.com/qdm12/gluetun-wiki
# PIA VPN: https://github.com/qdm12/gluetun-wiki/blob/main/setup/providers/private-internet-access.md
# Control server: https://github.com/qdm12/gluetun-wiki/blob/main/setup/advanced/control-server.md
# Port forwarding: https://github.com/qdm12/gluetun-wiki/blob/main/setup/options/port-forwarding.md

# Mandatory env vars:
# GLUETUN_CONTROL_ENDPOINT
# GLUETUN_HEALTH_ENDPOINT
# TRANSMISSION_ENDPOINT
# TRANSMISSION_USER
# TRANSMISSION_PASS

GLUETUN_PICK_NEW_SERVER_AFTER=${GLUETUN_PICK_NEW_SERVER_AFTER:-10}
PEERPORT_CHECK_INTERVAL=${PEERPORT_CHECK_INTERVAL:-15}
STANDARD_WAIT_TIME=${STANDARD_WAIT_TIME:-5}

tag="gluetranspia"

# wait for gluetun to become healthy
wait_for_gluetun() {
    until curl -s -m $STANDARD_WAIT_TIME -o /dev/null -w "%{http_code}" $GLUETUN_HEALTH_ENDPOINT | grep -q 200; do
        echo "[$tag] waiting for gluetun to become active..." >> /proc/1/fd/1
        sleep $STANDARD_WAIT_TIME
    done
    echo "[$tag] gluetun is active." >> /proc/1/fd/1
}

# get transmission peer port
get_transmission_port() {
    transmission_response=$(transmission-remote "$TRANSMISSION_ENDPOINT" -n "$TRANSMISSION_USER":"$TRANSMISSION_PASS" -si | grep Listenport | awk -F' ' '{print $2}')
    if [ "$transmission_response" == "" ]; then
        echo "[$tag] tramsmission returned null ($transmission_response), retrying..." >> /proc/1/fd/1
        return 1
    else
        echo "$transmission_response"
    fi
}

# Function to get gluetun peer port
get_gluetun_port() {
    gluetun_response=$(curl -s "$GLUETUN_CONTROL_ENDPOINT/v1/openvpn/portforwarded")
    if [ "$gluetun_response" == "" ] || [ "$gluetun_response" == '{"port":0}' ]; then
        echo "[$tag] gluetun returned null or port 0 ($gluetun_response), retrying..." >> /proc/1/fd/1
        return 1
    else
        echo "$gluetun_response" | jq -r '.port'
    fi
}

# Function to update transmission peer port
update_transmission_port() {
    transmission-remote "$TRANSMISSION_ENDPOINT" -n "$TRANSMISSION_USER":"$TRANSMISSION_PASS" -p "$1" || return 1
}

check_transmission_port_open() {
    transmission_response=$(transmission-remote "$TRANSMISSION_ENDPOINT" -n "$TRANSMISSION_USER":"$TRANSMISSION_PASS" -pt) || return 1
    echo "$transmission_response"
}

# validate input
# required env vars
required_vars=(
    GLUETUN_CONTROL_ENDPOINT
    TRANSMISSION_ENDPOINT
    TRANSMISSION_USER
    TRANSMISSION_PASS
    GLUETUN_HEALTH_ENDPOINT
)

# exit of any env var is unset
for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        echo "$var is not set. Please set the environment variable." >&2
        exit 1
    fi
done

# wait for gluetun to wake up
wait_for_gluetun

gluetun_port_fail_count=0
# main loop
while true; do
    sleep "$PEERPORT_CHECK_INTERVAL"

    gluetun_port=$(get_gluetun_port) || { gluetun_port_fail_count=$((gluetun_port_fail_count + 1)); continue; }
    transmission_port=$(get_transmission_port) || continue

    # check if we need to instruct gluetun to pick a new server
    if [ "$gluetun_port_fail_count" -gt $GLUETUN_PICK_NEW_SERVER_AFTER ]; then
        echo "[$tag] gluetun port check failed $GLUETUN_PICK_NEW_SERVER_AFTER times, instructing gluetun to pick a new server..." >> /proc/1/fd/1
        gluetun_server_response=`curl -s -X PUT -d '{"status":"stopped"}' "$GLUETUN_CONTROL_ENDPOINT/v1/openvpn/status"` || echo "[$tag] error instructing gluetun to pick new server ($gluetun_server_response)." >> /proc/1/fd/1
        if [ "$gluetun_server_response" != '{"outcome":"stopped"}' ]; then
            echo "[$tag] Bleh, gluetun server response is weird, expected {\"outcome\":\"stopped\"}, got $gluetun_server_response" >> /proc/1/fd/1
            continue
        fi
        gluetun_port_fail_count=0
        sleep 15 # this is fixed as ~ around this time it takes for gluetun to reconnect, this avoids some nag in logs
        wait_for_gluetun # just in case this takes longer than expected
        continue
    fi

    # check for port change, and instruct transmission to pick enanble new port
    if [ "$gluetun_port" != "$transmission_port" ] || [ $(check_transmission_port_open) != "Port is open: Yes" ]; then
        echo "[$tag] port change detected: gluetun is $gluetun_port, transmission is $transmission_port, updating..." >> /proc/1/fd/1
        update_transmission_port "$gluetun_port"
        count=0
        while [ "$count" -lt 5 ]; do
            sleep $STANDARD_WAIT_TIME
            if [ $(check_transmission_port_open) == "Port is open: Yes" ]; then
                break
            fi
            echo "[$tag] waiting for transmission port to update ($count/5)..." >> /proc/1/fd/1
            update_transmission_port "$gluetun_port"
            count=$((count + 1))
        done

        new_transmission_port=$(get_transmission_port)
        if [ "$new_transmission_port" != "$gluetun_port" ]; then
            echo "[$tag] error: transmission port update failed." >> /proc/1/fd/1
        else
            echo "[$tag] success: transmission port updated successfully." >> /proc/1/fd/1
        fi
    else
        echo "[$tag] heartbeat: gluetun and transmission ports match ($new_transmission_port), status: $(check_transmission_port_open) " >> /proc/1/fd/1
    fi
done
