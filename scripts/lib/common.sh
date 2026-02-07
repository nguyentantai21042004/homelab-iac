#!/usr/bin/env bash
# scripts/lib/common.sh — Shared functions for Terraform helper scripts.
# Source this file:  source "$(dirname "$0")/lib/common.sh"

auto_unlock_terraform() {
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
}
