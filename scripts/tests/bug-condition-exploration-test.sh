#!/bin/bash

# Bug Condition Exploration Test for AWS CLI Validation
# This test MUST FAIL on unfixed code to prove the bug exists
# **Validates: Requirements 2.1, 2.2**

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utilities/logging.sh"

# Test configuration
TEST_NAME="Bug Condition Exploration Test"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Initialize test results
TESTS_RUN=0
TESTS_FAILED=0
COUNTEREXAMPLES=()

log_info "Starting $TEST_NAME"
log_info "CRITICAL: This test MUST FAIL on unfixed code - failure confirms the bug exists"
echo ""

# Property 1: Fault Condition - Unbound Variable Parameter Handling
# Test that validate_aws_cli function can be called without parameters
test_validate_aws_cli_no_parameters() {
    local test_case="validate_aws_cli function call without parameters"
    log_info "Testing: $test_case"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Create a test script that sources and calls validate_aws_cli without parameters
    cat > "$TEMP_DIR/test-no-params.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utilities/logging.sh"
source "$SCRIPT_DIR/../utilities/validate-aws-cli.sh"

# This should work according to expected behavior (Requirements 2.1, 2.2)
# but will FAIL on unfixed code due to unbound variable $1
validate_aws_cli
EOF
    
    chmod +x "$TEMP_DIR/test-no-params.sh"
    
    local output
    local exit_code
    
    # Execute the test and capture results
    if output=$("$TEMP_DIR/test-no-params.sh" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    # Expected behavior: function should proceed with default profile validation
    # Actual behavior on unfixed code: crashes with "unbound variable" error
    if [ $exit_code -ne 0 ]; then
        log_error "❌ FAILED: $test_case"
        log_error "Exit code: $exit_code"
        log_error "Output: $output"
        
        # Check if this is the expected unbound variable error
        if echo "$output" | grep -q "unbound variable"; then
            log_info "✓ Confirmed: Unbound variable error detected (this proves the bug exists)"
            COUNTEREXAMPLES+=("Function call without parameters: unbound variable error at \$1")
        else
            log_warn "Unexpected error type: $output"
            COUNTEREXAMPLES+=("Function call without parameters: unexpected error - $output")
        fi
        
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    else
        log_success "✅ PASSED: $test_case"
        log_info "Function proceeded with default profile validation"
        return 0
    fi
}

# Test direct script execution without arguments
test_direct_script_execution() {
    local test_case="Direct script execution without arguments"
    log_info "Testing: $test_case"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    local script_path="$SCRIPT_DIR/../utilities/validate-aws-cli.sh"
    local output
    local exit_code
    
    # Execute the script directly without arguments
    if output=$("$script_path" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    # Expected behavior: script should handle missing arguments gracefully
    # Actual behavior on unfixed code: may crash with unbound variable error
    if [ $exit_code -ne 0 ]; then
        log_error "❌ FAILED: $test_case"
        log_error "Exit code: $exit_code"
        log_error "Output: $output"
        
        if echo "$output" | grep -q "unbound variable"; then
            log_info "✓ Confirmed: Unbound variable error in direct execution"
            COUNTEREXAMPLES+=("Direct script execution: unbound variable error")
        else
            COUNTEREXAMPLES+=("Direct script execution: error - $output")
        fi
        
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    else
        log_success "✅ PASSED: $test_case"
        return 0
    fi
}

# Test function call with empty string parameter (should work even on unfixed code)
test_validate_aws_cli_empty_parameter() {
    local test_case="validate_aws_cli function call with empty string parameter"
    log_info "Testing: $test_case"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Create a test script that calls validate_aws_cli with empty string
    cat > "$TEMP_DIR/test-empty-param.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utilities/logging.sh"
source "$SCRIPT_DIR/../utilities/validate-aws-cli.sh"

# Call with empty string - this should work even on unfixed code
validate_aws_cli ""
EOF
    
    chmod +x "$TEMP_DIR/test-empty-param.sh"
    
    local output
    local exit_code
    
    if output=$("$TEMP_DIR/test-empty-param.sh" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    if [ $exit_code -ne 0 ]; then
        log_error "❌ FAILED: $test_case"
        log_error "Exit code: $exit_code"
        log_error "Output: $output"
        COUNTEREXAMPLES+=("Function call with empty string: error - $output")
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    else
        log_success "✅ PASSED: $test_case"
        return 0
    fi
}

# Run all tests
echo "=== Running Bug Condition Exploration Tests ==="
echo ""

test_validate_aws_cli_no_parameters
echo ""

test_direct_script_execution  
echo ""

test_validate_aws_cli_empty_parameter
echo ""

# Report results
echo "=== Test Results Summary ==="
echo "Tests run: $TESTS_RUN"
echo "Tests failed: $TESTS_FAILED"
echo "Tests passed: $((TESTS_RUN - TESTS_FAILED))"
echo ""

if [ ${#COUNTEREXAMPLES[@]} -gt 0 ]; then
    echo "=== Counterexamples Found (Proof of Bug) ==="
    for example in "${COUNTEREXAMPLES[@]}"; do
        echo "  - $example"
    done
    echo ""
    
    log_info "✓ Bug condition confirmed: validate_aws_cli fails with unbound variable when called without parameters"
    log_info "✓ Root cause: Line 725 'local profile=\"\$1\"' accesses unbound variable in strict mode"
    log_info "✓ Expected behavior: Function should proceed with default AWS profile validation"
else
    log_warn "No counterexamples found - bug may already be fixed or test needs adjustment"
fi

echo "=== Expected Outcome ==="
if [ $TESTS_FAILED -gt 0 ]; then
    log_info "✓ CORRECT: Test failed as expected on unfixed code"
    log_info "✓ This confirms the bug exists and needs to be fixed"
    echo ""
    echo "Next steps:"
    echo "1. Implement the fix for unbound variable parameter handling"
    echo "2. Re-run this test to verify it passes after the fix"
    echo "3. Ensure preservation tests still pass"
else
    log_warn "⚠ UNEXPECTED: Test passed - this may indicate:"
    log_warn "  - The bug is already fixed"
    log_warn "  - The test logic needs adjustment"
    log_warn "  - The root cause analysis was incorrect"
fi

echo ""
log_info "$TEST_NAME completed"

# Exit with failure if tests failed (expected on unfixed code)
exit $TESTS_FAILED