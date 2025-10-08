# Configuration Guide

This guide explains how to configure the K6 load testing framework for your Kubernetes cluster.

---

## 🚀 **NEW: Version 2.0 Configuration**

**v2.0 uses central configuration** via `config.yaml` instead of editing individual manifests.

**Benefits:**
- All settings in one file
- No need to edit 12+ manifest files
- Environment-specific configs
- Easier customization

📖 **[See v2.0 Documentation →](README-v2.md)** for the new configuration approach.

**Quick config example (v2.0):**
```yaml
# config.yaml
test:
  target:
    baseUrl: "http://your-service.svc.cluster.local"
    appLabel: "your-app"
    namespace: "prod"
```

Then deploy: `./scripts/v2/deploy-test.sh --type stress --rps 100`

---

## v1.0 Configuration Guide

This guide explains how to configure the K6 stress test package (v1.0) for your Kubernetes cluster.

## 📋 Required Configuration

### 1. Update Target URL

**Files to modify:**
- `manifests/k6-stress-configmaps.yaml`
- All job manifests in `manifests/jobs/stress/*.yaml`

**What to change:**

#### ConfigMap (manifests/k6-stress-configmaps.yaml)

```yaml
# Line 22 in the k6-stress-script ConfigMap
const BASE_URL = __ENV.BASE_URL || 'https://your-domain.com';  # Change this default
```

#### All Job Manifests (manifests/jobs/stress/*.yaml)

```yaml
env:
- name: BASE_URL
  value: "http://ingress-nginx-controller.ingress-nginx.svc.cluster.local"  # Change this
```

**URL Options:**

**Internal cluster URL (recommended for testing without external DNS):**
```yaml
value: "http://ingress-nginx-controller.ingress-nginx.svc.cluster.local"
```

**External domain (if testing through CDN/load balancer):**
```yaml
value: "https://your-domain.com"
```

**Specific service:**
```yaml
value: "http://your-service.your-namespace.svc.cluster.local"
```

### 2. Update Test URLs

**File:** `manifests/k6-stress-configmaps.yaml`

Find the `k6-urls-data` ConfigMap (around line 247):

```yaml
data:
  urls-1.json: |
    {
      "urls": [
        "/your-product-page-1",
        "/your-product-page-2",
        "/your-api-endpoint-1",
        "/your-api-endpoint-2"
      ]
    }
```

**Tips:**
- Use paths that represent your typical traffic
- Mix heavy and light endpoints for realistic testing
- Start with 1-5 URLs, expand as needed
- Paths should start with `/`

### 3. Update Namespace (if not using 'prod')

**Files to modify:** All job manifests in `manifests/jobs/stress/*.yaml`

```yaml
metadata:
  namespace: your-namespace  # Change from 'prod'

# ...and in the env section:
env:
- name: NAMESPACE
  value: "your-namespace"  # Change from 'prod'
- name: APP_LABEL
  value: "your-app-label"  # Change to match your app's label
```

**Also update ConfigMap:**
```yaml
# manifests/k6-stress-configmaps.yaml
metadata:
  namespace: your-namespace  # Change from 'prod'
```

### 4. Resource Discovery (Automatic)

**No configuration needed!** The test automatically discovers:
- All deployments in the target namespace
- All nodepools (via `agentpool` label or node names)

Metrics are collected for all discovered resources during the test.

**Note:** If your cluster uses different nodepool labels, you may need to modify the `discover-resources.sh` script in the ConfigMap to use your cluster's labeling scheme (e.g., `node.kubernetes.io/instance-type` instead of `agentpool`).

## 🎛️ Optional Configuration

### 5. Adjust Test Duration

**Default:** 2 minutes per test

**Files to modify:** Individual job manifests

```yaml
env:
- name: DURATION
  value: "5m"  # Options: "30s", "2m", "10m", etc.
```

**Recommendations:**
- Quick smoke test: `30s` - `1m`
- Standard test: `2m` - `5m`
- Sustained load: `10m` - `30m`
- Soak test: `1h` - `24h`

### 6. Modify RPS Levels

**Files to modify:**
- `scripts/run-all-stress-tests.sh` (line 9)
- Create/remove job manifests as needed

**Current levels:** 50, 100, 150, 200, 300, 400, 500, 750, 1000, 1500

To add a new level (e.g., 2000 RPS):

1. Copy an existing job manifest:
   ```bash
   cp manifests/jobs/stress/stress-1500rps.yaml manifests/jobs/stress/stress-2000rps.yaml
   ```

2. Update the new manifest:
   ```yaml
   metadata:
     name: k6-stress-2000rps
     labels:
       rps: "2000"
   spec:
     template:
       metadata:
         labels:
           rps: "2000"
       spec:
         containers:
         - name: k6
           args:
             - |
               echo "Starting K6 stress test: 2000 RPS"
               # ...
           env:
           - name: TARGET_RPS
             value: "2000"
   ```

3. Add to run-all script:
   ```bash
   # scripts/run-all-stress-tests.sh line 9
   RPS_LEVELS="50 100 150 200 300 400 500 750 1000 1500 2000"
   ```

### 7. Node Placement

**Default:** Tests run on nodes labeled `workload=k6`

**To remove node selector** (run on any node):

Edit all job manifests, delete/comment out:
```yaml
# Remove these sections:
nodeSelector:
  workload: k6
tolerations:
- key: workload
  operator: Equal
  value: k6
  effect: NoSchedule
```

**To use different labels:**
```yaml
nodeSelector:
  your-label: your-value
tolerations:
- key: your-label
  operator: Equal
  value: your-value
  effect: NoSchedule
```

**To create labeled nodes:**
```bash
kubectl label node <node-name> workload=k6
kubectl taint node <node-name> workload=k6:NoSchedule
```

### 8. Resource Limits

**Default per test job:**
- Requests: 500m CPU, 512Mi memory
- Limits: 2000m CPU, 2Gi memory

**Files to modify:** All job manifests

```yaml
resources:
  requests:
    cpu: "1000m"      # Increase for higher RPS
    memory: "1Gi"
  limits:
    cpu: "4000m"
    memory: "4Gi"
```

**Guidelines:**
- 50-200 RPS: Default is fine
- 300-500 RPS: Consider 1000m CPU, 1Gi memory
- 750-1000 RPS: Consider 2000m CPU, 2Gi memory
- 1500+ RPS: Consider 4000m CPU, 4Gi memory

### 9. HTTP Headers

**File:** `manifests/k6-stress-configmaps.yaml` (k6-stress-script ConfigMap)

Find the `params` section in the K6 script (around line 72):

```javascript
const params = {
  headers: {
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Encoding': 'gzip, deflate, br',
    'Accept-Language': 'en-US,en;q=0.9',
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
    'Host': 'your-domain.com',  // Update this to match your domain
    'X-Custom-Header': 'value',  // Add custom headers as needed
  },
  timeout: '30s',
};
```

**Common additions:**
- Authentication: `'Authorization': 'Bearer token'`
- API keys: `'X-API-Key': 'your-key'`
- User agent: `'User-Agent': 'CustomAgent/1.0'`
- Cookies: `'Cookie': 'session=abc123'`

### 10. Success Thresholds

**File:** `manifests/k6-stress-configmaps.yaml` (k6-stress-script ConfigMap)

Find the `thresholds` section (around line 40):

```javascript
thresholds: {
  'http_req_duration{expected_response:true}': ['p(95)<2000'],  // p95 latency < 2s
  'errors': ['rate<0.02'],                                       // < 2% errors
  'http_req_failed': ['rate<0.02'],                             // < 2% failures
},
```

**Examples:**

**Stricter thresholds:**
```javascript
thresholds: {
  'http_req_duration{expected_response:true}': ['p(95)<1000', 'p(99)<3000'],
  'errors': ['rate<0.01'],        // < 1% errors
  'http_req_failed': ['rate<0.01'],
},
```

**Relaxed thresholds:**
```javascript
thresholds: {
  'http_req_duration{expected_response:true}': ['p(95)<5000'],
  'errors': ['rate<0.05'],        // < 5% errors
  'http_req_failed': ['rate<0.05'],
},
```

### 11. Connection Reuse

**File:** `manifests/k6-stress-configmaps.yaml` (k6-stress-script ConfigMap)

```javascript
export const options = {
  // ...
  noConnectionReuse: false,  // Set to true to disable HTTP keep-alive
  // ...
};
```

**When to disable connection reuse:**
- Testing connection establishment overhead
- Simulating clients that don't support keep-alive
- Testing load balancer behavior with new connections

**Performance impact:**
- `false` (keep-alive enabled): Higher RPS, lower CPU, more realistic for modern clients
- `true` (keep-alive disabled): Lower RPS, higher CPU, more stress on connection handling

### 12. TLS Verification

**File:** `manifests/k6-stress-configmaps.yaml` (k6-stress-script ConfigMap)

```javascript
export const options = {
  // ...
  insecureSkipTLSVerify: true,  // Set to false to validate certificates
  // ...
};
```

**Set to `false` if:**
- Testing production TLS configuration
- Validating certificate chain
- Testing with real CA-signed certificates

**Keep as `true` if:**
- Using self-signed certificates
- Testing internal cluster services
- Certificate validation not critical for test

## 🔐 RBAC Configuration

**Default RBAC is included in:** `manifests/jobs/stress/stress-50rps.yaml`

If your cluster has strict RBAC policies, you may need to adjust permissions.

### Current Permissions

**ServiceAccount:** `k6-stress-test` (namespace: prod)

**Namespace roles (prod):**
```yaml
- apiGroups: [""]
  resources: ["pods", "nodes"]
  verbs: ["get", "list"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list"]
- apiGroups: ["metrics.k8s.io"]
  resources: ["pods", "nodes"]
  verbs: ["get", "list"]
```

**Namespace roles (kube-system):**
```yaml
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
- apiGroups: ["metrics.k8s.io"]
  resources: ["pods"]
  verbs: ["get", "list"]
```

**Namespace roles (ingress-nginx):**
```yaml
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
- apiGroups: ["metrics.k8s.io"]
  resources: ["pods"]
  verbs: ["get", "list"]
```

**Cluster roles:**
```yaml
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list"]
- apiGroups: ["metrics.k8s.io"]
  resources: ["nodes"]
  verbs: ["get", "list"]
```

### Minimal Configuration (No Metrics)

If metrics collection fails or you don't need it:

1. Remove the `metrics-collector` container from job manifests
2. Remove RBAC resources (ServiceAccount, Roles, RoleBindings)
3. Simplify K6 container args (remove metrics coordination logic)

## ✅ Configuration Checklist

Before running tests, verify:

- [ ] `BASE_URL` updated in ConfigMap and all job manifests
- [ ] Test URLs added to `k6-urls-data` ConfigMap
- [ ] Namespace updated (if not using `prod`)
- [ ] `APP_LABEL` matches your application
- [ ] Node selector configured or removed
- [ ] Resource limits appropriate for test scale
- [ ] Success thresholds appropriate for your SLA
- [ ] HTTP headers include required authentication/host
- [ ] RBAC permissions compatible with cluster policies
- [ ] ConfigMaps deployed: `kubectl apply -f manifests/k6-stress-configmaps.yaml`
- [ ] Target application running and healthy

## 🧪 Testing Configuration

**Dry run:**
```bash
# Validate manifests
kubectl apply -f manifests/k6-stress-configmaps.yaml --dry-run=client
kubectl apply -f manifests/jobs/stress/stress-50rps.yaml --dry-run=client

# Test with low RPS first
./scripts/run-single-stress-test.sh 50
```

**Verify connectivity:**
```bash
# Deploy a test pod
kubectl run test-pod --rm -it --image=alpine/curl --restart=Never -- \
  curl -v http://your-service.your-namespace.svc.cluster.local/health
```

**Check metrics availability:**
```bash
kubectl top pods -n your-namespace
kubectl top nodes
```

## 📝 Examples

### Example 1: E-commerce Site

```yaml
# BASE_URL
value: "https://shop.example.com"

# URLs
urls-1.json: |
  {
    "urls": [
      "/",
      "/products",
      "/products/best-sellers",
      "/cart",
      "/search?q=shoes"
    ]
  }

# APP_LABEL
value: "frontend"

# Thresholds (strict SLA)
'http_req_duration{expected_response:true}': ['p(95)<1500', 'p(99)<3000']
'errors': ['rate<0.01']
```

### Example 2: API Testing

```yaml
# BASE_URL
value: "https://api.example.com"

# URLs
urls-1.json: |
  {
    "urls": [
      "/v1/users",
      "/v1/products",
      "/v1/orders",
      "/health"
    ]
  }

# Headers (add authentication)
headers: {
  'Authorization': 'Bearer YOUR_TOKEN',
  'Content-Type': 'application/json',
}

# Connection reuse (API clients typically use keep-alive)
noConnectionReuse: false
```

### Example 3: Internal Service

```yaml
# BASE_URL (cluster-internal)
value: "http://backend-service.production.svc.cluster.local:8080"

# Namespace
namespace: production

# APP_LABEL
value: "backend"

# No TLS
insecureSkipTLSVerify: true
```

## 🆘 Help

For issues with configuration:

1. Check logs: `kubectl logs -n prod -l app=k6-stress-test -f`
2. Validate YAML: `kubectl apply --dry-run=client -f <file>`
3. Test connectivity: `kubectl run test-pod --rm -it --image=alpine/curl -- curl <url>`
4. Review [README.md](README.md) troubleshooting section
