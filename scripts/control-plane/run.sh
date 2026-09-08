#!/bin/bash

set -x

IP=$(hostname --all-ip-addresses | awk '{print $1}')
CURRENT_IPV4="$(dig +short myip.opendns.com @resolver1.opendns.com)"

EXTERNAL_IP=${CURRENT_IPV4}

export K3S_KUBECONFIG_MODE=644
# --disable local-storage: k3s ships local-path as a StorageClass annotated
# is-default-class=true, hardcoded in its bundled manifest
# (/var/lib/rancher/k3s/server/manifests/local-storage.yaml). Longhorn also
# marks its class default, so the cluster had TWO defaults and Kubernetes chose
# between them arbitrarily for any PVC that omitted storageClassName. Patching
# the class with kubectl does not hold: the k3s addon controller owns it and
# re-applies whenever an upgrade changes that manifest. Longhorn is the real
# storage layer here (every PVC in the cluster uses it), and local-path cannot
# expand and pins data to a single node, so local-storage is disabled outright.
export INSTALL_K3S_EXEC="--node-taint node-role.kubernetes.io/control-plane=true:NoSchedule --advertise-address=${IP} --node-external-ip=${EXTERNAL_IP} --tls-san=${EXTERNAL_IP},${IP},${1} --disable local-storage"

curl -sfL https://get.k3s.io | sh -
