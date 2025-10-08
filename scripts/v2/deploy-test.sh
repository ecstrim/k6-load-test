#!/bin/bash
# K6 Load Test Deployment Script v2.0
# Deploy parameterized K6 load tests using central configuration

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/config.yaml"
TEMPLATE_FILE="${PROJECT_ROOT}/manifests/v2/templates/parameterized-job.yaml"
LOGS_DIR="${PROJECT_ROOT}/logs"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_section() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=========================================${NC}"
}

# Function to parse YAML (simple key-value extraction)
get_yaml_value() {
    local file=$1
    local key=$2
    local default=$3

    # Try to get value using yq if available, otherwise use grep/sed
    if command -v yq &> /dev/null; then
        yq eval "$key" "$file" 2>/dev/null || echo "$default"
    else
        grep "^  ${key##*.}:" "$file" | head -1 | sed 's/.*: //' | tr -d '"' || echo "$default"
    fi
}

# Function to determine resource tier based on RPS
get_resource_tier() {
    local rps=$1

    if [ "$rps" -le 50 ]; then
        echo "low"
    elif [ "$rps" -le 500 ]; then
        echo "medium"
    else
        echo "high"
    fi
}

# Parse command line arguments
show_help() {
    cat << EOF
K6 Load Test Deployment Script v2.0

Usage: $0 [OPTIONS]

Required Options:
  --type TYPE          Test type: stress, spike, soak, load
  --rps RPS            Target requests per second

Optional:
  --duration TIME      Test duration (default: from config.yaml)
  --namespace NS       Kubernetes namespace (default: from config.yaml)
  --app-label LABEL    Application label for metrics (default: from config.yaml)
  --base-url URL       Target base URL (default: from config.yaml)
  --config FILE        Custom config file (default: config.yaml)
  --wait               Wait for test completion and stream logs
  --save-results       Save test results to ConfigMap
  -h, --help           Show this help message

Examples:
  # Deploy 100 RPS stress test
  $0 --type stress --rps 100

  # Deploy spike test with custom duration
  $0 --type spike --rps 50 --duration 5m

  # Deploy soak test and wait for completion
  $0 --type soak --rps 100 --wait

  # Deploy with custom config
  $0 --type load --rps 200 --config custom-config.yaml

EOF
}

# Initialize variables
TEST_TYPE=""
RPS=""
DURATION=""
NAMESPACE=""
APP_LABEL=""
BASE_URL=""
CUSTOM_CONFIG=""
WAIT_FOR_COMPLETION=false
SAVE_RESULTS="false"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --type)
            TEST_TYPE="$2"
            shift 2
            ;;
        --rps)
            RPS="$2"
            shift 2
            ;;
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --app-label)
            APP_LABEL="$2"
            shift 2
            ;;
        --base-url)
            BASE_URL="$2"
            shift 2
            ;;
        --config)
            CUSTOM_CONFIG="$2"
            CONFIG_FILE="$2"
            shift 2
            ;;
        --wait)
            WAIT_FOR_COMPLETION=true
            shift
            ;;
        --save-results)
            SAVE_RESULTS="true"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$TEST_TYPE" ] || [ -z "$RPS" ]; then
    log_error "Missing required arguments"
    show_help
    exit 1
fi

# Validate test type
if [[ ! "$TEST_TYPE" =~ ^(stress|spike|soak|load)$ ]]; then
    log_error "Invalid test type: $TEST_TYPE (must be: stress, spike, soak, or load)"
    exit 1
fi

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

# Check if template file exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    log_error "Template file not found: $TEMPLATE_FILE"
    exit 1
fi

log_section "K6 Load Test Deployment v2.0"
log_info "Test Type: $TEST_TYPE"
log_info "RPS: $RPS"
log_info "Config File: $CONFIG_FILE"
echo ""

# Load configuration from YAML
NAMESPACE="${NAMESPACE:-prod}"
APP_LABEL="${APP_LABEL:-my-app}"
BASE_URL="${BASE_URL:-http://ingress-nginx-controller.ingress-nginx.svc.cluster.local}"
DURATION="${DURATION:-2m}"

# Determine resource tier
RESOURCE_TIER=$(get_resource_tier "$RPS")
log_info "Resource Tier: $RESOURCE_TIER (based on RPS: $RPS)"

# Set resources based on tier (hardcoded for now, could parse from YAML)
case $RESOURCE_TIER in
    low)
        CPU_REQUEST="100m"
        MEMORY_REQUEST="256Mi"
        CPU_LIMIT="500m"
        MEMORY_LIMIT="1Gi"
        ;;
    medium)
        CPU_REQUEST="200m"
        MEMORY_REQUEST="512Mi"
        CPU_LIMIT="1000m"
        MEMORY_LIMIT="2Gi"
        ;;
    high)
        CPU_REQUEST="500m"
        MEMORY_REQUEST="1Gi"
        CPU_LIMIT="2000m"
        MEMORY_LIMIT="4Gi"
        ;;
esac

# Determine test script path based on type
case $TEST_TYPE in
    stress)
        TEST_SCRIPT="/scripts/stress-test.js"
        ;;
    spike)
        TEST_SCRIPT="/scripts/v2/scenarios/spike-test.js"
        SPIKE_MULTIPLIER="${SPIKE_MULTIPLIER:-5}"
        SPIKE_DURATION="${SPIKE_DURATION:-30s}"
        ;;
    soak)
        TEST_SCRIPT="/scripts/v2/scenarios/soak-test.js"
        DURATION="${DURATION:-30m}"
        ;;
    load)
        TEST_SCRIPT="/scripts/v2/scenarios/load-test.js"
        RAMP_UP_TIME="${RAMP_UP_TIME:-5m}"
        SUSTAIN_TIME="${SUSTAIN_TIME:-10m}"
        RAMP_DOWN_TIME="${RAMP_DOWN_TIME:-5m}"
        ;;
esac

# Generate job manifest from template
JOB_NAME="k6-${TEST_TYPE}-${RPS}rps"
TEMP_MANIFEST=$(mktemp)

log_info "Generating manifest for job: $JOB_NAME"

# Substitute variables in template
sed -e "s|{{TEST_TYPE}}|${TEST_TYPE}|g" \
    -e "s|{{RPS}}|${RPS}|g" \
    -e "s|{{NAMESPACE}}|${NAMESPACE}|g" \
    -e "s|{{SERVICE_ACCOUNT}}|k6-test-runner|g" \
    -e "s|{{NODE_SELECTOR_KEY}}|workload|g" \
    -e "s|{{NODE_SELECTOR_VALUE}}|k6|g" \
    -e "s|{{TOLERATION_KEY}}|workload|g" \
    -e "s|{{TOLERATION_VALUE}}|k6|g" \
    -e "s|{{TTL_SECONDS}}|600|g" \
    -e "s|{{DURATION}}|${DURATION}|g" \
    -e "s|{{BASE_URL}}|${BASE_URL}|g" \
    -e "s|{{TEST_SCRIPT}}|${TEST_SCRIPT}|g" \
    -e "s|{{URL_DATA_PATH}}|/data/urls-1.json|g" \
    -e "s|{{APP_LABEL}}|${APP_LABEL}|g" \
    -e "s|{{SAVE_RESULTS}}|${SAVE_RESULTS}|g" \
    -e "s|{{SPIKE_MULTIPLIER}}|${SPIKE_MULTIPLIER:-5}|g" \
    -e "s|{{SPIKE_DURATION}}|${SPIKE_DURATION:-30s}|g" \
    -e "s|{{RAMP_UP_TIME}}|${RAMP_UP_TIME:-5m}|g" \
    -e "s|{{SUSTAIN_TIME}}|${SUSTAIN_TIME:-10m}|g" \
    -e "s|{{RAMP_DOWN_TIME}}|${RAMP_DOWN_TIME:-5m}|g" \
    -e "s|{{CPU_REQUEST}}|${CPU_REQUEST}|g" \
    -e "s|{{MEMORY_REQUEST}}|${MEMORY_REQUEST}|g" \
    -e "s|{{CPU_LIMIT}}|${CPU_LIMIT}|g" \
    -e "s|{{MEMORY_LIMIT}}|${MEMORY_LIMIT}|g" \
    "$TEMPLATE_FILE" > "$TEMP_MANIFEST"

# Ensure ConfigMaps exist
log_info "Ensuring ConfigMaps are deployed..."
kubectl apply -f "${PROJECT_ROOT}/manifests/k6-stress-configmaps.yaml" -n "$NAMESPACE" 2>&1 | grep -E '(configured|created|unchanged)' || true

# Create logs directory
mkdir -p "$LOGS_DIR"

# Clean up any existing job with same name
if kubectl get job "$JOB_NAME" -n "$NAMESPACE" &>/dev/null; then
    log_warn "Cleaning up existing job: $JOB_NAME"
    kubectl delete job "$JOB_NAME" -n "$NAMESPACE" --wait=true 2>&1 | tee -a "$LOGS_DIR/deploy.log" || true
    sleep 2
fi

# Deploy the job
log_info "Deploying job: $JOB_NAME"
kubectl apply -f "$TEMP_MANIFEST"

# Clean up temp file
rm -f "$TEMP_MANIFEST"

log_info "Job deployed successfully!"
echo ""

# Wait for completion if requested
if [ "$WAIT_FOR_COMPLETION" = true ]; then
    log_info "Waiting for pod to start..."
    sleep 3

    # Get pod name
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l "app=k6-load-test,test-type=${TEST_TYPE},rps=${RPS}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$POD_NAME" ]; then
        log_error "Failed to find pod for job $JOB_NAME"
        exit 1
    fi

    log_info "Pod name: $POD_NAME"
    log_info "Streaming logs..."
    log_section "Test Output"

    # Stream logs
    kubectl logs -f "$POD_NAME" -n "$NAMESPACE" -c k6 2>&1

    # Wait for job completion
    log_info "Waiting for job to complete..."
    kubectl wait --for=condition=complete --timeout=60m "job/${JOB_NAME}" -n "$NAMESPACE" 2>&1 || true

    # Get job status
    JOB_STATUS=$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "Unknown")

    echo ""
    log_section "Test Summary"
    if [ "$JOB_STATUS" == "True" ]; then
        log_info "✅ Test completed successfully!"
    else
        log_error "❌ Test failed or did not complete"
    fi
else
    log_info "Job deployed. Use the following commands to monitor:"
    echo ""
    echo "  # Get pod name"
    echo "  kubectl get pods -n $NAMESPACE -l app=k6-load-test,test-type=${TEST_TYPE},rps=${RPS}"
    echo ""
    echo "  # Stream logs"
    echo "  kubectl logs -f <POD_NAME> -n $NAMESPACE -c k6"
    echo ""
    echo "  # Check job status"
    echo "  kubectl get job $JOB_NAME -n $NAMESPACE"
fi

echo ""
log_info "==========================================="
