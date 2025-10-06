#!/bin/bash
# Run a single K6 stress test at specified RPS level
# Usage: ./run-single-stress-test.sh <RPS>
# Example: ./run-single-stress-test.sh 100

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOGS_DIR="${PROJECT_ROOT}/logs"
MANIFESTS_DIR="${PROJECT_ROOT}/manifests"
NAMESPACE="prod"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
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

# Validate input
if [ $# -ne 1 ]; then
    log_error "Usage: $0 <RPS>"
    log_info "Available RPS levels: 50, 100, 150, 200, 300, 400, 500, 750, 1000, 1500"
    exit 1
fi

RPS=$1
VALID_RPS="50 100 150 200 300 400 500 750 1000 1500"

if ! echo "$VALID_RPS" | grep -wq "$RPS"; then
    log_error "Invalid RPS level: $RPS"
    log_info "Valid RPS levels: $VALID_RPS"
    exit 1
fi

# Create logs directory if it doesn't exist
mkdir -p "${LOGS_DIR}"

# Generate timestamp for log file
TIMESTAMP=$(date +"%Y-%m-%d-%H%M%S")
LOG_FILE="${LOGS_DIR}/ingress-stress-test-${RPS}rps-${TIMESTAMP}.log"

log_info "Starting K6 stress test: ${RPS} RPS"
log_info "Log file: ${LOG_FILE}"
log_info ""

# Apply ConfigMaps if they don't exist
log_info "Ensuring ConfigMaps are deployed..."
kubectl apply -f "${MANIFESTS_DIR}/configmaps/k6-stress-configmaps.yaml" -n ${NAMESPACE} 2>&1 | tee -a "${LOG_FILE}"

# Apply RBAC if it doesn't exist (from the 50rps manifest)
log_info "Ensuring RBAC is configured..."
kubectl apply -f "${MANIFESTS_DIR}/jobs/stress/stress-50rps.yaml" 2>&1 | grep -E '(serviceaccount|role|clusterrole)' | tee -a "${LOG_FILE}" || true

# Clean up any existing job
JOB_NAME="k6-stress-${RPS}rps"
if kubectl get job "${JOB_NAME}" -n ${NAMESPACE} &>/dev/null; then
    log_warn "Cleaning up existing job: ${JOB_NAME}"
    kubectl delete job "${JOB_NAME}" -n ${NAMESPACE} --wait=true 2>&1 | tee -a "${LOG_FILE}"
fi

# Apply job manifest
log_info "Deploying stress test job: ${JOB_NAME}"
kubectl apply -f "${MANIFESTS_DIR}/jobs/stress/stress-${RPS}rps.yaml" 2>&1 | tee -a "${LOG_FILE}"

# Wait for pod to be created
log_info "Waiting for pod to start..."
sleep 3

# Get pod name
POD_NAME=$(kubectl get pods -n ${NAMESPACE} -l "app=k6-stress-test,rps=${RPS}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POD_NAME" ]; then
    log_error "Failed to find pod for job ${JOB_NAME}"
    exit 1
fi

log_info "Pod name: ${POD_NAME}"
log_info "Streaming logs (also saving to ${LOG_FILE})..."
log_info "==========================================="
echo "" | tee -a "${LOG_FILE}"

# Stream logs to both console and file
kubectl logs -f "${POD_NAME}" -n ${NAMESPACE} 2>&1 | tee -a "${LOG_FILE}"

# Wait for job to complete
log_info ""
log_info "Waiting for job to complete..."
kubectl wait --for=condition=complete --timeout=10m "job/${JOB_NAME}" -n ${NAMESPACE} 2>&1 | tee -a "${LOG_FILE}"

# Get final job status
JOB_STATUS=$(kubectl get job "${JOB_NAME}" -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "Unknown")

if [ "$JOB_STATUS" == "True" ]; then
    log_info "✅ Test completed successfully!"
    log_info "Results saved to: ${LOG_FILE}"
    EXIT_CODE=0
else
    log_error "❌ Test failed or did not complete"
    log_info "Check logs at: ${LOG_FILE}"
    EXIT_CODE=1
fi

# Summary
echo "" | tee -a "${LOG_FILE}"
log_info "==========================================="
log_info "Test Summary:"
log_info "  RPS Level: ${RPS}"
log_info "  Job Name: ${JOB_NAME}"
log_info "  Log File: ${LOG_FILE}"
log_info "  Status: ${JOB_STATUS}"
log_info "==========================================="

exit ${EXIT_CODE}
