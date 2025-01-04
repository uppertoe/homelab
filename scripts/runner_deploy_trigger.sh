#!/bin/bash

# Enable strict modes
set -euo pipefail
IFS=$'\n\t'

# Set PATH to include directories where docker-compose is located
export PATH="/usr/local/bin:/usr/bin:/bin"

# Path to the project directory
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# Path to the .env file (one level up from SCRIPTS)
ENV_FILE="$PROJECT_DIR/.env"

# Verify that the .env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo "$(date) - ERROR: .env file not found at $ENV_FILE" >&2
    exit 1
fi

# Source the .env file
source "$ENV_FILE"

# Verify that required variables are set
: "${DOCKER_CONFIG_PATH:?Environment variable DOCKER_CONFIG_PATH not set}"
: "${BASE_DOCKER_COMPOSE_YML:?Environment variable BASE_DOCKER_COMPOSE_YML not set}"

GH_RUNNER_WATCH_DIR=$DOCKER_CONFIG_PATH/github-runner
mkdir -p $GH_RUNNER_WATCH_DIR
ABS_BASE_DOCKER_COMPOSE_YML=$(readlink -f "$PROJECT_DIR/$BASE_DOCKER_COMPOSE_YML" || true)

# Configuration
DEPLOY_COMMAND="docker compose -f $ABS_BASE_DOCKER_COMPOSE_YML pull && docker compose -f $ABS_BASE_DOCKER_COMPOSE_YML up -d"

# Setup logs
LOGS_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOGS_DIR"
LOG_FILE="$LOGS_DIR/deploy-trigger.log"

# Function to log messages
log() {
    echo "$(date): $1" >> "$LOG_FILE"
}

# Check if deploy.trigger exists
if [ -f "$GH_RUNNER_WATCH_DIR/deploy.trigger" ]; then
    log "Deployment trigger detected. Executing deployment."

    # Execute deployment commands
    if eval "$DEPLOY_COMMAND" >> "$LOG_FILE" 2>&1; then
        log "Deployment successful."
    else
        log "Deployment failed."
    fi

    # Remove the trigger file
    rm "$GH_RUNNER_WATCH_DIR/deploy.trigger"
fi
