# How to Create a ServiceMonitor for Prometheus

This guide explains how to create a ServiceMonitor resource to enable Prometheus to scrape metrics from your application.

## Prerequisites

1. **Your app must expose metrics**: Your application needs to expose Prometheus metrics on an HTTP endpoint (typically `/metrics`)
2. **A Kubernetes Service**: You need a Service that exposes the metrics port
3. **Prometheus Operator**: Already installed via `prom-stack` ArgoCD application
4. **Cross-namespace discovery enabled**: Prometheus is configured to discover ServiceMonitors from all namespaces (see `prom-stack.yaml`)

## Step-by-Step Guide

### Step 1: Verify Your Service Exposes Metrics

First, ensure your application has:
- A metrics endpoint (e.g., `http://your-app:8080/metrics`)
- A Kubernetes Service that exposes this port

Example Service:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: my-app-namespace
  labels:
    app: my-app  # Important: ServiceMonitor will select by these labels
spec:
  ports:
    - name: metrics
      port: 8080
      targetPort: 8080
  selector:
    app: my-app
```

### Step 2: Create the ServiceMonitor

Create a ServiceMonitor resource. You have two options:

#### Option A: Place in your app's namespace (Recommended)
Create the ServiceMonitor in the same namespace as your application. This keeps monitoring configuration close to the app.

#### Option B: Place in monitoring namespace
Create the ServiceMonitor in the `monitoring` namespace and use `namespaceSelector` to discover services in other namespaces.

### Step 3: Basic ServiceMonitor Example

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app-metrics
  namespace: my-app-namespace  # Same namespace as your app
  labels:
    app: my-app
spec:
  selector:
    matchLabels:
      app: my-app  # Must match labels on your Service
  endpoints:
    - port: metrics  # Name of the port in your Service
      path: /metrics  # Path to metrics endpoint
```

### Step 4: Add to Kustomization (if using Kustomize)

If you're managing your app with Kustomize, add the ServiceMonitor to your `kustomization.yaml`:

```yaml
resources:
  - my-app-deployment.yaml
  - my-app-service.yaml
  - my-app-servicemonitor.yaml  # Add this
```

### Step 5: Verify Prometheus Discovery

After applying the ServiceMonitor:

1. Check that Prometheus discovered it:
   ```bash
   kubectl get servicemonitor -n my-app-namespace
   ```

2. Check Prometheus targets:
   - Access Prometheus UI: `https://prometheus.leetserve.com`
   - Go to Status → Targets
   - Look for your service in the targets list

3. Verify metrics are being scraped:
   - In Prometheus UI, go to Graph
   - Query for metrics from your app (e.g., `up{job="my-app"}`)

## Common Configurations

### Custom Metrics Path

If your app uses a different path:
```yaml
endpoints:
  - port: metrics
    path: /custom/metrics/path
```

### Custom Scrape Interval

```yaml
endpoints:
  - port: metrics
    path: /metrics
    interval: 60s  # Scrape every 60 seconds
```

### HTTPS Metrics Endpoint

```yaml
endpoints:
  - port: metrics
    path: /metrics
    scheme: https
    tlsConfig:
      insecureSkipVerify: true  # Only for self-signed certs
```

### Basic Authentication

```yaml
endpoints:
  - port: metrics
    path: /metrics
    basicAuth:
      username:
        name: metrics-auth-secret
        key: username
      password:
        name: metrics-auth-secret
        key: password
```

### Multiple Endpoints

If your service exposes multiple metrics endpoints:
```yaml
endpoints:
  - port: metrics
    path: /metrics
  - port: custom-metrics
    path: /custom/metrics
```

### Cross-Namespace Discovery

To discover services in other namespaces:
```yaml
spec:
  selector:
    matchLabels:
      app: my-app
  namespaceSelector:
    matchNames:
      - my-app-namespace
      - another-namespace
```

## Troubleshooting

### ServiceMonitor not discovered by Prometheus

1. **Check namespace selector**: If your ServiceMonitor is in a different namespace, ensure Prometheus is configured to discover it
   - Prometheus is configured to discover ServiceMonitors from all namespaces (see `prom-stack.yaml`)
   - Verify configuration: `kubectl get prometheus -n monitoring -o jsonpath='{.items[0].spec.serviceMonitorNamespaceSelector}'`
   - Should show `{}` (empty selector = all namespaces) or specific namespace selectors

2. **Check labels**: Ensure your Prometheus `serviceMonitorSelector` matches the ServiceMonitor labels
   - Default kube-prometheus-stack selects all ServiceMonitors (empty selector)
   - Check Prometheus CRD: `kubectl get prometheus -n monitoring -o yaml`

3. **Check Service labels**: Ensure ServiceMonitor `selector.matchLabels` matches your Service labels

4. **Check RBAC permissions**: Prometheus needs permissions to read ServiceMonitors in other namespaces
   - kube-prometheus-stack typically handles this with ClusterRole/ClusterRoleBinding
   - Verify: `kubectl get clusterrolebinding | grep prometheus`

### Metrics not appearing

1. **Verify endpoint is accessible**:
   ```bash
   kubectl port-forward svc/my-app 8080:8080 -n my-app-namespace
   curl http://localhost:8080/metrics
   ```

2. **Check Prometheus logs**:
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus
   ```

3. **Verify Service port name**: The `port` in ServiceMonitor must match the port `name` in your Service

## Example: ServiceMonitor for Gift Wiki

Here's a real example you could use for the gift-wiki app:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: gift-wiki-metrics
  namespace: wikileet
  labels:
    app: gift-wiki
spec:
  selector:
    matchLabels:
      app: gift-wiki
  endpoints:
    - port: http  # Adjust based on your Service port name
      path: /metrics
      interval: 30s
```

## References

- [Prometheus Operator ServiceMonitor Documentation](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api.md#servicemonitor)
- [Prometheus Metrics Best Practices](https://prometheus.io/docs/practices/naming/)

