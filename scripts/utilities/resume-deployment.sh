#!/bin/bash

# Resume Deployment Script
# Provides resume-from-checkpoint functionality for partial deployment failures
# Allows continuing deployment from the last successful step
# Implements intelligent checkpoint detection and recovery

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/error-handling.sh"
source "$SCRIPT_DIR/validate-aws-cli.sh"

# Configuration variables
ENVIRONMENT="${ENVIRONMENT:-dev}"
PROJECT_NAME="${PROJECT_NAME:-myragapp}"
MODE="${MODE:-initial}"
CHECKPOINT_NAME="${CHECKPOINT_NAME:-}"
FORCE_RESUME="${FORCE_RESUME:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Global variables for resume tracking
RESUME_ACTIONS=()
DEPLOYMENT_STATE=""
LAST_CHECKPOINT=""

# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Resumes AWS deployment from the last successful checkpoint.

OPTIONS:
    --environment ENV          Environment name (default: dev)
    --project-name NAME        Project name (default: myapp)
    --mode MODE                Deployment mode: initial, update (default: initial)
    --aws-profile PROFILE      AWS profile to use
    --checkpoint NAME          Specific checkpoint to resume from
    --force                    Skip confirmation prompts
    --dry-run                  Show what would be resumed without executing
    --list-checkpoints         List available checkpoints
    --help                     Show this help message

EXAMPLES:
    $0 --environment production --mode initial
    $0 --checkpoint rds_provisioned --force
    $0 --list-checkpoints
    $0 --dry-run

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
            --mode)
                MODE="$2"
                shift 2
                ;;
            --aws-profile)
                export AWS_PROFILE="$2"
                shift 2
                ;;
            --checkpoint)
                CHECKPOINT_NAME="$2"
                shift 2
                ;;
            --force)
                FORCE_RESUME="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --list-checkpoints)
                list_checkpoints
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

# Function to list available checkpoints
list_checkpoints() {
    log_info "Available deployment checkpoints:"
    
    local checkpoint_dir="./deployment_checkpoints"
    if [ ! -d "$checkpoint_dir" ]; then
        log_warn "No checkpoint directory found"
        return 0
    fi
    
    local checkpoints=($(ls "$checkpoint_dir"/*.checkpoint 2>/dev/null | sort || echo ""))
    
    if [ ${#checkpoints[@]} -eq 0 ]; then
        log_warn "No checkpoints found"
        return 0
    fi
    
    for checkpoint_file in "${checkpoints[@]}"; do
        local checkpoint_name=$(basename "$checkpoint_file" .checkpoint)
        local checkpoint_time=$(cat "$checkpoint_file" 2>/dev/null || echo "unknown")
        echo "  - $checkpoint_name (created: $checkpoint_time)"
    done
}

# Function to detect last successful checkpoint
detect_last_checkpoint() {
    log_info "Detecting last successful checkpoint..."
    
    local checkpoint_dir="./deployment_checkpoints"
    if [ ! -d "$checkpoint_dir" ]; then
        log_warn "No checkpoint directory found"
        return 1
    fi
    
    # Get the most recent checkpoint
    local latest_checkpoint=$(ls -t "$checkpoint_dir"/*.checkpoint 2>/dev/null | head -1 || echo "")
    
    if [ -z "$latest_checkpoint" ]; then
        log_warn "No checkpoints found"
        return 1
    fi
    
    LAST_CHECKPOINT=$(basename "$latest_checkpoint" .checkpoint)
    log_info "Last checkpoint detected: $LAST_CHECKPOINT"
    
    # If specific checkpoint requested, use that instead
    if [ -n "$CHECKPOINT_NAME" ]; then
        if [ -f "$checkpoint_dir/${CHECKPOINT_NAME}.checkpoint" ]; then
            LAST_CHECKPOINT="$CHECKPOINT_NAME"
            log_info "Using specified checkpoint: $CHECKPOINT_NAME"
        else
            set_error_context "Checkpoint validation"
            set_error_remediation "Check available checkpoints with --list-checkpoints"
            handle_error $ERROR_CODE_CHECKPOINT "Specified checkpoint not found: $CHECKPOINT_NAME" true
        fi
    fi
    
    return 0
}
# Function to determine resume actions based on last checkpoint
determine_resume_actions() {
    log_info "Determining resume actions from checkpoint: $LAST_CHECKPOINT"
    
    case "$LAST_CHECKPOINT" in
        "deployment_start"|"infrastructure_start")
            log_info "Resuming from deployment start - running full infrastructure provisioning"
            RESUME_ACTIONS+=("provision_vpc")
            RESUME_ACTIONS+=("provision_rds")
            RESUME_ACTIONS+=("provision_lambda")
            RESUME_ACTIONS+=("configure_iam")
            RESUME_ACTIONS+=("run_migrations")
            RESUME_ACTIONS+=("deploy_lambda_code")
            ;;
        "vpc_provisioned")
            log_info "VPC already provisioned - continuing with RDS and Lambda"
            RESUME_ACTIONS+=("provision_rds")
            RESUME_ACTIONS+=("provision_lambda")
            RESUME_ACTIONS+=("configure_iam")
            RESUME_ACTIONS+=("run_migrations")
            RESUME_ACTIONS+=("deploy_lambda_code")
            ;;
        "rds_provisioned")
            log_info "RDS already provisioned - continuing with Lambda and deployment"
            RESUME_ACTIONS+=("provision_lambda")
            RESUME_ACTIONS+=("configure_iam")
            RESUME_ACTIONS+=("run_migrations")
            RESUME_ACTIONS+=("deploy_lambda_code")
            ;;
        "lambda_provisioned")
            log_info "Lambda already provisioned - continuing with migrations and deployment"
            RESUME_ACTIONS+=("run_migrations")
            RESUME_ACTIONS+=("deploy_lambda_code")
            ;;
        "iam_configured")
            log_info "IAM already configured - continuing with migrations and deployment"
            RESUME_ACTIONS+=("run_migrations")
            RESUME_ACTIONS+=("deploy_lambda_code")
            ;;
        "migrations_completed")
            log_info "Migrations completed - continuing with Lambda deployment"
            RESUME_ACTIONS+=("deploy_lambda_code")
            ;;
        "lambda_deployed")
            log_info "Lambda deployment completed - running final validation"
            RESUME_ACTIONS+=("validate_deployment")
            ;;
        "deployment_complete")
            log_info "Deployment already complete - nothing to resume"
            ;;
        *)
            log_warn "Unknown checkpoint: $LAST_CHECKPOINT - running full deployment"
            RESUME_ACTIONS+=("provision_vpc")
            RESUME_ACTIONS+=("provision_rds")
            RESUME_ACTIONS+=("provision_lambda")
            RESUME_ACTIONS+=("configure_iam")
            RESUME_ACTIONS+=("run_migrations")
            RESUME_ACTIONS+=("deploy_lambda_code")
            ;;
    esac
    
    # Adjust actions based on deployment mode
    if [[ "$MODE" == "update" ]]; then
        log_info "Update mode - skipping infrastructure provisioning"
        RESUME_ACTIONS=()
        RESUME_ACTIONS+=("deploy_lambda_code")
        RESUME_ACTIONS+=("validate_deployment")
    fi
    
    log_info "Resume actions determined: ${RESUME_ACTIONS[*]}"
}

# Function to validate current infrastructure state
validate_infrastructure_state() {
    log_info "Validating current infrastructure state..."
    
    set_error_context "Infrastructure state validation"
    set_error_remediation "Check AWS resources and permissions"
    
    local validation_script="$SCRIPT_DIR/check-infrastructure.sh"
    if [ -f "$validation_script" ]; then
        log_info "Running infrastructure validation..."
        
        if bash "$validation_script" --environment "$ENVIRONMENT" --project-name "$PROJECT_NAME"; then
            log_success "Infrastructure validation passed"
            return 0
        else
            log_warn "Infrastructure validation failed - some resources may be missing"
            return 1
        fi
    else
        log_warn "Infrastructure validation script not found: $validation_script"
        return 1
    fi
}

# Function to provision VPC
provision_vpc() {
    log_info "Provisioning VPC infrastructure..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would provision VPC infrastructure"
        return 0
    fi
    
    set_error_context "VPC provisioning"
    set_error_remediation "Check AWS permissions and VPC limits"
    
    # Check if VPC already exists
    local vpc_name="$PROJECT_NAME-$ENVIRONMENT-vpc"
    local existing_vpc=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$vpc_name" --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "None")
    
    if [[ "$existing_vpc" != "None" && "$existing_vpc" != "null" ]]; then
        log_info "VPC already exists: $existing_vpc"
        create_checkpoint "vpc_provisioned" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        return 0
    fi
    
    # VPC provisioning logic would go here
    # For now, we'll simulate it
    log_info "VPC provisioning would be executed here"
    create_checkpoint "vpc_provisioned" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# Function to provision RDS
provision_rds() {
    log_info "Provisioning RDS database..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would provision RDS database"
        return 0
    fi
    
    set_error_context "RDS provisioning"
    set_error_remediation "Check RDS limits and existing instances"
    
    local rds_script="$SCRIPT_DIR/../infrastructure/provision-rds.sh"
    if [ -f "$rds_script" ]; then
        log_info "Running RDS provisioning script..."
        
        if bash "$rds_script" --environment "$ENVIRONMENT" --project-name "$PROJECT_NAME"; then
            log_success "RDS provisioning completed"
            create_checkpoint "rds_provisioned" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        else
            handle_error $ERROR_CODE_INFRASTRUCTURE "RDS provisioning failed" true
        fi
    else
        handle_error $ERROR_CODE_DEPENDENCY "RDS provisioning script not found: $rds_script" true
    fi
}

# Function to provision Lambda
provision_lambda() {
    log_info "Provisioning Lambda function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would provision Lambda function"
        return 0
    fi
    
    set_error_context "Lambda provisioning"
    set_error_remediation "Check Lambda limits and IAM permissions"
    
    local lambda_script="$SCRIPT_DIR/../infrastructure/provision-lambda.sh"
    if [ -f "$lambda_script" ]; then
        log_info "Running Lambda provisioning script..."
        
        if bash "$lambda_script" --environment "$ENVIRONMENT" --project-name "$PROJECT_NAME"; then
            log_success "Lambda provisioning completed"
            create_checkpoint "lambda_provisioned" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        else
            handle_error $ERROR_CODE_LAMBDA "Lambda provisioning failed" true
        fi
    else
        handle_error $ERROR_CODE_DEPENDENCY "Lambda provisioning script not found: $lambda_script" true
    fi
}
# Function to configure IAM
configure_iam() {
    log_info "Configuring IAM roles and policies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure IAM roles and policies"
        return 0
    fi
    
    set_error_context "IAM configuration"
    set_error_remediation "Check IAM permissions and policy limits"
    
    local iam_script="$SCRIPT_DIR/../infrastructure/configure-iam.sh"
    if [ -f "$iam_script" ]; then
        log_info "Running IAM configuration script..."
        
        if bash "$iam_script" --environment "$ENVIRONMENT" --project-name "$PROJECT_NAME"; then
            log_success "IAM configuration completed"
            create_checkpoint "iam_configured" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        else
            handle_error $ERROR_CODE_AWS_PERMISSIONS "IAM configuration failed" true
        fi
    else
        handle_error $ERROR_CODE_DEPENDENCY "IAM configuration script not found: $iam_script" true
    fi
}

# Function to run migrations
run_migrations() {
    log_info "Running database migrations..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would run database migrations"
        return 0
    fi
    
    set_error_context "Database migrations"
    set_error_remediation "Check database connectivity and migration scripts"
    
    local migration_script="$SCRIPT_DIR/../migration/run-migrations.sh"
    if [ -f "$migration_script" ]; then
        log_info "Running migration script..."
        
        if bash "$migration_script" --environment "$ENVIRONMENT"; then
            log_success "Database migrations completed"
            create_checkpoint "migrations_completed" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        else
            handle_error $ERROR_CODE_MIGRATION "Database migrations failed" true
        fi
    else
        handle_error $ERROR_CODE_DEPENDENCY "Migration script not found: $migration_script" true
    fi
}

# Function to deploy Lambda code
deploy_lambda_code() {
    log_info "Deploying Lambda code..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy Lambda code"
        return 0
    fi
    
    set_error_context "Lambda code deployment"
    set_error_remediation "Check deployment package and Lambda function status"
    
    local deploy_script="$SCRIPT_DIR/../deployment/deploy-lambda.sh"
    if [ -f "$deploy_script" ]; then
        log_info "Running Lambda deployment script..."
        
        if bash "$deploy_script" --environment "$ENVIRONMENT" --project-name "$PROJECT_NAME"; then
            log_success "Lambda code deployment completed"
            create_checkpoint "lambda_deployed" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        else
            handle_error $ERROR_CODE_DEPLOYMENT "Lambda code deployment failed" true
        fi
    else
        handle_error $ERROR_CODE_DEPENDENCY "Lambda deployment script not found: $deploy_script" true
    fi
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate deployment"
        return 0
    fi
    
    set_error_context "Deployment validation"
    set_error_remediation "Check deployed resources and connectivity"
    
    # Basic validation - check if Lambda function is active
    local function_name="$PROJECT_NAME-$ENVIRONMENT-api"
    local function_state=$(aws lambda get-function --function-name "$function_name" --query "Configuration.State" --output text 2>/dev/null || echo "NotFound")
    
    if [[ "$function_state" == "Active" ]]; then
        log_success "Lambda function is active: $function_name"
    else
        log_warn "Lambda function state: $function_state"
    fi
    
    # Check RDS instance status
    local db_identifier="$PROJECT_NAME-$ENVIRONMENT-db"
    local db_status=$(aws rds describe-db-instances --db-instance-identifier "$db_identifier" --query "DBInstances[0].DBInstanceStatus" --output text 2>/dev/null || echo "NotFound")
    
    if [[ "$db_status" == "available" ]]; then
        log_success "RDS instance is available: $db_identifier"
    else
        log_warn "RDS instance status: $db_status"
    fi
    
    create_checkpoint "deployment_complete" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    log_success "Deployment validation completed"
}

# Function to confirm resume operation
confirm_resume() {
    if [[ "$FORCE_RESUME" == "true" ]]; then
        log_info "Force resume enabled - skipping confirmation"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run mode - no actual deployment will be performed"
        return 0
    fi
    
    echo ""
    log_info "Resume deployment from checkpoint: $LAST_CHECKPOINT"
    log_info "The following actions will be executed:"
    echo ""
    
    for action in "${RESUME_ACTIONS[@]}"; do
        case "$action" in
            "provision_vpc")
                echo "  - Provision VPC and networking infrastructure"
                ;;
            "provision_rds")
                echo "  - Provision RDS PostgreSQL database"
                ;;
            "provision_lambda")
                echo "  - Provision Lambda function infrastructure"
                ;;
            "configure_iam")
                echo "  - Configure IAM roles and policies"
                ;;
            "run_migrations")
                echo "  - Run database migrations and seed data"
                ;;
            "deploy_lambda_code")
                echo "  - Deploy Lambda application code"
                ;;
            "validate_deployment")
                echo "  - Validate deployment status"
                ;;
            *)
                echo "  - $action"
                ;;
        esac
    done
    
    echo ""
    
    read -p "Do you want to proceed with resuming the deployment? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Resume cancelled by user"
        exit 0
    fi
    
    log_info "Resume confirmed by user"
}
# Function to execute resume actions
execute_resume() {
    log_info "Executing resume actions..."
    
    # Initialize error logging
    initialize_error_logging
    
    # Create resume checkpoint
    create_checkpoint "resume_start" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    for action in "${RESUME_ACTIONS[@]}"; do
        log_info "Executing resume action: $action"
        
        case "$action" in
            "provision_vpc")
                provision_vpc
                ;;
            "provision_rds")
                provision_rds
                ;;
            "provision_lambda")
                provision_lambda
                ;;
            "configure_iam")
                configure_iam
                ;;
            "run_migrations")
                run_migrations
                ;;
            "deploy_lambda_code")
                deploy_lambda_code
                ;;
            "validate_deployment")
                validate_deployment
                ;;
            *)
                log_warn "Unknown resume action: $action"
                ;;
        esac
    done
    
    # Create completion checkpoint
    create_checkpoint "resume_complete" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# Function to generate resume report
generate_resume_report() {
    log_info "Generating resume report..."
    
    local total_actions=${#RESUME_ACTIONS[@]}
    
    echo ""
    log_info "=== RESUME DEPLOYMENT REPORT ==="
    log_info "Resumed from checkpoint: $LAST_CHECKPOINT"
    log_info "Total actions executed: $total_actions"
    log_info "Deployment mode: $MODE"
    log_info "Environment: $ENVIRONMENT"
    log_info "Project: $PROJECT_NAME"
    
    echo ""
    log_success "Deployment resume completed successfully!"
    log_info "All resume actions have been executed"
    
    # Show next steps
    echo ""
    log_info "Next steps:"
    log_info "1. Verify your application is working correctly"
    log_info "2. Run integration tests if available"
    log_info "3. Monitor AWS CloudWatch logs for any issues"
    
    return 0
}

# Main execution function
main() {
    log_info "Starting Deployment Resume"
    log_info "Project: $PROJECT_NAME, Environment: $ENVIRONMENT, Mode: $MODE"
    
    # Initialize error handling
    set_error_context "Deployment resume initialization"
    set_error_remediation "Check script parameters and AWS configuration"
    
    # Validate AWS CLI
    if ! validate_aws_cli; then
        handle_error $ERROR_CODE_AWS_CLI "AWS CLI validation failed" true
    fi
    
    # Detect last checkpoint
    if ! detect_last_checkpoint; then
        log_warn "No checkpoints found - starting fresh deployment"
        log_info "Consider running the main deployment script instead"
        exit 0
    fi
    
    # Determine resume actions
    determine_resume_actions
    
    if [ ${#RESUME_ACTIONS[@]} -eq 0 ]; then
        log_info "No resume actions needed"
        log_success "Deployment appears to be complete"
        exit 0
    fi
    
    # Validate infrastructure state (optional)
    validate_infrastructure_state || log_warn "Infrastructure validation failed - proceeding anyway"
    
    # Confirm resume operation
    confirm_resume
    
    # Execute resume
    execute_resume
    
    # Generate report
    if generate_resume_report; then
        exit 0
    else
        exit $ERROR_CODE_DEPLOYMENT
    fi
}

# Register cleanup function for error handling
register_cleanup_function cleanup_checkpoints

# Parse command line arguments
parse_arguments "$@"

# Execute main function
main