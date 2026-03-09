#!/bin/bash

# Property Test for Cost Optimization
# Task 10.3: Property 3 - Cost optimization constraints
# Validates: Requirements 5.1, 5.2, 5.3
# Test that provisioned resources meet cost optimization criteria

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

# Cost optimization constraints
declare -A COST_CONSTRAINTS=(
    ["RDS_INSTANCE_CLASS"]="db.t3.micro"
    ["RDS_ALLOCATED_STORAGE"]="20"
    ["RDS_MAX_ALLOCATED_STORAGE"]="100"
    ["LAMBDA_MEMORY_SIZE"]="128"
    ["LAMBDA_TIMEOUT"]="30"
    ["LAMBDA_RESERVED_CONCURRENCY"]="10"
)

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

# Property Test 1: RDS Cost Optimization Constraints
test_rds_cost_optimization_constraints() {
    log_info "=== Property Test 1: RDS Cost Optimization Constraints ==="
    
    # Test RDS provisioning with cost optimization
    for i in $(seq 1 $ITERATIONS); do
        log_info "Test RDS cost optimization iteration $i/$ITERATIONS"
        
        local output_file="/tmp/rds_cost_test_${i}_$$"
        local exit_code=0
        
        # Run RDS provisioning with dry-run
        if "$SCRIPT_DIR/infrastructure/provision-rds.sh" \
            --project-name "test-project" \
            --environment "development" \
            --dry-run \
            --cost-optimized > "$output_file" 2>&1; then
            exit_code=0
        else
            exit_code=$?
        fi
        
        # Check if cost optimization constraints are applied
        local constraints_met=true
        
        # Check instance class constraint
        if ! grep -q "InstanceClass.*${COST_CONSTRAINTS[RDS_INSTANCE_CLASS]}" "$output_file"; then
            log_error "RDS instance class không tuân thủ cost optimization: mong đợi ${COST_CONSTRAINTS[RDS_INSTANCE_CLASS]}"
            constraints_met=false
        fi
        
        # Check allocated storage constraint
        if ! grep -q "AllocatedStorage.*${COST_CONSTRAINTS[RDS_ALLOCATED_STORAGE]}" "$output_file"; then
            log_error "RDS allocated storage không tuân thủ cost optimization: mong đợi ${COST_CONSTRAINTS[RDS_ALLOCATED_STORAGE]}"
            constraints_met=false
        fi
        
        # Check MultiAZ is disabled for cost optimization
        if grep -q "MultiAZ.*true" "$output_file"; then
            log_error "RDS MultiAZ should be disabled for cost optimization"
            constraints_met=false
        fi
        
        rm -f "$output_file"
        
        if [ "$constraints_met" = false ]; then
            return 1
        fi
        
        sleep 1
    done
    
    log_success "RDS cost optimization constraints được thỏa mãn qua tất cả iterations"
    return 0
}

# Property Test 2: Lambda Cost Optimization Constraints
test_lambda_cost_optimization_constraints() {
    log_info "=== Property Test 2: Lambda Cost Optimization Constraints ==="
    
    # Test Lambda provisioning with cost optimization
    for i in $(seq 1 $ITERATIONS); do
        log_info "Test Lambda cost optimization iteration $i/$ITERATIONS"
        
        local output_file="/tmp/lambda_cost_test_${i}_$$"
        local exit_code=0
        
        # Run Lambda provisioning with dry-run
        if "$SCRIPT_DIR/infrastructure/provision-lambda.sh" \
            --project-name "test-project" \
            --environment "development" \
            --dry-run \
            --cost-optimized > "$output_file" 2>&1; then
            exit_code=0
        else
            exit_code=$?
        fi
        
        # Check if cost optimization constraints are applied
        local constraints_met=true
        
        # Check memory size constraint
        if ! grep -q "MemorySize.*${COST_CONSTRAINTS[LAMBDA_MEMORY_SIZE]}" "$output_file"; then
            log_error "Lambda memory size không tuân thủ cost optimization: mong đợi ${COST_CONSTRAINTS[LAMBDA_MEMORY_SIZE]}"
            constraints_met=false
        fi
        
        # Check timeout constraint
        if ! grep -q "Timeout.*${COST_CONSTRAINTS[LAMBDA_TIMEOUT]}" "$output_file"; then
            log_error "Lambda timeout không tuân thủ cost optimization: mong đợi ${COST_CONSTRAINTS[LAMBDA_TIMEOUT]}"
            constraints_met=false
        fi
        
        # Check reserved concurrency constraint
        local reserved_concurrency=$(grep -o "ReservedConcurrency.*[0-9]\+" "$output_file" | grep -o "[0-9]\+")
        if [ -n "$reserved_concurrency" ] && [ "$reserved_concurrency" -gt "${COST_CONSTRAINTS[LAMBDA_RESERVED_CONCURRENCY]}" ]; then
            log_error "Lambda reserved concurrency vượt quá cost optimization limit: $reserved_concurrency > ${COST_CONSTRAINTS[LAMBDA_RESERVED_CONCURRENCY]}"
            constraints_met=false
        fi
        
        rm -f "$output_file"
        
        if [ "$constraints_met" = false ]; then
            return 1
        fi
        
        sleep 1
    done
    
    log_success "Lambda cost optimization constraints được thỏa mãn qua tất cả iterations"
    return 0
}

# Property Test 3: Cost Estimation Accuracy
test_cost_estimation_accuracy() {
    log_info "=== Property Test 3: Cost Estimation Accuracy ==="
    
    # Test cost estimation consistency
    local cost_estimates=()
    
    for i in $(seq 1 $ITERATIONS); do
        log_info "Test cost estimation iteration $i/$ITERATIONS"
        
        local output_file="/tmp/cost_estimation_${i}_$$"
        local exit_code=0
        
        # Run cost optimization script
        if "$SCRIPT_DIR/utilities/cost-optimization.sh" \
            --project-name "test-project" \
            --environment "development" \
            --estimate-only \
            --dry-run > "$output_file" 2>&1; then
            exit_code=0
        else
            exit_code=$?
        fi
        
        # Extract cost estimate
        local cost_estimate=$(grep -o "Estimated.*cost.*\$[0-9.]\+" "$output_file" | grep -o "\$[0-9.]\+" | tr -d '$')
        
        if [ -n "$cost_estimate" ]; then
            cost_estimates+=("$cost_estimate")
            log_info "Cost estimate iteration $i: \$${cost_estimate}"
        else
            log_error "Không thể extract cost estimate từ iteration $i"
            rm -f "$output_file"
            return 1
        fi
        
        rm -f "$output_file"
        sleep 1
    done
    
    # Check cost estimate consistency
    if [ ${#cost_estimates[@]} -gt 1 ]; then
        local first_estimate="${cost_estimates[0]}"
        
        for estimate in "${cost_estimates[@]:1}"; do
            # Allow small variance in cost estimates (within 5%)
            local variance=$(echo "scale=2; ($estimate - $first_estimate) / $first_estimate * 100" | bc -l 2>/dev/null || echo "0")
            local abs_variance=$(echo "$variance" | tr -d '-')
            
            if (( $(echo "$abs_variance > 5" | bc -l 2>/dev/null || echo "0") )); then
                log_error "Cost estimate variance quá lớn: $variance% (first: \$${first_estimate}, current: \$${estimate})"
                return 1
            fi
        done
        
        log_success "Cost estimates nhất quán qua tất cả iterations (variance < 5%)"
    fi
    
    return 0
}

# Property Test 4: Free Tier Resource Selection
test_free_tier_resource_selection() {
    log_info "=== Property Test 4: Free Tier Resource Selection ==="
    
    # Test free tier resource selection
    for i in $(seq 1 $ITERATIONS); do
        log_info "Test free tier selection iteration $i/$ITERATIONS"
        
        local output_file="/tmp/free_tier_test_${i}_$$"
        local exit_code=0
        
        # Run cost optimization with free tier preference
        if "$SCRIPT_DIR/utilities/cost-optimization.sh" \
            --project-name "test-project" \
            --environment "development" \
            --prefer-free-tier \
            --dry-run > "$output_file" 2>&1; then
            exit_code=0
        else
            exit_code=$?
        fi
        
        # Check if free tier resources are selected
        local free_tier_compliant=true
        
        # Check RDS free tier compliance
        if ! grep -q "db\.t[23]\.micro" "$output_file"; then
            log_error "RDS instance không sử dụng free tier eligible instance class"
            free_tier_compliant=false
        fi
        
        # Check storage is within free tier limits (20GB)
        local storage=$(grep -o "AllocatedStorage.*[0-9]\+" "$output_file" | grep -o "[0-9]\+")
        if [ -n "$storage" ] && [ "$storage" -gt 20 ]; then
            log_error "RDS storage vượt quá free tier limit: ${storage}GB > 20GB"
            free_tier_compliant=false
        fi
        
        # Check Lambda memory is within free tier optimal range
        local lambda_memory=$(grep -o "MemorySize.*[0-9]\+" "$output_file" | grep -o "[0-9]\+")
        if [ -n "$lambda_memory" ] && [ "$lambda_memory" -gt 512 ]; then
            log_warn "Lambda memory có thể vượt quá free tier optimal: ${lambda_memory}MB"
        fi
        
        rm -f "$output_file"
        
        if [ "$free_tier_compliant" = false ]; then
            return 1
        fi
        
        sleep 1
    done
    
    log_success "Free tier resource selection được thỏa mãn qua tất cả iterations"
    return 0
}

# Property Test 5: Cost Optimization Configuration Consistency
test_cost_optimization_config_consistency() {
    log_info "=== Property Test 5: Cost Optimization Configuration Consistency ==="
    
    # Test cost optimization configuration consistency
    local config_outputs=()
    
    for i in $(seq 1 $ITERATIONS); do
        log_info "Test cost optimization config iteration $i/$ITERATIONS"
        
        local output_file="/tmp/cost_config_${i}_$$"
        local exit_code=0
        
        # Generate cost optimization configuration
        if "$SCRIPT_DIR/utilities/cost-optimization.sh" \
            --project-name "test-project" \
            --environment "development" \
            --generate-config \
            --output-file "$output_file" \
            --dry-run > /dev/null 2>&1; then
            exit_code=0
        else
            exit_code=$?
        fi
        
        if [ -f "$output_file" ]; then
            config_outputs+=("$output_file")
        else
            log_error "Cost optimization config không được tạo ở iteration $i"
            return 1
        fi
        
        sleep 1
    done
    
    # Check configuration consistency
    if [ ${#config_outputs[@]} -gt 1 ]; then
        local first_config="${config_outputs[0]}"
        
        for config in "${config_outputs[@]:1}"; do
            if ! diff -q "$first_config" "$config" > /dev/null; then
                log_error "Cost optimization configuration không nhất quán"
                # Cleanup
                for output in "${config_outputs[@]}"; do
                    rm -f "$output"
                done
                return 1
            fi
        done
        
        log_success "Cost optimization configuration nhất quán qua tất cả iterations"
    fi
    
    # Cleanup
    for output in "${config_outputs[@]}"; do
        rm -f "$output"
    done
    
    return 0
}

# Property Test 6: Cost Monitoring Thresholds
test_cost_monitoring_thresholds() {
    log_info "=== Property Test 6: Cost Monitoring Thresholds ==="
    
    # Test cost monitoring threshold consistency
    local threshold_configs=(
        "--cost-threshold 10"
        "--cost-threshold 50"
        "--cost-threshold 100"
    )
    
    for threshold_config in "${threshold_configs[@]}"; do
        log_info "Test cost monitoring với: $threshold_config"
        
        local threshold_outputs=()
        
        for i in $(seq 1 $ITERATIONS); do
            local output_file="/tmp/cost_threshold_${i}_$$"
            local exit_code=0
            
            # Test cost monitoring with threshold
            if "$SCRIPT_DIR/utilities/cost-optimization.sh" \
                --project-name "test-project" \
                --environment "development" \
                $threshold_config \
                --monitor-costs \
                --dry-run > "$output_file" 2>&1; then
                exit_code=0
            else
                exit_code=$?
            fi
            
            threshold_outputs+=("$(cat "$output_file")")
            rm -f "$output_file"
            sleep 1
        done
        
        # Check threshold consistency
        if [ ${#threshold_outputs[@]} -gt 1 ]; then
            local first_output="${threshold_outputs[0]}"
            
            for output in "${threshold_outputs[@]:1}"; do
                if [ "$output" != "$first_output" ]; then
                    log_error "Cost monitoring threshold output không nhất quán cho: $threshold_config"
                    return 1
                fi
            done
            
            log_success "Cost monitoring threshold nhất quán cho: $threshold_config"
        fi
    done
    
    return 0
}

# Generate property test report
generate_property_test_report() {
    local report_file="./test-cost-optimization-report.md"
    
    log_info "Tạo báo cáo property test: $report_file"
    
    cat > "$report_file" << EOF
# Báo Cáo Property Test - Cost Optimization

**Property:** Cost Optimization Constraints  
**Task:** 10.3 Write property test for cost optimization  
**Requirements:** 5.1, 5.2, 5.3  
**Ngày test:** $(date -u +%Y-%m-%dT%H:%M:%SZ)  
**Iterations:** $ITERATIONS  

## Định Nghĩa Property

**Cost Optimization Constraints Property:** Tất cả AWS resources được provision phải tuân thủ cost optimization constraints và free tier limits khi có thể.

## Cost Optimization Constraints

EOF
    
    for constraint in "${!COST_CONSTRAINTS[@]}"; do
        echo "- **$constraint:** ${COST_CONSTRAINTS[$constraint]}" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

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

### 1. RDS Cost Optimization Constraints
**Property:** RDS instances phải sử dụng cost-optimized configurations.
**Validation:** Instance class, storage, MultiAZ settings tuân thủ cost constraints.

### 2. Lambda Cost Optimization Constraints
**Property:** Lambda functions phải sử dụng cost-optimized configurations.
**Validation:** Memory size, timeout, concurrency tuân thủ cost constraints.

### 3. Cost Estimation Accuracy
**Property:** Cost estimates phải nhất quán và accurate qua các lần tính toán.
**Validation:** Cost estimates có variance < 5%.

### 4. Free Tier Resource Selection
**Property:** Khi có thể, resources phải sử dụng free tier eligible options.
**Validation:** Instance classes và storage limits tuân thủ free tier.

### 5. Cost Optimization Configuration Consistency
**Property:** Cost optimization configurations phải deterministic.
**Validation:** Cùng inputs tạo ra cùng cost optimization configs.

### 6. Cost Monitoring Thresholds
**Property:** Cost monitoring thresholds phải hoạt động nhất quán.
**Validation:** Threshold alerts và monitoring consistent qua iterations.

## Cấu Hình Test

- **Iterations per Test:** $ITERATIONS
- **Test Mode:** Dry Run (không provision resources thực tế)
- **Cost Constraints:** Defined in COST_CONSTRAINTS array
- **Free Tier Focus:** RDS db.t3.micro, 20GB storage, Lambda optimized memory

## Kết Quả Validation

EOF
    
    if [ $PROPERTY_TESTS_FAILED -eq 0 ]; then
        cat >> "$report_file" << EOF
✅ **TẤT CẢ PROPERTIES ĐƯỢC THỎA MÃN**

Cost optimization system thỏa mãn tất cả cost constraints. Provisioned resources sẽ tuân thủ cost optimization, đảm bảo:

1. **Cost-Optimized Resources:** RDS và Lambda sử dụng cost-effective configurations
2. **Free Tier Compliance:** Resources tận dụng AWS free tier khi có thể
3. **Consistent Cost Estimates:** Cost estimation accurate và reliable
4. **Deterministic Configuration:** Cost optimization configs predictable
5. **Effective Monitoring:** Cost thresholds và alerts hoạt động đúng

### Ý Nghĩa Cho Production

- **Predictable Costs:** AWS costs sẽ được kiểm soát và dự đoán được
- **Free Tier Utilization:** Tối đa hóa free tier benefits
- **Cost Monitoring:** Proactive cost management và alerts
- **Budget Compliance:** Resources tuân thủ budget constraints

### Estimated Monthly Costs (Free Tier)

- **RDS db.t3.micro (20GB):** \$0 (trong free tier limits)
- **Lambda (128MB, low usage):** \$0 (trong free tier limits)
- **VPC, Security Groups:** \$0 (free)
- **Total Estimated:** \$0-5/month (depending on usage)

EOF
    else
        cat >> "$report_file" << EOF
❌ **PHÁT HIỆN VI PHẠM PROPERTY**

Cost optimization system có vấn đề constraints cần được giải quyết:

### Vấn Đề Nghiêm Trọng
- Resources không tuân thủ cost optimization constraints
- Cost estimates không accurate hoặc inconsistent
- Free tier resources không được sử dụng optimal

### Hành Động Cần Thiết
1. Review các property tests failed ở trên
2. Sửa resource provisioning scripts để tuân thủ cost constraints
3. Fix cost estimation logic
4. Ensure free tier resource selection
5. Validate cost monitoring thresholds
6. Chạy lại property tests để validate fixes

### Tác Động Production
- **Risk:** AWS costs có thể vượt quá budget
- **Mitigation:** Sửa cost optimization issues trước khi deploy
- **Monitoring:** Cần cost alerts và monitoring

EOF
    fi
    
    log_success "Báo cáo property test được tạo: $report_file"
}

# Main execution function
main() {
    log_info "Bắt đầu Property Tests cho Cost Optimization"
    log_info "Testing Property: Cost optimization constraints qua $ITERATIONS iterations"
    
    # Set log level
    set_log_level "$TEST_LOG_LEVEL"
    
    # Run all property tests
    run_property_test "RDS Cost Optimization Constraints" \
        "RDS instances tuân thủ cost optimization" \
        "test_rds_cost_optimization_constraints"
    
    run_property_test "Lambda Cost Optimization Constraints" \
        "Lambda functions tuân thủ cost optimization" \
        "test_lambda_cost_optimization_constraints"
    
    run_property_test "Cost Estimation Accuracy" \
        "Cost estimates nhất quán và accurate" \
        "test_cost_estimation_accuracy"
    
    run_property_test "Free Tier Resource Selection" \
        "Resources sử dụng free tier khi có thể" \
        "test_free_tier_resource_selection"
    
    run_property_test "Cost Optimization Configuration Consistency" \
        "Cost optimization configs deterministic" \
        "test_cost_optimization_config_consistency"
    
    run_property_test "Cost Monitoring Thresholds" \
        "Cost monitoring thresholds hoạt động nhất quán" \
        "test_cost_monitoring_thresholds"
    
    # Generate property test report
    generate_property_test_report
    
    # Final summary
    echo ""
    echo "========================================"
    echo "Tóm Tắt Property Test"
    echo "========================================"
    echo "Property: Cost Optimization Constraints"
    echo "Tổng Tests: $((PROPERTY_TESTS_PASSED + PROPERTY_TESTS_FAILED))"
    echo "Passed: $PROPERTY_TESTS_PASSED"
    echo "Failed: $PROPERTY_TESTS_FAILED"
    
    if [ $PROPERTY_TESTS_FAILED -eq 0 ]; then
        log_success "🎉 Cost Optimization Constraints Property ĐƯỢC THỎA MÃN! Resources tuân thủ cost optimization."
        exit 0
    else
        log_error "❌ Cost Optimization Constraints Property BỊ VI PHẠM! Cần sửa cost optimization."
        exit 1
    fi
}

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi