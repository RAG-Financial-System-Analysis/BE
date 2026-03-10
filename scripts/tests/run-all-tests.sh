#!/bin/bash

# Run All Tests Script
# Executes all available test suites for the RAG System deployment

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILITIES_DIR="$SCRIPT_DIR/../utilities"
source "$UTILITIES_DIR/logging.sh"

# Configuration
ENVIRONMENT="${ENVIRONMENT:-dev}"
PROJECT_NAME="${PROJECT_NAME:-myragapp}"
LAMBDA_FUNCTION_NAME="$PROJECT_NAME-$ENVIRONMENT-api"

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Runs all available test suites for the RAG System deployment.

OPTIONS:
    --environment ENV         Environment name (default: dev)
    --project-name NAME       Project name (default: myapp)
    --skip-integration       Skip integration tests
    --skip-api               Skip API tests
    --skip-credentials       Skip credential tests
    --help                   Show this help message

TEST SUITES:
    1. 🔐 AWS Credential Detection Test
    2. 🔗 Lambda-RDS Connection Test
    3. 🌐 API Endpoints Test
    4. 👤 User Authentication & Roles Test

EXAMPLES:
    # Run all tests
    $0

    # Run tests for production environment
    $0 --environment production --project-name myrag

    # Skip integration tests
    $0 --skip-integration

EOF
}

# Parse arguments
parse_arguments() {
    local skip_integration=false
    local skip_api=false
    local skip_credentials=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --environment)
                ENVIRONMENT="$2"
                LAMBDA_FUNCTION_NAME="$PROJECT_NAME-$ENVIRONMENT-api"
                shift 2
                ;;
            --project-name)
                PROJECT_NAME="$2"
                LAMBDA_FUNCTION_NAME="$PROJECT_NAME-$ENVIRONMENT-api"
                shift 2
                ;;
            --skip-integration)
                skip_integration=true
                shift
                ;;
            --skip-api)
                skip_api=true
                shift
                ;;
            --skip-credentials)
                skip_credentials=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    export SKIP_INTEGRATION=$skip_integration
    export SKIP_API=$skip_api
    export SKIP_CREDENTIALS=$skip_credentials
}

# Function to run credential detection test
run_credential_test() {
    if [ "$SKIP_CREDENTIALS" = true ]; then
        log_info "⏭️  Skipping credential detection test"
        return 0
    fi
    
    log_info "🔐 Running AWS Credential Detection Test..."
    
    if [ -f "$SCRIPT_DIR/test-credential-detection.sh" ]; then
        if "$SCRIPT_DIR/test-credential-detection.sh"; then
            log_success "✅ Credential detection test passed"
            return 0
        else
            log_error "❌ Credential detection test failed"
            return 1
        fi
    else
        log_warn "⚠️  Credential detection test not found"
        return 0
    fi
}

# Function to run Lambda-RDS connection test
run_connection_test() {
    if [ "$SKIP_INTEGRATION" = true ]; then
        log_info "⏭️  Skipping Lambda-RDS connection test"
        return 0
    fi
    
    log_info "🔗 Running Lambda-RDS Connection Test..."
    
    if [ -f "$SCRIPT_DIR/test-lambda-db-connection.sh" ]; then
        if "$SCRIPT_DIR/test-lambda-db-connection.sh" --function-name "$LAMBDA_FUNCTION_NAME"; then
            log_success "✅ Lambda-RDS connection test passed"
            return 0
        else
            log_error "❌ Lambda-RDS connection test failed"
            return 1
        fi
    else
        log_warn "⚠️  Lambda-RDS connection test not found"
        return 0
    fi
}

# Function to run API tests
run_api_tests() {
    if [ "$SKIP_API" = true ]; then
        log_info "⏭️  Skipping API tests"
        return 0
    fi
    
    log_info "🌐 Running API Endpoints Test..."
    
    local api_test_passed=true
    
    # Test API endpoints
    if [ -f "$SCRIPT_DIR/test-api.sh" ]; then
        if ! "$SCRIPT_DIR/test-api.sh"; then
            log_error "❌ API endpoints test failed"
            api_test_passed=false
        fi
    else
        log_warn "⚠️  API endpoints test not found"
    fi
    
    # Test user roles
    if [ -f "$SCRIPT_DIR/test-user-roles.sh" ]; then
        if ! "$SCRIPT_DIR/test-user-roles.sh"; then
            log_error "❌ User roles test failed"
            api_test_passed=false
        fi
    else
        log_warn "⚠️  User roles test not found"
    fi
    
    if [ "$api_test_passed" = true ]; then
        log_success "✅ API tests passed"
        return 0
    else
        log_error "❌ Some API tests failed"
        return 1
    fi
}

# Function to display test summary
display_test_summary() {
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    local skipped_tests=0
    
    echo ""
    echo "=== Test Summary ==="
    echo "Environment: $ENVIRONMENT"
    echo "Project: $PROJECT_NAME"
    echo "Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo ""
    
    # Count and display results
    if [ "$SKIP_CREDENTIALS" = false ]; then
        total_tests=$((total_tests + 1))
        if run_credential_test &>/dev/null; then
            echo "✅ Credential Detection Test: PASSED"
            passed_tests=$((passed_tests + 1))
        else
            echo "❌ Credential Detection Test: FAILED"
            failed_tests=$((failed_tests + 1))
        fi
    else
        echo "⏭️  Credential Detection Test: SKIPPED"
        skipped_tests=$((skipped_tests + 1))
    fi
    
    if [ "$SKIP_INTEGRATION" = false ]; then
        total_tests=$((total_tests + 1))
        if run_connection_test &>/dev/null; then
            echo "✅ Lambda-RDS Connection Test: PASSED"
            passed_tests=$((passed_tests + 1))
        else
            echo "❌ Lambda-RDS Connection Test: FAILED"
            failed_tests=$((failed_tests + 1))
        fi
    else
        echo "⏭️  Lambda-RDS Connection Test: SKIPPED"
        skipped_tests=$((skipped_tests + 1))
    fi
    
    if [ "$SKIP_API" = false ]; then
        total_tests=$((total_tests + 1))
        if run_api_tests &>/dev/null; then
            echo "✅ API Tests: PASSED"
            passed_tests=$((passed_tests + 1))
        else
            echo "❌ API Tests: FAILED"
            failed_tests=$((failed_tests + 1))
        fi
    else
        echo "⏭️  API Tests: SKIPPED"
        skipped_tests=$((skipped_tests + 1))
    fi
    
    echo ""
    echo "=== Results ==="
    echo "Total Tests: $((total_tests + skipped_tests))"
    echo "Passed: $passed_tests"
    echo "Failed: $failed_tests"
    echo "Skipped: $skipped_tests"
    echo ""
    
    if [ $failed_tests -eq 0 ]; then
        log_success "🎉 All tests completed successfully!"
        return 0
    else
        log_error "❌ $failed_tests test(s) failed"
        return 1
    fi
}

# Main execution function
main() {
    log_info "🧪 Starting All Tests..."
    log_info "Environment: $ENVIRONMENT, Project: $PROJECT_NAME"
    
    # Parse arguments
    parse_arguments "$@"
    
    local overall_success=true
    
    # Run tests
    if ! run_credential_test; then
        overall_success=false
    fi
    
    if ! run_connection_test; then
        overall_success=false
    fi
    
    if ! run_api_tests; then
        overall_success=false
    fi
    
    # Display summary
    display_test_summary
    
    if [ "$overall_success" = true ]; then
        log_success "🎉 All tests completed successfully!"
        exit 0
    else
        log_error "❌ Some tests failed"
        exit 1
    fi
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi