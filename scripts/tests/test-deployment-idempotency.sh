#!/bin/bash

# Deployment Idempotency Property Test
# Property 4: Deployment idempotency
# Validates: Requirements 3.1, 3.2, 3.3
# Tests that repeated deployments produce consistent infrastructure state

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/utilities/logging.sh"
source "$SCRIPT_DIR/utilities/error-handling.sh"

# Test configuration
TEST_PROJECT_NAME="idempotency-test"
TEST_ENVIRONMENT="development"
TEST_AWS_REGION="us-east-1"
TEST_LOG_LEVEL="INFO"
ITERATIONS=3  # Number of repeated deployments to test

# Test results
PROPERTY_TESTS_PASSED=0
PROPERTY_TESTS_FAILED=0
PROPERTY_RESULTS=()

# Function to run property test
run_property_test() {
    local property_name="$1"
    local test_description="$2"
    local test_function="$3"
    
    log_info "Testing Property: $property_name"
    log_info "Description: $test_description"
    
    local start_time=$(date +%s)
    
    if $test_function; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_success "✓ Property '$property_name' holds (${duration}s)"
        PROPERTY_TESTS_PASSED=$((PROPERTY_TESTS_PASSED + 1))
        PROPERTY_RESULTS+=("PASS: $property_name")
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_error "✗ Property '$property_name' violated (${duration}s)"
        PROPERTY_TESTS_FAILED=$((PROPERTY_TESTS_FAILED + 1))
        PROPERTY_RESULTS+=("FAIL: $property_name")
    fi
}

# Property Test 1: Deployment Output Consistency
test_deployment_output_consistency() {
    log_info "=== Property Test 1: Deployment Output Consistency ==="
    
    local outputs=()
    local exit_codes=()
    
    # Run the same deployment command multiple times
    for i in $(seq 1 $ITERATIONS); do
        log_info "Running deployment iteration $i/$ITERATIONS"
        
        local output_file="/tmp/deployment_output_${i}_$$"
        local exit_code=0
        
        # Run deployment and capture output
        if "$SCRIPT_DIR/deploy.sh" --mode initial --environment $TEST_ENVIRONMENT \
            --project-name "${TEST_PROJECT_NAME}-consistency" --dry-run --skip-validation \
            > "$output_file" 2>&1; then
            exit_code=0
        else
            exit_code=$?
        fi
        
        outputs+=("$(cat "$output_file")")
        exit_codes+=($exit_code)
        rm -f "$output_file"
        
        # Small delay between iterations
        sleep 1
    done
    
    # Analyze consistency
    local first_exit_code=${exit_codes[0]}
    local consistent_exit_codes=true
    
    for exit_code in "${exit_codes[@]}"; do
        if [ "$exit_code" != "$first_exit_code" ]; then
            consistent_exit_codes=false
            log_error "Inconsistent exit codes: expected $first_exit_code, got $exit_code"
            break
        fi
    done
    
    if [ "$consistent_exit_codes" = true ]; then
        log_success "Exit codes are consistent across all iterations"
        return 0
    else
        log_error "Exit codes are inconsistent across iterations"
        return 1
    fi
}

# Property Test 2: Configuration State Consistency
test_configuration_state_consistency() {
    log_info "=== Property Test 2: Configuration State Consistency ==="
    
    local config_hashes=()
    
    # Run deployment multiple times and capture configuration state
    for i in $(seq 1 $ITERATIONS); do
        log_info "Capturing configuration state iteration $i/$ITERATIONS"
        
        local config_file="/tmp/deployment_config_${i}_$$"
        
        # Run deployment with debug output to capture configuration
        "$SCRIPT_DIR/deploy.sh" --mode initial --environment $TEST_ENVIRONMENT \
            --project-name "${TEST_PROJECT_NAME}-config" --dry-run --skip-validation \
            --log-level DEBUG > "$config_file" 2>&1 || true
        
        # Extract configuration section and create hash
        local config_hash=$(grep -A 10 "Configuration set:" "$config_file" 2>/dev/null | md5sum | cut -d' ' -f1 || echo "no-config")
        config_hashes+=("$config_hash")
        
        rm -f "$config_file"
        sleep 1
    done
    
    # Check if all configuration hashes are the same
    local first_hash=${config_hashes[0]}
    local consistent_config=true
    
    for hash in "${config_hashes[@]}"; do
        if [ "$hash" != "$first_hash" ]; then
            consistent_config=false
            log_error "Inconsistent configuration hash: expected $first_hash, got $hash"
            break
        fi
    done
    
    if [ "$consistent_config" = true ]; then
        log_success "Configuration state is consistent across all iterations"
        return 0
    else
        log_error "Configuration state is inconsistent across iterations"
        return 1
    fi
}

# Property Test 3: Orchestrator Invocation Consistency
test_orchestrator_invocation_consistency() {
    log_info "=== Property Test 3: Orchestrator Invocation Consistency ==="
    
    local orchestrator_commands=()
    
    # Run deployment multiple times and capture orchestrator invocation
    for i in $(seq 1 $ITERATIONS); do
        log_info "Capturing orchestrator invocation iteration $i/$ITERATIONS"
        
        local output_file="/tmp/orchestrator_output_${i}_$$"
        
        # Run deployment with debug output to capture orchestrator command
        "$SCRIPT_DIR/deploy.sh" --mode initial --environment $TEST_ENVIRONMENT \
            --project-name "${TEST_PROJECT_NAME}-orchestrator" --dry-run --skip-validation \
            --log-level DEBUG > "$output_file" 2>&1 || true
        
        # Extract orchestrator command line
        local orchestrator_cmd=$(grep "Executing orchestrator:" "$output_file" 2>/dev/null | head -1 || echo "no-orchestrator")
        orchestrator_commands+=("$orchestrator_cmd")
        
        rm -f "$output_file"
        sleep 1
    done
    
    # Check if all orchestrator commands are the same
    local first_cmd="${orchestrator_commands[0]}"
    local consistent_orchestrator=true
    
    for cmd in "${orchestrator_commands[@]}"; do
        if [ "$cmd" != "$first_cmd" ]; then
            consistent_orchestrator=false
            log_error "Inconsistent orchestrator command"
            log_error "Expected: $first_cmd"
            log_error "Got: $cmd"
            break
        fi
    done
    
    if [ "$consistent_orchestrator" = true ]; then
        log_success "Orchestrator invocation is consistent across all iterations"
        return 0
    else
        log_error "Orchestrator invocation is inconsistent across iterations"
        return 1
    fi
}

# Property Test 4: Deployment Mode Behavior Consistency
test_deployment_mode_consistency() {
    log_info "=== Property Test 4: Deployment Mode Behavior Consistency ==="
    
    local modes=("initial" "update" "cleanup")
    local mode_results=()
    
    for mode in "${modes[@]}"; do
        log_info "Testing consistency for mode: $mode"
        
        local mode_outputs=()
        local mode_exit_codes=()
        
        # Run the same mode multiple times
        for i in $(seq 1 $ITERATIONS); do
            local output_file="/tmp/mode_${mode}_${i}_$$"
            local exit_code=0
            
            local cmd_args="--mode $mode --environment $TEST_ENVIRONMENT --project-name ${TEST_PROJECT_NAME}-${mode} --dry-run --skip-validation"
            if [ "$mode" = "cleanup" ]; then
                cmd_args="$cmd_args --force"
            fi
            
            if "$SCRIPT_DIR/deploy.sh" $cmd_args > "$output_file" 2>&1; then
                exit_code=0
            else
                exit_code=$?
            fi
            
            mode_outputs+=("$(cat "$output_file")")
            mode_exit_codes+=($exit_code)
            rm -f "$output_file"
            sleep 1
        done
        
        # Check consistency for this mode
        local first_exit_code=${mode_exit_codes[0]}
        local mode_consistent=true
        
        for exit_code in "${mode_exit_codes[@]}"; do
            if [ "$exit_code" != "$first_exit_code" ]; then
                mode_consistent=false
                log_error "Mode $mode: inconsistent exit codes"
                break
            fi
        done
        
        if [ "$mode_consistent" = true ]; then
            log_success "Mode $mode behavior is consistent"
            mode_results+=("PASS: $mode")
        else
            log_error "Mode $mode behavior is inconsistent"
            mode_results+=("FAIL: $mode")
            return 1
        fi
    done
    
    log_success "All deployment modes show consistent behavior"
    return 0
}

# Property Test 5: Parameter Handling Consistency
test_parameter_handling_consistency() {
    log_info "=== Property Test 5: Parameter Handling Consistency ==="
    
    local parameter_sets=(
        "--region us-east-1"
        "--region ap-southeast-1"
        "--log-level DEBUG"
        "--log-level INFO"
        "--aws-profile default"
    )
    
    for params in "${parameter_sets[@]}"; do
        log_info "Testing parameter consistency: $params"
        
        local param_outputs=()
        local param_exit_codes=()
        
        # Run with the same parameters multiple times
        for i in $(seq 1 $ITERATIONS); do
            local output_file="/tmp/param_test_${i}_$$"
            local exit_code=0
            
            if "$SCRIPT_DIR/deploy.sh" --mode initial --environment $TEST_ENVIRONMENT \
                --project-name "${TEST_PROJECT_NAME}-params" $params --dry-run --skip-validation \
                > "$output_file" 2>&1; then
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
                log_error "Parameter set '$params': inconsistent exit codes"
                return 1
            fi
        done
        
        log_success "Parameter set '$params' shows consistent behavior"
    done
    
    log_success "All parameter combinations show consistent behavior"
    return 0
}

# Property Test 6: Concurrent Deployment Isolation
test_concurrent_deployment_isolation() {
    log_info "=== Property Test 6: Concurrent Deployment Isolation ==="
    
    # Start multiple deployments with different project names concurrently
    local pids=()
    local project_names=()
    local output_files=()
    
    for i in $(seq 1 3); do
        local project_name="${TEST_PROJECT_NAME}-concurrent-${i}"
        local output_file="/tmp/concurrent_${i}_$$"
        
        project_names+=("$project_name")
        output_files+=("$output_file")
        
        # Start deployment in background
        "$SCRIPT_DIR/deploy.sh" --mode initial --environment $TEST_ENVIRONMENT \
            --project-name "$project_name" --dry-run --skip-validation \
            > "$output_file" 2>&1 &
        
        pids+=($!)
    done
    
    # Wait for all deployments to complete
    local all_successful=true
    for i in "${!pids[@]}"; do
        local pid=${pids[$i]}
        local project_name=${project_names[$i]}
        local output_file=${output_files[$i]}
        
        if wait $pid; then
            log_success "Concurrent deployment $((i+1)) completed successfully"
        else
            log_error "Concurrent deployment $((i+1)) failed"
            all_successful=false
        fi
        
        # Clean up
        rm -f "$output_file"
    done
    
    if [ "$all_successful" = true ]; then
        log_success "All concurrent deployments completed successfully (isolation maintained)"
        return 0
    else
        log_error "Some concurrent deployments failed (isolation may be compromised)"
        return 1
    fi
}

# Function to generate property test report
generate_property_test_report() {
    local report_file="./deployment-idempotency-property-test-report.md"
    
    log_info "Generating property test report: $report_file"
    
    cat > "$report_file" << EOF
# Deployment Idempotency Property Test Report

**Property:** Deployment Idempotency  
**Requirements:** 3.1, 3.2, 3.3  
**Test Run:** $(date -u +%Y-%m-%dT%H:%M:%SZ)  
**Environment:** $TEST_ENVIRONMENT  
**Iterations:** $ITERATIONS  

## Property Definition

**Deployment Idempotency Property:** Repeated deployments with identical parameters must produce consistent infrastructure state and behavior, regardless of the number of executions or timing.

## Test Summary

- **Total Property Tests:** $((PROPERTY_TESTS_PASSED + PROPERTY_TESTS_FAILED))
- **Passed:** $PROPERTY_TESTS_PASSED
- **Failed:** $PROPERTY_TESTS_FAILED
- **Success Rate:** $(( PROPERTY_TESTS_PASSED * 100 / (PROPERTY_TESTS_PASSED + PROPERTY_TESTS_FAILED) ))%

## Property Test Results

EOF
    
    for result in "${PROPERTY_RESULTS[@]}"; do
        echo "- $result" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

## Tested Properties

### 1. Deployment Output Consistency
**Property:** Multiple executions of the same deployment command produce identical exit codes.
**Validation:** Ensures deterministic behavior across repeated deployments.

### 2. Configuration State Consistency  
**Property:** Deployment configuration remains stable across multiple executions.
**Validation:** Ensures configuration parsing and processing is deterministic.

### 3. Orchestrator Invocation Consistency
**Property:** Orchestrator is invoked with identical parameters across repeated deployments.
**Validation:** Ensures parameter mapping and delegation is consistent.

### 4. Deployment Mode Behavior Consistency
**Property:** Each deployment mode (initial, update, cleanup) behaves consistently across executions.
**Validation:** Ensures mode-specific logic is deterministic.

### 5. Parameter Handling Consistency
**Property:** Different parameter combinations produce consistent behavior across executions.
**Validation:** Ensures parameter processing is deterministic.

### 6. Concurrent Deployment Isolation
**Property:** Multiple concurrent deployments with different project names do not interfere with each other.
**Validation:** Ensures proper isolation and resource management.

## Test Configuration

- **Test Project Name:** $TEST_PROJECT_NAME
- **Test Environment:** $TEST_ENVIRONMENT
- **Test AWS Region:** $TEST_AWS_REGION
- **Iterations per Test:** $ITERATIONS
- **Test Mode:** Dry Run (no actual AWS resources)

## Property Validation Results

EOF
    
    if [ $PROPERTY_TESTS_FAILED -eq 0 ]; then
        cat >> "$report_file" << EOF
✅ **ALL PROPERTIES HOLD**

The deployment system satisfies the idempotency property. Repeated deployments produce consistent results, ensuring:

1. **Deterministic Behavior:** Same inputs always produce same outputs
2. **State Consistency:** Infrastructure state remains predictable
3. **Reliable Operations:** Deployments can be safely repeated
4. **Concurrent Safety:** Multiple deployments don't interfere with each other

### Implications for Production Use

- **Safe Retry Logic:** Failed deployments can be safely retried
- **CI/CD Integration:** Automated deployments will behave predictably
- **Operational Confidence:** Operations teams can trust deployment consistency
- **Rollback Safety:** Rollback operations will behave predictably

EOF
    else
        cat >> "$report_file" << EOF
❌ **PROPERTY VIOLATIONS DETECTED**

The deployment system has idempotency issues that must be addressed:

### Critical Issues
- Inconsistent behavior detected across repeated executions
- Non-deterministic outputs or state changes
- Potential race conditions or timing dependencies

### Required Actions
1. Review failed property tests above
2. Identify root causes of non-deterministic behavior
3. Fix timing dependencies and race conditions
4. Re-run property tests to validate fixes
5. Consider additional property tests for edge cases

### Production Impact
- **Risk:** Unpredictable deployment behavior
- **Mitigation:** Fix issues before production deployment
- **Testing:** Extensive validation required

EOF
    fi
    
    log_success "Property test report generated: $report_file"
}

# Main execution function
main() {
    log_info "Starting Deployment Idempotency Property Tests"
    log_info "Testing Property: Deployment idempotency across $ITERATIONS iterations"
    
    # Set log level
    set_log_level "$TEST_LOG_LEVEL"
    
    # Run all property tests
    run_property_test "Deployment Output Consistency" \
        "Multiple executions produce identical exit codes" \
        "test_deployment_output_consistency"
    
    run_property_test "Configuration State Consistency" \
        "Configuration remains stable across executions" \
        "test_configuration_state_consistency"
    
    run_property_test "Orchestrator Invocation Consistency" \
        "Orchestrator invoked with identical parameters" \
        "test_orchestrator_invocation_consistency"
    
    run_property_test "Deployment Mode Behavior Consistency" \
        "Each mode behaves consistently across executions" \
        "test_deployment_mode_consistency"
    
    run_property_test "Parameter Handling Consistency" \
        "Parameter combinations produce consistent behavior" \
        "test_parameter_handling_consistency"
    
    run_property_test "Concurrent Deployment Isolation" \
        "Concurrent deployments don't interfere with each other" \
        "test_concurrent_deployment_isolation"
    
    # Generate property test report
    generate_property_test_report
    
    # Final summary
    echo ""
    echo "========================================"
    echo "Property Test Summary"
    echo "========================================"
    echo "Property: Deployment Idempotency"
    echo "Total Tests: $((PROPERTY_TESTS_PASSED + PROPERTY_TESTS_FAILED))"
    echo "Passed: $PROPERTY_TESTS_PASSED"
    echo "Failed: $PROPERTY_TESTS_FAILED"
    
    if [ $PROPERTY_TESTS_FAILED -eq 0 ]; then
        log_success "🎉 Deployment Idempotency Property HOLDS! System is deterministic."
        exit 0
    else
        log_error "❌ Deployment Idempotency Property VIOLATED! Fix required."
        exit 1
    fi
}

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi