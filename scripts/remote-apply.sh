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

# Auto-unlock Terraform lock (best-effort)
if [ -f ".terraform.tfstate.lock.info" ]; then
  LOCK_ID=$(python3 - <<'PY'
import json
with open(".terraform.tfstate.lock.info", "r", encoding="utf-8") as f:
    data = json.load(f)
print(data.get("ID", ""))
PY
)
  if [ -n "${LOCK_ID}" ]; then
    echo "Found stale Terraform lock (${LOCK_ID}), forcing unlock..."
    if ! terraform force-unlock -force "${LOCK_ID}"; then
      echo "force-unlock failed; removing lock file manually (LocalState not locked case)"
      rm -f ".terraform.tfstate.lock.info"
    fi
  else
    echo "Lock file exists but ID is empty; removing lock file."
    rm -f ".terraform.tfstate.lock.info"
  fi
fi

(test -d .terraform || terraform init)
terraform apply -auto-approve
EOF
