#!/bin/bash

# Lambda Function Provisioning Script
# Creates AWS Lambda functions configured for .NET 10 runtime
# Implements cost-optimized memory and timeout settings
# Configures VPC settings for database access
# Sets up IAM roles and policies for Lambda execution

set -euo pipefail

# Initialize AWS_PROFILE with default value if not set
AWS_PROFILE="${AWS_PROFILE:-}"

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILITIES_DIR="$SCRIPT_DIR/../utilities"
source "$UTILITIES_DIR/logging.sh"
source "$UTILITIES_DIR/error-handling.sh"
source "$UTILITIES_DIR/validate-aws-cli.sh"
source "$UTILITIES_DIR/configure-cognito-iam.sh"

# Default configuration values (cost-optimized)
DEFAULT_RUNTIME="dotnet8"  # Closest available to .NET 10
DEFAULT_MEMORY_SIZE="512"  # Cost-optimized memory allocation
DEFAULT_TIMEOUT="30"       # Reasonable timeout for database operations
DEFAULT_HANDLER="TestDeployLambda::TestDeployLambda.LambdaEntryPoint::FunctionHandlerAsync"

# Configuration variables
RUNTIME="${RUNTIME:-$DEFAULT_RUNTIME}"
MEMORY_SIZE="${MEMORY_SIZE:-$DEFAULT_MEMORY_SIZE}"
TIMEOUT="${TIMEOUT:-$DEFAULT_TIMEOUT}"
HANDLER="${HANDLER:-$DEFAULT_HANDLER}"

# Resource naming
ENVIRONMENT="${ENVIRONMENT:-dev}"
PROJECT_NAME="${PROJECT_NAME:-myapp}"
LAMBDA_FUNCTION_NAME="$PROJECT_NAME-$ENVIRONMENT-api"
LAMBDA_ROLE_NAME="$PROJECT_NAME-$ENVIRONMENT-lambda-role"
LAMBDA_POLICY_NAME="$PROJECT_NAME-$ENVIRONMENT-lambda-policy"

# Global variables for resource tracking
LAMBDA_ROLE_ARN=""
LAMBDA_FUNCTION_ARN=""
VPC_ID=""
SUBNET_IDS=""
SECURITY_GROUP_ID=""

# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Provisions AWS Lambda function configured for .NET runtime with cost optimization.

OPTIONS:
    --function-name NAME       Lambda function name (default: $PROJECT_NAME-$ENVIRONMENT-api)
    --runtime RUNTIME          Lambda runtime (default: $DEFAULT_RUNTIME)
    --memory SIZE              Memory allocation in MB (default: $DEFAULT_MEMORY_SIZE)
    --timeout SECONDS          Function timeout in seconds (default: $DEFAULT_TIMEOUT)
    --handler HANDLER          Function handler (default: $DEFAULT_HANDLER)
    --environment ENV          Environment name (default: dev)
    --project-name NAME        Project name (default: myapp)
    --aws-profile PROFILE      AWS profile to use
    --help                     Show this help message

EXAMPLES:
    $0 --environment production --project-name webapp
    $0 --memory 1024 --timeout 60 --aws-profile prod

COST OPTIMIZATION:
    - Uses 512MB memory allocation (cost-effective for most workloads)
    - 30-second timeout (sufficient for database operations)
    - VPC configuration only when needed for RDS access
    - Minimal IAM permissions (principle of least privilege)

PREREQUISITES:
    - RDS infrastructure must be provisioned first (run provision-rds.sh)
    - AWS CLI configured with appropriate permissions

EOF
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --function-name)
                LAMBDA_FUNCTION_NAME="$2"
                shift 2
                ;;
            --runtime)
                RUNTIME="$2"
                shift 2
                ;;
            --memory)
                MEMORY_SIZE="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --handler)
                HANDLER="$2"
                shift 2
                ;;
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
    LAMBDA_FUNCTION_NAME="${LAMBDA_FUNCTION_NAME:-$PROJECT_NAME-$ENVIRONMENT-api}"
    LAMBDA_ROLE_NAME="$PROJECT_NAME-$ENVIRONMENT-lambda-role"
    LAMBDA_POLICY_NAME="$PROJECT_NAME-$ENVIRONMENT-lambda-policy"
}

# Function to load RDS infrastructure state
load_rds_infrastructure_state() {
    local state_file="./deployment_checkpoints/rds_infrastructure.state"
    
    if [ -f "$state_file" ]; then
        log_info "Loading RDS infrastructure state from: $state_file"
        source "$state_file"
        
        if [ -n "$VPC_ID" ] && [ -n "$SUBNET_ID_1" ] && [ -n "$SUBNET_ID_2" ]; then
            SUBNET_IDS="$SUBNET_ID_1,$SUBNET_ID_2"
            log_success "Loaded RDS infrastructure state"
            log_info "VPC ID: $VPC_ID"
            log_info "Subnet IDs: $SUBNET_IDS"
            return 0
        else
            log_warn "RDS infrastructure state file exists but is incomplete"
        fi
    else
        log_warn "RDS infrastructure state file not found: $state_file"
    fi
    
    log_warn "Lambda will be created without VPC configuration"
    log_warn "Run provision-rds.sh first to enable database access"
    return 1
}

# Function to create Lambda security group
create_lambda_security_group() {
    if [ -z "$VPC_ID" ]; then
        log_info "Skipping Lambda security group creation (no VPC)"
        return 0
    fi
    
    local sg_name="$PROJECT_NAME-$ENVIRONMENT-lambda-sg"
    
    log_info "Checking for existing Lambda security group: $sg_name"
    
    local sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$sg_name" "Name=vpc-id,Values=$VPC_ID" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$sg_id" != "None" ] && [ "$sg_id" != "null" ]; then
        log_info "Found existing Lambda security group: $sg_id"
        SECURITY_GROUP_ID="$sg_id"
        return 0
    fi
    
    log_info "Creating Lambda security group: $sg_name"
    set_error_context "Lambda security group creation"
    set_error_remediation "Check AWS permissions for EC2 security group operations"
    
    SECURITY_GROUP_ID=$(execute_with_error_handling \
        "aws ec2 create-security-group --group-name $sg_name --description 'Security group for Lambda functions' --vpc-id $VPC_ID --query 'GroupId' --output text" \
        "Failed to create Lambda security group" \
        $ERROR_CODE_INFRASTRUCTURE)
    
    log_success "Created Lambda security group: $SECURITY_GROUP_ID"
    
    # Tag the security group
    execute_with_error_handling \
        "aws ec2 create-tags --resources $SECURITY_GROUP_ID --tags Key=Name,Value=$sg_name Key=Environment,Value=$ENVIRONMENT Key=Project,Value=$PROJECT_NAME" \
        "Failed to tag Lambda security group" \
        $ERROR_CODE_INFRASTRUCTURE
    
    # Add outbound rule for HTTPS (443) - for external API calls
    log_info "Adding HTTPS outbound rule to Lambda security group"
    execute_with_error_handling \
        "aws ec2 authorize-security-group-egress --group-id $SECURITY_GROUP_ID --protocol tcp --port 443 --cidr 0.0.0.0/0" \
        "Failed to add HTTPS outbound rule" \
        $ERROR_CODE_INFRASTRUCTURE
    
    # Add outbound rule for PostgreSQL (5432) - for RDS access
    log_info "Adding PostgreSQL outbound rule to Lambda security group"
    execute_with_error_handling \
        "aws ec2 authorize-security-group-egress --group-id $SECURITY_GROUP_ID --protocol tcp --port 5432 --cidr 10.0.0.0/16" \
        "Failed to add PostgreSQL outbound rule" \
        $ERROR_CODE_INFRASTRUCTURE
    
    log_success "Lambda security group configuration completed"
    register_cleanup_function "cleanup_lambda_security_group"
}

# Function to create IAM trust policy document
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

# Function to create IAM policy document for Lambda execution
create_lambda_execution_policy() {
    local vpc_permissions=""
    
    # Add VPC permissions if VPC is configured
    if [ -n "$VPC_ID" ]; then
        vpc_permissions=',
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateNetworkInterface",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DeleteNetworkInterface",
                "ec2:AttachNetworkInterface",
                "ec2:DetachNetworkInterface"
            ],
            "Resource": "*"
        }'
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
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "cognito-idp:AdminGetUser",
                "cognito-idp:AdminCreateUser",
                "cognito-idp:AdminSetUserPassword",
                "cognito-idp:AdminUpdateUserAttributes",
                "cognito-idp:ListUsers",
                "cognito-idp:AdminListGroupsForUser",
                "cognito-idp:AdminAddUserToGroup",
                "cognito-idp:AdminRemoveUserFromGroup"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            "Resource": "*"
        }$vpc_permissions
    ]
}
EOF
}

# Function to check if IAM role already exists
check_existing_lambda_role() {
    log_info "Checking for existing Lambda IAM role: $LAMBDA_ROLE_NAME"
    
    local role_arn=$(aws iam get-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        --query 'Role.Arn' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$role_arn" != "None" ] && [ "$role_arn" != "null" ]; then
        log_info "Found existing Lambda IAM role: $role_arn"
        LAMBDA_ROLE_ARN="$role_arn"
        return 0
    fi
    
    return 1
}

# Function to create IAM role for Lambda execution
create_lambda_iam_role() {
    if check_existing_lambda_role; then
        log_info "Using existing Lambda IAM role: $LAMBDA_ROLE_ARN"
        return 0
    fi
    
    log_info "Creating IAM role for Lambda execution: $LAMBDA_ROLE_NAME"
    set_error_context "Lambda IAM role creation"
    set_error_remediation "Check AWS permissions for IAM operations"
    
    # Create trust policy file
    local trust_policy_file="./lambda-trust-policy.json"
    create_lambda_trust_policy > "$trust_policy_file"
    
    # Create IAM role
    LAMBDA_ROLE_ARN=$(execute_with_error_handling \
        "aws iam create-role --role-name $LAMBDA_ROLE_NAME --assume-role-policy-document file://$trust_policy_file --query 'Role.Arn' --output text" \
        "Failed to create Lambda IAM role" \
        $ERROR_CODE_INFRASTRUCTURE)
    
    log_success "Created Lambda IAM role: $LAMBDA_ROLE_ARN"
    
    # Tag the role
    execute_with_error_handling \
        "aws iam tag-role --role-name $LAMBDA_ROLE_NAME --tags Key=Environment,Value=$ENVIRONMENT Key=Project,Value=$PROJECT_NAME" \
        "Failed to tag Lambda IAM role" \
        $ERROR_CODE_INFRASTRUCTURE
    
    # Create execution policy file
    local execution_policy_file="./lambda-execution-policy.json"
    create_lambda_execution_policy > "$execution_policy_file"
    
    # Create and attach custom policy
    log_info "Creating custom Lambda execution policy: $LAMBDA_POLICY_NAME"
    local policy_arn=$(execute_with_error_handling \
        "aws iam create-policy --policy-name $LAMBDA_POLICY_NAME --policy-document file://$execution_policy_file --query 'Policy.Arn' --output text" \
        "Failed to create Lambda execution policy" \
        $ERROR_CODE_INFRASTRUCTURE)
    
    # Attach custom policy to role
    execute_with_error_handling \
        "aws iam attach-role-policy --role-name $LAMBDA_ROLE_NAME --policy-arn $policy_arn" \
        "Failed to attach custom policy to Lambda role" \
        $ERROR_CODE_INFRASTRUCTURE
    
    # Attach AWS managed policy for VPC access (if VPC is configured)
    if [ -n "$VPC_ID" ]; then
        log_info "Attaching VPC execution policy to Lambda role"
        execute_with_error_handling \
            "aws iam attach-role-policy --role-name $LAMBDA_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole" \
            "Failed to attach VPC execution policy to Lambda role" \
            $ERROR_CODE_INFRASTRUCTURE
    else
        # Attach basic execution policy if no VPC
        log_info "Attaching basic execution policy to Lambda role"
        execute_with_error_handling \
            "aws iam attach-role-policy --role-name $LAMBDA_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
            "Failed to attach basic execution policy to Lambda role" \
            $ERROR_CODE_INFRASTRUCTURE
    fi
    
    # Configure Cognito permissions for Lambda role
    log_info "Configuring Cognito permissions for Lambda role"
    local cognito_policy_name="${LAMBDA_ROLE_NAME}-CognitoAccess"
    local cognito_policy_description="Cognito access permissions for Lambda function in $ENVIRONMENT environment"
    
    # Create and attach Cognito policy using the utility function
    if create_cognito_iam_policy "$cognito_policy_name" "full" "$cognito_policy_description"; then
        if attach_cognito_policy_to_role "$LAMBDA_ROLE_NAME" "$cognito_policy_name"; then
            log_success "Cognito permissions configured for Lambda role"
        else
            log_warn "Failed to attach Cognito policy to Lambda role - continuing without Cognito permissions"
        fi
    else
        log_warn "Failed to create Cognito IAM policy - continuing without Cognito permissions"
    fi
    
    # Clean up temporary files
    rm -f "$trust_policy_file" "$execution_policy_file"
    
    log_success "Lambda IAM role configuration completed"
    register_cleanup_function "cleanup_lambda_iam_role"
    
    # Wait for role to propagate
    log_info "Waiting for IAM role to propagate..."
    sleep 10
}

# Function to create placeholder deployment package
create_placeholder_deployment_package() {
    local package_dir="./lambda-package"
    local zip_file="./lambda-deployment.zip"
    
    # Don't use log_info here as it will interfere with the return value
    
    # Create temporary directory
    mkdir -p "$package_dir"
    
    # Create a simple placeholder Lambda function
    cat > "$package_dir/lambda_function.py" << 'EOF'
import json

def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Lambda function created successfully. Deploy your .NET application to replace this placeholder.',
            'timestamp': context.aws_request_id
        })
    }
EOF
    
    # Create deployment package using PowerShell (Windows compatible)
    if command -v powershell >/dev/null 2>&1; then
        powershell -Command "Compress-Archive -Path '$package_dir/*' -DestinationPath '$zip_file' -Force" > /dev/null
    elif command -v zip >/dev/null 2>&1; then
        cd "$package_dir"
        zip -r "$zip_file" . > /dev/null
        cd - > /dev/null
    else
        return 1
    fi
    
    # Clean up temporary directory
    rm -rf "$package_dir"
    
    echo "$zip_file"
}

# Function to check if Lambda function already exists
check_existing_lambda_function() {
    log_info "Checking for existing Lambda function: $LAMBDA_FUNCTION_NAME"
    
    local function_arn=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Configuration.FunctionArn' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$function_arn" != "None" ] && [ "$function_arn" != "null" ]; then
        log_info "Found existing Lambda function: $function_arn"
        LAMBDA_FUNCTION_ARN="$function_arn"
        return 0
    fi
    
    return 1
}

# Function to create Lambda function
create_lambda_function() {
    if check_existing_lambda_function; then
        log_info "Using existing Lambda function: $LAMBDA_FUNCTION_ARN"
        return 0
    fi
    
    log_info "Creating Lambda function: $LAMBDA_FUNCTION_NAME"
    log_info "Configuration: $RUNTIME, ${MEMORY_SIZE}MB, ${TIMEOUT}s timeout"
    
    set_error_context "Lambda function creation"
    set_error_remediation "Check AWS permissions for Lambda operations and ensure IAM role exists"
    
    # Create placeholder deployment package
    log_info "Creating placeholder deployment package"
    local zip_file=$(create_placeholder_deployment_package)
    if [ $? -ne 0 ]; then
        handle_error $ERROR_CODE_LAMBDA "Failed to create deployment package" true
    fi
    
    # Prepare VPC configuration
    local vpc_config=""
    if [ -n "$VPC_ID" ] && [ -n "$SUBNET_IDS" ] && [ -n "$SECURITY_GROUP_ID" ]; then
        vpc_config="--vpc-config SubnetIds=$SUBNET_IDS,SecurityGroupIds=$SECURITY_GROUP_ID"
        log_info "Configuring Lambda with VPC access"
    else
        log_info "Creating Lambda without VPC configuration"
    fi
    
    # Create Lambda function
    LAMBDA_FUNCTION_ARN=$(execute_with_error_handling \
        "aws lambda create-function \
            --function-name $LAMBDA_FUNCTION_NAME \
            --runtime python3.9 \
            --role $LAMBDA_ROLE_ARN \
            --handler lambda_function.lambda_handler \
            --zip-file fileb://$zip_file \
            --memory-size $MEMORY_SIZE \
            --timeout $TIMEOUT \
            --description 'Placeholder Lambda function for $PROJECT_NAME $ENVIRONMENT' \
            $vpc_config \
            --tags Environment=$ENVIRONMENT,Project=$PROJECT_NAME \
            --query 'FunctionArn' \
            --output text" \
        "Failed to create Lambda function" \
        $ERROR_CODE_LAMBDA)
    
    log_success "Created Lambda function: $LAMBDA_FUNCTION_ARN"
    
    # Clean up deployment package
    rm -f "$zip_file"
    
    register_cleanup_function "cleanup_lambda_function"
}

# Function to configure Lambda environment variables
configure_lambda_environment() {
    log_info "Configuring Lambda environment variables"
    
    # Load database password from checkpoint
    local db_password=""
    if db_password=$(cat "./deployment_checkpoints/rds_password.checkpoint" 2>/dev/null); then
        log_info "Retrieved database password from checkpoint"
    else
        log_warn "Database password not found in checkpoint. Lambda will need manual configuration."
        db_password="PLACEHOLDER_PASSWORD"
    fi
    
    # Prepare environment variables
    local env_vars="Variables={"
    env_vars="${env_vars}ASPNETCORE_ENVIRONMENT=$ENVIRONMENT"
    
    # Add database connection string if RDS is configured
    if [ -n "${DB_ENDPOINT:-}" ]; then
        local connection_string="Host=${DB_ENDPOINT};Database=appdb;Username=dbadmin;Password=${db_password};Port=5432;SSL Mode=Require;"
        env_vars="${env_vars},ConnectionStrings__DefaultConnection=$connection_string"
        log_info "Added database connection string to environment variables"
    fi
    
    # Add AWS region
    local aws_region=$(aws configure get region || echo "us-east-1")
    env_vars="${env_vars},AWS__Region=$aws_region"
    
    env_vars="${env_vars}}"
    
    # Update Lambda environment variables
    execute_with_error_handling \
        "aws lambda update-function-configuration \
            --function-name $LAMBDA_FUNCTION_NAME \
            --environment '$env_vars'" \
        "Failed to configure Lambda environment variables" \
        $ERROR_CODE_LAMBDA
    
    log_success "Lambda environment variables configured"
}

# Cleanup functions for rollback
cleanup_lambda_function() {
    if [ -n "$LAMBDA_FUNCTION_NAME" ]; then
        log_info "Cleaning up Lambda function: $LAMBDA_FUNCTION_NAME"
        aws lambda delete-function \
            --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null || true
    fi
}

cleanup_lambda_iam_role() {
    if [ -n "$LAMBDA_ROLE_NAME" ]; then
        log_info "Cleaning up Lambda IAM role: $LAMBDA_ROLE_NAME"
        
        # Detach policies
        aws iam detach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" &>/dev/null || true
        aws iam detach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole" &>/dev/null || true
        
        # Delete custom policy
        local policy_arn="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/$LAMBDA_POLICY_NAME"
        aws iam detach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn "$policy_arn" &>/dev/null || true
        aws iam delete-policy \
            --policy-arn "$policy_arn" &>/dev/null || true
        
        # Remove Cognito permissions using utility function
        log_info "Removing Cognito permissions from Lambda role"
        remove_cognito_permissions "$LAMBDA_ROLE_NAME" || true
        
        # Delete role
        aws iam delete-role \
            --role-name "$LAMBDA_ROLE_NAME" &>/dev/null || true
    fi
}

cleanup_lambda_security_group() {
    if [ -n "$SECURITY_GROUP_ID" ]; then
        log_info "Cleaning up Lambda security group: $SECURITY_GROUP_ID"
        aws ec2 delete-security-group \
            --group-id "$SECURITY_GROUP_ID" &>/dev/null || true
    fi
}

# Function to save Lambda infrastructure state
save_lambda_infrastructure_state() {
    local state_file="./deployment_checkpoints/lambda_infrastructure.state"
    mkdir -p "$(dirname "$state_file")"
    
    cat > "$state_file" << EOF
# Lambda Infrastructure State
# Generated on $(date)
LAMBDA_FUNCTION_NAME="$LAMBDA_FUNCTION_NAME"
LAMBDA_FUNCTION_ARN="$LAMBDA_FUNCTION_ARN"
LAMBDA_ROLE_NAME="$LAMBDA_ROLE_NAME"
LAMBDA_ROLE_ARN="$LAMBDA_ROLE_ARN"
LAMBDA_POLICY_NAME="$LAMBDA_POLICY_NAME"
SECURITY_GROUP_ID="$SECURITY_GROUP_ID"
RUNTIME="$RUNTIME"
MEMORY_SIZE="$MEMORY_SIZE"
TIMEOUT="$TIMEOUT"
ENVIRONMENT="$ENVIRONMENT"
PROJECT_NAME="$PROJECT_NAME"
EOF
    
    log_success "Lambda infrastructure state saved to: $state_file"
}

# Function to display Lambda information
display_lambda_info() {
    log_success "Lambda function provisioning completed successfully!"
    echo ""
    echo "=== Lambda Function Information ==="
    echo "Function Name: $LAMBDA_FUNCTION_NAME"
    echo "Function ARN: $LAMBDA_FUNCTION_ARN"
    echo "Runtime: $RUNTIME"
    echo "Memory: ${MEMORY_SIZE}MB"
    echo "Timeout: ${TIMEOUT}s"
    echo "Handler: $HANDLER"
    echo ""
    echo "=== IAM Configuration ==="
    echo "Role Name: $LAMBDA_ROLE_NAME"
    echo "Role ARN: $LAMBDA_ROLE_ARN"
    echo ""
    if [ -n "$VPC_ID" ]; then
        echo "=== VPC Configuration ==="
        echo "VPC ID: $VPC_ID"
        echo "Subnet IDs: $SUBNET_IDS"
        echo "Security Group ID: $SECURITY_GROUP_ID"
        echo ""
    fi
    echo "=== Security Notes ==="
    echo "- IAM role follows principle of least privilege"
    echo "- Cognito integration permissions included"
    echo "- CloudWatch logging enabled"
    if [ -n "$VPC_ID" ]; then
        echo "- VPC configuration enables RDS access"
    else
        echo "- No VPC configuration (run provision-rds.sh first for database access)"
    fi
    echo ""
    echo "=== Next Steps ==="
    echo "1. Deploy your .NET application code to replace the placeholder"
    echo "2. Update the runtime to dotnet8 when deploying .NET code"
    echo "3. Configure additional environment variables as needed"
    echo "4. Test the function with sample events"
    echo ""
}

# Main execution function
main() {
    log_info "Starting Lambda function provisioning..."
    log_info "Project: $PROJECT_NAME, Environment: $ENVIRONMENT"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate AWS CLI
    if ! validate_aws_cli "$AWS_PROFILE"; then
        handle_error $ERROR_CODE_AWS_CLI "AWS CLI validation failed" true
    fi
    
    # Log configuration
    log_info "Configuration:"
    log_info "  Function Name: $LAMBDA_FUNCTION_NAME"
    log_info "  Runtime: $RUNTIME"
    log_info "  Memory: ${MEMORY_SIZE}MB"
    log_info "  Timeout: ${TIMEOUT}s"
    log_info "  Handler: $HANDLER"
    
    # Load RDS infrastructure state (optional)
    load_rds_infrastructure_state || true
    
    # Create Lambda infrastructure components
    create_lambda_security_group
    create_lambda_iam_role
    create_lambda_function
    configure_lambda_environment
    
    # Save state and display information
    save_lambda_infrastructure_state
    display_lambda_info
    
    log_success "Lambda function provisioning completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi