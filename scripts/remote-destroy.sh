#!/bin/bash
# Script: Run terraform destroy on Admin VM

ADMIN_VM_IP="${1:-admin-vm}"
ADMIN_VM_USER="${2:-tantai}"
REMOTE_PATH="/home/${ADMIN_VM_USER}/homelab-iac/terraform"

echo "Running terraform destroy on ${ADMIN_VM_IP}..."

ssh "${ADMIN_VM_USER}@${ADMIN_VM_IP}" REMOTE_PATH="${REMOTE_PATH}" 'bash -s' <<'EOF'
set -euo pipefail
cd "${REMOTE_PATH}"

source "../scripts/lib/common.sh"
auto_unlock_terraform

terraform init
terraform destroy -auto-approve
EOF
