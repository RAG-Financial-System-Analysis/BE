#!/bin/bash

# Full Deployment Orchestrator
# Integrates all scripts through master deployment orchestration
# Implements proper script execution order and dependency management
# Adds comprehensive logging throughout the entire deployment process
# Tests complete end-to-end deployment workflows

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILITIES_DIR="$SCRIPT_DIR/../utilities"
source "$UTILITIES_DIR/logging.sh"
source "$UTILITIES_DIR/error-handling.sh"
source "$UTILITIES_DIR/validate-aws-cli.sh"
source "$UTILITIES_DIR/cost-optimization.sh"

# Global configuration
DEPLOYMENT_ID="deployment_$(date +%Y%m%d_%H%M%S)"
DEPLOYMENT_LOG_DIR="./deployment_logs/$DEPLOYMENT_ID"
CHECKPOINT_DIR="./deployment_checkpoints"

# Default values
ENVIRONMENT="dev"
PROJECT_NAME="myapp"
AWS_REGION="ap-southeast-1"
MODE="initial"
DRY_RUN=false
SKIP_VALIDATION=false
FORCE_CLEANUP=false

# Deployment phases
declare -a DEPLOYMENT_PHASES=(
    "validation"
    "infrastructure"
    "database"
    "application"
    "verification"
)

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Full deployment orchestrator for AWS infrastructure and applications.

OPTIONS:
    --mode MODE                 Deployment mode (initial, update, cleanup)
    --environment ENV           Environment (dev, staging, production)
    --project-name NAME         Project name
    --region REGION             AWS region (default: ap-southeast-1)
    --dry-run                   Perform dry run without making changes
    --skip-validation           Skip pre-deployment validation
    --force-cleanup             Force cleanup without confirmation
    --resume-from PHASE         Resume deployment from specific phase
    --help                      Show this help message

MODES:
    initial     Complete infrastructure setup from scratch
    update      Update existing infrastructure and application
    cleanup     Remove all AWS resources

PHASES:
    validation      Pre-deployment validation and checks
    infrastructure  AWS infrastructure provisioning
    database        Database setup and migrations
    application     Application deployment and configuration
    verification    Post-deployment verification

EXAMPLES:
    # Initial deployment for production
    $0 --mode initial --environment production --project-name myapp

    # Update existing deployment
    $0 --mode update --environment production --project-name myapp

    # Dry run for testing
    $0 --mode initial --environment dev --dry-run

    # Resume from database phase
    $0 --mode initial --environment production --resume-from database

    # Complete cleanup
    $0 --mode cleanup --environment dev --force-cleanup

EOF
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mode)
                MODE="$2"
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
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --force-cleanup)
                FORCE_CLEANUP=true
                shift
                ;;
            --resume-from)
                RESUME_FROM="$2"
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
    
    # Validate required parameters
    if [[ ! "$MODE" =~ ^(initial|update|cleanup)$ ]]; then
        log_error "Invalid mode: $MODE. Must be initial, update, or cleanup"
        exit 1
    fi
    
    if [[ ! "$ENVIRONMENT" =~ ^(dev|development|staging|production)$ ]]; then
        log_error "Invalid environment: $ENVIRONMENT"
        exit 1
    fi
}

# Function to setup deployment environment
setup_deployment_environment() {
    log_info "Setting up deployment environment"
    
    # Create deployment directories
    mkdir -p "$DEPLOYMENT_LOG_DIR"
    mkdir -p "$CHECKPOINT_DIR"
    
    # Set environment variables
    export ENVIRONMENT
    export PROJECT_NAME
    export AWS_DEFAULT_REGION="$AWS_REGION"
    export DEPLOYMENT_ID
    export LOG_LEVEL="${LOG_LEVEL:-INFO}"
    
    # Setup logging
    exec 1> >(tee -a "$DEPLOYMENT_LOG_DIR/deployment.log")
    exec 2> >(tee -a "$DEPLOYMENT_LOG_DIR/errors.log" >&2)
    
    log_info "Deployment ID: $DEPLOYMENT_ID"
    log_info "Environment: $ENVIRONMENT"
    log_info "Project: $PROJECT_NAME"
    log_info "Region: $AWS_REGION"
    log_info "Mode: $MODE"
    log_info "Dry Run: $DRY_RUN"
    
    # Save deployment configuration
    cat > "$DEPLOYMENT_LOG_DIR/config.json" << EOF
{
  "deploymentId": "$DEPLOYMENT_ID",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "environment": "$ENVIRONMENT",
  "projectName": "$PROJECT_NAME",
  "region": "$AWS_REGION",
  "mode": "$MODE",
  "dryRun": $DRY_RUN,
  "skipValidation": $SKIP_VALIDATION
}
EOF
}

# Function to create deployment checkpoint
create_checkpoint() {
    local phase="$1"
    local status="$2"
    local message="${3:-}"
    
    local checkpoint_file="$CHECKPOINT_DIR/${DEPLOYMENT_ID}_${phase}.checkpoint"
    
    cat > "$checkpoint_file" << EOF
{
  "deploymentId": "$DEPLOYMENT_ID",
  "phase": "$phase",
  "status": "$status",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "message": "$message",
  "environment": "$ENVIRONMENT",
  "projectName": "$PROJECT_NAME",
  "region": "$AWS_REGION"
}
EOF
    
    log_debug "Checkpoint created: $checkpoint_file"
}

# Function to validate deployment prerequisites
validate_deployment() {
    if [ "$SKIP_VALIDATION" = true ]; then
        log_warn "Skipping validation as requested"
        return 0
    fi
    
    log_info "=== Phase 1: Validation ==="
    create_checkpoint "validation" "in_progress" "Starting validation phase"
    
    local validation_failed=false
    
    # Validate AWS CLI
    log_info "Validating AWS CLI configuration..."
    if ! validate_aws_cli; then
        log_error "AWS CLI validation failed"
        validation_failed=true
    fi
    
    # Validate project structure
    log_info "Validating project structure..."
    if ! validate_project_structure; then
        log_error "Project structure validation failed"
        validation_failed=true
    fi
    
    # Validate configuration files
    log_info "Validating configuration files..."
    if ! validate_configuration_files; then
        log_error "Configuration validation failed"
        validation_failed=true
    fi
    
    # Cost estimation
    log_info "Generating cost estimation..."
    if ! generate_cost_estimation; then
        log_warn "Cost estimation failed, continuing anyway"
    fi
    
    if [ "$validation_failed" = true ]; then
        create_checkpoint "validation" "failed" "Validation phase failed"
        log_error "Validation phase failed. Please fix the issues above."
        exit 1
    fi
    
    create_checkpoint "validation" "completed" "Validation phase completed successfully"
    log_success "Validation phase completed successfully"
}

# Function to validate project structure
validate_project_structure() {
    local required_dirs=(
        "scripts/infrastructure"
        "scripts/deployment"
        "scripts/migration"
        "scripts/utilities"
    )
    
    local required_files=(
        "scripts/deploy.sh"
        "scripts/infrastructure/provision-rds.sh"
        "scripts/infrastructure/provision-lambda.sh"
        "scripts/migration/run-migrations.sh"
        "scripts/deployment/deploy-lambda.sh"
    )
    
    # Check directories
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_error "Required directory not found: $dir"
            return 1
        fi
    done
    
    # Check files
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "Required file not found: $file"
            return 1
        fi
        
        if [ ! -x "$file" ]; then
            log_error "File not executable: $file"
            return 1
        fi
    done
    
    log_success "Project structure validation passed"
    return 0
}

# Function to validate configuration files
validate_configuration_files() {
    local config_files=(
        "appsettings.json"
        "appsettings.$ENVIRONMENT.json"
    )
    
    for config_file in "${config_files[@]}"; do
        if [ -f "$config_file" ]; then
            log_info "Validating configuration file: $config_file"
            
            # Validate JSON syntax
            if ! jq empty "$config_file" 2>/dev/null; then
                log_error "Invalid JSON in configuration file: $config_file"
                return 1
            fi
            
            # Validate Cognito configuration if present
            if jq -e '.AWS.Cognito' "$config_file" >/dev/null 2>&1; then
                log_info "Validating Cognito configuration in $config_file"
                if ! "$UTILITIES_DIR/validate-cognito.sh" validate --config "$config_file"; then
                    log_warn "Cognito validation failed for $config_file"
                fi
            fi
        fi
    done
    
    log_success "Configuration files validation passed"
    return 0
}

# Function to generate cost estimation
generate_cost_estimation() {
    log_info "Generating cost estimation for $ENVIRONMENT environment"
    
    local cost_report="$DEPLOYMENT_LOG_DIR/cost-estimation.md"
    
    if "$UTILITIES_DIR/cost-optimization.sh" report \
        --environment "$ENVIRONMENT" \
        --region "$AWS_REGION" \
        --output "$cost_report"; then
        
        log_success "Cost estimation report generated: $cost_report"
        return 0
    else
        log_error "Failed to generate cost estimation"
        return 1
    fi
}

# Function to deploy infrastructure
deploy_infrastructure() {
    log_info "=== Phase 2: Infrastructure Deployment ==="
    create_checkpoint "infrastructure" "in_progress" "Starting infrastructure deployment"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would deploy infrastructure components"
        create_checkpoint "infrastructure" "completed" "Infrastructure deployment (dry run)"
        return 0
    fi
    
    # Deploy RDS
    log_info "Deploying RDS PostgreSQL..."
    if ! "$SCRIPT_DIR/../infrastructure/provision-rds.sh" \
        --environment "$ENVIRONMENT" \
        --project-name "$PROJECT_NAME"; then
        
        create_checkpoint "infrastructure" "failed" "RDS deployment failed"
        log_error "RDS deployment failed"
        return 1
    fi
    
    # Deploy Lambda
    log_info "Deploying Lambda function..."
    if ! "$SCRIPT_DIR/../infrastructure/provision-lambda.sh" \
        --environment "$ENVIRONMENT" \
        --project-name "$PROJECT_NAME"; then
        
        create_checkpoint "infrastructure" "failed" "Lambda deployment failed"
        log_error "Lambda deployment failed"
        return 1
    fi
    
    # Configure IAM
    log_info "Configuring IAM roles and policies..."
    if ! "$SCRIPT_DIR/../infrastructure/configure-iam.sh" \
        --environment "$ENVIRONMENT" \
        --project-name "$PROJECT_NAME"; then
        
        create_checkpoint "infrastructure" "failed" "IAM configuration failed"
        log_error "IAM configuration failed"
        return 1
    fi
    
    create_checkpoint "infrastructure" "completed" "Infrastructure deployment completed"
    log_success "Infrastructure deployment completed successfully"
}

# Function to setup database
setup_database() {
    log_info "=== Phase 3: Database Setup ==="
    create_checkpoint "database" "in_progress" "Starting database setup"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would setup database and run migrations"
        create_checkpoint "database" "completed" "Database setup (dry run)"
        return 0
    fi
    
    # Wait for RDS to be available
    log_info "Waiting for RDS instance to be available..."
    if ! wait_for_rds_availability; then
        create_checkpoint "database" "failed" "RDS not available"
        log_error "RDS instance is not available"
        return 1
    fi
    
    # Run migrations
    log_info "Running database migrations..."
    if ! "$SCRIPT_DIR/../migration/run-migrations.sh" \
        --environment "$ENVIRONMENT"; then
        
        create_checkpoint "database" "failed" "Database migrations failed"
        log_error "Database migrations failed"
        return 1
    fi
    
    # Seed initial data
    log_info "Seeding initial data..."
    if ! "$SCRIPT_DIR/../migration/seed-data.sh" \
        --environment "$ENVIRONMENT"; then
        
        create_checkpoint "database" "failed" "Data seeding failed"
        log_error "Data seeding failed"
        return 1
    fi
    
    create_checkpoint "database" "completed" "Database setup completed"
    log_success "Database setup completed successfully"
}

# Function to deploy application
deploy_application() {
    log_info "=== Phase 4: Application Deployment ==="
    create_checkpoint "application" "in_progress" "Starting application deployment"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would deploy application code"
        create_checkpoint "application" "completed" "Application deployment (dry run)"
        return 0
    fi
    
    # Configure environment variables
    log_info "Configuring environment variables..."
    if ! "$SCRIPT_DIR/../deployment/configure-environment.sh" \
        --environment "$ENVIRONMENT" \
        --project-name "$PROJECT_NAME"; then
        
        create_checkpoint "application" "failed" "Environment configuration failed"
        log_error "Environment configuration failed"
        return 1
    fi
    
    # Deploy Lambda code (if deployment package exists)
    if [ -f "deployment.zip" ]; then
        log_info "Deploying Lambda application code..."
        if ! "$SCRIPT_DIR/../deployment/deploy-lambda.sh" \
            --zip-file "deployment.zip" \
            --environment "$ENVIRONMENT" \
            --project-name "$PROJECT_NAME"; then
            
            create_checkpoint "application" "failed" "Lambda code deployment failed"
            log_error "Lambda code deployment failed"
            return 1
        fi
    else
        log_warn "No deployment.zip found, skipping Lambda code deployment"
    fi
    
    # Update Lambda environment variables
    log_info "Updating Lambda environment variables..."
    if ! "$SCRIPT_DIR/../deployment/update-lambda-environment.sh" \
        --environment "$ENVIRONMENT" \
        --project-name "$PROJECT_NAME"; then
        
        create_checkpoint "application" "failed" "Lambda environment update failed"
        log_error "Lambda environment update failed"
        return 1
    fi
    
    create_checkpoint "application" "completed" "Application deployment completed"
    log_success "Application deployment completed successfully"
}

# Function to verify deployment
verify_deployment() {
    log_info "=== Phase 5: Deployment Verification ==="
    create_checkpoint "verification" "in_progress" "Starting deployment verification"
    
    local verification_failed=false
    
    # Check infrastructure status
    log_info "Verifying infrastructure status..."
    if ! "$UTILITIES_DIR/check-infrastructure.sh" \
        --environment "$ENVIRONMENT" \
        --project-name "$PROJECT_NAME"; then
        
        log_error "Infrastructure verification failed"
        verification_failed=true
    fi
    
    # Test database connectivity
    log_info "Testing database connectivity..."
    if ! test_database_connectivity; then
        log_error "Database connectivity test failed"
        verification_failed=true
    fi
    
    # Test Lambda function
    log_info "Testing Lambda function..."
    if ! test_lambda_function; then
        log_error "Lambda function test failed"
        verification_failed=true
    fi
    
    # Test Cognito integration (if configured)
    log_info "Testing Cognito integration..."
    if ! test_cognito_integration; then
        log_warn "Cognito integration test failed or not configured"
    fi
    
    if [ "$verification_failed" = true ]; then
        create_checkpoint "verification" "failed" "Deployment verification failed"
        log_error "Deployment verification failed"
        return 1
    fi
    
    create_checkpoint "verification" "completed" "Deployment verification completed"
    log_success "Deployment verification completed successfully"
}

# Function to wait for RDS availability
wait_for_rds_availability() {
    local db_identifier="$PROJECT_NAME-$ENVIRONMENT-db"
    local max_wait=1800  # 30 minutes
    local wait_interval=30
    local elapsed=0
    
    log_info "Waiting for RDS instance to be available: $db_identifier"
    
    while [ $elapsed -lt $max_wait ]; do
        local status=$(aws rds describe-db-instances \
            --db-instance-identifier "$db_identifier" \
            --query 'DBInstances[0].DBInstanceStatus' \
            --output text 2>/dev/null || echo "not-found")
        
        if [ "$status" = "available" ]; then
            log_success "RDS instance is available"
            return 0
        elif [ "$status" = "not-found" ]; then
            log_error "RDS instance not found: $db_identifier"
            return 1
        fi
        
        log_info "RDS status: $status, waiting..."
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done
    
    log_error "Timeout waiting for RDS instance to be available"
    return 1
}

# Function to test database connectivity
test_database_connectivity() {
    log_info "Testing database connectivity..."
    
    # Try to run a simple migration test
    if "$SCRIPT_DIR/../migration/run-migrations.sh" --dry-run --environment "$ENVIRONMENT"; then
        log_success "Database connectivity test passed"
        return 0
    else
        log_error "Database connectivity test failed"
        return 1
    fi
}

# Function to test Lambda function
test_lambda_function() {
    local function_name="$PROJECT_NAME-$ENVIRONMENT-api"
    
    log_info "Testing Lambda function: $function_name"
    
    # Test Lambda function with a simple payload
    local test_payload='{"test": "deployment-verification"}'
    local response_file="/tmp/lambda-test-response.json"
    
    if aws lambda invoke \
        --function-name "$function_name" \
        --payload "$test_payload" \
        "$response_file" >/dev/null 2>&1; then
        
        log_success "Lambda function test passed"
        log_debug "Lambda response: $(cat "$response_file")"
        rm -f "$response_file"
        return 0
    else
        log_error "Lambda function test failed"
        return 1
    fi
}

# Function to test Cognito integration
test_cognito_integration() {
    # Check if Cognito configuration exists
    if [ -f "appsettings.json" ] && jq -e '.AWS.Cognito' appsettings.json >/dev/null 2>&1; then
        log_info "Testing Cognito integration..."
        
        if "$UTILITIES_DIR/validate-cognito.sh" validate --config appsettings.json; then
            log_success "Cognito integration test passed"
            return 0
        else
            log_error "Cognito integration test failed"
            return 1
        fi
    else
        log_info "No Cognito configuration found, skipping test"
        return 0
    fi
}

# Function to cleanup deployment
cleanup_deployment() {
    log_info "=== Cleanup Mode ==="
    
    if [ "$FORCE_CLEANUP" = false ]; then
        echo "This will delete ALL AWS resources for $PROJECT_NAME-$ENVIRONMENT"
        echo "This action cannot be undone!"
        read -p "Are you sure you want to continue? (yes/no): " confirm
        
        if [ "$confirm" != "yes" ]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    create_checkpoint "cleanup" "in_progress" "Starting cleanup"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would cleanup all AWS resources"
        create_checkpoint "cleanup" "completed" "Cleanup (dry run)"
        return 0
    fi
    
    # Run cleanup script
    log_info "Running infrastructure cleanup..."
    if "$SCRIPT_DIR/../infrastructure/cleanup-infrastructure.sh" \
        --environment "$ENVIRONMENT" \
        --project-name "$PROJECT_NAME" \
        --force; then
        
        create_checkpoint "cleanup" "completed" "Cleanup completed successfully"
        log_success "Cleanup completed successfully"
    else
        create_checkpoint "cleanup" "failed" "Cleanup failed"
        log_error "Cleanup failed"
        return 1
    fi
}

# Function to generate deployment report
generate_deployment_report() {
    local report_file="$DEPLOYMENT_LOG_DIR/deployment-report.md"
    
    log_info "Generating deployment report: $report_file"
    
    cat > "$report_file" << EOF
# Deployment Report

**Deployment ID:** $DEPLOYMENT_ID  
**Timestamp:** $(date -u +%Y-%m-%dT%H:%M:%SZ)  
**Environment:** $ENVIRONMENT  
**Project:** $PROJECT_NAME  
**Region:** $AWS_REGION  
**Mode:** $MODE  

## Configuration

\`\`\`json
$(cat "$DEPLOYMENT_LOG_DIR/config.json")
\`\`\`

## Deployment Phases

EOF
    
    # Add phase status
    for phase in "${DEPLOYMENT_PHASES[@]}"; do
        local checkpoint_file="$CHECKPOINT_DIR/${DEPLOYMENT_ID}_${phase}.checkpoint"
        if [ -f "$checkpoint_file" ]; then
            local status=$(jq -r '.status' "$checkpoint_file")
            local timestamp=$(jq -r '.timestamp' "$checkpoint_file")
            local message=$(jq -r '.message' "$checkpoint_file")
            
            echo "### $phase" >> "$report_file"
            echo "- **Status:** $status" >> "$report_file"
            echo "- **Timestamp:** $timestamp" >> "$report_file"
            echo "- **Message:** $message" >> "$report_file"
            echo "" >> "$report_file"
        fi
    done
    
    # Add cost estimation if available
    if [ -f "$DEPLOYMENT_LOG_DIR/cost-estimation.md" ]; then
        echo "## Cost Estimation" >> "$report_file"
        echo "" >> "$report_file"
        cat "$DEPLOYMENT_LOG_DIR/cost-estimation.md" >> "$report_file"
    fi
    
    # Add logs summary
    echo "## Logs" >> "$report_file"
    echo "" >> "$report_file"
    echo "- **Deployment Log:** $DEPLOYMENT_LOG_DIR/deployment.log" >> "$report_file"
    echo "- **Error Log:** $DEPLOYMENT_LOG_DIR/errors.log" >> "$report_file"
    echo "- **Checkpoints:** $CHECKPOINT_DIR/" >> "$report_file"
    
    log_success "Deployment report generated: $report_file"
}

# Main execution function
main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Setup deployment environment
    setup_deployment_environment
    
    log_info "Starting full deployment orchestration"
    log_info "Mode: $MODE, Environment: $ENVIRONMENT, Project: $PROJECT_NAME"
    
    # Execute based on mode
    case "$MODE" in
        "initial"|"update")
            validate_deployment
            deploy_infrastructure
            setup_database
            deploy_application
            verify_deployment
            ;;
        "cleanup")
            cleanup_deployment
            ;;
        *)
            log_error "Invalid mode: $MODE"
            exit 1
            ;;
    esac
    
    # Generate deployment report
    generate_deployment_report
    
    log_success "Deployment orchestration completed successfully!"
    log_info "Deployment ID: $DEPLOYMENT_ID"
    log_info "Logs available in: $DEPLOYMENT_LOG_DIR"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi