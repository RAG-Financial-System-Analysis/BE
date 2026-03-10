#!/bin/bash

# Lambda Deployment Script for .NET 10 Applications
# Handles deployment package creation with dependencies
# Supports both initial deployment and code-only updates
# Configures proper runtime settings and resource allocation

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILITIES_DIR="$SCRIPT_DIR/../utilities"
source "$UTILITIES_DIR/logging.sh"
source "$UTILITIES_DIR/error-handling.sh"
source "$UTILITIES_DIR/validate-aws-cli.sh"

# Default configuration values
DEFAULT_RUNTIME="dotnet10"  # .NET 10 runtime
DEFAULT_MEMORY_SIZE="512"  # Cost-optimized memory allocation
DEFAULT_TIMEOUT="30"       # Reasonable timeout for database operations
DEFAULT_HANDLER="RAG.APIs::RAG.APIs.LambdaEntryPoint::FunctionHandlerAsync"

# Configuration variables
RUNTIME="${RUNTIME:-$DEFAULT_RUNTIME}"
MEMORY_SIZE="${MEMORY_SIZE:-$DEFAULT_MEMORY_SIZE}"
TIMEOUT="${TIMEOUT:-$DEFAULT_TIMEOUT}"
HANDLER="${HANDLER:-$DEFAULT_HANDLER}"
AWS_PROFILE="${AWS_PROFILE:-}"

# Resource naming
ENVIRONMENT="${ENVIRONMENT:-dev}"
PROJECT_NAME="${PROJECT_NAME:-myragapp}"
LAMBDA_FUNCTION_NAME="$PROJECT_NAME-$ENVIRONMENT-api"

# Paths
BACKEND_PATH="${BACKEND_PATH:-$(pwd)}"
PROJECT_PATH="${PROJECT_PATH:-$BACKEND_PATH/RAG.APIs}"
BUILD_OUTPUT_PATH="/tmp/lambda-build"
DEPLOYMENT_PACKAGE_PATH="./lambda-deployment.zip"

# Global variables
LAMBDA_FUNCTION_ARN=""
UPDATE_MODE=false

# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploys .NET 10 application to AWS Lambda with proper packaging and dependencies.

OPTIONS:
    --function-name NAME       Lambda function name (default: $PROJECT_NAME-$ENVIRONMENT-api)
    --runtime RUNTIME          Lambda runtime (default: $DEFAULT_RUNTIME)
    --memory SIZE              Memory allocation in MB (default: $DEFAULT_MEMORY_SIZE)
    --timeout SECONDS          Function timeout in seconds (default: $DEFAULT_TIMEOUT)
    --handler HANDLER          Function handler (default: $DEFAULT_HANDLER)
    --environment ENV          Environment name (default: dev)
    --project-name NAME        Project name (default: myapp)
    --backend-path PATH        Path to backend code (default: $BACKEND_PATH)
    --project-path PATH        Path to main project (default: $PROJECT_PATH)
    --update-mode              Update existing function code only (skip configuration)
    --aws-profile PROFILE      AWS profile to use
    --help                     Show this help message

EXAMPLES:
    # Initial deployment
    $0 --environment production --project-name webapp

    # Code-only update
    $0 --update-mode --function-name webapp-prod-api

    # Custom configuration
    $0 --memory 1024 --timeout 60 --aws-profile prod

DEPLOYMENT MODES:
    - Initial: Creates or updates Lambda function with full configuration
    - Update: Updates only the function code (faster for development)

PREREQUISITES:
    - .NET 8 SDK installed (for building .NET 10 applications)
    - Lambda infrastructure provisioned (run provision-lambda.sh first)
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
            --backend-path)
                BACKEND_PATH="$2"
                PROJECT_PATH="$BACKEND_PATH/RAG.APIs"
                shift 2
                ;;
            --project-path)
                PROJECT_PATH="$2"
                shift 2
                ;;
            --update-mode)
                UPDATE_MODE=true
                shift
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
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating deployment prerequisites..."
    
    # Check if .NET SDK is installed
    if ! command -v dotnet &> /dev/null; then
        set_error_context "Prerequisites validation"
        set_error_remediation "Install .NET 8 SDK from https://dotnet.microsoft.com/download"
        handle_error $ERROR_CODE_VALIDATION ".NET SDK not found" true
    fi
    
    # Check .NET version
    local dotnet_version=$(dotnet --version 2>/dev/null || echo "unknown")
    log_info "Found .NET SDK version: $dotnet_version"
    
    # Validate backend path exists
    validate_directory_exists "$BACKEND_PATH" "backend code directory"
    validate_directory_exists "$PROJECT_PATH" "main project directory"
    
    # Check for project file
    local project_file="$PROJECT_PATH/RAG.APIs.csproj"
    validate_file_exists "$project_file" "project file"
    
    # Check for appsettings.json
    local appsettings_file="$PROJECT_PATH/appsettings.json"
    validate_file_exists "$appsettings_file" "appsettings.json configuration file"
    
    log_success "Prerequisites validation completed"
}

# Function to check if Lambda function exists
check_lambda_function_exists() {
    log_info "Checking if Lambda function exists: $LAMBDA_FUNCTION_NAME"
    
    local function_arn=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Configuration.FunctionArn' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$function_arn" != "None" ] && [ "$function_arn" != "null" ]; then
        log_info "Found existing Lambda function: $function_arn"
        LAMBDA_FUNCTION_ARN="$function_arn"
        return 0
    else
        log_warn "Lambda function not found: $LAMBDA_FUNCTION_NAME"
        return 1
    fi
}

# Function to clean build output directory
clean_build_output() {
    log_info "Cleaning build output directory: $BUILD_OUTPUT_PATH"
    rm -rf "$BUILD_OUTPUT_PATH"
    mkdir -p "$BUILD_OUTPUT_PATH"
}

# Function to restore NuGet packages
restore_packages() {
    log_info "Restoring NuGet packages..."
    set_error_context "NuGet package restoration"
    set_error_remediation "Check internet connectivity and NuGet configuration"
    
    cd "$PROJECT_PATH"
    execute_with_error_handling \
        "dotnet restore" \
        "Failed to restore NuGet packages" \
        $ERROR_CODE_CONFIGURATION
    
    log_success "NuGet packages restored successfully"
}

# Function to build the .NET application
build_application() {
    log_info "Building .NET application for Lambda deployment..."
    set_error_context ".NET application build"
    set_error_remediation "Check project configuration and resolve build errors"
    
    cd "$PROJECT_PATH"
    
    # Build for Lambda runtime (linux-x64)
    execute_with_error_handling \
        "dotnet publish -c Release -r linux-x64 --self-contained false -o $BUILD_OUTPUT_PATH" \
        "Failed to build .NET application" \
        $ERROR_CODE_CONFIGURATION
    
    log_success ".NET application built successfully"
}

# Function to add Lambda entry point if missing
ensure_lambda_entry_point() {
    local program_file="$PROJECT_PATH/Program.cs"
    
    if [ -f "$program_file" ]; then
        # Check if LambdaEntryPoint already exists
        if grep -q "LambdaEntryPoint" "$program_file"; then
            log_info "Lambda entry point already exists in Program.cs"
            return 0
        fi
        
        log_info "Adding Lambda entry point to Program.cs"
        
        # Create backup
        cp "$program_file" "$program_file.backup"
        
        # Add Lambda entry point class
        cat >> "$program_file" << 'EOF'

// Lambda Entry Point for AWS Lambda deployment
public class LambdaEntryPoint : Amazon.Lambda.AspNetCoreServer.APIGatewayProxyFunction
{
    protected override void Init(IWebHostBuilder builder)
    {
        builder.UseStartup<Program>();
    }
}
EOF
        
        log_success "Lambda entry point added to Program.cs"
    else
        log_warn "Program.cs not found, assuming Lambda entry point exists elsewhere"
    fi
}

# Function to add required Lambda NuGet packages
add_lambda_packages() {
    log_info "Checking for required Lambda NuGet packages..."
    
    cd "$PROJECT_PATH"
    
    # Check if Amazon.Lambda.AspNetCoreServer is already referenced
    if ! grep -q "Amazon.Lambda.AspNetCoreServer" "RAG.APIs.csproj"; then
        log_info "Adding Amazon.Lambda.AspNetCoreServer package"
        execute_with_error_handling \
            "dotnet add package Amazon.Lambda.AspNetCoreServer" \
            "Failed to add Lambda AspNetCore server package" \
            $ERROR_CODE_CONFIGURATION
    fi
    
    # Check if Amazon.Lambda.Core is already referenced
    if ! grep -q "Amazon.Lambda.Core" "RAG.APIs.csproj"; then
        log_info "Adding Amazon.Lambda.Core package"
        execute_with_error_handling \
            "dotnet add package Amazon.Lambda.Core" \
            "Failed to add Lambda Core package" \
            $ERROR_CODE_CONFIGURATION
    fi
    
    log_success "Lambda packages verified"
}

# Function to create deployment package
create_deployment_package() {
    log_info "Creating Lambda deployment package..."
    set_error_context "Deployment package creation"
    set_error_remediation "Check build output and file permissions"
    
    # Remove existing deployment package
    rm -f "$DEPLOYMENT_PACKAGE_PATH"
    
    # Create zip package from build output using PowerShell (Windows compatible)
    cd "$BUILD_OUTPUT_PATH"
    
    # Use PowerShell Compress-Archive for Windows compatibility
    if command -v powershell >/dev/null 2>&1; then
        execute_with_error_handling \
            "powershell -Command \"Compress-Archive -Path '*' -DestinationPath '$DEPLOYMENT_PACKAGE_PATH' -Force\"" \
            "Failed to create deployment package with PowerShell" \
            $ERROR_CODE_CONFIGURATION
    elif command -v zip >/dev/null 2>&1; then
        execute_with_error_handling \
            "zip -r $DEPLOYMENT_PACKAGE_PATH . -x '*.pdb' '*.xml'" \
            "Failed to create deployment package with zip" \
            $ERROR_CODE_CONFIGURATION
    else
        handle_error $ERROR_CODE_CONFIGURATION "Neither PowerShell nor zip command available for creating deployment package" true
    fi
    
    # Check package size
    local package_size=$(stat -f%z "$DEPLOYMENT_PACKAGE_PATH" 2>/dev/null || stat -c%s "$DEPLOYMENT_PACKAGE_PATH" 2>/dev/null || echo "0")
    local package_size_mb=$((package_size / 1024 / 1024))
    
    log_info "Deployment package created: $DEPLOYMENT_PACKAGE_PATH"
    log_info "Package size: ${package_size_mb}MB"
    
    # Warn if package is large
    if [ "$package_size_mb" -gt 50 ]; then
        log_warn "Large deployment package (${package_size_mb}MB). Consider optimizing dependencies."
    fi
    
    # Lambda has a 50MB limit for direct upload, 250MB for S3
    if [ "$package_size_mb" -gt 50 ]; then
        log_warn "Package exceeds 50MB limit for direct upload. Will use S3 upload method."
        return 1
    fi
    
    log_success "Deployment package ready for upload"
    return 0
}

# Function to upload large package to S3
upload_package_to_s3() {
    log_info "Uploading large deployment package to S3..."
    
    local bucket_name="$PROJECT_NAME-$ENVIRONMENT-lambda-deployments"
    local s3_key="deployments/$(basename "$DEPLOYMENT_PACKAGE_PATH")"
    
    # Create S3 bucket if it doesn't exist
    if ! aws s3 ls "s3://$bucket_name" &>/dev/null; then
        log_info "Creating S3 bucket for deployments: $bucket_name"
        execute_with_error_handling \
            "aws s3 mb s3://$bucket_name" \
            "Failed to create S3 bucket for deployments" \
            $ERROR_CODE_INFRASTRUCTURE
    fi
    
    # Upload package to S3
    execute_with_error_handling \
        "aws s3 cp $DEPLOYMENT_PACKAGE_PATH s3://$bucket_name/$s3_key" \
        "Failed to upload deployment package to S3" \
        $ERROR_CODE_INFRASTRUCTURE
    
    log_success "Deployment package uploaded to S3: s3://$bucket_name/$s3_key"
    echo "$bucket_name,$s3_key"
}

# Function to deploy Lambda function code
deploy_lambda_code() {
    log_info "Deploying code to Lambda function: $LAMBDA_FUNCTION_NAME"
    set_error_context "Lambda code deployment"
    set_error_remediation "Check Lambda function exists and AWS permissions"
    
    # Try direct upload first
    if create_deployment_package; then
        # Direct upload (package < 50MB)
        execute_with_error_handling \
            "aws lambda update-function-code \
                --function-name $LAMBDA_FUNCTION_NAME \
                --zip-file fileb://$DEPLOYMENT_PACKAGE_PATH" \
            "Failed to update Lambda function code" \
            $ERROR_CODE_LAMBDA
    else
        # S3 upload (package >= 50MB)
        local s3_info=$(upload_package_to_s3)
        local bucket_name=$(echo "$s3_info" | cut -d',' -f1)
        local s3_key=$(echo "$s3_info" | cut -d',' -f2)
        
        execute_with_error_handling \
            "aws lambda update-function-code \
                --function-name $LAMBDA_FUNCTION_NAME \
                --s3-bucket $bucket_name \
                --s3-key $s3_key" \
            "Failed to update Lambda function code from S3" \
            $ERROR_CODE_LAMBDA
    fi
    
    log_success "Lambda function code updated successfully"
}

# Function to update Lambda configuration
update_lambda_configuration() {
    if [ "$UPDATE_MODE" = true ]; then
        log_info "Skipping configuration update (update mode)"
        return 0
    fi
    
    log_info "Updating Lambda function configuration..."
    set_error_context "Lambda configuration update"
    set_error_remediation "Check Lambda function exists and configuration values"
    
    # Update runtime, memory, timeout, and handler
    execute_with_error_handling \
        "aws lambda update-function-configuration \
            --function-name $LAMBDA_FUNCTION_NAME \
            --runtime $RUNTIME \
            --memory-size $MEMORY_SIZE \
            --timeout $TIMEOUT \
            --handler $HANDLER" \
        "Failed to update Lambda function configuration" \
        $ERROR_CODE_LAMBDA
    
    log_success "Lambda function configuration updated"
}

# Function to wait for Lambda function to be ready
wait_for_function_ready() {
    log_info "Waiting for Lambda function to be ready..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local state=$(aws lambda get-function \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --query 'Configuration.State' \
            --output text 2>/dev/null || echo "Unknown")
        
        case "$state" in
            "Active")
                log_success "Lambda function is ready"
                return 0
                ;;
            "Pending"|"InProgress")
                log_info "Lambda function state: $state (attempt $attempt/$max_attempts)"
                sleep 5
                ;;
            "Failed"|"Unknown")
                log_error "Lambda function deployment failed or unknown state: $state"
                return 1
                ;;
            *)
                log_warn "Unexpected Lambda function state: $state"
                sleep 5
                ;;
        esac
        
        ((attempt++))
    done
    
    log_error "Timeout waiting for Lambda function to be ready"
    return 1
}

# Function to test Lambda function
test_lambda_function() {
    log_info "Testing Lambda function deployment..."
    
    # Create a simple test event
    local test_event='{"httpMethod":"GET","path":"/health","headers":{},"body":null}'
    
    # Invoke Lambda function
    local response=$(aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload "$test_event" \
        --cli-binary-format raw-in-base64-out \
        /tmp/lambda-response.json 2>&1 || echo "FAILED")
    
    if echo "$response" | grep -q "FAILED"; then
        log_warn "Lambda function test invocation failed: $response"
        log_warn "This may be normal if the function requires specific routing or authentication"
    else
        log_success "Lambda function test invocation completed"
        if [ -f "/tmp/lambda-response.json" ]; then
            local status_code=$(cat /tmp/lambda-response.json | grep -o '"statusCode":[0-9]*' | cut -d':' -f2 || echo "unknown")
            log_info "Response status code: $status_code"
        fi
    fi
    
    # Clean up test response
    rm -f /tmp/lambda-response.json
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    rm -rf "$BUILD_OUTPUT_PATH"
    rm -f "$DEPLOYMENT_PACKAGE_PATH"
    
    # Restore Program.cs backup if it exists
    if [ -f "$PROJECT_PATH/Program.cs.backup" ]; then
        log_info "Restoring Program.cs backup"
        mv "$PROJECT_PATH/Program.cs.backup" "$PROJECT_PATH/Program.cs"
    fi
}

# Function to display deployment information
display_deployment_info() {
    log_success "Lambda deployment completed successfully!"
    echo ""
    echo "=== Deployment Information ==="
    echo "Function Name: $LAMBDA_FUNCTION_NAME"
    echo "Function ARN: $LAMBDA_FUNCTION_ARN"
    echo "Runtime: $RUNTIME"
    echo "Memory: ${MEMORY_SIZE}MB"
    echo "Timeout: ${TIMEOUT}s"
    echo "Handler: $HANDLER"
    echo "Mode: $([ "$UPDATE_MODE" = true ] && echo "Update (code only)" || echo "Full deployment")"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Configure API Gateway to route requests to this Lambda function"
    echo "2. Update environment variables using configure-environment.sh"
    echo "3. Test the API endpoints"
    echo "4. Monitor CloudWatch logs for any issues"
    echo ""
    echo "=== Useful Commands ==="
    echo "# View function logs:"
    echo "aws logs tail /aws/lambda/$LAMBDA_FUNCTION_NAME --follow"
    echo ""
    echo "# Test function:"
    echo "aws lambda invoke --function-name $LAMBDA_FUNCTION_NAME --payload '{}' response.json"
    echo ""
}

# Main execution function
main() {
    log_info "Starting Lambda deployment..."
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
    log_info "  Backend Path: $BACKEND_PATH"
    log_info "  Project Path: $PROJECT_PATH"
    log_info "  Update Mode: $UPDATE_MODE"
    
    # Register cleanup function
    register_cleanup_function "cleanup_temp_files"
    
    # Validate prerequisites
    validate_prerequisites
    
    # Check if Lambda function exists
    if ! check_lambda_function_exists; then
        if [ "$UPDATE_MODE" = true ]; then
            handle_error $ERROR_CODE_LAMBDA "Cannot use update mode: Lambda function does not exist" true
        else
            log_warn "Lambda function does not exist. Run provision-lambda.sh first to create infrastructure."
            handle_error $ERROR_CODE_LAMBDA "Lambda function not found" true
        fi
    fi
    
    # Prepare build environment
    clean_build_output
    
    # Add Lambda packages and entry point
    add_lambda_packages
    ensure_lambda_entry_point
    
    # Build and deploy
    restore_packages
    build_application
    deploy_lambda_code
    update_lambda_configuration
    
    # Wait for deployment to complete and test
    wait_for_function_ready
    test_lambda_function
    
    # Display results
    display_deployment_info
    
    log_success "Lambda deployment completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi