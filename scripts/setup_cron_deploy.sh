#!/bin/bash

# -----------------------------------------------------------------------------
# Script Name: setup_cron_deploy.sh
# Description: Sets up a minutely cron job to see if the Github Runner has set the deploy trigger
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
: "${DEPLOY_TRIGGER_CRON_SCHEDULE:?Environment variable CRON_SCHEDULE not set}"

# Set up logs
LOGS_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOGS_DIR"

# Verify that the logs directory was created
if [ ! -d "$LOGS_DIR" ]; then
    echo "$(date) - ERROR: Logs directory $LOGS_DIR was not created." >&2
    exit 1
fi

CRON_LOG_FILE="${LOGS_DIR}/runner_deploy_trigger_cron.log"
SCRIPT_LOG_FILE="${LOGS_DIR}/runner_deploy_trigger.log"

# Ensure the log files exist
touch "$CRON_LOG_FILE" "$SCRIPT_LOG_FILE"

# Set appropriate permissions
chmod 700 "$LOGS_DIR"
chmod 600 "$CRON_LOG_FILE" "$SCRIPT_LOG_FILE"

# Path to the script
DEPLOY_SCRIPT="runner_deploy_trigger.sh"

# Ensure the update script exists and is executable
if [ ! -f "$DEPLOY_SCRIPT" ]; then
    echo "$(date) - ERROR: $DEPLOY_SCRIPT does not exist. Please ensure the script is in the correct location." >> "$SCRIPT_LOG_FILE"
    exit 1
fi

if [ ! -x "$DEPLOY_SCRIPT" ]; then
    echo "$(date) - INFO: Making $DEPLOY_SCRIPT executable." >> "$SCRIPT_LOG_FILE"
    chmod +x "$DEPLOY_SCRIPT"
fi

# Resolve absolute paths
ABS_DEPLOY_SCRIPT=$(readlink -f "$DEPLOY_SCRIPT" || true)
ABS_CRON_LOG_FILE=$(readlink -f "$CRON_LOG_FILE" || true)

# Verify that readlink worked
if [ -z "$ABS_DEPLOY_SCRIPT" ]; then
    echo "$(date) - ERROR: Failed to resolve absolute paths." >> "$SCRIPT_LOG_FILE"
    exit 1
fi

# Construct the cron job command
CRON_COMMAND_DEPLOY_TRIGGER="$DEPLOY_TRIGGER_CRON_SCHEDULE /bin/bash $ABS_DEPLOY_SCRIPT >> $ABS_CRON_LOG_FILE 2>&1"

# Check if the cron job already exists
(crontab -l 2>/dev/null | grep -F "$ABS_DEPLOY_SCRIPT") && EXISTS=true || EXISTS=false

if [ "$EXISTS" = true ]; then
    echo "$(date) - Cron job already exists. No changes made." >> "$SCRIPT_LOG_FILE"
else
    # Add the cron job
    (crontab -l 2>/dev/null; echo "$CRON_COMMAND_DEPLOY_TRIGGER") | crontab -
    echo "$(date) - Cron job added successfully:" >> "$SCRIPT_LOG_FILE"
    echo "$CRON_COMMAND_DEPLOY_TRIGGER" >> "$SCRIPT_LOG_FILE"
fi

echo "$(date) - Setup complete." >> "$SCRIPT_LOG_FILE"
