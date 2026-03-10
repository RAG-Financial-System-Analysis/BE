#!/bin/bash

# IAM Roles and Policies Configuration Script
# Creates comprehensive IAM roles and policies for AWS deployment automation
# Implements Lambda execution roles, Cognito access, RDS permissions, and Secrets Manager access
# Follows principle of least privilege security with cross-service integration

set -euo pipefail

# Initialize AWS_PROFILE with default value if not set
AWS_PROFILE="${AWS_PROFILE:-}"

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILITIES_DIR="$SCRIPT_DIR/../utilities"
source "$UTILITIES_DIR/logging.sh"
source "$UTILITIES_DIR/error-handling.sh"
source "$UTILITIES_DIR/validate-aws-cli.sh"

# Configuration variables
ENVIRONMENT="${ENVIRONMENT:-dev}"
PROJECT_NAME="${PROJECT_NAME:-myragapp}"

# IAM resource naming
LAMBDA_ROLE_NAME="$PROJECT_NAME-$ENVIRONMENT-lambda-execution-role"
LAMBDA_POLICY_NAME="$PROJECT_NAME-$ENVIRONMENT-lambda-policy"
COGNITO_POLICY_NAME="$PROJECT_NAME-$ENVIRONMENT-cognito-policy"
RDS_POLICY_NAME="$PROJECT_NAME-$ENVIRONMENT-rds-policy"
SECRETS_POLICY_NAME="$PROJECT_NAME-$ENVIRONMENT-secrets-policy"

# Global variables for resource tracking
LAMBDA_ROLE_ARN=""
LAMBDA_POLICY_ARN=""
COGNITO_POLICY_ARN=""
RDS_POLICY_ARN=""
SECRETS_POLICY_ARN=""
AWS_ACCOUNT_ID=""
AWS_REGION=""

# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Creates comprehensive IAM roles and policies for AWS deployment automation.

OPTIONS:
    --environment ENV          Environment name (default: dev)
    --project-name NAME        Project name (default: myapp)
    --aws-profile PROFILE      AWS profile to use
    --cognito-user-pool-id ID  Cognito User Pool ID for specific permissions
    --rds-instance-id ID       RDS instance identifier for specific permissions
    --secrets-prefix PREFIX    Secrets Manager prefix for scoped access
    --help                     Show this help message

EXAMPLES:
    $0 --environment production --project-name webapp
    $0 --cognito-user-pool-id us-east-1_ABC123 --rds-instance-id myapp-prod-db
    $0 --aws-profile prod --secrets-prefix /myapp/prod/

SECURITY FEATURES:
    - Principle of least privilege IAM policies
    - Resource-specific permissions where possible
    - Comprehensive logging and monitoring permissions
    - Cross-service integration support
    - Secure credential handling via Secrets Manager

CREATED RESOURCES:
    - Lambda execution role with comprehensive permissions
    - Cognito integration policy for authentication
    - RDS access policy for database operations
    - Secrets Manager policy for secure credentials
    - CloudWatch logging permissions

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
                AWS_PROFILE="$2"
                export AWS_PROFILE
                shift 2
                ;;
            --cognito-user-pool-id)
                COGNITO_USER_POOL_ID="$2"
                shift 2
                ;;
            --rds-instance-id)
                RDS_INSTANCE_ID="$2"
                shift 2
                ;;
            --secrets-prefix)
                SECRETS_PREFIX="$2"
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
    
    # Update resource names after parsing arguments
    LAMBDA_ROLE_NAME="$PROJECT_NAME-$ENVIRONMENT-lambda-execution-role"
    LAMBDA_POLICY_NAME="$PROJECT_NAME-$ENVIRONMENT-lambda-policy"
    COGNITO_POLICY_NAME="$PROJECT_NAME-$ENVIRONMENT-cognito-policy"
    RDS_POLICY_NAME="$PROJECT_NAME-$ENVIRONMENT-rds-policy"
    SECRETS_POLICY_NAME="$PROJECT_NAME-$ENVIRONMENT-secrets-policy"
}

# Function to get AWS account information
get_aws_account_info() {
    log_info "Retrieving AWS account information"
    
    set_error_context "AWS account information retrieval"
    set_error_remediation "Check AWS CLI configuration and credentials"
    
    AWS_ACCOUNT_ID=$(execute_with_error_handling \
        "aws sts get-caller-identity --query Account --output text" \
        "Failed to get AWS account ID" \
        $ERROR_CODE_AWS_CREDENTIALS)
    
    # Use flexible region detection
    source "$SCRIPT_DIR/../utilities/validate-aws-cli.sh"
    AWS_REGION=$(get_aws_region)
    
    log_success "AWS Account ID: $AWS_ACCOUNT_ID"
    log_success "AWS Region: $AWS_REGION"
}

# Function to create Lambda trust policy document
create_lambda_trust_policy() {
    cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
}

# Function to create comprehensive Lambda execution policy
create_lambda_execution_policy() {
    local vpc_permissions=""
    local rds_resource=""
    local cognito_resource=""
    local secrets_resource=""
    
    # Add VPC permissions for Lambda in VPC
    vpc_permissions='{
            "Effect": "Allow",
            "Action": [
                "ec2:CreateNetworkInterface",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DeleteNetworkInterface",
                "ec2:AttachNetworkInterface",
                "ec2:DetachNetworkInterface"
            ],
            "Resource": "*"
        },'
    
    # Configure resource-specific ARNs if provided
    if [ -n "${RDS_INSTANCE_ID:-}" ]; then
        rds_resource="arn:aws:rds:$AWS_REGION:$AWS_ACCOUNT_ID:db:$RDS_INSTANCE_ID"
    else
        rds_resource="arn:aws:rds:$AWS_REGION:$AWS_ACCOUNT_ID:db:$PROJECT_NAME-$ENVIRONMENT-*"
    fi
    
    if [ -n "${COGNITO_USER_POOL_ID:-}" ]; then
        cognito_resource="arn:aws:cognito-idp:$AWS_REGION:$AWS_ACCOUNT_ID:userpool/$COGNITO_USER_POOL_ID"
    else
        cognito_resource="arn:aws:cognito-idp:$AWS_REGION:$AWS_ACCOUNT_ID:userpool/*"
    fi
    
    if [ -n "${SECRETS_PREFIX:-}" ]; then
        secrets_resource="arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT_ID:secret:${SECRETS_PREFIX}*"
    else
        secrets_resource="arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT_ID:secret:/$PROJECT_NAME/$ENVIRONMENT/*"
    fi
    
    cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams"
            ],
            "Resource": [
                "arn:aws:logs:$AWS_REGION:$AWS_ACCOUNT_ID:log-group:/aws/lambda/$PROJECT_NAME-$ENVIRONMENT-*",
                "arn:aws:logs:$AWS_REGION:$AWS_ACCOUNT_ID:log-group:/aws/lambda/$PROJECT_NAME-$ENVIRONMENT-*:*"
            ]
        },
        $vpc_permissions
        {
            "Effect": "Allow",
            "Action": [
                "xray:PutTraceSegments",
                "xray:PutTelemetryRecords"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

# Function to create Cognito integration policy
create_cognito_policy() {
    local cognito_resource=""
    
    if [ -n "${COGNITO_USER_POOL_ID:-}" ]; then
        cognito_resource="arn:aws:cognito-idp:$AWS_REGION:$AWS_ACCOUNT_ID:userpool/$COGNITO_USER_POOL_ID"
    else
        cognito_resource="arn:aws:cognito-idp:$AWS_REGION:$AWS_ACCOUNT_ID:userpool/*"
    fi
    
    cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cognito-idp:AdminGetUser",
                "cognito-idp:AdminCreateUser",
                "cognito-idp:AdminSetUserPassword",
                "cognito-idp:AdminUpdateUserAttributes",
                "cognito-idp:AdminDeleteUser",
                "cognito-idp:AdminEnableUser",
                "cognito-idp:AdminDisableUser",
                "cognito-idp:ListUsers",
                "cognito-idp:AdminListGroupsForUser",
                "cognito-idp:AdminAddUserToGroup",
                "cognito-idp:AdminRemoveUserFromGroup",
                "cognito-idp:GetUser",
                "cognito-idp:ChangePassword",
                "cognito-idp:ConfirmForgotPassword",
                "cognito-idp:ForgotPassword",
                "cognito-idp:InitiateAuth",
                "cognito-idp:RespondToAuthChallenge",
                "cognito-idp:ConfirmSignUp",
                "cognito-idp:ResendConfirmationCode"
            ],
            "Resource": "$cognito_resource"
        },
        {
            "Effect": "Allow",
            "Action": [
                "cognito-idp:DescribeUserPool",
                "cognito-idp:DescribeUserPoolClient",
                "cognito-idp:ListUserPools",
                "cognito-idp:ListUserPoolClients"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

# Function to create RDS access policy
create_rds_policy() {
    local rds_resource=""
    
    if [ -n "${RDS_INSTANCE_ID:-}" ]; then
        rds_resource="arn:aws:rds:$AWS_REGION:$AWS_ACCOUNT_ID:db:$RDS_INSTANCE_ID"
    else
        rds_resource="arn:aws:rds:$AWS_REGION:$AWS_ACCOUNT_ID:db:$PROJECT_NAME-$ENVIRONMENT-*"
    fi
    
    cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "rds:DescribeDBInstances",
                "rds:DescribeDBClusters",
                "rds:DescribeDBSubnetGroups",
                "rds:DescribeDBParameterGroups",
                "rds:DescribeDBClusterParameterGroups"
            ],
            "Resource": "$rds_resource"
        },
        {
            "Effect": "Allow",
            "Action": [
                "rds-db:connect"
            ],
            "Resource": [
                "arn:aws:rds-db:$AWS_REGION:$AWS_ACCOUNT_ID:dbuser:$PROJECT_NAME-$ENVIRONMENT-*/*",
                "$rds_resource"
            ]
        }
    ]
}
EOF
}

# Function to create Secrets Manager policy
create_secrets_policy() {
    local secrets_resource=""
    
    if [ -n "${SECRETS_PREFIX:-}" ]; then
        secrets_resource="arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT_ID:secret:${SECRETS_PREFIX}*"
    else
        secrets_resource="arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT_ID:secret:/$PROJECT_NAME/$ENVIRONMENT/*"
    fi
    
    cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": "$secrets_resource"
        },
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:ListSecrets"
            ],
            "Resource": "*",
            "Condition": {
                "StringLike": {
                    "secretsmanager:Name": [
                        "/$PROJECT_NAME/$ENVIRONMENT/*"
                    ]
                }
            }
        }
    ]
}
EOF
}

# Function to check if IAM role exists
check_existing_role() {
    local role_name="$1"
    
    log_info "Checking for existing IAM role: $role_name"
    
    local role_arn=$(aws iam get-role \
        --role-name "$role_name" \
        --query 'Role.Arn' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$role_arn" != "None" ] && [ "$role_arn" != "null" ]; then
        log_info "Found existing IAM role: $role_arn"
        echo "$role_arn"
        return 0
    fi
    
    return 1
}

# Function to check if IAM policy exists
check_existing_policy() {
    local policy_name="$1"
    
    log_debug "Checking for existing IAM policy: $policy_name"
    
    local policy_arn="arn:aws:iam::$AWS_ACCOUNT_ID:policy/$policy_name"
    
    if aws iam get-policy --policy-arn "$policy_arn" &>/dev/null; then
        log_info "Found existing IAM policy: $policy_arn"
        echo "$policy_arn"
        return 0
    fi
    
    return 1
}

# Function to create or update IAM policy
create_or_update_policy() {
    local policy_name="$1"
    local policy_document="$2"
    local policy_description="$3"
    
    local policy_arn="arn:aws:iam::$AWS_ACCOUNT_ID:policy/$policy_name"
    
    if check_existing_policy "$policy_name" &>/dev/null; then
        log_info "Updating existing IAM policy: $policy_name"
        
        # Get current policy version
        local current_version=$(aws iam get-policy \
            --policy-arn "$policy_arn" \
            --query 'Policy.DefaultVersionId' \
            --output text)
        
        # Create new policy version
        local new_version=$(execute_with_error_handling \
            "aws iam create-policy-version --policy-arn $policy_arn --policy-document '$policy_document' --set-as-default --query 'PolicyVersion.VersionId' --output text" \
            "Failed to update IAM policy: $policy_name" \
            $ERROR_CODE_INFRASTRUCTURE)
        
        # Delete old policy version (keep only 2 versions max)
        if [ "$current_version" != "v1" ]; then
            aws iam delete-policy-version \
                --policy-arn "$policy_arn" \
                --version-id "$current_version" &>/dev/null || true
        fi
        
        log_success "Updated IAM policy: $policy_name (version: $new_version)"
    else
        log_info "Creating new IAM policy: $policy_name"
        
        execute_with_error_handling \
            "aws iam create-policy --policy-name $policy_name --policy-document '$policy_document' --description '$policy_description' --tags Key=Environment,Value=$ENVIRONMENT Key=Project,Value=$PROJECT_NAME" \
            "Failed to create IAM policy: $policy_name" \
            $ERROR_CODE_INFRASTRUCTURE
        
        log_success "Created IAM policy: $policy_name"
        register_cleanup_function "cleanup_policy_$policy_name"
    fi
    
    echo "$policy_arn"
}

# Function to create Lambda execution role
create_lambda_execution_role() {
    log_info "Creating Lambda execution role: $LAMBDA_ROLE_NAME"
    
    if LAMBDA_ROLE_ARN=$(check_existing_role "$LAMBDA_ROLE_NAME"); then
        log_info "Using existing Lambda execution role: $LAMBDA_ROLE_ARN"
    else
        set_error_context "Lambda execution role creation"
        set_error_remediation "Check AWS permissions for IAM role operations"
        
        # Create trust policy file
        local trust_policy_file="./lambda-trust-policy.json"
        create_lambda_trust_policy > "$trust_policy_file"
        
        # Create IAM role
        LAMBDA_ROLE_ARN=$(execute_with_error_handling \
            "aws iam create-role --role-name $LAMBDA_ROLE_NAME --assume-role-policy-document file://$trust_policy_file --description 'Lambda execution role for $PROJECT_NAME $ENVIRONMENT' --tags Key=Environment,Value=$ENVIRONMENT Key=Project,Value=$PROJECT_NAME --query 'Role.Arn' --output text" \
            "Failed to create Lambda execution role" \
            $ERROR_CODE_INFRASTRUCTURE)
        
        log_success "Created Lambda execution role: $LAMBDA_ROLE_ARN"
        
        # Clean up temporary file
        rm -f "$trust_policy_file"
        
        register_cleanup_function "cleanup_lambda_role"
        
        # Wait for role to propagate
        log_info "Waiting for IAM role to propagate..."
        sleep 10
    fi
}

# Function to create and attach IAM policies
create_and_attach_policies() {
    log_info "Creating and attaching IAM policies to Lambda role"
    
    # Create Lambda execution policy
    log_info "Creating Lambda execution policy"
    local lambda_policy_doc=$(create_lambda_execution_policy)
    LAMBDA_POLICY_ARN=$(create_or_update_policy "$LAMBDA_POLICY_NAME" "$lambda_policy_doc" "Lambda execution policy for $PROJECT_NAME $ENVIRONMENT")
    
    # Create Cognito integration policy
    log_info "Creating Cognito integration policy"
    local cognito_policy_doc=$(create_cognito_policy)
    COGNITO_POLICY_ARN=$(create_or_update_policy "$COGNITO_POLICY_NAME" "$cognito_policy_doc" "Cognito integration policy for $PROJECT_NAME $ENVIRONMENT")
    
    # Create RDS access policy
    log_info "Creating RDS access policy"
    local rds_policy_doc=$(create_rds_policy)
    RDS_POLICY_ARN=$(create_or_update_policy "$RDS_POLICY_NAME" "$rds_policy_doc" "RDS access policy for $PROJECT_NAME $ENVIRONMENT")
    
    # Create Secrets Manager policy
    log_info "Creating Secrets Manager policy"
    local secrets_policy_doc=$(create_secrets_policy)
    SECRETS_POLICY_ARN=$(create_or_update_policy "$SECRETS_POLICY_NAME" "$secrets_policy_doc" "Secrets Manager policy for $PROJECT_NAME $ENVIRONMENT")
    
    # Attach policies to Lambda role
    log_info "Attaching policies to Lambda execution role"
    
    # Attach custom policies
    for policy_arn in "$LAMBDA_POLICY_ARN" "$COGNITO_POLICY_ARN" "$RDS_POLICY_ARN" "$SECRETS_POLICY_ARN"; do
        if ! aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE_NAME" --query "AttachedPolicies[?PolicyArn=='$policy_arn']" --output text | grep -q "$policy_arn"; then
            execute_with_error_handling \
                "aws iam attach-role-policy --role-name $LAMBDA_ROLE_NAME --policy-arn $policy_arn" \
                "Failed to attach policy to Lambda role: $policy_arn" \
                $ERROR_CODE_INFRASTRUCTURE
            log_success "Attached policy to Lambda role: $(basename $policy_arn)"
        else
            log_info "Policy already attached: $(basename $policy_arn)"
        fi
    done
    
    # Attach AWS managed policies
    local managed_policies=(
        "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
        "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
    )
    
    for policy_arn in "${managed_policies[@]}"; do
        if ! aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE_NAME" --query "AttachedPolicies[?PolicyArn=='$policy_arn']" --output text | grep -q "$policy_arn"; then
            execute_with_error_handling \
                "aws iam attach-role-policy --role-name $LAMBDA_ROLE_NAME --policy-arn $policy_arn" \
                "Failed to attach managed policy to Lambda role: $policy_arn" \
                $ERROR_CODE_INFRASTRUCTURE
            log_success "Attached managed policy: $(basename $policy_arn)"
        else
            log_info "Managed policy already attached: $(basename $policy_arn)"
        fi
    done
    
    log_success "All policies attached to Lambda execution role"
}

# Function to validate IAM configuration
validate_iam_configuration() {
    log_info "Validating IAM configuration"
    
    # Check role exists and is assumable
    if ! aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
        handle_error $ERROR_CODE_VALIDATION "Lambda execution role not found: $LAMBDA_ROLE_NAME" true
    fi
    
    # Check policies are attached
    local attached_policies=$(aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text)
    
    local required_policies=("$LAMBDA_POLICY_ARN" "$COGNITO_POLICY_ARN" "$RDS_POLICY_ARN" "$SECRETS_POLICY_ARN")
    
    for policy_arn in "${required_policies[@]}"; do
        if ! echo "$attached_policies" | grep -q "$policy_arn"; then
            handle_error $ERROR_CODE_VALIDATION "Required policy not attached: $policy_arn" true
        fi
    done
    
    log_success "IAM configuration validation completed"
}

# Cleanup functions for rollback
cleanup_lambda_role() {
    if [ -n "$LAMBDA_ROLE_NAME" ]; then
        log_info "Cleaning up Lambda execution role: $LAMBDA_ROLE_NAME"
        
        # Detach all policies
        local attached_policies=$(aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
        
        for policy_arn in $attached_policies; do
            aws iam detach-role-policy --role-name "$LAMBDA_ROLE_NAME" --policy-arn "$policy_arn" &>/dev/null || true
        done
        
        # Delete role
        aws iam delete-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null || true
    fi
}

# Generic cleanup function for policies
cleanup_policy() {
    local policy_name="$1"
    local policy_arn="arn:aws:iam::$AWS_ACCOUNT_ID:policy/$policy_name"
    
    log_info "Cleaning up IAM policy: $policy_name"
    
    # Detach from all roles
    local attached_roles=$(aws iam list-entities-for-policy --policy-arn "$policy_arn" --query 'PolicyRoles[].RoleName' --output text 2>/dev/null || echo "")
    
    for role_name in $attached_roles; do
        aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" &>/dev/null || true
    done
    
    # Delete all policy versions except default
    local versions=$(aws iam list-policy-versions --policy-arn "$policy_arn" --query 'Versions[?!IsDefaultVersion].VersionId' --output text 2>/dev/null || echo "")
    
    for version in $versions; do
        aws iam delete-policy-version --policy-arn "$policy_arn" --version-id "$version" &>/dev/null || true
    done
    
    # Delete policy
    aws iam delete-policy --policy-arn "$policy_arn" &>/dev/null || true
}

# Register cleanup functions for all policies
cleanup_policy_lambda() { cleanup_policy "$LAMBDA_POLICY_NAME"; }
cleanup_policy_cognito() { cleanup_policy "$COGNITO_POLICY_NAME"; }
cleanup_policy_rds() { cleanup_policy "$RDS_POLICY_NAME"; }
cleanup_policy_secrets() { cleanup_policy "$SECRETS_POLICY_NAME"; }

# Function to save IAM configuration state
save_iam_configuration_state() {
    local state_file="./deployment_checkpoints/iam_configuration.state"
    mkdir -p "$(dirname "$state_file")"
    
    cat > "$state_file" << EOF
# IAM Configuration State
# Generated on $(date)
LAMBDA_ROLE_NAME="$LAMBDA_ROLE_NAME"
LAMBDA_ROLE_ARN="$LAMBDA_ROLE_ARN"
LAMBDA_POLICY_NAME="$LAMBDA_POLICY_NAME"
LAMBDA_POLICY_ARN="$LAMBDA_POLICY_ARN"
COGNITO_POLICY_NAME="$COGNITO_POLICY_NAME"
COGNITO_POLICY_ARN="$COGNITO_POLICY_ARN"
RDS_POLICY_NAME="$RDS_POLICY_NAME"
RDS_POLICY_ARN="$RDS_POLICY_ARN"
SECRETS_POLICY_NAME="$SECRETS_POLICY_NAME"
SECRETS_POLICY_ARN="$SECRETS_POLICY_ARN"
AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
AWS_REGION="$AWS_REGION"
ENVIRONMENT="$ENVIRONMENT"
PROJECT_NAME="$PROJECT_NAME"
EOF
    
    log_success "IAM configuration state saved to: $state_file"
}

# Function to display IAM configuration information
display_iam_info() {
    log_success "IAM roles and policies configuration completed successfully!"
    echo ""
    echo "=== Lambda Execution Role ==="
    echo "Role Name: $LAMBDA_ROLE_NAME"
    echo "Role ARN: $LAMBDA_ROLE_ARN"
    echo ""
    echo "=== Custom IAM Policies ==="
    echo "Lambda Policy: $LAMBDA_POLICY_ARN"
    echo "Cognito Policy: $COGNITO_POLICY_ARN"
    echo "RDS Policy: $RDS_POLICY_ARN"
    echo "Secrets Manager Policy: $SECRETS_POLICY_ARN"
    echo ""
    echo "=== AWS Managed Policies Attached ==="
    echo "- AWSLambdaVPCAccessExecutionRole"
    echo "- AWSXRayDaemonWriteAccess"
    echo ""
    echo "=== Security Features ==="
    echo "- Principle of least privilege applied"
    echo "- Resource-specific permissions where possible"
    echo "- Comprehensive logging and monitoring"
    echo "- Cross-service integration support"
    echo "- Secure credential handling via Secrets Manager"
    echo ""
    echo "=== Permissions Summary ==="
    echo "Lambda Execution:"
    echo "  - CloudWatch Logs (create/write)"
    echo "  - VPC networking (ENI management)"
    echo "  - X-Ray tracing"
    echo ""
    echo "Cognito Integration:"
    echo "  - User management (CRUD operations)"
    echo "  - Authentication flows"
    echo "  - Group management"
    echo ""
    echo "RDS Access:"
    echo "  - Database instance metadata"
    echo "  - IAM database authentication"
    echo ""
    echo "Secrets Manager:"
    echo "  - Read secrets with project/environment prefix"
    echo "  - List secrets (scoped)"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Use this role ARN in Lambda function configurations"
    echo "2. Store database credentials in Secrets Manager"
    echo "3. Configure Cognito User Pool ID in application settings"
    echo "4. Test permissions with actual Lambda deployments"
    echo ""
}

# Main execution function
main() {
    log_info "Starting IAM roles and policies configuration..."
    log_info "Project: $PROJECT_NAME, Environment: $ENVIRONMENT"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate AWS CLI
    if ! validate_aws_cli "$AWS_PROFILE"; then
        handle_error $ERROR_CODE_AWS_CLI "AWS CLI validation failed" true
    fi
    
    # Get AWS account information
    get_aws_account_info
    
    # Log configuration
    log_info "Configuration:"
    log_info "  Lambda Role: $LAMBDA_ROLE_NAME"
    log_info "  AWS Account: $AWS_ACCOUNT_ID"
    log_info "  AWS Region: $AWS_REGION"
    if [ -n "${COGNITO_USER_POOL_ID:-}" ]; then
        log_info "  Cognito User Pool: $COGNITO_USER_POOL_ID"
    fi
    if [ -n "${RDS_INSTANCE_ID:-}" ]; then
        log_info "  RDS Instance: $RDS_INSTANCE_ID"
    fi
    if [ -n "${SECRETS_PREFIX:-}" ]; then
        log_info "  Secrets Prefix: $SECRETS_PREFIX"
    fi
    
    # Create IAM resources
    create_lambda_execution_role
    create_and_attach_policies
    validate_iam_configuration
    
    # Save state and display information
    save_iam_configuration_state
    display_iam_info
    
    log_success "IAM roles and policies configuration completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi