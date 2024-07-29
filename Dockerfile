# Use Alpine Linux as the base image
FROM alpine:3.20.2

# required env vars
ENV GLUETUN_ENDPOINT=$GLUETUN_ENDPOINT
ENV TRANSMISSION_ENDPOINT=$TRANSMISSION_ENDPOINT
ENV TRANSMISSION_USER=$TRANSMISSION_USER
ENV TRANSMISSION_PASS=$TRANSMISSION_PASS
ENV PEERPORT_CHECK_INTERVAL=$PEERPORT_CHECK_INTERVAL

# install packages
RUN apk add --no-cache transmission-remote=4.0.5-r2 jq=1.7.1-r0 bash=5.2.26-r0 curl=8.9.0-r0

# copy script to container
COPY entrypoint.sh /entrypoint.sh

# Make the script executable
RUN chmod +x /entrypoint.sh

# Run the script when the container starts
CMD ["sh", "-c", "echo 'GlueTrans starting...'; sleep 5; /entrypoint.sh"]
