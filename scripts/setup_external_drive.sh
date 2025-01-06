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

# Function to list available drives and partitions
list_drives() {
    echo "Available Drives and Partitions:"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
}

# Function to prompt user to select a partition
select_partition() {
    echo "Select a partition to mount (e.g., sda2, sdb1):"
    read -rp "Enter partition name (without /dev/): " PARTITION

    # Validate input format
    if [[ ! "$PARTITION" =~ ^[a-z]+[0-9]+$ ]]; then
        echo "Invalid partition format. Please try again."
        select_partition
    fi

    SELECTED_PARTITION="/dev/$PARTITION"

    # Check if the partition exists
    if [ ! -b "$SELECTED_PARTITION" ]; then
        echo "Partition $SELECTED_PARTITION does not exist. Please try again."
        select_partition
    fi

    echo "You selected: $SELECTED_PARTITION"
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

# Function to check and optionally format the partition to ext4
check_and_format_partition() {
    CURRENT_FS=$(lsblk -no FSTYPE "$SELECTED_PARTITION")

    if [ "$CURRENT_FS" != "ext4" ]; then
        echo "Current filesystem on $SELECTED_PARTITION is $CURRENT_FS."
        echo "Recommended filesystem: ext4 for Linux compatibility and Docker integration."

        read -p "Do you want to format $SELECTED_PARTITION to ext4? This will erase all data on the partition. (y/n): " format_choice

        case "$format_choice" in
            [Yy]* )
                echo "Formatting $SELECTED_PARTITION to ext4..."
                sudo mkfs.ext4 "$SELECTED_PARTITION"
                echo "Formatting completed."
                ;;
            [Nn]* )
                echo "Skipping formatting. Attempting to mount with existing filesystem."
                ;;
            * )
                echo "Invalid choice. Please enter y or n."
                check_and_format_partition
                ;;
        esac
    else
        echo "Partition $SELECTED_PARTITION is already formatted as ext4."
    fi
}

# Function to mount the partition
mount_partition() {
    echo "Mounting $SELECTED_PARTITION to $MOUNT_POINT..."
    sudo mount "$SELECTED_PARTITION" "$MOUNT_POINT"

    # Get filesystem type after mounting
    FSTYPE=$(lsblk -no FSTYPE "$SELECTED_PARTITION")
    if [ -z "$FSTYPE" ]; then
        echo "Unable to determine filesystem type. Please ensure the partition is formatted."
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

    echo "Creating target directory if it doesn't exist..."
    sudo mkdir -p "$TARGET_DIR"

    echo "Creating bind mount for $LOCAL_DIR..."
    sudo mount --bind "$DIR_ON_DRIVE" "$TARGET_DIR"

    # Add bind mount to /etc/fstab for persistence
    if ! grep -qs "$DIR_ON_DRIVE $TARGET_DIR none bind" /etc/fstab; then
        echo "$DIR_ON_DRIVE $TARGET_DIR none bind 0 0" | sudo tee -a /etc/fstab
    else
        echo "Bind mount for $TARGET_DIR already exists in /etc/fstab. Skipping."
    fi
}

# Function to set permissions for a directory on the drive
set_permissions() {
    DIRECTORY="$1"  # e.g., $CONFIG_DIR_ON_DRIVE or $DATA_DIR_ON_DRIVE
    echo "Setting ownership to $ORIGINAL_USER:$ORIGINAL_USER for $DIRECTORY..."
    sudo chown -R "$ORIGINAL_USER":"$ORIGINAL_USER" "$DIRECTORY"

    echo "Setting permissions to 755 for directories and 644 for files in $DIRECTORY..."
    sudo find "$DIRECTORY" -type d -exec chmod 755 {} \;
    sudo find "$DIRECTORY" -type f -exec chmod 644 {} \;
}

# Function to update /etc/fstab for the main mount
update_fstab_main_mount() {
    echo "Updating /etc/fstab to ensure persistence on startup for the main mount..."

    UUID=$(blkid -s UUID -o value "$SELECTED_PARTITION")
    if [ -z "$UUID" ]; then
        echo "Unable to retrieve UUID for $SELECTED_PARTITION. Exiting."
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

    # Check if the main mount is already in fstab
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
select_partition
check_and_format_partition
determine_mount_point
mount_partition

# Update /etc/fstab for the main mount
update_fstab_main_mount

# Bind homelab/config
bind_directory "homelab/config" "$CONFIG_DIR"
# Set permissions for homelab/config
CONFIG_DIR_ON_DRIVE="$MOUNT_POINT/homelab/config"
set_permissions "$CONFIG_DIR_ON_DRIVE"

# Bind homelab/data
bind_directory "homelab/data" "$DATA_DIR"
# Set permissions for homelab/data
DATA_DIR_ON_DRIVE="$MOUNT_POINT/homelab/data"
set_permissions "$DATA_DIR_ON_DRIVE"

echo "===== Setup Completed Successfully! ====="
echo "Partition $SELECTED_PARTITION is mounted at $MOUNT_POINT."
echo "~/homelab/config is bind-mounted to $CONFIG_DIR_ON_DRIVE."
echo "~/homelab/data is bind-mounted to $DATA_DIR_ON_DRIVE."
