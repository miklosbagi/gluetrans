# GlueTrans Peer Port updater
[![GlueTrans PR Check Latest](https://github.com/miklosbagi/gluetrans/actions/workflows/pr-check-latest.yml/badge.svg)](https://github.com/miklosbagi/gluetrans/actions/workflows/pr-check-latest.yml)  
[![GlueTrans PR Check v3.37](https://github.com/miklosbagi/gluetrans/actions/workflows/pr-check-3.37.yml/badge.svg)](https://github.com/miklosbagi/gluetrans/actions/workflows/pr-check-3.36.yml) [![GlueTrans PR Check v3.36](https://github.com/miklosbagi/gluetrans/actions/workflows/pr-check-3.36.yml/badge.svg)](https://github.com/miklosbagi/gluetrans/actions/workflows/pr-check-3.36.yml)

[![Docker Pulls](https://badgen.net/docker/pulls/miklosbagi/gluetrans?icon=docker&label=Docker%20Pulls)](https://hub.docker.com/r/miklosbagi/gluetrans/)

Gluetun VPN Peer Port updater for Transmission.
Supported providers:
- Private Internet Access
- ProtonVPN

Supported gluetun versions: v3.35, v3.36, v3.37

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
-e TRANSMISSION_ENDPOINT=http://transmission:9091/transmission/rpc \
-e TRANSMISSION_USER=transmission \
-e TRANSMISSION_PASS=transmission \
gluetrans:local
```

## Docker-compose example with gluetun + transmission + piavpn
Please note that `data` directory will be created if this gets executed as is.
Also, please note that we test against versions, not :latest, as that's like a weather report.

```
services:
  gluetun:
    image: qmcgaw/gluetun:v3.37.0
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
    restart: unless-stopped

  transmission:
    image: linuxserver/transmission:4.0.5
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

## Gluetun configuration for protonvpn example (for gluetun v3.36 and later please)
Please note that `data` directory will be created if this gets executed as is.
Also, please note that we test against versions, not :latest, as that's like a weather report.

```
services:
  gluetun:
    image: qmcgaw/gluetun:v3.37.0
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
    restart: unless-stopped

  transmission: ...same as with piavpn above...
  gluetrans: ....same as with piavpn above...
```

Please note that the above is example for piavpn. Nightly tests are running against protonvpn provider, feel free to take a look into the compose file in test for a working example.

## Debug
`docker logs -f gluetrans` should reveal what's happening.

### Ideal scenario
```
GlueTrans starting...
Oct 10 10:10:11 [gt] waiting for gluetun to become active...
Oct 10 10:10:17 [gt] gluetun is active, country details: "123.123.1.12,UK,Belgrade,CODE Test DataCenterHost Inc."
Oct 10 10:10:17 [gt] monitoring...
Oct 10 10:10:47 [gt] gluetun returned {"port":0}, retrying (1 / 15)...
Oct 10 10:11:17 [gt] tramsmission returned '', retrying (1/15)...
Oct 10 10:11:47 [gt] tramsmission returned '', retrying (2/15)...
Oct 10 10:12:18 [gt] tramsmission returned '', retrying (3/15)...
Oct 10 10:12:48 [gt] port change detected: gluetun is 12345, transmission is 0, updating...
Oct 10 10:12:54 [gt] success: transmission port updated successfully.
Oct 10 10:13:23 [gt] country jump timer: 14 minutes left on this server.
Oct 10 10:13:24 [gt] heartbeat: gluetun & transmission ports match (12345), Port is open: Yes
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
- If you see that the thirs server you'd expect is still not returning a valid peer port, please check the logs of gluetun, as it might be that the server is not healthy, or the port is not open. If it keeps returning 0 as port, please stop and start it again, there is a known bug
- You probably want to avoid running this against gluetun:latest in case you see one of the build checks marked as failing. Fixing to a specific known to work version is rarely a bad idea.
