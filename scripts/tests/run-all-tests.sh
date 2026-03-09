#!/bin/bash

# Run All Tests - AWS Deployment Automation System
# Comprehensive test runner for all test suites

set -euo pipefail

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_RESULTS_DIR="$SCRIPT_DIR/test-results-$(date +%Y%m%d-%H%M%S)"

# Colors for output
readonly RUNNER_RED='\033[0;31m'
readonly RUNNER_GREEN='\033[0;32m'
readonly RUNNER_YELLOW='\033[1;33m'
readonly RUNNER_BLUE='\033[0;34m'
readonly RUNNER_NC='\033[0m'

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

log_info() {
    echo -e "${RUNNER_BLUE}[RUNNER]${RUNNER_NC} $1"
}

log_success() {
    echo -e "${RUNNER_GREEN}[SUCCESS]${RUNNER_NC} $1"
}

log_failure() {
    echo -e "${RUNNER_RED}[FAILURE]${RUNNER_NC} $1"
}

log_warning() {
    echo -e "${RUNNER_YELLOW}[WARNING]${RUNNER_NC} $1"
}

cleanup_test_results() {
    log_info "Cleaning up test results..."
    # Keep test results for analysis
}

# Note: Removed trap to avoid early exit issues

setup_test_environment() {
    log_info "Setting up test environment..."
    
    # Create test results directory
    mkdir -p "$TEST_RESULTS_DIR"
    
    # Set environment variables for tests
    export TEST_MODE="mock"
    export TEST_RESULTS_DIR="$TEST_RESULTS_DIR"
    
    log_success "Test environment setup completed"
}

run_test_suite() {
    local test_name="$1"
    local test_script="$2"
    local test_description="$3"
    
    log_info "Running test suite: $test_name"
    echo "Description: $test_description"
    
    ((TOTAL_TESTS++))
    
    local test_log="$TEST_RESULTS_DIR/${test_name}.log"
    local test_start_time=$(date +%s)
    
    if [ -f "$SCRIPT_DIR/$test_script" ] && [ -x "$SCRIPT_DIR/$test_script" ]; then
        # Run the test and capture output
        if "$SCRIPT_DIR/$test_script" > "$test_log" 2>&1; then
            local test_end_time=$(date +%s)
            local test_duration=$((test_end_time - test_start_time))
            
            log_success "$test_name PASSED (${test_duration}s)"
            ((PASSED_TESTS++))
            
            # Extract key metrics from test output
            local test_summary=$(tail -5 "$test_log" | grep -E "(PASS|FAIL|✅|❌)" | head -1 || echo "Test completed")
            echo "  Result: $test_summary"
            
        else
            local test_end_time=$(date +%s)
            local test_duration=$((test_end_time - test_start_time))
            
            log_failure "$test_name FAILED (${test_duration}s)"
            ((FAILED_TESTS++))
            
            # Show last few lines of error output
            echo "  Error details:"
            tail -10 "$test_log" | sed 's/^/    /'
        fi
    else
        log_warning "$test_name SKIPPED (script not found or not executable)"
        ((SKIPPED_TESTS++))
    fi
    
    echo ""
}

# Test suite definitions
run_all_test_suites() {
    log_info "Starting comprehensive test execution..."
    echo "=================================================="
    
    # Property Tests
    echo -e "${RUNNER_BLUE}=== PROPERTY TESTS ===${RUNNER_NC}"
    run_test_suite "migration-idempotency" "property-test-migration-idempotency.sh" "Tests migration idempotency property"
    run_test_suite "config-conversion" "property-test-configuration-conversion.sh" "Tests configuration round-trip consistency"
    run_test_suite "cost-optimization" "property-test-cost-optimization.sh" "Tests cost optimization constraints"
    run_test_suite "deployment-idempotency" "property-test-deployment-idempotency.sh" "Tests deployment idempotency property"
    
    # Unit Tests
    echo -e "${RUNNER_BLUE}=== UNIT TESTS ===${RUNNER_NC}"
    run_test_suite "database-seeding" "unit-test-database-seeding.sh" "Tests database seeding functionality"
    run_test_suite "infrastructure-detection" "unit-test-infrastructure-detection.sh" "Tests infrastructure detection"
    run_test_suite "cognito-integration" "unit-test-cognito-integration.sh" "Tests Cognito integration"
    
    # Integration Tests
    echo -e "${RUNNER_BLUE}=== INTEGRATION TESTS ===${RUNNER_NC}"
    run_test_suite "end-to-end" "integration-test-end-to-end.sh" "Tests complete deployment workflows"
    
    # Existing Tests (for compatibility)
    echo -e "${RUNNER_BLUE}=== EXISTING TESTS ===${RUNNER_NC}"
    run_test_suite "deployment-args" "test-deployment-argument-parsing.sh" "Tests deployment argument parsing"
    run_test_suite "infrastructure-integration" "test-infrastructure-integration-final.sh" "Tests infrastructure integration"
    run_test_suite "error-handling" "test-error-handling-integration.sh" "Tests error handling mechanisms"
}

generate_test_report() {
    local report_file="$TEST_RESULTS_DIR/test-execution-report.md"
    
    log_info "Generating comprehensive test report..."
    
    cat > "$report_file" << EOF
# AWS Deployment Automation - Test Execution Report

**Date:** $(date)
**Test Results Directory:** $TEST_RESULTS_DIR

## Summary

- **Total Tests:** $TOTAL_TESTS
- **Passed:** $PASSED_TESTS
- **Failed:** $FAILED_TESTS
- **Skipped:** $SKIPPED_TESTS
- **Success Rate:** $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%

## Test Results

EOF

    # Add individual test results
    for log_file in "$TEST_RESULTS_DIR"/*.log; do
        if [ -f "$log_file" ]; then
            local test_name=$(basename "$log_file" .log)
            echo "### $test_name" >> "$report_file"
            
            if grep -q "PASS\|✅" "$log_file"; then
                echo "**Status:** ✅ PASSED" >> "$report_file"
            elif grep -q "FAIL\|❌" "$log_file"; then
                echo "**Status:** ❌ FAILED" >> "$report_file"
            else
                echo "**Status:** ⚠️ UNKNOWN" >> "$report_file"
            fi
            
            echo "" >> "$report_file"
            echo "**Output Summary:**" >> "$report_file"
            echo '```' >> "$report_file"
            tail -20 "$log_file" >> "$report_file"
            echo '```' >> "$report_file"
            echo "" >> "$report_file"
        fi
    done
    
    cat >> "$report_file" << EOF

## Test Environment

- **Test Mode:** $TEST_MODE
- **Script Directory:** $SCRIPT_DIR
- **Results Directory:** $TEST_RESULTS_DIR

## Recommendations

EOF

    if [ $FAILED_TESTS -eq 0 ]; then
        echo "✅ All tests passed successfully! The deployment system is ready for use." >> "$report_file"
    else
        echo "❌ Some tests failed. Please review the failed tests and fix issues before deployment." >> "$report_file"
        echo "" >> "$report_file"
        echo "**Failed Tests:**" >> "$report_file"
        for log_file in "$TEST_RESULTS_DIR"/*.log; do
            if [ -f "$log_file" ] && grep -q "FAIL\|❌" "$log_file"; then
                local test_name=$(basename "$log_file" .log)
                echo "- $test_name" >> "$report_file"
            fi
        done
    fi
    
    echo ""
    echo "📋 Test report generated: $report_file"
    
    # Display summary
    cat "$report_file"
}

main() {
    echo -e "${RUNNER_BLUE}🧪 AWS Deployment Automation - Comprehensive Test Suite${RUNNER_NC}"
    echo "=================================================="
    
    # Setup test environment
    setup_test_environment
    
    # Run all test suites
    run_all_test_suites
    
    # Generate comprehensive report
    generate_test_report
    
    # Manual cleanup
    cleanup_test_results
    
    echo ""
    echo "=================================================="
    echo -e "${RUNNER_BLUE}Test Execution Summary:${RUNNER_NC}"
    echo "  Total Tests: $TOTAL_TESTS"
    echo "  Passed: $PASSED_TESTS"
    echo "  Failed: $FAILED_TESTS"
    echo "  Skipped: $SKIPPED_TESTS"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${RUNNER_GREEN}✅ All tests passed! System is ready for deployment.${RUNNER_NC}"
        exit 0
    else
        echo -e "${RUNNER_RED}❌ $FAILED_TESTS test(s) failed. Please review and fix issues.${RUNNER_NC}"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "AWS Deployment Automation - Comprehensive Test Runner"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h              Show this help message"
        echo ""
        echo "This script runs all available test suites:"
        echo "- Property tests (idempotency, consistency)"
        echo "- Unit tests (individual components)"
        echo "- Integration tests (end-to-end workflows)"
        echo ""
        echo "Test results are saved to: test-results-YYYYMMDD-HHMMSS/"
        exit 0
        ;;
    *)
        # Continue with main execution
        ;;
esac

# Run main function
main "$@"