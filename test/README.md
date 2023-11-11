# GlueTrans Tests
Please note that in order to use any of this, the following variables need to be exported in the shell:
- `GLUETRANS_VPN_USERNAME`
- `GLUETRANS_VPN_PASSWORD`
- `GLUETRANS_VPN_REGIONS`
- `GLUETRANS_TRANSMISSION_USERNAME`
- `GLUETRANS_TRANSMISSION_PASSWORD`

These are utilized via [.env](./.env).

## Test infrastructure
`make test-env-start` and `make test-env-stop` to start and stop the test environment.
Components:
- Gluetun
- Transmisison
- GlueTrans

Please take a look at the [docker-compose](./docker-compose-build.yaml) file.

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