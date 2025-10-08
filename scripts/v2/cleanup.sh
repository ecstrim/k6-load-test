#!/bin/bash
# K6 Load Test Cleanup Script v2.0
# Clean up K6 test resources from Kubernetes cluster

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Parse arguments
show_help() {
    cat << EOF
K6 Load Test Cleanup Script v2.0

Usage: $0 [OPTIONS]

Options:
  --all                Delete all K6 resources (jobs, configmaps, RBAC)
  --jobs               Delete only K6 jobs
  --completed          Delete only completed jobs
  --failed             Delete only failed jobs
  --older-than TIME    Delete jobs older than TIME (e.g., 1h, 2d)
  --type TYPE          Delete jobs of specific type (stress, spike, soak, load)
  --rps RPS            Delete jobs of specific RPS level
  --namespace NS       Kubernetes namespace (default: prod)
  --dry-run            Show what would be deleted without deleting
  --preserve-results   Keep ConfigMaps with test results
  -h, --help           Show this help message

Examples:
  # Delete all K6 resources
  $0 --all

  # Delete only completed jobs
  $0 --completed

  # Delete jobs older than 1 hour
  $0 --older-than 1h

  # Delete specific test type
  $0 --type stress

  # Dry run to see what would be deleted
  $0 --all --dry-run

  # Delete jobs but keep results
  $0 --jobs --preserve-results

EOF
}

# Initialize variables
DELETE_ALL=false
DELETE_JOBS=false
DELETE_COMPLETED=false
DELETE_FAILED=false
OLDER_THAN=""
TEST_TYPE=""
RPS=""
NAMESPACE="prod"
DRY_RUN=false
PRESERVE_RESULTS=false

# Parse arguments
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            DELETE_ALL=true
            shift
            ;;
        --jobs)
            DELETE_JOBS=true
            shift
            ;;
        --completed)
            DELETE_COMPLETED=true
            shift
            ;;
        --failed)
            DELETE_FAILED=true
            shift
            ;;
        --older-than)
            OLDER_THAN="$2"
            shift 2
            ;;
        --type)
            TEST_TYPE="$2"
            shift 2
            ;;
        --rps)
            RPS="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --preserve-results)
            PRESERVE_RESULTS=true
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

log_section "K6 Load Test Cleanup v2.0"
log_info "Namespace: $NAMESPACE"
if [ "$DRY_RUN" = true ]; then
    log_warn "DRY RUN MODE - No resources will be deleted"
fi
echo ""

# Function to delete resource
delete_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-$NAMESPACE}

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would delete: $resource_type/$resource_name"
    else
        log_info "Deleting: $resource_type/$resource_name"
        kubectl delete "$resource_type" "$resource_name" -n "$namespace" --ignore-not-found=true
    fi
}

# Delete all resources
if [ "$DELETE_ALL" = true ]; then
    log_section "Deleting All K6 Resources"

    # Delete all K6 jobs
    log_info "Finding K6 jobs..."
    JOBS=$(kubectl get jobs -n "$NAMESPACE" -l app=k6-load-test -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$JOBS" ]; then
        for job in $JOBS; do
            delete_resource "job" "$job"
        done
    else
        log_info "No K6 jobs found"
    fi

    # Delete ConfigMaps (unless preserving results)
    if [ "$PRESERVE_RESULTS" = false ]; then
        log_info "Finding K6 ConfigMaps..."
        CONFIGMAPS=$(kubectl get configmaps -n "$NAMESPACE" | grep -E '(k6-scripts-v2|k6-urls-data|k6-stress-script)' | awk '{print $1}' || echo "")

        if [ -n "$CONFIGMAPS" ]; then
            for cm in $CONFIGMAPS; do
                delete_resource "configmap" "$cm"
            done
        else
            log_info "No K6 ConfigMaps found"
        fi
    else
        log_info "Preserving ConfigMaps (--preserve-results)"
    fi

    # Delete RBAC resources
    log_info "Deleting RBAC resources..."
    delete_resource "serviceaccount" "k6-test-runner"
    delete_resource "role" "k6-metrics-reader"
    delete_resource "rolebinding" "k6-metrics-reader"
    delete_resource "clusterrole" "k6-node-metrics-reader" ""
    delete_resource "clusterrolebinding" "k6-node-metrics-reader" ""

    echo ""
    log_info "✅ Cleanup complete!"
    exit 0
fi

# Delete jobs with filters
if [ "$DELETE_JOBS" = true ] || [ "$DELETE_COMPLETED" = true ] || [ "$DELETE_FAILED" = true ] || [ -n "$TEST_TYPE" ] || [ -n "$RPS" ]; then
    log_section "Deleting K6 Jobs"

    # Build label selector
    LABEL_SELECTOR="app=k6-load-test"
    if [ -n "$TEST_TYPE" ]; then
        LABEL_SELECTOR="${LABEL_SELECTOR},test-type=${TEST_TYPE}"
    fi
    if [ -n "$RPS" ]; then
        LABEL_SELECTOR="${LABEL_SELECTOR},rps=${RPS}"
    fi

    log_info "Label selector: $LABEL_SELECTOR"

    # Get jobs
    JOBS=$(kubectl get jobs -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o json 2>/dev/null || echo '{"items":[]}')

    # Parse jobs
    JOB_COUNT=$(echo "$JOBS" | jq -r '.items | length')
    log_info "Found $JOB_COUNT job(s)"

    if [ "$JOB_COUNT" -eq 0 ]; then
        log_info "No jobs to delete"
        exit 0
    fi

    # Filter jobs
    for i in $(seq 0 $((JOB_COUNT - 1))); do
        JOB_NAME=$(echo "$JOBS" | jq -r ".items[$i].metadata.name")
        JOB_STATUS=$(echo "$JOBS" | jq -r ".items[$i].status.conditions[0].type // \"Unknown\"")
        JOB_TIMESTAMP=$(echo "$JOBS" | jq -r ".items[$i].metadata.creationTimestamp")

        # Check if should delete based on status
        SHOULD_DELETE=false

        if [ "$DELETE_JOBS" = true ]; then
            SHOULD_DELETE=true
        elif [ "$DELETE_COMPLETED" = true ] && [ "$JOB_STATUS" = "Complete" ]; then
            SHOULD_DELETE=true
        elif [ "$DELETE_FAILED" = true ] && [ "$JOB_STATUS" = "Failed" ]; then
            SHOULD_DELETE=true
        fi

        # Check age if older-than specified
        if [ -n "$OLDER_THAN" ] && [ "$SHOULD_DELETE" = true ]; then
            # Convert timestamp to epoch
            JOB_EPOCH=$(date -d "$JOB_TIMESTAMP" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$JOB_TIMESTAMP" +%s 2>/dev/null || echo 0)
            NOW_EPOCH=$(date +%s)
            AGE_SECONDS=$((NOW_EPOCH - JOB_EPOCH))

            # Parse OLDER_THAN (supports: 1h, 2d, 30m)
            case $OLDER_THAN in
                *h)
                    THRESHOLD_SECONDS=$((${OLDER_THAN%h} * 3600))
                    ;;
                *d)
                    THRESHOLD_SECONDS=$((${OLDER_THAN%d} * 86400))
                    ;;
                *m)
                    THRESHOLD_SECONDS=$((${OLDER_THAN%m} * 60))
                    ;;
                *)
                    log_error "Invalid time format: $OLDER_THAN (use: 1h, 2d, 30m)"
                    exit 1
                    ;;
            esac

            if [ "$AGE_SECONDS" -lt "$THRESHOLD_SECONDS" ]; then
                SHOULD_DELETE=false
            fi
        fi

        # Delete if criteria met
        if [ "$SHOULD_DELETE" = true ]; then
            delete_resource "job" "$JOB_NAME"
        fi
    done

    echo ""
    log_info "✅ Cleanup complete!"
fi
