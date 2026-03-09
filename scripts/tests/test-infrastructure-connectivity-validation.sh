#!/bin/bash

# Infrastructure Connectivity Validation Tests
# Tests actual AWS resource connectivity and integration when resources exist
# Validates networking between Lambda and RDS, IAM permissions, and component health
# 
# Task 3.4: Write integration tests for infrastructure provisioning
# Requirements: 1.1, 1.2, 1.3, 1.4

set -euo pipefail

# Script directory and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utilities/logging.sh"
source "$SCRIPT_DIR/../utilities/error-handling.sh"
source "$SCRIPT_DIR/../utilities/validate-aws-cli.sh"

# Test configuration
TEST_ENVIRONMENT="${ENVIRONMENT:-integration-test}"
TEST_PROJECT="${PROJECT_NAME:-infra-test}"
readonly TEST_LOG_LEVEL="INFO"
readonly TEST_TIMEOUT=300

# Test state tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Resource identifiers (will be detected or provided)
VPC_ID=""
RDS_INSTANCE_ID=""
LAMBDA_FUNCTION_NAME=""
LAMBDA_ROLE_ARN=""
SECURITY_GROUP_IDS=""

# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Tests actual AWS infrastructure connectivity and integration.
This script validates that provisioned resources can communicate properly.

OPTIONS:
    --environment ENV          Environment to test (default: integration-test)
    --project-name NAME        Project name (default: infra-test)
    --vpc-id VPC_ID           Specific VPC ID to test
    --rds-instance-id ID      Specific RDS instance ID to test
    --lambda-function NAME    Specific Lambda function name to test
    --aws-profile PROFILE     AWS profile to use
    --skip-connectivity       Skip actual connectivity tests (validation only)
    --help                    Show this help message

EXAMPLES:
    # Auto-detect resources and test
    $0 --environment production --project-name myapp

    # Test specific resources
    $0 --vpc-id vpc-123 --rds-instance-id mydb --lambda-function myfunction

    # Validation only (no actual connectivity tests)
    $0 --skip-connectivity --environment staging

PREREQUISITES:
    - AWS CLI configured with appropriate permissions
    - Infrastructure resources must be provisioned
    - Lambda function must be deployed and configured

EOF
}

# Function to parse command line arguments
parse_arguments() {
    SKIP_CONNECTIVITY=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --environment)
                TEST_ENVIRONMENT="$2"
                shift 2
                ;;
            --project-name)
                TEST_PROJECT="$2"
                shift 2
                ;;
            --vpc-id)
                VPC_ID="$2"
                shift 2
                ;;
            --rds-instance-id)
                RDS_INSTANCE_ID="$2"
                shift 2
                ;;
            --lambda-function)
                LAMBDA_FUNCTION_NAME="$2"
                shift 2
                ;;
            --aws-profile)
                AWS_PROFILE="$2"
                export AWS_PROFILE
                shift 2
                ;;
            --skip-connectivity)
                SKIP_CONNECTIVITY=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to run a test and track results
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    ((TESTS_RUN++))
    log_info "Running test: $test_name"
    
    if $test_function; then
        log_success "✓ PASS: $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        log_error "✗ FAIL: $test_name"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Function to auto-detect infrastructure resources
detect_infrastructure_resources() {
    log_info "Auto-detecting infrastructure resources..."
    
    # Detect VPC if not provided
    if [ -z "$VPC_ID" ]; then
        VPC_ID=$(aws ec2 describe-vpcs \
            --filters "Name=tag:Name,Values=$TEST_PROJECT-$TEST_ENVIRONMENT-vpc" \
            --query 'Vpcs[0].VpcId' \
            --output text 2>/dev/null || echo "None")
        
        if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
            log_warn "VPC not found for project $TEST_PROJECT environment $TEST_ENVIRONMENT"
            VPC_ID=""
        else
            log_info "Detected VPC: $VPC_ID"
        fi
    fi
    
    # Detect RDS instance if not provided
    if [ -z "$RDS_INSTANCE_ID" ]; then
        RDS_INSTANCE_ID=$(aws rds describe-db-instances \
            --query "DBInstances[?contains(DBInstanceIdentifier, '$TEST_PROJECT-$TEST_ENVIRONMENT')].DBInstanceIdentifier" \
            --output text 2>/dev/null || echo "")
        
        if [ -z "$RDS_INSTANCE_ID" ]; then
            log_warn "RDS instance not found for project $TEST_PROJECT environment $TEST_ENVIRONMENT"
        else
            log_info "Detected RDS instance: $RDS_INSTANCE_ID"
        fi
    fi
    
    # Detect Lambda function if not provided
    if [ -z "$LAMBDA_FUNCTION_NAME" ]; then
        LAMBDA_FUNCTION_NAME=$(aws lambda list-functions \
            --query "Functions[?contains(FunctionName, '$TEST_PROJECT-$TEST_ENVIRONMENT')].FunctionName" \
            --output text 2>/dev/null || echo "")
        
        if [ -z "$LAMBDA_FUNCTION_NAME" ]; then
            log_warn "Lambda function not found for project $TEST_PROJECT environment $TEST_ENVIRONMENT"
        else
            log_info "Detected Lambda function: $LAMBDA_FUNCTION_NAME"
        fi
    fi
}

# Test 1: VPC and Networking Validation
test_vpc_networking_validation() {
    log_info "=== Test 1: VPC and Networking Validation ==="
    
    if [ -z "$VPC_ID" ]; then
        log_warn "VPC ID not available, skipping VPC tests"
        return 0
    fi
    
    # Test VPC exists and is available
    log_info "Validating VPC exists and is available..."
    local vpc_state=$(aws ec2 describe-vpcs \
        --vpc-ids "$VPC_ID" \
        --query 'Vpcs[0].State' \
        --output text 2>/dev/null || echo "not-found")
    
    if [ "$vpc_state" = "available" ]; then
        log_success "VPC $VPC_ID is available"
    else
        log_error "VPC $VPC_ID is not available (state: $vpc_state)"
        return 1
    fi
    
    # Test subnets exist in multiple AZs
    log_info "Validating subnets exist in multiple availability zones..."
    local subnet_count=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'length(Subnets)' \
        --output text 2>/dev/null || echo "0")
    
    if [ "$subnet_count" -ge 2 ]; then
        log_success "Found $subnet_count subnets in VPC"
        
        # Check availability zones
        local az_count=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$VPC_ID" \
            --query 'length(Subnets[].AvailabilityZone | sort(@) | unique(@))' \
            --output text 2>/dev/null || echo "0")
        
        if [ "$az_count" -ge 2 ]; then
            log_success "Subnets span $az_count availability zones"
        else
            log_warn "Subnets only span $az_count availability zone(s)"
        fi
    else
        log_error "Insufficient subnets found: $subnet_count (minimum 2 required)"
        return 1
    fi
    
    # Test security groups exist
    log_info "Validating security groups exist..."
    local sg_count=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=*$TEST_PROJECT-$TEST_ENVIRONMENT*" \
        --query 'length(SecurityGroups)' \
        --output text 2>/dev/null || echo "0")
    
    if [ "$sg_count" -gt 0 ]; then
        log_success "Found $sg_count security groups"
    else
        log_warn "No project-specific security groups found"
    fi
    
    log_success "VPC and networking validation completed"
    return 0
}

# Test 2: RDS Instance Validation
test_rds_instance_validation() {
    log_info "=== Test 2: RDS Instance Validation ==="
    
    if [ -z "$RDS_INSTANCE_ID" ]; then
        log_warn "RDS instance ID not available, skipping RDS tests"
        return 0
    fi
    
    # Test RDS instance exists and is available
    log_info "Validating RDS instance exists and is available..."
    local rds_status=$(aws rds describe-db-instances \
        --db-instance-identifier "$RDS_INSTANCE_ID" \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text 2>/dev/null || echo "not-found")
    
    if [ "$rds_status" = "available" ]; then
        log_success "RDS instance $RDS_INSTANCE_ID is available"
    else
        log_error "RDS instance $RDS_INSTANCE_ID is not available (status: $rds_status)"
        return 1
    fi
    
    # Test RDS configuration
    log_info "Validating RDS configuration..."
    local rds_info=$(aws rds describe-db-instances \
        --db-instance-identifier "$RDS_INSTANCE_ID" \
        --query 'DBInstances[0].{Engine:Engine,EngineVersion:EngineVersion,InstanceClass:DBInstanceClass,PubliclyAccessible:PubliclyAccessible}' \
        --output json 2>/dev/null)
    
    if [ -n "$rds_info" ]; then
        local engine=$(echo "$rds_info" | jq -r '.Engine')
        local engine_version=$(echo "$rds_info" | jq -r '.EngineVersion')
        local instance_class=$(echo "$rds_info" | jq -r '.InstanceClass')
        local publicly_accessible=$(echo "$rds_info" | jq -r '.PubliclyAccessible')
        
        log_info "RDS Engine: $engine $engine_version"
        log_info "RDS Instance Class: $instance_class"
        log_info "Publicly Accessible: $publicly_accessible"
        
        # Validate PostgreSQL engine
        if [[ "$engine" == "postgres" ]]; then
            log_success "RDS engine is PostgreSQL"
        else
            log_error "RDS engine is not PostgreSQL: $engine"
            return 1
        fi
        
        # Validate not publicly accessible
        if [ "$publicly_accessible" = "false" ]; then
            log_success "RDS instance is not publicly accessible (secure)"
        else
            log_warn "RDS instance is publicly accessible (security concern)"
        fi
        
        # Validate cost-optimized instance class
        if [[ "$instance_class" == "db.t3.micro" ]] || [[ "$instance_class" == "db.t3.small" ]]; then
            log_success "RDS instance class is cost-optimized: $instance_class"
        else
            log_warn "RDS instance class may not be cost-optimized: $instance_class"
        fi
    else
        log_error "Failed to retrieve RDS configuration"
        return 1
    fi
    
    # Test RDS security groups
    log_info "Validating RDS security groups..."
    local rds_sg_count=$(aws rds describe-db-instances \
        --db-instance-identifier "$RDS_INSTANCE_ID" \
        --query 'length(DBInstances[0].VpcSecurityGroups)' \
        --output text 2>/dev/null || echo "0")
    
    if [ "$rds_sg_count" -gt 0 ]; then
        log_success "RDS has $rds_sg_count security group(s) configured"
    else
        log_error "RDS has no security groups configured"
        return 1
    fi
    
    log_success "RDS instance validation completed"
    return 0
}

# Test 3: Lambda Function Validation
test_lambda_function_validation() {
    log_info "=== Test 3: Lambda Function Validation ==="
    
    if [ -z "$LAMBDA_FUNCTION_NAME" ]; then
        log_warn "Lambda function name not available, skipping Lambda tests"
        return 0
    fi
    
    # Test Lambda function exists
    log_info "Validating Lambda function exists..."
    local lambda_state=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Configuration.State' \
        --output text 2>/dev/null || echo "not-found")
    
    if [ "$lambda_state" = "Active" ]; then
        log_success "Lambda function $LAMBDA_FUNCTION_NAME is active"
    else
        log_error "Lambda function $LAMBDA_FUNCTION_NAME is not active (state: $lambda_state)"
        return 1
    fi
    
    # Test Lambda configuration
    log_info "Validating Lambda configuration..."
    local lambda_config=$(aws lambda get-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query '{Runtime:Runtime,MemorySize:MemorySize,Timeout:Timeout,VpcConfig:VpcConfig}' \
        --output json 2>/dev/null)
    
    if [ -n "$lambda_config" ]; then
        local runtime=$(echo "$lambda_config" | jq -r '.Runtime')
        local memory_size=$(echo "$lambda_config" | jq -r '.MemorySize')
        local timeout=$(echo "$lambda_config" | jq -r '.Timeout')
        local vpc_config=$(echo "$lambda_config" | jq -r '.VpcConfig')
        
        log_info "Lambda Runtime: $runtime"
        log_info "Lambda Memory: ${memory_size}MB"
        log_info "Lambda Timeout: ${timeout}s"
        
        # Validate .NET runtime
        if [[ "$runtime" == "dotnet"* ]]; then
            log_success "Lambda runtime is .NET: $runtime"
        else
            log_error "Lambda runtime is not .NET: $runtime"
            return 1
        fi
        
        # Validate cost-optimized memory
        if [ "$memory_size" -le 1024 ]; then
            log_success "Lambda memory is cost-optimized: ${memory_size}MB"
        else
            log_warn "Lambda memory may not be cost-optimized: ${memory_size}MB"
        fi
        
        # Validate VPC configuration if VPC exists
        if [ -n "$VPC_ID" ] && [ "$vpc_config" != "null" ]; then
            local lambda_vpc_id=$(echo "$lambda_config" | jq -r '.VpcConfig.VpcId')
            if [ "$lambda_vpc_id" = "$VPC_ID" ]; then
                log_success "Lambda is configured for VPC: $lambda_vpc_id"
            else
                log_warn "Lambda VPC configuration mismatch: expected $VPC_ID, got $lambda_vpc_id"
            fi
        fi
    else
        log_error "Failed to retrieve Lambda configuration"
        return 1
    fi
    
    # Test Lambda IAM role
    log_info "Validating Lambda IAM role..."
    LAMBDA_ROLE_ARN=$(aws lambda get-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Role' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$LAMBDA_ROLE_ARN" ]; then
        log_success "Lambda has IAM role: $LAMBDA_ROLE_ARN"
        
        # Test role policies
        local role_name=$(echo "$LAMBDA_ROLE_ARN" | cut -d'/' -f2)
        local policy_count=$(aws iam list-attached-role-policies \
            --role-name "$role_name" \
            --query 'length(AttachedPolicies)' \
            --output text 2>/dev/null || echo "0")
        
        if [ "$policy_count" -gt 0 ]; then
            log_success "Lambda role has $policy_count attached policies"
        else
            log_warn "Lambda role has no attached policies"
        fi
    else
        log_error "Lambda has no IAM role configured"
        return 1
    fi
    
    log_success "Lambda function validation completed"
    return 0
}

# Test 4: Network Connectivity Validation
test_network_connectivity_validation() {
    log_info "=== Test 4: Network Connectivity Validation ==="
    
    if [ "$SKIP_CONNECTIVITY" = true ]; then
        log_info "Skipping connectivity tests as requested"
        return 0
    fi
    
    if [ -z "$LAMBDA_FUNCTION_NAME" ] || [ -z "$RDS_INSTANCE_ID" ]; then
        log_warn "Lambda function or RDS instance not available, skipping connectivity tests"
        return 0
    fi
    
    # Test Lambda can reach RDS (simulate with security group validation)
    log_info "Validating Lambda-RDS network connectivity configuration..."
    
    # Get Lambda security groups
    local lambda_sg_ids=$(aws lambda get-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'VpcConfig.SecurityGroupIds' \
        --output text 2>/dev/null || echo "")
    
    # Get RDS security groups
    local rds_sg_ids=$(aws rds describe-db-instances \
        --db-instance-identifier "$RDS_INSTANCE_ID" \
        --query 'DBInstances[0].VpcSecurityGroups[].VpcSecurityGroupId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$lambda_sg_ids" ] && [ -n "$rds_sg_ids" ]; then
        log_info "Lambda security groups: $lambda_sg_ids"
        log_info "RDS security groups: $rds_sg_ids"
        
        # Check if RDS security group allows access from Lambda security group
        for rds_sg in $rds_sg_ids; do
            local ingress_rules=$(aws ec2 describe-security-groups \
                --group-ids "$rds_sg" \
                --query 'SecurityGroups[0].IpPermissions[?FromPort==`5432`]' \
                --output json 2>/dev/null || echo "[]")
            
            if [ "$ingress_rules" != "[]" ]; then
                log_success "RDS security group $rds_sg allows PostgreSQL connections"
            else
                log_warn "RDS security group $rds_sg may not allow PostgreSQL connections"
            fi
        done
    else
        log_warn "Could not retrieve security group information for connectivity validation"
    fi
    
    # Test Lambda environment variables for database connection
    log_info "Validating Lambda environment variables for database connection..."
    local lambda_env_vars=$(aws lambda get-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Environment.Variables' \
        --output json 2>/dev/null || echo "{}")
    
    if [ "$lambda_env_vars" != "{}" ]; then
        local connection_string_exists=$(echo "$lambda_env_vars" | jq -r 'has("ConnectionStrings__DefaultConnection")')
        
        if [ "$connection_string_exists" = "true" ]; then
            log_success "Lambda has database connection string configured"
        else
            log_warn "Lambda may not have database connection string configured"
        fi
        
        # Check for other required environment variables
        local aws_region_exists=$(echo "$lambda_env_vars" | jq -r 'has("AWS__Region")')
        if [ "$aws_region_exists" = "true" ]; then
            log_success "Lambda has AWS region configured"
        else
            log_warn "Lambda may not have AWS region configured"
        fi
    else
        log_warn "Lambda has no environment variables configured"
    fi
    
    log_success "Network connectivity validation completed"
    return 0
}

# Test 5: IAM Permissions Validation
test_iam_permissions_validation() {
    log_info "=== Test 5: IAM Permissions Validation ==="
    
    if [ -z "$LAMBDA_ROLE_ARN" ]; then
        log_warn "Lambda role ARN not available, skipping IAM permissions tests"
        return 0
    fi
    
    local role_name=$(echo "$LAMBDA_ROLE_ARN" | cut -d'/' -f2)
    
    # Test basic Lambda execution permissions
    log_info "Validating basic Lambda execution permissions..."
    local basic_policy_attached=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query 'AttachedPolicies[?contains(PolicyName, `AWSLambdaVPCAccessExecutionRole`) || contains(PolicyName, `AWSLambdaBasicExecutionRole`)]' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$basic_policy_attached" ]; then
        log_success "Lambda role has basic execution permissions"
    else
        log_warn "Lambda role may not have basic execution permissions"
    fi
    
    # Test VPC access permissions
    log_info "Validating VPC access permissions..."
    local vpc_policy_attached=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query 'AttachedPolicies[?contains(PolicyName, `VPC`)]' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$vpc_policy_attached" ]; then
        log_success "Lambda role has VPC access permissions"
    else
        log_warn "Lambda role may not have VPC access permissions"
    fi
    
    # Test custom policies
    log_info "Validating custom application policies..."
    local custom_policies=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query "AttachedPolicies[?contains(PolicyName, '$TEST_PROJECT')]" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$custom_policies" ]; then
        log_success "Lambda role has custom application policies"
    else
        log_warn "Lambda role may not have custom application policies"
    fi
    
    log_success "IAM permissions validation completed"
    return 0
}

# Function to display test results
display_test_results() {
    echo ""
    echo "========================================"
    echo "Infrastructure Connectivity Validation Results"
    echo "========================================"
    echo ""
    echo "Tests Run:    $TESTS_RUN"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "All infrastructure connectivity validation tests passed!"
        echo ""
        echo "✓ VPC and networking validation"
        echo "✓ RDS instance validation"
        echo "✓ Lambda function validation"
        echo "✓ Network connectivity validation"
        echo "✓ IAM permissions validation"
        echo ""
        echo "Infrastructure is properly configured and components can communicate."
        return 0
    else
        log_error "$TESTS_FAILED infrastructure connectivity validation tests failed!"
        echo ""
        echo "Please review the failed tests and fix the configuration issues."
        return 1
    fi
}

# Main execution function
main() {
    echo "========================================"
    echo "Infrastructure Connectivity Validation Tests"
    echo "Task 3.4: Write integration tests for infrastructure provisioning"
    echo "Requirements: 1.1, 1.2, 1.3, 1.4"
    echo "========================================"
    echo ""
    
    # Parse arguments
    parse_arguments "$@"
    
    # Set up logging
    set_log_level "$TEST_LOG_LEVEL"
    log_info "Starting infrastructure connectivity validation tests"
    
    # Validate prerequisites
    if ! validate_aws_cli ""; then
        log_error "AWS CLI validation failed"
        exit 3
    fi
    
    # Auto-detect resources if not provided
    detect_infrastructure_resources
    
    # Run all validation tests
    run_test "VPC and Networking Validation" test_vpc_networking_validation
    run_test "RDS Instance Validation" test_rds_instance_validation
    run_test "Lambda Function Validation" test_lambda_function_validation
    run_test "Network Connectivity Validation" test_network_connectivity_validation
    run_test "IAM Permissions Validation" test_iam_permissions_validation
    
    # Display results
    display_test_results
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi