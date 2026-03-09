#!/bin/bash

# Cognito Configuration Validation Utility
# Validates UserPoolId and ClientId configuration for Lambda integration
# Tests connectivity between Lambda and Cognito services
# Verifies JWT token validation functionality

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/error-handling.sh"

# Cognito configuration validation
declare -A COGNITO_CONFIG_KEYS=(
    ["UserPoolId"]="AWS Cognito User Pool ID"
    ["ClientId"]="AWS Cognito App Client ID"
    ["Region"]="AWS Region for Cognito service"
    ["JwtIssuer"]="JWT token issuer URL"
    ["JwtAudience"]="JWT token audience"
)

# Function to validate Cognito User Pool ID format
validate_user_pool_id() {
    local user_pool_id="$1"
    
    log_debug "Validating User Pool ID format: $user_pool_id"
    
    # AWS Cognito User Pool ID format: region_randomstring
    # Example: us-east-1_abcdef123
    if [[ "$user_pool_id" =~ ^[a-z]{2,3}-[a-z]+-[0-9]+_[A-Za-z0-9]+$ ]]; then
        log_success "User Pool ID format is valid"
        
        # Extract region from User Pool ID
        local pool_region=$(echo "$user_pool_id" | cut -d'_' -f1)
        log_info "Detected region from User Pool ID: $pool_region"
        
        return 0
    else
        log_error "Invalid User Pool ID format: $user_pool_id"
        log_error "Expected format: region_randomstring (e.g., us-east-1_abcdef123)"
        return 1
    fi
}

# Function to validate Cognito Client ID format
validate_client_id() {
    local client_id="$1"
    
    log_debug "Validating Client ID format: $client_id"
    
    # AWS Cognito Client ID format: 26 character alphanumeric string
    if [[ "$client_id" =~ ^[a-z0-9]{26}$ ]]; then
        log_success "Client ID format is valid"
        return 0
    else
        log_error "Invalid Client ID format: $client_id"
        log_error "Expected format: 26 character lowercase alphanumeric string"
        return 1
    fi
}

# Function to check if User Pool exists and is accessible
check_user_pool_exists() {
    local user_pool_id="$1"
    local region="${2:-}"
    
    log_info "Checking if User Pool exists: $user_pool_id"
    
    # Extract region from User Pool ID if not provided
    if [ -z "$region" ]; then
        region=$(echo "$user_pool_id" | cut -d'_' -f1)
    fi
    
    # Try to describe the User Pool
    local describe_result
    if describe_result=$(aws cognito-idp describe-user-pool --user-pool-id "$user_pool_id" --region "$region" 2>&1); then
        log_success "User Pool exists and is accessible"
        
        # Extract useful information
        local pool_name=$(echo "$describe_result" | grep -o '"Name": "[^"]*"' | cut -d'"' -f4 | head -1)
        local pool_status=$(echo "$describe_result" | grep -o '"Status": "[^"]*"' | cut -d'"' -f4 | head -1)
        local creation_date=$(echo "$describe_result" | grep -o '"CreationDate": "[^"]*"' | cut -d'"' -f4 | head -1)
        
        log_info "User Pool Details:"
        log_info "  Name: ${pool_name:-"Not specified"}"
        log_info "  Status: ${pool_status:-"Unknown"}"
        log_info "  Region: $region"
        if [ -n "$creation_date" ]; then
            log_info "  Created: $creation_date"
        fi
        
        return 0
    else
        log_error "User Pool not found or not accessible: $user_pool_id"
        log_error "AWS CLI response: $describe_result"
        
        # Provide troubleshooting guidance
        echo ""
        echo "=== User Pool Troubleshooting ==="
        echo "1. Verify User Pool ID is correct"
        echo "2. Check AWS region matches User Pool region ($region)"
        echo "3. Ensure AWS credentials have Cognito permissions"
        echo "4. Verify User Pool exists in AWS Console"
        echo ""
        
        return 1
    fi
}

# Function to check if App Client exists and is accessible
check_app_client_exists() {
    local user_pool_id="$1"
    local client_id="$2"
    local region="${3:-}"
    
    log_info "Checking if App Client exists: $client_id"
    
    # Extract region from User Pool ID if not provided
    if [ -z "$region" ]; then
        region=$(echo "$user_pool_id" | cut -d'_' -f1)
    fi
    
    # Try to describe the App Client
    local describe_result
    if describe_result=$(aws cognito-idp describe-user-pool-client --user-pool-id "$user_pool_id" --client-id "$client_id" --region "$region" 2>&1); then
        log_success "App Client exists and is accessible"
        
        # Extract useful information
        local client_name=$(echo "$describe_result" | grep -o '"ClientName": "[^"]*"' | cut -d'"' -f4 | head -1)
        local generate_secret=$(echo "$describe_result" | grep -o '"GenerateSecret": [^,}]*' | cut -d':' -f2 | tr -d ' ')
        local refresh_token_validity=$(echo "$describe_result" | grep -o '"RefreshTokenValidity": [^,}]*' | cut -d':' -f2 | tr -d ' ')
        
        log_info "App Client Details:"
        log_info "  Name: ${client_name:-"Not specified"}"
        log_info "  Has Secret: ${generate_secret:-"Unknown"}"
        log_info "  Refresh Token Validity: ${refresh_token_validity:-"Unknown"} days"
        
        # Check for potential configuration issues
        if [ "$generate_secret" = "true" ]; then
            log_warn "App Client has secret enabled - ensure Lambda handles client secret properly"
        fi
        
        return 0
    else
        log_error "App Client not found or not accessible: $client_id"
        log_error "AWS CLI response: $describe_result"
        
        # Provide troubleshooting guidance
        echo ""
        echo "=== App Client Troubleshooting ==="
        echo "1. Verify Client ID is correct"
        echo "2. Check Client belongs to the specified User Pool"
        echo "3. Ensure AWS credentials have Cognito permissions"
        echo "4. Verify App Client exists in AWS Console"
        echo ""
        
        return 1
    fi
}
# Function to validate JWT issuer URL
validate_jwt_issuer() {
    local user_pool_id="$1"
    local jwt_issuer="$2"
    local region="${3:-}"
    
    log_info "Validating JWT issuer URL"
    
    # Extract region from User Pool ID if not provided
    if [ -z "$region" ]; then
        region=$(echo "$user_pool_id" | cut -d'_' -f1)
    fi
    
    # Expected JWT issuer format: https://cognito-idp.{region}.amazonaws.com/{userPoolId}
    local expected_issuer="https://cognito-idp.${region}.amazonaws.com/${user_pool_id}"
    
    if [ "$jwt_issuer" = "$expected_issuer" ]; then
        log_success "JWT issuer URL is correct"
        return 0
    else
        log_error "JWT issuer URL mismatch"
        log_error "Expected: $expected_issuer"
        log_error "Actual: $jwt_issuer"
        
        echo ""
        echo "=== JWT Issuer Configuration ==="
        echo "The JWT issuer should match the Cognito User Pool issuer URL."
        echo "Update your configuration to use: $expected_issuer"
        echo ""
        
        return 1
    fi
}

# Function to test JWT token validation endpoint
test_jwt_validation_endpoint() {
    local user_pool_id="$1"
    local region="${2:-}"
    
    log_info "Testing JWT validation endpoint accessibility"
    
    # Extract region from User Pool ID if not provided
    if [ -z "$region" ]; then
        region=$(echo "$user_pool_id" | cut -d'_' -f1)
    fi
    
    # JWT keys endpoint
    local jwks_url="https://cognito-idp.${region}.amazonaws.com/${user_pool_id}/.well-known/jwks.json"
    
    log_debug "Testing JWKS endpoint: $jwks_url"
    
    # Test endpoint accessibility
    if command -v curl &> /dev/null; then
        local response
        local http_code
        
        response=$(curl -s -w "%{http_code}" --connect-timeout 10 --max-time 30 "$jwks_url" 2>/dev/null)
        http_code="${response: -3}"
        response="${response%???}"
        
        if [ "$http_code" = "200" ]; then
            log_success "JWT validation endpoint is accessible"
            
            # Validate response contains keys
            if echo "$response" | grep -q '"keys"'; then
                log_success "JWKS response contains valid key information"
                
                # Count available keys
                local key_count=$(echo "$response" | grep -o '"kid"' | wc -l)
                log_info "Available JWT signing keys: $key_count"
                
                return 0
            else
                log_error "JWKS response does not contain valid key information"
                log_debug "Response: $response"
                return 1
            fi
        else
            log_error "JWT validation endpoint returned HTTP $http_code"
            log_error "URL: $jwks_url"
            
            case "$http_code" in
                "404")
                    log_error "User Pool not found or JWKS endpoint not available"
                    ;;
                "403")
                    log_error "Access denied to JWKS endpoint"
                    ;;
                "000")
                    log_error "Connection failed - check network connectivity"
                    ;;
                *)
                    log_error "Unexpected HTTP response code"
                    ;;
            esac
            
            return 1
        fi
    else
        log_warn "curl not available - skipping JWT endpoint test"
        log_info "Install curl to enable JWT endpoint validation"
        return 0
    fi
}

# Function to validate Cognito configuration from appsettings.json
validate_cognito_config_file() {
    local config_file="$1"
    
    log_info "Validating Cognito configuration from: $config_file"
    
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Check if file contains JSON
    if ! command -v jq &> /dev/null; then
        log_warn "jq not available - using basic text parsing"
        return validate_cognito_config_file_basic "$config_file"
    fi
    
    # Parse JSON configuration
    local user_pool_id client_id region jwt_issuer jwt_audience
    
    # Try different possible configuration paths
    user_pool_id=$(jq -r '.AWS.Cognito.UserPoolId // .Cognito.UserPoolId // .UserPoolId // empty' "$config_file" 2>/dev/null)
    client_id=$(jq -r '.AWS.Cognito.ClientId // .Cognito.ClientId // .ClientId // empty' "$config_file" 2>/dev/null)
    region=$(jq -r '.AWS.Region // .Region // empty' "$config_file" 2>/dev/null)
    jwt_issuer=$(jq -r '.JWT.Issuer // .Jwt.Issuer // .JwtIssuer // empty' "$config_file" 2>/dev/null)
    jwt_audience=$(jq -r '.JWT.Audience // .Jwt.Audience // .JwtAudience // empty' "$config_file" 2>/dev/null)
    
    local validation_failed=false
    
    # Validate required fields
    if [ -z "$user_pool_id" ] || [ "$user_pool_id" = "null" ]; then
        log_error "UserPoolId not found in configuration"
        validation_failed=true
    else
        log_info "Found UserPoolId: $user_pool_id"
        if ! validate_user_pool_id "$user_pool_id"; then
            validation_failed=true
        fi
    fi
    
    if [ -z "$client_id" ] || [ "$client_id" = "null" ]; then
        log_error "ClientId not found in configuration"
        validation_failed=true
    else
        log_info "Found ClientId: $client_id"
        if ! validate_client_id "$client_id"; then
            validation_failed=true
        fi
    fi
    
    if [ -z "$region" ] || [ "$region" = "null" ]; then
        log_warn "Region not found in configuration - will extract from UserPoolId"
        if [ -n "$user_pool_id" ] && [ "$user_pool_id" != "null" ]; then
            region=$(echo "$user_pool_id" | cut -d'_' -f1)
            log_info "Extracted region from UserPoolId: $region"
        fi
    else
        log_info "Found Region: $region"
    fi
    
    # Validate JWT configuration if present
    if [ -n "$jwt_issuer" ] && [ "$jwt_issuer" != "null" ]; then
        log_info "Found JWT Issuer: $jwt_issuer"
        if [ -n "$user_pool_id" ] && [ "$user_pool_id" != "null" ]; then
            if ! validate_jwt_issuer "$user_pool_id" "$jwt_issuer" "$region"; then
                validation_failed=true
            fi
        fi
    else
        log_warn "JWT Issuer not configured - Lambda may need manual JWT validation setup"
    fi
    
    if [ -n "$jwt_audience" ] && [ "$jwt_audience" != "null" ]; then
        log_info "Found JWT Audience: $jwt_audience"
        # JWT audience should typically match the Client ID
        if [ -n "$client_id" ] && [ "$client_id" != "null" ] && [ "$jwt_audience" != "$client_id" ]; then
            log_warn "JWT Audience ($jwt_audience) does not match Client ID ($client_id)"
            log_warn "This may be intentional, but verify JWT validation logic"
        fi
    fi
    
    # Test connectivity if we have valid configuration
    if [ "$validation_failed" = false ] && [ -n "$user_pool_id" ] && [ -n "$client_id" ]; then
        log_info "Testing Cognito service connectivity..."
        
        if check_user_pool_exists "$user_pool_id" "$region"; then
            if check_app_client_exists "$user_pool_id" "$client_id" "$region"; then
                if test_jwt_validation_endpoint "$user_pool_id" "$region"; then
                    log_success "All Cognito connectivity tests passed"
                else
                    log_warn "JWT validation endpoint test failed"
                    validation_failed=true
                fi
            else
                validation_failed=true
            fi
        else
            validation_failed=true
        fi
    fi
    
    if [ "$validation_failed" = true ]; then
        log_error "Cognito configuration validation failed"
        return 1
    else
        log_success "Cognito configuration validation passed"
        return 0
    fi
}

# Function to validate Cognito configuration using basic text parsing (fallback)
validate_cognito_config_file_basic() {
    local config_file="$1"
    
    log_debug "Using basic text parsing for configuration validation"
    
    local user_pool_id client_id region
    local validation_failed=false
    
    # Extract configuration values using grep and sed
    user_pool_id=$(grep -i "userpoolid\|UserPoolId" "$config_file" | head -1 | sed 's/.*[":]\s*"\([^"]*\)".*/\1/' | tr -d ' ')
    client_id=$(grep -i "clientid\|ClientId" "$config_file" | head -1 | sed 's/.*[":]\s*"\([^"]*\)".*/\1/' | tr -d ' ')
    region=$(grep -i "region\|Region" "$config_file" | head -1 | sed 's/.*[":]\s*"\([^"]*\)".*/\1/' | tr -d ' ')
    
    # Validate extracted values
    if [ -z "$user_pool_id" ]; then
        log_error "UserPoolId not found in configuration"
        validation_failed=true
    else
        log_info "Found UserPoolId: $user_pool_id"
        if ! validate_user_pool_id "$user_pool_id"; then
            validation_failed=true
        fi
    fi
    
    if [ -z "$client_id" ]; then
        log_error "ClientId not found in configuration"
        validation_failed=true
    else
        log_info "Found ClientId: $client_id"
        if ! validate_client_id "$client_id"; then
            validation_failed=true
        fi
    fi
    
    if [ -z "$region" ]; then
        log_warn "Region not found in configuration"
        if [ -n "$user_pool_id" ]; then
            region=$(echo "$user_pool_id" | cut -d'_' -f1)
            log_info "Extracted region from UserPoolId: $region"
        fi
    else
        log_info "Found Region: $region"
    fi
    
    # Test connectivity if we have valid configuration
    if [ "$validation_failed" = false ] && [ -n "$user_pool_id" ] && [ -n "$client_id" ]; then
        log_info "Testing Cognito service connectivity..."
        
        if check_user_pool_exists "$user_pool_id" "$region"; then
            if check_app_client_exists "$user_pool_id" "$client_id" "$region"; then
                log_success "Cognito connectivity tests passed"
            else
                validation_failed=true
            fi
        else
            validation_failed=true
        fi
    fi
    
    if [ "$validation_failed" = true ]; then
        return 1
    else
        return 0
    fi
}

# Function to generate Cognito configuration template
generate_cognito_config_template() {
    local output_file="${1:-cognito-config-template.json}"
    
    log_info "Generating Cognito configuration template: $output_file"
    
    cat > "$output_file" << 'EOF'
{
  "AWS": {
    "Region": "us-east-1",
    "Cognito": {
      "UserPoolId": "us-east-1_abcdef123",
      "ClientId": "1234567890abcdefghijklmnop"
    }
  },
  "JWT": {
    "Issuer": "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_abcdef123",
    "Audience": "1234567890abcdefghijklmnop",
    "ValidateIssuer": true,
    "ValidateAudience": true,
    "ValidateLifetime": true,
    "ClockSkew": "00:05:00"
  }
}
EOF
    
    log_success "Configuration template created: $output_file"
    
    echo ""
    echo "=== Configuration Template Usage ==="
    echo "1. Replace placeholder values with your actual Cognito configuration:"
    echo "   - UserPoolId: Your Cognito User Pool ID"
    echo "   - ClientId: Your Cognito App Client ID"
    echo "   - Region: Your AWS region"
    echo ""
    echo "2. Update JWT settings as needed:"
    echo "   - Issuer: Should match Cognito User Pool issuer"
    echo "   - Audience: Typically matches ClientId"
    echo "   - Validation settings: Configure based on security requirements"
    echo ""
    echo "3. Integrate into your appsettings.json or environment variables"
    echo ""
}

# Function to check Cognito permissions
check_cognito_permissions() {
    log_info "Checking AWS permissions for Cognito operations..."
    
    local permissions_ok=true
    local missing_permissions=()
    
    # Test Cognito Identity Provider permissions
    log_debug "Testing Cognito Identity Provider permissions..."
    if ! aws cognito-idp list-user-pools --max-results 1 &> /dev/null; then
        log_warn "Missing Cognito Identity Provider permissions (list-user-pools)"
        missing_permissions+=("cognito-idp:ListUserPools")
        permissions_ok=false
    else
        log_debug "✓ Cognito Identity Provider list permissions available"
    fi
    
    # Test describe permissions
    if ! aws cognito-idp list-user-pool-clients --user-pool-id "test" --max-results 1 2>&1 | grep -q "InvalidParameterException\|ResourceNotFoundException"; then
        if ! aws cognito-idp list-user-pool-clients --user-pool-id "test" --max-results 1 &> /dev/null; then
            log_warn "Missing Cognito client permissions (list-user-pool-clients)"
            missing_permissions+=("cognito-idp:ListUserPoolClients")
            permissions_ok=false
        fi
    else
        log_debug "✓ Cognito client list permissions available"
    fi
    
    # Report results
    if [ "$permissions_ok" = true ]; then
        log_success "Required Cognito permissions are available"
        return 0
    else
        log_error "Missing Cognito permissions detected"
        echo ""
        echo "=== Missing Cognito Permissions ==="
        for permission in "${missing_permissions[@]}"; do
            echo "❌ $permission"
        done
        echo ""
        echo "=== Required IAM Permissions ==="
        echo "Add these permissions to your IAM user/role:"
        echo "  - cognito-idp:DescribeUserPool"
        echo "  - cognito-idp:DescribeUserPoolClient"
        echo "  - cognito-idp:ListUserPools"
        echo "  - cognito-idp:ListUserPoolClients"
        echo ""
        echo "Or attach the managed policy: AmazonCognitoPowerUser"
        echo ""
        return 1
    fi
}

# Function to provide Cognito setup guidance
provide_cognito_setup_guidance() {
    echo ""
    echo "=== AWS Cognito Setup Guide ==="
    echo ""
    echo "🔧 Creating a User Pool:"
    echo "1. Go to AWS Console → Cognito → User Pools"
    echo "2. Click 'Create user pool'"
    echo "3. Configure sign-in options (email, username, etc.)"
    echo "4. Configure security requirements (password policy, MFA)"
    echo "5. Configure message delivery (email/SMS)"
    echo "6. Review and create"
    echo ""
    echo "🔧 Creating an App Client:"
    echo "1. In your User Pool, go to 'App integration' tab"
    echo "2. Click 'Create app client'"
    echo "3. Choose 'Public client' for mobile/web apps"
    echo "4. Configure authentication flows"
    echo "5. Set token expiration times"
    echo "6. Create the client"
    echo ""
    echo "🔧 Integration with Lambda:"
    echo "1. Note your User Pool ID and App Client ID"
    echo "2. Configure JWT validation in your Lambda function"
    echo "3. Set up proper IAM permissions for Lambda"
    echo "4. Test authentication flow"
    echo ""
    echo "🔧 Vietnamese Context Considerations:"
    echo "1. Choose ap-southeast-1 (Singapore) region for lowest latency"
    echo "2. Configure Vietnamese language support if needed"
    echo "3. Consider local compliance requirements"
    echo "4. Set appropriate token expiration for user experience"
    echo ""
}

# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Cognito configuration validation utility for AWS deployment automation.

COMMANDS:
    validate        Validate Cognito configuration from file
    check           Check Cognito service connectivity
    permissions     Check required AWS permissions
    template        Generate configuration template
    setup           Show Cognito setup guidance

OPTIONS:
    --config FILE           Configuration file to validate (default: appsettings.json)
    --user-pool-id ID       User Pool ID to validate
    --client-id ID          App Client ID to validate
    --region REGION         AWS region (auto-detected from User Pool ID)
    --output FILE           Output file for template generation
    --help                  Show this help message

EXAMPLES:
    # Validate configuration from appsettings.json
    $0 validate --config appsettings.json

    # Check specific Cognito resources
    $0 check --user-pool-id us-east-1_abcdef123 --client-id 1234567890abcdefghijklmnop

    # Generate configuration template
    $0 template --output my-cognito-config.json

    # Check permissions
    $0 permissions

    # Show setup guidance
    $0 setup

VALIDATION CHECKS:
    ✓ User Pool ID format and existence
    ✓ App Client ID format and existence
    ✓ JWT issuer URL validation
    ✓ Service connectivity testing
    ✓ Required AWS permissions

EOF
}

# Main function to handle command-line interface
main() {
    local command=""
    local config_file="appsettings.json"
    local user_pool_id=""
    local client_id=""
    local region=""
    local output_file=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            validate|check|permissions|template|setup)
                command="$1"
                shift
                ;;
            --config)
                config_file="$2"
                shift 2
                ;;
            --user-pool-id)
                user_pool_id="$2"
                shift 2
                ;;
            --client-id)
                client_id="$2"
                shift 2
                ;;
            --region)
                region="$2"
                shift 2
                ;;
            --output)
                output_file="$2"
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
        "validate")
            if [ ! -f "$config_file" ]; then
                log_error "Configuration file not found: $config_file"
                exit 1
            fi
            validate_cognito_config_file "$config_file"
            ;;
        "check")
            if [ -z "$user_pool_id" ] || [ -z "$client_id" ]; then
                log_error "User Pool ID and Client ID are required for check command"
                exit 1
            fi
            
            local validation_failed=false
            
            if ! validate_user_pool_id "$user_pool_id"; then
                validation_failed=true
            fi
            
            if ! validate_client_id "$client_id"; then
                validation_failed=true
            fi
            
            if [ "$validation_failed" = false ]; then
                if ! check_user_pool_exists "$user_pool_id" "$region"; then
                    validation_failed=true
                fi
                
                if ! check_app_client_exists "$user_pool_id" "$client_id" "$region"; then
                    validation_failed=true
                fi
                
                if ! test_jwt_validation_endpoint "$user_pool_id" "$region"; then
                    validation_failed=true
                fi
            fi
            
            if [ "$validation_failed" = true ]; then
                exit 1
            fi
            ;;
        "permissions")
            check_cognito_permissions
            ;;
        "template")
            local template_file="${output_file:-cognito-config-template.json}"
            generate_cognito_config_template "$template_file"
            ;;
        "setup")
            provide_cognito_setup_guidance
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
export -f validate_user_pool_id validate_client_id check_user_pool_exists
export -f check_app_client_exists validate_jwt_issuer test_jwt_validation_endpoint
export -f validate_cognito_config_file check_cognito_permissions

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi