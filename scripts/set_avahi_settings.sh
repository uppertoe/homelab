#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Define variables
CONFIG_FILE="/etc/avahi/avahi-daemon.conf"
BACKUP_FILE="/etc/avahi/avahi-daemon.conf.bak_$(date +%F_%T)"
SERVICE_NAME="avahi-daemon"

# Function to check if a line exists in the file
line_exists() {
    grep -Fxq "$1" "$CONFIG_FILE"
}

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or use sudo."
    exit 1
fi

# Create a backup of the original configuration file
echo "Creating a backup of the original configuration file at $BACKUP_FILE"
cp "$CONFIG_FILE" "$BACKUP_FILE"

# Initialize a flag to determine if changes are made
CHANGED=0

# Function to uncomment and set a configuration option
uncomment_and_set() {
    local option="$1"
    local value="$2"
    
    if grep -q "^[#]*\s*$option\s*=" "$CONFIG_FILE"; then
        # Uncomment the line and set the value
        sed -i "s/^[#]*\s*$option\s*=.*/$option=$value/" "$CONFIG_FILE"
        echo "Set $option to $value"
        CHANGED=1
    elif grep -q "^\s*$option\s*=" "$CONFIG_FILE"; then
        # Option exists but is already uncommented; set the value
        sed -i "s|^\s*$option\s*=.*|$option=$value|" "$CONFIG_FILE"
        echo "Updated $option to $value"
        CHANGED=1
    else
        # Option does not exist; append it
        echo "$option=$value" >> "$CONFIG_FILE"
        echo "Added $option=$value"
        CHANGED=1
    fi
}

# Ensure the [reflector] section exists
if ! grep -q "^\[reflector\]" "$CONFIG_FILE"; then
    echo "Adding [reflector] section to the configuration file."
    echo -e "\n[reflector]" >> "$CONFIG_FILE"
    CHANGED=1
fi

# Uncomment and set enable-reflector=yes
uncomment_and_set "enable-reflector" "yes"

# Uncomment and set reflect-ipv=no
uncomment_and_set "reflect-ipv" "no"

# Restart the avahi-daemon service if changes were made
if [ "$CHANGED" -eq 1 ]; then
    echo "Restarting $SERVICE_NAME service to apply changes."
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        systemctl restart "$SERVICE_NAME"
    else
        service "$SERVICE_NAME" restart
    fi
    echo "Service restarted successfully."
else
    echo "No changes were made to the configuration file. Service restart not required."
fi

echo "Configuration update completed."
