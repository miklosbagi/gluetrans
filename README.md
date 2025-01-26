# GlueTrans Peer Port updater
[![GlueTrans PR Check Latest](https://github.com/miklosbagi/gluetrans/actions/workflows/pr-check.yml/badge.svg)](https://github.com/miklosbagi/gluetrans/actions/workflows/pr-check.yml)

[![Docker Pulls](https://badgen.net/docker/pulls/miklosbagi/gluetrans?icon=docker&label=Docker%20Pulls)](https://hub.docker.com/r/miklosbagi/gluetrans/)

Gluetun VPN Peer Port updater for Transmission.
Supported providers:
- Private Internet Access
- ProtonVPN

Supported gluetun versions: all between v3.35 and v3.40 (incl minor versions), see tests passing/failing above for latest.
(please note that there's no CI test for v3.35 as that version did not support protonvpn peer port back that time, but was tested and working with PIA).

> [!WARNING]
> Breaking change ahead: starting from gluetun 3.40.0+ versions, control server requires authentication. You can read more about this in [gluetun control server documentation](https://github.com/qdm12/gluetun-wiki/blob/main/setup/advanced/control-server.md#authentication).<br>
> Gluetrans, from version 0.3.5 and above provides support for this change, but an API key must be provided. Please [consult compose the examples](#docker-compose-examples) and [config.toml example](#gluetun-configtoml) below.<br><br>
> In short:
> 1. Set `GLUETUN_CONTROL_API_KEY` in your environment variables.
> 1. Create a role in gluetun's `config.toml` with the same API key.
> 1. Map `config.toml` to gluetun container.
> 1. Set the same API key in gluetrans' environment variables.

## What does it do?
1. Waits for gluetun to report healthy
1. Checks gluetun's VPN Peer Port (via control server), and keep trying until it gets a valid port
   1. If port can't be retrieved in x tries, it insrtucts gluetun to pick a new server.
1. Checks Transmission's current Peer Port
   1. If transmission port can't be retrieved in x tries, it instructs gluetun to pick a new server.
1. If there is a difference between the two ports, it instructs Transmission to update its Peer Port.
1. Tests that transmission peer port is open, and updates it when things go sideways.

It keeps trying until you have a valid peer port.
## Environment variables
Mandatory:
- `GLUETUN_CONTROL_ENDPOINT`: Full Control Server URL with port, e.g.: `http://gluetun:8000`.
- `GLUETUN_CONTROL_API_KEY`: API key for the control server. This is requried from gluetun versions newer than v3.40.0.
- `GLUETUN_HEALTH_ENDPOINT`: Full Health URL with port, `http://gluetun:9999` by default.
- `TRANSMISSION_ENDPOINT` : Full Transmission RPC URL with port, service path, e.g.: `http://transmission:9091/transmission/rpc`.
- `TRANSMISSION_USER`: Username for transmission RPC auth.
- `TRANSMISSION_PASS`: Password for transmission RPC auth.

Optional:
- `PEERPORT_CHECK_INTERVAL`: how often peer port should be validated. Default: 15, in seconds.
- `GLUETUN_PICK_NEW_SERVER_AFTER`: pick a new server after X number of failures in detecting a working peer port. Default: 10, in number of retries.
- `FORCED_COUNTRY_JUMP`: jump to a new country every X minutes. Default: 0 (means: disabled). Example: 120 (jump to new country every 2 hours).
- `SANITIZE_LOGS`: sanitize logs. Default: 0 (means disabled). Set to 1 to omit potentially sensitive information from logs.

## Vanilla usage
Export the necessary variables, for example:
```
export GLUETUN_CONTROL_ENDPOINT=http://gluetun:8000
export GLUETUN_CONTROL_API_KEY=your-secret-api-key
export GLUETUN_HEALTH_ENDPOINT=http://gluetun:8080
export TRANSMISSION_ENDPOINT=http://transmission:9091/transmission/rpc
export TRANSMISSION_USER=transmission
export TRANSMISSION_PASS=transmission
```

Run the script:
```
./entrypoint.sh
```

Script logs to stdout, you can redirect it to a file if you want to with `./entrypoint.sh > /path/to/logfile.log`

## Docker pull
```
docker run \
-e GLUETUN_CONTROL_ENDPOINT=http://gluetun:8000 \
-e GLUETUN_CONTROL_API_KEY=your-secret-api-key \
-e GLUETUN_HEALTH_ENDPOINT=http://gluetun:8080 \
-e TRANSMISSION_ENDPOINT=http://transmission:9091/transmission/rpc \
-e TRANSMISSION_USER=transmission \
-e TRANSMISSION_PASS=transmission \
miklosbagi/gluetrans:latest
```

## Docker build for local testing
- Clone this repo, and `cd` into it
- If this is not the first time you build, remove the old image with `docker rmi gluetrans:local`
- Build the image with `docker build -t gluetrans:local .`
- Run with:
```
docker run \
-e GLUETUN_CONTROL_ENDPOINT=http://gluetun:8000 \
-e GLUETUN_HEALTH_ENDPOINT=http://gluetun:8080 \
-e GLUETUN_CONTROL_API_KEY=your-secret-api-key \
-e TRANSMISSION_ENDPOINT=http://transmission:9091/transmission/rpc \
-e TRANSMISSION_USER=transmission \
-e TRANSMISSION_PASS=transmission \
gluetrans:local
```

## Docker-compose examples
### PiaVPN (gluetun + transmission + piavpn)
Please note that `data` directory will be created if this gets executed as is.
Also, please note that we test against versions, not :latest, as that's like a weather report.

```
services:
  gluetun:
    image: qmcgaw/gluetun:v3.40.0
    volumes:
      - ./data/gluetun:/gluetun
    cap_add:
      - NET_ADMIN
    ports:
      - 8000:8000 # Control server
      - 9091:9091 # Transmission UI
    environment:
      VPN_SERVICE_PROVIDER: "private internet access"
      OPENVPN_USER: My OpenVPN Username
      OPENVPN_PASSWORD: My OpenVPN Password
      SERVER_REGIONS: "FI Helsinki,France,Norway,SE Stockholm,Serbia"
      VPN_PORT_FORWARDING: on
      VPN_PORT_FORWARDING_PROVIDER: "private internet access"
    # from gluetun v3.40.0+ control server auth, mapping config.toml with api key is required
    volumes:
      - ./gluetun-config/config.toml:/gluetun/auth/config.toml
    restart: unless-stopped
    # for ubuntu-latest, you may need:
    devices:
      - /dev/net/tun:/dev/net/tun

  transmission:
    image: linuxserver/transmission:4.0.6
    environment:
      USER: My Transmission Username
      PASS: My Transmission Password
      #PEERPORT: # this is what we do here, so skip it.
    volumes:
      - ./data/transmission:/config
      - ./data/transmission_downloads:/downloads
    network_mode: "service:gluetun" # go through gluetun's VPN
    restart: unless-stopped
    depends_on:
      - gluetun

  gluetrans:
    image: miklosbagi/gluetrans:latest
    environment:
      GLUETUN_CONTROL_ENDPOINT: http://localhost:8000
      GLUETUN_HEALTH_ENDPOINT: http://localhost:9999
      # from gluetun v3.40.0+ control server auth key must be passed
      GLUETUN_CONTROL_API_KEY: "secret-apikey-for-gluetrans" # must match the one in config.toml
      TRANSMISSION_ENDPOINT: http://localhost:9091/transmission/rpc
      TRANSMISSION_USER: My Transmission Username
      TRANSMISSION_PASS: My Transmission Password
      PEERPORT_CHECK_INTERVAL: 30 # optional, default: 15, in seconds
      GLUETUN_PICK_NEW_SERVER_AFTER: 15 # optional, default: 10, in number of retries
      FORCED_COUNTRY_JUMP: 0 # optional, default: 0 (means: disabled). Example: 120 (jump to new country every 2 hours)
    network_mode: "service:gluetun" # go through gluetun's VPN
    depends_on:
      - gluetun
```

### ProtonVPN (gluetun + transmission + protonvpn) (gluetun v3.36 and above only)
Please note that `data` directory will be created if this gets executed as is.
Also, please note that we test against versions, not :latest, as that's like a weather report.

```
services:
  gluetun:
    image: qmcgaw/gluetun:v3.40.0
    volumes:
      - ./data/gluetun:/gluetun
    cap_add:
      - NET_ADMIN
    ports:
      - 8000:8000 # Control server
      - 9091:9091 # Transmission UI
    environment:
      VPN_SERVICE_PROVIDER: "protonvpn"
      OPENVPN_USER: My OpenVPN Username
      OPENVPN_PASSWORD: My OpenVPN Password
      SERVER_COUNTRIES: "Romania,Poland,Netherlands,Moldova"
      VPN_PORT_FORWARDING: on
      VPN_PORT_FORWARDING_PROVIDER: "protonvpn"
    # from gluetun v3.40.0+ control server auth, mapping config.toml with api key is required
    volumes:
      - ./gluetun-config/config.toml:/gluetun/auth/config.toml
    restart: unless-stopped
    # for ubuntu-latest, you may need:
    devices:
      - /dev/net/tun:/dev/net/tun

  transmission: ...same as with piavpn above...
  gluetrans: ....same as with piavpn above...
```

Please note that the above is example for piavpn. Nightly tests are running against protonvpn provider, feel free to take a look into the compose file in test for a working example.

### Gluetun config.toml
For control server authentication, `config.toml` will be required to allow gluetrans to send authenticated requests to gluetun.
```
[[roles]]
name = "gluetrans"
routes = ["GET /v1/openvpn/portforwarded", "PUT /v1/openvpn/status"]
auth = "apikey"
apikey = "secret-apikey-for-gluetrans"
```

## Debug
`docker logs -f gluetrans` should reveal what's happening.

### Ideal scenario
```
GlueTrans starting...
Jan 26 17:43:11 [gt] waiting for gluetun to establish connection...
Jan 26 17:43:16 [gt] waiting for gluetun to establish connection...
Jan 26 17:43:21 [gt] gluetun is active, country details: Europe/Berlin,
Jan 26 17:43:21 [gt] monitoring...
Jan 26 17:45:43 [gt] country jump timer: 0 minute(s) left on this server.
Jan 26 17:45:43 [gt] port change detected: gluetun is 49198, transmission is 56864, Port is open: Yes updating...
Jan 26 17:45:48 [gt] success: transmission port updated successfully.
Jan 26 17:46:18 [gt] country jump timer: 0 minute(s) left on this server.
Jan 26 17:46:19 [gt] heartbeat: gluetun & transmission ports match (49198), Port is open: Yes
Jan 26 17:46:49 [gt] country jump timer: 0 minute(s) left on this server.
Jan 26 17:46:49 [gt] countryjump: forcing gluetun to pick a new server after 1 minute(s).
Jan 26 17:46:49 [gt] asking gluetun to disconnect from Europe/Berlin,
Jan 26 17:47:04 [gt] gluetun is active, country details: Europe/Paris,
...
```
Please note that this data is sanitized.

### Self-healing scenario
```
GlueTrans starting...
Oct 10 10:10:11 [gt] waiting for gluetun to become active...
Oct 10 10:10:17 [gt] gluetun is active, country details: "123.123.1.12,UK,Belgrade,CODE Test DataCenterHost Inc."
Oct 10 10:10:17 [gt] monitoring...
Oct 10 10:10:47 [gt] gluetun returned {"port":0}, retrying (1 / 15)...
Oct 10 10:11:17 [gt] tramsmission returned '', retrying (1/15)...
Oct 10 10:11:47 [gt] tramsmission returned '', retrying (2/15)...
...
Oct 10 10:14:38 [gt] gluetun returned {"port":0}, retrying (15 / 15)...
Oct 10 10:11:38 [gt] gluetun port check failed 15 times, instructing gluetun to pick a new server.
Oct 10 10:15:17 [gt] gluetun is active, country details: "123.123.1.12,UK,Berlin,CODE Test DataCenterHost Inc."
Oct 10 10:15:47 [gt] gluetun returned {"port":0}, retrying (1 / 15)...
Oct 10 10:16:48 [gt] port change detected: gluetun is 12345, transmission is 0, updating...
Oct 10 10:16:54 [gt] success: transmission port updated successfully.
Oct 10 10:17:23 [gt] country jump timer: 14 minutes left on this server.
Oct 10 10:17:24 [gt] heartbeat: gluetun & transmission ports match (12345), Port is open: Yes
...
```
Please note that this data is sanitized.

## Known issues
- Transmission w/o RPC auth is not supported
- If you see that the third server you'd expect is still not returning a valid peer port, please check the logs of gluetun, as it might be that the server is not healthy, or the port is not open. If it keeps returning 0 as port, please stop and start it again, there is a known bug
- You probably want to avoid running this against gluetun:latest in case you see one of the build checks marked as failing. Fixing to a specific known to work version is rarely a bad idea.
