#!/bin/bash

set -u

# NAME=worker1
TOKEN="${1}"
ADVERTISE_IP="${2}"
EXTERNAL_IP="${3}"

# export K3S_NODE_NAME=${NAME}
export K3S_URL=https://${ADVERTISE_IP}:6443
export INSTALL_K3S_EXEC="--node-external-ip=${EXTERNAL_IP}"

curl -sfL https://get.k3s.io | K3S_TOKEN=${TOKEN} sh -
