#!/bin/bash

# AWS Deployment Automation - Master Deployment Script
# Orchestrates the entire deployment process with mode selection and environment support
# 
# Usage: ./deploy.sh --mode <initial|update|cleanup> --environment <development|staging|production> [options]
#
# Requirements: 3.1, 3.2, 4.3

set -euo pipefail

# Script directory and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utilities/logging.sh"
source "$SCRIPT_DIR/utilities/error-handling.sh"
source "$SCRIPT_DIR/utilities/validate-aws-cli.sh"

# Script metadata
readonly SCRIPT_NAME="AWS Deployment Automation"
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_AUTHOR="AWS Deployment Automation System"

# Default values
DEFAULT_ENVIRONMENT="development"
DEFAULT_LOG_LEVEL="INFO"
DEFAULT_AWS_REGION="us-east-1"

# Initialize LOG_LEVEL early to avoid warnings
LOG_LEVEL=${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}

# Global variables
MODE=""
ENVIRONMENT=""
PROJECT_NAME=""
AWS_PROFILE=""
AWS_REGION=""
LOG_LEVEL=""
DRY_RUN=false
FORCE=false
SKIP_VALIDATION=false
CONFIG_FILE=""
CHECKPOINT_NAME=""
ROLLBACK_SCOPE=""
LIST_CHECKPOINTS=false

# Function to display script header
show_header() {
    echo "========================================"
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo "========================================"
    echo ""
}

# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 --mode <MODE> --environment <ENVIRONMENT> [OPTIONS]

DESCRIPTION:
    Master deployment script for AWS infrastructure and .NET 10 application deployment.
    Supports initial infrastructure provisioning, code updates, cleanup operations, and recovery.

REQUIRED ARGUMENTS:
    --mode, -m <MODE>           Deployment mode (required)
                               initial  - Provision infrastructure and deploy code
                               update   - Deploy code changes only (no infrastructure)
                               cleanup  - Remove all provisioned resources
                               rollback - Rollback failed deployment
                               resume   - Resume from last checkpoint

    --environment, -e <ENV>     Target environment (required)
                               development - Development environment
                               staging     - Staging environment  
                               production  - Production environment

    --project-name, -p <NAME>   Project name for resource naming (required)
                               Used as prefix for AWS resource names

OPTIONS:
    --aws-profile <PROFILE>     AWS CLI profile to use (optional)
    --aws-region <REGION>       AWS region (default: $DEFAULT_AWS_REGION)
    --log-level <LEVEL>         Logging level: ERROR|WARN|INFO|DEBUG (default: $DEFAULT_LOG_LEVEL)
    --config-file <FILE>        Custom configuration file path (optional)
    --dry-run                   Show what would be done without executing
    --force                     Skip confirmation prompts
    --skip-validation           Skip AWS CLI and permissions validation
    --checkpoint <NAME>         Specific checkpoint for rollback/resume operations
    --rollback-scope <SCOPE>    Rollback scope: all, lambda, rds, iam, partial
    --list-checkpoints          List available deployment checkpoints
    --help, -h                  Show this help message
    --version, -v               Show version information

EXAMPLES:
    # Initial deployment to production
    $0 --mode initial --environment production --project-name myapp

    # Update deployment with specific AWS profile
    $0 --mode update --environment staging --project-name myapp --aws-profile my-profile

    # Cleanup with debug logging
    $0 --mode cleanup --environment development --project-name myapp --log-level DEBUG

    # Rollback failed deployment
    $0 --mode rollback --environment production --project-name myapp --force

    # Resume from specific checkpoint
    $0 --mode resume --environment production --project-name myapp --checkpoint rds_provisioned

    # List available checkpoints
    $0 --list-checkpoints

    # Dry run to see what would be deployed
    $0 --mode initial --environment production --project-name myapp --dry-run

DEPLOYMENT MODES:
    initial:
        - Validates AWS CLI and permissions
        - Provisions RDS PostgreSQL instance
        - Creates Lambda functions and IAM roles
        - Sets up VPC networking and security groups
        - Runs Entity Framework migrations
        - Deploys .NET 10 application code
        - Configures environment variables

    update:
        - Validates existing infrastructure
        - Deploys updated application code
        - Updates Lambda environment variables
        - Runs any pending migrations
        - No infrastructure changes

    cleanup:
        - Removes Lambda functions
        - Deletes RDS instance (with confirmation)
        - Cleans up VPC resources
        - Removes IAM roles and policies
        - Deletes deployment artifacts

    rollback:
        - Analyzes deployment state and errors
        - Rolls back Lambda deployments to previous versions
        - Cleans up partial infrastructure provisioning
        - Restores from database snapshots if available
        - Provides recovery guidance for manual steps

    resume:
        - Detects last successful checkpoint
        - Continues deployment from interruption point
        - Validates existing infrastructure state
        - Executes remaining deployment steps
        - Creates new checkpoints for progress tracking

RECOVERY FEATURES:
    - Automatic checkpoint creation during deployment
    - Intelligent rollback based on failure type
    - Resume capability from any checkpoint
    - Comprehensive error logging and reporting
    - Manual recovery guidance for complex scenarios

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - .NET 10 SDK installed
    - Entity Framework CLI tools
    - Appropriate AWS IAM permissions
    - Valid appsettings.json configuration

For detailed documentation, see: $SCRIPT_DIR/README.md
EOF
}

# Function to display version information
show_version() {
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo "Author: $SCRIPT_AUTHOR"
    echo ""
    echo "Dependencies:"
    echo "  - AWS CLI: $(aws --version 2>&1 | head -n1 || echo 'Not installed')"
    echo "  - .NET: $(dotnet --version 2>/dev/null || echo 'Not installed')"
    echo "  - Bash: $BASH_VERSION"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mode|-m)
                MODE="$2"
                shift 2
                ;;
            --environment|-e)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --project-name|-p)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --aws-profile)
                AWS_PROFILE="$2"
                shift 2
                ;;
            --aws-region)
                AWS_REGION="$2"
                shift 2
                ;;
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            --log-level)
                LOG_LEVEL="$2"
                shift 2
                ;;
            --config-file)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --checkpoint)
                CHECKPOINT_NAME="$2"
                shift 2
                ;;
            --rollback-scope)
                ROLLBACK_SCOPE="$2"
                shift 2
                ;;
            --list-checkpoints)
                LIST_CHECKPOINTS=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            --version|-v)
                show_version
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                echo ""
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to validate arguments
validate_arguments() {
    local validation_failed=false

    # Validate required arguments
    if [ -z "$MODE" ]; then
        log_error "Mode is required. Use --mode <initial|update|cleanup|rollback|resume>"
        validation_failed=true
    fi

    if [ -z "$ENVIRONMENT" ]; then
        log_error "Environment is required. Use --environment <development|staging|production>"
        validation_failed=true
    fi

    if [ -z "$PROJECT_NAME" ]; then
        log_error "Project name is required. Use --project-name <name>"
        validation_failed=true
    fi

    # Validate mode values
    case "$MODE" in
        initial|update|cleanup|rollback|resume)
            ;;
        *)
            log_error "Invalid mode: $MODE. Valid modes: initial, update, cleanup, rollback, resume"
            validation_failed=true
            ;;
    esac

    # Validate environment values
    case "$ENVIRONMENT" in
        development|staging|production)
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT. Valid environments: development, staging, production"
            validation_failed=true
            ;;
    esac

    # Validate config file if specified
    if [ -n "$CONFIG_FILE" ] && [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        validation_failed=true
    fi

    if [ "$validation_failed" = true ]; then
        echo ""
        show_usage
        exit 1
    fi
}

# Function to set default values
set_defaults() {
    # Set default values for optional parameters
    ENVIRONMENT=${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}
    LOG_LEVEL=${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}
    AWS_REGION=${AWS_REGION:-$DEFAULT_AWS_REGION}

    # Set log level
    set_log_level "$LOG_LEVEL"

    # Set AWS region environment variable
    export AWS_DEFAULT_REGION="$AWS_REGION"

    log_debug "Configuration set:"
    log_debug "  Mode: $MODE"
    log_debug "  Environment: $ENVIRONMENT"
    log_debug "  Project Name: $PROJECT_NAME"
    log_debug "  AWS Profile: ${AWS_PROFILE:-'default'}"
    log_debug "  AWS Region: $AWS_REGION"
    log_debug "  Log Level: $LOG_LEVEL"
    log_debug "  Dry Run: $DRY_RUN"
    log_debug "  Force: $FORCE"
}

# Function to validate prerequisites
validate_prerequisites() {
    if [ "$SKIP_VALIDATION" = true ]; then
        log_warn "Skipping AWS CLI validation (--skip-validation flag used)"
        return 0
    fi

    log_info "Validating prerequisites..."

    # Validate AWS CLI
    if ! validate_aws_cli "$AWS_PROFILE"; then
        set_error_context "Prerequisites validation"
        set_error_remediation "Fix AWS CLI configuration issues above"
        handle_error $ERROR_CODE_AWS_CLI "AWS CLI validation failed" true
    fi

    # Check .NET SDK
    if ! command -v dotnet &> /dev/null; then
        log_warn ".NET SDK not found. Required for Lambda deployment."
        log_warn "Install from: https://dotnet.microsoft.com/download"
    else
        local dotnet_version=$(dotnet --version 2>/dev/null)
        log_success ".NET SDK found - Version: $dotnet_version"
    fi

    # Check Entity Framework CLI
    if ! dotnet tool list -g | grep -q "dotnet-ef"; then
        log_warn "Entity Framework CLI tools not found. Required for database migrations."
        log_warn "Install with: dotnet tool install --global dotnet-ef"
    else
        log_success "Entity Framework CLI tools found"
    fi

    log_success "Prerequisites validation completed"
}

# Function to check existing infrastructure using the infrastructure detection script
check_existing_infrastructure() {
    log_info "Checking existing infrastructure using detection script..."

    local check_script="$SCRIPT_DIR/utilities/check-infrastructure.sh"
    
    # If SCRIPT_DIR ends with utilities, adjust the path
    if [[ "$SCRIPT_DIR" == */utilities ]]; then
        check_script="$SCRIPT_DIR/check-infrastructure.sh"
    fi
    
    # Verify the infrastructure detection script exists
    if [ ! -f "$check_script" ]; then
        log_error "Infrastructure detection script not found: $check_script"
        return 1
    fi

    # Build command with appropriate options
    local check_cmd="$check_script --environment $ENVIRONMENT --output-format summary"
    
    if [ -n "$AWS_PROFILE" ]; then
        check_cmd="$check_cmd --aws-profile $AWS_PROFILE"
    fi
    
    if [ -n "$AWS_REGION" ]; then
        check_cmd="$check_cmd --aws-region $AWS_REGION"
    fi
    
    # Add log level if debug is enabled
    if [ "$LOG_LEVEL" = "DEBUG" ]; then
        check_cmd="$check_cmd --log-level DEBUG"
    fi

    log_debug "Running infrastructure check: $check_cmd"

    # Execute the infrastructure detection script
    local check_result
    if check_result=$($check_cmd 2>&1); then
        local exit_code=$?
        
        case "$check_result" in
            "EXISTS")
                log_info "Existing infrastructure detected for environment: $ENVIRONMENT"
                
                # Get detailed information if verbose logging is enabled
                if [ "$LOG_LEVEL" = "DEBUG" ] || [ "$VERBOSE" = true ]; then
                    log_debug "Getting detailed infrastructure information..."
                    local detailed_cmd="${check_cmd/--output-format summary/--output-format text}"
                    $detailed_cmd 2>/dev/null || true
                fi
                
                return 0
                ;;
            "NOT_FOUND")
                log_info "No existing infrastructure found for environment: $ENVIRONMENT"
                return 1
                ;;
            *)
                log_warn "Unexpected infrastructure check result: $check_result"
                return 1
                ;;
        esac
    else
        local exit_code=$?
        log_error "Infrastructure detection script failed with exit code: $exit_code"
        log_error "Output: $check_result"
        
        # Handle specific exit codes from the infrastructure detection script
        case $exit_code in
            1)
                log_info "No infrastructure found (confirmed by detection script)"
                return 1
                ;;
            2)
                log_warn "Infrastructure found but has health issues"
                log_warn "Proceeding with caution - some resources may be unhealthy"
                return 0
                ;;
            3)
                log_error "AWS CLI or permission errors detected"
                set_error_context "Infrastructure detection - AWS CLI validation"
                set_error_remediation "Check AWS CLI configuration and permissions"
                handle_error $ERROR_CODE_AWS_CLI "Infrastructure detection failed due to AWS CLI issues" true
                ;;
            4)
                log_error "Invalid arguments passed to infrastructure detection script"
                set_error_context "Infrastructure detection - argument validation"
                set_error_remediation "Check deployment script configuration"
                handle_error $ERROR_CODE_VALIDATION "Infrastructure detection script argument error" true
                ;;
            *)
                log_error "Unknown error from infrastructure detection script"
                return 1
                ;;
        esac
    fi
}

# Function to validate deployment mode against infrastructure state
validate_deployment_mode() {
    log_info "Validating deployment mode '$MODE' against infrastructure state..."

    case "$MODE" in
        initial)
            # For initial deployment, check if infrastructure already exists
            if check_existing_infrastructure; then
                log_warn "Infrastructure already exists for environment '$ENVIRONMENT'"
                log_warn "Initial deployment will recreate all resources"
                
                # This will trigger confirmation prompt in execute_initial_deployment
                return 0
            else
                log_info "No existing infrastructure found - initial deployment is appropriate"
                return 0
            fi
            ;;
        update)
            # For update deployment, infrastructure must exist
            if ! check_existing_infrastructure; then
                log_error "Update deployment requested but no infrastructure exists for environment '$ENVIRONMENT'"
                log_error ""
                log_error "RESOLUTION STEPS:"
                log_error "1. Run initial deployment first:"
                log_error "   $0 --mode initial --environment $ENVIRONMENT"
                log_error ""
                log_error "2. Or check if you're using the correct environment name"
                log_error "   Available environments: development, staging, production"
                log_error ""
                log_error "3. Verify AWS region and profile settings:"
                log_error "   Current region: $AWS_REGION"
                log_error "   Current profile: ${AWS_PROFILE:-'default'}"
                
                set_error_context "Update deployment validation"
                set_error_remediation "Run initial deployment or verify environment/AWS settings"
                handle_error $ERROR_CODE_INFRASTRUCTURE "No infrastructure exists for update deployment" true
            else
                log_success "Infrastructure exists - update deployment is valid"
                return 0
            fi
            ;;
        cleanup)
            # For cleanup, warn if no infrastructure exists but don't fail
            if ! check_existing_infrastructure; then
                log_warn "No infrastructure found for environment '$ENVIRONMENT'"
                log_info "Nothing to clean up - this is not an error"
                return 0
            else
                log_info "Infrastructure exists - cleanup deployment is valid"
                return 0
            fi
            ;;
        *)
            log_error "Invalid deployment mode: $MODE"
            log_error "Valid modes: initial, update, cleanup"
            set_error_context "Deployment mode validation"
            set_error_remediation "Use a valid deployment mode: initial, update, or cleanup"
            handle_error $ERROR_CODE_VALIDATION "Invalid deployment mode specified" true
            ;;
    esac
}

# Function to confirm destructive operations with enhanced prompts
confirm_operation() {
    local operation="$1"
    local message="$2"
    local additional_info="${3:-}"

    if [ "$FORCE" = true ]; then
        log_info "Skipping confirmation (--force flag used)"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would confirm: $operation"
        return 0
    fi

    echo ""
    echo "========================================"
    echo "CONFIRMATION REQUIRED"
    echo "========================================"
    echo "Operation: $operation"
    echo "Environment: $ENVIRONMENT"
    echo "AWS Region: $AWS_REGION"
    echo "AWS Profile: ${AWS_PROFILE:-'default'}"
    echo ""
    log_warn "$message"
    
    if [ -n "$additional_info" ]; then
        echo ""
        echo "$additional_info"
    fi
    
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    # Enhanced confirmation with multiple prompts for critical operations
    if [[ "$operation" == *"Recreation"* ]] || [[ "$operation" == *"Cleanup"* ]]; then
        echo "Type 'yes' to confirm, or anything else to cancel:"
        read -p "> " -r
        echo ""

        case "$REPLY" in
            yes)
                # Double confirmation for destructive operations
                echo "Are you absolutely sure? This will permanently affect your $ENVIRONMENT environment."
                echo "Type 'CONFIRM' to proceed:"
                read -p "> " -r
                echo ""
                
                case "$REPLY" in
                    CONFIRM)
                        log_info "Operation confirmed by user with double confirmation"
                        return 0
                        ;;
                    *)
                        log_info "Operation cancelled - second confirmation not provided"
                        exit 0
                        ;;
                esac
                ;;
            *)
                log_info "Operation cancelled by user"
                exit 0
                ;;
        esac
    else
        # Standard confirmation for less destructive operations
        echo "Type 'yes' to continue, or anything else to cancel:"
        read -p "> " -r
        echo ""

        case "$REPLY" in
            yes|YES|y|Y)
                log_info "Operation confirmed by user"
                return 0
                ;;
            *)
                log_info "Operation cancelled by user"
                exit 0
                ;;
        esac
    fi
}

# Function to delegate to full deployment orchestrator
delegate_to_orchestrator() {
    local mode="$1"
    
    log_info "Delegating to full deployment orchestrator for mode: $mode"
    
    # Path to the full deployment orchestrator
    # Handle case where SCRIPT_DIR might be pointing to utilities subdirectory
    local orchestrator_script
    if [[ "$SCRIPT_DIR" == */utilities ]]; then
        orchestrator_script="${SCRIPT_DIR%/utilities}/integration/full-deployment-orchestrator.sh"
    else
        orchestrator_script="$SCRIPT_DIR/integration/full-deployment-orchestrator.sh"
    fi
    
    # Verify orchestrator script exists
    if [ ! -f "$orchestrator_script" ]; then
        log_error "Full deployment orchestrator not found: $orchestrator_script"
        handle_error $ERROR_CODE_DEPLOYMENT "Orchestrator script missing" true
    fi
    
    # Build orchestrator command arguments
    local orchestrator_args="--mode $mode --environment $ENVIRONMENT --project-name $PROJECT_NAME"
    
    # Add optional parameters
    if [ -n "$AWS_PROFILE" ]; then
        orchestrator_args="$orchestrator_args --aws-profile $AWS_PROFILE"
    fi
    
    if [ -n "$AWS_REGION" ]; then
        orchestrator_args="$orchestrator_args --region $AWS_REGION"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        orchestrator_args="$orchestrator_args --dry-run"
    fi
    
    if [ "$SKIP_VALIDATION" = true ]; then
        orchestrator_args="$orchestrator_args --skip-validation"
    fi
    
    if [ "$FORCE" = true ]; then
        orchestrator_args="$orchestrator_args --force-cleanup"
    fi
    
    # Add checkpoint and rollback scope for resume/rollback modes
    if [ -n "$CHECKPOINT_NAME" ]; then
        orchestrator_args="$orchestrator_args --resume-from $CHECKPOINT_NAME"
    fi
    
    log_debug "Executing orchestrator: $orchestrator_script $orchestrator_args"
    
    # Execute the full deployment orchestrator
    if bash "$orchestrator_script" $orchestrator_args; then
        log_success "Full deployment orchestrator completed successfully"
        return 0
    else
        local exit_code=$?
        log_error "Full deployment orchestrator failed with exit code: $exit_code"
        handle_error $ERROR_CODE_DEPLOYMENT "Orchestrator execution failed" true
    fi
}

# Function to execute initial deployment
execute_initial_deployment() {
    log_info "Starting initial deployment for environment: $ENVIRONMENT"
    
    # Delegate to full deployment orchestrator
    delegate_to_orchestrator "initial"
}

# Function to execute update deployment
execute_update_deployment() {
    log_info "Starting update deployment for environment: $ENVIRONMENT"
    
    # Delegate to full deployment orchestrator
    delegate_to_orchestrator "update"
}

# Function to execute cleanup deployment
execute_cleanup_deployment() {
    log_info "Starting cleanup for environment: $ENVIRONMENT"
    
    # Delegate to full deployment orchestrator
    delegate_to_orchestrator "cleanup"
}

# Function to execute rollback deployment
execute_rollback_deployment() {
    log_info "Starting rollback for environment: $ENVIRONMENT"
    
    # Initialize error logging
    initialize_error_logging
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would execute rollback with the following steps:"
        log_info "[DRY RUN]   1. Analyze deployment state and errors"
        log_info "[DRY RUN]   2. Determine rollback actions based on failure type"
        log_info "[DRY RUN]   3. Execute rollback procedures"
        log_info "[DRY RUN]   4. Generate rollback report"
        return 0
    fi
    
    # Set error context for rollback
    set_error_context "Rollback deployment for environment: $ENVIRONMENT"
    set_error_remediation "Check deployment state and error logs"
    
    # Prepare rollback script arguments
    local rollback_args="--environment $ENVIRONMENT"
    
    if [ -n "$AWS_PROFILE" ]; then
        rollback_args="$rollback_args --aws-profile $AWS_PROFILE"
    fi
    
    if [ -n "$ROLLBACK_SCOPE" ]; then
        rollback_args="$rollback_args --scope $ROLLBACK_SCOPE"
    fi
    
    if [ -n "$CHECKPOINT_NAME" ]; then
        rollback_args="$rollback_args --checkpoint $CHECKPOINT_NAME"
    fi
    
    if [ "$FORCE" = true ]; then
        rollback_args="$rollback_args --force"
    fi
    
    # Execute rollback script
    local rollback_script="$SCRIPT_DIR/utilities/rollback-deployment.sh"
    
    log_info "Executing rollback script: $rollback_script"
    
    if bash "$rollback_script" $rollback_args; then
        log_success "Rollback completed successfully for environment: $ENVIRONMENT"
    else
        handle_error $ERROR_CODE_ROLLBACK "Rollback failed for environment: $ENVIRONMENT" true
    fi
}

# Function to execute resume deployment
execute_resume_deployment() {
    log_info "Starting resume deployment for environment: $ENVIRONMENT"
    
    # Initialize error logging
    initialize_error_logging
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would execute resume with the following steps:"
        log_info "[DRY RUN]   1. Detect last successful checkpoint"
        log_info "[DRY RUN]   2. Validate existing infrastructure state"
        log_info "[DRY RUN]   3. Determine remaining deployment actions"
        log_info "[DRY RUN]   4. Execute remaining deployment steps"
        return 0
    fi
    
    # Set error context for resume
    set_error_context "Resume deployment for environment: $ENVIRONMENT"
    set_error_remediation "Check checkpoint availability and deployment state"
    
    # For resume, we delegate to the orchestrator with resume-from parameter
    # The orchestrator will handle checkpoint detection and resume logic
    local resume_mode="initial"  # Default to initial mode for resume
    
    # If checkpoint is specified, use it; otherwise let orchestrator detect
    if [ -n "$CHECKPOINT_NAME" ]; then
        log_info "Resuming from specified checkpoint: $CHECKPOINT_NAME"
    else
        log_info "Orchestrator will detect last successful checkpoint"
    fi
    
    # Delegate to orchestrator with resume functionality
    delegate_to_orchestrator "$resume_mode"
}

# Function to execute deployment based on mode
execute_deployment() {
    case "$MODE" in
        initial)
            execute_initial_deployment
            ;;
        update)
            execute_update_deployment
            ;;
        cleanup)
            execute_cleanup_deployment
            ;;
        rollback)
            execute_rollback_deployment
            ;;
        resume)
            execute_resume_deployment
            ;;
        *)
            handle_error $ERROR_CODE_VALIDATION "Invalid deployment mode: $MODE" true
            ;;
    esac
}

# Function to display deployment summary
show_deployment_summary() {
    echo ""
    echo "========================================"
    echo "Deployment Summary"
    echo "========================================"
    echo "Mode: $MODE"
    echo "Environment: $ENVIRONMENT"
    echo "Project Name: $PROJECT_NAME"
    echo "AWS Profile: ${AWS_PROFILE:-'default'}"
    echo "AWS Region: $AWS_REGION"
    echo "Dry Run: $DRY_RUN"
    echo ""
    
    if [ "$DRY_RUN" = false ]; then
        echo "Log file: $LOG_FILE"
        echo "Error log: ${LOG_FILE%.log}_errors.log"
        echo ""
    fi
    
    echo "For troubleshooting, see: $SCRIPT_DIR/README.md"
    echo "========================================"
}

# Main execution function
main() {
    # Set up error handling
    set_error_context "Master deployment script initialization"
    
    # Show header
    show_header
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Handle list checkpoints option early
    if [ "$LIST_CHECKPOINTS" = true ]; then
        local checkpoint_dir="./deployment_checkpoints"
        if [ ! -d "$checkpoint_dir" ]; then
            log_warn "No checkpoint directory found"
            exit 0
        fi
        
        local checkpoints=($(ls "$checkpoint_dir"/*.checkpoint 2>/dev/null | sort || echo ""))
        
        if [ ${#checkpoints[@]} -eq 0 ]; then
            log_warn "No checkpoints found"
            exit 0
        fi
        
        echo "Available deployment checkpoints:"
        for checkpoint_file in "${checkpoints[@]}"; do
            local checkpoint_name=$(basename "$checkpoint_file" .checkpoint)
            local checkpoint_time=$(cat "$checkpoint_file" 2>/dev/null || echo "unknown")
            echo "  - $checkpoint_name (created: $checkpoint_time)"
        done
        exit 0
    fi
    
    # Validate arguments
    validate_arguments
    
    # Set default values
    set_defaults
    
    # Set up logging
    mkdir -p "./logs"
    local log_file="./logs/deployment_${ENVIRONMENT}_$(date +%Y%m%d_%H%M%S).log"
    set_log_file "$log_file"
    
    log_info "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    log_info "Mode: $MODE, Environment: $ENVIRONMENT"
    
    # Validate prerequisites
    validate_prerequisites
    
    # Execute deployment
    execute_deployment
    
    # Show summary
    show_deployment_summary
    
    log_success "Deployment script completed successfully"
}

# Execute main function with all arguments
main "$@"