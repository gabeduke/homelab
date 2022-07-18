CONTROL_PLANE_NODE=ubuntu@pi-master
WORKER1=ubuntu@pi-agent1
WORKER2=ubuntu@pi-agent2

TOKEN = $(shell ssh $(CONTROL_PLANE_NODE) sudo cat /var/lib/rancher/k3s/server/node-token)
KUBECONFIG = $(shell ssh $(CONTROL_PLANE_NODE) cat /etc/rancher/k3s/k3s.yaml)

namespaces:
	kubectl create namespace argocd || true
	kubectl create namespace grafana || true
	kubectl create namespace externaldns || true
	kubectl create namespace wioc02 || true
	kubectl create namespace wiotemp1 || true

secrets:
	kubectl create secret generic -n grafana grafana-credentials --from-env-file=./hack/grafana.env || true
	kubectl create secret generic -n wioc02 --from-env-file=./hack/wioC02.env || true
	kubectl create secret generic -n wiotemp1 --from-env-file=./hack/wiotemp1.env || true
	kubectl create secret generic -n externaldns external-dns --from-file=./hack/credentials || true

iot: namespaces secrets
	kubectl kustomize clusters/iot | kubectl apply -f -

argocd:
	kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
	kubectl port-forward svc/argocd-server -n argocd 8080:443

uninstall:
	ssh $(CONTROL_PLANE_NODE) /usr/local/bin/k3s-uninstall.sh
	ssh $(WORKER1) /usr/local/bin/k3s-agent-uninstall.sh
	ssh $(WORKER2) /usr/local/bin/k3s-agent-uninstall.sh

apply-cluster:
	ssh $(CONTROL_PLANE_NODE) sh run.sh
	ssh $(WORKER1) 'export TOKEN=$(TOKEN) && sh run.sh'
	ssh $(WORKER2) 'export TOKEN=$(TOKEN) && sh run.sh'

get-kubeconfig:
	@ssh $(CONTROL_PLANE_NODE) cat /etc/rancher/k3s/k3s.yaml

merge-kubeconfig:
	cp ~/.kube/config ~/.kube/config.bak 
	kubeconfig=~/.kube/config:kubeconfig kubectl config view --flatten > /tmp/config 
	mv /tmp/config ~/.kube/config 

sync:
	scp scripts/control-plane/run.sh $(CONTROL_PLANE_NODE):/home/ubuntu/
	scp scripts/control-plane/ip.sh $(CONTROL_PLANE_NODE):/home/ubuntu/
	scp scripts/agent/run.sh $(WORKER1):/home/ubuntu/
	scp scripts/agent/run.sh $(WORKER2):/home/ubuntu/
