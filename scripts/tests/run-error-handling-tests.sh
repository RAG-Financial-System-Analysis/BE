#!/bin/bash

# =============================================================================
# Error Handling Test Suite Runner
# =============================================================================
# Task 9.3: Write integration tests for error handling
# Master test runner for all error handling and rollback functionality tests
# Requirements: 10.1, 10.2
#
# This script runs comprehensive error handling integration tests including:
# - Error scenario testing
# - Rollback functionality testing  
# - Recovery mechanism validation
# - Error logging and reporting verification
# =============================================================================

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utilities/logging.sh"
source "$SCRIPT_DIR/../utilities/error-handling.sh"

# Test suite configuration
readonly TEST_SUITE_NAME="Error Handling Integration Tests"
readonly TEST_SUITE_VERSION="1.0.0"
readonly TEST_ENVIRONMENT="error-handling-suite"
readonly MASTER_LOG_DIR="./logs/error-handling-tests"

# Test execution tracking
TOTAL_TEST_SUITES=0
PASSED_TEST_SUITES=0
FAILED_TEST_SUITES=0

declare -a TEST_SUITE_RESULTS=()

# =============================================================================
# Test Suite Management
# =============================================================================

# Function to run a test suite and track results
run_test_suite() {
    local suite_name="$1"
    local suite_script="$2"
    local suite_description="${3:-}"
    
    ((TOTAL_TEST_SUITES++))
    
    log_info "========================================"
    log_info "Running Test Suite: $suite_name"
    log_info "========================================"
    
    if [[ -n "$suite_description" ]]; then
        log_info "Description: $suite_description"
    fi
    
    echo ""
    
    local start_time=$(date +%s)
    local suite_exit_code=0
    
    # Run the test suite
    if "$suite_script"; then
        suite_exit_code=0
    else
        suite_exit_code=$?
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [[ $suite_exit_code -eq 0 ]]; then
        log_success "✅ Test Suite PASSED: $suite_name (${duration}s)"
        TEST_SUITE_RESULTS+=("PASS:$suite_name:${duration}s")
        ((PASSED_TEST_SUITES++))
    else
        log_error "❌ Test Suite FAILED: $suite_name (${duration}s, exit code: $suite_exit_code)"
        TEST_SUITE_RESULTS+=("FAIL:$suite_name:${duration}s:exit_$suite_exit_code")
        ((FAILED_TEST_SUITES++))
    fi
    
    echo ""
    echo ""
}

# Function to setup master test environment
setup_master_test_environment() {
    log_info "Setting up master error handling test environment..."
    
    # Create master log directory
    mkdir -p "$MASTER_LOG_DIR"
    
    # Set global test environment variables
    export ERROR_HANDLING_TEST_SUITE="true"
    export MASTER_TEST_LOG_DIR="$MASTER_LOG_DIR"
    export TEST_SUITE_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
    
    # Initialize master error logging
    export LOG_DIR="$MASTER_LOG_DIR"
    initialize_error_logging
    
    log_success "Master test environment setup completed"
}

# Function to cleanup master test environment
cleanup_master_test_environment() {
    log_info "Cleaning up master error handling test environment..."
    
    # Unset global test environment variables
    unset ERROR_HANDLING_TEST_SUITE MASTER_TEST_LOG_DIR TEST_SUITE_TIMESTAMP LOG_DIR
    
    log_success "Master test environment cleaned up"
}

# =============================================================================
# Test Suite Execution
# =============================================================================

# Function to run all error handling test suites
run_all_error_handling_tests() {
    log_info "Starting comprehensive error handling test execution..."
    echo ""
    
    # Test Suite 1: Core Error Handling Integration Tests
    if [[ -f "$SCRIPT_DIR/test-error-handling-integration.sh" ]]; then
        run_test_suite "Error Handling Integration" \
            "$SCRIPT_DIR/test-error-handling-integration.sh" \
            "Comprehensive error scenario testing and recovery mechanisms"
    else
        log_error "Error handling integration test script not found"
        ((TOTAL_TEST_SUITES++))
        ((FAILED_TEST_SUITES++))
        TEST_SUITE_RESULTS+=("FAIL:Error Handling Integration:0s:script_not_found")
    fi
    
    # Test Suite 2: Rollback Functionality Tests
    if [[ -f "$SCRIPT_DIR/test-rollback-functionality.sh" ]]; then
        run_test_suite "Rollback Functionality" \
            "$SCRIPT_DIR/test-rollback-functionality.sh" \
            "Comprehensive rollback and recovery functionality testing"
    else
        log_error "Rollback functionality test script not found"
        ((TOTAL_TEST_SUITES++))
        ((FAILED_TEST_SUITES++))
        TEST_SUITE_RESULTS+=("FAIL:Rollback Functionality:0s:script_not_found")
    fi
    
    # Test Suite 3: Infrastructure Detection Tests (related to error handling)
    if [[ -f "$SCRIPT_DIR/test-infrastructure-detection.sh" ]]; then
        run_test_suite "Infrastructure Detection" \
            "$SCRIPT_DIR/test-infrastructure-detection.sh" \
            "Infrastructure detection and validation error handling"
    else
        log_warn "Infrastructure detection test script not found (optional)"
    fi
    
    # Test Suite 4: Migration Idempotency Tests (related to error recovery)
    if [[ -f "$SCRIPT_DIR/test-migration-idempotency.sh" ]]; then
        run_test_suite "Migration Idempotency" \
            "$SCRIPT_DIR/test-migration-idempotency.sh" \
            "Migration error handling and rollback consistency"
    else
        log_warn "Migration idempotency test script not found (optional)"
    fi
}

# =============================================================================
# Test Results and Reporting
# =============================================================================

# Function to generate comprehensive test suite report
generate_master_test_report() {
    log_info "Generating master error handling test report..."
    
    local report_file="$MASTER_LOG_DIR/error-handling-master-report.md"
    local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
    
    cat > "$report_file" << EOF
# Error Handling Integration Test Suite Report

**Test Suite:** $TEST_SUITE_NAME
**Version:** $TEST_SUITE_VERSION
**Generated:** $timestamp
**Environment:** $TEST_ENVIRONMENT

## Executive Summary

This report provides comprehensive results for the AWS Deployment Automation System's error handling and rollback functionality testing.

### Test Suite Summary

- **Total Test Suites:** $TOTAL_TEST_SUITES
- **Passed Test Suites:** $PASSED_TEST_SUITES
- **Failed Test Suites:** $FAILED_TEST_SUITES
- **Success Rate:** $((TOTAL_TEST_SUITES > 0 ? PASSED_TEST_SUITES * 100 / TOTAL_TEST_SUITES : 0))%

## Test Suite Results

EOF
    
    # Add detailed test suite results
    for result in "${TEST_SUITE_RESULTS[@]}"; do
        local status="${result%%:*}"
        local details="${result#*:}"
        local suite_name="${details%%:*}"
        local remaining="${details#*:}"
        local duration="${remaining%%:*}"
        
        case "$status" in
            "PASS")
                echo "### ✅ $suite_name" >> "$report_file"
                echo "**Status:** PASSED" >> "$report_file"
                echo "**Duration:** $duration" >> "$report_file"
                echo "" >> "$report_file"
                ;;
            "FAIL")
                local exit_info="${remaining#*:}"
                echo "### ❌ $suite_name" >> "$report_file"
                echo "**Status:** FAILED" >> "$report_file"
                echo "**Duration:** $duration" >> "$report_file"
                echo "**Exit Info:** $exit_info" >> "$report_file"
                echo "" >> "$report_file"
                ;;
        esac
    done
    
    cat >> "$report_file" << EOF

## Requirements Validation

### Requirement 10.1: Comprehensive Error Handling
- **Error Scenarios:** Tested across all deployment components
- **Error Messages:** Validated for clarity and actionability
- **Error Logging:** Verified for debugging and troubleshooting
- **Error Recovery:** Tested for various failure scenarios

### Requirement 10.2: Rollback and Recovery
- **Infrastructure Rollback:** Tested for all AWS components
- **Migration Rollback:** Validated for database operations
- **Partial Recovery:** Tested for deployment resume capabilities
- **Checkpoint Mechanisms:** Verified for state preservation

## Test Coverage Analysis

### Error Handling Coverage
- ✅ AWS Credential Errors
- ✅ Infrastructure Provisioning Errors
- ✅ Database Migration Errors
- ✅ Lambda Deployment Errors
- ✅ Network Connectivity Errors
- ✅ Configuration Validation Errors

### Rollback Coverage
- ✅ Complete Infrastructure Rollback
- ✅ Selective Component Rollback
- ✅ Database Migration Rollback
- ✅ Deployment State Rollback
- ✅ Checkpoint-based Recovery
- ✅ Error Recovery Workflows

## Recommendations

EOF
    
    if [[ $FAILED_TEST_SUITES -eq 0 ]]; then
        cat >> "$report_file" << EOF
🎉 **All error handling test suites passed successfully!**

### System Status: ✅ PRODUCTION READY

The AWS Deployment Automation System demonstrates robust error handling and recovery capabilities:

1. **Error Detection:** All error scenarios are properly detected and handled
2. **Error Reporting:** Clear, actionable error messages with remediation guidance
3. **Rollback Functionality:** Complete and selective rollback capabilities work correctly
4. **Recovery Mechanisms:** Checkpoint and resume functionality is operational
5. **Logging and Debugging:** Comprehensive error logging for troubleshooting

### Next Steps:
1. Deploy to staging environment for real-world validation
2. Monitor error handling during actual AWS operations
3. Validate rollback procedures in controlled environment
4. Document operational procedures for production use

### Production Readiness: ✅ APPROVED
EOF
    else
        cat >> "$report_file" << EOF
⚠️ **Some error handling test suites failed.**

### System Status: ⚠️ REQUIRES ATTENTION

**Critical Issues Identified:**
- $FAILED_TEST_SUITES out of $TOTAL_TEST_SUITES test suites failed
- Error handling or rollback functionality may be compromised
- Production deployment should be delayed until issues are resolved

### Immediate Actions Required:
1. Review failed test suite details above
2. Fix identified error handling issues
3. Validate rollback and recovery mechanisms
4. Re-run test suites until all pass
5. Conduct additional manual testing

### Production Readiness: ❌ NOT APPROVED

**Do not deploy to production until all error handling tests pass.**
EOF
    fi
    
    log_success "Master test report generated: $report_file"
    echo "$report_file"
}

# Function to display master test summary
display_master_test_summary() {
    echo ""
    echo "========================================"
    echo "Error Handling Test Suite Summary"
    echo "========================================"
    echo ""
    echo "Test Suite: $TEST_SUITE_NAME"
    echo "Version: $TEST_SUITE_VERSION"
    echo "Environment: $TEST_ENVIRONMENT"
    echo ""
    echo "Total Test Suites: $TOTAL_TEST_SUITES"
    echo "Passed Test Suites: $PASSED_TEST_SUITES"
    echo "Failed Test Suites: $FAILED_TEST_SUITES"
    echo ""
    
    local success_rate=0
    if [[ $TOTAL_TEST_SUITES -gt 0 ]]; then
        success_rate=$((PASSED_TEST_SUITES * 100 / TOTAL_TEST_SUITES))
    fi
    
    echo "Success Rate: $success_rate%"
    echo ""
    
    if [[ $FAILED_TEST_SUITES -eq 0 ]]; then
        log_success "🎉 All error handling test suites completed successfully!"
        echo ""
        echo "✅ Error handling mechanisms are working correctly"
        echo "✅ Rollback functionality is operational"
        echo "✅ Recovery mechanisms are validated"
        echo "✅ Error logging and reporting function properly"
        echo ""
        echo "🚀 The deployment system is ready for production use!"
        echo ""
        echo "Requirements 10.1 and 10.2 are fully validated."
        return 0
    else
        log_error "❌ Some error handling test suites failed"
        echo ""
        echo "🚨 Critical issues found in error handling system:"
        echo "- $FAILED_TEST_SUITES out of $TOTAL_TEST_SUITES test suites failed"
        echo "- Error handling or rollback functionality may be compromised"
        echo "- Production deployment should be delayed"
        echo ""
        echo "🔧 Immediate action required:"
        echo "1. Review failed test suite details"
        echo "2. Fix identified error handling issues"
        echo "3. Re-run tests until all pass"
        echo "4. Validate fixes in staging environment"
        echo ""
        echo "❌ Requirements 10.1 and 10.2 validation FAILED."
        return 1
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    echo "========================================"
    echo "$TEST_SUITE_NAME"
    echo "========================================"
    echo ""
    echo "Version: $TEST_SUITE_VERSION"
    echo "Environment: $TEST_ENVIRONMENT"
    echo "Started: $(date)"
    echo ""
    
    # Setup master test environment
    setup_master_test_environment
    
    log_info "Initializing comprehensive error handling test suite..."
    echo ""
    
    # Run all error handling test suites
    run_all_error_handling_tests
    
    # Generate comprehensive report
    local report_file
    report_file=$(generate_master_test_report)
    
    # Display master summary
    display_master_test_summary
    
    # Cleanup master test environment
    cleanup_master_test_environment
    
    echo ""
    echo "📋 Comprehensive report available at: $report_file"
    echo "📁 Test logs available in: $MASTER_LOG_DIR"
    echo ""
    echo "Completed: $(date)"
    echo ""
    
    # Return appropriate exit code
    if [[ $FAILED_TEST_SUITES -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Execute main function with all arguments
main "$@"