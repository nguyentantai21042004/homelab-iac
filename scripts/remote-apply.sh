#!/bin/bash
# Script: Run terraform apply on Admin VM

ADMIN_VM_IP="${1:-admin-vm}"
ADMIN_VM_USER="${2:-tantai}"
REMOTE_PATH="/home/${ADMIN_VM_USER}/homelab-iac/terraform"

echo "Running terraform apply on ${ADMIN_VM_IP}..."

ssh "${ADMIN_VM_USER}@${ADMIN_VM_IP}" "cd ${REMOTE_PATH} && terraform apply -auto-approve"
