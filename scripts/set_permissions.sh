#!/bin/bash

# Exit if any command fails
set -e

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

echo "Setting up project folders and permissions"
CONFIG_DIR="$PROJECT_DIR/$CONFIG"
DATA_DIR="$PROJECT_DIR/$DATA"
mkdir -p $CONFIG_DIR $DATA_DIR
sudo chown -R $USER:$USER $PROJECT_DIR

echo "Permissions applied successfully"