# GlueTrans Peer Port updater

This image updates Transmission peer port with the one received from VPN via Gluetun.  
Please see the [github page](https://github.com/miklosbagi/gluetrans) for detailed usage and documentation.

**Supported VPN Providers:**
- Private Internet Access
- ProtonVPN

**Supported Gluetun Versions:** v3.35 through v3.41.0+ (and minor versions)  
AMD64 and ARM64 platforms are supported.

## Tags

* **`latest`**: Latest stable release (currently v0.3.8)
* **`vX.Y.Z`**: Specific version tags for pinning (e.g., v0.3.8, v0.3.7, v0.3.6). See [Releases](https://github.com/miklosbagi/gluetrans/releases) for details.
* **`dev`**: Development builds from active branches - expect issues, use for testing only

## Security Note (v0.3.7+)

> **🔒 Security Feature:** Starting from v0.3.7, sensitive credentials (API keys, usernames, passwords) are automatically removed from the container environment after startup. They remain functional in memory but are not visible via `docker exec` or container inspection. Set `DEBUG=1` to keep credentials visible for troubleshooting.

## API Compatibility Note (v0.3.6+)

> **Note:** Gluetun v3.41.0 introduced new Control Server HTTP API endpoints. Gluetrans v0.3.6+ automatically detects and uses the correct endpoints:
> - **Gluetun v3.41.0+**: Uses new API (`/v1/portforward`, `/v1/vpn/status`)
> - **Gluetun v3.40.0 and older**: Uses old API (`/v1/openvpn/portforwarded`, `/v1/openvpn/status`)
>
> The script automatically tries the new endpoint first and falls back to the old one if needed. If you use a bind-mounted Gluetun `config.toml` (v3.38–v3.40.0 or per-route roles), its routes must match your Gluetun version (see below).

> **Warning:** Starting from gluetun 3.40.0+ versions, control server requires authentication.  
> Gluetrans, from version 0.3.5 and above provides support for this change, but an API key must be provided.  
> 
> Quick setup (see [Gluetun control server](https://github.com/qdm12/gluetun-wiki/blob/main/setup/advanced/control-server.md#configuration)):
> 1. **Gluetun v3.41.0+:** set `HTTP_CONTROL_SERVER_AUTH_DEFAULT_ROLE` on gluetun (JSON with API key; [issue #92](https://github.com/miklosbagi/gluetrans/issues/92)).
> 2. Set `GLUETUN_CONTROL_API_KEY` on gluetrans to the **same** key.
> 3. **Gluetun v3.38–v3.40.0:** bind-mount `config.toml` instead (env-based default role is not available before v3.41.0).

## Minimal Example

```bash
docker run \
-e GLUETUN_CONTROL_ENDPOINT=http://gluetun:8000 \
-e GLUETUN_CONTROL_API_KEY=your-secret-api-key \
-e GLUETUN_HEALTH_ENDPOINT=http://gluetun:9999 \
-e TRANSMISSION_ENDPOINT=http://transmission:9091/transmission/rpc \
-e TRANSMISSION_USER=transmission \
-e TRANSMISSION_PASS=transmission \
miklosbagi/gluetrans:latest
```

## Docker-Compose Example

### PIA/ProtonVPN with Gluetun + Transmission

**CI smoke tests** use **Private Internet Access** (see `test/docker-compose-build.yaml` for v3.41.0+ or `test/docker-compose-build-legacy-gluetun.yaml` for v3.38–v3.40.0). Full stack example (PIA):

```yaml
services:
  gluetun:
    image: qmcgaw/gluetun:v3.41.0
    cap_add:
      - NET_ADMIN
    ports:
      - 8000:8000 # Control server
      - 9091:9091 # Transmission UI
    environment:
      VPN_SERVICE_PROVIDER: "private internet access"
      OPENVPN_USER: My OpenVPN Username
      OPENVPN_PASSWORD: My OpenVPN Password
      SERVER_REGIONS: "Switzerland,DE Berlin,FI Helsinki,France"
      VPN_PORT_FORWARDING: on
      VPN_PORT_FORWARDING_PROVIDER: "private internet access"
      HTTP_CONTROL_SERVER_AUTH_DEFAULT_ROLE: '{"auth":"apikey","apikey":"secret-apikey-for-gluetrans"}'
    volumes:
      - ./data/gluetun:/gluetun
    devices:
      - /dev/net/tun:/dev/net/tun
    restart: unless-stopped

  transmission:
    image: linuxserver/transmission:4.0.6
    environment:
      USER: My Transmission Username
      PASS: My Transmission Password
    volumes:
      - ./data/transmission:/config
      - ./data/transmission_downloads:/downloads
    network_mode: "service:gluetun"
    restart: unless-stopped
    depends_on:
      - gluetun

  gluetrans:
    image: miklosbagi/gluetrans:latest
    environment:
      GLUETUN_CONTROL_ENDPOINT: http://localhost:8000
      GLUETUN_HEALTH_ENDPOINT: http://localhost:9999
      GLUETUN_CONTROL_API_KEY: "secret-apikey-for-gluetrans"  # same key as Gluetun HTTP_CONTROL_SERVER_AUTH_DEFAULT_ROLE
      TRANSMISSION_ENDPOINT: http://localhost:9091/transmission/rpc
      TRANSMISSION_USER: My Transmission Username
      TRANSMISSION_PASS: My Transmission Password
      PEERPORT_CHECK_INTERVAL: 30  # optional, default: 15
      GLUETUN_PICK_NEW_SERVER_AFTER: 15  # optional, default: 10
      FORCED_COUNTRY_JUMP: 0  # optional, 0=disabled, e.g. 120=every 2 hours
    network_mode: "service:gluetun"
    depends_on:
      - gluetun
```

For **ProtonVPN**, use `VPN_SERVICE_PROVIDER: "protonvpn"`, **`SERVER_COUNTRIES`** (not `SERVER_REGIONS`), and `VPN_PORT_FORWARDING_PROVIDER: "protonvpn"`. See [Gluetun ProtonVPN setup](https://github.com/qdm12/gluetun-wiki/blob/main/setup/providers/protonvpn.md) and the compose snippet in the [GitHub README](https://github.com/miklosbagi/gluetrans/blob/main/README.md).

## Gluetun `config.toml` (optional)

**Gluetun v3.41.0+:** prefer `HTTP_CONTROL_SERVER_AUTH_DEFAULT_ROLE` on gluetun (see compose example above). A bind-mounted `config.toml` is optional if you need [per-route roles](https://github.com/qdm12/gluetun-wiki/blob/main/setup/advanced/control-server.md#configuration).

**Gluetun v3.38–v3.40.0:** use `config.toml` at `/gluetun/auth/config.toml`; `HTTP_CONTROL_SERVER_AUTH_DEFAULT_ROLE` is not available before v3.41.0.

When you use a file, pick the snippet that matches your Gluetun version’s routes:

### Gluetun v3.41.0 and newer (new API endpoints)

```toml
[[roles]]
name = "gluetrans"
routes = ["GET /v1/portforward", "GET /v1/vpn/status", "PUT /v1/vpn/status"]
auth = "apikey"
apikey = "secret-apikey-for-gluetrans"
```

### Gluetun v3.40.0 and older (old API endpoints)

```toml
[[roles]]
name = "gluetrans"
routes = ["GET /v1/openvpn/portforwarded", "GET /v1/openvpn/status", "PUT /v1/openvpn/status"]
auth = "apikey"
apikey = "secret-apikey-for-gluetrans"
```

**Why separate configs?** Gluetun validates listed routes at startup. Gluetrans still picks HTTP paths automatically; the file must list paths that exist on your Gluetun version.

## Environment Variables

**Mandatory:**
- `GLUETUN_CONTROL_ENDPOINT`: Control Server URL, e.g. `http://gluetun:8000`
- `GLUETUN_CONTROL_API_KEY`: API key for control server (required for v3.40.0+)
- `GLUETUN_HEALTH_ENDPOINT`: Health check URL, e.g. `http://gluetun:9999`
- `TRANSMISSION_ENDPOINT`: Transmission RPC URL, e.g. `http://transmission:9091/transmission/rpc`
- `TRANSMISSION_USER`: Transmission RPC username
- `TRANSMISSION_PASS`: Transmission RPC password

**Optional:**
- `PEERPORT_CHECK_INTERVAL`: Validation interval in seconds (default: 15)
- `GLUETUN_PICK_NEW_SERVER_AFTER`: Max retry failures before switching servers (default: 10)
- `FORCED_COUNTRY_JUMP`: Minutes between forced country changes, 0=disabled (default: 0)
- `SANITIZE_LOGS`: Omit sensitive info from logs, 0=disabled (default: 0)
- `DEBUG`: Keep credentials visible in environment for debugging, 0=disabled (default: 0)

## What It Does

1. Waits for Gluetun to establish VPN connection
2. Monitors Gluetun's VPN peer port via control server
3. Compares with Transmission's current peer port
4. Updates Transmission when ports differ
5. Verifies port is open and accessible
6. Automatically switches servers if port issues persist
7. Optional: Force server changes at intervals

It keeps trying until you have a working peer port!

## Debugging

Check logs: `docker logs -f gluetrans`

Ideal output shows:
- `security: sensitive environment variables removed from environment (stored in memory only)` (v0.3.7+)
- `security: verified - sensitive vars are not accessible in main process environment` (v0.3.7+)
- `gluetun is active, country details: ...`
- `port change detected: ... updating...`
- `success: transmission port updated successfully`
- `heartbeat: gluetun & transmission ports match (XXXXX), Port is open: Yes`

**Debug Mode:** Set `DEBUG=1` to keep credentials visible and see `debug: DEBUG=1, keeping sensitive environment variables visible`

## Links

- **GitHub Repository**: https://github.com/miklosbagi/gluetrans
- **Issues**: https://github.com/miklosbagi/gluetrans/issues
- **Releases**: https://github.com/miklosbagi/gluetrans/releases
- **GHCR Mirror**: https://github.com/miklosbagi/gluetrans/pkgs/container/gluetranspia

## Version Info

**Current Release:** v0.3.8
- 🔒 **Security update**: Upgraded Alpine Linux 3.21.3 → 3.23.3 (addresses CVEs)
- 🔐 Updated curl 8.12.1 → 8.17.0 (security fixes)
- 🐚 Updated bash 5.2.37 → 5.3.3
- ✅ All tests passing, zero breaking changes

**Previous Release:** v0.3.7
- Security enhancement: Automatic credential removal from container environment
- Optional DEBUG mode for troubleshooting
- Comprehensive security testing

**v0.3.6:**
- Gluetun v3.41.0 API support with Wireguard compatibility
- Automatic backward compatibility with v3.35-v3.41.0+

See [Release Notes](https://github.com/miklosbagi/gluetrans/releases) for full changelog.
