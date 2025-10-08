#!/bin/bash
# K6 Load Test Suite Runner v2.0
# Run multiple load tests in sequence based on configuration

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/config.yaml"

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
K6 Load Test Suite Runner v2.0

Usage: $0 [OPTIONS]

Options:
  --type TYPE          Test type to run: stress, spike, soak, load, all (default: stress)
  --rps-levels "LIST"  Custom RPS levels (default: from config.yaml)
  --duration TIME      Override default duration
  --delay SECONDS      Delay between tests (default: 30)
  --namespace NS       Kubernetes namespace (default: prod)
  --config FILE        Custom config file (default: config.yaml)
  --parallel           Run tests in parallel (experimental)
  -h, --help           Show this help message

Examples:
  # Run all stress tests from config.yaml
  $0 --type stress

  # Run custom RPS levels
  $0 --type stress --rps-levels "10 50 100"

  # Run spike tests with custom duration
  $0 --type spike --duration 5m

  # Run all test types
  $0 --type all

  # Run with custom delay between tests
  $0 --type stress --delay 60

EOF
}

# Initialize variables
TEST_TYPE="stress"
RPS_LEVELS=""
DURATION=""
DELAY=30
NAMESPACE="prod"
CUSTOM_CONFIG=""
PARALLEL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --type)
            TEST_TYPE="$2"
            shift 2
            ;;
        --rps-levels)
            RPS_LEVELS="$2"
            shift 2
            ;;
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --delay)
            DELAY="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --config)
            CUSTOM_CONFIG="$2"
            CONFIG_FILE="$2"
            shift 2
            ;;
        --parallel)
            PARALLEL=true
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

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

log_section "K6 Load Test Suite Runner v2.0"
log_info "Test Type: $TEST_TYPE"
log_info "Namespace: $NAMESPACE"
log_info "Config File: $CONFIG_FILE"
log_info "Delay Between Tests: ${DELAY}s"
echo ""

# Get RPS levels from config if not provided
if [ -z "$RPS_LEVELS" ]; then
    # Parse RPS levels from YAML (default hardcoded if parsing fails)
    if command -v yq &> /dev/null; then
        RPS_LEVELS=$(yq eval '.test.rpsLevels[]' "$CONFIG_FILE" 2>/dev/null | tr '\n' ' ' || echo "5 10 50 100 150 200 300 400 500 750 1000 1500")
    else
        # Fallback: use default RPS levels
        RPS_LEVELS="5 10 50 100 150 200 300 400 500 750 1000 1500"
        log_warn "yq not installed, using default RPS levels"
    fi
fi

log_info "RPS Levels: $RPS_LEVELS"
echo ""

# Track results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
declare -a FAILED_TESTS_LIST

START_TIME=$(date +%s)

# Determine test types to run
TEST_TYPES=""
if [ "$TEST_TYPE" = "all" ]; then
    TEST_TYPES="stress spike soak load"
else
    TEST_TYPES="$TEST_TYPE"
fi

# Run tests
for type in $TEST_TYPES; do
    log_section "Running ${type} tests"

    for rps in $RPS_LEVELS; do
        ((TOTAL_TESTS++))

        log_info "Test ${TOTAL_TESTS}: ${type} @ ${rps} RPS"

        # Build command
        CMD="${SCRIPT_DIR}/deploy-test.sh --type ${type} --rps ${rps} --namespace ${NAMESPACE}"

        if [ -n "$DURATION" ]; then
            CMD="${CMD} --duration ${DURATION}"
        fi

        if [ -n "$CUSTOM_CONFIG" ]; then
            CMD="${CMD} --config ${CUSTOM_CONFIG}"
        fi

        # Run test
        if [ "$PARALLEL" = false ]; then
            CMD="${CMD} --wait"
        fi

        if $CMD; then
            ((PASSED_TESTS++))
            log_info "✅ Test ${type} @ ${rps} RPS: PASSED"
        else
            ((FAILED_TESTS++))
            FAILED_TESTS_LIST+=("${type} @ ${rps} RPS")
            log_error "❌ Test ${type} @ ${rps} RPS: FAILED"
        fi

        # Wait between tests (except after last one)
        if [ "$PARALLEL" = false ] && [ "$TOTAL_TESTS" -lt $(($(echo "$TEST_TYPES" | wc -w) * $(echo "$RPS_LEVELS" | wc -w))) ]; then
            log_info "Waiting ${DELAY}s before next test..."
            sleep "$DELAY"
        fi

        echo ""
    done
done

# Calculate duration
END_TIME=$(date +%s)
DURATION_SECONDS=$((END_TIME - START_TIME))
MINUTES=$((DURATION_SECONDS / 60))
SECONDS=$((DURATION_SECONDS % 60))

# Final summary
log_section "Test Suite Complete"
log_info "Total tests: ${TOTAL_TESTS}"
log_info "Passed: ${PASSED_TESTS}"
log_info "Failed: ${FAILED_TESTS}"
log_info "Duration: ${MINUTES}m ${SECONDS}s"

if [ ${FAILED_TESTS} -gt 0 ]; then
    log_error "Failed tests:"
    for test in "${FAILED_TESTS_LIST[@]}"; do
        echo "  - $test"
    done
    echo ""
    log_error "❌ Test suite completed with failures"
    exit 1
else
    echo ""
    log_info "✅ All tests passed successfully!"
    exit 0
fi
