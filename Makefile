EXTERNAL_IP := 71.176.233.168
ADVERTISE_IP := 192.168.86.53
TOKEN = $(shell ssh ubuntu@pi1 sudo cat /var/lib/rancher/k3s/server/node-token)
KUBECONFIG = $(shell ssh ubuntu@pi1 cat /etc/rancher/k3s/k3s.yaml)

iot:
	kubectl create namespace argocd || true
	kubectl create namespace grafana || true
	kubectl create namespace externaldns || true
	kubectl kustomize clusters/iot | kubectl apply -f -
	kubectl create secret generic -n grafana grafana-credentials --from-env-file=./hack/.env || true
	kubectl create secret generic -n externaldns external-dns --from-file=./hack/credentials || true

argocd:
	kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
	kubectl port-forward svc/argocd-server -n argocd 8080:443

uninstall:
	ssh ubuntu@pi1 /usr/local/bin/k3s-uninstall.sh
	ssh ubuntu@pi2 /usr/local/bin/k3s-agent-uninstall.sh
	ssh ubuntu@pi3 /usr/local/bin/k3s-agent-uninstall.sh

apply-cluster:
	ssh ubuntu@pi1 'export INSTALL_K3S_EXEC="--advertise-address=$(ADVERTISE_IP)" EXTERNAL_IP=$(EXTERNAL_IP) && sh run.sh'
	ssh ubuntu@pi2 'export ADVERTISE_IP=$(ADVERTISE_IP) TOKEN=$(TOKEN) && sh run.sh'
	ssh ubuntu@pi3 'export ADVERTISE_IP=$(ADVERTISE_IP) TOKEN=$(TOKEN) && sh run.sh'

get-kubeconfig:
	ssh ubuntu@pi1 cat /etc/rancher/k3s/k3s.yaml

merge-kubeconfig:
	cp ~/.kube/config ~/.kube/config.bak 
	kubeconfig=~/.kube/config:kubeconfig kubectl config view --flatten > /tmp/config 
	mv /tmp/config ~/.kube/config 
