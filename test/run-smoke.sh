#!/bin/bash

SERVICE_NAME="gluetrans" # as in docker-compose.yml
COMPOSE_FILE="test/docker-compose-build.yaml"

check_docker_logs() {
    test_name=$1
    pattern=$2
    end_time=$((SECONDS+TIMEOUT))
    while [ $SECONDS -lt $end_time ]; do
        if docker_logs=$(docker compose -f "$COMPOSE_FILE" logs "$SERVICE_NAME" 2>&1 | tac); then
            if echo "$docker_logs" | grep -qE "$pattern"; then
                echo "  👍🏻 [$test_name] passed: Pattern '$pattern' found in the logs."
                return 0
            fi
        fi
    done
    echo "  😵 [$test_name] failed: Pattern '$pattern' not found in the logs within $TIMEOUT seconds."
    return 1
}

assert_keyword() {
    test_name=$1
    pattern=$2
    if ! check_docker_logs "$test_name" "$pattern"; then
        echo "  😵 [$test_name] failed for pattern: $pattern"
        exit 1
    fi
}


# country-jump test: get country hashes
get_hash() {
    log_output=$1
    if [[ $log_output =~ $HASH_PATTERN ]]; then
        if [[ $hash_count -eq 0 ]]; then
            hash1="${BASH_REMATCH[0]}"
            ((hash_count++))
        else
            hash2="${BASH_REMATCH[1]}"
            #DEBUG echo "2: $hash2"
        fi
    else
        echo "  😵 [Country Jump] failed, country details not found."
        exit 1
    fi
}

echo "Running tests..."

# Active Gluetun is detected
TIMEOUT=120
assert_keyword "Active gluetun is detected" "gluetun is active, country details"
hash_count=0
HASH_PATTERN="country details: [[:alpha:]]+/[[:alpha:]]+,"
get_hash "$docker_logs"

# Port change is detected
TIMEOUT=60
assert_keyword "Port change is detected" "port change detected: gluetun is .*, transmission is .*,  updating..."

# Transmission port updated successfully
TIMEOUT=60
assert_keyword "Transmission port update is successful" "success: transmission port updated successfully."

# Heartbeat is happening
TIMEOUT=120
assert_keyword "Heartbeat is happening" "heartbeat: .*"

# Gluetun and Transmission ports end up matching
TIMEOUT=60
assert_keyword "Gluetun and Transmission ports end up matching" "heartbeat: gluetun & transmission ports match"

# Transmission reports port is open
TIMEOUT=60
assert_keyword "Transmission reports port is open" ", Port is open: Yes$"

# Country jump timer is running
TIMEOUT=60
assert_keyword "Country jump timer is running" "country jump timer: [0-9]+ minute\(s\) left on this server."

# Asking gluetun to disconnect
TIMEOUT=120
assert_keyword "Asking gluetun to disconnect" "asking gluetun to disconnect from .*,$"

# Country jump works
TIMEOUT=240 # we may randomly jump to the same country again, so leave this a bit longer
HASH_PATTERN="country details: [[:alpha:]]+/[[:alpha:]]+,"
# hash1=""
# hash2=""
# hash_count=0
get_hash "$docker_logs"

if [ "$hash1" = "$hash2" ]; then
    echo "  😵 [Country Jump] failed, country hashes are the same."
    exit 1
else
    echo "  👍🏻 [Country Jump] passed: country hashes are different."
fi

### END
exit 0
