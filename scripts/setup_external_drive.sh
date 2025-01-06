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

# Determine the original user (the one running the script)
ORIGINAL_USER="$USER"

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
    read -rp "Enter mount point [Default: $DEFAULT_MOUNT_POINT]: " INPUT_MOUNT_POINT
    MOUNT_POINT="${INPUT_MOUNT_POINT:-$DEFAULT_MOUNT_POINT}"

    # Check if the mount point is already in use
    if mountpoint -q "$MOUNT_POINT"; then
        CURRENT_MOUNTED_PARTITION=$(findmnt -no SOURCE --target "$MOUNT_POINT")
        
        if [ "$CURRENT_MOUNTED_PARTITION" == "$SELECTED_PARTITION" ]; then
            echo "Partition $SELECTED_PARTITION is already mounted at $MOUNT_POINT."
            read -rp "Do you want to unmount it and proceed with the setup? (y/n): " choice
            case "$choice" in
                [Yy]* )
                    echo "Unmounting $SELECTED_PARTITION from $MOUNT_POINT..."
                    sudo umount "$MOUNT_POINT"
                    echo "Successfully unmounted $SELECTED_PARTITION from $MOUNT_POINT."
                    ;;
                [Nn]* )
                    echo "Exiting to avoid mount conflicts."
                    exit 1
                    ;;
                * )
                    echo "Invalid choice. Please enter y or n."
                    determine_mount_point  # Recursively prompt again
                    ;;
            esac
        else
            echo "Mount point $MOUNT_POINT is already in use by $CURRENT_MOUNTED_PARTITION."
            read -rp "Do you want to use a different mount point? (y/n): " choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                determine_mount_point  # Recursively prompt again
            else
                echo "Exiting to avoid mount conflicts."
                exit 1
            fi
        fi
    fi

    # Create the mount point directory if it doesn't exist
    if [ ! -d "$MOUNT_POINT" ]; then
        echo "Creating mount point at $MOUNT_POINT..."
        sudo mkdir -p "$MOUNT_POINT"
        sudo chown "$ORIGINAL_USER":"$ORIGINAL_USER" "$MOUNT_POINT"
        echo "Mount point created and ownership set to $ORIGINAL_USER."
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

        read -rp "Do you want to format $SELECTED_PARTITION to ext4? This will erase all data on the partition. (y/n): " format_choice

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

# Function to unmount the selected partition if it's already mounted
unmount_partition() {
    if mountpoint -q "$MOUNT_POINT"; then
        echo "Unmounting $SELECTED_PARTITION from $MOUNT_POINT..."
        sudo umount "$MOUNT_POINT"
        echo "Successfully unmounted $SELECTED_PARTITION."
    else
        echo "Partition $SELECTED_PARTITION is not mounted at $MOUNT_POINT. Skipping unmount."
    fi
}

# Function to unmount bind mounts if they exist
unmount_bind_mounts() {
    local bind_mount
    for bind_mount in "$CONFIG_DIR" "$DATA_DIR"; do
        if mountpoint -q "$bind_mount"; then
            echo "Unmounting bind mount: $bind_mount..."
            sudo umount "$bind_mount"
            echo "Successfully unmounted $bind_mount."
        else
            echo "Bind mount $bind_mount is not currently mounted. Skipping unmount."
        fi
    done
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

# Function to bind a directory (config or data) and restore from backup
bind_directory() {
    LOCAL_DIR="$1"         # e.g., homelab/config
    TARGET_DIR="$2"        # e.g., $CONFIG_DIR or $DATA_DIR
    DIR_ON_DRIVE="$MOUNT_POINT/$LOCAL_DIR"
    BACKUP_DIR="${TARGET_DIR}.backup_$(date +%s)"

    echo "Creating $LOCAL_DIR directory on the drive..."
    sudo mkdir -p "$DIR_ON_DRIVE"

    echo "Backing up existing $LOCAL_DIR directory (if any)..."
    if [ -d "$TARGET_DIR" ]; then
        sudo mv "$TARGET_DIR" "$BACKUP_DIR"
        echo "Existing $TARGET_DIR moved to $BACKUP_DIR."
    fi

    echo "Creating target directory if it doesn't exist..."
    mkdir -p "$TARGET_DIR"

    echo "Creating bind mount for $LOCAL_DIR..."
    sudo mount --bind "$DIR_ON_DRIVE" "$TARGET_DIR"

    # Add bind mount to /etc/fstab for persistence
    if ! grep -qs "$DIR_ON_DRIVE $TARGET_DIR none bind" /etc/fstab; then
        echo "$DIR_ON_DRIVE $TARGET_DIR none bind 0 0" | sudo tee -a /etc/fstab
        echo "Added bind mount for $TARGET_DIR to /etc/fstab."
        echo "Reloading systemd daemon to recognize new fstab entries..."
        sudo systemctl daemon-reload
    else
        echo "Bind mount for $TARGET_DIR already exists in /etc/fstab. Skipping."
    fi

    # Restore contents from backup to the new bind mount
    if [ -d "$BACKUP_DIR" ]; then
        echo "Restoring contents from $BACKUP_DIR to $TARGET_DIR..."
        
        # Use rsync for efficient and permission-preserving copy
        sudo rsync -a "$BACKUP_DIR/" "$TARGET_DIR/"
        echo "Contents restored from $BACKUP_DIR to $TARGET_DIR."

        # Change ownership to the original user
        sudo chown -R "$ORIGINAL_USER":"$ORIGINAL_USER" "$TARGET_DIR"

        # Remove the backup directory
        echo "Removing backup directory $BACKUP_DIR..."
        sudo rm -rf "$BACKUP_DIR"
        echo "Backup directory $BACKUP_DIR removed."
    else
        echo "No backup directory found at $BACKUP_DIR. Skipping restoration."
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
    echo "Retrieved UUID: '$UUID'"

    if [ -z "$UUID" ]; then
        echo "ERROR: Unable to retrieve UUID for $SELECTED_PARTITION. Exiting." >&2
        exit 1
    fi

    # Determine mount options based on filesystem type
    case "$FSTYPE" in
        ext4|ext3|ext2)
            OPTIONS="defaults,noatime"
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

# Function to enable TRIM for SSD
enable_trim() {
    read -rp "Do you want to enable TRIM for your SSD? (y/n): " trim_choice

    case "$trim_choice" in
        [Yy]* )
            echo "Enabling TRIM for SSD..."

            # Check if fstrim is available
            if ! command -v fstrim &> /dev/null; then
                echo "fstrim could not be found. Installing util-linux..."
                sudo apt update
                sudo apt install -y util-linux
            fi

            echo "Running initial TRIM operation on $MOUNT_POINT..."
            sudo fstrim -v "$MOUNT_POINT"

            echo "Enabling and starting fstrim.timer for periodic TRIM operations..."
            sudo systemctl enable fstrim.timer
            sudo systemctl start fstrim.timer

            echo "TRIM has been enabled and scheduled successfully."
            ;;
        [Nn]* )
            echo "Skipping TRIM setup."
            ;;
        * )
            echo "Invalid choice. Please enter y or n."
            enable_trim
            ;;
    esac
}

# Main Script Execution
echo "===== Homelab Mount Setup Script ====="

list_drives
select_partition
check_and_format_partition
determine_mount_point

# Unmount any existing mounts to ensure a clean setup
unmount_partition
unmount_bind_mounts

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

# Prompt to enable TRIM
enable_trim

sudo systemctl daemon-reload

echo "===== Setup Completed Successfully! ====="
echo "Partition $SELECTED_PARTITION is mounted at $MOUNT_POINT."
echo "~/homelab/config is bind-mounted to $CONFIG_DIR_ON_DRIVE."
echo "~/homelab/data is bind-mounted to $DATA_DIR_ON_DRIVE."
