#!/bin/bash
set -e

# Create credentials file from environment variable if it exists
if [ -n "$GOOGLE_CREDENTIALS_JSON" ]; then
    echo "Setting up Google Cloud credentials..."
    mkdir -p /etc/secrets
    echo "$GOOGLE_CREDENTIALS_JSON" > /etc/secrets/google-service-account.json
    export GOOGLE_APPLICATION_CREDENTIALS=/etc/secrets/google-service-account.json
    echo "Google credentials configured"
fi

# Start the FastAPI application
echo "Starting FastAPI application..."
exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-10000}
