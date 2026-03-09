#!/bin/bash

# =============================================================================
# Entity Framework Migration Runner Script
# =============================================================================
# This script runs Entity Framework migrations for the .NET 10 application
# with proper database connectivity validation, error handling, and rollback
# capabilities.
#
# Usage:
#   ./run-migrations.sh [OPTIONS]
#
# Options:
#   --connection-string <string>  Database connection string (required)
#   --project-path <path>         Path to the .NET project (default: code/TestDeployLambda/BE)
#   --startup-project <path>      Startup project path (default: RAG.APIs)
#   --context <name>              DbContext name (default: ApplicationDbContext)
#   --rollback-to <migration>     Rollback to specific migration
#   --dry-run                     Show what would be executed without running
#   --verbose                     Enable verbose logging
#   --help                        Show this help message
#
# Requirements: 2.1, 2.3, 2.4
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
PROJECT_PATH=""
STARTUP_PROJECT=""
CONTEXT_NAME=""
ROLLBACK_TO=""
DRY_RUN=false
VERBOSE=false

# =============================================================================
# Helper Functions
# =============================================================================

show_help() {
    cat << EOF
Entity Framework Migration Runner

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --connection-string <string>  Database connection string (required)
    --project-path <path>         Path to the .NET project (default: $DEFAULT_PROJECT_PATH)
    --startup-project <path>      Startup project path (default: $DEFAULT_STARTUP_PROJECT)
    --context <name>              DbContext name (default: $DEFAULT_CONTEXT)
    --rollback-to <migration>     Rollback to specific migration
    --dry-run                     Show what would be executed without running
    --verbose                     Enable verbose logging
    --help                        Show this help message

EXAMPLES:
    # Run migrations with connection string
    $0 --connection-string "Host=mydb.amazonaws.com;Port=5432;Database=RAG-System;Username=postgres;Password=mypass"
    
    # Rollback to specific migration
    $0 --connection-string "..." --rollback-to "20260303161754_initDb"
    
    # Dry run to see what would be executed
    $0 --connection-string "..." --dry-run

REQUIREMENTS:
    - .NET 10 SDK installed
    - Entity Framework Core tools installed
    - PostgreSQL database accessible
    - Valid connection string with proper permissions

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --connection-string)
                CONNECTION_STRING="$2"
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
            --rollback-to)
                ROLLBACK_TO="$2"
                shift 2
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
}

validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check if .NET SDK is installed
    if ! command -v dotnet &> /dev/null; then
        log_error ".NET SDK is not installed or not in PATH"
        log_error "Please install .NET 10 SDK: https://dotnet.microsoft.com/download"
        exit 1
    fi

    # Check .NET version
    local dotnet_version
    dotnet_version=$(dotnet --version)
    log_info "Found .NET SDK version: $dotnet_version"

    # Check if project path exists
    if [[ ! -d "$PROJECT_PATH" ]]; then
        log_error "Project path does not exist: $PROJECT_PATH"
        exit 1
    fi

    # Check if startup project exists
    local startup_project_path="$PROJECT_PATH/$STARTUP_PROJECT"
    if [[ ! -d "$startup_project_path" ]]; then
        log_error "Startup project does not exist: $startup_project_path"
        exit 1
    fi

    # Check if Infrastructure project exists (contains DbContext)
    local infrastructure_project="$PROJECT_PATH/RAG.Infrastructure"
    if [[ ! -d "$infrastructure_project" ]]; then
        log_error "Infrastructure project does not exist: $infrastructure_project"
        exit 1
    fi

    # Check if Entity Framework tools are available
    if ! dotnet ef --version &> /dev/null; then
        log_info "Installing Entity Framework Core tools..."
        if ! dotnet tool install --global dotnet-ef; then
            log_error "Failed to install Entity Framework Core tools"
            exit 1
        fi
    fi

    log_success "Prerequisites validation completed"
}

validate_database_connectivity() {
    log_info "Validating database connectivity..."

    # Extract database details from connection string for validation
    local host port database username
    
    # Parse connection string (PostgreSQL format)
    if [[ $CONNECTION_STRING =~ Host=([^;]+) ]]; then
        host="${BASH_REMATCH[1]}"
    else
        log_error "Could not extract host from connection string"
        return 1
    fi

    if [[ $CONNECTION_STRING =~ Port=([^;]+) ]]; then
        port="${BASH_REMATCH[1]}"
    else
        port="5432"  # Default PostgreSQL port
    fi

    if [[ $CONNECTION_STRING =~ Database=([^;]+) ]]; then
        database="${BASH_REMATCH[1]}"
    else
        log_error "Could not extract database name from connection string"
        return 1
    fi

    if [[ $CONNECTION_STRING =~ Username=([^;]+) ]]; then
        username="${BASH_REMATCH[1]}"
    else
        log_error "Could not extract username from connection string"
        return 1
    fi

    log_info "Testing connection to: $host:$port/$database as $username"

    # Test basic connectivity using psql if available
    if command -v psql &> /dev/null; then
        log_info "Testing database connectivity with psql..."
        if timeout 10 psql "$CONNECTION_STRING" -c "SELECT 1;" &> /dev/null; then
            log_success "Database connectivity test passed"
        else
            log_warning "Direct psql test failed, but will proceed with EF migration test"
        fi
    else
        log_info "psql not available, skipping direct connectivity test"
    fi

    # Test EF connectivity by checking database
    log_info "Testing Entity Framework connectivity..."
    local ef_test_output
    if ef_test_output=$(cd "$PROJECT_PATH" && dotnet ef database drop --force --dry-run \
        --connection "$CONNECTION_STRING" \
        --project "RAG.Infrastructure" \
        --startup-project "$STARTUP_PROJECT" \
        --context "$CONTEXT_NAME" 2>&1); then
        log_success "Entity Framework can connect to database"
    else
        log_error "Entity Framework connectivity test failed:"
        log_error "$ef_test_output"
        return 1
    fi
}

get_current_migration() {
    log_info "Getting current migration status..."
    
    local migration_output
    if migration_output=$(cd "$PROJECT_PATH" && dotnet ef migrations list \
        --connection "$CONNECTION_STRING" \
        --project "RAG.Infrastructure" \
        --startup-project "$STARTUP_PROJECT" \
        --context "$CONTEXT_NAME" 2>&1); then
        
        log_info "Current migrations:"
        echo "$migration_output" | while IFS= read -r line; do
            log_info "  $line"
        done
        
        # Get the last applied migration
        local last_migration
        last_migration=$(echo "$migration_output" | grep -E "^\s*[0-9]" | tail -1 | awk '{print $1}' || echo "")
        
        if [[ -n "$last_migration" ]]; then
            log_info "Last applied migration: $last_migration"
        else
            log_info "No migrations have been applied yet"
        fi
    else
        log_error "Failed to get migration status:"
        log_error "$migration_output"
        return 1
    fi
}

backup_database() {
    log_info "Creating database backup before migration..."
    
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
    backup_file="backup_${database}_$(date +%Y%m%d_%H%M%S).sql"
    
    if command -v pg_dump &> /dev/null; then
        log_info "Creating backup: $backup_file"
        
        # Set password for pg_dump
        export PGPASSWORD="$password"
        
        if pg_dump -h "$host" -p "$port" -U "$username" -d "$database" > "$backup_file"; then
            log_success "Database backup created: $backup_file"
            echo "$backup_file"  # Return backup filename
        else
            log_warning "Failed to create database backup, but continuing with migration"
            echo ""
        fi
        
        unset PGPASSWORD
    else
        log_warning "pg_dump not available, skipping database backup"
        echo ""
    fi
}

run_migrations() {
    log_info "Running Entity Framework migrations..."
    
    local migration_command
    if [[ -n "$ROLLBACK_TO" ]]; then
        migration_command="dotnet ef database update \"$ROLLBACK_TO\""
        log_info "Rolling back to migration: $ROLLBACK_TO"
    else
        migration_command="dotnet ef database update"
        log_info "Applying all pending migrations"
    fi
    
    # Add common parameters
    migration_command="$migration_command --connection \"$CONNECTION_STRING\""
    migration_command="$migration_command --project \"RAG.Infrastructure\""
    migration_command="$migration_command --startup-project \"$STARTUP_PROJECT\""
    migration_command="$migration_command --context \"$CONTEXT_NAME\""
    
    if [[ "$VERBOSE" == "true" ]]; then
        migration_command="$migration_command --verbose"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN - Would execute:"
        log_info "$migration_command"
        return 0
    fi
    
    log_info "Executing migration command..."
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Command: $migration_command"
    fi
    
    local migration_output
    if migration_output=$(cd "$PROJECT_PATH" && eval "$migration_command" 2>&1); then
        log_success "Migrations completed successfully"
        if [[ "$VERBOSE" == "true" ]]; then
            log_info "Migration output:"
            echo "$migration_output" | while IFS= read -r line; do
                log_info "  $line"
            done
        fi
    else
        log_error "Migration failed:"
        log_error "$migration_output"
        return 1
    fi
}

rollback_on_failure() {
    local backup_file="$1"
    
    if [[ -n "$backup_file" && -f "$backup_file" ]]; then
        log_info "Attempting to restore database from backup: $backup_file"
        
        # Extract database connection details
        local host port database username password
        
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
        
        if command -v psql &> /dev/null; then
            export PGPASSWORD="$password"
            
            # Drop and recreate database
            log_info "Dropping and recreating database for restore..."
            if psql -h "$host" -p "$port" -U "$username" -d "postgres" \
                -c "DROP DATABASE IF EXISTS \"$database\";" \
                -c "CREATE DATABASE \"$database\";"; then
                
                # Restore from backup
                log_info "Restoring database from backup..."
                if psql -h "$host" -p "$port" -U "$username" -d "$database" < "$backup_file"; then
                    log_success "Database restored successfully from backup"
                else
                    log_error "Failed to restore database from backup"
                fi
            else
                log_error "Failed to recreate database for restore"
            fi
            
            unset PGPASSWORD
        else
            log_error "psql not available, cannot restore from backup"
        fi
    else
        log_warning "No backup file available for rollback"
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    log_info "Starting Entity Framework Migration Runner"
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
    
    # Validate database connectivity
    if ! validate_database_connectivity; then
        log_error "Database connectivity validation failed"
        exit 1
    fi
    
    # Get current migration status
    get_current_migration
    
    # Create backup before migration (if not dry run)
    local backup_file=""
    if [[ "$DRY_RUN" != "true" && -z "$ROLLBACK_TO" ]]; then
        backup_file=$(backup_database)
    fi
    
    # Run migrations with error handling
    if ! run_migrations; then
        log_error "Migration failed"
        
        # Attempt rollback if we have a backup
        if [[ -n "$backup_file" ]]; then
            log_info "Attempting automatic rollback..."
            rollback_on_failure "$backup_file"
        fi
        
        exit 1
    fi
    
    # Verify migration status after completion
    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Verifying migration status after completion..."
        get_current_migration
    fi
    
    # Clean up backup file if migration was successful and it's not a rollback
    if [[ -n "$backup_file" && -f "$backup_file" && -z "$ROLLBACK_TO" ]]; then
        log_info "Migration successful, cleaning up backup file: $backup_file"
        rm -f "$backup_file"
    fi
    
    log_success "Entity Framework migration runner completed successfully"
}

# Execute main function with all arguments
main "$@"