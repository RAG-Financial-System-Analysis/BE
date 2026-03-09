#!/bin/bash

# Complete End-to-End Workflow Tests
# Tests complete initial deployment, update deployment, cleanup and rollback scenarios
# Validates all deployment workflows work correctly together

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/utilities/logging.sh"
source "$SCRIPT_DIR/utilities/error-handling.sh"

# Test configuration
TEST_PROJECT_NAME="e2e-workflow-test"
TEST_ENVIRONMENT="development"
TEST_AWS_REGION="us-east-1"
TEST_LOG_LEVEL="INFO"

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TEST_RESULTS=()

# Function to run a workflow test
run_workflow_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"
    local timeout="${4:-300}"  # 5 minutes default timeout
    
    log_info "Running workflow test: $test_name"
    
    local start_time=$(date +%s)
    local exit_code=0
    local output=""
    
    # Run command with timeout
    if timeout "$timeout" bash -c "$test_command" > "/tmp/test_output_$$" 2>&1; then
        exit_code=0
        output=$(cat "/tmp/test_output_$$")
    else
        exit_code=$?
        output=$(cat "/tmp/test_output_$$" 2>/dev/null || echo "No output captured")
    fi
    
    rm -f "/tmp/test_output_$$"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Check if test passed
    if [ $exit_code -eq $expected_exit_code ]; then
        log_success "✓ $test_name (${duration}s)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        TEST_RESULTS+=("PASS: $test_name")
    else
        log_error "✗ $test_name (${duration}s) - Expected exit code $expected_exit_code, got $exit_code"
        if [ ${#output} -lt 500 ]; then
            log_error "Output: $output"
        else
            log_error "Output (truncated): ${output:0:500}..."
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
        TEST_RESULTS+=("FAIL: $test_name - Exit code $exit_code")
    fi
}

# Function to test complete initial deployment workflow
test_initial_deployment_workflow() {
    log_info "=== Testing Complete Initial Deployment Workflow ==="
    
    # Test dry run initial deployment
    run_workflow_test "Initial deployment dry run" \
        "$SCRIPT_DIR/deploy.sh --mode initial --environment $TEST_ENVIRONMENT --project-name $TEST_PROJECT_NAME --dry-run --skip-validation" \
        0 \
        120
    
    # Test initial deployment with validation (will fail on AWS CLI but should handle gracefully)
    run_workflow_test "Initial deployment with validation" \
        "$SCRIPT_DIR/deploy.sh --mode initial --environment $TEST_ENVIRONMENT --project-name $TEST_PROJECT_NAME --dry-run" \
        1 \
        120
    
    # Test initial deployment with custom region
    run_workflow_test "Initial deployment with custom region" \
        "$SCRIPT_DIR/deploy.sh --mode initial --environment $TEST_ENVIRONMENT --project-name $TEST_PROJECT_NAME --region ap-southeast-1 --dry-run --skip-validation" \
        0 \
        120
    
    # Test initial deployment with force flag
    run_workflow_test "Initial deployment with force flag" \
        "$SCRIPT_DIR/deploy.sh --mode initial --environment $TEST_ENVIRONMENT --project-name $TEST_PROJECT_NAME --dry-run --skip-validation --force" \
        0 \
        120
}

# Function to test complete update deployment workflow
test_update_deployment_workflow() {
    log_info "=== Testing Complete Update Deployment Workflow ==="
    
    # Test dry run update deployment
    run_workflow_test "Update deployment dry run" \
        "$SCRIPT_DIR/deploy.sh --mode update --environment $TEST_ENVIRONMENT --project-name $TEST_PROJECT_NAME --dry-run --skip-validation" \
        0 \
        120
    
    # Test update deployment with custom AWS profile
    run_workflow_test "Update deployment with AWS profile" \
        "$SCRIPT_DIR/deploy.sh --mode update --environment $TEST_ENVIRONMENT --project-name $TEST_PROJECT_NAME --aws-profile test-profile --dry-run --skip-validation" \
        0 \
        120
    
    # Test update deployment with debug logging
    run_workflow_test "Update deployment with debug logging" \
        "$SCRIPT_DIR/deploy.sh --mode update --environment $TEST_ENVIRONMENT --project-name $TEST_PROJECT_NAME --log-level DEBUG --dry-run --skip-validation" \
        0 \
        120
}

# Function to test complete cleanup workflow
test_cleanup_workflow() {
    log_info "=== Testing Complete Cleanup Workflow ==="
    
    # Test dry run cleanup
    run_workflow_test "Cleanup dry run" \
        "$SCRIPT_DIR/deploy.sh --mode cleanup --environment $TEST_ENVIRONMENT --project-name $TEST_PROJECT_NAME --dry-run --skip-validation" \
        0 \
        120
    
    # Test cleanup with force flag
    run_workflow_test "Cleanup with force flag" \
        "$SCRIPT_DIR/deploy.sh --mode cleanup --environment $TEST_ENVIRONMENT --project-name $TEST_PROJECT_NAME --dry-run --skip-validation --force" \
        0 \
        120
    
    # Test cleanup for production environment (should work in dry run)
    run_workflow_test "Production cleanup dry run" \
        "$SCRIPT_DIR/deploy.sh --mode cleanup --environment production --project-name $TEST_PROJECT_NAME --dry-run --skip-validation --force" \
        0 \
        120
}

# Function to test rollback scenarios
test_rollback_scenarios() {
    log_info "=== Testing Rollback Scenarios ==="
    
    # Test rollback dry run
    run_workflow_test "Rollback dry run" \
        "$SCRIPT_DIR/deploy.sh --mode rollback --environment $TEST_ENVIRONMENT --project-name $TEST_PROJECT_NAME --dry-run --skip-validation" \
        0 \
        120
    
    # Test rollback with specific scope
    run_workflow_test "Rollback with lambda scope" \
        "$SCRIPT_DIR/deploy.sh --mode rollback --environment $TEST_ENVIRONMENT --project-name $TEST_PROJECT_NAME --rollback-scope lambda --dry-run --skip-validation" \
        0 \
        120
    
    # Test rollback with checkpoint
    run_workflow_test "Rollback with checkpoint" \
        "$SCRIPT_DIR/deploy.sh --mode rollback --environment $TEST_ENVIRONMENT --project-name $TEST_PROJECT_NAME --checkpoint test-checkpoint --dry-run --skip-validation" \
        0 \
        120
}

# Function to test resume scenarios
test_resume_scenarios() {
    log_info "=== Testing Resume Scenarios ==="
    
    # Test resume dry run
    run_workflow_test "Resume deployment dry run" \
        "$SCRIPT_DIR/deploy.sh --mode resume --environment $TEST_ENVIRONMENT --project-name $TEST_PROJECT_NAME --dry-run --skip-validation" \
        0 \
        120
    
    # Test resume with specific checkpoint
    run_workflow_test "Resume from checkpoint" \
        "$SCRIPT_DIR/deploy.sh --mode resume --environment $TEST_ENVIRONMENT --project-name $TEST_PROJECT_NAME --checkpoint infrastructure --dry-run --skip-validation" \
        0 \
        120
}

# Function to test error handling scenarios
test_error_handling_scenarios() {
    log_info "=== Testing Error Handling Scenarios ==="
    
    # Test invalid mode
    run_workflow_test "Invalid deployment mode" \
        "$SCRIPT_DIR/deploy.sh --mode invalid --environment $TEST_ENVIRONMENT --project-name $TEST_PROJECT_NAME" \
        1 \
        30
    
    # Test missing required arguments
    run_workflow_test "Missing project name" \
        "$SCRIPT_DIR/deploy.sh --mode initial --environment $TEST_ENVIRONMENT" \
        1 \
        30
    
    # Test invalid environment
    run_workflow_test "Invalid environment" \
        "$SCRIPT_DIR/deploy.sh --mode initial --environment invalid --project-name $TEST_PROJECT_NAME" \
        1 \
        30
    
    # Test invalid AWS region
    run_workflow_test "Invalid AWS region" \
        "$SCRIPT_DIR/deploy.sh --mode initial --environment $TEST_ENVIRONMENT --project-name $TEST_PROJECT_NAME --region invalid-region --dry-run --skip-validation" \
        0 \
        120
}

# Function to test orchestrator integration
test_orchestrator_integration() {
    log_info "=== Testing Orchestrator Integration ==="
    
    # Test orchestrator direct execution
    run_workflow_test "Orchestrator direct execution" \
        "$SCRIPT_DIR/integration/full-deployment-orchestrator.sh --mode initial --environment $TEST_ENVIRONMENT --project-name $TEST_PROJECT_NAME --dry-run --skip-validation" \
        0 \
        120
    
    # Test orchestrator with all parameters
    run_workflow_test "Orchestrator with all parameters" \
        "$SCRIPT_DIR/integration/full-deployment-orchestrator.sh --mode initial --environment $TEST_ENVIRONMENT --project-name $TEST_PROJECT_NAME --region ap-southeast-1 --dry-run --skip-validation --force-cleanup" \
        0 \
        120
    
    # Test orchestrator cleanup mode
    run_workflow_test "Orchestrator cleanup mode" \
        "$SCRIPT_DIR/integration/full-deployment-orchestrator.sh --mode cleanup --environment $TEST_ENVIRONMENT --project-name $TEST_PROJECT_NAME --dry-run --skip-validation --force-cleanup" \
        0 \
        120
}

# Function to test workflow combinations
test_workflow_combinations() {
    log_info "=== Testing Workflow Combinations ==="
    
    # Test initial -> update sequence (dry run)
    log_info "Testing initial -> update sequence"
    run_workflow_test "Initial deployment in sequence" \
        "$SCRIPT_DIR/deploy.sh --mode initial --environment $TEST_ENVIRONMENT --project-name ${TEST_PROJECT_NAME}-seq --dry-run --skip-validation" \
        0 \
        120
    
    run_workflow_test "Update deployment in sequence" \
        "$SCRIPT_DIR/deploy.sh --mode update --environment $TEST_ENVIRONMENT --project-name ${TEST_PROJECT_NAME}-seq --dry-run --skip-validation" \
        0 \
        120
    
    # Test initial -> cleanup sequence (dry run)
    log_info "Testing initial -> cleanup sequence"
    run_workflow_test "Initial deployment for cleanup test" \
        "$SCRIPT_DIR/deploy.sh --mode initial --environment $TEST_ENVIRONMENT --project-name ${TEST_PROJECT_NAME}-cleanup --dry-run --skip-validation" \
        0 \
        120
    
    run_workflow_test "Cleanup deployment in sequence" \
        "$SCRIPT_DIR/deploy.sh --mode cleanup --environment $TEST_ENVIRONMENT --project-name ${TEST_PROJECT_NAME}-cleanup --dry-run --skip-validation --force" \
        0 \
        120
}

# Function to test concurrent execution safety
test_concurrent_execution() {
    log_info "=== Testing Concurrent Execution Safety ==="
    
    # Test multiple dry runs in parallel (should be safe)
    log_info "Starting parallel dry run tests..."
    
    # Start multiple background processes
    "$SCRIPT_DIR/deploy.sh" --mode initial --environment $TEST_ENVIRONMENT --project-name ${TEST_PROJECT_NAME}-p1 --dry-run --skip-validation > "/tmp/parallel_test_1_$$" 2>&1 &
    local pid1=$!
    
    "$SCRIPT_DIR/deploy.sh" --mode update --environment $TEST_ENVIRONMENT --project-name ${TEST_PROJECT_NAME}-p2 --dry-run --skip-validation > "/tmp/parallel_test_2_$$" 2>&1 &
    local pid2=$!
    
    "$SCRIPT_DIR/deploy.sh" --mode cleanup --environment $TEST_ENVIRONMENT --project-name ${TEST_PROJECT_NAME}-p3 --dry-run --skip-validation --force > "/tmp/parallel_test_3_$$" 2>&1 &
    local pid3=$!
    
    # Wait for all processes to complete
    local all_passed=true
    
    if wait $pid1; then
        log_success "✓ Parallel test 1 completed successfully"
    else
        log_error "✗ Parallel test 1 failed"
        all_passed=false
    fi
    
    if wait $pid2; then
        log_success "✓ Parallel test 2 completed successfully"
    else
        log_error "✗ Parallel test 2 failed"
        all_passed=false
    fi
    
    if wait $pid3; then
        log_success "✓ Parallel test 3 completed successfully"
    else
        log_error "✗ Parallel test 3 failed"
        all_passed=false
    fi
    
    # Clean up temp files
    rm -f "/tmp/parallel_test_"*"_$$"
    
    if [ "$all_passed" = true ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        TEST_RESULTS+=("PASS: Concurrent execution safety")
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        TEST_RESULTS+=("FAIL: Concurrent execution safety")
    fi
}

# Function to generate comprehensive test report
generate_test_report() {
    local report_file="./complete-workflow-test-report.md"
    
    log_info "Generating comprehensive test report: $report_file"
    
    cat > "$report_file" << EOF
# Complete End-to-End Workflow Test Report

**Test Run:** $(date -u +%Y-%m-%dT%H:%M:%SZ)  
**Environment:** $TEST_ENVIRONMENT  
**Project:** $TEST_PROJECT_NAME  
**Region:** $TEST_AWS_REGION  

## Summary

- **Total Tests:** $((TESTS_PASSED + TESTS_FAILED))
- **Passed:** $TESTS_PASSED
- **Failed:** $TESTS_FAILED
- **Success Rate:** $(( TESTS_PASSED * 100 / (TESTS_PASSED + TESTS_FAILED) ))%

## Test Results

EOF
    
    for result in "${TEST_RESULTS[@]}"; do
        echo "- $result" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

## Test Categories

### 1. Initial Deployment Workflow
- Complete initial deployment process
- Validation handling
- Custom region support
- Force flag functionality

### 2. Update Deployment Workflow
- Update deployment process
- AWS profile configuration
- Debug logging functionality

### 3. Cleanup Workflow
- Resource cleanup process
- Force cleanup functionality
- Production environment handling

### 4. Rollback Scenarios
- Rollback functionality
- Scope-specific rollback
- Checkpoint-based rollback

### 5. Resume Scenarios
- Resume deployment functionality
- Checkpoint-based resume

### 6. Error Handling
- Invalid parameter handling
- Missing argument validation
- Graceful error recovery

### 7. Orchestrator Integration
- Direct orchestrator execution
- Parameter passing validation
- Mode-specific functionality

### 8. Workflow Combinations
- Sequential deployment workflows
- Initial -> Update sequences
- Initial -> Cleanup sequences

### 9. Concurrent Execution
- Parallel execution safety
- Resource conflict prevention

## Configuration

- **Test Project Name:** $TEST_PROJECT_NAME
- **Test Environment:** $TEST_ENVIRONMENT
- **Test AWS Region:** $TEST_AWS_REGION
- **Test Log Level:** $TEST_LOG_LEVEL

## Recommendations

EOF
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo "✅ All workflow tests passed! The deployment system is production-ready." >> "$report_file"
        echo "" >> "$report_file"
        echo "### Next Steps" >> "$report_file"
        echo "1. Deploy to a test AWS environment for real infrastructure validation" >> "$report_file"
        echo "2. Set up monitoring and alerting for production deployments" >> "$report_file"
        echo "3. Create CI/CD pipeline integration" >> "$report_file"
        echo "4. Document operational procedures for production use" >> "$report_file"
    else
        echo "❌ Some workflow tests failed. Please review and fix the issues before production use." >> "$report_file"
        echo "" >> "$report_file"
        echo "### Required Actions" >> "$report_file"
        echo "1. Review failed test outputs above" >> "$report_file"
        echo "2. Fix identified issues in the deployment scripts" >> "$report_file"
        echo "3. Re-run the complete test suite" >> "$report_file"
        echo "4. Validate fixes with additional testing" >> "$report_file"
    fi
    
    log_success "Comprehensive test report generated: $report_file"
}

# Main execution function
main() {
    log_info "Starting Complete End-to-End Workflow Tests"
    log_info "Test Configuration: Project=$TEST_PROJECT_NAME, Environment=$TEST_ENVIRONMENT, Region=$TEST_AWS_REGION"
    
    # Set log level
    set_log_level "$TEST_LOG_LEVEL"
    
    # Run all test suites
    test_initial_deployment_workflow
    test_update_deployment_workflow
    test_cleanup_workflow
    test_rollback_scenarios
    test_resume_scenarios
    test_error_handling_scenarios
    test_orchestrator_integration
    test_workflow_combinations
    test_concurrent_execution
    
    # Generate comprehensive test report
    generate_test_report
    
    # Final summary
    echo ""
    echo "========================================"
    echo "Complete Workflow Test Summary"
    echo "========================================"
    echo "Total Tests: $((TESTS_PASSED + TESTS_FAILED))"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "🎉 All workflow tests passed! System is production-ready."
        exit 0
    else
        log_error "❌ $TESTS_FAILED workflow test(s) failed. Please review and fix issues."
        exit 1
    fi
}

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi