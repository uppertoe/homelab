#!/usr/bin/env bash

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"  # Up 2 levels
ENV_FILE="$PROJECT_DIR/.env"

source $ENV_FILE

WATCH_DIR="$PROJECT_DIR/$CONFIG/webhooks/triggers"
TRIGGER_FILE="pull.trigger"

inotifywait -m --event create --format '%f' "$WATCH_DIR" | while read NEW_FILE
do
    echo "[DEBUG] Detected file creation: $NEW_FILE"

    if [ "$NEW_FILE" = "$TRIGGER_FILE" ]; then
        echo "[INFO] Detected $TRIGGER_FILE. Pulling latest code and restarting containers..."
        
        cd "$PROJECT_DIR" || { echo "[ERROR] Failed to cd to $PROJECT_DIR"; exit 1; }
        
        # Execute git pull and docker compose
        git pull || { echo "[ERROR] git pull failed"; exit 1; }
        docker compose up -d || { echo "[ERROR] docker compose up failed"; exit 1; }
        
        # Remove the trigger file
        rm -f "$WATCH_DIR/$TRIGGER_FILE"
        echo "[INFO] Successfully pulled updates and restarted containers."
    fi
done
