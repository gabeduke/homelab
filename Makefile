USER=gabeduke
CONTROL_PLANE_NODE=$(USER)@alphapi
WORKER1=$(USER)@betapi
WORKER2=$(USER)@charliepi
WORKER3=$(USER)@mothership
WORKER4=$(USER)@bigpi

EXTRA_SANS=alphapi

TOKEN = $(shell ssh $(CONTROL_PLANE_NODE) sudo cat /var/lib/rancher/k3s/server/node-token)
CONTROL_IP = $(shell ssh $(CONTROL_PLANE_NODE) hostname --all-ip-addresses | awk '{print $$1}')
EXTERNAL_IP = $(shell ssh $(CONTROL_PLANE_NODE) dig +short myip.opendns.com @resolver1.opendns.com)
KUBECONFIG = $(shell ssh $(CONTROL_PLANE_NODE) cat /etc/rancher/k3s/k3s.yaml)

ARGOCD_PASSWORD = $(shell kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

dummy:
	@echo $(CONTROL_IP)

namespaces:
	kubectl create namespace argocd || true
	kubectl create namespace fretbook-dev || true
	kubectl create namespace fretbook || true
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
	kubectl create namespace dukeverse || true
	kubectl create namespace plant-shop || true

.PHONY: secrets
secrets:
	kubectl kustomize | kubectl apply -f -

# Context `make iot` will apply to. Printed in the approval prompt so you cannot
# apply to the wrong cluster by accident.
CONTEXT ?= $(shell kubectl config current-context)

# Show what `make iot` would change, without applying anything.
#
# Worth running on its own before any apply. The repo and the live cluster drift
# in BOTH directions: manifests get edited without being applied, and the cluster
# gets patched without the repo catching up. A blind `make iot` silently pushes
# the repo's side of that disagreement -- which has previously meant an unpinned
# ArgoCD upgrade and dropping entries from the forward-auth whitelist.
#
# kubectl diff exit codes: 0 = no differences, 1 = differences found, >1 = error.
.PHONY: diff
diff:
	@echo "==> secrets: which would change (names only -- values are NOT printed)"
	@kubectl diff -k . > /tmp/.homelab-secrets.diff 2>/dev/null; \
		st=$$?; \
		if [ $$st -gt 1 ]; then echo "    secrets diff failed (exit $$st)"; rm -f /tmp/.homelab-secrets.diff; exit $$st; fi; \
		n=$$(grep -c '^+++' /tmp/.homelab-secrets.diff 2>/dev/null || true); \
		n=$${n:-0}; \
		if [ "$$n" -eq 0 ]; then echo "    none"; \
		else grep '^+++' /tmp/.homelab-secrets.diff | sed 's|.*/|    |;s|\t.*||' | sort -u; \
		     echo "    ($$n secret(s) would change -- inspect with: kubectl diff -k .)"; fi; \
		rm -f /tmp/.homelab-secrets.diff
	@echo "==> clusters/iot diff (context: $(CONTEXT))"
	@kubectl diff -k clusters/iot --server-side --force-conflicts; \
		st=$$?; \
		if [ $$st -eq 0 ]; then echo "==> no differences"; \
		elif [ $$st -eq 1 ]; then echo "==> differences shown above -- review before approving"; \
		else echo "==> kubectl diff failed (exit $$st)"; exit $$st; fi

# Interactive gate. Fails closed: with no TTY it aborts rather than applying.
# Set AUTO_APPROVE=1 to skip (scripted / CI use).
.PHONY: approve
approve:
	@if [ "$(AUTO_APPROVE)" = "1" ]; then \
		echo "==> AUTO_APPROVE=1, skipping confirmation"; \
	elif [ ! -t 0 ] && [ ! -e /dev/tty ]; then \
		echo "==> no TTY for confirmation; re-run interactively or set AUTO_APPROVE=1"; exit 1; \
	else \
		printf '==> Apply the changes above to "%s"? [y/N] ' "$(CONTEXT)"; \
		read ans < /dev/tty || { echo "==> could not read confirmation"; exit 1; }; \
		case "$$ans" in y|Y|yes|YES) ;; *) echo "==> aborted, nothing applied"; exit 1 ;; esac; \
	fi

# Review-then-apply.
#
# Order matters: diff and approve run FIRST, so nothing mutates the cluster until
# you have said yes -- `namespaces` and `secrets` both write, so they must come
# after the gate. Prerequisites run left-to-right (do not use `make -j` here).
#
# Use `make apply-iot` to bypass the gate entirely.
.PHONY: iot
iot: diff approve namespaces secrets apply-iot

.PHONY: apply-iot
apply-iot:
	kubectl apply -k clusters/iot --server-side --force-conflicts

.PHONY: argocd
argocd:
	@echo http://argocd.leetserve.com
	@echo "Username: admin"
	@echo "Password: $(ARGOCD_PASSWORD)"

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
	ssh $(WORKER1) sh run.sh $(TOKEN) $(CONTROL_IP) $(EXTERNAL_IP)
	ssh $(WORKER2) sh run.sh $(TOKEN) $(CONTROL_IP) $(EXTERNAL_IP)
	# ssh -t $(WORKER3) sh run.sh $(TOKEN) $(CONTROL_IP) $(EXTERNAL_IP)
	# ssh -t $(WORKER4) sh run.sh $(TOKEN) $(CONTROL_IP) $(EXTERNAL_IP)

.PHONY: apply-cluster
apply-cluster: sync setup install-control-plane install-agent

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
	scp scripts/load-nfs-modules.sh $(CONTROL_PLANE_NODE):/home/$(USER)/ || true
	scp scripts/agent/run.sh $(WORKER1):/home/$(USER)/
	scp scripts/setup.sh $(WORKER1):/home/$(USER)/
	scp scripts/load-nfs-modules.sh $(WORKER1):/home/$(USER)/ || true
	scp scripts/agent/run.sh $(WORKER2):/home/$(USER)/
	scp scripts/setup.sh $(WORKER2):/home/$(USER)/
	scp scripts/load-nfs-modules.sh $(WORKER2):/home/$(USER)/ || true
	# scp scripts/agent/run.sh $(WORKER4):/home/$(USER)/
	# scp scripts/setup.sh $(WORKER4):/home/$(USER)/
	# scp scripts/load-nfs-modules.sh $(WORKER4):/home/$(USER)/ || true

.PHONY: setup-cron
setup-cron:
	@echo "Setting up hourly cron job for IP updates on $(CONTROL_PLANE_NODE)..."
	@ssh $(CONTROL_PLANE_NODE) "crontab -l | grep -v 'ip.sh' | { cat; echo '@hourly /home/$(USER)/ip.sh >> /home/$(USER)/log/ip-cron.log 2>&1'; } | crontab -"
	@ssh $(CONTROL_PLANE_NODE) "mkdir -p /home/$(USER)/log"

.PHONY: setup
setup: 
	ssh $(CONTROL_PLANE_NODE) bash setup.sh
	ssh $(WORKER1) bash setup.sh
	ssh $(WORKER2) bash setup.sh
	# ssh -t $(WORKER4) bash setup.sh

.PHONY: patch
patch:
	@$(MAKE) -j patch-control-plane patch-agent1 patch-agent2

patch-control-plane:
	ssh $(CONTROL_PLANE_NODE) sudo apt-get update && sudo apt-get upgrade -y

patch-agent1:
	ssh $(WORKER1) sudo apt-get update && sudo apt-get upgrade -y

patch-agent2:
	ssh $(WORKER2) sudo apt-get update && sudo apt-get upgrade -y

patch-agent4:
	ssh $(WORKER4) sudo apt-get update && sudo apt-get upgrade -y

# NFS Module Management (required for Longhorn RWX volumes)
.PHONY: load-nfs-modules
load-nfs-modules:
	@echo "Loading NFS modules on all nodes..."
	@$(MAKE) -j load-nfs-control-plane load-nfs-agent1 load-nfs-agent2

load-nfs-control-plane:
	@echo "Loading NFS modules on control plane..."
	@ssh $(CONTROL_PLANE_NODE) 'bash -s' < scripts/load-nfs-modules.sh || echo "Warning: Failed to load NFS modules on control plane"

load-nfs-agent1:
	@echo "Loading NFS modules on agent1..."
	@ssh $(WORKER1) 'bash -s' < scripts/load-nfs-modules.sh || echo "Warning: Failed to load NFS modules on agent1"

load-nfs-agent2:
	@echo "Loading NFS modules on agent2..."
	@ssh $(WORKER2) 'bash -s' < scripts/load-nfs-modules.sh || echo "Warning: Failed to load NFS modules on agent2"

.PHONY: check-nfs-modules
check-nfs-modules:
	@echo "Checking NFS modules on all nodes..."
	@echo ""
	@echo "Control Plane ($(CONTROL_PLANE_NODE)):"
	@ssh $(CONTROL_PLANE_NODE) 'lsmod | grep -E "^nfs|^nfsd|^lockd|^sunrpc" || echo "  No NFS modules loaded"' || echo "  Failed to check"
	@echo ""
	@echo "Worker 1 ($(WORKER1)):"
	@ssh $(WORKER1) 'lsmod | grep -E "^nfs|^nfsd|^lockd|^sunrpc" || echo "  No NFS modules loaded"' || echo "  Failed to check"
	@echo ""
	@echo "Worker 2 ($(WORKER2)):"
	@ssh $(WORKER2) 'lsmod | grep -E "^nfs|^nfsd|^lockd|^sunrpc" || echo "  No NFS modules loaded"' || echo "  Failed to check"

