#!/bin/bash

# Cognito IAM Configuration Utility
# Implements proper IAM roles for Cognito access from Lambda
# Adds Cognito service permissions to Lambda execution role
# Creates Cognito configuration error handling and guidance

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/error-handling.sh"

# IAM policy templates for Cognito integration
COGNITO_LAMBDA_POLICY_TEMPLATE='{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cognito-idp:AdminGetUser",
                "cognito-idp:AdminListGroupsForUser",
                "cognito-idp:AdminGetUserAttributes",
                "cognito-idp:ListUsers",
                "cognito-idp:AdminCreateUser",
                "cognito-idp:AdminSetUserPassword",
                "cognito-idp:AdminUpdateUserAttributes",
                "cognito-idp:AdminDeleteUser"
            ],
            "Resource": "arn:aws:cognito-idp:*:*:userpool/*"
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
}'

COGNITO_READONLY_POLICY_TEMPLATE='{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cognito-idp:AdminGetUser",
                "cognito-idp:AdminListGroupsForUser",
                "cognito-idp:AdminGetUserAttributes",
                "cognito-idp:ListUsers"
            ],
            "Resource": "arn:aws:cognito-idp:*:*:userpool/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "cognito-idp:DescribeUserPool",
                "cognito-idp:DescribeUserPoolClient"
            ],
            "Resource": "*"
        }
    ]
}'

# Function to create Cognito IAM policy
create_cognito_iam_policy() {
    local policy_name="$1"
    local policy_type="${2:-full}"  # full, readonly
    local description="$3"
    
    log_info "Creating Cognito IAM policy: $policy_name"
    
    # Select policy template based on type
    local policy_document
    case "$policy_type" in
        "readonly")
            policy_document="$COGNITO_READONLY_POLICY_TEMPLATE"
            ;;
        "full"|*)
            policy_document="$COGNITO_LAMBDA_POLICY_TEMPLATE"
            ;;
    esac
    
    # Check if policy already exists
    if aws iam get-policy --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/$policy_name" &> /dev/null; then
        log_warn "IAM policy already exists: $policy_name"
        log_info "Updating existing policy..."
        
        # Create new policy version
        local version_result
        if version_result=$(aws iam create-policy-version \
            --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/$policy_name" \
            --policy-document "$policy_document" \
            --set-as-default 2>&1); then
            
            log_success "Policy updated successfully"
            local version_id=$(echo "$version_result" | grep -o '"VersionId": "[^"]*"' | cut -d'"' -f4)
            log_info "New policy version: $version_id"
            
            # Clean up old versions (keep only latest 5)
            cleanup_old_policy_versions "$policy_name"
            
            return 0
        else
            log_error "Failed to update policy: $version_result"
            return 1
        fi
    else
        # Create new policy
        local create_result
        if create_result=$(aws iam create-policy \
            --policy-name "$policy_name" \
            --policy-document "$policy_document" \
            --description "$description" 2>&1); then
            
            log_success "IAM policy created successfully: $policy_name"
            local policy_arn=$(echo "$create_result" | grep -o '"Arn": "[^"]*"' | cut -d'"' -f4)
            log_info "Policy ARN: $policy_arn"
            
            return 0
        else
            log_error "Failed to create policy: $create_result"
            return 1
        fi
    fi
}

# Function to cleanup old policy versions
cleanup_old_policy_versions() {
    local policy_name="$1"
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local policy_arn="arn:aws:iam::$account_id:policy/$policy_name"
    
    log_debug "Cleaning up old policy versions for: $policy_name"
    
    # List all policy versions
    local versions_result
    if versions_result=$(aws iam list-policy-versions --policy-arn "$policy_arn" 2>&1); then
        # Extract version IDs (excluding default version)
        local old_versions=$(echo "$versions_result" | grep -o '"VersionId": "v[0-9]*"' | cut -d'"' -f4 | grep -v "$(echo "$versions_result" | grep -A1 '"IsDefaultVersion": true' | grep -o '"VersionId": "v[0-9]*"' | cut -d'"' -f4)" | head -n -4)
        
        # Delete old versions
        for version in $old_versions; do
            if [ -n "$version" ]; then
                log_debug "Deleting old policy version: $version"
                aws iam delete-policy-version --policy-arn "$policy_arn" --version-id "$version" &> /dev/null || true
            fi
        done
    fi
}

# Function to attach Cognito policy to Lambda execution role
attach_cognito_policy_to_role() {
    local role_name="$1"
    local policy_name="$2"
    
    log_info "Attaching Cognito policy to Lambda execution role: $role_name"
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local policy_arn="arn:aws:iam::$account_id:policy/$policy_name"
    
    # Check if role exists
    if ! aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_error "Lambda execution role not found: $role_name"
        log_error "Please create the Lambda execution role first"
        return 1
    fi
    
    # Check if policy is already attached
    if aws iam list-attached-role-policies --role-name "$role_name" | grep -q "$policy_arn"; then
        log_info "Policy already attached to role: $role_name"
        return 0
    fi
    
    # Attach policy to role
    if aws iam attach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" 2>&1; then
        log_success "Cognito policy attached to Lambda execution role"
        
        # Verify attachment
        if aws iam list-attached-role-policies --role-name "$role_name" | grep -q "$policy_arn"; then
            log_success "Policy attachment verified"
            return 0
        else
            log_error "Policy attachment verification failed"
            return 1
        fi
    else
        log_error "Failed to attach policy to role"
        return 1
    fi
}

# Function to create Lambda execution role with Cognito permissions
create_lambda_execution_role_with_cognito() {
    local role_name="$1"
    local user_pool_arn="${2:-}"
    local environment="${3:-dev}"
    
    log_info "Creating Lambda execution role with Cognito permissions: $role_name"
    
    # Lambda trust policy
    local trust_policy='{
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
    }'
    
    # Check if role already exists
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_warn "Lambda execution role already exists: $role_name"
        log_info "Updating role policies..."
    else
        # Create the role
        if aws iam create-role \
            --role-name "$role_name" \
            --assume-role-policy-document "$trust_policy" \
            --description "Lambda execution role with Cognito permissions for $environment environment" &> /dev/null; then
            
            log_success "Lambda execution role created: $role_name"
        else
            log_error "Failed to create Lambda execution role"
            return 1
        fi
    fi
    
    # Attach basic Lambda execution policy
    log_info "Attaching basic Lambda execution policy..."
    if aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" &> /dev/null; then
        log_success "Basic Lambda execution policy attached"
    else
        log_warn "Failed to attach basic Lambda execution policy (may already be attached)"
    fi
    
    # Attach VPC execution policy (needed for RDS access)
    log_info "Attaching VPC execution policy..."
    if aws iam attach-role-policy \
        --role-name "$role_name" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole" &> /dev/null; then
        log_success "VPC execution policy attached"
    else
        log_warn "Failed to attach VPC execution policy (may already be attached)"
    fi
    
    # Create and attach Cognito policy
    local cognito_policy_name="${role_name}-CognitoAccess"
    local policy_description="Cognito access permissions for Lambda function in $environment environment"
    
    if create_cognito_iam_policy "$cognito_policy_name" "full" "$policy_description"; then
        if attach_cognito_policy_to_role "$role_name" "$cognito_policy_name"; then
            log_success "Cognito permissions configured for Lambda execution role"
        else
            log_error "Failed to attach Cognito policy to role"
            return 1
        fi
    else
        log_error "Failed to create Cognito IAM policy"
        return 1
    fi
    
    # Create specific User Pool policy if ARN provided
    if [ -n "$user_pool_arn" ]; then
        log_info "Creating specific User Pool policy..."
        create_user_pool_specific_policy "$role_name" "$user_pool_arn"
    fi
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 10
    
    # Get role ARN
    local role_arn
    if role_arn=$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text 2>/dev/null); then
        log_success "Lambda execution role ready: $role_arn"
        echo "$role_arn"
        return 0
    else
        log_error "Failed to retrieve role ARN"
        return 1
    fi
}

# Function to create User Pool specific policy
create_user_pool_specific_policy() {
    local role_name="$1"
    local user_pool_arn="$2"
    
    log_info "Creating User Pool specific policy"
    
    local specific_policy_name="${role_name}-SpecificUserPool"
    local specific_policy="{
        \"Version\": \"2012-10-17\",
        \"Statement\": [
            {
                \"Effect\": \"Allow\",
                \"Action\": [
                    \"cognito-idp:AdminGetUser\",
                    \"cognito-idp:AdminListGroupsForUser\",
                    \"cognito-idp:AdminGetUserAttributes\",
                    \"cognito-idp:AdminCreateUser\",
                    \"cognito-idp:AdminSetUserPassword\",
                    \"cognito-idp:AdminUpdateUserAttributes\",
                    \"cognito-idp:AdminDeleteUser\"
                ],
                \"Resource\": \"$user_pool_arn\"
            }
        ]
    }"
    
    if create_cognito_iam_policy "$specific_policy_name" "custom" "Specific User Pool access for $user_pool_arn"; then
        # Update the policy with specific ARN
        local account_id=$(aws sts get-caller-identity --query Account --output text)
        local policy_arn="arn:aws:iam::$account_id:policy/$specific_policy_name"
        
        if aws iam create-policy-version \
            --policy-arn "$policy_arn" \
            --policy-document "$specific_policy" \
            --set-as-default &> /dev/null; then
            
            log_success "User Pool specific policy created"
            
            # Attach to role
            if attach_cognito_policy_to_role "$role_name" "$specific_policy_name"; then
                log_success "User Pool specific policy attached to role"
            fi
        fi
    fi
}

# Function to validate Lambda role Cognito permissions
validate_lambda_cognito_permissions() {
    local role_name="$1"
    local user_pool_id="${2:-}"
    
    log_info "Validating Lambda role Cognito permissions: $role_name"
    
    # Check if role exists
    if ! aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_error "Lambda execution role not found: $role_name"
        return 1
    fi
    
    # Get attached policies
    local attached_policies
    if attached_policies=$(aws iam list-attached-role-policies --role-name "$role_name" 2>&1); then
        log_debug "Attached policies retrieved"
    else
        log_error "Failed to retrieve attached policies: $attached_policies"
        return 1
    fi
    
    # Check for Cognito-related policies
    local has_cognito_policy=false
    local cognito_policies=()
    
    # Extract policy ARNs and names
    while IFS= read -r line; do
        if [[ "$line" == *"cognito"* ]] || [[ "$line" == *"Cognito"* ]]; then
            has_cognito_policy=true
            local policy_name=$(echo "$line" | grep -o '"PolicyName": "[^"]*"' | cut -d'"' -f4)
            cognito_policies+=("$policy_name")
        fi
    done <<< "$attached_policies"
    
    if [ "$has_cognito_policy" = true ]; then
        log_success "Cognito policies found on role:"
        for policy in "${cognito_policies[@]}"; do
            log_info "  ✓ $policy"
        done
    else
        log_warn "No Cognito-specific policies found on role"
        log_info "Checking for broad permissions..."
        
        # Check for admin or power user policies
        if echo "$attached_policies" | grep -q "AdministratorAccess\|PowerUserAccess"; then
            log_info "Role has broad permissions that include Cognito access"
            has_cognito_policy=true
        fi
    fi
    
    # Test actual permissions if User Pool ID provided
    if [ -n "$user_pool_id" ] && [ "$has_cognito_policy" = true ]; then
        log_info "Testing actual Cognito permissions..."
        test_cognito_permissions_with_role "$role_name" "$user_pool_id"
    fi
    
    if [ "$has_cognito_policy" = true ]; then
        log_success "Lambda role has Cognito permissions"
        return 0
    else
        log_error "Lambda role lacks Cognito permissions"
        provide_cognito_permission_guidance "$role_name"
        return 1
    fi
}

# Function to test Cognito permissions with role (simulation)
test_cognito_permissions_with_role() {
    local role_name="$1"
    local user_pool_id="$2"
    
    log_debug "Testing Cognito permissions for role: $role_name"
    
    # Get role ARN
    local role_arn
    if role_arn=$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text 2>/dev/null); then
        log_debug "Role ARN: $role_arn"
    else
        log_error "Failed to get role ARN"
        return 1
    fi
    
    # Simulate policy evaluation (this is a simplified check)
    log_info "Simulating Cognito permissions..."
    
    # Check if we can describe the user pool (this tests our current permissions, not the role's)
    if aws cognito-idp describe-user-pool --user-pool-id "$user_pool_id" &> /dev/null; then
        log_success "Cognito service is accessible"
    else
        log_warn "Cannot access Cognito service with current credentials"
        log_warn "Role permissions cannot be fully validated"
    fi
    
    # Use IAM policy simulator if available
    log_info "For complete validation, test the Lambda function with actual Cognito operations"
}

# Function to provide Cognito permission guidance
provide_cognito_permission_guidance() {
    local role_name="$1"
    
    echo ""
    echo "=== Cognito Permission Configuration Guide ==="
    echo ""
    echo "🔧 Required Actions for Role: $role_name"
    echo ""
    echo "1. Create Cognito IAM Policy:"
    echo "   $0 create-policy --name ${role_name}-CognitoAccess --type full"
    echo ""
    echo "2. Attach Policy to Role:"
    echo "   $0 attach-policy --role $role_name --policy ${role_name}-CognitoAccess"
    echo ""
    echo "3. Or use this script to configure everything:"
    echo "   $0 configure-role --role $role_name --environment production"
    echo ""
    echo "🔍 Manual Configuration (AWS Console):"
    echo "1. Go to IAM → Roles → $role_name"
    echo "2. Click 'Attach policies'"
    echo "3. Create custom policy with Cognito permissions"
    echo "4. Attach the policy to the role"
    echo ""
    echo "📋 Required Cognito Permissions:"
    echo "  - cognito-idp:AdminGetUser"
    echo "  - cognito-idp:AdminListGroupsForUser"
    echo "  - cognito-idp:AdminGetUserAttributes"
    echo "  - cognito-idp:DescribeUserPool"
    echo "  - cognito-idp:DescribeUserPoolClient"
    echo ""
}

# Function to remove Cognito permissions from role
remove_cognito_permissions() {
    local role_name="$1"
    
    log_info "Removing Cognito permissions from role: $role_name"
    
    # List attached policies
    local attached_policies
    if attached_policies=$(aws iam list-attached-role-policies --role-name "$role_name" 2>&1); then
        # Find Cognito-related policies
        local cognito_policy_arns=()
        while IFS= read -r line; do
            if [[ "$line" == *"cognito"* ]] || [[ "$line" == *"Cognito"* ]]; then
                local policy_arn=$(echo "$line" | grep -o '"PolicyArn": "[^"]*"' | cut -d'"' -f4)
                if [ -n "$policy_arn" ]; then
                    cognito_policy_arns+=("$policy_arn")
                fi
            fi
        done <<< "$attached_policies"
        
        # Detach Cognito policies
        for policy_arn in "${cognito_policy_arns[@]}"; do
            log_info "Detaching policy: $policy_arn"
            if aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" 2>&1; then
                log_success "Policy detached: $policy_arn"
            else
                log_error "Failed to detach policy: $policy_arn"
            fi
        done
        
        if [ ${#cognito_policy_arns[@]} -eq 0 ]; then
            log_info "No Cognito policies found to remove"
        else
            log_success "Cognito permissions removed from role"
        fi
    else
        log_error "Failed to list attached policies: $attached_policies"
        return 1
    fi
}

# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Cognito IAM configuration utility for AWS Lambda deployment.

COMMANDS:
    create-policy       Create Cognito IAM policy
    attach-policy       Attach Cognito policy to Lambda role
    configure-role      Create/configure Lambda role with Cognito permissions
    validate-role       Validate Lambda role Cognito permissions
    remove-permissions  Remove Cognito permissions from role
    guidance           Show configuration guidance

OPTIONS:
    --role ROLE_NAME           Lambda execution role name
    --policy POLICY_NAME       IAM policy name
    --type POLICY_TYPE         Policy type (full, readonly) [default: full]
    --user-pool-id ID          User Pool ID for specific permissions
    --user-pool-arn ARN        User Pool ARN for specific permissions
    --environment ENV          Environment (dev, staging, production) [default: dev]
    --help                     Show this help message

EXAMPLES:
    # Create complete Lambda role with Cognito permissions
    $0 configure-role --role MyLambdaRole --environment production

    # Create Cognito policy only
    $0 create-policy --name MyCognitoPolicy --type full

    # Attach existing policy to role
    $0 attach-policy --role MyLambdaRole --policy MyCognitoPolicy

    # Validate role permissions
    $0 validate-role --role MyLambdaRole --user-pool-id us-east-1_abcdef123

    # Remove Cognito permissions
    $0 remove-permissions --role MyLambdaRole

POLICY TYPES:
    full        Full Cognito admin permissions (create, update, delete users)
    readonly    Read-only permissions (get user info, list users)

EOF
}

# Main function to handle command-line interface
main() {
    local command=""
    local role_name=""
    local policy_name=""
    local policy_type="full"
    local user_pool_id=""
    local user_pool_arn=""
    local environment="dev"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            create-policy|attach-policy|configure-role|validate-role|remove-permissions|guidance)
                command="$1"
                shift
                ;;
            --role)
                role_name="$2"
                shift 2
                ;;
            --policy)
                policy_name="$2"
                shift 2
                ;;
            --type)
                policy_type="$2"
                shift 2
                ;;
            --user-pool-id)
                user_pool_id="$2"
                shift 2
                ;;
            --user-pool-arn)
                user_pool_arn="$2"
                shift 2
                ;;
            --environment)
                environment="$2"
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
    
    # Execute command
    case "$command" in
        "create-policy")
            if [ -z "$policy_name" ]; then
                log_error "Policy name is required for create-policy command"
                exit 1
            fi
            
            local description="Cognito access policy for Lambda functions in $environment environment"
            create_cognito_iam_policy "$policy_name" "$policy_type" "$description"
            ;;
        "attach-policy")
            if [ -z "$role_name" ] || [ -z "$policy_name" ]; then
                log_error "Role name and policy name are required for attach-policy command"
                exit 1
            fi
            
            attach_cognito_policy_to_role "$role_name" "$policy_name"
            ;;
        "configure-role")
            if [ -z "$role_name" ]; then
                log_error "Role name is required for configure-role command"
                exit 1
            fi
            
            create_lambda_execution_role_with_cognito "$role_name" "$user_pool_arn" "$environment"
            ;;
        "validate-role")
            if [ -z "$role_name" ]; then
                log_error "Role name is required for validate-role command"
                exit 1
            fi
            
            validate_lambda_cognito_permissions "$role_name" "$user_pool_id"
            ;;
        "remove-permissions")
            if [ -z "$role_name" ]; then
                log_error "Role name is required for remove-permissions command"
                exit 1
            fi
            
            remove_cognito_permissions "$role_name"
            ;;
        "guidance")
            provide_cognito_permission_guidance "${role_name:-YourLambdaRole}"
            ;;
        "")
            log_error "Command is required"
            show_usage
            exit 1
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Export functions for use in other scripts
export -f create_cognito_iam_policy attach_cognito_policy_to_role
export -f create_lambda_execution_role_with_cognito validate_lambda_cognito_permissions
export -f remove_cognito_permissions provide_cognito_permission_guidance

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi