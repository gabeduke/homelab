#!/bin/bash

set -x

IP=$(hostname --all-ip-addresses | awk '{print $1}')
CURRENT_IPV4="$(dig +short myip.opendns.com @resolver1.opendns.com)"

EXTERNAL_IP=${CURRENT_IPV4}

export K3S_KUBECONFIG_MODE=644
export INSTALL_K3S_EXEC="--advertise-address=${IP} --node-external-ip=${EXTERNAL_IP} --tls-san=${EXTERNAL_IP} --tls-san=${1}"

curl -sfL https://get.k3s.io | sh -
