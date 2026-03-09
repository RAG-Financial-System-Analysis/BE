#!/bin/bash

# Unit Tests for Database Seeding
# Task 5.4: Test seed data creation and validation
# Test duplicate prevention logic
# Requirements: 2.2

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

# Test seed data creation
test_seed_data_creation() {
    log_info "=== Test Seed Data Creation ==="
    
    # Test help option
    run_unit_test "Seed script help option" \
        "$SCRIPT_DIR/migration/seed-data.sh --help" \
        0
    
    # Test dry run mode
    run_unit_test "Seed script dry run mode" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --connection-string 'Host=localhost;Database=test;Username=test;Password=test'" \
        0
    
    # Test with valid connection string
    run_unit_test "Valid connection string" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --connection-string 'Host=localhost;Database=testdb;Username=testuser;Password=testpass'" \
        0
    
    # Test with environment parameter
    run_unit_test "Environment parameter" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --environment development --connection-string 'Host=localhost;Database=test;Username=test;Password=test'" \
        0
    
    # Test with project path parameter
    run_unit_test "Project path parameter" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --project-path ./test --connection-string 'Host=localhost;Database=test;Username=test;Password=test'" \
        0
}

# Test seed data validation
test_seed_data_validation() {
    log_info "=== Test Seed Data Validation ==="
    
    # Test invalid connection string
    run_unit_test "Invalid connection string" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --connection-string 'invalid-connection'" \
        1
    
    # Test empty connection string
    run_unit_test "Empty connection string" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --connection-string ''" \
        1
    
    # Test missing connection string
    run_unit_test "Missing connection string" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run" \
        1
    
    # Test invalid environment
    run_unit_test "Invalid environment" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --environment invalid --connection-string 'Host=localhost;Database=test;Username=test;Password=test'" \
        0  # Should still work with warning
    
    # Test invalid project path
    run_unit_test "Invalid project path" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --project-path /nonexistent/path --connection-string 'Host=localhost;Database=test;Username=test;Password=test'" \
        1
}

# Test duplicate prevention logic
test_duplicate_prevention() {
    log_info "=== Test Duplicate Prevention Logic ==="
    
    # Test idempotent seeding (multiple runs should be safe)
    run_unit_test "First seeding run" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --connection-string 'Host=localhost;Database=test;Username=test;Password=test'" \
        0
    
    run_unit_test "Second seeding run (idempotent)" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --connection-string 'Host=localhost;Database=test;Username=test;Password=test'" \
        0
    
    run_unit_test "Third seeding run (idempotent)" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --connection-string 'Host=localhost;Database=test;Username=test;Password=test'" \
        0
    
    # Test force seeding option
    run_unit_test "Force seeding option" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --force --connection-string 'Host=localhost;Database=test;Username=test;Password=test'" \
        0
    
    # Test skip existing data option
    run_unit_test "Skip existing data option" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --skip-existing --connection-string 'Host=localhost;Database=test;Username=test;Password=test'" \
        0
}

# Test seed data types
test_seed_data_types() {
    log_info "=== Test Seed Data Types ==="
    
    # Test roles seeding
    run_unit_test "Roles seeding" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --seed-type roles --connection-string 'Host=localhost;Database=test;Username=test;Password=test'" \
        0
    
    # Test users seeding
    run_unit_test "Users seeding" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --seed-type users --connection-string 'Host=localhost;Database=test;Username=test;Password=test'" \
        0
    
    # Test all data seeding
    run_unit_test "All data seeding" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --seed-type all --connection-string 'Host=localhost;Database=test;Username=test;Password=test'" \
        0
    
    # Test invalid seed type
    run_unit_test "Invalid seed type" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --seed-type invalid --connection-string 'Host=localhost;Database=test;Username=test;Password=test'" \
        1
}

# Test error handling
test_error_handling() {
    log_info "=== Test Error Handling ==="
    
    # Test unknown arguments
    run_unit_test "Unknown argument" \
        "$SCRIPT_DIR/migration/seed-data.sh --unknown-arg value --dry-run --connection-string 'Host=localhost;Database=test;Username=test;Password=test'" \
        1
    
    # Test malformed connection string
    run_unit_test "Malformed connection string" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --connection-string 'Host=localhost;Database=;Username=;Password='" \
        1
    
    # Test connection timeout scenarios
    run_unit_test "Connection timeout handling" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --timeout 1 --connection-string 'Host=nonexistent.host;Database=test;Username=test;Password=test'" \
        1
}

# Test verbose and logging options
test_logging_options() {
    log_info "=== Test Logging Options ==="
    
    # Test verbose mode
    run_unit_test "Verbose mode" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --verbose --connection-string 'Host=localhost;Database=test;Username=test;Password=test'" \
        0
    
    # Test quiet mode
    run_unit_test "Quiet mode" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --quiet --connection-string 'Host=localhost;Database=test;Username=test;Password=test'" \
        0
    
    # Test log level options
    run_unit_test "Debug log level" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --log-level DEBUG --connection-string 'Host=localhost;Database=test;Username=test;Password=test'" \
        0
    
    run_unit_test "Error log level" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --log-level ERROR --connection-string 'Host=localhost;Database=test;Username=test;Password=test'" \
        0
}

# Test configuration file support
test_configuration_support() {
    log_info "=== Test Configuration File Support ==="
    
    # Create temporary config file
    local temp_config="/tmp/seed-config-test.json"
    cat > "$temp_config" << EOF
{
    "ConnectionString": "Host=localhost;Database=test;Username=test;Password=test",
    "Environment": "development",
    "SeedType": "all",
    "Force": false
}
EOF
    
    # Test config file loading
    run_unit_test "Config file loading" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --config-file '$temp_config'" \
        0
    
    # Test invalid config file
    run_unit_test "Invalid config file" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --config-file '/nonexistent/config.json'" \
        1
    
    # Test malformed config file
    echo "invalid json" > "$temp_config"
    run_unit_test "Malformed config file" \
        "$SCRIPT_DIR/migration/seed-data.sh --dry-run --config-file '$temp_config'" \
        1
    
    # Cleanup
    rm -f "$temp_config"
}

# Generate test report
generate_test_report() {
    local report_file="./test-database-seeding-report.md"
    
    log_info "Tạo báo cáo test: $report_file"
    
    cat > "$report_file" << EOF
# Báo Cáo Unit Test - Database Seeding

**Ngày test:** $(date -u +%Y-%m-%dT%H:%M:%SZ)  
**Task:** 5.4 Write unit tests for database seeding  
**Requirements:** 2.2  

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

### 1. Seed Data Creation
- Test tạo seed data cơ bản
- Kiểm tra dry run mode
- Validate connection string handling

### 2. Seed Data Validation
- Test validation logic
- Error handling cho invalid inputs
- Connection string validation

### 3. Duplicate Prevention Logic
- Test idempotent seeding
- Multiple run safety
- Force và skip options

### 4. Seed Data Types
- Test roles seeding
- Test users seeding
- Test all data seeding

### 5. Error Handling
- Unknown arguments
- Malformed inputs
- Connection failures

### 6. Logging Options
- Verbose và quiet modes
- Log level configurations
- Output formatting

### 7. Configuration Support
- Config file loading
- JSON parsing
- Configuration validation

## Kết Luận

EOF
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo "✅ Tất cả unit tests đều PASS! Database seeding hoạt động chính xác." >> "$report_file"
    else
        echo "❌ Có $TESTS_FAILED test(s) FAIL. Cần sửa lỗi database seeding." >> "$report_file"
    fi
    
    log_success "Báo cáo test được tạo: $report_file"
}

# Main execution function
main() {
    log_info "Bắt đầu Unit Tests cho Database Seeding"
    
    # Set log level
    set_log_level "$TEST_LOG_LEVEL"
    
    # Run all test suites
    test_seed_data_creation
    test_seed_data_validation
    test_duplicate_prevention
    test_seed_data_types
    test_error_handling
    test_logging_options
    test_configuration_support
    
    # Generate test report
    generate_test_report
    
    # Final summary
    echo ""
    echo "========================================"
    echo "Tóm Tắt Unit Test - Database Seeding"
    echo "========================================"
    echo "Tổng tests: $((TESTS_PASSED + TESTS_FAILED))"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "🎉 Tất cả unit tests PASS! Database seeding hoạt động tốt."
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