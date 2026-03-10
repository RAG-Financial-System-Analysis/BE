#!/bin/bash

# Update Deployment Script
# Updates Lambda function code without running migrations or seeding
# Use this when you only want to deploy new code changes

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILITIES_DIR="$SCRIPT_DIR/utilities"
source "$UTILITIES_DIR/logging.sh"
source "$UTILITIES_DIR/error-handling.sh"
source "$UTILITIES_DIR/load-config.sh"
source "$UTILITIES_DIR/validate-aws-cli.sh"

# Load deployment configuration
load_deployment_config

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Updates Lambda function code without running migrations or seeding.
Use this for deploying code changes to existing infrastructure.

OPTIONS:
    --config FILE             Configuration file path (default: ./deployment-config.env)
    --environment ENV         Environment name (overrides config)
    --project-name NAME       Project name (overrides config)
    --show-config            Display current configuration and exit
    --help                   Show this help message

WHAT THIS SCRIPT DOES:
    1. ⚡ Update Lambda Function Code
    2. 🧪 Run Tests (optional)

WHAT THIS SCRIPT DOES NOT DO:
    ❌ Create new infrastructure (RDS, API Gateway)
    ❌ Run database migrations
    ❌ Seed database (roles, users, analytics types)

EXAMPLES:
    # Update code with default config
    $0

    # Use custom config file
    $0 --config ./production-config.env

    # Override environment
    $0 --environment production

EOF
}

# Parse arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_FILE="$2"
                # Reload configuration with new file
                load_deployment_config "$CONFIG_FILE"
                shift 2
                ;;
            --environment)
                ENVIRONMENT="$2"
                export ENVIRONMENT
                shift 2
                ;;
            --project-name)
                PROJECT_NAME="$2"
                export PROJECT_NAME
                shift 2
                ;;
            --show-config)
                show_deployment_config
                exit 0
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
}

# Function to check prerequisites
check_prerequisites() {
    log_info "🔍 Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI."
        exit 1
    fi
    
    # Check .NET SDK
    if ! command -v dotnet &> /dev/null; then
        log_error ".NET SDK not found. Please install .NET SDK."
        exit 1
    fi
    
    # Check AWS credentials using the flexible detection utility
    log_info "Checking AWS credentials..."
    
    if ! check_aws_credentials; then
        log_error "AWS credentials validation failed"
        exit 1
    fi
    
    # Check if Lambda function exists
    local lambda_function_name="$PROJECT_NAME-$ENVIRONMENT-api"
    if ! aws lambda get-function --function-name "$lambda_function_name" &>/dev/null; then
        log_error "Lambda function not found: $lambda_function_name"
        log_error "Please run full deployment first: ./deploy-full-stack.sh"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to update Lambda function
update_lambda() {
    log_info "⚡ Step 1: Updating Lambda Function Code..."
    
    if ! "$SCRIPT_DIR/deployment/deploy-lambda.sh" \
        --environment "$ENVIRONMENT" \
        --project-name "$PROJECT_NAME"; then
        log_error "Lambda code update failed"
        exit 1
    fi
    
    log_success "Lambda Function code updated successfully"
}

# Function to run tests
run_tests() {
    log_info "🧪 Step 2: Running Tests..."
    
    # Test Lambda-RDS connection
    if ! "$SCRIPT_DIR/tests/test-lambda-db-connection.sh" \
        --function-name "$PROJECT_NAME-$ENVIRONMENT-api"; then
        log_warn "Lambda-RDS connection test failed"
    fi
    
    # Test API endpoints
    if ! "$SCRIPT_DIR/tests/test-api.sh"; then
        log_warn "API tests failed"
    fi
    
    # Test user roles
    if ! "$SCRIPT_DIR/tests/test-user-roles.sh"; then
        log_warn "User role tests failed"
    fi
    
    log_success "Tests completed"
}

# Function to display deployment summary
display_summary() {
    log_success "🎉 Lambda Code Update Completed!"
    echo ""
    echo "=== Update Summary ==="
    echo "Environment: $ENVIRONMENT"
    echo "Project: $PROJECT_NAME"
    echo "Lambda Function: $PROJECT_NAME-$ENVIRONMENT-api"
    echo ""
    echo "=== What Was Updated ==="
    echo "✅ Lambda .NET 10 Function Code"
    echo "✅ Tests Executed"
    echo ""
    echo "=== What Was NOT Changed ==="
    echo "⏭️  Database schema (no migrations run)"
    echo "⏭️  Database data (no seeding)"
    echo "⏭️  Infrastructure (RDS, API Gateway unchanged)"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Test API endpoints using Swagger or Postman"
    echo "2. Monitor CloudWatch logs for any issues"
    echo "3. Verify application functionality"
    echo ""
    
    # Get API Gateway URL if available
    local api_url_file="./deployment_checkpoints/api_gateway_infrastructure.state"
    if [[ -f "$api_url_file" ]]; then
        local api_url=$(grep "^API_URL=" "$api_url_file" | cut -d'=' -f2 | tr -d '"')
        if [[ -n "$api_url" ]]; then
            echo "🌐 API Gateway URL: $api_url"
            echo "📖 Swagger Documentation: $api_url/swagger"
        fi
    fi
}

# Main execution function
main() {
    log_info "🚀 Starting Lambda Code Update..."
    log_info "Environment: $ENVIRONMENT, Project: $PROJECT_NAME"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Execute update steps
    update_lambda
    run_tests
    
    # Display summary
    display_summary
    
    log_success "🎉 Lambda code update completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi