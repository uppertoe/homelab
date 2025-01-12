#!/usr/bin/env bash
#
# external_nfs_setup.sh
#
# This script helps you pick an external drive partition, mount it,
# optionally bind-mount it to /srv/nfs/share, and export it via NFS.
#

set -e  # Exit on error

#######################################
#               VARIABLES
#######################################
ALLOWED_SUBNET="192.168.0.0/24"     # Adjust to match your local network
NFS_SHARE_DIR="/srv/nfs/share"      # Default directory to serve over NFS
NFS_EXPORT_OPTIONS="rw,sync,no_subtree_check"

#######################################
#           HELPER FUNCTIONS
#######################################

print_header() {
  echo "=================================================="
  echo "   External Drive + NFS Setup on Raspberry Pi"
  echo "=================================================="
}

require_root() {
  # We need root or sudo privileges to do things like mounting, editing fstab, etc.
  if [[ $EUID -ne 0 ]]; then
    echo "Please run this script with sudo or as root."
    exit 1
  fi
}

list_partitions() {
  # Lists all block devices excluding the root filesystem and possibly other
  # built-in devices. We filter out 'mmcblk0' (the Pi's SD card) to avoid confusion.
  # You can adapt the grep if you want to exclude or include other devices.
  echo "Available partitions (excluding mmcblk0):"
  lsblk -rpo NAME,TYPE,SIZE,MOUNTPOINT | grep -E "part" | grep -v "mmcblk0" || true
}

prompt_partition_choice() {
  # Capture only the partition names for easy selection
  mapfile -t PARTITIONS < <(lsblk -rpo NAME,TYPE | grep "part" | grep -v "mmcblk0" | awk '{print $1}')

  if [ ${#PARTITIONS[@]} -eq 0 ]; then
    echo "No external partitions found (other than the Pi's SD card)."
    echo "Please connect an external drive and try again."
    exit 1
  fi

  echo ""
  echo "Select the partition you would like to mount:"
  PS3="Enter your choice (number): "
  select PARTITION_CHOICE in "${PARTITIONS[@]}" "Quit"; do
    case "$REPLY" in
      [0-9]*)
        if [ "$REPLY" -le "${#PARTITIONS[@]}" ]; then
          SELECTED_PARTITION="$PARTITION_CHOICE"
          break
        else
          echo "Invalid option."
        fi
        ;;
      "Quit")
        echo "Exiting..."
        exit 0
        ;;
      *)
        echo "Invalid option."
        ;;
    esac
  done
}

prompt_mountpoint() {
  echo ""
  echo "Enter the mount point for $SELECTED_PARTITION (e.g., /mnt/external):"
  read -r MOUNTPOINT

  # Create the directory if it doesn’t exist
  if [ ! -d "$MOUNTPOINT" ]; then
    mkdir -p "$MOUNTPOINT"
  fi
}

mount_partition() {
  # Check if it's already mounted
  if mount | grep -q "on $MOUNTPOINT "; then
    echo "$SELECTED_PARTITION is already mounted on $MOUNTPOINT"
  else
    echo "Mounting $SELECTED_PARTITION on $MOUNTPOINT..."
    mount "$SELECTED_PARTITION" "$MOUNTPOINT"
    echo "Mounted successfully."
  fi

  # Ask if user wants to add to /etc/fstab
  read -p "Add this partition to /etc/fstab for persistence? (y/n): " ADD_PART_FSTAB
  if [[ "$ADD_PART_FSTAB" =~ ^[Yy]$ ]]; then
    # Check if fstab already has an entry
    if grep -q "$SELECTED_PARTITION" /etc/fstab; then
      echo "An entry for $SELECTED_PARTITION already exists in /etc/fstab. Skipping..."
    else
      # We'll assume ext4 for simplicity. If different, user needs to edit fstab manually.
      FSTAB_LINE="$SELECTED_PARTITION  $MOUNTPOINT  ext4  defaults  0  2"
      echo "Adding to /etc/fstab:"
      echo "  $FSTAB_LINE"
      echo "$FSTAB_LINE" >> /etc/fstab
    fi
  fi
}

prompt_bind_mount() {
  echo ""
  read -p "Would you like to bind-mount $MOUNTPOINT to $NFS_SHARE_DIR? (y/n): " BIND_CHOICE
  if [[ "$BIND_CHOICE" =~ ^[Yy]$ ]]; then
    setup_bind_mount
  else
    # If user doesn’t want a bind mount, we’ll just export $MOUNTPOINT directly for NFS.
    echo "Skipping bind mount."
    BIND_MOUNTPOINT="$MOUNTPOINT"
  fi
}

setup_bind_mount() {
  # Create the share directory if needed
  if [ ! -d "$NFS_SHARE_DIR" ]; then
    mkdir -p "$NFS_SHARE_DIR"
  fi

  echo "Bind-mounting $MOUNTPOINT to $NFS_SHARE_DIR..."
  mount --bind "$MOUNTPOINT" "$NFS_SHARE_DIR"
  echo "Bind mount done."

  # Offer to persist this bind mount in /etc/fstab
  read -p "Persist this bind mount in /etc/fstab? (y/n): " ADD_BIND_FSTAB
  if [[ "$ADD_BIND_FSTAB" =~ ^[Yy]$ ]]; then
    # Check if an fstab entry already exists
    if grep -q "$NFS_SHARE_DIR" /etc/fstab; then
      echo "An entry for $NFS_SHARE_DIR already exists in /etc/fstab. Skipping..."
    else
      # Format: MOUNTPOINT  NFS_SHARE_DIR  none  bind  0  0
      BIND_LINE="$MOUNTPOINT  $NFS_SHARE_DIR  none  bind  0  0"
      echo "Adding the following entry to /etc/fstab:"
      echo "  $BIND_LINE"
      echo "$BIND_LINE" >> /etc/fstab
    fi
  fi

  # Remember that for the NFS export
  BIND_MOUNTPOINT="$NFS_SHARE_DIR"
}

configure_nfs_export() {
  echo ""
  echo "Now we'll configure an NFS export for $BIND_MOUNTPOINT, accessible by $ALLOWED_SUBNET."
  echo "NFS options: $NFS_EXPORT_OPTIONS"
  echo ""

  # Make sure nfs-kernel-server is installed (if not, install it).
  if ! dpkg -l | grep -q nfs-kernel-server; then
    echo "Installing nfs-kernel-server..."
    apt update
    apt install -y nfs-kernel-server
  fi

  # Adjust permissions if necessary
  chown nobody:nogroup "$BIND_MOUNTPOINT" || true
  chmod 777 "$BIND_MOUNTPOINT" || true

  # Add to /etc/exports if it’s not already there
  EXPORT_LINE="$BIND_MOUNTPOINT $ALLOWED_SUBNET($NFS_EXPORT_OPTIONS)"
  if grep -q "$EXPORT_LINE" /etc/exports; then
    echo "Export line already exists in /etc/exports. Skipping..."
  else
    echo "Adding export line to /etc/exports:"
    echo "  $EXPORT_LINE"
    echo "$EXPORT_LINE" >> /etc/exports
  fi

  echo "Reloading NFS exports..."
  exportfs -ra

  echo "Enabling and restarting NFS server..."
  systemctl enable nfs-kernel-server
  systemctl restart nfs-kernel-server

  echo "NFS export configuration complete!"
  echo "You can verify with:  sudo exportfs -v"
}

#######################################
#           SCRIPT EXECUTION
#######################################

require_root
print_header
list_partitions
prompt_partition_choice
prompt_mountpoint
mount_partition
prompt_bind_mount
configure_nfs_export

echo ""
echo "All done!"
echo "=================================================="
echo "  Partition:     $SELECTED_PARTITION"
echo "  Mounted at:    $MOUNTPOINT"
echo "  Exported from: $BIND_MOUNTPOINT"
echo "  Accessible by: $ALLOWED_SUBNET"
echo "=================================================="
echo "You can run:  mount | grep '$MOUNTPOINT'  to confirm the partition is mounted."
echo "Or check:     mount | grep '$BIND_MOUNTPOINT'  for the bind mount."
echo "And:          cat /etc/exports                to see the NFS export."
