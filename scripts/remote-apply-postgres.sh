#!/bin/bash
# Script: Run terraform apply for PostgreSQL only on Admin VM

ADMIN_VM_IP="${1:-192.168.1.100}"
ADMIN_VM_USER="${2:-tantai}"
REMOTE_PATH="/home/${ADMIN_VM_USER}/homelab-iac/terraform"

echo "Running terraform apply -target=module.postgres on ${ADMIN_VM_IP}..."

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

# Always run terraform init to ensure providers are up-to-date
terraform init

# Apply only PostgreSQL module with auto-approve
terraform apply -target=module.postgres -auto-approve
EOF
