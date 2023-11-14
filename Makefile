USER=gabeduke
CONTROL_PLANE_NODE=$(USER)@alphapi
WORKER1=$(USER)@betapi
WORKER2=$(USER)@charliepi
WORKER3=$(USER)@mothership
WORKER4=$(USER)@bigpi

EXTRA_SANS=alphapi

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
	kubectl create namespace longhorn-system || true
	kubectl create namespace minecraft || true
	kubectl create namespace influxdb || true
	kubectl create namespace monitoring || true
	kubectl create namespace reap || true

.PHONY: secrets
secrets:
	kubectl kustomize | kubectl apply -f -

.PHONY: iot
iot: namespaces secrets
	kubectl apply -k clusters/iot --server-side --force-conflicts

.PHONY: argocd
argocd:
	@echo http://localhost:8080
	kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
	kubectl port-forward svc/argocd-server -n argocd 8080:443

.PHONY: uninstall
uninstall:
	ssh $(CONTROL_PLANE_NODE) /usr/local/bin/k3s-uninstall.sh
	ssh $(WORKER1) /usr/local/bin/k3s-agent-uninstall.sh
	ssh $(WORKER2) /usr/local/bin/k3s-agent-uninstall.sh
	# ssh -t $(WORKER3) /usr/local/bin/k3s-agent-uninstall.sh
	# ssh $(WORKER4) /usr/local/bin/k3s-agent-uninstall.sh

.PHONY: install-control-plane
install-control-plane:
	ssh $(CONTROL_PLANE_NODE) sh run.sh $(EXTRA_SANS)

.PHONY: install-agent
install-agent:
	ssh $(WORKER1) sh run.sh $(TOKEN) $(CONTROL_IP)
	ssh $(WORKER2) sh run.sh $(TOKEN) $(CONTROL_IP)
	# ssh -t $(WORKER3) sh run.sh $(TOKEN) $(CONTROL_IP)
	# ssh -t $(WORKER4) sh run.sh $(TOKEN) $(CONTROL_IP)

.PHONY: apply-cluster
apply-cluster: sync install-control-plane install-agent

.PHONY: get-kubeconfig
get-kubeconfig:
	@scp $(CONTROL_PLANE_NODE):/etc/rancher/k3s/k3s.yaml .k3s.yaml
	chown $(USER):$(USER) .k3s.yaml

.PHONY: merge-kubeconfig
merge-kubeconfig:
	cp ~/.kube/config ~/.kube/config.bak 
	kubeconfig=~/.kube/config:.k3s.yaml kubectl config view --flatten > /tmp/config 
	mv /tmp/config ~/.kube/config 

.PHONY: sync
sync:
	scp scripts/control-plane/run.sh $(CONTROL_PLANE_NODE):/home/$(USER)/
	scp scripts/control-plane/ip.sh $(CONTROL_PLANE_NODE):/home/$(USER)/
	scp scripts/setup.sh $(CONTROL_PLANE_NODE):/home/$(USER)/
	scp scripts/agent/run.sh $(WORKER1):/home/$(USER)/
	scp scripts/setup.sh $(WORKER1):/home/$(USER)/
	scp scripts/agent/run.sh $(WORKER2):/home/$(USER)/
	scp scripts/setup.sh $(WORKER2):/home/$(USER)/
	# scp scripts/agent/run.sh $(WORKER3):/home/$(USER)/
	# scp scripts/agent/run.sh $(WORKER4):/home/$(USER)/
	# scp scripts/setup.sh $(WORKER4):/home/$(USER)/

.PHONY: setup
setup: sync
	ssh $(CONTROL_PLANE_NODE) sh setup.sh
	ssh $(WORKER1) sh setup.sh
	ssh $(WORKER2) sh setup.sh
	# ssh -t $(WORKER4) sh setup.sh

.PHONY: patch
patch:
	@$(MAKE) -j patch-control-plane patch-agent1 patch-agent2 patch-agent4

patch-control-plane:
	ssh $(CONTROL_PLANE_NODE) sudo apt-get update && sudo apt-get upgrade -y

patch-agent1:
	ssh $(WORKER1) sudo apt-get update && sudo apt-get upgrade -y

patch-agent2:
	ssh $(WORKER2) sudo apt-get update && sudo apt-get upgrade -y

patch-agent4:
	ssh $(WORKER4) sudo apt-get update && sudo apt-get upgrade -y

