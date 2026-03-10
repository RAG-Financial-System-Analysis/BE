#!/bin/bash

# Test script for flexible AWS credential detection
# This script tests the new credential detection logic

set -euo pipefail

# Source the utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utilities/logging.sh"
source "$SCRIPT_DIR/../utilities/validate-aws-cli.sh"

echo "=== Testing Flexible AWS Credential Detection ==="
echo ""

# Test 1: Check if get_aws_region function works
echo "🔍 Test 1: AWS Region Detection"
aws_region=$(get_aws_region)
log_info "Detected AWS region: $aws_region"
echo ""

# Test 2: Check credential detection
echo "🔍 Test 2: AWS Credential Detection"
if check_aws_credentials; then
    log_success "✅ AWS credentials detected successfully"
else
    log_error "❌ AWS credentials not detected"
fi
echo ""

# Test 3: Show current AWS identity (if available)
echo "🔍 Test 3: AWS Identity Check"
if aws sts get-caller-identity &>/dev/null; then
    caller_identity=$(aws sts get-caller-identity 2>/dev/null)
    account_id=$(echo "$caller_identity" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
    user_arn=$(echo "$caller_identity" | grep -o '"Arn": "[^"]*"' | cut -d'"' -f4)
    log_success "✅ AWS Identity verified"
    log_info "Account ID: $account_id"
    log_info "User/Role ARN: $user_arn"
else
    log_warn "⚠️  Cannot verify AWS identity (credentials may be invalid)"
fi
echo ""

# Test 4: Check environment variables
echo "🔍 Test 4: Environment Variable Check"
if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]]; then
    log_info "✅ AWS_ACCESS_KEY_ID is set"
else
    log_info "❌ AWS_ACCESS_KEY_ID is not set"
fi

if [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    log_info "✅ AWS_SECRET_ACCESS_KEY is set"
else
    log_info "❌ AWS_SECRET_ACCESS_KEY is not set"
fi

if [[ -n "${AWS_DEFAULT_REGION:-}" ]]; then
    log_info "✅ AWS_DEFAULT_REGION is set: $AWS_DEFAULT_REGION"
else
    log_info "❌ AWS_DEFAULT_REGION is not set"
fi

if [[ -n "${AWS_PROFILE:-}" ]]; then
    log_info "✅ AWS_PROFILE is set: $AWS_PROFILE"
else
    log_info "❌ AWS_PROFILE is not set"
fi
echo ""

# Test 5: Check credential files
echo "🔍 Test 5: Credential File Check"
if [[ -f "$HOME/.aws/credentials" ]]; then
    log_info "✅ AWS credentials file exists: $HOME/.aws/credentials"
else
    log_info "❌ AWS credentials file not found: $HOME/.aws/credentials"
fi

if [[ -f "$HOME/.aws/config" ]]; then
    log_info "✅ AWS config file exists: $HOME/.aws/config"
else
    log_info "❌ AWS config file not found: $HOME/.aws/config"
fi
echo ""

echo "=== Test Complete ==="
echo ""
echo "💡 Summary:"
echo "   - Region detection: $aws_region"
echo "   - Credential detection: $(check_aws_credentials && echo "✅ Working" || echo "❌ Failed")"
echo "   - AWS CLI access: $(aws sts get-caller-identity &>/dev/null && echo "✅ Working" || echo "❌ Failed")"
echo ""
echo "If all tests show ✅, your AWS credentials are properly configured!"
echo "If any tests show ❌, please configure AWS credentials using one of the supported methods."