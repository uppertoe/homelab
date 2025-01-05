#!/bin/bash

#------------------------------------------------------------------------------
# Strict settings
#------------------------------------------------------------------------------
set -euo pipefail
IFS=$'\n\t'

#------------------------------------------------------------------------------
# Paths and environment
#------------------------------------------------------------------------------
export PATH="/usr/local/bin:/usr/bin:/bin"

# Resolve the project directory (two levels up from this script)
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env"

# Ensure .env exists
if [[ ! -f "$ENV_FILE" ]]; then
  echo "$(date) - ERROR: .env not found at $ENV_FILE" >&2
  exit 1
fi

# Load environment variables
source "$ENV_FILE"

# Validate required env vars
: "${DOCKER_CONFIG_PATH:?Environment variable DOCKER_CONFIG_PATH not set}"
: "${BASE_DOCKER_COMPOSE_YML:?Environment variable BASE_DOCKER_COMPOSE_YML not set}"

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------
GH_WATCH_DIR="$DOCKER_CONFIG_PATH/webhooks/triggers"
mkdir -p "$GH_WATCH_DIR"

DEPLOY_COMMAND="cd \"$PROJECT_DIR\" && git pull && docker compose -f \"$BASE_DOCKER_COMPOSE_YML\" up -d"

#------------------------------------------------------------------------------
# Logging
#------------------------------------------------------------------------------
LOGS_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOGS_DIR/deploy-trigger.log"
mkdir -p "$LOGS_DIR"

log() {
  echo "$(date): $1" >> "$LOG_FILE"
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------
if [[ -f "$GH_WATCH_DIR/pull.trigger" ]]; then
  log "Deployment trigger detected. Executing deployment."
  rm "$GH_WATCH_DIR/pull.trigger"
  
  if eval "$DEPLOY_COMMAND" >> "$LOG_FILE" 2>&1; then
    log "Deployment successful."
  else
    log "Deployment failed."
  fi
fi
