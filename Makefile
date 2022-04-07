k3d:
	kubectl kustomize clusters/k3d | kubectl apply -f -
	kubectl create secret generic -n grafana grafana-credentials --from-env-file=./hack/.env || true

argocd: k3d
	kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
	kubectl port-forward svc/argocd-server -n argocd 8080:443

mothership:
	kubectl kustomize clusters/mothership | kubectl apply -f -
	# kubectl create secret generic -n grafana grafana-credentials --from-env-file=./hack/.env
