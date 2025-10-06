#!/bin/bash
# Run all K6 stress tests sequentially
# Usage: ./run-all-stress-tests.sh

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RPS_LEVELS="50 100 150 200 300 400 500 750 1000"
DELAY_BETWEEN_TESTS=30  # seconds

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Track results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
declare -a FAILED_RPS_LEVELS

# Start time
START_TIME=$(date +%s)
log_section "Starting K6 Stress Test Suite"
log_info "RPS levels to test: ${RPS_LEVELS}"
log_info "Delay between tests: ${DELAY_BETWEEN_TESTS}s"
log_info "Start time: $(date)"
echo ""

# Run each test
for RPS in $RPS_LEVELS; do
    ((TOTAL_TESTS++))

    log_section "Test ${TOTAL_TESTS}: ${RPS} RPS"

    if "${SCRIPT_DIR}/run-single-stress-test.sh" "$RPS"; then
        ((PASSED_TESTS++))
        log_info "✅ Test ${RPS} RPS: PASSED"
    else
        ((FAILED_TESTS++))
        FAILED_RPS_LEVELS+=("$RPS")
        log_error "❌ Test ${RPS} RPS: FAILED"
    fi

    # Wait between tests (except after the last one)
    if [ "$RPS" != "1000" ]; then
        log_info "Waiting ${DELAY_BETWEEN_TESTS}s before next test..."
        sleep ${DELAY_BETWEEN_TESTS}
    fi

    echo ""
done

# Calculate duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

# Final summary
log_section "Test Suite Complete"
log_info "Total tests: ${TOTAL_TESTS}"
log_info "Passed: ${PASSED_TESTS}"
log_info "Failed: ${FAILED_TESTS}"
log_info "Duration: ${MINUTES}m ${SECONDS}s"

if [ ${FAILED_TESTS} -gt 0 ]; then
    log_error "Failed RPS levels: ${FAILED_RPS_LEVELS[*]}"
    echo ""
    log_error "❌ Test suite completed with failures"
    exit 1
else
    echo ""
    log_info "✅ All tests passed successfully!"
    exit 0
fi
