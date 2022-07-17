#!/bin/bash

set -x

ETH0=$(ip addr show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
CURRENT_IPV4="$(dig +short myip.opendns.com @resolver1.opendns.com)"

EXTERNAL_IP=${CURRENT_IPV4}

export K3S_KUBECONFIG_MODE=644
export INSTALL_K3S_EXEC="--advertise-address=${ETH0} --node-external-ip=${EXTERNAL_IP} --tls-san=${EXTERNAL_IP} --tls-san=pi-master"

curl -sfL https://get.k3s.io | sh -
