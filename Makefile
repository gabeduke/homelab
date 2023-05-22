USER=gabeduke
CONTROL_PLANE_NODE=$(USER)@pi-control.local
WORKER1=$(USER)@pi-beta.local
WORKER2=$(USER)@pi-charlie.local

TOKEN = $(shell ssh $(CONTROL_PLANE_NODE) sudo cat /var/lib/rancher/k3s/server/node-token)
CONTROL_IP = $(shell ssh $(CONTROL_PLANE_NODE) hostname --all-ip-addresses | awk '{print $$1}')
KUBECONFIG = $(shell ssh $(CONTROL_PLANE_NODE) cat /etc/rancher/k3s/k3s.yaml)

dummy:
	@echo $(CONTROL_IP)

namespaces:
	kubectl create namespace argocd || true
	kubectl create namespace grafana || true
	kubectl create namespace externaldns || true
	kubectl create namespace wikileet || true
	kubectl create namespace wikileet-dev || true
	kubectl create namespace wikileet-test || true
	kubectl create namespace wioc02 || true
	kubectl create namespace wiotemp1 || true

.PHONY: secrets
secrets:
	kubectl kustomize | kubectl apply -f -

iot: namespaces secrets
	kubectl kustomize clusters/iot | kubectl apply -f -

argocd:
	@echo http://localhost:8080
	kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
	kubectl port-forward svc/argocd-server -n argocd 8080:443

uninstall:
	ssh $(CONTROL_PLANE_NODE) /usr/local/bin/k3s-uninstall.sh
	ssh $(WORKER1) /usr/local/bin/k3s-agent-uninstall.sh
	ssh $(WORKER2) /usr/local/bin/k3s-agent-uninstall.sh

apply-cluster: sync
	# ssh $(CONTROL_PLANE_NODE) sh run.sh
	ssh $(WORKER1) sh run.sh $(TOKEN) $(CONTROL_IP)
	ssh $(WORKER2) sh run.sh $(TOKEN) $(CONTROL_IP)

get-kubeconfig:
	@scp $(CONTROL_PLANE_NODE):/etc/rancher/k3s/k3s.yaml .k3s.yaml
	chown $(USER):$(USER) .k3s.yaml

merge-kubeconfig:
	cp ~/.kube/config ~/.kube/config.bak 
	kubeconfig=~/.kube/config:.k3s.yaml kubectl config view --flatten > /tmp/config 
	mv /tmp/config ~/.kube/config 

sync:
	scp scripts/control-plane/run.sh $(CONTROL_PLANE_NODE):/home/$(USER)/
	scp scripts/control-plane/ip.sh $(CONTROL_PLANE_NODE):/home/$(USER)/
	scp scripts/setup.sh $(CONTROL_PLANE_NODE):/home/$(USER)/
	scp scripts/agent/run.sh $(WORKER1):/home/$(USER)/
	scp scripts/setup.sh $(WORKER1):/home/$(USER)/
	scp scripts/agent/run.sh $(WORKER2):/home/$(USER)/
	scp scripts/setup.sh $(WORKER2):/home/$(USER)/

setup: sync
	ssh $(CONTROL_PLANE_NODE) sh setup.sh
	ssh $(WORKER1) sh setup.sh
	ssh $(WORKER2) sh setup.sh
