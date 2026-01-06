#!/bin/bash
# Script: Run terraform destroy on Admin VM

ADMIN_VM_IP="${1:-admin-vm}"
ADMIN_VM_USER="${2:-tantai}"
REMOTE_PATH="/home/${ADMIN_VM_USER}/homelab-iac/terraform"

echo "Running terraform destroy on ${ADMIN_VM_IP}..."

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

terraform init
terraform destroy -auto-approve
EOF
