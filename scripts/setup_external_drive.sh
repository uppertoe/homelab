#!/bin/bash

# Exit immediately if a command exits with a non-zero status
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

# Validate that CONFIG and DATA variables are set
if [ -z "$CONFIG" ] || [ -z "$DATA" ]; then
    echo "ERROR: CONFIG and DATA variables must be defined in the .env file." >&2
    exit 1
fi

CONFIG_DIR="$PROJECT_DIR/$CONFIG"
DATA_DIR="$PROJECT_DIR/$DATA"

# Determine the original user (the one who invoked sudo)
if [ -n "$SUDO_USER" ]; then
    ORIGINAL_USER="$SUDO_USER"
else
    ORIGINAL_USER="$USER"
fi

# Function to list available drives
list_drives() {
    echo "Available Drives:"
    # List drives excluding the root filesystem
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E 'disk|part' | grep -v "$(df / | tail -1 | awk '{print $1}')"
}

# Function to prompt user to select a drive
select_drive() {
    drives=($(lsblk -dn -o NAME,TYPE | grep disk | awk '{print $1}'))
    if [ ${#drives[@]} -eq 0 ]; then
        echo "No available drives found."
        exit 1
    fi

    echo "Select a drive to mount:"
    select drive in "${drives[@]}"; do
        if [[ -n "$drive" ]]; then
            echo "You selected: /dev/$drive"
            SELECTED_DRIVE="/dev/$drive"
            break
        else
            echo "Invalid selection."
        fi
    done
}

# Function to determine or create a mount point
determine_mount_point() {
    DEFAULT_MOUNT_POINT="/mnt/homelab"
    read -p "Enter mount point [Default: $DEFAULT_MOUNT_POINT]: " INPUT_MOUNT_POINT
    MOUNT_POINT="${INPUT_MOUNT_POINT:-$DEFAULT_MOUNT_POINT}"

    # Check if the mount point is already in use
    if mount | grep "on $MOUNT_POINT " > /dev/null; then
        echo "Mount point $MOUNT_POINT is already in use."
        read -p "Do you want to use a different mount point? (y/n): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            determine_mount_point  # Recursively prompt again
        else
            echo "Exiting to avoid mount conflicts."
            exit 1
        fi
    fi

    # Create the mount point directory if it doesn't exist
    if [ ! -d "$MOUNT_POINT" ]; then
        echo "Creating mount point at $MOUNT_POINT..."
        sudo mkdir -p "$MOUNT_POINT"
    else
        echo "Mount point $MOUNT_POINT already exists."
    fi
}

# Function to mount the drive
mount_drive() {
    echo "Mounting $SELECTED_DRIVE to $MOUNT_POINT..."
    sudo mount "$SELECTED_DRIVE" "$MOUNT_POINT"

    # Get filesystem type
    FSTYPE=$(lsblk -no FSTYPE "$SELECTED_DRIVE")
    if [ -z "$FSTYPE" ]; then
        echo "Unable to determine filesystem type. Please ensure the drive is formatted."
        exit 1
    fi
}

# Function to bind a directory (config or data)
bind_directory() {
    LOCAL_DIR="$1"         # e.g., homelab/config
    TARGET_DIR="$2"        # e.g., $CONFIG_DIR or $DATA_DIR
    DIR_ON_DRIVE="$MOUNT_POINT/$LOCAL_DIR"

    echo "Creating $LOCAL_DIR directory on the drive..."
    sudo mkdir -p "$DIR_ON_DRIVE"

    echo "Backing up existing $LOCAL_DIR directory (if any)..."
    if [ -d "$TARGET_DIR" ]; then
        sudo mv "$TARGET_DIR" "${TARGET_DIR}.backup_$(date +%s)"
    fi

    echo "Creating symbolic link for $LOCAL_DIR..."
    ln -s "$DIR_ON_DRIVE" "$TARGET_DIR"
}

# Function to set permissions for a directory on the drive
set_permissions() {
    DIRECTORY="$1"  # e.g., $CONFIG_DIR_ON_DRIVE or $DATA_DIR_ON_DRIVE
    echo "Setting ownership to $ORIGINAL_USER:$ORIGINAL_USER for $DIRECTORY..."
    sudo chown -R "$ORIGINAL_USER":"$ORIGINAL_USER" "$DIRECTORY"

    echo "Setting permissions to 755 for directories and 644 for files in $DIRECTORY..."
    find "$DIRECTORY" -type d -exec sudo chmod 755 {} \;
    find "$DIRECTORY" -type f -exec sudo chmod 644 {} \;
}

# Function to update /etc/fstab
update_fstab() {
    echo "Updating /etc/fstab to ensure persistence on startup..."

    UUID=$(blkid -s UUID -o value "$SELECTED_DRIVE")
    if [ -z "$UUID" ]; then
        echo "Unable to retrieve UUID for $SELECTED_DRIVE. Exiting."
        exit 1
    fi

    # Determine mount options based on filesystem type
    case "$FSTYPE" in
        ext4|ext3|ext2)
            OPTIONS="defaults"
            ;;
        ntfs)
            OPTIONS="defaults,uid=$(id -u "$ORIGINAL_USER"),gid=$(id -g "$ORIGINAL_USER")"
            ;;
        vfat|fat32)
            OPTIONS="defaults,uid=$(id -u "$ORIGINAL_USER"),gid=$(id -g "$ORIGINAL_USER"),umask=022"
            ;;
        *)
            OPTIONS="defaults"
            ;;
    esac

    # Check if the mount point is already in fstab
    if grep -qs "UUID=$UUID" /etc/fstab; then
        echo "An entry for UUID=$UUID already exists in /etc/fstab. Skipping."
    else
        echo "Adding entry to /etc/fstab..."
        echo "UUID=$UUID $MOUNT_POINT $FSTYPE $OPTIONS 0 2" | sudo tee -a /etc/fstab
    fi
}

# Main Script Execution
echo "===== Homelab Mount Setup Script ====="

list_drives
select_drive
determine_mount_point
mount_drive

# Bind homelab/config
bind_directory "homelab/config" "$CONFIG_DIR"
# Set permissions for homelab/config
CONFIG_DIR_ON_DRIVE="$MOUNT_POINT/homelab/config"
set_permissions "$CONFIG_DIR_ON_DRIVE"

# Bind homelab/data
bind_directory "homelab/data" "$DATA_DIR"
# Set permissions for homelab/data
DATA_DIR_ON_DRIVE="$MOUNT_point/homelab/data"
set_permissions "$DATA_DIR_ON_DRIVE"

update_fstab

echo "===== Setup Completed Successfully! ====="
echo "Drive $SELECTED_DRIVE is mounted at $MOUNT_POINT."
echo "~/homelab/config is linked to $CONFIG_DIR_ON_DRIVE."
echo "~/homelab/data is linked to $DATA_DIR_ON_DRIVE."
