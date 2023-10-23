# Use Alpine Linux as the base image
FROM alpine:3.18

# Env vars
ENV GLUETUN_ENDPOINT=$GLUETUN_ENDPOINT
ENV TRANSMISSION_ENDPOINT=$TRANSMISSION_ENDPOINT
ENV TRANSMISSION_USER=$TRANSMISSION_USER
ENV TRANSMISSION_PASS=$TRANSMISSION_PASS
ENV PEERPORT_CHECK_INTERVAL=$PEERPORT_CHECK_INTERVAL

# Install necessary packages
RUN apk add --no-cache transmission-cli=4.0.4-r0 jq=1.6-r3 bash=5.2.15-r5 curl=8.4.0-r0

# Copy the script into the container
COPY entrypoint.sh /entrypoint.sh

# Make the script executable
RUN chmod +x /entrypoint.sh

# Run the script when the container starts
CMD ["sh", "-c", "echo 'GlueTransPIA starting...'; sleep 15; /entrypoint.sh"]
# CMD ["sleep", "3600"]