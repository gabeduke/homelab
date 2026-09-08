#!/bin/bash

# Configuration
LOG_DIR="/home/gabeduke/log"
IPS_LOG="${LOG_DIR}/ips.log"
CRON_LOG="${LOG_DIR}/ip-cron.log"
RUN_SCRIPT="/home/gabeduke/run.sh"

mkdir -p "${LOG_DIR}"
touch "${IPS_LOG}"

CURRENT_IPV4="$(dig +short myip.opendns.com @resolver1.opendns.com)"
LAST_IPV4="$(tail -1 "${IPS_LOG}" | awk -F, '{print $2}')"

if [ "$CURRENT_IPV4" = "$LAST_IPV4" ]; then
    echo "$(date): IP has not changed ($CURRENT_IPV4)"
else
    echo "$(date): IP has changed to $CURRENT_IPV4"
    echo "$(date),$CURRENT_IPV4" >> "${IPS_LOG}"
    sh "${RUN_SCRIPT}"
fi
