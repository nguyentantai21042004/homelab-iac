#!/bin/bash
# Script: Stop sync

SYNC_NAME="homelab-iac"

if mutagen sync list | grep -q "$SYNC_NAME"; then
    mutagen sync terminate "$SYNC_NAME"
    echo "Sync stopped"
else
    echo "No sync session running"
fi
