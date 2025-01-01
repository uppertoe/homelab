#!/bin/bash

# -----------------------------------------------------------------------------
# Script Name: setup_cron.sh
# Description: Sets up a weekly cron job to update PROXY_COOKIE_ID and clean up
#              .tokens.bak files by running update_proxy_cookie_id.sh.
# -----------------------------------------------------------------------------

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Ensure necessary commands are available
if ! command_exists crontab; then
    echo "Error: crontab command not found. Please install cron utilities."
    exit 1
fi

# Path to the update_proxy_cookie_id.sh script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATE_SCRIPT="${SCRIPT_DIR}/update_proxy_cookie_id.sh"

# Ensure the update script exists
if [ ! -f "$UPDATE_SCRIPT" ]; then
    echo "Error: $UPDATE_SCRIPT does not exist. Please ensure the script is in the correct location."
    exit 1
fi

# Absolute path to the update script
ABS_UPDATE_SCRIPT=$(readlink -f "$UPDATE_SCRIPT")

# Log file path
LOG_FILE="${SCRIPT_DIR}/update_proxy_cookie_id_cron.log"

# Cron job schedule: Every Sunday at 3:00 AM
CRON_SCHEDULE="0 3 * * 0"

# Cron job command
CRON_COMMAND="$CRON_SCHEDULE $ABS_UPDATE_SCRIPT >> $LOG_FILE 2>&1"

# Check if the cron job already exists
(crontab -l | grep -F "$ABS_UPDATE_SCRIPT") && EXISTS=true || EXISTS=false

if [ "$EXISTS" = true ]; then
    echo "Cron job already exists. No changes made."
else
    # Add the cron job
    (crontab -l 2>/dev/null; echo "$CRON_COMMAND") | crontab -
    echo "Cron job added successfully:"
    echo "$CRON_COMMAND"
fi

echo "Setup complete."
