#!/bin/bash

# Full Stack Deployment Script
# Deploys complete RAG System to AWS in correct order
# 
# Order:
# 1. Deploy RDS Database
# 2. Deploy Lambda Function  
# 3. Run Database Migrations
# 4. Trigger DbInitializer (seeds roles, analytics types, users automatically)
# 5. Deploy API Gateway
# 6. Run Tests

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

Deploys complete RAG System to AWS in correct order.

OPTIONS:
    --config FILE             Configuration file path (default: ./deployment-config.env)
    --environment ENV         Environment name (overrides config)
    --project-name NAME       Project name (overrides config)
    --skip-tests             Skip running tests after deployment
    --skip-seeding           Skip database seeding (roles, users)
    --show-config            Display current configuration and exit
    --validate-config        Validate configuration file and exit
    --help                   Show this help message

DEPLOYMENT ORDER (CORRECT SEQUENCE):
    1. 🗄️  Deploy RDS Database
    2. ⚡ Deploy Lambda Function  
    3. 🔄 Run Database Migrations (from Lambda to DB)
    4. 🌱 Trigger DbInitializer (seeds roles, analytics types, users automatically)
    5. 🌐 Deploy API Gateway
    6. 🧪 Run Tests

CONFIGURATION:
    All deployment parameters are loaded from deployment-config.env file.
    You can override specific values using command line options.
    Use --show-config to see current configuration values.

EXAMPLES:
    # Full deployment with default config
    $0

    # Use custom config file
    $0 --config ./production-config.env

    # Override specific settings
    $0 --environment production --project-name myrag

    # Show current configuration
    $0 --show-config

    # Validate configuration file
    $0 --validate-config

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
            --skip-tests)
                SKIP_TESTS=true
                export SKIP_TESTS
                shift
                ;;
            --skip-seeding)
                SKIP_SEEDING=true
                export SKIP_SEEDING
                shift
                ;;
            --show-config)
                show_deployment_config
                exit 0
                ;;
            --validate-config)
                validate_config_file
                exit $?
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
    log_info "🔍 Checking deployment prerequisites..."
    
    # Create temporary files directory
    mkdir -p "./scripts/temp"
    
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
    
    # Check PostgreSQL client
    if ! command -v psql &> /dev/null; then
        log_warn "PostgreSQL client not found. Database seeding will be skipped."
        SKIP_SEEDING=true
    fi
    
    # Check AWS credentials using the flexible detection utility
    log_info "Checking AWS credentials..."
    log_info "Note: AWS credentials are automatically detected from:"
    log_info "  • ~/.aws/credentials (saved by 'aws configure')"
    log_info "  • ~/.aws/config (saved by 'aws configure')"
    log_info "  • Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)"
    log_info "  • IAM roles (if running on EC2)"
    log_info "You only need to run 'aws configure' ONCE - credentials are saved permanently."
    
    if ! check_aws_credentials; then
        log_error "AWS credentials validation failed"
        log_error "Run 'aws configure' to set up your credentials if this is your first time."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to deploy RDS database
deploy_database() {
    log_info "🗄️  Step 1: Deploying RDS Database..."
    
    if ! "$SCRIPT_DIR/infrastructure/provision-rds.sh" \
        --environment "$ENVIRONMENT" \
        --project-name "$PROJECT_NAME"; then
        log_error "RDS deployment failed"
        exit 1
    fi
    
    log_success "RDS Database deployed successfully"
}

# Function to deploy Lambda function
deploy_lambda() {
    log_info "⚡ Step 2: Deploying Lambda Function..."
    
    if ! "$SCRIPT_DIR/infrastructure/provision-lambda.sh" \
        --environment "$ENVIRONMENT" \
        --project-name "$PROJECT_NAME"; then
        log_error "Lambda infrastructure provisioning failed"
        exit 1
    fi
    
    if ! "$SCRIPT_DIR/deployment/deploy-lambda.sh" \
        --environment "$ENVIRONMENT" \
        --project-name "$PROJECT_NAME"; then
        log_error "Lambda deployment failed"
        exit 1
    fi
    
    log_success "Lambda Function deployed successfully"
}

# Function to run database migrations
run_migrations() {
    log_info "🔄 Step 3: Running Database Migrations..."
    
    if ! "$SCRIPT_DIR/migration/run-migrations.sh" \
        --environment "$ENVIRONMENT"; then
        log_error "Database migrations failed"
        exit 1
    fi
    
    log_success "Database migrations completed successfully"
}

# Function to seed database via DbInitializer
seed_database() {
    if [ "$SKIP_SEEDING" = true ]; then
        log_info "🌱 Step 4: Skipping database seeding (--skip-seeding flag)"
        return 0
    fi
    
    log_info "🌱 Step 4: Triggering DbInitializer to seed database..."
    log_info "   DbInitializer will automatically:"
    log_info "   - Create Admin and Analyst roles"
    log_info "   - Create 5 analytics types (RISK, TREND, COMPARISON, OPPORTUNITY, EXECUTIVE)"
    log_info "   - Create default users in both Cognito and Database:"
    log_info "     • admin@rag.com (Admin role)"
    log_info "     • analyst@rag.com (Analyst role)"
    log_info "   - Sync users between Cognito and Database"
    
    # Trigger Lambda again to ensure DbInitializer runs with proper AWS config
    if ! "$SCRIPT_DIR/database/trigger-db-initializer.sh" \
        --function-name "$PROJECT_NAME-$ENVIRONMENT-api"; then
        log_error "DbInitializer trigger failed"
        exit 1
    fi
    
    log_success "Database seeding completed via DbInitializer"
}

# Function to deploy API Gateway
deploy_api_gateway() {
    log_info "🌐 Step 5: Deploying API Gateway..."
    
    if ! "$SCRIPT_DIR/infrastructure/provision-api-gateway.sh" \
        --environment "$ENVIRONMENT" \
        --project-name "$PROJECT_NAME"; then
        log_error "API Gateway deployment failed"
        exit 1
    fi
    
    log_success "API Gateway deployed successfully"
}

# Function to run tests
run_tests() {
    if [ "$SKIP_TESTS" = true ]; then
        log_info "🧪 Step 6: Skipping tests (--skip-tests flag)"
        return 0
    fi
    
    log_info "🧪 Step 6: Running Tests..."
    
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
    log_success "🎉 Full Stack Deployment Completed!"
    echo ""
    echo "=== Deployment Summary ==="
    echo "Environment: $ENVIRONMENT"
    echo "Project: $PROJECT_NAME"
    echo "Lambda Function: $PROJECT_NAME-$ENVIRONMENT-api"
    echo ""
    echo "=== Deployed Components ==="
    echo "✅ RDS PostgreSQL Database"
    echo "✅ Lambda .NET 10 Function"
    echo "✅ Database Migrations Applied"
    if [ "$SKIP_SEEDING" = false ]; then
        echo "✅ Database Seeded via DbInitializer (Roles, Users, Analytics Types)"
    else
        echo "⏭️  Database Seeding Skipped"
    fi
    echo "✅ API Gateway"
    if [ "$SKIP_TESTS" = false ]; then
        echo "✅ Tests Executed"
    else
        echo "⏭️  Tests Skipped"
    fi
    echo ""
    echo "=== Default Users ==="
    if [ "$SKIP_SEEDING" = false ]; then
        echo "Admin: admin@rag.com / Admin@123!!"
        echo "Analyst: analyst@rag.com / Analyst@123!!"
    else
        echo "No default users created (seeding skipped)"
    fi
    echo ""
    echo "=== Next Steps ==="
    echo "1. Test API endpoints using Swagger or Postman"
    echo "2. Configure frontend to use the API Gateway URL"
    echo "3. Monitor CloudWatch logs for any issues"
    echo "4. Set up CI/CD pipeline for future deployments"
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
    log_info "🚀 Starting Full Stack Deployment..."
    log_info "Environment: $ENVIRONMENT, Project: $PROJECT_NAME"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Execute deployment steps
    deploy_database
    deploy_lambda
    run_migrations
    seed_database
    deploy_api_gateway
    run_tests
    
    # Display summary
    display_summary
    
    log_success "🎉 Full Stack Deployment completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi