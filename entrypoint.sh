#!/bin/bash

GLUETUN_ENDPOINT=$GLUETUN_ENDPOINT
TRANSMISSION_ENDPOINT=$TRANSMISSION_ENDPOINT
TRANSMISSION_USER=$TRANSMISSION_USER
TRANSMISSION_PASS=$TRANSMISSION_PASS
PEERPORT_CHECK_INTERVAL=${PEERPORT_CHECK_INTERVAL:-15}

WAIT_TIME_FOR_GLUETUN=5
WAIT_TIME_FOR_GLUETUN_ACTIVE=3

tag="gluetranspia"

# Function to wait for Gluetun to become active
wait_for_gluetun() {
    until curl -s -m $WAIT_TIME_FOR_GLUETUN -o /dev/null -w "%{http_code}" http://localhost:9999 | grep 200; do
        echo "[$tag] waiting for Gluetun to become active..." >> /proc/1/fd/1
        sleep $WAIT_TIME_FOR_GLUETUN_ACTIVE
    done
    echo "[$tag] Gluetun is active." >> /proc/1/fd/1
}

# Function to get transmission peer port
get_transmission_port() {
    transmission_port=$(transmission-remote "$TRANSMISSION_ENDPOINT" -n "$TRANSMISSION_USER":"$TRANSMISSION_PASS" -si | grep Listenport | awk -F' ' '{print $2}')
    echo "$transmission_port"
}

# Function to get gluetun peer port
get_gluetun_port() {
    gluetun_response=$(curl -s "$GLUETUN_ENDPOINT/v1/openvpn/portforwarded")
    if [ "$gluetun_response" == "null" ] || [ "$gluetun_response" == '{"port":0}' ]; then
        echo "[$tag] error: Gluetun returned null or port 0." >> /proc/1/fd/1
        exit 1
    else
        gluetun_port=$(echo "$gluetun_response" | jq -r '.port')
        if [ "$gluetun_port" != "$(get_transmission_port)" ]; then
            echo "[$tag] new gluetun port: $gluetun_port" >> /proc/1/fd/1
        fi
    fi
}

# Function to update transmission peer port
update_transmission_port() {
    transmission-remote "$TRANSMISSION_ENDPOINT" -n "$TRANSMISSION_USER":"$TRANSMISSION_PASS" --port "$1"
}

# Main loop
wait_for_gluetun
while true; do
    gluetun_port=$(get_gluetun_port)
    transmission_port=$(get_transmission_port)
    if [ "$gluetun_port" != "$transmission_port" ]; then
        echo "[$tag] port update: change detected: gluetun is $gluetun_port, transmission is $transmission_port, updating..." >> /proc/1/fd/1
        update_transmission_port "$gluetun_port"
        sleep 5

        new_transmission_port=$(get_transmission_port)
        if [ "$new_transmission_port" != "$gluetun_port" ]; then
            echo "[$tag] error: transmission port update failed." >> /proc/1/fd/1
            exit 1
        else
            echo "[$tag] success: transmission port updated successfully." >> /proc/1/fd/1
        fi
    else
        if [ ! -z "$gluetun_port" ] && [ ! -z "$transmission_port" ]; then
            echo "[$tag] heartbeat: gluetun ($gluetun_port) and transmission ($transmission_port) ports match" >> /proc/1/fd/1
        fi
    fi
    sleep "$PEERPORT_CHECK_INTERVAL"
done
