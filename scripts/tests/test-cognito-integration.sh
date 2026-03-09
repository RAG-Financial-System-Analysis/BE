#!/bin/bash

# Unit Tests for Cognito Integration
# Task 11.3: Test Cognito configuration validation
# Test IAM permission setup
# Requirements: 8.1, 8.2, 8.3

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/utilities/logging.sh"
source "$SCRIPT_DIR/utilities/error-handling.sh"

# Test configuration
TEST_LOG_LEVEL="INFO"
TESTS_PASSED=0
TESTS_FAILED=0
TEST_RESULTS=()

# Function to run unit test
run_unit_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"
    
    log_info "Chạy unit test: $test_name"
    
    local start_time=$(date +%s)
    local exit_code=0
    local output=""
    
    # Capture output and exit code
    if output=$(eval "$test_command" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Check if test passed
    if [ $exit_code -eq $expected_exit_code ]; then
        log_success "✓ $test_name (${duration}s)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        TEST_RESULTS+=("PASS: $test_name")
    else
        log_error "✗ $test_name (${duration}s) - Mong đợi exit code $expected_exit_code, nhận được $exit_code"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        TEST_RESULTS+=("FAIL: $test_name - Exit code $exit_code")
    fi
}

# Test Cognito configuration validation
test_cognito_configuration_validation() {
    log_info "=== Test Cognito Configuration Validation ==="
    
    # Test help option
    run_unit_test "Cognito validation help" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --help" \
        0
    
    # Test with valid Cognito configuration
    run_unit_test "Valid Cognito configuration" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_XXXXXXXXX' --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --region 'ap-southeast-1' --dry-run" \
        0
    
    # Test with invalid User Pool ID format
    run_unit_test "Invalid User Pool ID format" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'invalid-pool-id' --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --region 'ap-southeast-1' --dry-run" \
        1
    
    # Test with invalid Client ID format
    run_unit_test "Invalid Client ID format" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_XXXXXXXXX' --client-id 'invalid-client-id' --region 'ap-southeast-1' --dry-run" \
        1
    
    # Test with invalid region
    run_unit_test "Invalid region" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_XXXXXXXXX' --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --region 'invalid-region' --dry-run" \
        1
    
    # Test with missing required parameters
    run_unit_test "Missing User Pool ID" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --region 'ap-southeast-1' --dry-run" \
        1
    
    run_unit_test "Missing Client ID" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_XXXXXXXXX' --region 'ap-southeast-1' --dry-run" \
        1
    
    run_unit_test "Missing region" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_XXXXXXXXX' --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --dry-run" \
        1
}

# Test Cognito connectivity testing
test_cognito_connectivity_testing() {
    log_info "=== Test Cognito Connectivity Testing ==="
    
    # Test connectivity check
    run_unit_test "Cognito connectivity check" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_XXXXXXXXX' --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --region 'ap-southeast-1' --test-connectivity --dry-run" \
        0
    
    # Test with different AWS profiles
    run_unit_test "Cognito connectivity with AWS profile" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_XXXXXXXXX' --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --region 'ap-southeast-1' --aws-profile 'test-profile' --test-connectivity --dry-run" \
        0
    
    # Test timeout scenarios
    run_unit_test "Cognito connectivity timeout" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_XXXXXXXXX' --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --region 'ap-southeast-1' --timeout 1 --test-connectivity --dry-run" \
        0  # Should handle timeout gracefully
}

# Test JWT token validation functionality
test_jwt_token_validation() {
    log_info "=== Test JWT Token Validation Functionality ==="
    
    # Test JWT validation setup
    run_unit_test "JWT validation setup" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_XXXXXXXXX' --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --region 'ap-southeast-1' --validate-jwt --dry-run" \
        0
    
    # Test with sample JWT token (invalid but format check)
    local sample_jwt="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    
    run_unit_test "JWT token format validation" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_XXXXXXXXX' --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --region 'ap-southeast-1' --jwt-token '$sample_jwt' --validate-jwt --dry-run" \
        0
    
    # Test with invalid JWT format
    run_unit_test "Invalid JWT token format" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_XXXXXXXXX' --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --region 'ap-southeast-1' --jwt-token 'invalid-jwt-token' --validate-jwt --dry-run" \
        1
    
    # Test JWT validation without token
    run_unit_test "JWT validation without token" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_XXXXXXXXX' --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --region 'ap-southeast-1' --validate-jwt --dry-run" \
        1
}

# Test IAM permission setup
test_iam_permission_setup() {
    log_info "=== Test IAM Permission Setup ==="
    
    # Test IAM configuration for Cognito
    run_unit_test "IAM Cognito configuration help" \
        "$SCRIPT_DIR/utilities/configure-cognito-iam.sh --help" \
        0
    
    # Test IAM role creation for Cognito access
    run_unit_test "IAM role creation for Cognito" \
        "$SCRIPT_DIR/utilities/configure-cognito-iam.sh --project-name 'test-project' --environment 'development' --dry-run" \
        0
    
    # Test with specific role name
    run_unit_test "IAM role with custom name" \
        "$SCRIPT_DIR/utilities/configure-cognito-iam.sh --project-name 'test-project' --environment 'development' --role-name 'custom-cognito-role' --dry-run" \
        0
    
    # Test IAM policy attachment
    run_unit_test "IAM policy attachment" \
        "$SCRIPT_DIR/utilities/configure-cognito-iam.sh --project-name 'test-project' --environment 'development' --attach-policies --dry-run" \
        0
    
    # Test with Lambda function ARN
    run_unit_test "IAM configuration with Lambda ARN" \
        "$SCRIPT_DIR/utilities/configure-cognito-iam.sh --project-name 'test-project' --environment 'development' --lambda-arn 'arn:aws:lambda:ap-southeast-1:123456789012:function:test-function' --dry-run" \
        0
}

# Test Cognito service permissions
test_cognito_service_permissions() {
    log_info "=== Test Cognito Service Permissions ==="
    
    # Test Cognito service permission validation
    run_unit_test "Cognito service permissions check" \
        "$SCRIPT_DIR/utilities/configure-cognito-iam.sh --project-name 'test-project' --environment 'development' --validate-permissions --dry-run" \
        0
    
    # Test with specific Cognito actions
    local cognito_actions=(
        "cognito-idp:AdminGetUser"
        "cognito-idp:AdminCreateUser"
        "cognito-idp:AdminSetUserPassword"
        "cognito-idp:AdminDeleteUser"
    )
    
    for action in "${cognito_actions[@]}"; do
        run_unit_test "Cognito permission: $action" \
            "$SCRIPT_DIR/utilities/configure-cognito-iam.sh --project-name 'test-project' --environment 'development' --cognito-action '$action' --validate-permissions --dry-run" \
            0
    done
    
    # Test invalid Cognito action
    run_unit_test "Invalid Cognito action" \
        "$SCRIPT_DIR/utilities/configure-cognito-iam.sh --project-name 'test-project' --environment 'development' --cognito-action 'invalid-action' --validate-permissions --dry-run" \
        1
}

# Test Cognito configuration error handling
test_cognito_error_handling() {
    log_info "=== Test Cognito Configuration Error Handling ==="
    
    # Test with non-existent User Pool
    run_unit_test "Non-existent User Pool" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_NONEXISTENT' --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --region 'ap-southeast-1' --test-connectivity --dry-run" \
        1
    
    # Test with non-existent Client ID
    run_unit_test "Non-existent Client ID" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_XXXXXXXXX' --client-id 'nonexistentclientid123456' --region 'ap-southeast-1' --test-connectivity --dry-run" \
        1
    
    # Test with invalid AWS credentials
    run_unit_test "Invalid AWS credentials for Cognito" \
        "AWS_ACCESS_KEY_ID=invalid AWS_SECRET_ACCESS_KEY=invalid $SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_XXXXXXXXX' --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --region 'ap-southeast-1' --test-connectivity --dry-run" \
        1
    
    # Test network connectivity issues
    run_unit_test "Network connectivity issues" \
        "timeout 1 $SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_XXXXXXXXX' --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --region 'ap-southeast-1' --test-connectivity --dry-run" \
        124  # timeout exit code
}

# Test Cognito integration with Lambda
test_cognito_lambda_integration() {
    log_info "=== Test Cognito Lambda Integration ==="
    
    # Test Lambda environment variable setup for Cognito
    run_unit_test "Lambda Cognito environment variables" \
        "$SCRIPT_DIR/utilities/configure-cognito-iam.sh --project-name 'test-project' --environment 'development' --setup-lambda-env --user-pool-id 'ap-southeast-1_XXXXXXXXX' --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --dry-run" \
        0
    
    # Test Lambda execution role for Cognito
    run_unit_test "Lambda execution role for Cognito" \
        "$SCRIPT_DIR/utilities/configure-cognito-iam.sh --project-name 'test-project' --environment 'development' --setup-lambda-role --dry-run" \
        0
    
    # Test Cognito trigger configuration
    run_unit_test "Cognito trigger configuration" \
        "$SCRIPT_DIR/utilities/configure-cognito-iam.sh --project-name 'test-project' --environment 'development' --setup-triggers --lambda-arn 'arn:aws:lambda:ap-southeast-1:123456789012:function:test-function' --dry-run" \
        0
}

# Test configuration file support
test_configuration_file_support() {
    log_info "=== Test Configuration File Support ==="
    
    # Create temporary Cognito config file
    local temp_config="/tmp/cognito-config-test.json"
    cat > "$temp_config" << EOF
{
    "UserPoolId": "ap-southeast-1_XXXXXXXXX",
    "ClientId": "xxxxxxxxxxxxxxxxxxxxxxxxxx",
    "Region": "ap-southeast-1",
    "TestConnectivity": true,
    "ValidateJWT": true
}
EOF
    
    # Test config file loading
    run_unit_test "Cognito config file loading" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --config-file '$temp_config' --dry-run" \
        0
    
    # Test invalid config file
    run_unit_test "Invalid Cognito config file" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --config-file '/nonexistent/config.json' --dry-run" \
        1
    
    # Test malformed config file
    echo "invalid json" > "$temp_config"
    run_unit_test "Malformed Cognito config file" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --config-file '$temp_config' --dry-run" \
        1
    
    # Cleanup
    rm -f "$temp_config"
}

# Test verbose and logging options
test_logging_options() {
    log_info "=== Test Logging Options ==="
    
    # Test verbose mode
    run_unit_test "Cognito validation verbose mode" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_XXXXXXXXX' --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --region 'ap-southeast-1' --verbose --dry-run" \
        0
    
    # Test quiet mode
    run_unit_test "Cognito validation quiet mode" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_XXXXXXXXX' --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --region 'ap-southeast-1' --quiet --dry-run" \
        0
    
    # Test debug log level
    run_unit_test "Cognito validation debug log" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_XXXXXXXXX' --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --region 'ap-southeast-1' --log-level DEBUG --dry-run" \
        0
    
    # Test log to file
    run_unit_test "Cognito validation log to file" \
        "$SCRIPT_DIR/utilities/validate-cognito.sh --user-pool-id 'ap-southeast-1_XXXXXXXXX' --client-id 'xxxxxxxxxxxxxxxxxxxxxxxxxx' --region 'ap-southeast-1' --log-file /tmp/cognito-validation.log --dry-run" \
        0
}

# Generate test report
generate_test_report() {
    local report_file="./test-cognito-integration-report.md"
    
    log_info "Tạo báo cáo test: $report_file"
    
    cat > "$report_file" << EOF
# Báo Cáo Unit Test - Cognito Integration

**Ngày test:** $(date -u +%Y-%m-%dT%H:%M:%SZ)  
**Task:** 11.3 Write unit tests for Cognito integration  
**Requirements:** 8.1, 8.2, 8.3  

## Tóm Tắt

- **Tổng số tests:** $((TESTS_PASSED + TESTS_FAILED))
- **Passed:** $TESTS_PASSED
- **Failed:** $TESTS_FAILED
- **Tỷ lệ thành công:** $(( TESTS_PASSED * 100 / (TESTS_PASSED + TESTS_FAILED) ))%

## Kết Quả Test

EOF
    
    for result in "${TEST_RESULTS[@]}"; do
        echo "- $result" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

## Các Nhóm Test

### 1. Cognito Configuration Validation
- Test validation của User Pool ID và Client ID
- Region validation
- Required parameter checking
- Configuration format validation

### 2. Cognito Connectivity Testing
- Test connectivity giữa Lambda và Cognito services
- AWS profile và credential handling
- Timeout và network error handling

### 3. JWT Token Validation Functionality
- Test JWT token validation setup
- Token format validation
- JWT parsing và verification logic

### 4. IAM Permission Setup
- Test IAM role creation cho Cognito access
- Policy attachment và permission validation
- Lambda execution role configuration

### 5. Cognito Service Permissions
- Test specific Cognito service permissions
- Action-based permission validation
- Permission scope và resource access

### 6. Cognito Configuration Error Handling
- Test error handling cho invalid configurations
- Non-existent resources handling
- AWS API error scenarios

### 7. Cognito Lambda Integration
- Test Lambda environment variable setup
- Execution role configuration
- Cognito trigger setup

### 8. Configuration File Support
- Test JSON config file loading
- Configuration parsing và validation
- Error handling cho malformed configs

### 9. Logging Options
- Test verbose, quiet, và debug modes
- Log level configurations
- Log file output

## Kết Luận

EOF
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo "✅ Tất cả unit tests đều PASS! Cognito integration hoạt động chính xác." >> "$report_file"
    else
        echo "❌ Có $TESTS_FAILED test(s) FAIL. Cần sửa lỗi Cognito integration." >> "$report_file"
    fi
    
    log_success "Báo cáo test được tạo: $report_file"
}

# Main execution function
main() {
    log_info "Bắt đầu Unit Tests cho Cognito Integration"
    
    # Set log level
    set_log_level "$TEST_LOG_LEVEL"
    
    # Run all test suites
    test_cognito_configuration_validation
    test_cognito_connectivity_testing
    test_jwt_token_validation
    test_iam_permission_setup
    test_cognito_service_permissions
    test_cognito_error_handling
    test_cognito_lambda_integration
    test_configuration_file_support
    test_logging_options
    
    # Generate test report
    generate_test_report
    
    # Final summary
    echo ""
    echo "========================================"
    echo "Tóm Tắt Unit Test - Cognito Integration"
    echo "========================================"
    echo "Tổng tests: $((TESTS_PASSED + TESTS_FAILED))"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "🎉 Tất cả unit tests PASS! Cognito integration hoạt động tốt."
        exit 0
    else
        log_error "❌ $TESTS_FAILED unit test(s) FAIL. Cần review và sửa lỗi."
        exit 1
    fi
}

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi