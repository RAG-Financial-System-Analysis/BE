#!/bin/bash

# =============================================================================
# Entity Framework Migration Rollback Script
# =============================================================================
# This script provides rollback capabilities for Entity Framework migrations
# with proper validation and safety checks.
#
# Usage:
#   ./rollback-migrations.sh [OPTIONS]
#
# Options:
#   --connection-string <string>  Database connection string (required)
#   --target-migration <name>     Target migration to rollback to (required)
#   --project-path <path>         Path to the .NET project (default: code/TestDeployLambda/BE)
#   --startup-project <path>      Startup project path (default: RAG.APIs)
#   --context <name>              DbContext name (default: ApplicationDbContext)
#   --force                       Skip confirmation prompts
#   --backup                      Create backup before rollback
#   --dry-run                     Show what would be executed without running
#   --verbose                     Enable verbose logging
#   --help                        Show this help message
#
# Requirements: 2.3, 2.4
# =============================================================================

set -euo pipefail

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/logging.sh"
source "${SCRIPT_DIR}/../utilities/error-handling.sh"

# Default configuration
DEFAULT_PROJECT_PATH="code/TestDeployLambda/BE"
DEFAULT_STARTUP_PROJECT="RAG.APIs"
DEFAULT_CONTEXT="ApplicationDbContext"

CONNECTION_STRING=""
TARGET_MIGRATION=""
PROJECT_PATH=""
STARTUP_PROJECT=""
CONTEXT_NAME=""
FORCE=false
BACKUP=false
DRY_RUN=false
VERBOSE=false

# =============================================================================
# Helper Functions
# =============================================================================

show_help() {
    cat << EOF
Entity Framework Migration Rollback Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --connection-string <string>  Database connection string (required)
    --target-migration <name>     Target migration to rollback to (required)
    --project-path <path>         Path to the .NET project (default: $DEFAULT_PROJECT_PATH)
    --startup-project <path>      Startup project path (default: $DEFAULT_STARTUP_PROJECT)
    --context <name>              DbContext name (default: $DEFAULT_CONTEXT)
    --force                       Skip confirmation prompts
    --backup                      Create backup before rollback
    --dry-run                     Show what would be executed without running
    --verbose                     Enable verbose logging
    --help                        Show this help message

EXAMPLES:
    # Rollback to specific migration
    $0 --connection-string "Host=mydb.amazonaws.com;..." --target-migration "20260303161754_initDb"
    
    # Rollback with backup
    $0 --connection-string "..." --target-migration "InitialCreate" --backup
    
    # Dry run to see what would be rolled back
    $0 --connection-string "..." --target-migration "InitialCreate" --dry-run

SPECIAL TARGETS:
    - Use "0" or "InitialCreate" to rollback all migrations
    - Use specific migration name to rollback to that point

SAFETY FEATURES:
    - Lists current migrations before rollback
    - Shows which migrations will be rolled back
    - Requires confirmation unless --force is used
    - Optional database backup before rollback

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --connection-string)
                CONNECTION_STRING="$2"
                shift 2
                ;;
            --target-migration)
                TARGET_MIGRATION="$2"
                shift 2
                ;;
            --project-path)
                PROJECT_PATH="$2"
                shift 2
                ;;
            --startup-project)
                STARTUP_PROJECT="$2"
                shift 2
                ;;
            --context)
                CONTEXT_NAME="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --backup)
                BACKUP=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Set defaults
    PROJECT_PATH="${PROJECT_PATH:-$DEFAULT_PROJECT_PATH}"
    STARTUP_PROJECT="${STARTUP_PROJECT:-$DEFAULT_STARTUP_PROJECT}"
    CONTEXT_NAME="${CONTEXT_NAME:-$DEFAULT_CONTEXT}"

    # Validate required parameters
    if [[ -z "$CONNECTION_STRING" ]]; then
        log_error "Connection string is required. Use --connection-string option."
        show_help
        exit 1
    fi

    if [[ -z "$TARGET_MIGRATION" ]]; then
        log_error "Target migration is required. Use --target-migration option."
        show_help
        exit 1
    fi
}

validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check if .NET SDK is installed
    if ! command -v dotnet &> /dev/null; then
        log_error ".NET SDK is not installed or not in PATH"
        exit 1
    fi

    # Check if project path exists
    if [[ ! -d "$PROJECT_PATH" ]]; then
        log_error "Project path does not exist: $PROJECT_PATH"
        exit 1
    fi

    # Check if Entity Framework tools are available
    if ! dotnet ef --version &> /dev/null; then
        log_error "Entity Framework Core tools are not installed"
        log_error "Install with: dotnet tool install --global dotnet-ef"
        exit 1
    fi

    log_success "Prerequisites validation completed"
}

get_migration_list() {
    log_info "Getting current migration list..."
    
    local migration_output
    if migration_output=$(cd "$PROJECT_PATH" && dotnet ef migrations list \
        --connection "$CONNECTION_STRING" \
        --project "RAG.Infrastructure" \
        --startup-project "$STARTUP_PROJECT" \
        --context "$CONTEXT_NAME" 2>&1); then
        
        echo "$migration_output"
    else
        log_error "Failed to get migration list:"
        log_error "$migration_output"
        return 1
    fi
}

validate_target_migration() {
    log_info "Validating target migration: $TARGET_MIGRATION"
    
    # Special cases
    if [[ "$TARGET_MIGRATION" == "0" || "$TARGET_MIGRATION" == "InitialCreate" ]]; then
        log_info "Target migration is valid (rollback all migrations)"
        return 0
    fi
    
    # Get migration list and check if target exists
    local migration_list
    if migration_list=$(get_migration_list); then
        if echo "$migration_list" | grep -q "$TARGET_MIGRATION"; then
            log_info "Target migration found in migration list"
            return 0
        else
            log_error "Target migration '$TARGET_MIGRATION' not found in migration list"
            log_info "Available migrations:"
            echo "$migration_list" | while IFS= read -r line; do
                log_info "  $line"
            done
            return 1
        fi
    else
        log_error "Could not validate target migration"
        return 1
    fi
}

show_rollback_plan() {
    log_info "Analyzing rollback plan..."
    
    local migration_list current_migration
    migration_list=$(get_migration_list)
    
    # Find current migration (last applied)
    current_migration=$(echo "$migration_list" | grep -E "^\s*[0-9]" | tail -1 | awk '{print $1}' || echo "")
    
    if [[ -z "$current_migration" ]]; then
        log_info "No migrations are currently applied"
        return 0
    fi
    
    log_info "Current migration: $current_migration"
    log_info "Target migration: $TARGET_MIGRATION"
    
    # Show migrations that will be rolled back
    log_warning "The following migrations will be ROLLED BACK:"
    
    local found_target=false
    echo "$migration_list" | grep -E "^\s*[0-9]" | while IFS= read -r line; do
        local migration_name
        migration_name=$(echo "$line" | awk '{print $1}')
        
        if [[ "$migration_name" == "$TARGET_MIGRATION" ]]; then
            found_target=true
        fi
        
        if [[ "$found_target" == "false" ]]; then
            log_warning "  - $migration_name (WILL BE ROLLED BACK)"
        else
            log_info "  - $migration_name (will remain)"
        fi
    done
}

create_backup() {
    log_info "Creating database backup before rollback..."
    
    # Extract database details for backup
    local host port database username password backup_file
    
    if [[ $CONNECTION_STRING =~ Host=([^;]+) ]]; then
        host="${BASH_REMATCH[1]}"
    fi
    
    if [[ $CONNECTION_STRING =~ Port=([^;]+) ]]; then
        port="${BASH_REMATCH[1]}"
    else
        port="5432"
    fi
    
    if [[ $CONNECTION_STRING =~ Database=([^;]+) ]]; then
        database="${BASH_REMATCH[1]}"
    fi
    
    if [[ $CONNECTION_STRING =~ Username=([^;]+) ]]; then
        username="${BASH_REMATCH[1]}"
    fi
    
    if [[ $CONNECTION_STRING =~ Password=([^;]+) ]]; then
        password="${BASH_REMATCH[1]}"
    fi
    
    # Create backup filename with timestamp
    backup_file="rollback_backup_${database}_$(date +%Y%m%d_%H%M%S).sql"
    
    if command -v pg_dump &> /dev/null; then
        log_info "Creating backup: $backup_file"
        
        # Set password for pg_dump
        export PGPASSWORD="$password"
        
        if pg_dump -h "$host" -p "$port" -U "$username" -d "$database" > "$backup_file"; then
            log_success "Database backup created: $backup_file"
            echo "$backup_file"  # Return backup filename
        else
            log_error "Failed to create database backup"
            unset PGPASSWORD
            return 1
        fi
        
        unset PGPASSWORD
    else
        log_error "pg_dump not available, cannot create backup"
        return 1
    fi
}

confirm_rollback() {
    if [[ "$FORCE" == "true" ]]; then
        log_info "Skipping confirmation (--force flag used)"
        return 0
    fi
    
    log_warning "⚠️  WARNING: This operation will rollback database migrations!"
    log_warning "⚠️  This may result in data loss if the rolled-back migrations contain data changes!"
    
    echo
    read -p "Are you sure you want to proceed with the rollback? (yes/no): " -r
    echo
    
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Rollback confirmed by user"
        return 0
    else
        log_info "Rollback cancelled by user"
        return 1
    fi
}

execute_rollback() {
    log_info "Executing migration rollback..."
    
    local rollback_command
    rollback_command="dotnet ef database update \"$TARGET_MIGRATION\""
    rollback_command="$rollback_command --connection \"$CONNECTION_STRING\""
    rollback_command="$rollback_command --project \"RAG.Infrastructure\""
    rollback_command="$rollback_command --startup-project \"$STARTUP_PROJECT\""
    rollback_command="$rollback_command --context \"$CONTEXT_NAME\""
    
    if [[ "$VERBOSE" == "true" ]]; then
        rollback_command="$rollback_command --verbose"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN - Would execute:"
        log_info "$rollback_command"
        return 0
    fi
    
    log_info "Executing rollback command..."
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Command: $rollback_command"
    fi
    
    local rollback_output
    if rollback_output=$(cd "$PROJECT_PATH" && eval "$rollback_command" 2>&1); then
        log_success "Migration rollback completed successfully"
        if [[ "$VERBOSE" == "true" ]]; then
            log_info "Rollback output:"
            echo "$rollback_output" | while IFS= read -r line; do
                log_info "  $line"
            done
        fi
    else
        log_error "Migration rollback failed:"
        log_error "$rollback_output"
        return 1
    fi
}

verify_rollback() {
    log_info "Verifying rollback completion..."
    
    local migration_list current_migration
    migration_list=$(get_migration_list)
    current_migration=$(echo "$migration_list" | grep -E "^\s*[0-9]" | tail -1 | awk '{print $1}' || echo "")
    
    if [[ "$TARGET_MIGRATION" == "0" || "$TARGET_MIGRATION" == "InitialCreate" ]]; then
        if [[ -z "$current_migration" ]]; then
            log_success "All migrations successfully rolled back"
        else
            log_error "Rollback verification failed: migrations still applied"
            return 1
        fi
    else
        if [[ "$current_migration" == "$TARGET_MIGRATION" ]]; then
            log_success "Successfully rolled back to migration: $TARGET_MIGRATION"
        else
            log_error "Rollback verification failed: current migration is $current_migration, expected $TARGET_MIGRATION"
            return 1
        fi
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    log_info "Starting Entity Framework Migration Rollback"
    log_info "Script: $0"
    log_info "Arguments: $*"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Enable verbose logging if requested
    if [[ "$VERBOSE" == "true" ]]; then
        set -x
    fi
    
    # Validate prerequisites
    validate_prerequisites
    
    # Validate target migration
    if ! validate_target_migration; then
        log_error "Target migration validation failed"
        exit 1
    fi
    
    # Show rollback plan
    show_rollback_plan
    
    # Create backup if requested
    local backup_file=""
    if [[ "$BACKUP" == "true" && "$DRY_RUN" != "true" ]]; then
        if backup_file=$(create_backup); then
            log_info "Backup created: $backup_file"
        else
            log_error "Backup creation failed"
            exit 1
        fi
    fi
    
    # Confirm rollback
    if ! confirm_rollback; then
        log_info "Rollback cancelled"
        exit 0
    fi
    
    # Execute rollback
    if ! execute_rollback; then
        log_error "Migration rollback failed"
        exit 1
    fi
    
    # Verify rollback (skip in dry run)
    if [[ "$DRY_RUN" != "true" ]]; then
        if ! verify_rollback; then
            log_error "Rollback verification failed"
            exit 1
        fi
    fi
    
    log_success "Migration rollback completed successfully"
    
    if [[ -n "$backup_file" ]]; then
        log_info "Backup file available at: $backup_file"
    fi
}

# Execute main function with all arguments
main "$@"