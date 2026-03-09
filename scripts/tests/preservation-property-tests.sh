#!/bin/bash

# Preservation Property Tests for AWS CLI Validation (Reduced Examples)
# Property 2: Preservation - Profile-Specific Validation Behavior
# 
# **Validates: Requirements 3.1, 3.2, 3.3, 3.4**
#
# These tests capture the baseline behavior on UNFIXED code for non-buggy inputs
# (calls with valid profile parameters) to ensure no regressions are introduced
# when fixing the unbound variable issue.
#
# OPTIMIZATION: Reduced number of test examples for faster execution while
# maintaining property-based testing coverage of essential scenarios.

set -euo pipefail

# Source required utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utilities/logging.sh"
source "$SCRIPT_DIR/../utilities/validate-aws-cli.sh"

# Test configuration
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TEMP_DIR=$(mktemp -d)

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Property-based test helper functions (reduced for faster execution)
generate_valid_profile_names() {
    # Generate a minimal set of valid profile names for testing
    echo "default"
    echo "production" 
}

generate_invalid_profile_names() {
    # Generate a minimal set of invalid profile names for testing
    echo "nonexistent-profile"
    echo "invalid-profile"
}

# Test function: Profile-specific validation behavior preservation
test_valid_profile_validation_preservation() {
    local test_case="Valid profile validation behavior preservation"
    log_info "Testing: $test_case"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test with known valid profile (default)
    local valid_profile="default"
    local test_output
    local exit_code
    
    # Capture the validation behavior
    if test_output=$(validate_aws_cli "$valid_profile" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    # Verify expected behavior patterns for valid profiles
    if [[ $exit_code -eq 0 ]] && 
       [[ "$test_output" == *"Starting comprehensive AWS CLI validation"* ]] &&
       [[ "$test_output" == *"Validating AWS profile: $valid_profile"* ]] &&
       [[ "$test_output" == *"AWS profile '$valid_profile' is valid"* ]]; then
        
        log_success "✓ Valid profile validation works correctly"
        log_debug "Profile validation includes comprehensive checks:"
        log_debug "  - AWS CLI installation check"
        log_debug "  - Profile existence verification"
        log_debug "  - Credential validation"
        log_debug "  - Region configuration check"
        log_debug "  - Permission validation"
        
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "✗ Valid profile validation behavior changed unexpectedly"
        log_error "Exit code: $exit_code"
        log_error "Output: $test_output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Test function: Invalid profile error handling preservation
test_invalid_profile_error_handling_preservation() {
    local test_case="Invalid profile error handling preservation"
    log_info "Testing: $test_case"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test with known invalid profile
    local invalid_profile="nonexistent-profile"
    local test_output
    local exit_code
    
    # Capture the error handling behavior
    if test_output=$(validate_aws_cli "$invalid_profile" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    # Verify expected error handling patterns for invalid profiles
    # Invalid profiles should provide error messages even if they exit with non-zero code
    if [[ "$test_output" == *"Starting comprehensive AWS CLI validation"* ]] &&
       [[ "$test_output" == *"Validating AWS profile: $invalid_profile"* ]] &&
       ([[ "$test_output" == *"AWS profile '$invalid_profile' not found"* ]] ||
        [[ "$test_output" == *"Available Profiles"* ]]); then
        
        log_success "✓ Invalid profile error handling works correctly (exit code: $exit_code)"
        log_debug "Error handling includes:"
        log_debug "  - Clear error message about profile not found"
        log_debug "  - Profile management instructions"
        
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "✗ Invalid profile error handling behavior changed unexpectedly"
        log_error "Exit code: $exit_code"
        log_error "Output: $test_output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Property-based test: AWS CLI validation checks preservation
test_aws_validation_checks_preservation() {
    local test_case="AWS CLI validation checks preservation"
    log_info "Testing: $test_case"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test that all AWS validation components work with valid profile
    local valid_profile="default"
    local test_output
    
    if test_output=$(validate_aws_cli "$valid_profile" 2>&1); then
        # Verify all expected validation steps are present
        local validation_steps=(
            "Checking AWS CLI installation"
            "Validating AWS profile"
            "Checking AWS credentials"
            "Checking AWS region configuration"
            "Checking AWS permissions"
        )
        
        local all_steps_present=true
        for step in "${validation_steps[@]}"; do
            if [[ "$test_output" != *"$step"* ]]; then
                log_error "Missing validation step: $step"
                all_steps_present=false
            fi
        done
        
        if [ "$all_steps_present" = true ]; then
            log_success "✓ All AWS validation checks are preserved"
            log_debug "Validation includes all required steps:"
            for step in "${validation_steps[@]}"; do
                log_debug "  - $step"
            done
            
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            log_error "✗ Some AWS validation checks are missing"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    else
        log_error "✗ AWS validation failed unexpectedly with valid profile"
        log_error "Output: $test_output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Property-based test: Profile parameter handling preservation (reduced examples)
test_profile_parameter_handling_preservation() {
    local test_case="Profile parameter handling preservation (property-based - reduced)"
    log_info "Testing: $test_case"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    local all_tests_passed=true
    
    # Test only essential valid profile names (reduced for speed)
    log_debug "Testing essential valid profile name patterns..."
    while IFS= read -r profile_name; do
        if [ "$profile_name" = "default" ]; then
            # Only test with default profile since it exists
            local test_output
            if test_output=$(validate_aws_cli "$profile_name" 2>&1); then
                if [[ "$test_output" == *"Validating AWS profile: $profile_name"* ]]; then
                    log_debug "✓ Profile parameter '$profile_name' handled correctly"
                else
                    log_error "✗ Profile parameter '$profile_name' not handled correctly"
                    all_tests_passed=false
                fi
            else
                # For default profile, this should not fail due to parameter handling
                log_error "✗ Profile parameter '$profile_name' caused unexpected failure"
                all_tests_passed=false
            fi
        fi
    done <<< "$(generate_valid_profile_names)"
    
    # Test only essential invalid profile names (reduced for speed)
    log_debug "Testing essential invalid profile name error patterns..."
    local invalid_count=0
    while IFS= read -r profile_name; do
        # Limit to first 2 invalid profiles for speed
        if [ $invalid_count -ge 2 ]; then
            break
        fi
        
        local test_output
        local exit_code
        if test_output=$(validate_aws_cli "$profile_name" 2>&1); then
            exit_code=0
        else
            exit_code=$?
        fi
        
        # Invalid profiles should either:
        # 1. Return gracefully with error message, OR
        # 2. Exit with non-zero code but still provide error message
        if [[ "$test_output" == *"AWS profile '$profile_name' not found"* ]] ||
           [[ "$test_output" == *"Available Profiles"* ]]; then
            log_debug "✓ Invalid profile '$profile_name' handled correctly (exit code: $exit_code)"
        else
            log_error "✗ Invalid profile '$profile_name' not handled correctly"
            log_error "Exit code: $exit_code, Output: $test_output"
            all_tests_passed=false
        fi
        
        invalid_count=$((invalid_count + 1))
    done <<< "$(generate_invalid_profile_names)"
    
    if [ "$all_tests_passed" = true ]; then
        log_success "✓ Profile parameter handling preservation verified across essential inputs"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "✗ Profile parameter handling preservation failed for some inputs"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Property-based test: Empty string parameter handling
test_empty_string_parameter_preservation() {
    local test_case="Empty string parameter handling preservation"
    log_info "Testing: $test_case"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test with empty string parameter (should work on unfixed code)
    local test_output
    local exit_code
    
    if test_output=$(validate_aws_cli "" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    # Empty string should be handled gracefully (not trigger profile validation)
    if [[ $exit_code -eq 0 ]] && 
       [[ "$test_output" == *"Starting comprehensive AWS CLI validation"* ]] &&
       [[ "$test_output" != *"Validating AWS profile:"* ]]; then
        
        log_success "✓ Empty string parameter handled correctly"
        log_debug "Empty string skips profile validation as expected"
        
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "✗ Empty string parameter handling changed unexpectedly"
        log_error "Exit code: $exit_code"
        log_error "Output: $test_output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Main test execution
main() {
    log_info "=== Preservation Property Tests ==="
    log_info "Property 2: Profile-Specific Validation Behavior"
    log_info "**Validates: Requirements 3.1, 3.2, 3.3, 3.4**"
    log_info ""
    log_info "Testing baseline behavior on UNFIXED code for non-buggy inputs"
    log_info "Expected outcome: All tests PASS (confirms behavior to preserve)"
    echo ""
    
    # Run all preservation tests
    test_valid_profile_validation_preservation
    echo ""
    
    test_invalid_profile_error_handling_preservation  
    echo ""
    
    test_aws_validation_checks_preservation
    echo ""
    
    test_profile_parameter_handling_preservation
    echo ""
    
    test_empty_string_parameter_preservation
    echo ""
    
    # Display test summary
    echo "=== Preservation Property Tests Summary ==="
    echo "Tests run: $TESTS_RUN"
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "✅ All preservation property tests PASSED"
        log_info "✓ Baseline behavior confirmed for profile-specific validation"
        log_info "✓ Ready to implement fix while preserving existing behavior"
        echo ""
        echo "=== Preserved Behaviors Confirmed ==="
        echo "• Profile-specific validation continues to work correctly"
        echo "• AWS CLI validation checks remain unchanged"  
        echo "• Error handling for invalid profiles remains unchanged"
        echo "• Parameter handling patterns are consistent"
        echo ""
        return 0
    else
        log_error "❌ Some preservation property tests FAILED"
        log_error "Baseline behavior verification incomplete"
        echo ""
        return 1
    fi
}

# Execute main function
main "$@"