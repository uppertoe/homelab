#!/usr/bin/env bash
#
# nfs_setup.sh
# A simple script to install and configure NFS on a Raspberry Pi running Raspberry Pi OS (Raspbian).

# --------------------------------------------------------------------
#                           CONFIGURATION
# --------------------------------------------------------------------

# Network subnet to allow. Update this to reflect your local network.
ALLOWED_SUBNET="192.168.0.0/24"

# Directory on the Raspberry Pi that will be shared via NFS.
NFS_SHARE_DIR="/srv/nfs/share"

# --------------------------------------------------------------------
#                          SCRIPT START
# --------------------------------------------------------------------
set -e  # Exit immediately if a command exits with a non-zero status

echo "Updating packages and installing nfs-kernel-server..."
sudo apt update
sudo apt install -y nfs-kernel-server

echo "Creating directory for NFS share: $NFS_SHARE_DIR"
sudo mkdir -p "$NFS_SHARE_DIR"
# Set ownership and permissions. Adjust as necessary.
sudo chown nobody:nogroup "$NFS_SHARE_DIR"
sudo chmod 777 "$NFS_SHARE_DIR"

# Configure /etc/exports
EXPORT_LINE="$NFS_SHARE_DIR $ALLOWED_SUBNET(rw,sync,no_subtree_check)"

echo "Adding NFS export to /etc/exports..."
if ! grep -q "$EXPORT_LINE" /etc/exports; then
  echo "$EXPORT_LINE" | sudo tee -a /etc/exports > /dev/null
else
  echo "Export configuration for $NFS_SHARE_DIR already exists in /etc/exports."
fi

echo "Reloading NFS exports..."
sudo exportfs -ra

echo "Enabling and starting nfs-kernel-server service..."
sudo systemctl enable nfs-kernel-server
sudo systemctl restart nfs-kernel-server

echo "NFS server setup is complete!"
echo "You can verify by running: sudo exportfs -v"
