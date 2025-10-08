# K6 Load Testing Framework v2.0

A powerful, flexible Kubernetes-based load testing framework using Grafana K6.

## What's New in v2.0

### Major Improvements

- **Parameterized Deployment**: Single template replaces 12+ separate manifest files
- **Central Configuration**: All settings in one `config.yaml` file
- **Multiple Test Scenarios**: Stress, Spike, Soak, and Load tests
- **Result Persistence**: Store and compare test results over time
- **Automated Reporting**: Generate markdown reports with trends
- **Smart Resource Allocation**: Auto-sizing based on RPS level
- **Better CLI**: Improved scripts with more options

### Architecture

```
┌─────────────────────────────────────────────┐
│         Central Configuration               │
│            (config.yaml)                    │
└─────────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        │                       │
        ▼                       ▼
┌──────────────┐        ┌──────────────┐
│  Deployment  │        │  Templates   │
│   Scripts    │───────▶│  & Scripts   │
└──────────────┘        └──────────────┘
        │                       │
        └───────────┬───────────┘
                    ▼
        ┌───────────────────────┐
        │   Kubernetes Jobs     │
        │  (K6 Test Runners)    │
        └───────────────────────┘
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
┌──────────────┐        ┌──────────────┐
│   Metrics    │        │   Results    │
│  Collection  │        │   Storage    │
└──────────────┘        └──────────────┘
```

## Quick Start

### 1. Prerequisites

- Kubernetes cluster with kubectl configured
- K6 node pool with appropriate labels/taints (optional)
- metrics-server for resource metrics collection

### 2. Configure Your Environment

Edit `config.yaml` to match your environment:

```yaml
kubernetes:
  namespace: prod
  nodeSelector:
    workload: k6

test:
  target:
    baseUrl: "http://your-service.namespace.svc.cluster.local"
    appLabel: "your-app"
    namespace: "prod"
```

### 3. Deploy RBAC (One-time Setup)

```bash
# Create ServiceAccount and RBAC
kubectl apply -f manifests/v2/rbac.yaml
```

### 4. Run Your First Test

```bash
# Deploy a stress test at 100 RPS
./scripts/v2/deploy-test.sh --type stress --rps 100 --wait

# Deploy a spike test
./scripts/v2/deploy-test.sh --type spike --rps 50 --wait

# Deploy a soak test
./scripts/v2/deploy-test.sh --type soak --rps 100 --duration 30m
```

## Test Scenarios

### Stress Test
Constant RPS load to find breaking points.

```bash
./scripts/v2/deploy-test.sh --type stress --rps 200
```

**Use Case**: Find maximum capacity, identify bottlenecks

### Spike Test
Sudden traffic surge to test auto-scaling.

```bash
./scripts/v2/deploy-test.sh --type spike --rps 100
```

- Baseline traffic at specified RPS
- Sudden 5x spike for 30 seconds
- Recovery period

**Use Case**: Test auto-scaling, cache warming, sudden traffic events

### Soak Test
Sustained load over extended period (30+ minutes).

```bash
./scripts/v2/deploy-test.sh --type soak --rps 100 --duration 1h
```

**Use Case**: Memory leak detection, performance degradation over time

### Load Test
Gradual ramp up and down to simulate realistic traffic patterns.

```bash
./scripts/v2/deploy-test.sh --type load --rps 200
```

- 5min ramp up to target RPS
- 10min sustained load
- 5min ramp down

**Use Case**: Realistic traffic simulation, gradual scaling validation

## CLI Reference

### Deploy Test

```bash
./scripts/v2/deploy-test.sh [OPTIONS]

Required:
  --type TYPE          Test type: stress, spike, soak, load
  --rps RPS            Target requests per second

Optional:
  --duration TIME      Test duration (default: from config.yaml)
  --namespace NS       Kubernetes namespace
  --app-label LABEL    Application label for metrics
  --base-url URL       Target base URL
  --config FILE        Custom config file
  --wait               Wait for completion and stream logs
  --save-results       Save results to ConfigMap
```

### Run Test Suite

```bash
./scripts/v2/run-suite.sh [OPTIONS]

Options:
  --type TYPE          Test type or 'all' (default: stress)
  --rps-levels "LIST"  Custom RPS levels
  --duration TIME      Override default duration
  --delay SECONDS      Delay between tests (default: 30)
  --namespace NS       Kubernetes namespace
```

**Example**: Run all stress tests from config.yaml

```bash
./scripts/v2/run-suite.sh --type stress
```

### Compare Results

```bash
./scripts/v2/compare-results.sh [OPTIONS]

Options:
  --type TYPE          Test type
  --rps RPS            RPS level
  --last N             Compare last N runs (default: 5)
```

**Example**: Compare last 10 runs at 100 RPS

```bash
./scripts/v2/compare-results.sh --type stress --rps 100 --last 10
```

### Generate Report

```bash
./scripts/v2/generate-report.sh [OPTIONS]

Options:
  --type TYPE          Test type
  --rps RPS            RPS level
  --last N             Include last N runs (default: 10)
  --output FILE        Output file path
```

**Example**: Generate markdown report

```bash
./scripts/v2/generate-report.sh --type stress --rps 100
# Output: reports/stress-100rps-2025-10-08.md
```

### Cleanup

```bash
./scripts/v2/cleanup.sh [OPTIONS]

Options:
  --all                Delete all K6 resources
  --jobs               Delete only jobs
  --completed          Delete only completed jobs
  --failed             Delete only failed jobs
  --older-than TIME    Delete jobs older than TIME (1h, 2d)
  --type TYPE          Delete specific test type
  --rps RPS            Delete specific RPS level
  --dry-run            Show what would be deleted
  --preserve-results   Keep ConfigMaps with results
```

**Examples**:

```bash
# Delete all completed jobs
./scripts/v2/cleanup.sh --completed

# Delete jobs older than 1 hour
./scripts/v2/cleanup.sh --older-than 1h

# Dry run to preview
./scripts/v2/cleanup.sh --all --dry-run

# Delete everything
./scripts/v2/cleanup.sh --all
```

## Configuration Reference

### config.yaml Structure

```yaml
kubernetes:
  namespace: prod                    # Target namespace
  serviceAccountName: k6-test-runner # Service account
  nodeSelector:                      # Node selection
    workload: k6
  tolerations:                       # Tolerations for taints
    - key: workload
      operator: Equal
      value: k6
      effect: NoSchedule
  resources:                         # Resource tiers
    low:    # <= 50 RPS
      requests: { cpu: 100m, memory: 256Mi }
      limits: { cpu: 500m, memory: 1Gi }
    medium: # 51-500 RPS
      requests: { cpu: 200m, memory: 512Mi }
      limits: { cpu: 1000m, memory: 2Gi }
    high:   # > 500 RPS
      requests: { cpu: 500m, memory: 1Gi }
      limits: { cpu: 2000m, memory: 4Gi }

test:
  target:
    baseUrl: "http://..."            # Target service URL
    appLabel: "my-app"               # App label for metrics
    namespace: "prod"                # App namespace
  defaults:
    duration: "2m"                   # Default test duration
    thresholds:
      errorRate: 0.02                # Max 2% error rate
      p95Latency: 2000               # Max 2000ms p95
  rpsLevels:                         # RPS levels for suites
    - 5
    - 10
    - 50
    - 100
    # ... more levels

scenarios:
  stress:
    enabled: true
  spike:
    enabled: true
    spikeMultiplier: 5               # 5x traffic spike
    spikeDuration: "30s"
  soak:
    enabled: true
    duration: "30m"
  load:
    enabled: true
    rampUpTime: "5m"
    sustainTime: "10m"
    rampDownTime: "5m"

metrics:
  enabled: true
  collectionWindow: 10               # Last 10 seconds
  targets:                           # What to collect
    - deployment
    - coredns
    - ingressController
    - nodepool

results:
  enabled: true
  storage: configmap                 # configmap or pvc
  retention: 10                      # Keep last 10 results
  comparisonEnabled: true

job:
  ttlSecondsAfterFinished: 600       # Auto-cleanup after 10min
  backoffLimit: 0
  parallelism: 1
  completions: 1
```

## Directory Structure

```
k6-load-test/
├── config.yaml                      # Central configuration
├── manifests/
│   ├── v2/
│   │   ├── templates/
│   │   │   └── parameterized-job.yaml  # Job template
│   │   └── rbac.yaml               # RBAC resources
│   ├── k6-stress-configmaps.yaml   # K6 scripts & data
│   └── jobs/stress/                # v1.0 (deprecated)
├── k6-scripts/
│   ├── stress-test.js              # v1.0 stress test
│   └── v2/scenarios/
│       ├── spike-test.js           # Spike scenario
│       ├── soak-test.js            # Soak scenario
│       └── load-test.js            # Load scenario
├── scripts/
│   └── v2/
│       ├── deploy-test.sh          # Deploy single test
│       ├── run-suite.sh            # Run test suite
│       ├── compare-results.sh      # Compare results
│       ├── generate-report.sh      # Generate reports
│       └── cleanup.sh              # Cleanup resources
├── results/                         # Test results (JSON)
├── reports/                         # Generated reports (MD)
└── logs/                            # Execution logs
```

## Migration from v1.0

v1.0 scripts and manifests continue to work. To migrate to v2.0:

1. **Test v2.0 alongside v1.0** - Both versions coexist
2. **Update config.yaml** with your settings
3. **Deploy RBAC** for v2.0 (separate from v1.0)
4. **Run tests** using new scripts in `scripts/v2/`
5. **Gradually phase out** v1.0 manifests

No breaking changes - migrate at your own pace.

## Best Practices

### 1. Start Small
```bash
# Begin with low RPS to validate setup
./scripts/v2/deploy-test.sh --type stress --rps 5 --wait
```

### 2. Use Dry Run for Cleanup
```bash
# Preview what will be deleted
./scripts/v2/cleanup.sh --all --dry-run
```

### 3. Save Results for Comparison
```bash
# Enable result saving
./scripts/v2/deploy-test.sh --type stress --rps 100 --save-results
```

### 4. Monitor Resource Usage
```bash
# Watch K6 pods
kubectl get pods -n prod -l app=k6-load-test -w

# Check job status
kubectl get jobs -n prod -l app=k6-load-test
```

### 5. Generate Regular Reports
```bash
# Weekly performance report
./scripts/v2/generate-report.sh --type stress --rps 100 --last 20
```

## Troubleshooting

### Job Fails to Schedule

**Symptom**: Pod stays in Pending state

**Solution**: Check node selector and tolerations
```bash
kubectl describe pod <pod-name> -n prod
```

Update `config.yaml` node selector to match your cluster.

### Script Not Found Error

**Symptom**: `/scripts/discover-resources.sh: not found`

**Solution**: Ensure ConfigMaps are deployed
```bash
kubectl apply -f manifests/k6-stress-configmaps.yaml -n prod
```

### High Error Rate

**Symptom**: All requests return 404 or 500

**Solution**: Check base URL and target service
```yaml
# In config.yaml
test:
  target:
    baseUrl: "http://correct-service.namespace.svc.cluster.local"
```

### Results Not Saving

**Symptom**: compare-results.sh finds no files

**Solution**: Run tests with --save-results flag
```bash
./scripts/v2/deploy-test.sh --type stress --rps 100 --save-results --wait
```

## Examples

### Example 1: Find Breaking Point
```bash
# Run increasing stress tests
for rps in 50 100 200 500 1000; do
  ./scripts/v2/deploy-test.sh --type stress --rps $rps --wait --save-results
  sleep 60  # Cool down between tests
done

# Compare results
./scripts/v2/compare-results.sh --type stress --rps 500
./scripts/v2/generate-report.sh --type stress --rps 500
```

### Example 2: Test Auto-Scaling
```bash
# Run spike test to trigger HPA
./scripts/v2/deploy-test.sh --type spike --rps 100 --wait

# Monitor pod scaling
kubectl get hpa -n prod -w
```

### Example 3: Memory Leak Detection
```bash
# Long soak test
./scripts/v2/deploy-test.sh --type soak --rps 100 --duration 2h --wait

# Check for memory increase over time in logs
```

### Example 4: Performance Regression Testing
```bash
# Before deployment
./scripts/v2/deploy-test.sh --type stress --rps 200 --save-results --wait

# After deployment (new version)
./scripts/v2/deploy-test.sh --type stress --rps 200 --save-results --wait

# Compare
./scripts/v2/compare-results.sh --type stress --rps 200 --last 2
```

## Support

For issues or questions:
- Check this documentation
- Review `config.yaml` settings
- Use `--dry-run` to preview actions
- Check Kubernetes events: `kubectl get events -n prod`

## Version History

- **v2.0** (2025-10-08): Parameterized deployment, multiple scenarios, result persistence
- **v1.0** (2025-10-02): Initial implementation with 12 RPS levels

---

*K6 Load Testing Framework v2.0*
