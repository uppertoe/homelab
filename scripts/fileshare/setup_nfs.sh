#!/usr/bin/env bash
#
# nfs_export_subdir.sh
#
# This script lets you pick a currently-mounted external drive,
# choose (or create) a subdirectory on that drive, and export it
# directly via NFS.
#

set -e  # Exit on error

#######################################
#          CONFIGURABLES
#######################################

# Subnet or IP range that should have access to the share
ALLOWED_SUBNET="192.168.0.0/24"

# NFS export options
NFS_EXPORT_OPTIONS="rw,sync,no_subtree_check"

#######################################
#         HELPER FUNCTIONS
#######################################

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run this script with sudo or as root."
    exit 1
  fi
}

print_header() {
  echo "=============================================="
  echo "     Exporting a Subdirectory via NFS"
  echo "=============================================="
}

list_mounted_drives() {
  # Show non-root, non-/boot mounts via lsblk
  echo "Currently mounted volumes (excluding root/boot):"
  lsblk -rpo NAME,MOUNTPOINT | grep -v "/boot" | grep -v " /$" || true
}

prompt_for_mounted_drive() {
  # Gather mount points (excluding root/boot)
  mapfile -t MOUNTPOINTS < <(lsblk -rpo NAME,MOUNTPOINT \
                             | grep -v "/boot" \
                             | grep -v " /$" \
                             | awk '{print $2}' \
                             | sort \
                             | uniq \
                             | sed '/^$/d')

  if [ ${#MOUNTPOINTS[@]} -eq 0 ]; then
    echo "No external drives appear to be mounted (other than system volumes)."
    echo "Please mount an external drive and re-run this script."
    exit 1
  fi

  echo ""
  echo "Select which mounted drive/directory to use as a base for the share:"
  PS3="Enter your choice (number): "
  select MP_CHOICE in "${MOUNTPOINTS[@]}" "Quit"; do
    case "$REPLY" in
      [0-9]*)
        if [ "$REPLY" -le "${#MOUNTPOINTS[@]}" ]; then
          BASE_MOUNTPOINT="$MP_CHOICE"
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

  echo "You selected: $BASE_MOUNTPOINT"
}

prompt_for_subdirectory() {
  echo ""
  echo "Enter the subdirectory (relative or absolute) you want to export from '$BASE_MOUNTPOINT'."
  echo "For example: 'myshare' (meaning $BASE_MOUNTPOINT/myshare) or an absolute path like /mnt/extern1/config."
  read -r SUBDIR_INPUT

  # If user enters an absolute path starting with '/', use it directly
  # Otherwise, treat it as relative to $BASE_MOUNTPOINT
  if [[ "$SUBDIR_INPUT" = /* ]]; then
    FULL_SUBDIR="$SUBDIR_INPUT"
  else
    FULL_SUBDIR="$BASE_MOUNTPOINT/$SUBDIR_INPUT"
  fi

  # Create the subdirectory if it doesn’t exist
  if [ ! -d "$FULL_SUBDIR" ]; then
    echo "Directory '$FULL_SUBDIR' does not exist. Creating it..."
    mkdir -p "$FULL_SUBDIR"
  fi
}

configure_nfs_export() {
  echo ""
  echo "Now configuring an NFS export for $FULL_SUBDIR, accessible by $ALLOWED_SUBNET."
  echo "NFS options: $NFS_EXPORT_OPTIONS"
  echo ""

  # Install nfs-kernel-server if needed
  if ! dpkg -l | grep -q nfs-kernel-server; then
    echo "Installing nfs-kernel-server..."
    apt update
    apt install -y nfs-kernel-server
  fi

  # Adjust permissions if you want broad read/write from all clients
  chown nobody:nogroup "$FULL_SUBDIR" || true
  chmod 777 "$FULL_SUBDIR" || true

  # Form the export line
  EXPORT_LINE="$FULL_SUBDIR $ALLOWED_SUBNET($NFS_EXPORT_OPTIONS)"

  # Check if it’s already in /etc/exports
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
  echo "Verify with: exportfs -v"
}

#######################################
#           SCRIPT EXECUTION
#######################################

require_root
print_header

list_mounted_drives
prompt_for_mounted_drive
prompt_for_subdirectory
configure_nfs_export

echo ""
echo "========================================="
echo "             ALL DONE!"
echo "========================================="
echo "Your subdirectory is exported:"
echo "  $FULL_SUBDIR  to  $ALLOWED_SUBNET"
echo ""
echo "Check with: mount | grep '$BASE_MOUNTPOINT'"
echo "And:        exportfs -v"
echo ""
