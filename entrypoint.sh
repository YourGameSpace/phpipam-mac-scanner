#!/bin/sh

echo "[INFO] Starting ipam-mac-scanner v1.0.3 ..."

while true; do
    /bin/bash /app/ipam-mac-scanner.sh
    sleep $((SCAN_INTERVAL * 60))
done