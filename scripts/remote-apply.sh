#!/bin/bash
# Script: Run terraform apply on Admin VM

ADMIN_VM_IP="${1:-admin-vm}"
ADMIN_VM_USER="${2:-tantai}"
REMOTE_PATH="/home/${ADMIN_VM_USER}/homelab-iac/terraform"

echo "Running terraform apply on ${ADMIN_VM_IP}..."

# Check if sync is running
if ! mutagen sync list | grep -q "homelab-iac"; then
    echo "⚠️  Warning: Mutagen sync not running. Files may not be up-to-date."
    echo "   Run: ./scripts/sync-start.sh ${ADMIN_VM_IP} ${ADMIN_VM_USER}"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

ssh "${ADMIN_VM_USER}@${ADMIN_VM_IP}" REMOTE_PATH="${REMOTE_PATH}" 'bash -s' <<'EOF'
set -euo pipefail
cd "${REMOTE_PATH}"

source "../scripts/lib/common.sh"
auto_unlock_terraform

(test -d .terraform || terraform init)
terraform apply -auto-approve
EOF
