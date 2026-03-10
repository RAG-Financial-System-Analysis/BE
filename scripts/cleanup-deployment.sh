#!/bin/bash

# Deployment Cleanup Script
# Cleans up temporary files, logs, and deployment artifacts
# Can also destroy AWS resources if requested

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILITIES_DIR="$SCRIPT_DIR/utilities"
source "$UTILITIES_DIR/logging.sh"
source "$UTILITIES_DIR/error-handling.sh"

# Configuration
CLEAN_LOGS="${CLEAN_LOGS:-false}"
CLEAN_TEMP="${CLEAN_TEMP:-true}"
CLEAN_CHECKPOINTS="${CLEAN_CHECKPOINTS:-false}"
DESTROY_AWS="${DESTROY_AWS:-false}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
PROJECT_NAME="${PROJECT_NAME:-myragapp}"

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Cleans up deployment artifacts and optionally destroys AWS resources.

OPTIONS:
    --clean-logs              Clean deployment logs
    --clean-temp              Clean temporary files (default: true)
    --clean-checkpoints       Clean deployment checkpoints
    --destroy-aws             Destroy AWS resources (DANGEROUS!)
    --environment ENV         Environment name (default: dev)
    --project-name NAME       Project name (default: myapp)
    --all                     Clean everything except AWS resources
    --help                    Show this help message

CLEANUP CATEGORIES:
    📁 Temporary Files:       JSON files, test events, build artifacts
    📋 Logs:                  Deployment logs, error logs
    🔖 Checkpoints:           Deployment state files
    ☁️  AWS Resources:        RDS, Lambda, API Gateway (DESTRUCTIVE!)

EXAMPLES:
    # Clean temporary files only (default)
    $0

    # Clean everything except AWS resources
    $0 --all

    # Clean logs and temp files
    $0 --clean-logs --clean-temp

    # DESTROY AWS resources (be careful!)
    $0 --destroy-aws --environment dev

EOF
}

# Parse arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean-logs)
                CLEAN_LOGS=true
                shift
                ;;
            --clean-temp)
                CLEAN_TEMP=true
                shift
                ;;
            --clean-checkpoints)
                CLEAN_CHECKPOINTS=true
                shift
                ;;
            --destroy-aws)
                DESTROY_AWS=true
                shift
                ;;
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --project-name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --all)
                CLEAN_LOGS=true
                CLEAN_TEMP=true
                CLEAN_CHECKPOINTS=true
                shift
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

# Function to clean temporary files
clean_temp_files() {
    if [ "$CLEAN_TEMP" = false ]; then
        return 0
    fi
    
    log_info "📁 Cleaning temporary files..."
    
    local temp_dir="./temp"
    local files_cleaned=0
    
    # Clean temp directory
    if [[ -d "$temp_dir" ]]; then
        local temp_files=$(find "$temp_dir" -type f 2>/dev/null | wc -l)
        if [[ $temp_files -gt 0 ]]; then
            rm -rf "$temp_dir"/*
            files_cleaned=$((files_cleaned + temp_files))
            log_info "Cleaned $temp_files files from temp directory"
        fi
    fi
    
    # Clean scripts/temp directory (new location)
    local scripts_temp_dir="./scripts/temp"
    if [[ -d "$scripts_temp_dir" ]]; then
        local scripts_temp_files=$(find "$scripts_temp_dir" -type f 2>/dev/null | wc -l)
        if [[ $scripts_temp_files -gt 0 ]]; then
            rm -rf "$scripts_temp_dir"/*
            files_cleaned=$((files_cleaned + scripts_temp_files))
            log_info "Cleaned $scripts_temp_files files from scripts/temp directory"
        fi
    fi
    
    # Clean root-level temporary files
    local root_temp_files=(
        "lambda-deployment.zip"
        "response.json"
        "test-event.json"
        "lambda-env-vars.json"
        "lambda-update.json"
        "migration-test-event.json"
        "migration-response.json"
    )
    
    for file in "${root_temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            files_cleaned=$((files_cleaned + 1))
            log_info "Removed $file"
        fi
    done
    
    # Clean build artifacts
    if [[ -d "/tmp/lambda-build" ]]; then
        rm -rf "/tmp/lambda-build"
        log_info "Cleaned Lambda build directory"
    fi
    
    # Clean .NET build artifacts
    find . -name "bin" -type d -path "*/RAG.*" -exec rm -rf {} + 2>/dev/null || true
    find . -name "obj" -type d -path "*/RAG.*" -exec rm -rf {} + 2>/dev/null || true
    
    log_success "Cleaned $files_cleaned temporary files"
}

# Function to clean logs
clean_logs() {
    if [ "$CLEAN_LOGS" = false ]; then
        return 0
    fi
    
    log_info "📋 Cleaning deployment logs..."
    
    local logs_cleaned=0
    
    # Clean logs directory
    if [[ -d "./logs" ]]; then
        local log_files=$(find "./logs" -type f 2>/dev/null | wc -l)
        if [[ $log_files -gt 0 ]]; then
            rm -rf "./logs"/*
            logs_cleaned=$((logs_cleaned + log_files))
            log_info "Cleaned $log_files files from logs directory"
        fi
    fi
    
    # Clean deployment_logs directory
    if [[ -d "./deployment_logs" ]]; then
        local deploy_log_dirs=$(find "./deployment_logs" -type d -mindepth 1 2>/dev/null | wc -l)
        if [[ $deploy_log_dirs -gt 0 ]]; then
            rm -rf "./deployment_logs"/*
            logs_cleaned=$((logs_cleaned + deploy_log_dirs))
            log_info "Cleaned $deploy_log_dirs deployment log directories"
        fi
    fi
    
    # Clean API logs
    if [[ -d "./RAG.APIs/logs" ]]; then
        rm -rf "./RAG.APIs/logs"/*
        log_info "Cleaned API logs"
    fi
    
    log_success "Cleaned $logs_cleaned log files/directories"
}

# Function to clean checkpoints
clean_checkpoints() {
    if [ "$CLEAN_CHECKPOINTS" = false ]; then
        return 0
    fi
    
    log_info "🔖 Cleaning deployment checkpoints..."
    
    local checkpoints_cleaned=0
    
    if [[ -d "./deployment_checkpoints" ]]; then
        local checkpoint_files=$(find "./deployment_checkpoints" -type f 2>/dev/null | wc -l)
        if [[ $checkpoint_files -gt 0 ]]; then
            rm -rf "./deployment_checkpoints"/*
            checkpoints_cleaned=$checkpoint_files
            log_info "Cleaned $checkpoint_files checkpoint files"
        fi
    fi
    
    log_success "Cleaned $checkpoints_cleaned checkpoint files"
}

# Function to destroy AWS resources
destroy_aws_resources() {
    if [ "$DESTROY_AWS" = false ]; then
        return 0
    fi
    
    log_warn "☁️  DESTROYING AWS RESOURCES - This action cannot be undone!"
    log_warn "Environment: $ENVIRONMENT, Project: $PROJECT_NAME"
    
    # Confirmation prompt
    echo ""
    read -p "Are you sure you want to destroy AWS resources? Type 'yes' to confirm: " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "AWS resource destruction cancelled"
        return 0
    fi
    
    log_info "Destroying AWS resources..."
    
    local lambda_function_name="$PROJECT_NAME-$ENVIRONMENT-api"
    local db_identifier="$PROJECT_NAME-$ENVIRONMENT-db"
    
    # Destroy API Gateway
    log_info "Destroying API Gateway..."
    if [[ -f "./deployment_checkpoints/api_gateway_infrastructure.state" ]]; then
        local api_id=$(grep "^API_ID=" "./deployment_checkpoints/api_gateway_infrastructure.state" | cut -d'=' -f2 | tr -d '"')
        if [[ -n "$api_id" ]]; then
            aws apigateway delete-rest-api --rest-api-id "$api_id" 2>/dev/null || log_warn "Failed to delete API Gateway"
            log_info "API Gateway deleted: $api_id"
        fi
    fi
    
    # Destroy Lambda function
    log_info "Destroying Lambda function..."
    if aws lambda get-function --function-name "$lambda_function_name" &>/dev/null; then
        aws lambda delete-function --function-name "$lambda_function_name" 2>/dev/null || log_warn "Failed to delete Lambda function"
        log_info "Lambda function deleted: $lambda_function_name"
    fi
    
    # Destroy Lambda IAM role
    local lambda_role_name="$PROJECT_NAME-$ENVIRONMENT-lambda-role"
    if aws iam get-role --role-name "$lambda_role_name" &>/dev/null; then
        # Detach policies first
        aws iam detach-role-policy --role-name "$lambda_role_name" --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
        aws iam detach-role-policy --role-name "$lambda_role_name" --policy-arn "arn:aws:iam::aws:policy/AmazonRDSDataFullAccess" 2>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name "$lambda_role_name" 2>/dev/null || log_warn "Failed to delete Lambda IAM role"
        log_info "Lambda IAM role deleted: $lambda_role_name"
    fi
    
    # Destroy RDS instance
    log_info "Destroying RDS instance..."
    if aws rds describe-db-instances --db-instance-identifier "$db_identifier" &>/dev/null; then
        aws rds delete-db-instance \
            --db-instance-identifier "$db_identifier" \
            --skip-final-snapshot \
            --delete-automated-backups 2>/dev/null || log_warn "Failed to delete RDS instance"
        log_info "RDS instance deletion initiated: $db_identifier"
        log_warn "RDS deletion may take several minutes to complete"
    fi
    
    log_success "AWS resource destruction completed"
}

# Function to display cleanup summary
display_summary() {
    log_success "🧹 Cleanup Process Completed!"
    echo ""
    echo "=== Cleanup Summary ==="
    echo "Environment: $ENVIRONMENT"
    echo "Project: $PROJECT_NAME"
    echo ""
    echo "=== Actions Performed ==="
    
    if [ "$CLEAN_TEMP" = true ]; then
        echo "✅ Temporary files cleaned"
    else
        echo "⏭️  Temporary files skipped"
    fi
    
    if [ "$CLEAN_LOGS" = true ]; then
        echo "✅ Logs cleaned"
    else
        echo "⏭️  Logs skipped"
    fi
    
    if [ "$CLEAN_CHECKPOINTS" = true ]; then
        echo "✅ Checkpoints cleaned"
    else
        echo "⏭️  Checkpoints skipped"
    fi
    
    if [ "$DESTROY_AWS" = true ]; then
        echo "⚠️  AWS resources destroyed"
    else
        echo "⏭️  AWS resources preserved"
    fi
    
    echo ""
    echo "=== Remaining Files ==="
    echo "📁 Source code: Preserved"
    echo "📁 Configuration: Preserved"
    echo "📁 Documentation: Preserved"
    
    if [ "$CLEAN_CHECKPOINTS" = false ]; then
        echo "📁 Deployment checkpoints: Preserved"
    fi
    
    if [ "$CLEAN_LOGS" = false ]; then
        echo "📁 Logs: Preserved"
    fi
    
    echo ""
}

# Main execution function
main() {
    log_info "🧹 Starting Cleanup Process..."
    
    # Parse arguments
    parse_arguments "$@"
    
    log_info "Configuration:"
    log_info "  Clean Temp: $CLEAN_TEMP"
    log_info "  Clean Logs: $CLEAN_LOGS"
    log_info "  Clean Checkpoints: $CLEAN_CHECKPOINTS"
    log_info "  Destroy AWS: $DESTROY_AWS"
    log_info "  Environment: $ENVIRONMENT"
    log_info "  Project: $PROJECT_NAME"
    
    # Perform cleanup operations
    clean_temp_files
    clean_logs
    clean_checkpoints
    destroy_aws_resources
    
    # Display summary
    display_summary
    
    log_success "🧹 Cleanup process completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi