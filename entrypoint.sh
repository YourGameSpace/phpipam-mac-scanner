#!/bin/sh

echo "[INFO] Starting ipam-mac-scanner v1.0.4 ..."

while true; do
    /bin/bash /app/ipam-mac-scanner.sh
    sleep $((SCAN_COOLDOWN * 60))
done