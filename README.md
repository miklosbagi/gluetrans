# GlueTransPIA Peer Port updater
The Glue between Gluetun, Transmission and PIA-VPN.  
This is docker image that checks gluetun's PIAVPN Peer Port periodically, and updates Transmission when it changes. The idea is to run this as a third container between thess two.

## Please note that this is not fully operational yet, it's a work in progress.

## Environment variables
Mandatory:
- `GLUETUN_CONTROL_ENDPOINT`: Full Control Server URL with port, e.g.: `http://gluetun:8000`
- `GLUETUN_HEALTH_ENDPOINT`: Full Health URL with port, `http://gluetun:9999` by default
- `TRANSMISSION_ENDPOINT` : Full Transmission RPC URL with port, service path, e.g.: `http://transmission:9091/transmission/rpc`
- `TRANSMISSION_USER`: Username for transmission RPC auth
- `TRANSMISSION_PASS`: Password for transmission RPC auth

Optional:
- `PEERPORT_CHECK_INTERVAL`: 30 # optional, default: 15, in seconds
- `GLUETUN_PICK_NEW_SERVER_AFTER`: 15 # optional, default: 10, in number of retries

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
miklosbagi/gluetranspia:dev
```

## Docker build for local testing
- Clone this repo, and `cd` into it
- If this is not the first time you build, remove the old image with `docker rmi gluetranspia:local`
- Build the image with `docker build -t gluetranspia:local .`
- Run with:
```
docker run \
-e GLUETUN_CONTROL_ENDPOINT=http://gluetun:8000 \
-e GLUETUN_HEALTH_ENDPOINT=http://gluetun:8080 \
-e TRANSMISSION_ENDPOINT=http://transmission:9091/transmission/rpc \
-e TRANSMISSION_USER=transmission \
-e TRANSMISSION_PASS=transmission \
gluetranspia:local
```

## Docker-compose example with gluetun + transmission
Please note that `data` directory will be created if this gets executed as is.
Also, please note that we test against versions, not :latest, as that's like a weather report.

```
services:
  gluetun:
    image: qmcgaw/gluetun:v3.35.0
    volumes:
      - ./data/gluetun:/gluetun
    cap_add:
      - NET_ADMIN
    ports:
      - 8000:8000 # Control server
      - 9091:9091 # Transmission UI
    environment:
      VPN_SERVICE_PROVIDER: "private internet access"
      OPENVPN_USER: My PIA Username
      OPENVPN_PASSWORD: My PIA Password
      SERVER_REGIONS: "FI Helsinki,France,Norway,SE Stockholm,Serbia"
      VPN_PORT_FORWARDING: on
      VPN_PORT_FORWARDING_PROVIDER: "private internet access"
    restart: unless-stopped

  transmission:
    image: linuxserver/transmission:4.0.4
    environment:
      USER: My Transmission Username
      PASS: My Transmission Password
      #PEERPORT: # this is what we do here, so skip it.

    volumes:
      - ./data/transmission:/config
      - ./data/transmissino_downloads:/downloads
    network_mode: "service:gluetun" # go through gluetun's VPN
    restart: unless-stopped
    depends_on:
      - gluetun

  gluetranspia:
    image: miklosbagi/gluetranspia:dev
    environment:
      GLUETUN_CONTROL_ENDPOINT: http://localhost:8000
      GLUETUN_HEALTH_ENDPOINT: http://localhost:9999
      TRANSMISSION_ENDPOINT: http://localhost:9091/transmission/rpc
      TRANSMISSION_USER: My Transmission Username
      TRANSMISSION_PASS: My Transmission Password
      PEERPORT_CHECK_INTERVAL: 30 # optional, default: 15, in seconds
      GLUETUN_PICK_NEW_SERVER_AFTER: 15 # optional, default: 10, in number of retries
    network_mode: "service:gluetun" # go through gluetun's VPN
    depends_on:
      - gluetun
```

## Debug
`docker logs -f gluetranspia` should reveal what's happening.

## Known issues
- Transmission w/o RPC auth is not supported