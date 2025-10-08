#!/bin/bash
# K6 Test Results Comparison Script v2.0
# Compare test results across multiple runs

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS_DIR="${PROJECT_ROOT}/results"

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

log_section() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=========================================${NC}"
}

# Parse arguments
show_help() {
    cat << EOF
K6 Test Results Comparison Script v2.0

Usage: $0 [OPTIONS]

Options:
  --type TYPE          Test type (stress, spike, soak, load)
  --rps RPS            RPS level to compare
  --last N             Compare last N test runs (default: 5)
  --namespace NS       Kubernetes namespace (default: prod)
  -h, --help           Show this help message

Examples:
  # Compare last 5 stress tests at 100 RPS
  $0 --type stress --rps 100

  # Compare last 10 spike tests
  $0 --type spike --rps 50 --last 10

EOF
}

# Initialize variables
TEST_TYPE=""
RPS=""
LAST=5
NAMESPACE="prod"

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
        --last)
            LAST="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
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

# Validate arguments
if [ -z "$TEST_TYPE" ] || [ -z "$RPS" ]; then
    log_error "Missing required arguments"
    show_help
    exit 1
fi

log_section "K6 Test Results Comparison"
log_info "Test Type: $TEST_TYPE"
log_info "RPS: $RPS"
log_info "Comparing last $LAST runs"
echo ""

# Check if results directory exists
if [ ! -d "$RESULTS_DIR" ]; then
    log_error "Results directory not found: $RESULTS_DIR"
    log_info "Run tests with --save-results flag to generate results"
    exit 1
fi

# Find result files matching pattern
PATTERN="${TEST_TYPE}-${RPS}rps-*.json"
RESULT_FILES=($(ls -t "${RESULTS_DIR}"/${PATTERN} 2>/dev/null | head -n "$LAST" || true))

if [ ${#RESULT_FILES[@]} -eq 0 ]; then
    log_error "No result files found matching: $PATTERN"
    log_info "Run tests with --save-results flag to generate results"
    exit 1
fi

log_info "Found ${#RESULT_FILES[@]} result file(s)"
echo ""

# Display comparison table
printf "%-20s %-10s %-12s %-12s %-12s %-10s %-10s\n" \
    "Timestamp" "Requests" "Errors" "P95 (ms)" "P99 (ms)" "Avg (ms)" "RPS"
echo "-----------------------------------------------------------------------------------------"

for file in "${RESULT_FILES[@]}"; do
    # Extract timestamp from filename
    TIMESTAMP=$(basename "$file" | sed -E 's/.*-([0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}).json/\1/')

    # Parse JSON results (basic parsing - could use jq if available)
    if command -v jq &> /dev/null; then
        TOTAL_REQUESTS=$(jq -r '.metrics.http_reqs.count // 0' "$file")
        ERROR_RATE=$(jq -r '.metrics.http_req_failed.rate // 0' "$file" | awk '{printf "%.2f%%", $1*100}')
        P95=$(jq -r '.metrics.http_req_duration.p95 // 0' "$file" | awk '{printf "%.2f", $1}')
        P99=$(jq -r '.metrics.http_req_duration.p99 // 0' "$file" | awk '{printf "%.2f", $1}')
        AVG=$(jq -r '.metrics.http_req_duration.avg // 0' "$file" | awk '{printf "%.2f", $1}')
        ACTUAL_RPS=$(jq -r '.metrics.http_reqs.rate // 0' "$file" | awk '{printf "%.2f", $1}')

        printf "%-20s %-10s %-12s %-12s %-12s %-10s %-10s\n" \
            "$TIMESTAMP" "$TOTAL_REQUESTS" "$ERROR_RATE" "$P95" "$P99" "$AVG" "$ACTUAL_RPS"
    else
        # Fallback if jq not available
        log_warn "jq not installed - limited result parsing"
        echo "  File: $(basename $file)"
    fi
done

echo ""
log_info "Detailed results available in: $RESULTS_DIR"

# Calculate trends if jq available
if command -v jq &> /dev/null && [ ${#RESULT_FILES[@]} -ge 2 ]; then
    echo ""
    log_section "Performance Trends"

    # Get oldest and newest file
    OLDEST_FILE="${RESULT_FILES[-1]}"
    NEWEST_FILE="${RESULT_FILES[0]}"

    OLD_P95=$(jq -r '.metrics.http_req_duration.p95 // 0' "$OLDEST_FILE")
    NEW_P95=$(jq -r '.metrics.http_req_duration.p95 // 0' "$NEWEST_FILE")
    OLD_ERROR_RATE=$(jq -r '.metrics.http_req_failed.rate // 0' "$OLDEST_FILE")
    NEW_ERROR_RATE=$(jq -r '.metrics.http_req_failed.rate // 0' "$NEWEST_FILE")

    # Calculate percentage change
    P95_CHANGE=$(awk "BEGIN {printf \"%.2f\", (($NEW_P95 - $OLD_P95) / $OLD_P95) * 100}")
    ERROR_CHANGE=$(awk "BEGIN {printf \"%.2f\", (($NEW_ERROR_RATE - $OLD_ERROR_RATE) / ($OLD_ERROR_RATE + 0.001)) * 100}")

    echo "P95 Latency:"
    if (( $(echo "$P95_CHANGE < 0" | bc -l) )); then
        echo -e "  ${GREEN}▼ Improved by ${P95_CHANGE#-}%${NC}"
    elif (( $(echo "$P95_CHANGE > 0" | bc -l) )); then
        echo -e "  ${RED}▲ Degraded by ${P95_CHANGE}%${NC}"
    else
        echo "  ✓ No change"
    fi

    echo "Error Rate:"
    if (( $(echo "$ERROR_CHANGE < 0" | bc -l) )); then
        echo -e "  ${GREEN}▼ Improved by ${ERROR_CHANGE#-}%${NC}"
    elif (( $(echo "$ERROR_CHANGE > 0" | bc -l) )); then
        echo -e "  ${RED}▲ Increased by ${ERROR_CHANGE}%${NC}"
    else
        echo "  ✓ No change"
    fi
fi

echo ""
