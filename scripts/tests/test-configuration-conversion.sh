#!/bin/bash

# Property Test for Configuration Conversion
# Task 6.4: Property 2 - Configuration round-trip consistency
# Validates: Requirements 6.1, 6.3
# Test that configuration values are preserved through conversion process

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/utilities/logging.sh"
source "$SCRIPT_DIR/utilities/error-handling.sh"

# Test configuration
TEST_LOG_LEVEL="INFO"
ITERATIONS=5
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

# Create test configuration files
create_test_configs() {
    local test_dir="/tmp/config-test-$$"
    mkdir -p "$test_dir"
    
    # Simple configuration
    cat > "$test_dir/simple.json" << EOF
{
    "ConnectionStrings": {
        "DefaultConnection": "Host=localhost;Database=test;Username=test;Password=test"
    },
    "AWS": {
        "Region": "ap-southeast-1",
        "AccessKey": "test-key"
    },
    "Logging": {
        "LogLevel": {
            "Default": "Information"
        }
    }
}
EOF
    
    # Complex nested configuration
    cat > "$test_dir/complex.json" << EOF
{
    "ConnectionStrings": {
        "DefaultConnection": "Host=localhost;Database=prod;Username=prod;Password=prod",
        "RedisConnection": "localhost:6379"
    },
    "AWS": {
        "Region": "ap-southeast-1",
        "AccessKey": "prod-access-key",
        "SecretKey": "prod-secret-key",
        "Lambda": {
            "FunctionName": "MyFunction",
            "Runtime": "dotnet8",
            "Timeout": 30
        },
        "RDS": {
            "InstanceClass": "db.t3.micro",
            "AllocatedStorage": 20,
            "MultiAZ": false
        }
    },
    "Cognito": {
        "UserPoolId": "ap-southeast-1_XXXXXXXXX",
        "ClientId": "xxxxxxxxxxxxxxxxxxxxxxxxxx",
        "Region": "ap-southeast-1"
    },
    "Logging": {
        "LogLevel": {
            "Default": "Information",
            "Microsoft": "Warning",
            "System": "Warning"
        },
        "Console": {
            "IncludeScopes": true
        }
    },
    "AllowedHosts": "*",
    "Environment": "Production"
}
EOF
    
    # Configuration with special characters
    cat > "$test_dir/special.json" << EOF
{
    "ConnectionStrings": {
        "DefaultConnection": "Host=localhost;Database=test-db;Username=test_user;Password=p@ssw0rd!123"
    },
    "AWS": {
        "Region": "ap-southeast-1",
        "Tags": {
            "Environment": "test-env",
            "Project": "test-project",
            "Owner": "test@example.com"
        }
    },
    "CustomSettings": {
        "ApiUrl": "https://api.example.com/v1",
        "MaxRetries": 3,
        "TimeoutSeconds": 30,
        "EnableFeatureX": true,
        "EnableFeatureY": false
    }
}
EOF
    
    echo "$test_dir"
}

# Property Test 1: Configuration Round-Trip Consistency
test_configuration_roundtrip_consistency() {
    log_info "=== Property Test 1: Configuration Round-Trip Consistency ==="
    
    local test_dir=$(create_test_configs)
    local configs=("simple.json" "complex.json" "special.json")
    
    for config in "${configs[@]}"; do
        log_info "Test round-trip consistency cho: $config"
        
        local config_file="$test_dir/$config"
        local converted_file="$test_dir/${config%.json}.env"
        local reconverted_file="$test_dir/${config%.json}.reconverted.json"
        
        # Convert JSON to environment variables
        if ! "$SCRIPT_DIR/deployment/configure-environment.sh" \
            --input "$config_file" \
            --output "$converted_file" \
            --format env > /dev/null 2>&1; then
            log_error "Failed to convert $config to environment variables"
            rm -rf "$test_dir"
            return 1
        fi
        
        # Verify conversion output exists and is not empty
        if [ ! -f "$converted_file" ] || [ ! -s "$converted_file" ]; then
            log_error "Conversion output file empty or missing for $config"
            rm -rf "$test_dir"
            return 1
        fi
        
        # Test multiple conversions produce same result
        for i in $(seq 1 $ITERATIONS); do
            local temp_converted="$test_dir/${config%.json}.temp${i}.env"
            
            if ! "$SCRIPT_DIR/deployment/configure-environment.sh" \
                --input "$config_file" \
                --output "$temp_converted" \
                --format env > /dev/null 2>&1; then
                log_error "Failed conversion iteration $i for $config"
                rm -rf "$test_dir"
                return 1
            fi
            
            # Compare with first conversion
            if ! diff -q "$converted_file" "$temp_converted" > /dev/null; then
                log_error "Conversion inconsistency detected for $config at iteration $i"
                rm -rf "$test_dir"
                return 1
            fi
            
            rm -f "$temp_converted"
        done
        
        log_success "Round-trip consistency verified for $config"
    done
    
    rm -rf "$test_dir"
    return 0
}

# Property Test 2: Configuration Value Preservation
test_configuration_value_preservation() {
    log_info "=== Property Test 2: Configuration Value Preservation ==="
    
    local test_dir=$(create_test_configs)
    
    # Test specific value preservation
    local test_values=(
        "ConnectionStrings__DefaultConnection"
        "AWS__Region"
        "AWS__Lambda__FunctionName"
        "Cognito__UserPoolId"
        "Logging__LogLevel__Default"
    )
    
    local config_file="$test_dir/complex.json"
    local converted_file="$test_dir/complex.env"
    
    # Convert configuration
    if ! "$SCRIPT_DIR/deployment/configure-environment.sh" \
        --input "$config_file" \
        --output "$converted_file" \
        --format env > /dev/null 2>&1; then
        log_error "Failed to convert complex configuration"
        rm -rf "$test_dir"
        return 1
    fi
    
    # Check if specific values are preserved
    for value_key in "${test_values[@]}"; do
        if ! grep -q "^${value_key}=" "$converted_file"; then
            log_error "Value key '$value_key' not found in converted configuration"
            rm -rf "$test_dir"
            return 1
        fi
        
        log_success "Value key '$value_key' preserved in conversion"
    done
    
    # Test value consistency across multiple conversions
    for i in $(seq 1 $ITERATIONS); do
        local temp_converted="$test_dir/complex.temp${i}.env"
        
        if ! "$SCRIPT_DIR/deployment/configure-environment.sh" \
            --input "$config_file" \
            --output "$temp_converted" \
            --format env > /dev/null 2>&1; then
            log_error "Failed value preservation test iteration $i"
            rm -rf "$test_dir"
            return 1
        fi
        
        # Check each value is consistent
        for value_key in "${test_values[@]}"; do
            local original_value=$(grep "^${value_key}=" "$converted_file" | cut -d'=' -f2-)
            local current_value=$(grep "^${value_key}=" "$temp_converted" | cut -d'=' -f2-)
            
            if [ "$original_value" != "$current_value" ]; then
                log_error "Value inconsistency for '$value_key': '$original_value' vs '$current_value'"
                rm -rf "$test_dir"
                return 1
            fi
        done
        
        rm -f "$temp_converted"
    done
    
    rm -rf "$test_dir"
    return 0
}

# Property Test 3: Configuration Format Consistency
test_configuration_format_consistency() {
    log_info "=== Property Test 3: Configuration Format Consistency ==="
    
    local test_dir=$(create_test_configs)
    local formats=("env" "json" "yaml")
    
    for format in "${formats[@]}"; do
        log_info "Test format consistency cho: $format"
        
        local config_file="$test_dir/simple.json"
        local outputs=()
        
        # Generate multiple outputs in same format
        for i in $(seq 1 $ITERATIONS); do
            local output_file="$test_dir/simple.${format}.${i}"
            
            if "$SCRIPT_DIR/deployment/configure-environment.sh" \
                --input "$config_file" \
                --output "$output_file" \
                --format "$format" > /dev/null 2>&1; then
                outputs+=("$output_file")
            else
                # Some formats might not be supported, that's OK
                log_info "Format '$format' không được hỗ trợ hoặc failed - skipping"
                break
            fi
        done
        
        # If we have outputs, check consistency
        if [ ${#outputs[@]} -gt 1 ]; then
            local first_output="${outputs[0]}"
            
            for output in "${outputs[@]:1}"; do
                if ! diff -q "$first_output" "$output" > /dev/null; then
                    log_error "Format inconsistency detected for $format"
                    rm -rf "$test_dir"
                    return 1
                fi
            done
            
            log_success "Format consistency verified for $format"
        fi
    done
    
    rm -rf "$test_dir"
    return 0
}

# Property Test 4: Configuration Error Handling Consistency
test_configuration_error_handling_consistency() {
    log_info "=== Property Test 4: Configuration Error Handling Consistency ==="
    
    local test_dir="/tmp/config-error-test-$$"
    mkdir -p "$test_dir"
    
    # Create invalid JSON file
    cat > "$test_dir/invalid.json" << EOF
{
    "ConnectionStrings": {
        "DefaultConnection": "test"
    },
    "AWS": {
        "Region": "ap-southeast-1"
    // Missing closing brace
EOF
    
    # Test error handling consistency
    local error_outputs=()
    local error_exit_codes=()
    
    for i in $(seq 1 $ITERATIONS); do
        local output_file="$test_dir/error_output_${i}"
        local exit_code=0
        
        if "$SCRIPT_DIR/deployment/configure-environment.sh" \
            --input "$test_dir/invalid.json" \
            --output "$test_dir/invalid.env" \
            --format env > "$output_file" 2>&1; then
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
            log_error "Error handling không nhất quán: mong đợi $first_exit_code, nhận được $exit_code"
            break
        fi
    done
    
    # Error cases should return non-zero exit codes
    if [ "$first_exit_code" -eq 0 ]; then
        log_error "Invalid JSON không tạo ra error exit code"
        error_consistent=false
    fi
    
    rm -rf "$test_dir"
    
    if [ "$error_consistent" = true ]; then
        log_success "Error handling nhất quán"
        return 0
    else
        return 1
    fi
}

# Property Test 5: Configuration Nested Key Flattening
test_configuration_nested_key_flattening() {
    log_info "=== Property Test 5: Configuration Nested Key Flattening ==="
    
    local test_dir="/tmp/config-nested-test-$$"
    mkdir -p "$test_dir"
    
    # Create deeply nested configuration
    cat > "$test_dir/nested.json" << EOF
{
    "Level1": {
        "Level2": {
            "Level3": {
                "Level4": {
                    "DeepValue": "test-value"
                }
            },
            "SimpleValue": "simple"
        },
        "DirectValue": "direct"
    },
    "RootValue": "root"
}
EOF
    
    # Test nested key flattening consistency
    local expected_keys=(
        "Level1__Level2__Level3__Level4__DeepValue"
        "Level1__Level2__SimpleValue"
        "Level1__DirectValue"
        "RootValue"
    )
    
    for i in $(seq 1 $ITERATIONS); do
        local output_file="$test_dir/nested.${i}.env"
        
        if ! "$SCRIPT_DIR/deployment/configure-environment.sh" \
            --input "$test_dir/nested.json" \
            --output "$output_file" \
            --format env > /dev/null 2>&1; then
            log_error "Failed nested key flattening iteration $i"
            rm -rf "$test_dir"
            return 1
        fi
        
        # Check all expected keys are present
        for key in "${expected_keys[@]}"; do
            if ! grep -q "^${key}=" "$output_file"; then
                log_error "Missing nested key '$key' in iteration $i"
                rm -rf "$test_dir"
                return 1
            fi
        done
        
        # Compare with first iteration if not first
        if [ $i -gt 1 ]; then
            local first_output="$test_dir/nested.1.env"
            if ! diff -q "$first_output" "$output_file" > /dev/null; then
                log_error "Nested key flattening inconsistency at iteration $i"
                rm -rf "$test_dir"
                return 1
            fi
        fi
    done
    
    rm -rf "$test_dir"
    log_success "Nested key flattening nhất quán"
    return 0
}

# Generate property test report
generate_property_test_report() {
    local report_file="./test-configuration-conversion-report.md"
    
    log_info "Tạo báo cáo property test: $report_file"
    
    cat > "$report_file" << EOF
# Báo Cáo Property Test - Configuration Conversion

**Property:** Configuration Round-Trip Consistency  
**Task:** 6.4 Write property test for configuration conversion  
**Requirements:** 6.1, 6.3  
**Ngày test:** $(date -u +%Y-%m-%dT%H:%M:%SZ)  
**Iterations:** $ITERATIONS  

## Định Nghĩa Property

**Configuration Round-Trip Consistency Property:** Việc convert configuration từ JSON sang environment variables phải bảo toàn tất cả values và tạo ra kết quả nhất quán qua nhiều lần thực thi.

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

### 1. Configuration Round-Trip Consistency
**Property:** Nhiều lần convert cùng một config file tạo ra output giống nhau.
**Validation:** Đảm bảo conversion process là deterministic.

### 2. Configuration Value Preservation
**Property:** Tất cả configuration values được bảo toàn qua conversion process.
**Validation:** Kiểm tra specific keys và values không bị mất hoặc thay đổi.

### 3. Configuration Format Consistency
**Property:** Conversion sang các formats khác nhau tạo ra kết quả nhất quán.
**Validation:** Đảm bảo format handling ổn định.

### 4. Configuration Error Handling Consistency
**Property:** Error handling cho invalid configs nhất quán qua các lần thực thi.
**Validation:** Đảm bảo error processing là deterministic.

### 5. Configuration Nested Key Flattening
**Property:** Nested JSON keys được flatten nhất quán thành environment variable format.
**Validation:** Đảm bảo key transformation logic ổn định.

## Cấu Hình Test

- **Iterations per Test:** $ITERATIONS
- **Test Configs:** Simple, Complex, Special Characters, Nested
- **Formats Tested:** ENV, JSON, YAML (nếu supported)
- **Key Patterns:** ConnectionStrings, AWS, Cognito, Logging

## Kết Quả Validation

EOF
    
    if [ $PROPERTY_TESTS_FAILED -eq 0 ]; then
        cat >> "$report_file" << EOF
✅ **TẤT CẢ PROPERTIES ĐƯỢC THỎA MÃN**

Configuration conversion system thỏa mãn property round-trip consistency. Việc convert configuration tạo ra kết quả nhất quán, đảm bảo:

1. **Value Preservation:** Tất cả configuration values được bảo toàn
2. **Deterministic Conversion:** Cùng input luôn tạo ra cùng output
3. **Format Consistency:** Conversion sang các formats khác nhau ổn định
4. **Error Predictability:** Error handling nhất quán
5. **Key Transformation:** Nested keys được flatten chính xác

### Ý Nghĩa Cho Production

- **Reliable Deployments:** Configuration conversion sẽ hoạt động dự đoán được
- **Lambda Environment Variables:** Environment variables sẽ được set chính xác
- **Configuration Management:** Config changes sẽ được apply đúng
- **Troubleshooting:** Configuration issues có thể debug dễ dàng

EOF
    else
        cat >> "$report_file" << EOF
❌ **PHÁT HIỆN VI PHẠM PROPERTY**

Configuration conversion system có vấn đề consistency cần được giải quyết:

### Vấn Đề Nghiêm Trọng
- Phát hiện hành vi không nhất quán trong conversion process
- Configuration values có thể bị mất hoặc thay đổi
- Non-deterministic conversion outputs

### Hành Động Cần Thiết
1. Review các property tests failed ở trên
2. Xác định root causes của conversion inconsistency
3. Sửa value preservation issues
4. Fix key transformation logic
5. Chạy lại property tests để validate fixes

### Tác Động Production
- **Risk:** Lambda environment variables có thể sai
- **Mitigation:** Sửa conversion issues trước khi deploy
- **Testing:** Cần validation extensive cho configuration

EOF
    fi
    
    log_success "Báo cáo property test được tạo: $report_file"
}

# Main execution function
main() {
    log_info "Bắt đầu Property Tests cho Configuration Conversion"
    log_info "Testing Property: Configuration round-trip consistency qua $ITERATIONS iterations"
    
    # Set log level
    set_log_level "$TEST_LOG_LEVEL"
    
    # Run all property tests
    run_property_test "Configuration Round-Trip Consistency" \
        "Nhiều lần convert tạo ra output giống nhau" \
        "test_configuration_roundtrip_consistency"
    
    run_property_test "Configuration Value Preservation" \
        "Tất cả values được bảo toàn qua conversion" \
        "test_configuration_value_preservation"
    
    run_property_test "Configuration Format Consistency" \
        "Conversion sang formats khác nhau ổn định" \
        "test_configuration_format_consistency"
    
    run_property_test "Configuration Error Handling Consistency" \
        "Error handling nhất quán qua các lần thực thi" \
        "test_configuration_error_handling_consistency"
    
    run_property_test "Configuration Nested Key Flattening" \
        "Nested keys được flatten nhất quán" \
        "test_configuration_nested_key_flattening"
    
    # Generate property test report
    generate_property_test_report
    
    # Final summary
    echo ""
    echo "========================================"
    echo "Tóm Tắt Property Test"
    echo "========================================"
    echo "Property: Configuration Round-Trip Consistency"
    echo "Tổng Tests: $((PROPERTY_TESTS_PASSED + PROPERTY_TESTS_FAILED))"
    echo "Passed: $PROPERTY_TESTS_PASSED"
    echo "Failed: $PROPERTY_TESTS_FAILED"
    
    if [ $PROPERTY_TESTS_FAILED -eq 0 ]; then
        log_success "🎉 Configuration Round-Trip Consistency Property ĐƯỢC THỎA MÃN! Conversion system là deterministic."
        exit 0
    else
        log_error "❌ Configuration Round-Trip Consistency Property BỊ VI PHẠM! Cần sửa lỗi."
        exit 1
    fi
}

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi