#!/bin/bash
set -e

# Create credentials file from environment variable if it exists
if [ -n "$GOOGLE_CREDENTIALS_JSON" ]; then
    echo "Setting up Google Cloud credentials..."
    mkdir -p /tmp/secrets
    echo "$GOOGLE_CREDENTIALS_JSON" > /tmp/secrets/google-service-account.json
    export GOOGLE_APPLICATION_CREDENTIALS=/tmp/secrets/google-service-account.json
    echo "Google credentials configured at $GOOGLE_APPLICATION_CREDENTIALS"
fi

# Start the LiveKit agent
echo "Starting LiveKit agent..."
exec python -m app.agent.runner dev
