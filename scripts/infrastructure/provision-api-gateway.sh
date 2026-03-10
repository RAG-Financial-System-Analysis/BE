#!/bin/bash

# API Gateway Provisioning Script
# Creates API Gateway with Lambda integration for Swagger access
# Provides public HTTP endpoint for .NET API

set -euo pipefail

# Initialize AWS_PROFILE with default value if not set
AWS_PROFILE="${AWS_PROFILE:-}"

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILITIES_DIR="$SCRIPT_DIR/../utilities"
source "$UTILITIES_DIR/logging.sh"
source "$UTILITIES_DIR/error-handling.sh"
source "$UTILITIES_DIR/validate-aws-cli.sh"

# Resource naming
ENVIRONMENT="${ENVIRONMENT:-dev}"
PROJECT_NAME="${PROJECT_NAME:-myragapp}"
API_NAME="$PROJECT_NAME-$ENVIRONMENT-api"
STAGE_NAME="$ENVIRONMENT"

# Global variables for resource tracking
API_ID=""
API_URL=""
LAMBDA_FUNCTION_NAME=""

# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Provisions API Gateway with Lambda integration for HTTP access.
Creates public endpoint for Swagger and API access.

OPTIONS:
    --environment ENV          Environment name (default: dev)
    --project-name NAME        Project name (default: myapp)
    --stage-name STAGE         API Gateway stage name (default: environment name)
    --aws-profile PROFILE      AWS profile to use
    --help                     Show this help message

EXAMPLES:
    $0 --environment production --project-name rag-system
    $0 --stage-name v1 --aws-profile prod

FEATURES:
    - REST API Gateway with Lambda proxy integration
    - CORS enabled for frontend access
    - Custom domain support (optional)
    - Swagger/OpenAPI documentation endpoint
    - Request/response logging

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
            --stage-name)
                STAGE_NAME="$2"
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
    API_NAME="$PROJECT_NAME-$ENVIRONMENT-api"
    LAMBDA_FUNCTION_NAME="$PROJECT_NAME-$ENVIRONMENT-api"
    
    # Use environment as default stage name if not specified
    if [ "$STAGE_NAME" = "dev" ] && [ "$ENVIRONMENT" != "dev" ]; then
        STAGE_NAME="$ENVIRONMENT"
    fi
}

# Function to get Lambda function ARN
get_lambda_function_arn() {
    # Try to get function name from Lambda infrastructure state first
    local state_file="./deployment_checkpoints/lambda_infrastructure.state"
    if [ -f "$state_file" ]; then
        source "$state_file"
        if [ -n "$LAMBDA_FUNCTION_NAME" ]; then
            log_info "Using Lambda function name from state: $LAMBDA_FUNCTION_NAME"
        fi
    fi
    
    log_info "Getting Lambda function ARN: $LAMBDA_FUNCTION_NAME"
    
    local function_arn=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Configuration.FunctionArn' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$function_arn" = "None" ] || [ "$function_arn" = "null" ]; then
        handle_error $ERROR_CODE_LAMBDA "Lambda function not found: $LAMBDA_FUNCTION_NAME. Run provision-lambda.sh first." true
    fi
    
    log_success "Found Lambda function: $function_arn"
    echo "$function_arn"
}

# Function to check if API Gateway already exists
check_existing_api_gateway() {
    log_info "Checking for existing API Gateway: $API_NAME"
    
    local api_id=$(aws apigateway get-rest-apis \
        --query "items[?name=='$API_NAME'].id" \
        --output text 2>/dev/null || echo "None")
    
    if [ "$api_id" != "None" ] && [ "$api_id" != "null" ] && [ -n "$api_id" ]; then
        log_info "Found existing API Gateway: $api_id"
        API_ID="$api_id"
        return 0
    fi
    
    return 1
}

# Function to create API Gateway
create_api_gateway() {
    if check_existing_api_gateway; then
        log_info "Using existing API Gateway: $API_ID"
        return 0
    fi
    
    log_info "Creating API Gateway: $API_NAME"
    set_error_context "API Gateway creation"
    set_error_remediation "Check AWS permissions for API Gateway operations"
    
    API_ID=$(execute_with_error_handling \
        "aws apigateway create-rest-api --name $API_NAME --description 'API Gateway for $PROJECT_NAME $ENVIRONMENT' --query 'id' --output text" \
        "Failed to create API Gateway" \
        $ERROR_CODE_INFRASTRUCTURE)
    
    log_success "Created API Gateway: $API_ID"
    
    # Tag the API Gateway - use flexible region detection
    source "$SCRIPT_DIR/../utilities/validate-aws-cli.sh"
    local aws_region=$(get_aws_region)
    local api_arn="arn:aws:apigateway:$aws_region::/restapis/$API_ID"
    execute_with_error_handling \
        "aws apigateway tag-resource --resource-arn '$api_arn' --tags Environment=$ENVIRONMENT,Project=$PROJECT_NAME" \
        "Failed to tag API Gateway" \
        $ERROR_CODE_INFRASTRUCTURE
    
    register_cleanup_function "cleanup_api_gateway"
}

# Function to setup Lambda integration
setup_lambda_integration() {
    log_info "Setting up Lambda integration for API Gateway"
    
    local lambda_arn=$(get_lambda_function_arn)
    # Use flexible region detection
    source "$SCRIPT_DIR/../utilities/validate-aws-cli.sh"
    local aws_region=$(get_aws_region)
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    
    # Get root resource ID
    local root_resource_id=$(aws apigateway get-resources \
        --rest-api-id "$API_ID" \
        --query 'items[?path==`/`].id' \
        --output text)
    
    log_info "Root resource ID: $root_resource_id"
    
    # Create proxy resource {proxy+}
    log_info "Creating proxy resource"
    local proxy_resource_id=$(aws apigateway get-resources \
        --rest-api-id "$API_ID" \
        --query 'items[?pathPart==`{proxy+}`].id' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$proxy_resource_id" ] || [ "$proxy_resource_id" = "None" ]; then
        proxy_resource_id=$(execute_with_error_handling \
            "aws apigateway create-resource --rest-api-id $API_ID --parent-id $root_resource_id --path-part '{proxy+}' --query 'id' --output text" \
            "Failed to create proxy resource" \
            $ERROR_CODE_INFRASTRUCTURE)
        log_success "Created proxy resource: $proxy_resource_id"
    else
        log_info "Using existing proxy resource: $proxy_resource_id"
    fi
    
    # Create ANY method for proxy resource
    log_info "Creating ANY method for proxy resource"
    aws apigateway put-method --rest-api-id "$API_ID" --resource-id "$proxy_resource_id" --http-method ANY --authorization-type NONE &>/dev/null || log_info "ANY method already exists"
    
    # Create Lambda integration for proxy resource
    log_info "Creating Lambda integration for proxy resource"
    local integration_uri="arn:aws:apigateway:$aws_region:lambda:path/2015-03-31/functions/$lambda_arn/invocations"
    
    aws apigateway put-integration --rest-api-id "$API_ID" --resource-id "$proxy_resource_id" --http-method ANY --type AWS_PROXY --integration-http-method POST --uri "$integration_uri" &>/dev/null || log_info "Lambda integration already exists"
    
    # Create ANY method for root resource
    log_info "Creating ANY method for root resource"
    aws apigateway put-method --rest-api-id "$API_ID" --resource-id "$root_resource_id" --http-method ANY --authorization-type NONE &>/dev/null || log_info "Root ANY method already exists"
    
    # Create Lambda integration for root resource
    log_info "Creating Lambda integration for root resource"
    aws apigateway put-integration --rest-api-id "$API_ID" --resource-id "$root_resource_id" --http-method ANY --type AWS_PROXY --integration-http-method POST --uri "$integration_uri" &>/dev/null || log_info "Root Lambda integration already exists"
    
    # Grant API Gateway permission to invoke Lambda
    log_info "Granting API Gateway permission to invoke Lambda"
    local source_arn="arn:aws:execute-api:$aws_region:$account_id:$API_ID/*/*"
    
    aws lambda add-permission --function-name "$LAMBDA_FUNCTION_NAME" --statement-id "apigateway-invoke-$API_ID" --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn "$source_arn" &>/dev/null || log_info "Permission already exists"
    
    log_success "Lambda integration setup completed"
}

# Function to enable CORS
enable_cors() {
    log_info "Enabling CORS for API Gateway"
    
    # Get root resource ID
    local root_resource_id=$(aws apigateway get-resources \
        --rest-api-id "$API_ID" \
        --query 'items[?path==`/`].id' \
        --output text)
    
    # Get proxy resource ID
    local proxy_resource_id=$(aws apigateway get-resources \
        --rest-api-id "$API_ID" \
        --query 'items[?pathPart==`{proxy+}`].id' \
        --output text)
    
    # Enable CORS for proxy resource
    if [ -n "$proxy_resource_id" ]; then
        log_info "Enabling CORS for proxy resource"
        
        # Create OPTIONS method
        execute_with_error_handling \
            "aws apigateway put-method --rest-api-id $API_ID --resource-id $proxy_resource_id --http-method OPTIONS --authorization-type NONE" \
            "Failed to create OPTIONS method" \
            $ERROR_CODE_INFRASTRUCTURE || true
        
        # Create mock integration for OPTIONS
        execute_with_error_handling \
            "aws apigateway put-integration --rest-api-id $API_ID --resource-id $proxy_resource_id --http-method OPTIONS --type MOCK --request-templates '{\"application/json\":\"{\\\"statusCode\\\": 200}\"}'" \
            "Failed to create OPTIONS integration" \
            $ERROR_CODE_INFRASTRUCTURE || true
        
        # Create method response for OPTIONS
        execute_with_error_handling \
            "aws apigateway put-method-response --rest-api-id $API_ID --resource-id $proxy_resource_id --http-method OPTIONS --status-code 200 --response-parameters 'method.response.header.Access-Control-Allow-Headers=false,method.response.header.Access-Control-Allow-Methods=false,method.response.header.Access-Control-Allow-Origin=false'" \
            "Failed to create OPTIONS method response" \
            $ERROR_CODE_INFRASTRUCTURE || true
        
        # Create integration response for OPTIONS
        execute_with_error_handling \
            "aws apigateway put-integration-response --rest-api-id $API_ID --resource-id $proxy_resource_id --http-method OPTIONS --status-code 200 --response-parameters '{\"method.response.header.Access-Control-Allow-Headers\":\"\\\"Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token\\\"\",\"method.response.header.Access-Control-Allow-Methods\":\"\\\"DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT\\\"\",\"method.response.header.Access-Control-Allow-Origin\":\"\\\"*\\\"\"}'" \
            "Failed to create OPTIONS integration response" \
            $ERROR_CODE_INFRASTRUCTURE || true
    fi
    
    log_success "CORS configuration completed"
}

# Function to deploy API Gateway
deploy_api_gateway() {
    log_info "Deploying API Gateway to stage: $STAGE_NAME"
    
    execute_with_error_handling \
        "aws apigateway create-deployment --rest-api-id $API_ID --stage-name $STAGE_NAME --description 'Deployment for $PROJECT_NAME $ENVIRONMENT'" \
        "Failed to deploy API Gateway" \
        $ERROR_CODE_INFRASTRUCTURE
    
    # Get API URL - use flexible region detection
    source "$SCRIPT_DIR/../utilities/validate-aws-cli.sh"
    local aws_region=$(get_aws_region)
    API_URL="https://$API_ID.execute-api.$aws_region.amazonaws.com/$STAGE_NAME"
    
    log_success "API Gateway deployed successfully"
    log_success "API URL: $API_URL"
}

# Function to configure API Gateway settings
configure_api_settings() {
    log_info "Configuring API Gateway settings"
    
    # Enable logging (optional)
    execute_with_error_handling \
        "aws apigateway update-stage --rest-api-id $API_ID --stage-name $STAGE_NAME --patch-ops op=replace,path=/logging/loglevel,value=INFO" \
        "Failed to configure logging" \
        $ERROR_CODE_INFRASTRUCTURE || true
    
    # Enable detailed metrics (optional)
    execute_with_error_handling \
        "aws apigateway update-stage --rest-api-id $API_ID --stage-name $STAGE_NAME --patch-ops op=replace,path=/metricsEnabled,value=true" \
        "Failed to enable metrics" \
        $ERROR_CODE_INFRASTRUCTURE || true
    
    log_success "API Gateway settings configured"
}

# Cleanup functions for rollback
cleanup_api_gateway() {
    if [ -n "$API_ID" ]; then
        log_info "Cleaning up API Gateway: $API_ID"
        aws apigateway delete-rest-api \
            --rest-api-id "$API_ID" &>/dev/null || true
    fi
}

# Function to save API Gateway state
save_api_gateway_state() {
    local state_file="./deployment_checkpoints/api_gateway_infrastructure.state"
    mkdir -p "$(dirname "$state_file")"
    
    cat > "$state_file" << EOF
# API Gateway Infrastructure State
# Generated on $(date)
API_ID="$API_ID"
API_NAME="$API_NAME"
API_URL="$API_URL"
STAGE_NAME="$STAGE_NAME"
LAMBDA_FUNCTION_NAME="$LAMBDA_FUNCTION_NAME"
ENVIRONMENT="$ENVIRONMENT"
PROJECT_NAME="$PROJECT_NAME"
EOF
    
    log_success "API Gateway state saved to: $state_file"
}

# Function to display API Gateway information
display_api_gateway_info() {
    log_success "API Gateway provisioning completed successfully!"
    echo ""
    echo "=== API Gateway Information ==="
    echo "API ID: $API_ID"
    echo "API Name: $API_NAME"
    echo "Stage: $STAGE_NAME"
    echo "API URL: $API_URL"
    echo ""
    echo "=== Swagger/OpenAPI Access ==="
    echo "Swagger UI: $API_URL/swagger"
    echo "OpenAPI JSON: $API_URL/swagger/v1/swagger.json"
    echo "Health Check: $API_URL/health"
    echo ""
    echo "=== Integration Details ==="
    echo "Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "Integration Type: AWS_PROXY"
    echo "CORS: Enabled"
    echo "Logging: Enabled"
    echo ""
    echo "=== Usage Examples ==="
    echo "# Test API"
    echo "curl $API_URL"
    echo ""
    echo "# Access Swagger"
    echo "curl $API_URL/swagger"
    echo ""
    echo "# Test with browser"
    echo "Open: $API_URL/swagger"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Deploy your .NET application to Lambda"
    echo "2. Access Swagger UI at: $API_URL/swagger"
    echo "3. Test API endpoints"
    echo "4. Configure custom domain (optional)"
    echo ""
}

# Main execution function
main() {
    log_info "Starting API Gateway provisioning..."
    log_info "Project: $PROJECT_NAME, Environment: $ENVIRONMENT"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate AWS CLI
    if ! validate_aws_cli "$AWS_PROFILE"; then
        handle_error $ERROR_CODE_AWS_CLI "AWS CLI validation failed" true
    fi
    
    # Log configuration
    log_info "Configuration:"
    log_info "  API Name: $API_NAME"
    log_info "  Stage Name: $STAGE_NAME"
    log_info "  Lambda Function: $LAMBDA_FUNCTION_NAME"
    
    # Create API Gateway components
    create_api_gateway
    setup_lambda_integration
    # Skip CORS setup - Lambda will handle CORS in application code
    deploy_api_gateway
    configure_api_settings
    
    # Save state and display information
    save_api_gateway_state
    display_api_gateway_info
    
    log_success "API Gateway provisioning completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi