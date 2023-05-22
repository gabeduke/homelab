#!/bin/bash

# cron entry (crontab -e)
# @hourly /home/${USER}/ip.sh >> /var/log/ip-cron.log 2>&1

#################### CHANGE THE FOLLOWING VARIABLES ####################
LOG_FILE="/home/${USER}/log/ips.log"
########################################################################

mkdir -p "$(dirname "${LOG_FILE}")"
touch "${LOG_FILE}"

CURRENT_IPV4="$(dig +short myip.opendns.com @resolver1.opendns.com)"
LAST_IPV4="$(tail -1 $LOG_FILE | awk -F, '{print $2}')"

if [ "$CURRENT_IPV4" = "$LAST_IPV4" ]; then
    echo "IP has not changed ($CURRENT_IPV4)"
else
    echo "IP has changed: $CURRENT_IPV4"
    echo "$(date),$CURRENT_IPV4" >> "$LOG_FILE"
    sh run.sh
fi
