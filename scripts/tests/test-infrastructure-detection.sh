#!/bin/bash

# Unit Tests for Infrastructure Detection
# Task 7.3: Test detection of existing and missing resources
# Test error handling for AWS API failures
# Requirements: 3.3

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

# Test basic infrastructure detection
test_basic_infrastructure_detection() {
    log_info "=== Test Basic Infrastructure Detection ==="
    
    # Test help option
    run_unit_test "Infrastructure detection help" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --help" \
        0
    
    # Test dry run mode
    run_unit_test "Infrastructure detection dry run" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --dry-run --project-name test-project" \
        0
    
    # Test with project name
    run_unit_test "Infrastructure detection with project name" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --dry-run" \
        0
    
    # Test with environment parameter
    run_unit_test "Infrastructure detection with environment" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --environment development --dry-run" \
        0
    
    # Test with AWS profile
    run_unit_test "Infrastructure detection with AWS profile" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --aws-profile test-profile --dry-run" \
        0
    
    # Test with custom region
    run_unit_test "Infrastructure detection with custom region" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --region ap-southeast-1 --dry-run" \
        0
}

# Test resource detection
test_resource_detection() {
    log_info "=== Test Resource Detection ==="
    
    # Test RDS detection
    run_unit_test "RDS instance detection" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --resource-type rds --dry-run" \
        0
    
    # Test Lambda detection
    run_unit_test "Lambda function detection" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --resource-type lambda --dry-run" \
        0
    
    # Test VPC detection
    run_unit_test "VPC detection" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --resource-type vpc --dry-run" \
        0
    
    # Test IAM role detection
    run_unit_test "IAM role detection" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --resource-type iam --dry-run" \
        0
    
    # Test all resources detection
    run_unit_test "All resources detection" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --resource-type all --dry-run" \
        0
    
    # Test invalid resource type
    run_unit_test "Invalid resource type" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --resource-type invalid --dry-run" \
        1
}

# Test missing resources detection
test_missing_resources_detection() {
    log_info "=== Test Missing Resources Detection ==="
    
    # Test detection of non-existent project
    run_unit_test "Non-existent project detection" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name nonexistent-project-12345 --dry-run" \
        0  # Should succeed but report no resources found
    
    # Test detection with invalid AWS credentials
    run_unit_test "Invalid AWS credentials handling" \
        "AWS_PROFILE=nonexistent-profile $SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --dry-run" \
        1  # Should fail with credential error
    
    # Test detection with invalid region
    run_unit_test "Invalid AWS region handling" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --region invalid-region --dry-run" \
        1  # Should fail with region error
    
    # Test detection without project name
    run_unit_test "Missing project name" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --dry-run" \
        1  # Should fail - project name required
}

# Test AWS API error handling
test_aws_api_error_handling() {
    log_info "=== Test AWS API Error Handling ==="
    
    # Test with no AWS CLI
    run_unit_test "No AWS CLI available" \
        "PATH=/nonexistent $SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --dry-run" \
        1  # Should fail if AWS CLI not found
    
    # Test with invalid AWS profile
    run_unit_test "Invalid AWS profile" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --aws-profile invalid-profile-12345 --dry-run" \
        1  # Should fail with profile error
    
    # Test network timeout scenarios
    run_unit_test "Network timeout handling" \
        "timeout 1 $SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --dry-run" \
        124  # timeout command returns 124
    
    # Test permission denied scenarios
    run_unit_test "Permission denied handling" \
        "AWS_ACCESS_KEY_ID=invalid AWS_SECRET_ACCESS_KEY=invalid $SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --dry-run" \
        1  # Should fail with permission error
}

# Test infrastructure health checking
test_infrastructure_health_checking() {
    log_info "=== Test Infrastructure Health Checking ==="
    
    # Test health check mode
    run_unit_test "Infrastructure health check" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --health-check --dry-run" \
        0
    
    # Test detailed health check
    run_unit_test "Detailed health check" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --health-check --detailed --dry-run" \
        0
    
    # Test health check for specific resource
    run_unit_test "RDS health check" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --resource-type rds --health-check --dry-run" \
        0
    
    run_unit_test "Lambda health check" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --resource-type lambda --health-check --dry-run" \
        0
}

# Test output formats
test_output_formats() {
    log_info "=== Test Output Formats ==="
    
    # Test JSON output
    run_unit_test "JSON output format" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --output-format json --dry-run" \
        0
    
    # Test table output
    run_unit_test "Table output format" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --output-format table --dry-run" \
        0
    
    # Test CSV output
    run_unit_test "CSV output format" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --output-format csv --dry-run" \
        0
    
    # Test invalid output format
    run_unit_test "Invalid output format" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --output-format invalid --dry-run" \
        1
}

# Test verbose and logging options
test_logging_options() {
    log_info "=== Test Logging Options ==="
    
    # Test verbose mode
    run_unit_test "Verbose mode" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --verbose --dry-run" \
        0
    
    # Test quiet mode
    run_unit_test "Quiet mode" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --quiet --dry-run" \
        0
    
    # Test debug log level
    run_unit_test "Debug log level" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --log-level DEBUG --dry-run" \
        0
    
    # Test error log level
    run_unit_test "Error log level" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --log-level ERROR --dry-run" \
        0
    
    # Test log to file
    run_unit_test "Log to file" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name test-project --log-file /tmp/infra-check.log --dry-run" \
        0
}

# Test argument validation
test_argument_validation() {
    log_info "=== Test Argument Validation ==="
    
    # Test unknown arguments
    run_unit_test "Unknown argument" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --unknown-arg value --project-name test-project --dry-run" \
        1
    
    # Test empty project name
    run_unit_test "Empty project name" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name '' --dry-run" \
        1
    
    # Test invalid characters in project name
    run_unit_test "Invalid characters in project name" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name 'test project with spaces' --dry-run" \
        1
    
    # Test project name too long
    run_unit_test "Project name too long" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name 'very-long-project-name-that-exceeds-aws-limits-and-should-be-rejected-by-validation' --dry-run" \
        1
    
    # Test valid project name formats
    run_unit_test "Valid project name with hyphens" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name 'test-project-name' --dry-run" \
        0
    
    run_unit_test "Valid project name with numbers" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --project-name 'test-project-123' --dry-run" \
        0
}

# Test configuration file support
test_configuration_support() {
    log_info "=== Test Configuration File Support ==="
    
    # Create temporary config file
    local temp_config="/tmp/infra-check-config-test.json"
    cat > "$temp_config" << EOF
{
    "ProjectName": "test-project",
    "Environment": "development",
    "Region": "ap-southeast-1",
    "ResourceTypes": ["rds", "lambda"],
    "HealthCheck": true,
    "OutputFormat": "json"
}
EOF
    
    # Test config file loading
    run_unit_test "Config file loading" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --config-file '$temp_config' --dry-run" \
        0
    
    # Test invalid config file
    run_unit_test "Invalid config file path" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --config-file '/nonexistent/config.json' --dry-run" \
        1
    
    # Test malformed config file
    echo "invalid json" > "$temp_config"
    run_unit_test "Malformed config file" \
        "$SCRIPT_DIR/utilities/check-infrastructure.sh --config-file '$temp_config' --dry-run" \
        1
    
    # Cleanup
    rm -f "$temp_config"
}

# Generate test report
generate_test_report() {
    local report_file="./test-infrastructure-detection-report.md"
    
    log_info "Tạo báo cáo test: $report_file"
    
    cat > "$report_file" << EOF
# Báo Cáo Unit Test - Infrastructure Detection

**Ngày test:** $(date -u +%Y-%m-%dT%H:%M:%SZ)  
**Task:** 7.3 Write unit tests for infrastructure detection  
**Requirements:** 3.3  

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

### 1. Basic Infrastructure Detection
- Test basic detection functionality
- Command line argument parsing
- Dry run mode validation

### 2. Resource Detection
- Test detection của các AWS resources
- RDS, Lambda, VPC, IAM detection
- Resource type validation

### 3. Missing Resources Detection
- Test detection của resources không tồn tại
- Non-existent project handling
- Invalid credentials handling

### 4. AWS API Error Handling
- Test error handling cho AWS API failures
- Network timeout scenarios
- Permission denied handling
- Invalid credentials và profiles

### 5. Infrastructure Health Checking
- Test health check functionality
- Detailed health check modes
- Resource-specific health checks

### 6. Output Formats
- Test các output formats khác nhau
- JSON, Table, CSV formats
- Format validation

### 7. Logging Options
- Test verbose và quiet modes
- Log level configurations
- Log file output

### 8. Argument Validation
- Test argument validation logic
- Project name validation
- Invalid argument handling

### 9. Configuration Support
- Test config file loading
- JSON configuration parsing
- Configuration validation

## Kết Luận

EOF
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo "✅ Tất cả unit tests đều PASS! Infrastructure detection hoạt động chính xác." >> "$report_file"
    else
        echo "❌ Có $TESTS_FAILED test(s) FAIL. Cần sửa lỗi infrastructure detection." >> "$report_file"
    fi
    
    log_success "Báo cáo test được tạo: $report_file"
}

# Main execution function
main() {
    log_info "Bắt đầu Unit Tests cho Infrastructure Detection"
    
    # Set log level
    set_log_level "$TEST_LOG_LEVEL"
    
    # Run all test suites
    test_basic_infrastructure_detection
    test_resource_detection
    test_missing_resources_detection
    test_aws_api_error_handling
    test_infrastructure_health_checking
    test_output_formats
    test_logging_options
    test_argument_validation
    test_configuration_support
    
    # Generate test report
    generate_test_report
    
    # Final summary
    echo ""
    echo "========================================"
    echo "Tóm Tắt Unit Test - Infrastructure Detection"
    echo "========================================"
    echo "Tổng tests: $((TESTS_PASSED + TESTS_FAILED))"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "🎉 Tất cả unit tests PASS! Infrastructure detection hoạt động tốt."
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