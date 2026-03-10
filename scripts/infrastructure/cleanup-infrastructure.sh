#!/bin/bash

# Infrastructure Cleanup Script
# Removes all AWS resources created by the deployment automation system
# Implements comprehensive resource removal with rollback capabilities
# Provides partial deployment recovery and cleanup options

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILITIES_DIR="$SCRIPT_DIR/../utilities"
source "$UTILITIES_DIR/logging.sh"
source "$UTILITIES_DIR/error-handling.sh"
source "$UTILITIES_DIR/validate-aws-cli.sh"

# Configuration variables
ENVIRONMENT="${ENVIRONMENT:-dev}"
PROJECT_NAME="${PROJECT_NAME:-myragapp}"
FORCE_CLEANUP="${FORCE_CLEANUP:-false}"
DRY_RUN="${DRY_RUN:-false}"
CLEANUP_SCOPE="${CLEANUP_SCOPE:-all}"  # all, lambda, rds, iam, vpc

# Resource naming patterns
VPC_NAME="$PROJECT_NAME-$ENVIRONMENT-vpc"
SUBNET_NAME_1="$PROJECT_NAME-$ENVIRONMENT-subnet-1"
SUBNET_NAME_2="$PROJECT_NAME-$ENVIRONMENT-subnet-2"
DB_SUBNET_GROUP_NAME="$PROJECT_NAME-$ENVIRONMENT-db-subnet-group"
SECURITY_GROUP_NAME="$PROJECT_NAME-$ENVIRONMENT-rds-sg"
DB_INSTANCE_IDENTIFIER="$PROJECT_NAME-$ENVIRONMENT-db"
LAMBDA_FUNCTION_NAME="$PROJECT_NAME-$ENVIRONMENT-api"
LAMBDA_ROLE_NAME="$PROJECT_NAME-$ENVIRONMENT-lambda-execution-role"
LAMBDA_POLICY_NAME="$PROJECT_NAME-$ENVIRONMENT-lambda-policy"

# Global variables for tracking cleanup progress
CLEANUP_PROGRESS=()
CLEANUP_ERRORS=()
RESOURCES_TO_CLEANUP=()

# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Removes AWS infrastructure resources created by the deployment system.

OPTIONS:
    --environment ENV          Environment name (default: dev)
    --project-name NAME        Project name (default: myapp)
    --aws-profile PROFILE      AWS profile to use
    --force                    Skip confirmation prompts
    --dry-run                  Show what would be deleted without actually deleting
    --scope SCOPE              Cleanup scope: all, lambda, rds, iam, vpc (default: all)
    --help                     Show this help message

EXAMPLES:
    $0 --environment production --force
    $0 --dry-run --scope lambda
    $0 --project-name myapp --environment staging

EOF
}
# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --project-name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --aws-profile)
                export AWS_PROFILE="$2"
                shift 2
                ;;
            --force)
                FORCE_CLEANUP="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --scope)
                CLEANUP_SCOPE="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Update resource names based on parsed arguments
    VPC_NAME="$PROJECT_NAME-$ENVIRONMENT-vpc"
    SUBNET_NAME_1="$PROJECT_NAME-$ENVIRONMENT-subnet-1"
    SUBNET_NAME_2="$PROJECT_NAME-$ENVIRONMENT-subnet-2"
    DB_SUBNET_GROUP_NAME="$PROJECT_NAME-$ENVIRONMENT-db-subnet-group"
    SECURITY_GROUP_NAME="$PROJECT_NAME-$ENVIRONMENT-rds-sg"
    DB_INSTANCE_IDENTIFIER="$PROJECT_NAME-$ENVIRONMENT-db"
    LAMBDA_FUNCTION_NAME="$PROJECT_NAME-$ENVIRONMENT-api"
    LAMBDA_ROLE_NAME="$PROJECT_NAME-$ENVIRONMENT-lambda-execution-role"
    LAMBDA_POLICY_NAME="$PROJECT_NAME-$ENVIRONMENT-lambda-policy"
}

# Function to validate cleanup scope
validate_cleanup_scope() {
    case "$CLEANUP_SCOPE" in
        all|lambda|rds|iam|vpc)
            log_info "Cleanup scope: $CLEANUP_SCOPE"
            ;;
        *)
            set_error_context "Cleanup scope validation"
            set_error_remediation "Use a valid cleanup scope: all, lambda, rds, iam, vpc"
            handle_error $ERROR_CODE_VALIDATION "Invalid cleanup scope: $CLEANUP_SCOPE" true
            ;;
    esac
}

# Function to discover existing resources
discover_resources() {
    log_info "Discovering existing resources for cleanup..."
    
    set_error_context "Resource discovery"
    set_error_remediation "Check AWS credentials and permissions"
    
    # Discover Lambda functions
    if [[ "$CLEANUP_SCOPE" == "all" || "$CLEANUP_SCOPE" == "lambda" ]]; then
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
            RESOURCES_TO_CLEANUP+=("lambda:$LAMBDA_FUNCTION_NAME")
            log_info "Found Lambda function: $LAMBDA_FUNCTION_NAME"
        fi
    fi
    
    # Discover RDS instances
    if [[ "$CLEANUP_SCOPE" == "all" || "$CLEANUP_SCOPE" == "rds" ]]; then
        if aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" &>/dev/null; then
            RESOURCES_TO_CLEANUP+=("rds:$DB_INSTANCE_IDENTIFIER")
            log_info "Found RDS instance: $DB_INSTANCE_IDENTIFIER"
        fi
        
        # Check for DB subnet group
        if aws rds describe-db-subnet-groups --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" &>/dev/null; then
            RESOURCES_TO_CLEANUP+=("db-subnet-group:$DB_SUBNET_GROUP_NAME")
            log_info "Found DB subnet group: $DB_SUBNET_GROUP_NAME"
        fi
    fi
    
    # Discover IAM resources
    if [[ "$CLEANUP_SCOPE" == "all" || "$CLEANUP_SCOPE" == "iam" ]]; then
        if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
            RESOURCES_TO_CLEANUP+=("iam-role:$LAMBDA_ROLE_NAME")
            log_info "Found IAM role: $LAMBDA_ROLE_NAME"
        fi
        
        # Check for attached policies
        local policies=("$LAMBDA_POLICY_NAME" "$PROJECT_NAME-$ENVIRONMENT-cognito-policy" "$PROJECT_NAME-$ENVIRONMENT-rds-policy")
        for policy in "${policies[@]}"; do
            local policy_arn="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/$policy"
            if aws iam get-policy --policy-arn "$policy_arn" &>/dev/null; then
                RESOURCES_TO_CLEANUP+=("iam-policy:$policy_arn")
                log_info "Found IAM policy: $policy"
            fi
        done
    fi
    
    # Discover VPC resources
    if [[ "$CLEANUP_SCOPE" == "all" || "$CLEANUP_SCOPE" == "vpc" ]]; then
        local vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "None")
        if [[ "$vpc_id" != "None" && "$vpc_id" != "null" ]]; then
            RESOURCES_TO_CLEANUP+=("vpc:$vpc_id")
            log_info "Found VPC: $vpc_id ($VPC_NAME)"
            
            # Find associated subnets
            local subnet_ids=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query "Subnets[].SubnetId" --output text 2>/dev/null || echo "")
            for subnet_id in $subnet_ids; do
                RESOURCES_TO_CLEANUP+=("subnet:$subnet_id")
                log_info "Found subnet: $subnet_id"
            done
            
            # Find security groups (excluding default)
            local sg_ids=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" "Name=group-name,Values=!default" --query "SecurityGroups[].GroupId" --output text 2>/dev/null || echo "")
            for sg_id in $sg_ids; do
                RESOURCES_TO_CLEANUP+=("security-group:$sg_id")
                log_info "Found security group: $sg_id"
            done
            
            # Find internet gateway
            local igw_id=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" --query "InternetGateways[0].InternetGatewayId" --output text 2>/dev/null || echo "None")
            if [[ "$igw_id" != "None" && "$igw_id" != "null" ]]; then
                RESOURCES_TO_CLEANUP+=("internet-gateway:$igw_id")
                log_info "Found internet gateway: $igw_id"
            fi
            
            # Find route tables (excluding main)
            local rt_ids=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" --query "RouteTables[?Associations[0].Main!=\`true\`].RouteTableId" --output text 2>/dev/null || echo "")
            for rt_id in $rt_ids; do
                RESOURCES_TO_CLEANUP+=("route-table:$rt_id")
                log_info "Found route table: $rt_id"
            done
        fi
    fi
    
    log_info "Resource discovery completed. Found ${#RESOURCES_TO_CLEANUP[@]} resources to cleanup."
}

# Function to confirm cleanup operation
confirm_cleanup() {
    if [[ "$FORCE_CLEANUP" == "true" ]]; then
        log_info "Force cleanup enabled - skipping confirmation"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run mode - no resources will be deleted"
        return 0
    fi
    
    echo ""
    log_warn "WARNING: This will permanently delete the following AWS resources:"
    echo ""
    
    for resource in "${RESOURCES_TO_CLEANUP[@]}"; do
        echo "  - $resource"
    done
    
    echo ""
    log_warn "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Cleanup confirmed by user"
}
# Function to cleanup Lambda resources
cleanup_lambda_resources() {
    log_info "Cleaning up Lambda resources..."
    
    for resource in "${RESOURCES_TO_CLEANUP[@]}"; do
        if [[ "$resource" == lambda:* ]]; then
            local function_name="${resource#lambda:}"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete Lambda function: $function_name"
                continue
            fi
            
            set_error_context "Lambda function cleanup: $function_name"
            set_error_remediation "Check Lambda function status and dependencies"
            
            log_info "Deleting Lambda function: $function_name"
            if aws lambda delete-function --function-name "$function_name" 2>/dev/null; then
                CLEANUP_PROGRESS+=("lambda:$function_name:success")
                log_success "Deleted Lambda function: $function_name"
            else
                CLEANUP_ERRORS+=("lambda:$function_name:failed")
                log_error "Failed to delete Lambda function: $function_name"
            fi
        fi
    done
}

# Function to cleanup RDS resources
cleanup_rds_resources() {
    log_info "Cleaning up RDS resources..."
    
    for resource in "${RESOURCES_TO_CLEANUP[@]}"; do
        if [[ "$resource" == rds:* ]]; then
            local db_identifier="${resource#rds:}"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete RDS instance: $db_identifier"
                continue
            fi
            
            set_error_context "RDS instance cleanup: $db_identifier"
            set_error_remediation "Check RDS instance status and delete protection settings"
            
            log_info "Deleting RDS instance: $db_identifier (this may take several minutes)"
            if aws rds delete-db-instance \
                --db-instance-identifier "$db_identifier" \
                --skip-final-snapshot \
                --delete-automated-backups 2>/dev/null; then
                
                log_info "RDS deletion initiated. Waiting for completion..."
                
                # Wait for RDS instance to be deleted (with timeout)
                local timeout=1800  # 30 minutes
                local elapsed=0
                local interval=30
                
                while [ $elapsed -lt $timeout ]; do
                    if ! aws rds describe-db-instances --db-instance-identifier "$db_identifier" &>/dev/null; then
                        CLEANUP_PROGRESS+=("rds:$db_identifier:success")
                        log_success "RDS instance deleted: $db_identifier"
                        break
                    fi
                    
                    log_info "Waiting for RDS deletion... (${elapsed}s elapsed)"
                    sleep $interval
                    elapsed=$((elapsed + interval))
                done
                
                if [ $elapsed -ge $timeout ]; then
                    CLEANUP_ERRORS+=("rds:$db_identifier:timeout")
                    log_error "RDS deletion timed out: $db_identifier"
                fi
            else
                CLEANUP_ERRORS+=("rds:$db_identifier:failed")
                log_error "Failed to initiate RDS deletion: $db_identifier"
            fi
        elif [[ "$resource" == db-subnet-group:* ]]; then
            local subnet_group_name="${resource#db-subnet-group:}"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete DB subnet group: $subnet_group_name"
                continue
            fi
            
            set_error_context "DB subnet group cleanup: $subnet_group_name"
            set_error_remediation "Ensure all RDS instances using this subnet group are deleted first"
            
            log_info "Deleting DB subnet group: $subnet_group_name"
            if aws rds delete-db-subnet-group --db-subnet-group-name "$subnet_group_name" 2>/dev/null; then
                CLEANUP_PROGRESS+=("db-subnet-group:$subnet_group_name:success")
                log_success "Deleted DB subnet group: $subnet_group_name"
            else
                CLEANUP_ERRORS+=("db-subnet-group:$subnet_group_name:failed")
                log_error "Failed to delete DB subnet group: $subnet_group_name"
            fi
        fi
    done
}
# Function to cleanup IAM resources
cleanup_iam_resources() {
    log_info "Cleaning up IAM resources..."
    
    # First detach and delete policies, then delete roles
    for resource in "${RESOURCES_TO_CLEANUP[@]}"; do
        if [[ "$resource" == iam-policy:* ]]; then
            local policy_arn="${resource#iam-policy:}"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete IAM policy: $policy_arn"
                continue
            fi
            
            set_error_context "IAM policy cleanup: $policy_arn"
            set_error_remediation "Check policy attachments and dependencies"
            
            # Detach policy from all entities first
            log_info "Detaching IAM policy from entities: $policy_arn"
            
            # Detach from roles
            local attached_roles=$(aws iam list-entities-for-policy --policy-arn "$policy_arn" --query "PolicyRoles[].RoleName" --output text 2>/dev/null || echo "")
            for role in $attached_roles; do
                log_info "Detaching policy from role: $role"
                aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn" 2>/dev/null || true
            done
            
            # Delete policy
            log_info "Deleting IAM policy: $policy_arn"
            if aws iam delete-policy --policy-arn "$policy_arn" 2>/dev/null; then
                CLEANUP_PROGRESS+=("iam-policy:$policy_arn:success")
                log_success "Deleted IAM policy: $policy_arn"
            else
                CLEANUP_ERRORS+=("iam-policy:$policy_arn:failed")
                log_error "Failed to delete IAM policy: $policy_arn"
            fi
        fi
    done
    
    # Delete roles
    for resource in "${RESOURCES_TO_CLEANUP[@]}"; do
        if [[ "$resource" == iam-role:* ]]; then
            local role_name="${resource#iam-role:}"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete IAM role: $role_name"
                continue
            fi
            
            set_error_context "IAM role cleanup: $role_name"
            set_error_remediation "Check role attachments and instance profiles"
            
            # Detach all managed policies from role
            log_info "Detaching managed policies from role: $role_name"
            local attached_policies=$(aws iam list-attached-role-policies --role-name "$role_name" --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null || echo "")
            for policy_arn in $attached_policies; do
                log_info "Detaching policy: $policy_arn"
                aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" 2>/dev/null || true
            done
            
            # Delete inline policies
            local inline_policies=$(aws iam list-role-policies --role-name "$role_name" --query "PolicyNames" --output text 2>/dev/null || echo "")
            for policy_name in $inline_policies; do
                log_info "Deleting inline policy: $policy_name"
                aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" 2>/dev/null || true
            done
            
            # Delete role
            log_info "Deleting IAM role: $role_name"
            if aws iam delete-role --role-name "$role_name" 2>/dev/null; then
                CLEANUP_PROGRESS+=("iam-role:$role_name:success")
                log_success "Deleted IAM role: $role_name"
            else
                CLEANUP_ERRORS+=("iam-role:$role_name:failed")
                log_error "Failed to delete IAM role: $role_name"
            fi
        fi
    done
}
# Function to cleanup VPC resources
cleanup_vpc_resources() {
    log_info "Cleaning up VPC resources..."
    
    # Delete resources in correct order: route tables, subnets, security groups, internet gateway, VPC
    
    # Delete route tables (non-main)
    for resource in "${RESOURCES_TO_CLEANUP[@]}"; do
        if [[ "$resource" == route-table:* ]]; then
            local rt_id="${resource#route-table:}"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete route table: $rt_id"
                continue
            fi
            
            set_error_context "Route table cleanup: $rt_id"
            set_error_remediation "Check route table associations and dependencies"
            
            log_info "Deleting route table: $rt_id"
            if aws ec2 delete-route-table --route-table-id "$rt_id" 2>/dev/null; then
                CLEANUP_PROGRESS+=("route-table:$rt_id:success")
                log_success "Deleted route table: $rt_id"
            else
                CLEANUP_ERRORS+=("route-table:$rt_id:failed")
                log_error "Failed to delete route table: $rt_id"
            fi
        fi
    done
    
    # Delete subnets
    for resource in "${RESOURCES_TO_CLEANUP[@]}"; do
        if [[ "$resource" == subnet:* ]]; then
            local subnet_id="${resource#subnet:}"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete subnet: $subnet_id"
                continue
            fi
            
            set_error_context "Subnet cleanup: $subnet_id"
            set_error_remediation "Check subnet dependencies and running instances"
            
            log_info "Deleting subnet: $subnet_id"
            if aws ec2 delete-subnet --subnet-id "$subnet_id" 2>/dev/null; then
                CLEANUP_PROGRESS+=("subnet:$subnet_id:success")
                log_success "Deleted subnet: $subnet_id"
            else
                CLEANUP_ERRORS+=("subnet:$subnet_id:failed")
                log_error "Failed to delete subnet: $subnet_id"
            fi
        fi
    done
    
    # Delete security groups
    for resource in "${RESOURCES_TO_CLEANUP[@]}"; do
        if [[ "$resource" == security-group:* ]]; then
            local sg_id="${resource#security-group:}"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete security group: $sg_id"
                continue
            fi
            
            set_error_context "Security group cleanup: $sg_id"
            set_error_remediation "Check security group dependencies and attached resources"
            
            log_info "Deleting security group: $sg_id"
            if aws ec2 delete-security-group --group-id "$sg_id" 2>/dev/null; then
                CLEANUP_PROGRESS+=("security-group:$sg_id:success")
                log_success "Deleted security group: $sg_id"
            else
                CLEANUP_ERRORS+=("security-group:$sg_id:failed")
                log_error "Failed to delete security group: $sg_id"
            fi
        fi
    done
    
    # Detach and delete internet gateway
    for resource in "${RESOURCES_TO_CLEANUP[@]}"; do
        if [[ "$resource" == internet-gateway:* ]]; then
            local igw_id="${resource#internet-gateway:}"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete internet gateway: $igw_id"
                continue
            fi
            
            set_error_context "Internet gateway cleanup: $igw_id"
            set_error_remediation "Check internet gateway attachments"
            
            # Find VPC ID for detachment
            local vpc_id=$(aws ec2 describe-internet-gateways --internet-gateway-ids "$igw_id" --query "InternetGateways[0].Attachments[0].VpcId" --output text 2>/dev/null || echo "None")
            
            if [[ "$vpc_id" != "None" && "$vpc_id" != "null" ]]; then
                log_info "Detaching internet gateway from VPC: $igw_id -> $vpc_id"
                aws ec2 detach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" 2>/dev/null || true
            fi
            
            log_info "Deleting internet gateway: $igw_id"
            if aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" 2>/dev/null; then
                CLEANUP_PROGRESS+=("internet-gateway:$igw_id:success")
                log_success "Deleted internet gateway: $igw_id"
            else
                CLEANUP_ERRORS+=("internet-gateway:$igw_id:failed")
                log_error "Failed to delete internet gateway: $igw_id"
            fi
        fi
    done
    # Delete VPC
    for resource in "${RESOURCES_TO_CLEANUP[@]}"; do
        if [[ "$resource" == vpc:* ]]; then
            local vpc_id="${resource#vpc:}"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete VPC: $vpc_id"
                continue
            fi
            
            set_error_context "VPC cleanup: $vpc_id"
            set_error_remediation "Ensure all VPC dependencies are removed first"
            
            log_info "Deleting VPC: $vpc_id"
            if aws ec2 delete-vpc --vpc-id "$vpc_id" 2>/dev/null; then
                CLEANUP_PROGRESS+=("vpc:$vpc_id:success")
                log_success "Deleted VPC: $vpc_id"
            else
                CLEANUP_ERRORS+=("vpc:$vpc_id:failed")
                log_error "Failed to delete VPC: $vpc_id"
            fi
        fi
    done
}

# Function to execute cleanup based on scope
execute_cleanup() {
    log_info "Starting infrastructure cleanup..."
    
    # Initialize error logging
    initialize_error_logging
    
    # Create cleanup checkpoint
    create_checkpoint "cleanup_start" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    case "$CLEANUP_SCOPE" in
        all)
            cleanup_lambda_resources
            cleanup_rds_resources
            cleanup_iam_resources
            cleanup_vpc_resources
            ;;
        lambda)
            cleanup_lambda_resources
            ;;
        rds)
            cleanup_rds_resources
            ;;
        iam)
            cleanup_iam_resources
            ;;
        vpc)
            cleanup_vpc_resources
            ;;
    esac
    
    # Create completion checkpoint
    create_checkpoint "cleanup_complete" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# Function to generate cleanup report
generate_cleanup_report() {
    log_info "Generating cleanup report..."
    
    local total_resources=${#RESOURCES_TO_CLEANUP[@]}
    local successful_cleanups=${#CLEANUP_PROGRESS[@]}
    local failed_cleanups=${#CLEANUP_ERRORS[@]}
    
    echo ""
    log_info "=== CLEANUP REPORT ==="
    log_info "Total resources identified: $total_resources"
    log_info "Successfully cleaned up: $successful_cleanups"
    log_info "Failed cleanups: $failed_cleanups"
    
    if [ ${#CLEANUP_PROGRESS[@]} -gt 0 ]; then
        echo ""
        log_success "Successfully cleaned up resources:"
        for progress in "${CLEANUP_PROGRESS[@]}"; do
            echo "  ✓ $progress"
        done
    fi
    
    if [ ${#CLEANUP_ERRORS[@]} -gt 0 ]; then
        echo ""
        log_error "Failed to clean up resources:"
        for error in "${CLEANUP_ERRORS[@]}"; do
            echo "  ✗ $error"
        done
        echo ""
        log_warn "Some resources may require manual cleanup"
        log_info "Check the error log for details: $ERROR_LOG_FILE"
    fi
    
    echo ""
    
    if [ $failed_cleanups -eq 0 ]; then
        log_success "Infrastructure cleanup completed successfully!"
        return 0
    else
        log_error "Infrastructure cleanup completed with errors"
        return 1
    fi
}
# Function to handle cleanup rollback (restore accidentally deleted resources)
rollback_cleanup() {
    log_warn "Cleanup rollback is not implemented"
    log_info "AWS resources cannot be automatically restored once deleted"
    log_info "You will need to re-run the deployment scripts to recreate infrastructure"
    log_info "Consider using --dry-run option before actual cleanup operations"
}

# Main execution function
main() {
    log_info "Starting AWS Infrastructure Cleanup"
    log_info "Project: $PROJECT_NAME, Environment: $ENVIRONMENT"
    
    # Initialize error handling
    set_error_context "Infrastructure cleanup initialization"
    set_error_remediation "Check script parameters and AWS configuration"
    
    # Validate AWS CLI
    if ! validate_aws_cli; then
        handle_error $ERROR_CODE_AWS_CLI "AWS CLI validation failed" true
    fi
    
    # Validate cleanup scope
    validate_cleanup_scope
    
    # Discover resources to cleanup
    discover_resources
    
    if [ ${#RESOURCES_TO_CLEANUP[@]} -eq 0 ]; then
        log_info "No resources found for cleanup"
        log_success "Nothing to clean up - infrastructure may already be removed"
        exit 0
    fi
    
    # Confirm cleanup operation
    confirm_cleanup
    
    # Execute cleanup
    execute_cleanup
    
    # Generate report
    if generate_cleanup_report; then
        exit 0
    else
        exit $ERROR_CODE_CLEANUP
    fi
}

# Register cleanup function for error handling
register_cleanup_function cleanup_checkpoints

# Parse command line arguments
parse_arguments "$@"

# Execute main function
main