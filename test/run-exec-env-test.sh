#!/bin/bash
# Issue #88: verify (1) PID 1 environ has no inline secret names after unset, and
# (2) with *_FILE only (no inline secrets in container config), `exec … env` has no
# secret *values* for the three credentials.
# No VPN. Use DOCKER_CMD=podman for Podman.
set -euo pipefail

DOCKER_CMD="${DOCKER_CMD:-docker}"
IMAGE_NAME="gluetrans-exec-env-test"
CONTAINER_NAME="gluetrans-exec-env-test"

export GLUETUN_CONTROL_ENDPOINT="http://localhost:8000"
export GLUETUN_HEALTH_ENDPOINT="http://localhost:9999"
export TRANSMISSION_ENDPOINT="http://localhost:9091/transmission/rpc"

cleanup() {
    $DOCKER_CMD rm -f "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

echo "Building image (DOCKER_CMD=$DOCKER_CMD)..."
if [ "$DOCKER_CMD" = "podman" ]; then
    $DOCKER_CMD build -t "$IMAGE_NAME" .
else
    # --load: required when the default builder is docker-container (image must exist in local daemon)
    docker buildx build --load -t "$IMAGE_NAME" .
fi

# --- Test A: inline -e secrets (legacy compose); entrypoint must log successful unset ---
echo "=== Test A: inline secrets — security log path ==="
$DOCKER_CMD rm -f "$CONTAINER_NAME" 2>/dev/null || true
$DOCKER_CMD run -d --name "$CONTAINER_NAME" \
    -e GLUETUN_CONTROL_ENDPOINT \
    -e GLUETUN_HEALTH_ENDPOINT \
    -e TRANSMISSION_ENDPOINT \
    -e GLUETUN_CONTROL_API_KEY="secret-api-key-must-not-appear-in-pid1" \
    -e TRANSMISSION_USER="testuser" \
    -e TRANSMISSION_PASS="testpass" \
    "$IMAGE_NAME"

for _i in $(seq 1 20); do
    if $DOCKER_CMD logs "$CONTAINER_NAME" 2>&1 | grep -q "sensitive environment variables removed from environment" \
        && $DOCKER_CMD logs "$CONTAINER_NAME" 2>&1 | grep -q "verified - sensitive vars are not accessible in main process environment"; then
        break
    fi
    if [ "$_i" -eq 20 ]; then
        echo "  😵 timeout waiting for security log lines"
        $DOCKER_CMD logs "$CONTAINER_NAME" 2>&1 | tail -30
        exit 1
    fi
    sleep 1
done
echo "  👍🏻 Security unset path ran (see issue #88: many runtimes still show inline -e values in 'exec env'; use *_FILE to hide values)"

# --- Test B: *_FILE only; exec env must not expose secret values ---
echo "=== Test B: *_FILE only — no secret values in exec env ==="
cleanup
SECRET_DIR=$(mktemp -d)
printf '%s' 'file-based-api-key' >"$SECRET_DIR/api"
printf '%s' 'file-based-user' >"$SECRET_DIR/tuser"
printf '%s' 'file-based-pass' >"$SECRET_DIR/tpass"
chmod 600 "$SECRET_DIR"/*

$DOCKER_CMD run -d --name "$CONTAINER_NAME" \
    -v "$SECRET_DIR/api:/run/gtsecrets/api:ro" \
    -v "$SECRET_DIR/tuser:/run/gtsecrets/tuser:ro" \
    -v "$SECRET_DIR/tpass:/run/gtsecrets/tpass:ro" \
    -e GLUETUN_CONTROL_ENDPOINT \
    -e GLUETUN_HEALTH_ENDPOINT \
    -e TRANSMISSION_ENDPOINT \
    -e GLUETUN_CONTROL_API_KEY_FILE=/run/gtsecrets/api \
    -e TRANSMISSION_USER_FILE=/run/gtsecrets/tuser \
    -e TRANSMISSION_PASS_FILE=/run/gtsecrets/tpass \
    "$IMAGE_NAME"

for _i in $(seq 1 20); do
    if $DOCKER_CMD logs "$CONTAINER_NAME" 2>&1 | grep -q "sensitive environment variables removed from environment"; then
        break
    fi
    if [ "$_i" -eq 20 ]; then
        echo "  😵 timeout waiting for security log (file mode)"
        $DOCKER_CMD logs "$CONTAINER_NAME" 2>&1 | tail -30
        exit 1
    fi
    sleep 1
done

exec_env=$($DOCKER_CMD exec "$CONTAINER_NAME" env 2>&1)
for needle in file-based-api-key file-based-user file-based-pass; do
    if echo "$exec_env" | grep -q "$needle"; then
        echo "  😵 exec env still contains secret value fragment: $needle"
        exit 1
    fi
done
# Inline names must not be set to values (compose did not pass them)
for var in GLUETUN_CONTROL_API_KEY TRANSMISSION_USER TRANSMISSION_PASS; do
    if echo "$exec_env" | grep -qE "^${var}="; then
        echo "  😵 exec env has ${var}= (unexpected in file-only mode)"
        exit 1
    fi
done
echo "  👍🏻 exec env has no credential names or file-based secret values"

cleanup
rm -rf "$SECRET_DIR"
echo "✅ Exec-env tests passed."
