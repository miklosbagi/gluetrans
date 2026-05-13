# GlueTrans Tests
Please note that in order to use any of this, the following variables need to be exported in the shell:
- `GLUETRANS_VPN_USERNAME` — PIA OpenVPN username
- `GLUETRANS_VPN_PASSWORD` — PIA OpenVPN password
- `GLUETRANS_VPN_REGIONS` — PIA **`SERVER_REGIONS`** for Gluetun (comma-separated region names as in [Gluetun’s PIA wiki](https://github.com/qdm12/gluetun-wiki/blob/main/setup/providers/private-internet-access.md)); pick regions that support **port forwarding**. Example shape: `Switzerland,DE Berlin,FI Helsinki,France` (adjust to regions you verify work in your account).
- `GLUETRANS_TRANSMISSION_USERNAME`
- `GLUETRANS_TRANSMISSION_PASSWORD`

These are utilized via [.env](./.env).

## Test infrastructure
`make test-env-start` and `make test-env-stop` start and stop the stack defined by `GLUETUN_VERSION`:
- **Gluetun v3.41.0, `latest`:** [`docker-compose-build.yaml`](./docker-compose-build.yaml) — control API auth via `HTTP_CONTROL_SERVER_AUTH_DEFAULT_ROLE` (no `config.toml` mount).
- **Gluetun v3.38, v3.39, v3.40.0:** [`docker-compose-build-legacy-gluetun.yaml`](./docker-compose-build-legacy-gluetun.yaml) — bind-mounted `test/gluetun-config/config.toml` (see [Makefile](../Makefile) `LEGACY_GLUETUN_CONTROL_AUTH`).

The Makefile exports `GLUETRANS_COMPOSE_FILE` / `GLUETRANS_COMPOSE_DEBUG_FILE` for [`run-smoke.sh`](./run-smoke.sh) and [`run-debug-test.sh`](./run-debug-test.sh).

Components:
- Gluetun (**Private Internet Access** / OpenVPN in CI)
- Transmisison
- GlueTrans

Please take a look at the compose file selected for your `GLUETUN_VERSION` (paths above).

## Linters
`make lint`
- Shellcheck is used for shell scripts: `shellcheck entrypoint.sh`
- Hadolint is used for dockerfile: `hadolint Dockerfile`

## Smoke pack
`make test-run-smoke` (depends on test infrastructure).

Coverage:
1. Active gluetun is detected.
1. Port change is detected.
1. Transmission port update is successful.
1. Heartbeat is happening.
1. Gluetun and Transmission ports end up matching.
1. Transmission reports port is open.
1. Country jump timer is running.
1. Asking gluetun to disconnect.
1. Country Jump.

Handled by [run-smoke.sh](./run-smoke.sh).

### Example output
```
[+] Running 4/4
 ✔ Network test_default           Created                                                                                                              0.0s
 ✔ Container test-gluetun-1       Started                                                                                                              0.0s
 ✔ Container test-gluetrans-1  Started                                                                                                              0.1s
 ✔ Container test-transmission-1  Started                                                                                                              0.1s
Running tests...
  👍🏻 [Active gluetun is detected] passed: Pattern 'gluetun is active, country details' found in the logs.
  👍🏻 [Port change is detected] passed: Pattern 'port change detected: gluetun is .*, transmission is .*,  updating...' found in the logs.
  👍🏻 [Transmission port update is successful] passed: Pattern 'success: transmission port updated successfully.' found in the logs.
  👍🏻 [Heartbeat is happening] passed: Pattern 'heartbeat: .*' found in the logs.
  👍🏻 [Gluetun and Transmission ports end up matching] passed: Pattern 'heartbeat: gluetun & transmission ports match' found in the logs.
  👍🏻 [Transmission reports port is open] passed: Pattern ', Port is open: Yes$' found in the logs.
  👍🏻 [Country jump timer is running] passed: Pattern 'country jump timer: [0-9]+ minute\(s\) left on this server.' found in the logs.
  👍🏻 [Asking gluetun to disconnect] passed: Pattern 'asking gluetun to disconnect from .*,$' found in the logs.
  👍🏻 [Country Jump] passed: country hashes are different.
✅ All smoke tests pass.
```