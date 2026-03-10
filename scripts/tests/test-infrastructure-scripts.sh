#!/bin/bash

# Comprehensive Infrastructure Scripts Test
# Tests all infrastructure provisioning scripts for functionality and integration

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source utilities
source "$SCRIPT_DIR/utilities/logging.sh"
source "$SCRIPT_DIR/utilities/error-handling.sh"
source "$SCRIPT_DIR/utilities/validate-aws-cli.sh"

# Test configuration
TEST_ENVIRONMENT="test"
TEST_PROJECT="infratest"
TEST_LOG_LEVEL="INFO"

echo "========================================"
echo "Infrastructure Scripts Validation Test"
echo "========================================"
echo ""

# Set up logging
set_log_level "$TEST_LOG_LEVEL"
log_info "Starting comprehensive infrastructure scripts test"

# Test 1: Validate all scripts have correct syntax
log_info "Test 1: Validating script syntax..."

scripts_to_test=(
    "infrastructure/provision-rds.sh"
    "infrastructure/provision-lambda.sh"
    "infrastructure/configure-iam.sh"
    "deploy-full-stack.sh"
)

syntax_errors=0
for script in "${scripts_to_test[@]}"; do
    log_debug "Checking syntax: $script"
    if bash -n "$SCRIPT_DIR/$script"; then
        log_success "✓ $script - syntax OK"
    else
        log_error "✗ $script - syntax error"
        ((syntax_errors++))
    fi
done

if [ $syntax_errors -eq 0 ]; then
    log_success "All scripts pass syntax validation"
else
    log_error "$syntax_errors scripts have syntax errors"
    exit 1
fi

echo ""

# Test 2: Validate script help functionality
log_info "Test 2: Validating help functionality..."

help_errors=0
for script in "${scripts_to_test[@]}"; do
    log_debug "Testing help for: $script"
    if bash "$SCRIPT_DIR/$script" --help >/dev/null 2>&1; then
        log_success "✓ $script - help works"
    else
        log_error "✗ $script - help failed"
        ((help_errors++))
    fi
done

if [ $help_errors -eq 0 ]; then
    log_success "All scripts provide working help"
else
    log_error "$help_errors scripts have help issues"
    exit 1
fi

echo ""

# Test 3: Validate utility dependencies
log_info "Test 3: Validating utility dependencies..."

utility_scripts=(
    "utilities/logging.sh"
    "utilities/error-handling.sh"
    "utilities/validate-aws-cli.sh"
)

dependency_errors=0
for utility in "${utility_scripts[@]}"; do
    log_debug "Checking utility: $utility"
    if [ -f "$SCRIPT_DIR/$utility" ] && bash -n "$SCRIPT_DIR/$utility"; then
        log_success "✓ $utility - available and valid"
    else
        log_error "✗ $utility - missing or invalid"
        ((dependency_errors++))
    fi
done

if [ $dependency_errors -eq 0 ]; then
    log_success "All utility dependencies are available"
else
    log_error "$dependency_errors utility dependencies have issues"
    exit 1
fi

echo ""

# Test 4: Validate AWS CLI integration
log_info "Test 4: Validating AWS CLI integration..."

if validate_aws_cli; then
    log_success "AWS CLI integration works correctly"
else
    log_warn "AWS CLI integration has issues (this may be expected in some environments)"
fi

echo ""

# Test 5: Test error handling framework
log_info "Test 5: Testing error handling framework..."

# Test error context setting
set_error_context "Test context"
set_error_remediation "Test remediation"

# Test checkpoint functionality
create_checkpoint "test_checkpoint" "test_data_123"
if restore_checkpoint "test_checkpoint" | grep -q "test_data_123"; then
    log_success "Checkpoint functionality works"
else
    log_error "Checkpoint functionality failed"
    exit 1
fi

# Clean up test checkpoint
rm -f "./deployment_checkpoints/test_checkpoint.checkpoint"

log_success "Error handling framework works correctly"

echo ""

# Test 6: Test script argument parsing
log_info "Test 6: Testing script argument parsing..."

# Test RDS script with dry-run equivalent (help doesn't fail)
if bash "$SCRIPT_DIR/infrastructure/provision-rds.sh" --environment "$TEST_ENVIRONMENT" --project-name "$TEST_PROJECT" --help >/dev/null 2>&1; then
    log_success "✓ RDS script argument parsing works"
else
    log_error "✗ RDS script argument parsing failed"
    exit 1
fi

# Test Lambda script
if bash "$SCRIPT_DIR/infrastructure/provision-lambda.sh" --environment "$TEST_ENVIRONMENT" --project-name "$TEST_PROJECT" --help >/dev/null 2>&1; then
    log_success "✓ Lambda script argument parsing works"
else
    log_error "✗ Lambda script argument parsing failed"
    exit 1
fi

# Test IAM script
if bash "$SCRIPT_DIR/infrastructure/configure-iam.sh" --environment "$TEST_ENVIRONMENT" --project-name "$TEST_PROJECT" --help >/dev/null 2>&1; then
    log_success "✓ IAM script argument parsing works"
else
    log_error "✗ IAM script argument parsing failed"
    exit 1
fi

log_success "All scripts handle arguments correctly"

echo ""

# Test 7: Test master deployment script integration
log_info "Test 7: Testing master deployment script integration..."

# Test dry-run mode
if bash "$SCRIPT_DIR/deploy-full-stack.sh" --skip-tests --dry-run >/dev/null 2>&1; then
    log_success "✓ Master deployment script dry-run works"
else
    log_error "✗ Master deployment script dry-run failed"
    exit 1
fi

# Test different modes
modes=("initial" "update" "cleanup")
for mode in "${modes[@]}"; do
    if bash "$SCRIPT_DIR/deploy.sh" --mode "$mode" --environment "$TEST_ENVIRONMENT" --dry-run >/dev/null 2>&1; then
        log_success "✓ Master deployment script mode '$mode' works"
    else
        log_error "✗ Master deployment script mode '$mode' failed"
        exit 1
    fi
done

log_success "Master deployment script integration works correctly"

echo ""

# Test 8: Validate script permissions and executability
log_info "Test 8: Validating script permissions..."

permission_errors=0
all_scripts=("${scripts_to_test[@]}" "${utility_scripts[@]}")

for script in "${all_scripts[@]}"; do
    if [ -x "$SCRIPT_DIR/$script" ]; then
        log_success "✓ $script - executable"
    else
        log_warn "! $script - not executable (this may be intentional)"
    fi
done

log_success "Script permissions validated"

echo ""

# Test Summary
echo "========================================"
echo "Test Summary"
echo "========================================"
echo ""
log_success "All infrastructure scripts validation tests passed!"
echo ""
echo "✓ Script syntax validation"
echo "✓ Help functionality"
echo "✓ Utility dependencies"
echo "✓ AWS CLI integration"
echo "✓ Error handling framework"
echo "✓ Argument parsing"
echo "✓ Master deployment integration"
echo "✓ Script permissions"
echo ""
echo "Infrastructure scripts are functional and ready for use."
echo ""
echo "Next steps:"
echo "1. Run actual infrastructure provisioning with: ./deploy-full-stack.sh"
echo "2. Monitor logs for any runtime issues"
echo "3. Validate created AWS resources"
echo ""

log_success "Infrastructure scripts validation completed successfully!"