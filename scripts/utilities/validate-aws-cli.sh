#!/bin/bash

# AWS CLI Validation Utility
# Checks AWS CLI installation, credentials, and permissions before deployment operations

# Source logging utility
VALIDATE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$VALIDATE_SCRIPT_DIR/logging.sh"

# Function to get AWS region using flexible detection
get_aws_region() {
    local region=""
    
    # Method 1: AWS CLI configuration
    if aws configure get region &>/dev/null; then
        region=$(aws configure get region)
    # Method 2: AWS_DEFAULT_REGION environment variable
    elif [[ -n "${AWS_DEFAULT_REGION:-}" ]]; then
        region="$AWS_DEFAULT_REGION"
    # Method 3: AWS_REGION environment variable
    elif [[ -n "${AWS_REGION:-}" ]]; then
        region="$AWS_REGION"
    # Method 4: Try to get from AWS profile if set
    elif [[ -n "${AWS_PROFILE:-}" ]] && aws configure get region --profile "$AWS_PROFILE" &>/dev/null; then
        region=$(aws configure get region --profile "$AWS_PROFILE")
    # Method 5: Default fallback
    else
        region="us-east-1"
        log_debug "No AWS region configured, using default: $region"
    fi
    
    echo "$region"
}

# Function to check if AWS CLI is installed
check_aws_cli_installation() {
    log_info "Checking AWS CLI installation..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed or not in PATH"
        log_error "Please install AWS CLI v2 from: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        return 1
    fi
    
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_success "AWS CLI found - Version: $aws_version"
    return 0
}

# Function to check AWS credentials configuration with detailed analysis
check_aws_credentials() {
    log_info "Checking AWS credentials configuration..."
    
    # Try multiple methods to detect credentials
    local credentials_found=false
    local credential_method=""
    
    # Method 1: Try aws sts get-caller-identity (most reliable)
    if aws sts get-caller-identity &> /dev/null; then
        credentials_found=true
        credential_method="AWS CLI/STS"
    # Method 2: Check environment variables
    elif [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        credentials_found=true
        credential_method="Environment Variables"
        log_info "AWS credentials found via environment variables"
        # Try to verify they work
        if ! aws sts get-caller-identity &> /dev/null; then
            log_warn "Environment variables are set but credentials may be invalid"
        fi
    # Method 3: Check AWS profile
    elif [[ -n "${AWS_PROFILE:-}" ]]; then
        credential_method="AWS Profile: $AWS_PROFILE"
        if aws sts get-caller-identity --profile "$AWS_PROFILE" &> /dev/null; then
            credentials_found=true
            log_info "AWS credentials found via profile: $AWS_PROFILE"
        else
            log_error "AWS profile '$AWS_PROFILE' is not valid or accessible"
            provide_credential_setup_instructions
            return 1
        fi
    # Method 4: Check if credentials files exist
    elif [[ -f "$HOME/.aws/credentials" || -f "$HOME/.aws/config" ]]; then
        credential_method="AWS Credentials File"
        log_info "AWS credentials file found, but unable to verify access"
        log_warn "This might be due to:"
        log_warn "  - Expired credentials"
        log_warn "  - Incorrect region configuration"  
        log_warn "  - Network connectivity issues"
        log_warn "Continuing - will fail later if credentials are invalid"
        credentials_found=true
    fi
    
    if [ "$credentials_found" = false ]; then
        log_error "AWS credentials are not configured or invalid"
        echo ""
        echo "=== AWS Credentials Setup Required ==="
        provide_credential_setup_instructions
        return 1
    fi
    
    # If we can get caller identity, show detailed info
    if aws sts get-caller-identity &> /dev/null; then
        # Get detailed caller identity information
        local caller_identity=$(aws sts get-caller-identity 2>/dev/null)
        local user_arn=$(echo "$caller_identity" | grep -o '"Arn": "[^"]*"' | cut -d'"' -f4)
        local account_id=$(echo "$caller_identity" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
        local user_id=$(echo "$caller_identity" | grep -o '"UserId": "[^"]*"' | cut -d'"' -f4)
        
        # Determine credential type
        local credential_type="Unknown"
        local credential_source="Unknown"
        
        if [[ "$user_arn" == *":user/"* ]]; then
            credential_type="IAM User"
            credential_source="Access Keys"
        elif [[ "$user_arn" == *":role/"* ]]; then
            credential_type="IAM Role"
            if [[ "$user_arn" == *"assumed-role"* ]]; then
                credential_source="Assumed Role"
            else
                credential_source="Instance Profile"
            fi
        elif [[ "$user_arn" == *":root"* ]]; then
            credential_type="Root Account"
            credential_source="Root Access Keys"
            log_warn "Using root account credentials is not recommended for security reasons"
        fi
        
        log_success "AWS credentials are valid"
        log_info "Credential Details:"
        log_info "  Account ID: $account_id"
        log_info "  User/Role ARN: $user_arn"
        log_info "  User ID: $user_id"
        log_info "  Credential Type: $credential_type"
        log_info "  Credential Source: $credential_source"
        log_info "  Detection Method: $credential_method"
        
        # Check credential age and provide security recommendations
        check_credential_security "$credential_type"
        
        # Validate credential scope
        validate_credential_scope "$user_arn"
    else
        log_success "AWS credentials detected via $credential_method"
        log_info "Unable to verify credential details, but proceeding with deployment"
    fi
    
    return 0
}

# Function to provide comprehensive credential setup instructions
provide_credential_setup_instructions() {
    echo "AWS credentials can be configured using several methods:"
    echo ""
    echo "🔑 Method 1: AWS CLI Configuration (Recommended for development)"
    echo "   aws configure"
    echo "   - Enter your AWS Access Key ID"
    echo "   - Enter your AWS Secret Access Key"
    echo "   - Enter your default region (e.g., us-east-1)"
    echo "   - Enter default output format (json recommended)"
    echo ""
    echo "🔑 Method 2: Environment Variables"
    echo "   export AWS_ACCESS_KEY_ID=your_access_key_id"
    echo "   export AWS_SECRET_ACCESS_KEY=your_secret_access_key"
    echo "   export AWS_DEFAULT_REGION=your_region"
    echo ""
    echo "🔑 Method 3: AWS Profiles (Recommended for multiple accounts)"
    echo "   aws configure --profile <profile-name>"
    echo "   # Then use: export AWS_PROFILE=<profile-name>"
    echo ""
    echo "🔑 Method 4: IAM Roles (Recommended for EC2/Lambda)"
    echo "   - Attach IAM role to EC2 instance"
    echo "   - No additional configuration needed"
    echo ""
    echo "🔑 Method 5: AWS SSO (Recommended for organizations)"
    echo "   aws configure sso"
    echo "   # Follow the prompts to set up SSO"
    echo ""
    echo "📋 How to Get Access Keys:"
    echo "1. Sign in to AWS Console"
    echo "2. Go to IAM → Users → [Your Username]"
    echo "3. Click 'Security credentials' tab"
    echo "4. Click 'Create access key'"
    echo "5. Download and securely store the credentials"
    echo ""
    echo "⚠️  Security Best Practices:"
    echo "   • Never share or commit access keys to version control"
    echo "   • Use IAM roles instead of access keys when possible"
    echo "   • Rotate access keys regularly (every 90 days)"
    echo "   • Use least privilege principle for permissions"
    echo "   • Enable MFA for additional security"
    echo ""
    echo "🔍 Verification:"
    echo "   aws sts get-caller-identity"
    echo ""
}

# Function to check credential security
check_credential_security() {
    local credential_type="$1"
    
    log_debug "Checking credential security best practices..."
    
    case "$credential_type" in
        "Root Account")
            log_error "🚨 Security Risk: Using root account credentials"
            echo "   Recommendations:"
            echo "   • Create an IAM user with appropriate permissions"
            echo "   • Never use root credentials for daily operations"
            echo "   • Enable MFA on root account"
            ;;
        "IAM User")
            log_info "✅ Using IAM user credentials (recommended)"
            echo "   Security reminders:"
            echo "   • Rotate access keys every 90 days"
            echo "   • Use least privilege permissions"
            echo "   • Enable MFA if possible"
            ;;
        "IAM Role")
            log_success "✅ Using IAM role (most secure)"
            echo "   Benefits:"
            echo "   • Temporary credentials"
            echo "   • Automatic rotation"
            echo "   • No long-term access keys"
            ;;
    esac
}

# Function to validate credential scope
validate_credential_scope() {
    local user_arn="$1"
    
    log_debug "Validating credential scope and permissions..."
    
    # Extract account ID and user/role name
    local account_id=$(echo "$user_arn" | cut -d':' -f5)
    local resource_part=$(echo "$user_arn" | cut -d':' -f6)
    
    # Check if this is a cross-account role
    if [[ "$user_arn" == *"assumed-role"* ]]; then
        local role_name=$(echo "$resource_part" | cut -d'/' -f2)
        log_info "Using assumed role: $role_name"
        
        # Check session duration if possible
        local session_name=$(echo "$resource_part" | cut -d'/' -f3)
        if [ -n "$session_name" ]; then
            log_debug "Session name: $session_name"
        fi
    fi
    
    # Provide account-specific guidance
    log_info "Operating in AWS Account: $account_id"
    
    # Check for common organizational patterns
    if [[ "$user_arn" == *"-dev-"* ]] || [[ "$user_arn" == *"-development-"* ]]; then
        log_info "Detected development environment credentials"
    elif [[ "$user_arn" == *"-prod-"* ]] || [[ "$user_arn" == *"-production-"* ]]; then
        log_warn "Detected production environment credentials - ensure proper change management"
    fi
}

# Function to check AWS region configuration with detailed validation
check_aws_region() {
    log_info "Checking AWS region configuration..."
    
    local region=""
    local region_source=""
    
    # Try multiple sources for region configuration
    # 1. AWS CLI profile configuration
    region=$(aws configure get region 2>/dev/null)
    if [ -n "$region" ]; then
        region_source="AWS CLI profile"
    else
        # 2. Environment variable
        region="${AWS_DEFAULT_REGION:-}"
        if [ -n "$region" ]; then
            region_source="AWS_DEFAULT_REGION environment variable"
        else
            # 3. Instance metadata (for EC2 instances)
            if command -v curl &> /dev/null; then
                region=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "")
                if [ -n "$region" ]; then
                    region_source="EC2 instance metadata"
                fi
            fi
        fi
    fi
    
    if [ -z "$region" ]; then
        log_error "AWS region is not configured"
        echo ""
        echo "=== Region Configuration Required ==="
        echo "Please configure AWS region using one of these methods:"
        echo ""
        echo "1. AWS CLI Configuration:"
        echo "   aws configure set region <region-name>"
        echo ""
        echo "2. Environment Variable:"
        echo "   export AWS_DEFAULT_REGION=<region-name>"
        echo ""
        echo "3. Profile-specific Configuration:"
        echo "   aws configure set region <region-name> --profile <profile-name>"
        echo ""
        provide_region_recommendations
        return 1
    fi
    
    # Validate region format and availability
    if ! validate_region_format "$region"; then
        log_error "Invalid region format: $region"
        provide_region_recommendations
        return 1
    fi
    
    # Test region accessibility
    if ! test_region_accessibility "$region"; then
        log_error "Cannot access region: $region"
        log_error "Region may not exist or you may not have access"
        provide_region_recommendations
        return 1
    fi
    
    log_success "AWS region configured: $region (source: $region_source)"
    
    # Provide region-specific information
    provide_region_info "$region"
    
    return 0
}

# Function to validate region format
validate_region_format() {
    local region="$1"
    
    # AWS region format: 2-3 letter region code, dash, direction, dash, number
    # Examples: us-east-1, eu-west-2, ap-southeast-1
    if [[ "$region" =~ ^[a-z]{2,3}-[a-z]+-[0-9]+$ ]]; then
        return 0
    fi
    
    return 1
}

# Function to test region accessibility
test_region_accessibility() {
    local region="$1"
    
    log_debug "Testing accessibility of region: $region"
    
    # Try to list S3 buckets in the region (minimal operation)
    if aws s3api list-buckets --region "$region" &> /dev/null; then
        return 0
    fi
    
    # Fallback: try to get caller identity with region
    if aws sts get-caller-identity --region "$region" &> /dev/null; then
        return 0
    fi
    
    return 1
}

# Function to provide region recommendations
provide_region_recommendations() {
    echo ""
    echo "=== Recommended AWS Regions ==="
    echo ""
    echo "🌍 Global Considerations:"
    echo "  • Choose regions closest to your users for lowest latency"
    echo "  • Consider data residency and compliance requirements"
    echo "  • Some services may not be available in all regions"
    echo ""
    echo "💰 Cost Optimization:"
    echo "  • us-east-1 (N. Virginia): Typically lowest cost, baseline pricing"
    echo "  • us-west-2 (Oregon): Good cost, renewable energy powered"
    echo ""
    echo "🇻🇳 Recommendations for Vietnam:"
    echo "  1. ap-southeast-1 (Singapore): ~50-80ms latency, ~15% higher cost"
    echo "  2. ap-northeast-1 (Tokyo): ~80-120ms latency, ~12% higher cost"
    echo "  3. us-east-1 (N. Virginia): ~200-250ms latency, lowest cost"
    echo ""
    echo "🏢 Popular Regions by Use Case:"
    echo "  • Development/Testing: us-east-1 (cost-effective)"
    echo "  • Production (Global): us-east-1, eu-west-1, ap-southeast-1"
    echo "  • Production (Asia-Pacific): ap-southeast-1, ap-northeast-1"
    echo ""
    echo "📋 Available Regions:"
    echo "  • US East: us-east-1, us-east-2"
    echo "  • US West: us-west-1, us-west-2"
    echo "  • Europe: eu-west-1, eu-west-2, eu-central-1"
    echo "  • Asia Pacific: ap-southeast-1, ap-southeast-2, ap-northeast-1, ap-northeast-2"
    echo "  • Others: ca-central-1, sa-east-1, ap-south-1"
    echo ""
}

# Function to provide region-specific information
provide_region_info() {
    local region="$1"
    
    # Define region information
    declare -A REGION_INFO=(
        ["us-east-1"]="N. Virginia|Lowest cost, most services|~200-250ms to Vietnam"
        ["us-west-2"]="Oregon|Good cost, renewable energy|~180-220ms to Vietnam"
        ["eu-west-1"]="Ireland|GDPR compliant|~300-350ms to Vietnam"
        ["ap-southeast-1"]="Singapore|Closest to Vietnam|~50-80ms to Vietnam"
        ["ap-northeast-1"]="Tokyo|Good for Asia-Pacific|~80-120ms to Vietnam"
        ["ap-southeast-2"]="Sydney|Australia/NZ focus|~150-200ms to Vietnam"
    )
    
    local info="${REGION_INFO[$region]:-"Unknown region|No specific info available|Unknown latency"}"
    local location=$(echo "$info" | cut -d'|' -f1)
    local characteristics=$(echo "$info" | cut -d'|' -f2)
    local latency=$(echo "$info" | cut -d'|' -f3)
    
    log_info "Region Information:"
    log_info "  Location: $location"
    log_info "  Characteristics: $characteristics"
    log_info "  Estimated latency from Vietnam: $latency"
    
    # Provide cost factor information
    source "$VALIDATE_SCRIPT_DIR/cost-optimization.sh" 2>/dev/null || true
    if declare -p REGIONAL_COST_FACTORS &>/dev/null; then
        local cost_factor="${REGIONAL_COST_FACTORS[$region]:-"Unknown"}"
        if [ "$cost_factor" != "Unknown" ]; then
            log_info "  Cost factor: ${cost_factor}x compared to us-east-1"
        fi
    fi
}

# Function to check required AWS permissions with detailed reporting
check_aws_permissions() {
    log_info "Checking AWS permissions for deployment operations..."
    
    local permissions_ok=true
    local missing_permissions=()
    local permission_details=()
    
    # Define required permissions with descriptions
    declare -A REQUIRED_PERMISSIONS=(
        ["rds:describe-db-instances"]="List RDS instances"
        ["rds:create-db-instance"]="Create RDS instances"
        ["rds:create-db-subnet-group"]="Create DB subnet groups"
        ["lambda:list-functions"]="List Lambda functions"
        ["lambda:create-function"]="Create Lambda functions"
        ["lambda:update-function-configuration"]="Update Lambda configuration"
        ["ec2:describe-vpcs"]="List VPCs"
        ["ec2:create-vpc"]="Create VPCs"
        ["ec2:create-subnet"]="Create subnets"
        ["ec2:create-security-group"]="Create security groups"
        ["iam:list-roles"]="List IAM roles"
        ["iam:create-role"]="Create IAM roles"
        ["iam:attach-role-policy"]="Attach policies to roles"
        ["sts:get-caller-identity"]="Get caller identity"
    )
    
    # Test each permission category
    log_debug "Checking RDS permissions..."
    if ! aws rds describe-db-instances --max-items 1 &> /dev/null; then
        log_warn "Missing RDS permissions (describe-db-instances)"
        missing_permissions+=("RDS")
        permission_details+=("RDS: Cannot list database instances")
        permissions_ok=false
    else
        log_debug "✓ RDS describe permissions available"
    fi
    
    # Test RDS creation permissions (dry-run where possible)
    if ! aws rds describe-db-subnet-groups --max-items 1 &> /dev/null; then
        log_warn "Missing RDS subnet group permissions"
        if [[ ! " ${missing_permissions[@]} " =~ " RDS " ]]; then
            missing_permissions+=("RDS")
        fi
        permission_details+=("RDS: Cannot manage DB subnet groups")
        permissions_ok=false
    fi
    
    # Check Lambda permissions
    log_debug "Checking Lambda permissions..."
    if ! aws lambda list-functions --max-items 1 &> /dev/null; then
        log_warn "Missing Lambda permissions (list-functions)"
        missing_permissions+=("Lambda")
        permission_details+=("Lambda: Cannot list functions")
        permissions_ok=false
    else
        log_debug "✓ Lambda list permissions available"
    fi
    
    # Check EC2/VPC permissions
    log_debug "Checking EC2/VPC permissions..."
    if ! aws ec2 describe-vpcs --max-items 1 &> /dev/null; then
        log_warn "Missing EC2/VPC permissions (describe-vpcs)"
        missing_permissions+=("EC2/VPC")
        permission_details+=("EC2/VPC: Cannot list VPCs")
        permissions_ok=false
    else
        log_debug "✓ EC2/VPC describe permissions available"
    fi
    
    # Check additional EC2 permissions
    if ! aws ec2 describe-subnets --max-items 1 &> /dev/null; then
        log_warn "Missing EC2 subnet permissions"
        if [[ ! " ${missing_permissions[@]} " =~ " EC2/VPC " ]]; then
            missing_permissions+=("EC2/VPC")
        fi
        permission_details+=("EC2/VPC: Cannot manage subnets")
        permissions_ok=false
    fi
    
    if ! aws ec2 describe-security-groups --max-items 1 &> /dev/null; then
        log_warn "Missing EC2 security group permissions"
        if [[ ! " ${missing_permissions[@]} " =~ " EC2/VPC " ]]; then
            missing_permissions+=("EC2/VPC")
        fi
        permission_details+=("EC2/VPC: Cannot manage security groups")
        permissions_ok=false
    fi
    
    # Check IAM permissions
    log_debug "Checking IAM permissions..."
    if ! aws iam list-roles --max-items 1 &> /dev/null; then
        log_warn "Missing IAM permissions (list-roles)"
        missing_permissions+=("IAM")
        permission_details+=("IAM: Cannot list roles")
        permissions_ok=false
    else
        log_debug "✓ IAM list permissions available"
    fi
    
    # Check IAM policy permissions
    if ! aws iam list-policies --scope Local --max-items 1 &> /dev/null; then
        log_warn "Missing IAM policy permissions"
        if [[ ! " ${missing_permissions[@]} " =~ " IAM " ]]; then
            missing_permissions+=("IAM")
        fi
        permission_details+=("IAM: Cannot manage policies")
        permissions_ok=false
    fi
    
    # Check STS permissions (should always work if credentials are valid)
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "Cannot get caller identity - credentials may be invalid"
        permissions_ok=false
    fi
    
    # Report results
    if [ "$permissions_ok" = true ]; then
        log_success "All required AWS permissions are available"
        return 0
    else
        log_error "Missing AWS permissions detected"
        echo ""
        echo "=== Missing Permissions Summary ==="
        for service in "${missing_permissions[@]}"; do
            echo "❌ $service"
        done
        echo ""
        echo "=== Detailed Permission Issues ==="
        for detail in "${permission_details[@]}"; do
            echo "  - $detail"
        done
        echo ""
        
        # Provide specific remediation guidance
        provide_permission_remediation "${missing_permissions[@]}"
        return 1
    fi
}

# Function to provide detailed permission remediation guidance
provide_permission_remediation() {
    local missing_services=("$@")
    
    echo "=== Permission Remediation Guide ==="
    echo ""
    
    for service in "${missing_services[@]}"; do
        case "$service" in
            "RDS")
                echo "🔧 RDS Permissions Required:"
                echo "   Managed Policy: AmazonRDSFullAccess"
                echo "   Or Custom Policy with actions:"
                echo "     - rds:CreateDBInstance"
                echo "     - rds:DescribeDBInstances"
                echo "     - rds:CreateDBSubnetGroup"
                echo "     - rds:DescribeDBSubnetGroups"
                echo "     - rds:AddTagsToResource"
                echo ""
                ;;
            "Lambda")
                echo "🔧 Lambda Permissions Required:"
                echo "   Managed Policy: AWSLambda_FullAccess"
                echo "   Or Custom Policy with actions:"
                echo "     - lambda:CreateFunction"
                echo "     - lambda:UpdateFunctionConfiguration"
                echo "     - lambda:ListFunctions"
                echo "     - lambda:GetFunction"
                echo "     - lambda:TagResource"
                echo ""
                ;;
            "EC2/VPC")
                echo "🔧 EC2/VPC Permissions Required:"
                echo "   Managed Policy: AmazonEC2FullAccess"
                echo "   Or Custom Policy with actions:"
                echo "     - ec2:CreateVpc"
                echo "     - ec2:CreateSubnet"
                echo "     - ec2:CreateSecurityGroup"
                echo "     - ec2:DescribeVpcs"
                echo "     - ec2:DescribeSubnets"
                echo "     - ec2:DescribeSecurityGroups"
                echo "     - ec2:CreateTags"
                echo "     - ec2:AuthorizeSecurityGroupIngress"
                echo "     - ec2:AuthorizeSecurityGroupEgress"
                echo ""
                ;;
            "IAM")
                echo "🔧 IAM Permissions Required:"
                echo "   Managed Policy: IAMFullAccess (or limited IAM permissions)"
                echo "   Or Custom Policy with actions:"
                echo "     - iam:CreateRole"
                echo "     - iam:AttachRolePolicy"
                echo "     - iam:CreatePolicy"
                echo "     - iam:ListRoles"
                echo "     - iam:ListPolicies"
                echo "     - iam:TagRole"
                echo "     - iam:PassRole"
                echo ""
                ;;
        esac
    done
    
    echo "📋 How to Apply Permissions:"
    echo "1. AWS Console Method:"
    echo "   - Go to IAM → Users → [Your User] → Permissions"
    echo "   - Click 'Add permissions' → 'Attach existing policies directly'"
    echo "   - Search for and attach the required managed policies"
    echo ""
    echo "2. AWS CLI Method (requires admin access):"
    echo "   aws iam attach-user-policy --user-name YOUR_USERNAME --policy-arn arn:aws:iam::aws:policy/POLICY_NAME"
    echo ""
    echo "3. Contact Administrator:"
    echo "   - Forward this permission list to your AWS administrator"
    echo "   - Request the specific managed policies or custom policy creation"
    echo ""
}

# Function to validate AWS profile with comprehensive checking
validate_aws_profile() {
    local profile="$1"
    
    if [ -n "$profile" ]; then
        log_info "Validating AWS profile: $profile"
        
        # Check if profile exists
        if ! aws configure list-profiles | grep -q "^$profile$"; then
            log_error "AWS profile '$profile' not found"
            echo ""
            echo "=== Available Profiles ==="
            local available_profiles=$(aws configure list-profiles 2>/dev/null)
            if [ -n "$available_profiles" ]; then
                echo "$available_profiles" | sed 's/^/  ✓ /'
            else
                echo "  No profiles configured"
            fi
            echo ""
            echo "=== Profile Management ==="
            echo "Create new profile:"
            echo "  aws configure --profile $profile"
            echo ""
            echo "List all profiles:"
            echo "  aws configure list-profiles"
            echo ""
            echo "View profile configuration:"
            echo "  aws configure list --profile $profile"
            echo ""
            return 1
        fi
        
        # Test profile credentials
        log_debug "Testing profile credentials..."
        if ! aws sts get-caller-identity --profile "$profile" &> /dev/null; then
            log_error "AWS profile '$profile' has invalid or expired credentials"
            echo ""
            echo "=== Profile Troubleshooting ==="
            echo "1. Check profile configuration:"
            echo "   aws configure list --profile $profile"
            echo ""
            echo "2. Reconfigure profile:"
            echo "   aws configure --profile $profile"
            echo ""
            echo "3. Check credential file:"
            echo "   cat ~/.aws/credentials"
            echo ""
            echo "4. Verify access keys are not expired or disabled"
            echo ""
            return 1
        fi
        
        # Get profile details
        local profile_region=$(aws configure get region --profile "$profile" 2>/dev/null || echo "Not set")
        local profile_output=$(aws configure get output --profile "$profile" 2>/dev/null || echo "Not set")
        
        # Get credential information for the profile
        local profile_identity=$(aws sts get-caller-identity --profile "$profile" 2>/dev/null)
        local profile_arn=$(echo "$profile_identity" | grep -o '"Arn": "[^"]*"' | cut -d'"' -f4)
        local profile_account=$(echo "$profile_identity" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
        
        log_success "AWS profile '$profile' is valid"
        log_info "Profile Configuration:"
        log_info "  Region: $profile_region"
        log_info "  Output format: $profile_output"
        log_info "  Account ID: $profile_account"
        log_info "  User/Role ARN: $profile_arn"
        
        # Set the profile for subsequent operations
        export AWS_PROFILE="$profile"
        log_info "AWS_PROFILE environment variable set to: $profile"
        
        # Validate profile permissions
        log_info "Validating profile permissions..."
        if check_aws_permissions; then
            log_success "Profile has required permissions for deployment"
        else
            log_warn "Profile may have insufficient permissions for some operations"
        fi
    fi
    
    return 0
}

# Function to list and analyze all configured profiles
list_aws_profiles() {
    log_info "Analyzing configured AWS profiles..."
    
    local profiles=$(aws configure list-profiles 2>/dev/null)
    
    if [ -z "$profiles" ]; then
        log_warn "No AWS profiles configured"
        echo ""
        echo "=== Profile Setup Guide ==="
        echo "Create your first profile:"
        echo "  aws configure"
        echo ""
        echo "Create additional profiles:"
        echo "  aws configure --profile <profile-name>"
        echo ""
        return 1
    fi
    
    echo ""
    echo "=== Configured AWS Profiles ==="
    echo ""
    
    local current_profile="${AWS_PROFILE:-default}"
    
    while IFS= read -r profile; do
        if [ -n "$profile" ]; then
            local status="❓"
            local details=""
            
            # Test profile credentials
            if aws sts get-caller-identity --profile "$profile" &> /dev/null; then
                status="✅"
                local profile_account=$(aws sts get-caller-identity --profile "$profile" --query 'Account' --output text 2>/dev/null)
                local profile_region=$(aws configure get region --profile "$profile" 2>/dev/null || echo "No region")
                details="Account: $profile_account, Region: $profile_region"
            else
                status="❌"
                details="Invalid or expired credentials"
            fi
            
            # Mark current profile
            local current_marker=""
            if [ "$profile" = "$current_profile" ]; then
                current_marker=" (CURRENT)"
            fi
            
            echo "$status $profile$current_marker"
            echo "    $details"
            echo ""
        fi
    done <<< "$profiles"
    
    echo "=== Profile Usage ==="
    echo "Switch to a profile:"
    echo "  export AWS_PROFILE=<profile-name>"
    echo ""
    echo "Use profile for single command:"
    echo "  aws <command> --profile <profile-name>"
    echo ""
}

# Function to perform comprehensive AWS CLI validation with detailed reporting
# Parameters:
#   $1 - AWS profile name (optional) - if not provided, uses default AWS configuration
validate_aws_cli() {
    local profile="${1:-}"
    local validation_failed=false
    local validation_summary=()
    
    log_info "Starting comprehensive AWS CLI validation..."
    echo ""
    
    # Check AWS CLI installation
    echo "🔍 Checking AWS CLI installation..."
    if ! check_aws_cli_installation; then
        validation_failed=true
        validation_summary+=("❌ AWS CLI installation")
    else
        validation_summary+=("✅ AWS CLI installation")
    fi
    echo ""
    
    # Validate profile if specified
    if [ -n "$profile" ]; then
        echo "👤 Validating AWS profile..."
        if ! validate_aws_profile "$profile"; then
            validation_failed=true
            validation_summary+=("❌ AWS profile validation")
        else
            validation_summary+=("✅ AWS profile validation")
        fi
        echo ""
    fi
    
    # Check credentials
    echo "🔐 Checking AWS credentials..."
    if ! check_aws_credentials; then
        validation_failed=true
        validation_summary+=("❌ AWS credentials")
    else
        validation_summary+=("✅ AWS credentials")
    fi
    echo ""
    
    # Check region
    echo "🌍 Checking AWS region configuration..."
    if ! check_aws_region; then
        validation_failed=true
        validation_summary+=("❌ AWS region configuration")
    else
        validation_summary+=("✅ AWS region configuration")
    fi
    echo ""
    
    # Check permissions
    echo "🔒 Checking AWS permissions..."
    if ! check_aws_permissions; then
        validation_failed=true
        validation_summary+=("❌ AWS permissions")
    else
        validation_summary+=("✅ AWS permissions")
    fi
    echo ""
    
    # Display validation summary
    echo "=== AWS CLI Validation Summary ==="
    for item in "${validation_summary[@]}"; do
        echo "  $item"
    done
    echo ""
    
    if [ "$validation_failed" = true ]; then
        log_error "AWS CLI validation failed. Please resolve the issues above before proceeding."
        echo ""
        echo "=== Quick Resolution Guide ==="
        echo "1. Install AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        echo "2. Configure credentials: aws configure"
        echo "3. Set region: aws configure set region <region-name>"
        echo "4. Contact administrator for permissions"
        echo ""
        echo "For detailed help, run: $0 --help"
        return 1
    fi
    
    log_success "✅ AWS CLI validation completed successfully"
    echo ""
    echo "=== Ready for Deployment ==="
    echo "Your AWS CLI is properly configured and ready for deployment operations."
    echo ""
    
    return 0
}

# Function to run AWS CLI diagnostics
run_aws_diagnostics() {
    log_info "Running AWS CLI diagnostics..."
    echo ""
    
    echo "=== System Information ==="
    echo "Operating System: $(uname -s)"
    echo "Architecture: $(uname -m)"
    echo "Shell: $SHELL"
    echo "User: $(whoami)"
    echo ""
    
    echo "=== AWS CLI Information ==="
    if command -v aws &> /dev/null; then
        echo "AWS CLI Version: $(aws --version 2>&1)"
        echo "AWS CLI Location: $(which aws)"
        
        # Check Python version (AWS CLI dependency)
        if command -v python3 &> /dev/null; then
            echo "Python3 Version: $(python3 --version 2>&1)"
        fi
        
        # Check configuration files
        echo ""
        echo "=== Configuration Files ==="
        local aws_dir="$HOME/.aws"
        if [ -d "$aws_dir" ]; then
            echo "AWS Directory: $aws_dir"
            if [ -f "$aws_dir/config" ]; then
                echo "Config file: ✅ Present"
                echo "Config file size: $(wc -c < "$aws_dir/config") bytes"
            else
                echo "Config file: ❌ Missing"
            fi
            
            if [ -f "$aws_dir/credentials" ]; then
                echo "Credentials file: ✅ Present"
                echo "Credentials file size: $(wc -c < "$aws_dir/credentials") bytes"
            else
                echo "Credentials file: ❌ Missing"
            fi
        else
            echo "AWS Directory: ❌ Missing ($aws_dir)"
        fi
    else
        echo "AWS CLI: ❌ Not installed or not in PATH"
    fi
    
    echo ""
    echo "=== Environment Variables ==="
    env | grep -E '^AWS_' | sort || echo "No AWS environment variables set"
    
    echo ""
    echo "=== Network Connectivity ==="
    if command -v curl &> /dev/null; then
        echo -n "AWS API connectivity: "
        if curl -s --connect-timeout 5 https://sts.amazonaws.com/ > /dev/null; then
            echo "✅ Connected"
        else
            echo "❌ Failed"
        fi
    else
        echo "Cannot test connectivity (curl not available)"
    fi
    
    echo ""
}

# Function to display comprehensive AWS CLI setup instructions
show_aws_setup_instructions() {
    echo ""
    echo "==============================================="
    echo "        AWS CLI Setup Instructions"
    echo "==============================================="
    echo ""
    
    echo "🚀 STEP 1: Install AWS CLI v2"
    echo "────────────────────────────────"
    echo ""
    echo "Windows:"
    echo "  • Download: https://awscli.amazonaws.com/AWSCLIV2.msi"
    echo "  • Run installer and follow prompts"
    echo "  • Restart command prompt/PowerShell"
    echo ""
    echo "macOS:"
    echo "  • Homebrew: brew install awscli"
    echo "  • Direct download: https://awscli.amazonaws.com/AWSCLIV2.pkg"
    echo ""
    echo "Linux (x86_64):"
    echo "  curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'"
    echo "  unzip awscliv2.zip"
    echo "  sudo ./aws/install"
    echo ""
    echo "Linux (ARM):"
    echo "  curl 'https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip' -o 'awscliv2.zip'"
    echo "  unzip awscliv2.zip"
    echo "  sudo ./aws/install"
    echo ""
    
    echo "🔐 STEP 2: Get AWS Access Keys"
    echo "────────────────────────────────"
    echo ""
    echo "1. Sign in to AWS Console: https://console.aws.amazon.com/"
    echo "2. Navigate to: IAM → Users → [Your Username]"
    echo "3. Click 'Security credentials' tab"
    echo "4. Click 'Create access key'"
    echo "5. Choose 'Command Line Interface (CLI)'"
    echo "6. Add description tag (optional)"
    echo "7. Download credentials CSV file"
    echo ""
    echo "⚠️  SECURITY NOTE: Never share or commit access keys!"
    echo ""
    
    echo "⚙️  STEP 3: Configure AWS CLI"
    echo "────────────────────────────────"
    echo ""
    echo "Basic Configuration:"
    echo "  aws configure"
    echo ""
    echo "You'll be prompted for:"
    echo "  • AWS Access Key ID: [From step 2]"
    echo "  • AWS Secret Access Key: [From step 2]"
    echo "  • Default region: [See region recommendations below]"
    echo "  • Default output format: json (recommended)"
    echo ""
    echo "Multiple Profiles (Optional):"
    echo "  aws configure --profile <profile-name>"
    echo "  export AWS_PROFILE=<profile-name>"
    echo ""
    
    echo "🌍 STEP 4: Choose AWS Region"
    echo "────────────────────────────────"
    echo ""
    echo "For Vietnam-based users:"
    echo "  🥇 ap-southeast-1 (Singapore)    - Best latency (~50-80ms)"
    echo "  🥈 ap-northeast-1 (Tokyo)        - Good latency (~80-120ms)"
    echo "  🥉 us-east-1 (N. Virginia)       - Lowest cost (~200-250ms)"
    echo ""
    echo "Global considerations:"
    echo "  • us-east-1: Lowest cost, most services"
    echo "  • us-west-2: Good cost, renewable energy"
    echo "  • eu-west-1: GDPR compliance"
    echo ""
    
    echo "✅ STEP 5: Verify Installation"
    echo "────────────────────────────────"
    echo ""
    echo "Check AWS CLI version:"
    echo "  aws --version"
    echo ""
    echo "Verify credentials:"
    echo "  aws sts get-caller-identity"
    echo ""
    echo "Test basic functionality:"
    echo "  aws s3 ls"
    echo ""
    
    echo "🔧 TROUBLESHOOTING"
    echo "────────────────────────────────"
    echo ""
    echo "Command not found:"
    echo "  • Restart terminal/command prompt"
    echo "  • Check PATH environment variable"
    echo "  • Reinstall AWS CLI"
    echo ""
    echo "Permission denied:"
    echo "  • Check access key permissions"
    echo "  • Verify IAM user has required policies"
    echo "  • Contact AWS administrator"
    echo ""
    echo "Invalid credentials:"
    echo "  • Verify access keys are correct"
    echo "  • Check if keys are expired or disabled"
    echo "  • Reconfigure: aws configure"
    echo ""
    
    echo "📚 ADDITIONAL RESOURCES"
    echo "────────────────────────────────"
    echo ""
    echo "Official Documentation:"
    echo "  https://docs.aws.amazon.com/cli/latest/userguide/"
    echo ""
    echo "AWS CLI Command Reference:"
    echo "  https://docs.aws.amazon.com/cli/latest/reference/"
    echo ""
    echo "IAM Best Practices:"
    echo "  https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html"
    echo ""
    echo "AWS Free Tier:"
    echo "  https://aws.amazon.com/free/"
    echo ""
    
    echo "🎯 NEXT STEPS"
    echo "────────────────────────────────"
    echo ""
    echo "After setup, run this script again:"
    echo "  $0 --validate"
    echo ""
    echo "Or run deployment validation:"
    echo "  ./scripts/utilities/validate-aws-cli.sh"
    echo ""
    echo "==============================================="
    echo ""
}

# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [COMMAND]

AWS CLI validation and setup utility for deployment automation.

COMMANDS:
    validate        Perform comprehensive AWS CLI validation (default)
    setup           Show detailed setup instructions
    profiles        List and analyze configured profiles
    diagnostics     Run system and AWS CLI diagnostics
    permissions     Check deployment permissions only
    region          Check and validate region configuration

OPTIONS:
    --profile PROFILE       Use specific AWS profile
    --region REGION         Override region for validation
    --help                  Show this help message
    --verbose               Enable verbose logging
    --quiet                 Suppress non-error output

EXAMPLES:
    $0                                    # Basic validation
    $0 validate --profile production      # Validate specific profile
    $0 setup                             # Show setup instructions
    $0 profiles                          # List all profiles
    $0 diagnostics                       # Run diagnostics
    $0 permissions --profile dev         # Check permissions only

VALIDATION CHECKS:
    ✓ AWS CLI installation and version
    ✓ Credential configuration and validity
    ✓ Region configuration and accessibility
    ✓ Required permissions for deployment
    ✓ Profile validation (if specified)

RETURN CODES:
    0    All validations passed
    1    Validation failed or error occurred
    2    Invalid arguments or usage

EOF
}

# Main function to handle command-line interface
main() {
    local command="validate"
    local profile=""
    local region=""
    local verbose=false
    local quiet=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            validate|setup|profiles|diagnostics|permissions|region)
                command="$1"
                shift
                ;;
            --profile)
                profile="$2"
                shift 2
                ;;
            --region)
                region="$2"
                shift 2
                ;;
            --verbose)
                verbose=true
                shift
                ;;
            --quiet)
                quiet=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 2
                ;;
        esac
    done
    
    # Set logging level
    if [ "$verbose" = true ]; then
        export LOG_LEVEL="DEBUG"
    elif [ "$quiet" = true ]; then
        export LOG_LEVEL="ERROR"
    fi
    
    # Override region if specified
    if [ -n "$region" ]; then
        export AWS_DEFAULT_REGION="$region"
    fi
    
    # Execute command
    case "$command" in
        "validate")
            validate_aws_cli "$profile"
            ;;
        "setup")
            show_aws_setup_instructions
            ;;
        "profiles")
            list_aws_profiles
            ;;
        "diagnostics")
            run_aws_diagnostics
            ;;
        "permissions")
            if [ -n "$profile" ]; then
                validate_aws_profile "$profile" || exit 1
            fi
            check_aws_permissions
            ;;
        "region")
            check_aws_region
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 2
            ;;
    esac
}

# Export functions for use in other scripts
export -f get_aws_region check_aws_cli_installation check_aws_credentials check_aws_region
export -f check_aws_permissions validate_aws_profile validate_aws_cli
export -f show_aws_setup_instructions list_aws_profiles run_aws_diagnostics
export -f provide_credential_setup_instructions provide_region_recommendations
export -f provide_permission_remediation

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi