#!/usr/bin/env bash

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"  # Up 2 levels
ENV_FILE="$PROJECT_DIR/.env"

source $ENV_FILE

WATCH_DIR="$PROJECT_DIR/$CONFIG/webhooks/triggers"
TRIGGER_FILE="pull.trigger"

inotifywait -m --event create --format '%f' "$WATCH_DIR" | while read NEW_FILE
do
    if [ "$NEW_FILE" = "$TRIGGER_FILE" ]; then
        echo "[INFO] Detected $TRIGGER_FILE. Pulling latest code and restarting containers..."
        
        cd "$PROJECT_DIR" || exit 1
        
        # Run the commands you need
        git pull
        docker compose up -d
        
        # Optionally remove the trigger file (if you only want it triggered once)
        rm -f "$WATCH_DIR/$TRIGGER_FILE"
    fi
done
