#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Configuration parameters
GITHUB_URL="https://github.com/${GH_RUNNER_REPO}"
RUNNER_TOKEN=${GH_RUNNER_CONFIG_TOKEN}

# Validate required environment variables
if [ -z "$GITHUB_URL" ] || [ -z "$RUNNER_TOKEN" ]; then
    echo "Error: GH_RUNNER_REPO and GH_RUNNER_CONFIG_TOKEN must be set."
    exit 1
fi

# Configure the runner
./config.sh \
    --url "$GITHUB_URL" \
    --token "$RUNNER_TOKEN" \
    --name "$RUNNER_NAME" \
    --labels "$RUNNER_LABELS" \
    --work "$RUNNER_WORKDIR" \
    --unattended \
    --replace

# Trap SIGTERM and SIGINT to gracefully stop the runner
trap './svc.sh stop; exit 0' SIGTERM SIGINT

# Start the runner
./run.sh
