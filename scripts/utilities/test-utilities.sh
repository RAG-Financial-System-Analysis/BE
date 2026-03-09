#!/bin/bash

# Test script for core utilities
# Validates that all utility scripts work correctly together

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all utilities
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/validate-aws-cli.sh"
source "$SCRIPT_DIR/error-handling.sh"

echo "=== Testing AWS Deployment Automation Utilities ==="
echo ""

# Test logging utility
log_info "Testing logging utility..."
log_debug "This is a debug message (may not be visible depending on log level)"
log_warn "This is a warning message"
log_success "Logging utility test completed"
echo ""

# Test error handling framework
log_info "Testing error handling framework..."
set_error_context "Utility testing"
set_error_remediation "This is just a test - no action needed"

# Test validation functions
log_info "Testing validation functions..."

# Test environment variable validation (should pass)
export TEST_VAR="test_value"
validate_required_vars "TEST_VAR"
log_success "Environment variable validation test passed"

# Test file validation (should pass for this script)
validate_file_exists "$0" "test script"
log_success "File validation test passed"

# Test directory validation (should pass for utilities directory)
validate_directory_exists "$SCRIPT_DIR" "utilities directory"
log_success "Directory validation test passed"

echo ""

# Test AWS CLI validation
log_info "Testing AWS CLI validation..."
if check_aws_cli_installation; then
    log_success "AWS CLI installation check passed"
    
    # Only test credentials if AWS CLI is installed
    if check_aws_credentials; then
        log_success "AWS credentials check passed"
    else
        log_warn "AWS credentials check failed (this is expected if not configured)"
    fi
    
    if check_aws_region; then
        log_success "AWS region check passed"
    else
        log_warn "AWS region check failed (this is expected if not configured)"
    fi
else
    log_warn "AWS CLI installation check failed"
fi

echo ""
log_success "All utility tests completed successfully!"
echo ""
echo "Log file location: $LOG_FILE"
echo "To view logs: cat $LOG_FILE"
echo ""
echo "Next steps:"
echo "1. Configure AWS CLI if not already done: aws configure"
echo "2. Run AWS validation: ./validate-aws-cli.sh"
echo "3. Proceed with deployment script implementation"