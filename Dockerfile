# Use Alpine Linux as the base image
FROM alpine:3.23.3

# required env vars
ENV GLUETUN_ENDPOINT=$GLUETUN_ENDPOINT
ENV TRANSMISSION_ENDPOINT=$TRANSMISSION_ENDPOINT
ENV TRANSMISSION_USER=$TRANSMISSION_USER
ENV TRANSMISSION_PASS=$TRANSMISSION_PASS
ENV PEERPORT_CHECK_INTERVAL=$PEERPORT_CHECK_INTERVAL

# install packages
# hadolint ignore=DL3018
RUN apk add --no-cache transmission-remote jq bash curl

# copy script to container
COPY entrypoint.sh /entrypoint.sh

# Make the script executable
RUN chmod +x /entrypoint.sh

# Run the script when the container starts
CMD ["sh", "-c", "echo 'GlueTrans starting...'; sleep 5; /entrypoint.sh"]
