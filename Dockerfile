# Use Alpine Linux as the base image
FROM alpine:latest

# Env vars
ENV GLUETUN_ENDPOINT=$GLUETUN_ENDPOINT
ENV TRANSMISSION_ENDPOINT=$TRANSMISSION_ENDPOINT
ENV TRANSMISSION_USER=$TRANSMISSION_USER
ENV TRANSMISSION_PASS=$TRANSMISSION_PASS
ENV PEERPORT_CHECK_INTERVAL=$PEERPORT_CHECK_INTERVAL

# Install necessary packages
RUN apk add --no-cache transmission-cli jq bash curl

# Copy the script into the container
COPY entrypoint.sh /entrypoint.sh

# Make the script executable
RUN chmod +x /entrypoint.sh

# Run the script when the container starts
CMD ["sh", "-c", "echo 'GlueTransPIA starting...'; sleep 15; /entrypoint.sh"]
# CMD ["sleep", "3600"]