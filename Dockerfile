# Use Alpine Linux as the base image
FROM alpine:3.23.3

# Runtime configuration is via environment variables only (do not bake ENV placeholders
# here — empty keys from build-time $VAR expansion show up in `docker exec … env`; see #88).

# install packages
# hadolint ignore=DL3018
RUN apk add --no-cache transmission-remote jq bash curl

# copy script to container
COPY entrypoint.sh /entrypoint.sh

# Make the script executable
RUN chmod +x /entrypoint.sh

# Bash as PID 1 runs entrypoint in-process so unset removes secrets from init environ.
# See issue #88; `docker exec … env` may still replay create-time `-e` secrets unless
# you use *_FILE env vars (no secret values in container config).
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
