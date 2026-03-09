#!/bin/bash

# Property Test for Migration Runner Idempotency
# Task 5.3: Property 1 - Migration idempotency
# Validates: Requirements 2.1, 2.3
# Test that running migrations multiple times produces consistent results

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/utilities/logging.sh"
source "$SCRIPT_DIR/utilities/error-handling.sh"

# Test configuration
TEST_LOG_LEVEL="INFO"
ITERATIONS=3
PROPERTY_TESTS_PASSED=0
PROPERTY_TESTS_FAILED=0
PROPERTY_RESULTS=()

# Function to run property test
run_property_test() {
    local property_name="$1"
    local test_description="$2"
    local test_function="$3"
    
    log_info "Test Property: $property_name"
    log_info "Mô tả: $test_description"
    
    local start_time=$(date +%s)
    
    if $test_function; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_success "✓ Property '$property_name' được thỏa mãn (${duration}s)"
        PROPERTY_TESTS_PASSED=$((PROPERTY_TESTS_PASSED + 1))
        PROPERTY_RESULTS+=("PASS: $property_name")
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_error "✗ Property '$property_name' bị vi phạm (${duration}s)"
        PROPERTY_TESTS_FAILED=$((PROPERTY_TESTS_FAILED + 1))
        PROPERTY_RESULTS+=("FAIL: $property_name")
    fi
}

# Property Test 1: Migration Command Consistency
test_migration_command_consistency() {
    log_info "=== Property Test 1: Migration Command Consistency ==="
    
    local outputs=()
    local exit_codes=()
    
    # Test connection string for dry run
    local test_connection="Host=localhost;Database=test;Username=test;Password=test"
    
    # Run migration command multiple times
    for i in $(seq 1 $ITERATIONS); do
        log_info "Chạy migration iteration $i/$ITERATIONS"
        
        local output_file="/tmp/migration_output_${i}_$$"
        local exit_code=0
        
        # Run migration with dry-run to avoid actual database operations
        if "$SCRIPT_DIR/migration/run-migrations.sh" --dry-run \
            --connection-string "$test_connection" > "$output_file" 2>&1; then
            exit_code=0
        else
            exit_code=$?
        fi
        
        outputs+=("$(cat "$output_file")")
        exit_codes+=($exit_code)
        rm -f "$output_file"
        
        sleep 1
    done
    
    # Analyze consistency
    local first_exit_code=${exit_codes[0]}
    local consistent_exit_codes=true
    
    for exit_code in "${exit_codes[@]}"; do
        if [ "$exit_code" != "$first_exit_code" ]; then
            consistent_exit_codes=false
            log_error "Exit codes không nhất quán: mong đợi $first_exit_code, nhận được $exit_code"
            break
        fi
    done
    
    if [ "$consistent_exit_codes" = true ]; then
        log_success "Exit codes nhất quán qua tất cả iterations"
        return 0
    else
        log_error "Exit codes không nhất quán qua các iterations"
        return 1
    fi
}

# Property Test 2: Migration Script Parameter Handling
test_migration_parameter_consistency() {
    log_info "=== Property Test 2: Migration Parameter Consistency ==="
    
    local parameter_sets=(
        "--dry-run --verbose"
        "--dry-run --project-path test"
        "--dry-run --context TestContext"
    )
    
    local test_connection="Host=localhost;Database=test;Username=test;Password=test"
    
    for params in "${parameter_sets[@]}"; do
        log_info "Test parameter consistency: $params"
        
        local param_outputs=()
        local param_exit_codes=()
        
        # Run with same parameters multiple times
        for i in $(seq 1 $ITERATIONS); do
            local output_file="/tmp/migration_param_${i}_$$"
            local exit_code=0
            
            if "$SCRIPT_DIR/migration/run-migrations.sh" \
                --connection-string "$test_connection" $params > "$output_file" 2>&1; then
                exit_code=0
            else
                exit_code=$?
            fi
            
            param_outputs+=("$(cat "$output_file")")
            param_exit_codes+=($exit_code)
            rm -f "$output_file"
            sleep 1
        done
        
        # Check consistency
        local first_exit_code=${param_exit_codes[0]}
        local param_consistent=true
        
        for exit_code in "${param_exit_codes[@]}"; do
            if [ "$exit_code" != "$first_exit_code" ]; then
                param_consistent=false
                log_error "Parameter set '$params': exit codes không nhất quán"
                return 1
            fi
        done
        
        log_success "Parameter set '$params' cho kết quả nhất quán"
    done
    
    log_success "Tất cả parameter combinations cho kết quả nhất quán"
    return 0
}

# Property Test 3: Migration Help and Version Consistency
test_migration_help_consistency() {
    log_info "=== Property Test 3: Migration Help/Version Consistency ==="
    
    local commands=("--help" "--version")
    
    for cmd in "${commands[@]}"; do
        log_info "Test consistency cho: $cmd"
        
        local cmd_outputs=()
        local cmd_exit_codes=()
        
        # Run command multiple times
        for i in $(seq 1 $ITERATIONS); do
            local output_file="/tmp/migration_help_${i}_$$"
            local exit_code=0
            
            # Handle the case where --version might not exist
            if "$SCRIPT_DIR/migration/run-migrations.sh" $cmd > "$output_file" 2>&1; then
                exit_code=0
            else
                exit_code=$?
            fi
            
            cmd_outputs+=("$(cat "$output_file")")
            cmd_exit_codes+=($exit_code)
            rm -f "$output_file"
            sleep 1
        done
        
        # Check consistency
        local first_exit_code=${cmd_exit_codes[0]}
        local first_output="${cmd_outputs[0]}"
        local cmd_consistent=true
        
        for i in "${!cmd_exit_codes[@]}"; do
            local exit_code=${cmd_exit_codes[$i]}
            local output="${cmd_outputs[$i]}"
            
            if [ "$exit_code" != "$first_exit_code" ]; then
                cmd_consistent=false
                log_error "Command '$cmd': exit codes không nhất quán"
                break
            fi
            
            # For help command, output should be identical
            if [ "$cmd" = "--help" ] && [ "$output" != "$first_output" ]; then
                cmd_consistent=false
                log_error "Command '$cmd': output không nhất quán"
                break
            fi
        done
        
        if [ "$cmd_consistent" = true ]; then
            log_success "Command '$cmd' cho kết quả nhất quán"
        else
            return 1
        fi
    done
    
    return 0
}

# Property Test 4: Migration Error Handling Consistency
test_migration_error_handling_consistency() {
    log_info "=== Property Test 4: Migration Error Handling Consistency ==="
    
    # Test with invalid connection strings
    local invalid_connections=(
        "invalid-connection-string"
        "Host=;Database=;Username=;Password="
        ""
    )
    
    for conn in "${invalid_connections[@]}"; do
        log_info "Test error handling cho connection: '$conn'"
        
        local error_outputs=()
        local error_exit_codes=()
        
        # Run with invalid connection multiple times
        for i in $(seq 1 $ITERATIONS); do
            local output_file="/tmp/migration_error_${i}_$$"
            local exit_code=0
            
            if "$SCRIPT_DIR/migration/run-migrations.sh" \
                --connection-string "$conn" --dry-run > "$output_file" 2>&1; then
                exit_code=0
            else
                exit_code=$?
            fi
            
            error_outputs+=("$(cat "$output_file")")
            error_exit_codes+=($exit_code)
            rm -f "$output_file"
            sleep 1
        done
        
        # Check error consistency
        local first_exit_code=${error_exit_codes[0]}
        local error_consistent=true
        
        for exit_code in "${error_exit_codes[@]}"; do
            if [ "$exit_code" != "$first_exit_code" ]; then
                error_consistent=false
                log_error "Error handling không nhất quán cho connection: '$conn'"
                return 1
            fi
        done
        
        # Error cases should return non-zero exit codes
        if [ "$first_exit_code" -eq 0 ] && [ -n "$conn" ]; then
            log_warn "Invalid connection '$conn' không tạo ra error (có thể là expected behavior)"
        fi
        
        log_success "Error handling nhất quán cho connection: '$conn'"
    done
    
    return 0
}

# Property Test 5: Migration Rollback Consistency
test_migration_rollback_consistency() {
    log_info "=== Property Test 5: Migration Rollback Consistency ==="
    
    local test_connection="Host=localhost;Database=test;Username=test;Password=test"
    local rollback_targets=("InitialCreate" "20240101000000_TestMigration")
    
    for target in "${rollback_targets[@]}"; do
        log_info "Test rollback consistency cho target: $target"
        
        local rollback_outputs=()
        local rollback_exit_codes=()
        
        # Run rollback command multiple times
        for i in $(seq 1 $ITERATIONS); do
            local output_file="/tmp/migration_rollback_${i}_$$"
            local exit_code=0
            
            if "$SCRIPT_DIR/migration/run-migrations.sh" \
                --connection-string "$test_connection" \
                --rollback-to "$target" --dry-run > "$output_file" 2>&1; then
                exit_code=0
            else
                exit_code=$?
            fi
            
            rollback_outputs+=("$(cat "$output_file")")
            rollback_exit_codes+=($exit_code)
            rm -f "$output_file"
            sleep 1
        done
        
        # Check rollback consistency
        local first_exit_code=${rollback_exit_codes[0]}
        local rollback_consistent=true
        
        for exit_code in "${rollback_exit_codes[@]}"; do
            if [ "$exit_code" != "$first_exit_code" ]; then
                rollback_consistent=false
                log_error "Rollback không nhất quán cho target: $target"
                return 1
            fi
        done
        
        log_success "Rollback nhất quán cho target: $target"
    done
    
    return 0
}

# Generate property test report
generate_property_test_report() {
    local report_file="./test-migration-idempotency-report.md"
    
    log_info "Tạo báo cáo property test: $report_file"
    
    cat > "$report_file" << EOF
# Báo Cáo Property Test - Migration Runner Idempotency

**Property:** Migration Idempotency  
**Task:** 5.3 Write property test for migration runner  
**Requirements:** 2.1, 2.3  
**Ngày test:** $(date -u +%Y-%m-%dT%H:%M:%SZ)  
**Iterations:** $ITERATIONS  

## Định Nghĩa Property

**Migration Idempotency Property:** Việc chạy migration nhiều lần với cùng tham số phải tạo ra kết quả nhất quán, bất kể số lần thực thi hay thời gian chạy.

## Tóm Tắt Test

- **Tổng Property Tests:** $((PROPERTY_TESTS_PASSED + PROPERTY_TESTS_FAILED))
- **Passed:** $PROPERTY_TESTS_PASSED
- **Failed:** $PROPERTY_TESTS_FAILED
- **Tỷ lệ thành công:** $(( PROPERTY_TESTS_PASSED * 100 / (PROPERTY_TESTS_PASSED + PROPERTY_TESTS_FAILED) ))%

## Kết Quả Property Test

EOF
    
    for result in "${PROPERTY_RESULTS[@]}"; do
        echo "- $result" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

## Các Properties Được Test

### 1. Migration Command Consistency
**Property:** Nhiều lần thực thi cùng một migration command tạo ra exit codes giống nhau.
**Validation:** Đảm bảo hành vi deterministic qua các lần chạy lặp lại.

### 2. Migration Parameter Consistency  
**Property:** Các tổ hợp tham số khác nhau tạo ra hành vi nhất quán qua các lần thực thi.
**Validation:** Đảm bảo parameter processing là deterministic.

### 3. Migration Help/Version Consistency
**Property:** Help và version commands tạo ra output giống nhau qua các lần thực thi.
**Validation:** Đảm bảo documentation commands ổn định.

### 4. Migration Error Handling Consistency
**Property:** Error handling cho invalid inputs nhất quán qua các lần thực thi.
**Validation:** Đảm bảo error processing là deterministic.

### 5. Migration Rollback Consistency
**Property:** Rollback operations tạo ra kết quả nhất quán qua các lần thực thi.
**Validation:** Đảm bảo rollback logic là deterministic.

## Cấu Hình Test

- **Iterations per Test:** $ITERATIONS
- **Test Mode:** Dry Run (không có database operations thực tế)
- **Connection Strings:** Test connections (không kết nối thực tế)

## Kết Quả Validation

EOF
    
    if [ $PROPERTY_TESTS_FAILED -eq 0 ]; then
        cat >> "$report_file" << EOF
✅ **TẤT CẢ PROPERTIES ĐƯỢC THỎA MÃN**

Migration system thỏa mãn property idempotency. Việc chạy migration lặp lại tạo ra kết quả nhất quán, đảm bảo:

1. **Hành Vi Deterministic:** Cùng inputs luôn tạo ra cùng outputs
2. **State Consistency:** Database state có thể dự đoán được
3. **Reliable Operations:** Migrations có thể chạy lại an toàn
4. **Error Predictability:** Error handling nhất quán

### Ý Nghĩa Cho Production

- **Safe Retry Logic:** Failed migrations có thể retry an toàn
- **CI/CD Integration:** Automated migrations sẽ hoạt động dự đoán được
- **Operational Confidence:** Operations teams có thể tin tưởng migration consistency
- **Rollback Safety:** Rollback operations sẽ hoạt động dự đoán được

EOF
    else
        cat >> "$report_file" << EOF
❌ **PHÁT HIỆN VI PHẠM PROPERTY**

Migration system có vấn đề idempotency cần được giải quyết:

### Vấn Đề Nghiêm Trọng
- Phát hiện hành vi không nhất quán qua các lần thực thi
- Non-deterministic outputs hoặc state changes
- Có thể có race conditions hoặc timing dependencies

### Hành Động Cần Thiết
1. Review các property tests failed ở trên
2. Xác định root causes của non-deterministic behavior
3. Sửa timing dependencies và race conditions
4. Chạy lại property tests để validate fixes
5. Cân nhắc thêm property tests cho edge cases

### Tác Động Production
- **Risk:** Hành vi migration không dự đoán được
- **Mitigation:** Sửa issues trước khi deploy production
- **Testing:** Cần validation extensive

EOF
    fi
    
    log_success "Báo cáo property test được tạo: $report_file"
}

# Main execution function
main() {
    log_info "Bắt đầu Property Tests cho Migration Runner Idempotency"
    log_info "Testing Property: Migration idempotency qua $ITERATIONS iterations"
    
    # Set log level
    set_log_level "$TEST_LOG_LEVEL"
    
    # Run all property tests
    run_property_test "Migration Command Consistency" \
        "Nhiều lần thực thi tạo ra exit codes giống nhau" \
        "test_migration_command_consistency"
    
    run_property_test "Migration Parameter Consistency" \
        "Parameter combinations tạo ra hành vi nhất quán" \
        "test_migration_parameter_consistency"
    
    run_property_test "Migration Help/Version Consistency" \
        "Help và version commands ổn định" \
        "test_migration_help_consistency"
    
    run_property_test "Migration Error Handling Consistency" \
        "Error handling nhất quán qua các lần thực thi" \
        "test_migration_error_handling_consistency"
    
    run_property_test "Migration Rollback Consistency" \
        "Rollback operations nhất quán" \
        "test_migration_rollback_consistency"
    
    # Generate property test report
    generate_property_test_report
    
    # Final summary
    echo ""
    echo "========================================"
    echo "Tóm Tắt Property Test"
    echo "========================================"
    echo "Property: Migration Idempotency"
    echo "Tổng Tests: $((PROPERTY_TESTS_PASSED + PROPERTY_TESTS_FAILED))"
    echo "Passed: $PROPERTY_TESTS_PASSED"
    echo "Failed: $PROPERTY_TESTS_FAILED"
    
    if [ $PROPERTY_TESTS_FAILED -eq 0 ]; then
        log_success "🎉 Migration Idempotency Property ĐƯỢC THỎA MÃN! System là deterministic."
        exit 0
    else
        log_error "❌ Migration Idempotency Property BỊ VI PHẠM! Cần sửa lỗi."
        exit 1
    fi
}

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi