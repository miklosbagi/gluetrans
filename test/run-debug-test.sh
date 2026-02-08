#!/bin/bash

# Test that DEBUG=1 mode works correctly and keeps sensitive vars visible

SERVICE_NAME="gluetrans"
COMPOSE_FILE="test/docker-compose-build-debug.yaml"

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

echo "Running DEBUG mode tests..."

# Debug mode is enabled
TIMEOUT=30
assert_keyword "Debug mode is enabled" "debug: DEBUG=1, keeping sensitive environment variables visible"

# Active Gluetun is detected (proves script still works in debug mode)
TIMEOUT=120
assert_keyword "Active gluetun is detected" "gluetun is active, country details"

# Port change is detected (proves functionality still works)
TIMEOUT=60
assert_keyword "Port change is detected" "port change detected: gluetun is .*, transmission is .*,  updating..."

# Transmission port updated successfully
TIMEOUT=60
assert_keyword "Transmission port update is successful" "success: transmission port updated successfully."

# Heartbeat is happening
TIMEOUT=120
assert_keyword "Heartbeat is happening" "heartbeat: .*"

### END
echo "✅ All DEBUG mode tests passed."
exit 0
