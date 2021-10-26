#!/bin/bash

kubectl kustomize clusters/k3d | kubectl apply -f -
kubectl create secret generic -n grafana grafana-credentials --from-env-file=./hack/.env
