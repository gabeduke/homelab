iot:
	kubectl kustomize clusters/iot | kubectl apply -f -
	kubectl create secret generic -n grafana grafana-credentials --from-env-file=./hack/.env || true

argocd:
	kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
	kubectl port-forward svc/argocd-server -n argocd 8080:443
