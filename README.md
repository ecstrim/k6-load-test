# K6 Load Testing Framework

Powerful, flexible Kubernetes-based load testing framework using Grafana K6.

---

## 🚀 **NEW: Version 2.0 Available!**

**v2.0 is a major redesign** with improved architecture and new features:

✨ **What's New:**
- **Parameterized deployment** - Single template replaces 12 manifests
- **Central configuration** - All settings in `config.yaml`
- **4 test scenarios** - Stress, Spike, Soak, and Load tests
- **Result persistence** - Store and compare test results over time
- **Automated reporting** - Generate markdown reports with trends
- **Smart resource allocation** - Auto-sizing based on RPS
- **Enhanced CLI** - Better scripts with comprehensive options

📖 **[Read v2.0 Documentation →](README-v2.md)**

```bash
# Quick start with v2.0
./scripts/v2/deploy-test.sh --type stress --rps 100 --wait
./scripts/v2/deploy-test.sh --type spike --rps 50 --wait
```

**Note:** v1.0 (below) continues to work. Both versions coexist.

---

## v1.0 Documentation

Portable K6 stress testing suite for Kubernetes clusters. Tests ingress capacity at various RPS (Requests Per Second) levels with automated metrics collection.

## 📦 Package Contents

```
k6-stress-test-package/
├── README.md                          # This file
├── CONFIGURATION.md                   # Configuration guide
├── manifests/
│   ├── k6-stress-configmaps.yaml     # ConfigMaps for K6 scripts and test data
│   └── jobs/
│       └── stress/
│           ├── stress-50rps.yaml     # Individual job manifests (50-1500 RPS)
│           ├── stress-100rps.yaml
│           ├── stress-150rps.yaml
│           ├── stress-200rps.yaml
│           ├── stress-300rps.yaml
│           ├── stress-400rps.yaml
│           ├── stress-500rps.yaml
│           ├── stress-750rps.yaml
│           ├── stress-1000rps.yaml
│           └── stress-1500rps.yaml
├── scripts/
│   ├── run-single-stress-test.sh     # Run single RPS level test
│   └── run-all-stress-tests.sh       # Run all tests sequentially
├── k6-scripts/
│   └── stress-test.js                # K6 test script (for reference)
├── k6-data/
│   └── urls-1.json                   # Test URLs (for reference)
└── logs/                             # Created automatically for test logs
```

## ⚙️ Prerequisites

### Required

1. **Kubernetes cluster** with kubectl access
2. **Metrics Server** installed:
   ```bash
   kubectl get deployment metrics-server -n kube-system
   ```
   If not installed:
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
   ```

3. **Target namespace** (default: `prod`)
4. **Target application** deployed and accessible via ingress

### Optional

- **Node taints/labels** for K6 workload isolation (recommended for production)
- **Ingress NGINX Controller** (tests use internal cluster ingress by default)

## 🚀 Quick Start

### 1. Configure for Your Cluster

Before deploying, you must configure the package for your environment. See [CONFIGURATION.md](CONFIGURATION.md) for detailed instructions.

**Minimum required changes:**
- Update `BASE_URL` in ConfigMap and job manifests
- Update `NAMESPACE` if not using `prod`
- Update test URLs in `manifests/k6-stress-configmaps.yaml`

### 2. Deploy ConfigMaps

```bash
kubectl apply -f manifests/k6-stress-configmaps.yaml
```

This creates:
- `k6-stress-script` ConfigMap (K6 test script + metrics collector)
- `k6-urls-data` ConfigMap (URLs to test)

### 3. Run a Single Test

```bash
cd scripts
./run-single-stress-test.sh 100  # Test at 100 RPS
```

**Valid RPS levels:** 50, 100, 150, 200, 300, 400, 500, 750, 1000, 1500

### 4. Run All Tests

```bash
cd scripts
./run-all-stress-tests.sh
```

Runs all RPS levels sequentially with 30-second delays between tests.

## 📊 Test Output

Each test generates a timestamped log file in `logs/`:

```
logs/ingress-stress-test-{RPS}rps-YYYY-MM-DD-HHMMSS.log
```

**Log contents:**
- Resource discovery (deployments and nodepools in namespace)
- K6 test configuration
- Real-time request metrics
- HTTP status codes, latencies (p95, p99, max)
- Error rates and failures
- Resource metrics (CPU/Memory) for:
  - All deployment pods in the namespace
  - CoreDNS pods
  - Ingress controller pods
  - All nodepools where deployments run

**Example output:**
```
=== Resource Discovery ===
Timestamp: 2025-10-06T10:30:00Z
Namespace: prod

--- Deployments ---
frontend backend worker

--- Nodepools ---
system apps

=== K6 Stress Test Configuration ===
Target RPS: 100
Duration: 2m
Base URL: http://ingress-nginx-controller.ingress-nginx.svc.cluster.local
URLs to test: 3
Calculated VUs: 25
====================================

... K6 test execution ...

=== Resource Metrics Collection ===
Timestamp: 2025-10-06T10:32:00Z
Namespace: prod

--- Deployment Pod Metrics ---
Deployment: frontend
frontend-abc123   150m   512Mi
frontend-def456   145m   498Mi

Deployment: backend
backend-xyz789    200m   768Mi
...
```

## 🎯 Success Criteria

Tests are considered successful when:
- **p95 latency** < 2000ms
- **Error rate** < 2%
- **HTTP failures** < 2%

K6 will exit with non-zero code if thresholds are exceeded.

## 🔧 Customization

### Change Test Duration

Edit the job manifest before deployment:
```yaml
env:
- name: DURATION
  value: "5m"  # Change from default 2m
```

### Change Target Namespace

Update all job manifests:
```yaml
metadata:
  namespace: your-namespace  # Change from 'prod'
env:
- name: NAMESPACE
  value: "your-namespace"
```

### Modify Test URLs

Edit `manifests/k6-stress-configmaps.yaml`:
```yaml
data:
  urls-1.json: |
    {
      "urls": [
        "/your-endpoint-1",
        "/your-endpoint-2",
        "/your-endpoint-3"
      ]
    }
```

### Adjust Node Placement

By default, tests try to run on nodes with `workload=k6` label/taint. To change:

**Option 1: Remove node selector (run anywhere)**
```yaml
# Delete or comment out in job manifests:
nodeSelector:
  workload: k6
tolerations:
- key: workload
  operator: Equal
  value: k6
  effect: NoSchedule
```

**Option 2: Use different label**
```yaml
nodeSelector:
  your-label: your-value
```

### Change Resource Limits

Edit job manifests:
```yaml
resources:
  requests:
    cpu: "500m"      # Adjust as needed
    memory: "512Mi"
  limits:
    cpu: "2000m"
    memory: "2Gi"
```

## 🐛 Troubleshooting

### Test Job Doesn't Start

```bash
# Check job status
kubectl get jobs -n prod | grep k6-stress

# Check pod status
kubectl get pods -n prod -l app=k6-stress-test

# View pod events
kubectl describe pod <pod-name> -n prod
```

**Common issues:**
- Node selector mismatch (no nodes with `workload=k6` label)
- Insufficient resources
- ConfigMaps not deployed

### Metrics Collection Fails

```bash
# Check metrics server
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Test metrics API
kubectl top pods -n prod
kubectl top nodes
```

**Note:** Tests will complete successfully even if metrics collection fails. Only the resource metrics section will be empty.

### Permission Errors

Ensure RBAC resources are deployed (automatically included in `stress-50rps.yaml`):
```bash
kubectl get sa k6-stress-test -n prod
kubectl get role k6-metrics-reader -n prod
kubectl get clusterrole k6-node-metrics-reader
```

### Job Stuck/Doesn't Complete

```bash
# View logs
kubectl logs -n prod -l app=k6-stress-test,rps=100 -f

# Delete stuck job
kubectl delete job k6-stress-100rps -n prod --wait=true
```

### High Error Rate

Check:
- Target application health: `kubectl get pods -n prod -l app=<your-app>`
- Ingress controller health: `kubectl get pods -n ingress-nginx`
- Network policies or rate limiting
- Application resource limits

## 📋 RBAC Permissions

The package creates minimal RBAC permissions:

**ServiceAccount:** `k6-stress-test` (in target namespace)

**Namespace-scoped (prod):**
- Read pods
- Read pod metrics

**Namespace-scoped (kube-system):**
- Read CoreDNS pods
- Read CoreDNS metrics

**Cluster-scoped:**
- Read nodes
- Read node metrics

**Namespace-scoped (ingress-nginx):**
- Automatically granted via Role in kube-system binding

## 🧹 Cleanup

### Remove Completed Jobs

```bash
# Jobs auto-delete after 10 minutes (ttlSecondsAfterFinished: 600)
# To delete immediately:
kubectl delete jobs -n prod -l app=k6-stress-test
```

### Remove All Resources

```bash
# ConfigMaps
kubectl delete configmap k6-stress-script k6-urls-data -n prod

# RBAC
kubectl delete sa k6-stress-test -n prod
kubectl delete role k6-metrics-reader -n prod
kubectl delete role k6-metrics-reader-kube-system -n kube-system
kubectl delete rolebinding k6-metrics-reader -n prod
kubectl delete rolebinding k6-metrics-reader-kube-system -n kube-system
kubectl delete clusterrole k6-node-metrics-reader
kubectl delete clusterrolebinding k6-node-metrics-reader

# Jobs (if not auto-deleted)
kubectl delete jobs -n prod -l app=k6-stress-test
```

## 📝 Architecture

### How It Works

1. **ConfigMaps** store K6 test script, resource discovery script, metrics collector, and test URLs
2. **Job manifests** define Kubernetes Jobs with:
   - **K6 container**: Discovers resources, then runs the stress test
   - **Metrics collector container**: Collects resource metrics near test end
   - **Shared volume**: Coordination between containers
3. **Test execution**:
   - K6 container discovers all deployments and nodepools in namespace
   - Saves discovered resources to shared volume
   - K6 test starts
   - 10 seconds before completion, signals metrics collector
   - Metrics collector reads discovered resources and runs `kubectl top` commands
   - K6 waits for metrics, then outputs results
4. **Scripts** orchestrate job deployment and log streaming

### Multi-Container Design

Jobs use `shareProcessNamespace: true` and `emptyDir` volume for inter-container communication:
- K6 discovers resources and saves to `/shared/deployments.txt` and `/shared/nodepools.txt`
- K6 signals metrics collector via `/shared/collect-metrics` file
- Metrics collector reads discovered resources and collects metrics
- Metrics collector saves results to `/shared/metrics.json`
- K6 waits for `/shared/metrics-done` signal before exiting

This ensures metrics are collected for all deployments and nodepools while the test is still running.

## 🔒 Security Notes

- Tests use `insecureSkipTLSVerify: true` for HTTPS (modify K6 script if cert validation needed)
- RBAC permissions are read-only
- Tests run as non-privileged containers
- No secrets required (unless your ingress needs authentication)

## 📖 Additional Resources

- [K6 Documentation](https://k6.io/docs/)
- [Kubernetes Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [CONFIGURATION.md](CONFIGURATION.md) - Detailed configuration guide

## 📄 License

This package is provided as-is for load testing Kubernetes applications.
