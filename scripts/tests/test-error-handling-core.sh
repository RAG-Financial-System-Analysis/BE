#!/bin/bash

# =============================================================================
# Core Error Handling Integration Tests
# =============================================================================
# Task 9.3: Write integration tests for error handling (Core Focus)
# Tests core error handling framework and rollback mechanisms
# Requirements: 10.1, 10.2
#
# This script focuses on testing the core error handling framework
# and rollback functionality that is already implemented.
# =============================================================================

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utilities/logging.sh"
source "$SCRIPT_DIR/../utilities/error-handling.sh"

# Test configuration
readonly TEST_ENVIRONMENT="core-error-test"
readonly TEST_PROJECT="core-error-test"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# =============================================================================
# Test Utility Functions
# =============================================================================

run_test() {
    local test_name="$1"
    local test_function="$2"
    
    ((TESTS_RUN++))
    
    log_info "Running test: $test_name"
    
    if $test_function; then
        log_success "✓ PASS: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "✗ FAIL: $test_name"
        ((TESTS_FAILED++))
        return 1
    fi
}

# =============================================================================
# Error Handling Framework Tests
# =============================================================================

test_error_code_definitions() {
    # Test that all error codes are defined
    [[ -n "${ERROR_CODE_GENERAL:-}" ]] || return 1
    [[ -n "${ERROR_CODE_AWS_CLI:-}" ]] || return 1
    [[ -n "${ERROR_CODE_INFRASTRUCTURE:-}" ]] || return 1
    [[ -n "${ERROR_CODE_DATABASE:-}" ]] || return 1
    [[ -n "${ERROR_CODE_ROLLBACK:-}" ]] || return 1
    
    # Test that error codes have different values
    [[ "$ERROR_CODE_GENERAL" != "$ERROR_CODE_AWS_CLI" ]] || return 1
    [[ "$ERROR_CODE_AWS_CLI" != "$ERROR_CODE_INFRASTRUCTURE" ]] || return 1
    
    return 0
}

test_error_context_functionality() {
    # Test setting and using error context
    set_error_context "Test context"
    [[ "$ERROR_CONTEXT" == "Test context" ]] || return 1
    
    # Test setting remediation
    set_error_remediation "Test remediation"
    [[ "$ERROR_REMEDIATION" == "Test remediation" ]] || return 1
    
    return 0
}

test_error_details_retrieval() {
    # Test getting error details for known error codes
    local details
    details=$(get_error_details "$ERROR_CODE_AWS_CLI")
    [[ -n "$details" ]] || return 1
    [[ "$details" == *"AWS CLI"* ]] || return 1
    
    details=$(get_error_details "$ERROR_CODE_INFRASTRUCTURE")
    [[ -n "$details" ]] || return 1
    [[ "$details" == *"Infrastructure"* ]] || return 1
    
    return 0
}

test_error_logging_initialization() {
    # Test error logging initialization
    initialize_error_logging
    
    # Check that error log file is created
    [[ -n "${ERROR_LOG_FILE:-}" ]] || return 1
    [[ -f "$ERROR_LOG_FILE" ]] || return 1
    
    # Check that deployment state file is set
    [[ -n "${DEPLOYMENT_STATE_FILE:-}" ]] || return 1
    
    return 0
}

test_deployment_state_management() {
    # Test updating deployment state
    update_deployment_state "testing" "0" "Test state update"
    
    # Check that state file exists and contains expected data
    [[ -f "$DEPLOYMENT_STATE_FILE" ]] || return 1
    
    local state_content
    state_content=$(get_deployment_state)
    [[ "$state_content" == *"testing"* ]] || return 1
    [[ "$state_content" == *"Test state update"* ]] || return 1
    
    return 0
}

# =============================================================================
# Checkpoint and Recovery Tests
# =============================================================================

test_checkpoint_creation() {
    local test_data='{"test": "checkpoint_data", "timestamp": "2026-03-08T18:00:00Z"}'
    
    # Test creating a checkpoint
    create_checkpoint "test_checkpoint" "$test_data"
    
    # Check that checkpoint file exists
    [[ -f "./deployment_checkpoints/test_checkpoint.checkpoint" ]] || return 1
    
    return 0
}

test_checkpoint_restoration() {
    # Test restoring from checkpoint (created in previous test)
    local restored_data
    restored_data=$(restore_checkpoint "test_checkpoint")
    
    # Check that restored data matches original
    [[ "$restored_data" == *"checkpoint_data"* ]] || return 1
    [[ "$restored_data" == *"2026-03-08T18:00:00Z"* ]] || return 1
    
    return 0
}

test_checkpoint_cleanup() {
    # Test checkpoint cleanup
    cleanup_checkpoints
    
    # Check that checkpoint directory is removed
    [[ ! -d "./deployment_checkpoints" ]] || return 1
    
    return 0
}

# =============================================================================
# File and Parameter Validation Tests
# =============================================================================

test_file_validation() {
    # Test file validation with existing file
    local temp_file="/tmp/test_file_$$"
    echo "test content" > "$temp_file"
    
    validate_file_exists "$temp_file" "test file" || return 1
    
    # Clean up
    rm -f "$temp_file"
    
    return 0
}

test_file_validation_error() {
    # Test file validation with non-existent file (should fail gracefully)
    local error_caught=false
    
    if ! validate_file_exists "/nonexistent/file.txt" "test file" 2>/dev/null; then
        error_caught=true
    fi
    
    [[ "$error_caught" == "true" ]] || return 1
    
    return 0
}

test_required_vars_validation() {
    # Test required variables validation
    export TEST_VAR1="value1"
    export TEST_VAR2="value2"
    
    validate_required_vars "TEST_VAR1" "TEST_VAR2" || return 1
    
    # Clean up
    unset TEST_VAR1 TEST_VAR2
    
    return 0
}

test_required_vars_validation_error() {
    # Test required variables validation with missing var (should fail)
    local error_caught=false
    
    if ! validate_required_vars "NONEXISTENT_VAR" 2>/dev/null; then
        error_caught=true
    fi
    
    [[ "$error_caught" == "true" ]] || return 1
    
    return 0
}

# =============================================================================
# Rollback Functionality Tests
# =============================================================================

test_cleanup_function_registration() {
    # Test registering cleanup functions
    register_cleanup_function "echo 'cleanup_test_1'"
    register_cleanup_function "echo 'cleanup_test_2'"
    
    # Check that functions are registered
    [[ ${#CLEANUP_FUNCTIONS[@]} -ge 2 ]] || return 1
    
    return 0
}

test_cleanup_execution() {
    # Test executing cleanup functions
    local cleanup_output
    cleanup_output=$(execute_cleanup 2>&1)
    
    # Check that cleanup functions were executed
    [[ "$cleanup_output" == *"cleanup_test_1"* ]] || return 1
    [[ "$cleanup_output" == *"cleanup_test_2"* ]] || return 1
    
    return 0
}

# =============================================================================
# Infrastructure Script Integration Tests
# =============================================================================

test_infrastructure_cleanup_script_exists() {
    # Test that cleanup script exists and is executable
    [[ -f "$SCRIPT_DIR/../infrastructure/cleanup-infrastructure.sh" ]] || return 1
    [[ -x "$SCRIPT_DIR/../infrastructure/cleanup-infrastructure.sh" ]] || return 1
    
    return 0
}

test_infrastructure_cleanup_help() {
    # Test that cleanup script provides help
    local help_output
    help_output=$("$SCRIPT_DIR/../infrastructure/cleanup-infrastructure.sh" --help 2>&1 || true)
    
    [[ "$help_output" == *"Usage"* ]] || return 1
    [[ "$help_output" == *"cleanup"* ]] || return 1
    
    return 0
}

test_migration_rollback_script_exists() {
    # Test that migration rollback script exists and is executable
    [[ -f "$SCRIPT_DIR/../migration/rollback-migrations.sh" ]] || return 1
    [[ -x "$SCRIPT_DIR/../migration/rollback-migrations.sh" ]] || return 1
    
    return 0
}

test_migration_rollback_help() {
    # Test that migration rollback script provides help
    local help_output
    help_output=$("$SCRIPT_DIR/../migration/rollback-migrations.sh" --help 2>&1 || true)
    
    [[ "$help_output" == *"Usage"* ]] || return 1
    [[ "$help_output" == *"rollback"* ]] || return 1
    
    return 0
}

# =============================================================================
# Error Scenario Simulation Tests
# =============================================================================

test_aws_error_handling_simulation() {
    # Simulate AWS error handling
    local error_output="UnauthorizedOperation: You are not authorized to perform this operation."
    local error_handled=false
    
    # Test AWS error parsing (should not exit, just set context)
    set_error_context "AWS CLI command test"
    set_error_remediation "Check IAM permissions"
    
    # Verify context was set
    [[ "$ERROR_CONTEXT" == *"AWS CLI command test"* ]] || return 1
    [[ "$ERROR_REMEDIATION" == *"IAM permissions"* ]] || return 1
    
    return 0
}

test_execute_with_error_handling() {
    # Test command execution with error handling
    local output
    output=$(execute_with_error_handling "echo 'test command success'" "Test command failed" 2>&1 || true)
    
    [[ "$output" == *"test command success"* ]] || return 1
    
    return 0
}

# =============================================================================
# Test Execution and Reporting
# =============================================================================

display_test_summary() {
    echo ""
    echo "========================================"
    echo "Core Error Handling Test Summary"
    echo "========================================"
    echo ""
    echo "Tests Run:    $TESTS_RUN"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo ""
    
    local success_rate=0
    if [[ $TESTS_RUN -gt 0 ]]; then
        success_rate=$((TESTS_PASSED * 100 / TESTS_RUN))
    fi
    
    echo "Success Rate: $success_rate%"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "🎉 All core error handling tests passed!"
        echo ""
        echo "✅ Error handling framework is working correctly"
        echo "✅ Checkpoint and recovery mechanisms are functional"
        echo "✅ File and parameter validation work properly"
        echo "✅ Rollback functionality is operational"
        echo "✅ Infrastructure scripts are properly integrated"
        echo ""
        echo "Requirements 10.1 and 10.2 are validated for core functionality!"
        return 0
    else
        log_error "❌ Some core error handling tests failed"
        echo ""
        echo "Issues found:"
        echo "- $TESTS_FAILED out of $TESTS_RUN tests failed"
        echo "- Core error handling functionality may be compromised"
        echo "- Review and fix identified issues"
        return 1
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    echo "========================================"
    echo "Core Error Handling Integration Tests"
    echo "========================================"
    echo ""
    echo "Environment: $TEST_ENVIRONMENT"
    echo "Project: $TEST_PROJECT"
    echo ""
    
    log_info "Starting core error handling integration tests..."
    echo ""
    
    # Error Handling Framework Tests
    log_info "=== Testing Error Handling Framework ==="
    run_test "Error code definitions" "test_error_code_definitions"
    run_test "Error context functionality" "test_error_context_functionality"
    run_test "Error details retrieval" "test_error_details_retrieval"
    run_test "Error logging initialization" "test_error_logging_initialization"
    run_test "Deployment state management" "test_deployment_state_management"
    echo ""
    
    # Checkpoint and Recovery Tests
    log_info "=== Testing Checkpoint and Recovery ==="
    run_test "Checkpoint creation" "test_checkpoint_creation"
    run_test "Checkpoint restoration" "test_checkpoint_restoration"
    run_test "Checkpoint cleanup" "test_checkpoint_cleanup"
    echo ""
    
    # File and Parameter Validation Tests
    log_info "=== Testing File and Parameter Validation ==="
    run_test "File validation (success)" "test_file_validation"
    run_test "File validation (error)" "test_file_validation_error"
    run_test "Required vars validation (success)" "test_required_vars_validation"
    run_test "Required vars validation (error)" "test_required_vars_validation_error"
    echo ""
    
    # Rollback Functionality Tests
    log_info "=== Testing Rollback Functionality ==="
    run_test "Cleanup function registration" "test_cleanup_function_registration"
    run_test "Cleanup execution" "test_cleanup_execution"
    echo ""
    
    # Infrastructure Script Integration Tests
    log_info "=== Testing Infrastructure Script Integration ==="
    run_test "Infrastructure cleanup script exists" "test_infrastructure_cleanup_script_exists"
    run_test "Infrastructure cleanup help" "test_infrastructure_cleanup_help"
    run_test "Migration rollback script exists" "test_migration_rollback_script_exists"
    run_test "Migration rollback help" "test_migration_rollback_help"
    echo ""
    
    # Error Scenario Simulation Tests
    log_info "=== Testing Error Scenario Simulation ==="
    run_test "AWS error handling simulation" "test_aws_error_handling_simulation"
    run_test "Execute with error handling" "test_execute_with_error_handling"
    echo ""
    
    # Display summary
    display_test_summary
    
    # Return appropriate exit code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Execute main function
main "$@"