#!/bin/bash

set -u

# NAME=worker1
ADVERTISE_IP=192.168.86.53

# export K3S_NODE_NAME=${NAME}
export K3S_URL=https://${ADVERTISE_IP}:6443

curl -sfL https://get.k3s.io | K3S_TOKEN=${TOKEN} sh -
