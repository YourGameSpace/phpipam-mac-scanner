#!/bin/sh

# Generate crontab
echo "$CRON_SCHEDULE /app/ipam-mac-scanner.sh >> /var/log/cron.log 2>&1" > /etc/crontabs/root

if [ "$RUN_AT_STARTUP" ]; then
    /bin/bash /app/ipam-mac-scanner.sh
fi

# Start cronjob
crond -f -l 8