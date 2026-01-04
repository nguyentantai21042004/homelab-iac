#!/bin/bash
# Script: Start 2-way sync with Admin VM

ADMIN_VM_IP="${1:-admin-vm}"
ADMIN_VM_USER="${2:-tantai}"
REMOTE_PATH="/home/${ADMIN_VM_USER}/homelab-iac"
SYNC_NAME="homelab-iac"

# Check if mutagen is installed
if ! command -v mutagen &> /dev/null; then
    echo "Mutagen not installed. Run: brew install mutagen-io/mutagen/mutagen"
    exit 1
fi

# Check if sync already exists
if mutagen sync list | grep -q "$SYNC_NAME"; then
    echo "Sync session '$SYNC_NAME' already exists"
    echo "   Use: mutagen sync list"
    echo "   Or: ./scripts/sync-stop.sh"
    exit 0
fi

# Start sync
echo "Starting sync with ${ADMIN_VM_USER}@${ADMIN_VM_IP}:${REMOTE_PATH}"

mutagen sync create \
    . \
    "${ADMIN_VM_USER}@${ADMIN_VM_IP}:${REMOTE_PATH}" \
    --name="$SYNC_NAME" \
    --ignore=".terraform" \
    --ignore="*.tfstate" \
    --ignore="*.tfstate.*" \
    --ignore=".terraform.lock.hcl" \
    --ignore="tools/" \
    --ignore=".git" \
    --sync-mode="two-way-resolved"

echo "Sync started!"
echo ""
echo "Commands:"
echo "   mutagen sync list          - View status"
echo "   mutagen sync monitor       - Monitor real-time"
echo "   ./scripts/sync-stop.sh     - Stop sync"
