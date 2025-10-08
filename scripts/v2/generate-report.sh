#!/bin/bash
# K6 Test Report Generator v2.0
# Generate markdown reports from test results

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS_DIR="${PROJECT_ROOT}/results"
REPORTS_DIR="${PROJECT_ROOT}/reports"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
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
K6 Test Report Generator v2.0

Usage: $0 [OPTIONS]

Options:
  --type TYPE          Test type (stress, spike, soak, load)
  --rps RPS            RPS level
  --last N             Include last N test runs (default: 10)
  --output FILE        Output file (default: reports/<type>-<rps>rps-<date>.md)
  -h, --help           Show this help message

Examples:
  # Generate report for stress test at 100 RPS
  $0 --type stress --rps 100

  # Generate report with last 5 runs
  $0 --type spike --rps 50 --last 5

EOF
}

# Initialize variables
TEST_TYPE=""
RPS=""
LAST=10
OUTPUT_FILE=""

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
        --output)
            OUTPUT_FILE="$2"
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

# Create reports directory
mkdir -p "$REPORTS_DIR"

# Set default output file
if [ -z "$OUTPUT_FILE" ]; then
    TIMESTAMP=$(date +"%Y-%m-%d")
    OUTPUT_FILE="${REPORTS_DIR}/${TEST_TYPE}-${RPS}rps-${TIMESTAMP}.md"
fi

log_section "K6 Test Report Generator"
log_info "Test Type: $TEST_TYPE"
log_info "RPS: $RPS"
log_info "Output: $OUTPUT_FILE"
echo ""

# Check if results exist
PATTERN="${TEST_TYPE}-${RPS}rps-*.json"
RESULT_FILES=($(ls -t "${RESULTS_DIR}"/${PATTERN} 2>/dev/null | head -n "$LAST" || true))

if [ ${#RESULT_FILES[@]} -eq 0 ]; then
    log_error "No result files found matching: $PATTERN"
    exit 1
fi

log_info "Found ${#RESULT_FILES[@]} result file(s), generating report..."

# Generate markdown report
cat > "$OUTPUT_FILE" << EOF
# K6 Load Test Report

**Test Type:** ${TEST_TYPE}
**Target RPS:** ${RPS}
**Report Generated:** $(date +"%Y-%m-%d %H:%M:%S")
**Test Runs Analyzed:** ${#RESULT_FILES[@]}

---

## Summary

EOF

# Add summary statistics if jq available
if command -v jq &> /dev/null && [ ${#RESULT_FILES[@]} -gt 0 ]; then
    LATEST_FILE="${RESULT_FILES[0]}"

    TOTAL_REQUESTS=$(jq -r '.metrics.http_reqs.count // 0' "$LATEST_FILE")
    ERROR_RATE=$(jq -r '.metrics.http_req_failed.rate // 0' "$LATEST_FILE" | awk '{printf "%.2f%%", $1*100}')
    P50=$(jq -r '.metrics.http_req_duration.p50 // 0' "$LATEST_FILE" | awk '{printf "%.2f", $1}')
    P95=$(jq -r '.metrics.http_req_duration.p95 // 0' "$LATEST_FILE" | awk '{printf "%.2f", $1}')
    P99=$(jq -r '.metrics.http_req_duration.p99 // 0' "$LATEST_FILE" | awk '{printf "%.2f", $1}')
    ACTUAL_RPS=$(jq -r '.metrics.http_reqs.rate // 0' "$LATEST_FILE" | awk '{printf "%.2f", $1}')

    cat >> "$OUTPUT_FILE" << EOF
### Latest Test Results

- **Total Requests:** ${TOTAL_REQUESTS}
- **Actual RPS:** ${ACTUAL_RPS}
- **Error Rate:** ${ERROR_RATE}
- **P50 Latency:** ${P50} ms
- **P95 Latency:** ${P95} ms
- **P99 Latency:** ${P99} ms

---

## Historical Performance

| Timestamp | Requests | Error Rate | P95 (ms) | P99 (ms) | Avg (ms) | RPS |
|-----------|----------|------------|----------|----------|----------|-----|
EOF

    # Add rows for each result file
    for file in "${RESULT_FILES[@]}"; do
        TIMESTAMP=$(basename "$file" | sed -E 's/.*-([0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}).json/\1/')
        TOTAL_REQUESTS=$(jq -r '.metrics.http_reqs.count // 0' "$file")
        ERROR_RATE=$(jq -r '.metrics.http_req_failed.rate // 0' "$file" | awk '{printf "%.2f%%", $1*100}')
        P95=$(jq -r '.metrics.http_req_duration.p95 // 0' "$file" | awk '{printf "%.2f", $1}')
        P99=$(jq -r '.metrics.http_req_duration.p99 // 0' "$file" | awk '{printf "%.2f", $1}')
        AVG=$(jq -r '.metrics.http_req_duration.avg // 0' "$file" | awk '{printf "%.2f", $1}')
        ACTUAL_RPS=$(jq -r '.metrics.http_reqs.rate // 0' "$file" | awk '{printf "%.2f", $1}')

        echo "| ${TIMESTAMP} | ${TOTAL_REQUESTS} | ${ERROR_RATE} | ${P95} | ${P99} | ${AVG} | ${ACTUAL_RPS} |" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" << EOF

---

## Performance Trends

EOF

    # Add trend analysis if multiple results
    if [ ${#RESULT_FILES[@]} -ge 2 ]; then
        OLDEST_FILE="${RESULT_FILES[-1]}"
        NEWEST_FILE="${RESULT_FILES[0]}"

        OLD_P95=$(jq -r '.metrics.http_req_duration.p95 // 0' "$OLDEST_FILE")
        NEW_P95=$(jq -r '.metrics.http_req_duration.p95 // 0' "$NEWEST_FILE")
        OLD_ERROR=$(jq -r '.metrics.http_req_failed.rate // 0' "$OLDEST_FILE")
        NEW_ERROR=$(jq -r '.metrics.http_req_failed.rate // 0' "$NEWEST_FILE")

        P95_CHANGE=$(awk "BEGIN {printf \"%.2f\", (($NEW_P95 - $OLD_P95) / $OLD_P95) * 100}")
        ERROR_CHANGE=$(awk "BEGIN {printf \"%.2f\", (($NEW_ERROR - $OLD_ERROR) / ($OLD_ERROR + 0.001)) * 100}")

        cat >> "$OUTPUT_FILE" << EOF
### P95 Latency Trend
EOF

        if (( $(echo "$P95_CHANGE < 0" | bc -l) )); then
            echo "✅ **Improved by ${P95_CHANGE#-}%** (${OLD_P95}ms → ${NEW_P95}ms)" >> "$OUTPUT_FILE"
        elif (( $(echo "$P95_CHANGE > 0" | bc -l) )); then
            echo "⚠️ **Degraded by ${P95_CHANGE}%** (${OLD_P95}ms → ${NEW_P95}ms)" >> "$OUTPUT_FILE"
        else
            echo "✓ No significant change" >> "$OUTPUT_FILE"
        fi

        cat >> "$OUTPUT_FILE" << EOF

### Error Rate Trend
EOF

        if (( $(echo "$ERROR_CHANGE < 0" | bc -l) )); then
            echo "✅ **Improved by ${ERROR_CHANGE#-}%**" >> "$OUTPUT_FILE"
        elif (( $(echo "$ERROR_CHANGE > 0" | bc -l) )); then
            echo "⚠️ **Increased by ${ERROR_CHANGE}%**" >> "$OUTPUT_FILE"
        else
            echo "✓ No significant change" >> "$OUTPUT_FILE"
        fi
    fi
else
    echo "⚠️ jq not installed - limited report generation" >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << EOF

---

## Test Configuration

- **Test Type:** ${TEST_TYPE}
- **Target RPS:** ${RPS}
- **Number of Runs:** ${#RESULT_FILES[@]}

---

*Report generated by K6 Load Test v2.0*
EOF

log_info "✅ Report generated: $OUTPUT_FILE"
echo ""
log_info "View report:"
echo "  cat $OUTPUT_FILE"
echo ""
