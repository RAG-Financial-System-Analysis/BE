#!/bin/bash

# Infrastructure Integration Tests Runner
# Runs comprehensive integration tests for infrastructure provisioning
# Combines validation tests and connectivity tests
# 
# Task 3.4: Write integration tests for infrastructure provisioning
# Requirements: 1.1, 1.2, 1.3, 1.4

set -euo pipefail

# Script directory and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utilities/logging.sh"
source "$SCRIPT_DIR/../utilities/error-handling.sh"

# Test configuration
readonly TEST_LOG_LEVEL="INFO"
readonly TEST_SUITE_NAME="Infrastructure Integration Tests"

# Test results tracking
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0

# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Runs comprehensive infrastructure integration tests for AWS deployment automation.

OPTIONS:
    --environment ENV          Environment to test (default: integration-test)
    --project-name NAME        Project name (default: infra-test)
    --validation-only          Run validation tests only (no connectivity tests)
    --connectivity-only        Run connectivity tests only (no validation tests)
    --skip-connectivity        Skip actual connectivity tests in connectivity suite
    --aws-profile PROFILE      AWS profile to use
    --verbose                  Enable verbose logging
    --help                     Show this help message

TEST SUITES:
    1. Infrastructure Provisioning Integration Tests
       - Complete infrastructure stack creation validation
       - VPC and networking configuration validation
       - IAM role and policy assignments validation
       - Component integration and connectivity validation
       - Cost optimization validation
       - Error handling and rollback mechanisms validation

    2. Infrastructure Connectivity Validation Tests
       - VPC and networking validation (actual resources)
       - RDS instance validation (actual resources)
       - Lambda function validation (actual resources)
       - Network connectivity validation (actual resources)
       - IAM permissions validation (actual resources)

EXAMPLES:
    # Run all integration tests
    $0 --environment production --project-name myapp

    # Run validation tests only
    $0 --validation-only --environment staging

    # Run connectivity tests with specific resources
    $0 --connectivity-only --environment production --verbose

    # Run tests without actual connectivity checks
    $0 --skip-connectivity --environment development

PREREQUISITES:
    - AWS CLI configured with appropriate permissions
    - Infrastructure provisioning scripts must be available
    - For connectivity tests: AWS resources must be provisioned

EOF
}

# Function to parse command line arguments
parse_arguments() {
    ENVIRONMENT="integration-test"
    PROJECT_NAME="infra-test"
    VALIDATION_ONLY=false
    CONNECTIVITY_ONLY=false
    SKIP_CONNECTIVITY=false
    AWS_PROFILE=""
    VERBOSE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --project-name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --validation-only)
                VALIDATION_ONLY=true
                shift
                ;;
            --connectivity-only)
                CONNECTIVITY_ONLY=true
                shift
                ;;
            --skip-connectivity)
                SKIP_CONNECTIVITY=true
                shift
                ;;
            --aws-profile)
                AWS_PROFILE="$2"
                export AWS_PROFILE
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate mutually exclusive options
    if [ "$VALIDATION_ONLY" = true ] && [ "$CONNECTIVITY_ONLY" = true ]; then
        log_error "Cannot specify both --validation-only and --connectivity-only"
        exit 1
    fi
}

# Function to run a test suite and track results
run_test_suite() {
    local suite_name="$1"
    local test_script="$2"
    shift 2
    local test_args=("$@")
    
    log_info "========================================"
    log_info "Running Test Suite: $suite_name"
    log_info "========================================"
    
    local suite_start_time=$(date +%s)
    
    if bash "$SCRIPT_DIR/$test_script" "${test_args[@]}"; then
        local suite_end_time=$(date +%s)
        local suite_duration=$((suite_end_time - suite_start_time))
        
        log_success "✓ Test Suite PASSED: $suite_name (${suite_duration}s)"
        ((TOTAL_PASSED++))
        return 0
    else
        local suite_end_time=$(date +%s)
        local suite_duration=$((suite_end_time - suite_start_time))
        
        log_error "✗ Test Suite FAILED: $suite_name (${suite_duration}s)"
        ((TOTAL_FAILED++))
        return 1
    fi
}

# Function to run infrastructure provisioning integration tests
run_provisioning_integration_tests() {
    log_info "Starting Infrastructure Provisioning Integration Tests..."
    
    ((TOTAL_TESTS++))
    run_test_suite \
        "Infrastructure Provisioning Integration Tests" \
        "test-infrastructure-provisioning-integration.sh"
}

# Function to run infrastructure connectivity validation tests
run_connectivity_validation_tests() {
    log_info "Starting Infrastructure Connectivity Validation Tests..."
    
    local connectivity_args=(
        "--environment" "$ENVIRONMENT"
        "--project-name" "$PROJECT_NAME"
    )
    
    if [ "$SKIP_CONNECTIVITY" = true ]; then
        connectivity_args+=("--skip-connectivity")
    fi
    
    if [ -n "$AWS_PROFILE" ]; then
        connectivity_args+=("--aws-profile" "$AWS_PROFILE")
    fi
    
    ((TOTAL_TESTS++))
    run_test_suite \
        "Infrastructure Connectivity Validation Tests" \
        "test-infrastructure-connectivity-validation.sh" \
        "${connectivity_args[@]}"
}

# Function to display comprehensive test results
display_comprehensive_results() {
    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))
    
    echo ""
    echo "========================================"
    echo "Infrastructure Integration Tests - Final Results"
    echo "========================================"
    echo ""
    echo "Test Environment: $ENVIRONMENT"
    echo "Project Name: $PROJECT_NAME"
    echo "Total Duration: ${total_duration}s"
    echo ""
    echo "Test Suites Run:    $TOTAL_TESTS"
    echo "Test Suites Passed: $TOTAL_PASSED"
    echo "Test Suites Failed: $TOTAL_FAILED"
    echo ""
    
    if [ $TOTAL_FAILED -eq 0 ]; then
        log_success "🎉 ALL INFRASTRUCTURE INTEGRATION TESTS PASSED!"
        echo ""
        echo "✅ Infrastructure provisioning scripts are validated and functional"
        echo "✅ Component integration and connectivity are properly configured"
        echo "✅ AWS resources meet requirements and cost optimization criteria"
        echo "✅ Error handling and rollback mechanisms are working correctly"
        echo ""
        echo "Infrastructure is ready for deployment!"
        echo ""
        echo "Next Steps:"
        echo "1. Run actual infrastructure provisioning: ./deploy.sh --mode initial"
        echo "2. Deploy application code: ./deploy.sh --mode update"
        echo "3. Monitor deployment logs and AWS resources"
        echo ""
        return 0
    else
        log_error "❌ $TOTAL_FAILED INFRASTRUCTURE INTEGRATION TEST SUITE(S) FAILED!"
        echo ""
        echo "Please review the failed test suites and address the issues:"
        echo ""
        echo "🔍 Check AWS CLI configuration and permissions"
        echo "🔍 Verify infrastructure provisioning scripts"
        echo "🔍 Review AWS resource configurations"
        echo "🔍 Validate network and security group settings"
        echo ""
        echo "Re-run tests after fixing issues:"
        echo "$0 --environment $ENVIRONMENT --project-name $PROJECT_NAME"
        echo ""
        return 1
    fi
}

# Function to validate test environment
validate_test_environment() {
    log_info "Validating test environment..."
    
    # Check required test scripts exist
    local required_scripts=(
        "test-infrastructure-provisioning-integration.sh"
        "test-infrastructure-connectivity-validation.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [ ! -f "$SCRIPT_DIR/$script" ]; then
            log_error "Required test script not found: $script"
            exit 1
        fi
        
        if [ ! -x "$SCRIPT_DIR/$script" ]; then
            log_warn "Making test script executable: $script"
            chmod +x "$SCRIPT_DIR/$script"
        fi
    done
    
    # Check utilities are available
    if [ ! -f "$SCRIPT_DIR/../utilities/logging.sh" ]; then
        log_error "Required utility not found: logging.sh"
        exit 1
    fi
    
    log_success "Test environment validation completed"
}

# Main execution function
main() {
    local START_TIME=$(date +%s)
    
    echo "========================================"
    echo "$TEST_SUITE_NAME"
    echo "Task 3.4: Write integration tests for infrastructure provisioning"
    echo "Requirements: 1.1, 1.2, 1.3, 1.4"
    echo "========================================"
    echo ""
    
    # Parse arguments
    parse_arguments "$@"
    
    # Set up logging
    if [ "$VERBOSE" = true ]; then
        set_log_level "DEBUG"
    else
        set_log_level "$TEST_LOG_LEVEL"
    fi
    
    log_info "Starting comprehensive infrastructure integration tests"
    log_info "Environment: $ENVIRONMENT"
    log_info "Project: $PROJECT_NAME"
    
    # Validate test environment
    validate_test_environment
    
    # Set up error handling
    set_error_context "Infrastructure Integration Tests"
    set_error_remediation "Check test scripts and AWS configuration, then retry"
    
    # Run test suites based on options
    if [ "$CONNECTIVITY_ONLY" = true ]; then
        log_info "Running connectivity validation tests only"
        run_connectivity_validation_tests
    elif [ "$VALIDATION_ONLY" = true ]; then
        log_info "Running provisioning integration tests only"
        run_provisioning_integration_tests
    else
        log_info "Running all infrastructure integration tests"
        run_provisioning_integration_tests
        run_connectivity_validation_tests
    fi
    
    # Display comprehensive results
    display_comprehensive_results
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi