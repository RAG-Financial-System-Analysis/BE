#!/bin/bash

# Deployment Rollback Script
# Provides rollback capabilities for failed infrastructure provisioning
# Implements partial deployment recovery and resume-from-checkpoint functionality
# Handles rollback of Lambda deployments, RDS configurations, and IAM changes

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/error-handling.sh"
source "$SCRIPT_DIR/validate-aws-cli.sh"

# Configuration variables
ENVIRONMENT="${ENVIRONMENT:-dev}"
PROJECT_NAME="${PROJECT_NAME:-myapp}"
ROLLBACK_SCOPE="${ROLLBACK_SCOPE:-all}"  # all, lambda, rds, iam, partial
CHECKPOINT_NAME="${CHECKPOINT_NAME:-}"
FORCE_ROLLBACK="${FORCE_ROLLBACK:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Global variables for rollback tracking
ROLLBACK_ACTIONS=()
ROLLBACK_ERRORS=()
DEPLOYMENT_STATE=""

# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Provides rollback capabilities for failed AWS deployments.

OPTIONS:
    --environment ENV          Environment name (default: dev)
    --project-name NAME        Project name (default: myapp)
    --aws-profile PROFILE      AWS profile to use
    --scope SCOPE              Rollback scope: all, lambda, rds, iam, partial (default: all)
    --checkpoint NAME          Specific checkpoint to rollback to
    --force                    Skip confirmation prompts
    --dry-run                  Show what would be rolled back without executing
    --list-checkpoints         List available checkpoints
    --help                     Show this help message

EXAMPLES:
    $0 --scope lambda --environment production
    $0 --checkpoint infrastructure_provisioned --force
    $0 --list-checkpoints
    $0 --dry-run --scope partial

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
            --aws-profile)
                export AWS_PROFILE="$2"
                shift 2
                ;;
            --scope)
                ROLLBACK_SCOPE="$2"
                shift 2
                ;;
            --checkpoint)
                CHECKPOINT_NAME="$2"
                shift 2
                ;;
            --force)
                FORCE_ROLLBACK="true"
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
    
    local checkpoints=($(ls "$checkpoint_dir"/*.checkpoint 2>/dev/null | sort -r || echo ""))
    
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
# Function to get current deployment state
get_current_deployment_state() {
    if [ -f "$DEPLOYMENT_STATE_FILE" ]; then
        DEPLOYMENT_STATE=$(cat "$DEPLOYMENT_STATE_FILE")
        log_debug "Current deployment state: $DEPLOYMENT_STATE"
    else
        log_warn "No deployment state file found"
        DEPLOYMENT_STATE="{\"state\": \"unknown\"}"
    fi
}

# Function to validate rollback scope
validate_rollback_scope() {
    case "$ROLLBACK_SCOPE" in
        all|lambda|rds|iam|partial)
            log_info "Rollback scope: $ROLLBACK_SCOPE"
            ;;
        *)
            set_error_context "Rollback scope validation"
            set_error_remediation "Use a valid rollback scope: all, lambda, rds, iam, partial"
            handle_error $ERROR_CODE_VALIDATION "Invalid rollback scope: $ROLLBACK_SCOPE" true
            ;;
    esac
}

# Function to determine rollback actions based on deployment state
determine_rollback_actions() {
    log_info "Determining rollback actions..."
    
    get_current_deployment_state
    
    # Parse deployment state to determine what needs rollback
    local state=$(echo "$DEPLOYMENT_STATE" | grep -o '"state":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
    local error_code=$(echo "$DEPLOYMENT_STATE" | grep -o '"error_code":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
    
    log_info "Current deployment state: $state"
    
    case "$state" in
        "error")
            log_info "Deployment failed - determining rollback actions based on error"
            case "$error_code" in
                "$ERROR_CODE_LAMBDA"|"$ERROR_CODE_DEPLOYMENT")
                    ROLLBACK_ACTIONS+=("rollback_lambda_deployment")
                    ;;
                "$ERROR_CODE_DATABASE"|"$ERROR_CODE_MIGRATION")
                    ROLLBACK_ACTIONS+=("rollback_database_changes")
                    ;;
                "$ERROR_CODE_INFRASTRUCTURE")
                    ROLLBACK_ACTIONS+=("cleanup_partial_infrastructure")
                    ;;
                "$ERROR_CODE_CONFIGURATION")
                    ROLLBACK_ACTIONS+=("restore_configuration")
                    ;;
                *)
                    ROLLBACK_ACTIONS+=("cleanup_partial_infrastructure")
                    ROLLBACK_ACTIONS+=("rollback_lambda_deployment")
                    ;;
            esac
            ;;
        "partial")
            log_info "Partial deployment detected - adding cleanup actions"
            ROLLBACK_ACTIONS+=("cleanup_partial_infrastructure")
            ;;
        "unknown")
            log_warn "Unknown deployment state - using scope-based rollback"
            case "$ROLLBACK_SCOPE" in
                "all")
                    ROLLBACK_ACTIONS+=("cleanup_partial_infrastructure")
                    ROLLBACK_ACTIONS+=("rollback_lambda_deployment")
                    ROLLBACK_ACTIONS+=("rollback_database_changes")
                    ;;
                "lambda")
                    ROLLBACK_ACTIONS+=("rollback_lambda_deployment")
                    ;;
                "rds")
                    ROLLBACK_ACTIONS+=("rollback_database_changes")
                    ;;
                "iam")
                    ROLLBACK_ACTIONS+=("cleanup_iam_resources")
                    ;;
                "partial")
                    ROLLBACK_ACTIONS+=("cleanup_partial_infrastructure")
                    ;;
            esac
            ;;
        *)
            log_info "Deployment state: $state - using scope-based rollback"
            ;;
    esac
    
    # Add checkpoint-specific actions if specified
    if [ -n "$CHECKPOINT_NAME" ]; then
        ROLLBACK_ACTIONS=("restore_from_checkpoint")
    fi
    
    log_info "Rollback actions determined: ${ROLLBACK_ACTIONS[*]}"
}

# Function to rollback Lambda deployment
rollback_lambda_deployment() {
    log_info "Rolling back Lambda deployment..."
    
    local function_name="$PROJECT_NAME-$ENVIRONMENT-api"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would rollback Lambda function: $function_name"
        return 0
    fi
    
    set_error_context "Lambda deployment rollback"
    set_error_remediation "Check Lambda function status and previous versions"
    
    # Check if function exists
    if ! aws lambda get-function --function-name "$function_name" &>/dev/null; then
        log_warn "Lambda function not found: $function_name"
        return 0
    fi
    
    # Get function versions
    local versions=$(aws lambda list-versions-by-function --function-name "$function_name" --query "Versions[?Version!='\$LATEST'].Version" --output text 2>/dev/null || echo "")
    
    if [ -z "$versions" ]; then
        log_warn "No previous versions found for Lambda function: $function_name"
        log_info "Consider deleting the function if it's not working correctly"
        return 0
    fi
    
    # Get the second-to-last version (previous working version)
    local version_array=($versions)
    local previous_version=""
    
    if [ ${#version_array[@]} -gt 1 ]; then
        previous_version="${version_array[-2]}"  # Second to last
    elif [ ${#version_array[@]} -eq 1 ]; then
        previous_version="${version_array[0]}"
    fi
    
    if [ -n "$previous_version" ]; then
        log_info "Rolling back Lambda function to version: $previous_version"
        
        # Update alias to point to previous version
        if aws lambda update-alias \
            --function-name "$function_name" \
            --name "LIVE" \
            --function-version "$previous_version" 2>/dev/null; then
            
            log_success "Lambda function rolled back to version: $previous_version"
        else
            # If alias doesn't exist, create it
            if aws lambda create-alias \
                --function-name "$function_name" \
                --name "LIVE" \
                --function-version "$previous_version" 2>/dev/null; then
                
                log_success "Lambda alias created pointing to version: $previous_version"
            else
                log_error "Failed to rollback Lambda function"
                ROLLBACK_ERRORS+=("lambda_rollback_failed")
            fi
        fi
    else
        log_warn "No suitable previous version found for rollback"
    fi
}
# Function to rollback database changes
rollback_database_changes() {
    log_info "Rolling back database changes..."
    
    local db_identifier="$PROJECT_NAME-$ENVIRONMENT-db"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would rollback database changes for: $db_identifier"
        return 0
    fi
    
    set_error_context "Database rollback"
    set_error_remediation "Check RDS instance status and available snapshots"
    
    # Check if RDS instance exists
    if ! aws rds describe-db-instances --db-instance-identifier "$db_identifier" &>/dev/null; then
        log_warn "RDS instance not found: $db_identifier"
        return 0
    fi
    
    # Look for recent automated snapshots
    local snapshots=$(aws rds describe-db-snapshots \
        --db-instance-identifier "$db_identifier" \
        --snapshot-type "automated" \
        --query "DBSnapshots[?Status=='available']|sort_by(@, &SnapshotCreateTime)|[-1].DBSnapshotIdentifier" \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$snapshots" == "None" || "$snapshots" == "null" ]]; then
        log_warn "No automated snapshots found for RDS instance: $db_identifier"
        log_info "Consider running database migration rollback scripts instead"
        
        # Try to run migration rollback script
        local migration_rollback_script="$SCRIPT_DIR/../migration/rollback-migrations.sh"
        if [ -f "$migration_rollback_script" ]; then
            log_info "Running migration rollback script..."
            if bash "$migration_rollback_script"; then
                log_success "Database migrations rolled back successfully"
            else
                log_error "Migration rollback failed"
                ROLLBACK_ERRORS+=("migration_rollback_failed")
            fi
        fi
        return 0
    fi
    
    log_warn "Database rollback from snapshot requires manual intervention"
    log_info "Available snapshot: $snapshots"
    log_info "To restore from snapshot, use:"
    log_info "  aws rds restore-db-instance-from-db-snapshot \\"
    log_info "    --db-instance-identifier $db_identifier-restored \\"
    log_info "    --db-snapshot-identifier $snapshots"
    
    ROLLBACK_ERRORS+=("database_rollback_manual_required")
}

# Function to cleanup partial infrastructure
cleanup_partial_infrastructure() {
    log_info "Cleaning up partial infrastructure..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would cleanup partial infrastructure"
        return 0
    fi
    
    set_error_context "Partial infrastructure cleanup"
    set_error_remediation "Check for partially created AWS resources"
    
    # Use the cleanup infrastructure script
    local cleanup_script="$SCRIPT_DIR/../infrastructure/cleanup-infrastructure.sh"
    if [ -f "$cleanup_script" ]; then
        log_info "Running infrastructure cleanup script..."
        
        # Run cleanup with force flag to avoid prompts
        if bash "$cleanup_script" \
            --environment "$ENVIRONMENT" \
            --project-name "$PROJECT_NAME" \
            --force; then
            
            log_success "Partial infrastructure cleaned up successfully"
        else
            log_error "Infrastructure cleanup failed"
            ROLLBACK_ERRORS+=("infrastructure_cleanup_failed")
        fi
    else
        log_error "Cleanup script not found: $cleanup_script"
        ROLLBACK_ERRORS+=("cleanup_script_missing")
    fi
}

# Function to restore from checkpoint
restore_from_checkpoint() {
    log_info "Restoring from checkpoint: $CHECKPOINT_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restore from checkpoint: $CHECKPOINT_NAME"
        return 0
    fi
    
    set_error_context "Checkpoint restoration"
    set_error_remediation "Check checkpoint availability and validity"
    
    local checkpoint_data=$(restore_checkpoint "$CHECKPOINT_NAME")
    local restore_exit_code=$?
    
    if [ $restore_exit_code -eq 0 ]; then
        log_info "Checkpoint data: $checkpoint_data"
        log_success "Checkpoint restored: $CHECKPOINT_NAME"
        
        # Parse checkpoint data and determine next steps
        case "$CHECKPOINT_NAME" in
            "infrastructure_start")
                log_info "Restoring to infrastructure start - cleaning up any partial resources"
                cleanup_partial_infrastructure
                ;;
            "rds_provisioned")
                log_info "Restoring to RDS provisioned state - cleaning up Lambda and IAM resources"
                # Cleanup Lambda and IAM but keep RDS
                ;;
            "lambda_provisioned")
                log_info "Restoring to Lambda provisioned state - rolling back deployment"
                rollback_lambda_deployment
                ;;
            *)
                log_info "Unknown checkpoint - performing general rollback"
                cleanup_partial_infrastructure
                ;;
        esac
    else
        log_error "Failed to restore checkpoint: $CHECKPOINT_NAME"
        ROLLBACK_ERRORS+=("checkpoint_restore_failed")
    fi
}

# Function to restore configuration
restore_configuration() {
    log_info "Restoring configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would restore configuration"
        return 0
    fi
    
    set_error_context "Configuration restoration"
    set_error_remediation "Check configuration backup availability"
    
    # Look for configuration backups
    local config_backup_dir="./config_backups"
    if [ -d "$config_backup_dir" ]; then
        local latest_backup=$(ls -t "$config_backup_dir"/*.json 2>/dev/null | head -1 || echo "")
        
        if [ -n "$latest_backup" ]; then
            log_info "Found configuration backup: $latest_backup"
            log_info "Manual restoration required - backup location: $latest_backup"
        else
            log_warn "No configuration backups found"
        fi
    else
        log_warn "No configuration backup directory found"
    fi
    
    ROLLBACK_ERRORS+=("configuration_restore_manual_required")
}
# Function to confirm rollback operation
confirm_rollback() {
    if [[ "$FORCE_ROLLBACK" == "true" ]]; then
        log_info "Force rollback enabled - skipping confirmation"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run mode - no actual rollback will be performed"
        return 0
    fi
    
    echo ""
    log_warn "WARNING: This will rollback the following deployment components:"
    echo ""
    
    for action in "${ROLLBACK_ACTIONS[@]}"; do
        case "$action" in
            "rollback_lambda_deployment")
                echo "  - Lambda function deployment (restore previous version)"
                ;;
            "rollback_database_changes")
                echo "  - Database changes (run migration rollback or restore from snapshot)"
                ;;
            "cleanup_partial_infrastructure")
                echo "  - Partial infrastructure (delete incomplete AWS resources)"
                ;;
            "restore_from_checkpoint")
                echo "  - Restore from checkpoint: $CHECKPOINT_NAME"
                ;;
            "restore_configuration")
                echo "  - Configuration settings (restore from backup)"
                ;;
            *)
                echo "  - $action"
                ;;
        esac
    done
    
    echo ""
    log_warn "This action may result in data loss or service interruption!"
    echo ""
    
    read -p "Are you sure you want to proceed with rollback? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Rollback cancelled by user"
        exit 0
    fi
    
    log_info "Rollback confirmed by user"
}

# Function to execute rollback actions
execute_rollback() {
    log_info "Executing rollback actions..."
    
    # Initialize error logging
    initialize_error_logging
    
    # Create rollback checkpoint
    create_checkpoint "rollback_start" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    for action in "${ROLLBACK_ACTIONS[@]}"; do
        log_info "Executing rollback action: $action"
        
        case "$action" in
            "rollback_lambda_deployment")
                rollback_lambda_deployment
                ;;
            "rollback_database_changes")
                rollback_database_changes
                ;;
            "cleanup_partial_infrastructure")
                cleanup_partial_infrastructure
                ;;
            "restore_from_checkpoint")
                restore_from_checkpoint
                ;;
            "restore_configuration")
                restore_configuration
                ;;
            *)
                log_warn "Unknown rollback action: $action"
                ROLLBACK_ERRORS+=("unknown_action:$action")
                ;;
        esac
    done
    
    # Create completion checkpoint
    create_checkpoint "rollback_complete" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# Function to generate rollback report
generate_rollback_report() {
    log_info "Generating rollback report..."
    
    local total_actions=${#ROLLBACK_ACTIONS[@]}
    local failed_actions=${#ROLLBACK_ERRORS[@]}
    local successful_actions=$((total_actions - failed_actions))
    
    echo ""
    log_info "=== ROLLBACK REPORT ==="
    log_info "Total rollback actions: $total_actions"
    log_info "Successful actions: $successful_actions"
    log_info "Failed actions: $failed_actions"
    
    if [ ${#ROLLBACK_ERRORS[@]} -gt 0 ]; then
        echo ""
        log_error "Failed rollback actions:"
        for error in "${ROLLBACK_ERRORS[@]}"; do
            echo "  ✗ $error"
        done
        echo ""
        log_warn "Some rollback actions may require manual intervention"
        log_info "Check the error log for details: $ERROR_LOG_FILE"
    fi
    
    echo ""
    
    if [ $failed_actions -eq 0 ]; then
        log_success "Rollback completed successfully!"
        log_info "You can now retry the deployment or investigate the original issue"
        return 0
    else
        log_error "Rollback completed with errors"
        log_info "Manual intervention may be required for complete recovery"
        return 1
    fi
}

# Main execution function
main() {
    log_info "Starting Deployment Rollback"
    log_info "Project: $PROJECT_NAME, Environment: $ENVIRONMENT"
    
    # Initialize error handling
    set_error_context "Deployment rollback initialization"
    set_error_remediation "Check script parameters and AWS configuration"
    
    # Validate AWS CLI
    if ! validate_aws_cli; then
        handle_error $ERROR_CODE_AWS_CLI "AWS CLI validation failed" true
    fi
    
    # Validate rollback scope
    validate_rollback_scope
    
    # Determine rollback actions
    determine_rollback_actions
    
    if [ ${#ROLLBACK_ACTIONS[@]} -eq 0 ]; then
        log_info "No rollback actions determined"
        log_success "Nothing to rollback - deployment may be in a clean state"
        exit 0
    fi
    
    # Confirm rollback operation
    confirm_rollback
    
    # Execute rollback
    execute_rollback
    
    # Generate report
    if generate_rollback_report; then
        exit 0
    else
        exit $ERROR_CODE_ROLLBACK
    fi
}

# Register cleanup function for error handling
register_cleanup_function cleanup_checkpoints

# Parse command line arguments
parse_arguments "$@"

# Execute main function
main