#!/bin/bash

# -----------------------------------------------------------------------------
# Script Name: setup_cron.sh
# Description: Sets up a weekly cron job to update PROXY_COOKIE_ID and clean up
#              .tokens.bak files by running update_proxy_cookie_id.sh.
# -----------------------------------------------------------------------------

set -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Ensure necessary commands are available
if ! command_exists crontab; then
    echo "Error: crontab command not found. Please install cron utilities."
    exit 1
fi

# Path to the project directory
PROJECT_DIR=".."

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
: "${ROTATE_CREDS_CRON_SCHEDULE:?Environment variable CRON_SCHEDULE not set}"
: "${DOCKER_BIN:?Environment variable DOCKER_BIN not set}"
: "${BASE_DOCKER_COMPOSE_YML:?Environment variable BASE_DOCKER_COMPOSE_YML not set}"

# Set up logs
LOGS_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOGS_DIR"

# Verify that the logs directory was created
if [ ! -d "$LOGS_DIR" ]; then
    echo "$(date) - ERROR: Logs directory $LOGS_DIR was not created." >&2
    exit 1
fi

CRON_LOG_FILE="${LOGS_DIR}/update_proxy_cookie_id_cron.log"
SCRIPT_LOG_FILE="${LOGS_DIR}/update_proxy_cookie_id_deploy.log"

# Ensure the log files exist
touch "$CRON_LOG_FILE" "$SCRIPT_LOG_FILE"

# Set appropriate permissions
chmod 700 "$LOGS_DIR"
chmod 600 "$CRON_LOG_FILE" "$SCRIPT_LOG_FILE"

# Path to the update_proxy_cookie_id.sh script
UPDATE_SCRIPT="update_proxy_cookie_id.sh"

# Ensure the update script exists and is executable
if [ ! -f "$UPDATE_SCRIPT" ]; then
    echo "$(date) - ERROR: $UPDATE_SCRIPT does not exist. Please ensure the script is in the correct location." >> "$SCRIPT_LOG_FILE"
    exit 1
fi

if [ ! -x "$UPDATE_SCRIPT" ]; then
    echo "$(date) - INFO: Making $UPDATE_SCRIPT executable." >> "$SCRIPT_LOG_FILE"
    chmod +x "$UPDATE_SCRIPT"
fi

# Resolve absolute paths
ABS_UPDATE_SCRIPT=$(readlink -f "$UPDATE_SCRIPT" || true)
ABS_DOCKER_BIN=$(readlink -f "$DOCKER_BIN" || true)
ABS_BASE_DOCKER_COMPOSE_YML=$(readlink -f "$PROJECT_DIR/$BASE_DOCKER_COMPOSE_YML" || true)
ABS_CRON_LOG_FILE=$(readlink -f "$CRON_LOG_FILE" || true)

# Verify that readlink worked
if [ -z "$ABS_UPDATE_SCRIPT" ] || [ -z "$ABS_DOCKER_BIN" ] || [ -z "$ABS_BASE_DOCKER_COMPOSE_YML" ]; then
    echo "$(date) - ERROR: Failed to resolve absolute paths." >> "$SCRIPT_LOG_FILE"
    exit 1
fi

# Ensure Docker executable is valid
if [ ! -x "$ABS_DOCKER_BIN" ]; then
    echo "$(date) - ERROR: Docker executable not found or not executable at $ABS_DOCKER_BIN" >> "$SCRIPT_LOG_FILE"
    exit 1
fi

# Ensure docker-compose.yml exists
if [ ! -f "$ABS_BASE_DOCKER_COMPOSE_YML" ]; then
    echo "$(date) - ERROR: Docker Compose YAML file not found at $ABS_BASE_DOCKER_COMPOSE_YML" >> "$SCRIPT_LOG_FILE"
    exit 1
fi

# Construct the cron job command
CRON_COMMAND_ROTATE_CADDY_CREDS="$ROTATE_CREDS_CRON_SCHEDULE /bin/bash $ABS_UPDATE_SCRIPT && $ABS_DOCKER_BIN compose -f $ABS_BASE_DOCKER_COMPOSE_YML up -d caddy >> $ABS_CRON_LOG_FILE 2>&1"

# Check if the cron job already exists
(crontab -l 2>/dev/null | grep -F "$ABS_UPDATE_SCRIPT") && EXISTS=true || EXISTS=false

if [ "$EXISTS" = true ]; then
    echo "$(date) - Cron job already exists. No changes made." >> "$SCRIPT_LOG_FILE"
else
    # Add the cron job
    (crontab -l 2>/dev/null; echo "$CRON_COMMAND_ROTATE_CADDY_CREDS") | crontab -
    echo "$(date) - Cron job added successfully:" >> "$SCRIPT_LOG_FILE"
    echo "$CRON_COMMAND_ROTATE_CADDY_CREDS" >> "$SCRIPT_LOG_FILE"
fi

echo "$(date) - Setup complete." >> "$SCRIPT_LOG_FILE"
