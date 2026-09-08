USER=gabeduke
CONTROL_PLANE_NODE=$(USER)@alphapi

# Workers currently in the cluster. `mothership` and `bigpi` were removed and
# are deliberately absent. Add a host back HERE and nowhere else -- every target
# below iterates these lists rather than keeping its own copy.
WORKER_HOSTS = betapi charliepi
WORKERS      = $(addprefix $(USER)@,$(WORKER_HOSTS))
ALL_NODES    = $(CONTROL_PLANE_NODE) $(WORKERS)

EXTRA_SANS=alphapi

TOKEN = $(shell ssh $(CONTROL_PLANE_NODE) sudo cat /var/lib/rancher/k3s/server/node-token)
CONTROL_IP = $(shell ssh $(CONTROL_PLANE_NODE) hostname --all-ip-addresses | awk '{print $$1}')
EXTERNAL_IP = $(shell ssh $(CONTROL_PLANE_NODE) dig +short myip.opendns.com @resolver1.opendns.com)

# Do NOT define a KUBECONFIG variable here. If KUBECONFIG is set in the
# environment when make starts, make re-exports ITS value into every recipe --
# so a makefile-level KUBECONFIG points every kubectl call in this file at the
# wrong place. The old one held the entire text of k3s.yaml and was unused.

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
	@for n in $(WORKERS); do \
		echo "==> uninstalling k3s agent on $$n"; \
		ssh $$n /usr/local/bin/k3s-agent-uninstall.sh || exit $$?; \
	done

.PHONY: install-control-plane
install-control-plane:
	ssh $(CONTROL_PLANE_NODE) sh run.sh $(EXTRA_SANS)

.PHONY: install-agent
install-agent:
	@for n in $(WORKERS); do \
		echo "==> installing k3s agent on $$n"; \
		ssh $$n sh run.sh '$(TOKEN)' '$(CONTROL_IP)' '$(EXTERNAL_IP)' || exit $$?; \
	done

.PHONY: apply-cluster
apply-cluster: sync setup install-control-plane install-agent

.PHONY: get-kubeconfig
get-kubeconfig:
	@scp $(CONTROL_PLANE_NODE):/etc/rancher/k3s/k3s.yaml .k3s.yaml
	@chmod 600 .k3s.yaml
	@ip='$(CONTROL_IP)'; \
		sed -i.bak "s|https://127.0.0.1:6443|https://$$ip:6443|" .k3s.yaml && rm -f .k3s.yaml.bak; \
		echo "==> .k3s.yaml points at $$ip:6443"

.PHONY: merge-kubeconfig
merge-kubeconfig: get-kubeconfig
	cp ~/.kube/config ~/.kube/config.bak
	KUBECONFIG=$$HOME/.kube/config:$(CURDIR)/.k3s.yaml kubectl config view --flatten > /tmp/config
	mv /tmp/config ~/.kube/config

.PHONY: sync
sync:
	scp scripts/control-plane/run.sh scripts/control-plane/ip.sh scripts/setup.sh \
		scripts/load-nfs-modules.sh $(CONTROL_PLANE_NODE):/home/$(USER)/
	@for n in $(WORKERS); do \
		echo "==> syncing scripts to $$n"; \
		scp scripts/agent/run.sh scripts/setup.sh scripts/load-nfs-modules.sh \
			$$n:/home/$(USER)/ || exit $$?; \
	done

.PHONY: setup-cron
setup-cron:
	@echo "Setting up hourly cron job for IP updates on $(CONTROL_PLANE_NODE)..."
	@ssh $(CONTROL_PLANE_NODE) "crontab -l | grep -v 'ip.sh' | { cat; echo '@hourly /home/$(USER)/ip.sh >> /home/$(USER)/log/ip-cron.log 2>&1'; } | crontab -"
	@ssh $(CONTROL_PLANE_NODE) "mkdir -p /home/$(USER)/log"

# setup.sh exits 3 when a node needs a reboot for cgroup changes to take effect.
# It no longer reboots on its own -- `make setup` runs against live nodes, and an
# unannounced control-plane reboot is an undrained outage. Opt in per run with
# `make setup REBOOT=1`, and prefer one node at a time.
REBOOT ?= 0

.PHONY: setup
setup:
	@rc_any=0; \
	for n in $(ALL_NODES); do \
		echo "==> setup $$n"; \
		ssh $$n "REBOOT=$(REBOOT) bash setup.sh"; \
		rc=$$?; \
		if [ $$rc -eq 3 ]; then \
			echo "!! $$n needs a reboot -- re-run with: make setup REBOOT=1"; rc_any=3; \
		elif [ $$rc -ne 0 ]; then \
			echo "!! $$n setup FAILED (exit $$rc)"; exit $$rc; \
		fi; \
	done; \
	exit $$rc_any

# The remote command MUST stay single-quoted. Unquoted, make's /bin/sh parses
# the `&&` locally, so `apt-get update` ran on the node and `apt-get upgrade`
# ran on the Mac -- no node was ever actually upgraded by this target.
#
# Serial on purpose: parallel apt-get across nodes interleaves output
# unreadably, and this is three Raspberry Pis, not a fleet.
.PHONY: patch
patch:
	@for n in $(ALL_NODES); do \
		echo "==> patching $$n"; \
		ssh $$n 'sudo apt-get update && sudo apt-get upgrade -y' || echo "!! $$n FAILED"; \
	done

# NFS Module Management (required for Longhorn RWX volumes)
.PHONY: load-nfs-modules
load-nfs-modules:
	@for n in $(ALL_NODES); do \
		echo "==> loading NFS modules on $$n"; \
		ssh $$n 'bash -s' < scripts/load-nfs-modules.sh || echo "!! $$n FAILED"; \
	done

.PHONY: check-nfs-modules
check-nfs-modules:
	@for n in $(ALL_NODES); do \
		echo ""; echo "$$n:"; \
		ssh $$n 'lsmod | grep -E "^nfs|^nfsd|^lockd|^sunrpc" || echo "  No NFS modules loaded"' \
			|| echo "  Failed to check"; \
	done

