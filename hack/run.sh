kubectl create secret generic -n grafana grafana-credentials --from-env-file=./hack/.env
