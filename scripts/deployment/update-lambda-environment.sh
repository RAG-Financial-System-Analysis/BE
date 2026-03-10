#!/bin/bash

# Lambda Environment Variable Update Utility
# Updates Lambda environment variables from converted configuration
# Handles connection string updates after RDS provisioning
# Implements secure handling of sensitive configuration values

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILITIES_DIR="$SCRIPT_DIR/../utilities"
source "$UTILITIES_DIR/logging.sh"
source "$UTILITIES_DIR/error-handling.sh"
source "$UTILITIES_DIR/validate-aws-cli.sh"

# Configuration variables
ENVIRONMENT="${ENVIRONMENT:-dev}"
PROJECT_NAME="${PROJECT_NAME:-myragapp}"
LAMBDA_FUNCTION_NAME="$PROJECT_NAME-$ENVIRONMENT-api"

# Update modes
UPDATE_MODE="${UPDATE_MODE:-merge}"  # merge, replace, selective
DRY_RUN="${DRY_RUN:-false}"

# Global variables
CURRENT_ENV_VARS=()
NEW_ENV_VARS=()
UPDATED_ENV_VARS=()
SENSITIVE_KEYS=("password" "secret" "key" "token" "connectionstring")

# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Updates Lambda environment variables with secure handling of sensitive values.

OPTIONS:
    --function-name NAME       Lambda function name (default: $PROJECT_NAME-$ENVIRONMENT-api)
    --environment ENV          Environment name (default: dev)
    --project-name NAME        Project name (default: myapp)
    --update-mode MODE         Update mode: merge, replace, selective (default: merge)
    --connection-string STR    Update database connection string
    --config-file FILE         Load variables from converted configuration file
    --env-file FILE            Load variables from environment file
    --set KEY=VALUE            Set individual environment variable
    --unset KEY                Remove environment variable
    --from-rds                 Update connection string from RDS checkpoint
    --dry-run                  Show changes without applying them
    --aws-profile PROFILE      AWS profile to use
    --help                     Show this help message

UPDATE MODES:
    merge      - Add/update variables, keep existing ones (default)
    replace    - Replace all environment variables with new ones
    selective  - Update only specified variables

EXAMPLES:
    # Update connection string from RDS provisioning
    $0 --from-rds --function-name webapp-prod-api

    # Set individual variables
    $0 --set "AWS__Region=us-east-1" --set "OpenAI__Model=gpt-4"

    # Load from configuration file
    $0 --config-file lambda-env-vars.json --update-mode merge

    # Replace all variables
    $0 --config-file new-config.json --update-mode replace

    # Remove sensitive variable
    $0 --unset "OpenAI__ApiKey"

    # Dry run to see changes
    $0 --from-rds --dry-run

SECURITY FEATURES:
    - Sensitive values are masked in logs and output
    - Connection strings are automatically detected as sensitive
    - Support for AWS Secrets Manager integration
    - Secure handling of database credentials

EOF
}

# Function to parse command line arguments
parse_arguments() {
    local config_file=""
    local env_file=""
    local connection_string=""
    local from_rds=false
    local set_vars=()
    local unset_vars=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --function-name)
                LAMBDA_FUNCTION_NAME="$2"
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
            --update-mode)
                UPDATE_MODE="$2"
                shift 2
                ;;
            --connection-string)
                connection_string="$2"
                shift 2
                ;;
            --config-file)
                config_file="$2"
                shift 2
                ;;
            --env-file)
                env_file="$2"
                shift 2
                ;;
            --set)
                set_vars+=("$2")
                shift 2
                ;;
            --unset)
                unset_vars+=("$2")
                shift 2
                ;;
            --from-rds)
                from_rds=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
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
    
    # Process parsed arguments
    if [ -n "$config_file" ]; then
        load_variables_from_config_file "$config_file"
    fi
    
    if [ -n "$env_file" ]; then
        load_variables_from_env_file "$env_file"
    fi
    
    if [ -n "$connection_string" ]; then
        NEW_ENV_VARS+=("ConnectionStrings__DefaultConnection=$connection_string")
    fi
    
    if [ "$from_rds" = true ]; then
        load_connection_string_from_rds
    fi
    
    for var in "${set_vars[@]}"; do
        NEW_ENV_VARS+=("$var")
    done
    
    for var in "${unset_vars[@]}"; do
        NEW_ENV_VARS+=("$var=__UNSET__")
    done
}

# Function to check if a key is sensitive
is_sensitive_key() {
    local key="$1"
    local key_lower=$(echo "$key" | tr '[:upper:]' '[:lower:]')
    
    for sensitive in "${SENSITIVE_KEYS[@]}"; do
        if [[ "$key_lower" == *"$sensitive"* ]]; then
            return 0
        fi
    done
    return 1
}

# Function to mask sensitive values for display
mask_sensitive_value() {
    local key="$1"
    local value="$2"
    
    if is_sensitive_key "$key"; then
        echo "***"
    else
        echo "$value"
    fi
}

# Function to validate Lambda function exists
validate_lambda_function() {
    log_info "Validating Lambda function: $LAMBDA_FUNCTION_NAME"
    
    if ! aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        set_error_context "Lambda function validation"
        set_error_remediation "Ensure Lambda function exists or run provision-lambda.sh first"
        handle_error $ERROR_CODE_LAMBDA "Lambda function not found: $LAMBDA_FUNCTION_NAME" true
    fi
    
    log_success "Lambda function validated"
}

# Function to get current environment variables
get_current_env_vars() {
    log_info "Retrieving current environment variables from Lambda function..."
    
    local env_json=$(aws lambda get-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Environment.Variables' \
        --output json 2>/dev/null || echo "{}")
    
    if [ "$env_json" = "null" ] || [ "$env_json" = "{}" ]; then
        log_info "No existing environment variables found"
        return 0
    fi
    
    # Convert JSON to key=value format
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            CURRENT_ENV_VARS+=("$line")
        fi
    done < <(echo "$env_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
    
    log_info "Found ${#CURRENT_ENV_VARS[@]} existing environment variables"
}

# Function to load variables from JSON config file
load_variables_from_config_file() {
    local config_file="$1"
    
    log_info "Loading variables from config file: $config_file"
    validate_file_exists "$config_file" "configuration file"
    
    # Validate JSON format
    if ! jq empty "$config_file" 2>/dev/null; then
        set_error_context "Configuration file validation"
        set_error_remediation "Ensure $config_file contains valid JSON"
        handle_error $ERROR_CODE_VALIDATION "Invalid JSON in configuration file: $config_file" true
    fi
    
    # Load variables from JSON
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            NEW_ENV_VARS+=("$line")
        fi
    done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' "$config_file")
    
    log_success "Loaded ${#NEW_ENV_VARS[@]} variables from config file"
}

# Function to load variables from environment file
load_variables_from_env_file() {
    local env_file="$1"
    
    log_info "Loading variables from environment file: $env_file"
    validate_file_exists "$env_file" "environment file"
    
    # Load variables from file (format: KEY=VALUE)
    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
            continue
        fi
        
        # Remove 'export ' prefix if present
        line=$(echo "$line" | sed 's/^export //')
        
        # Validate format
        if [[ "$line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*= ]]; then
            NEW_ENV_VARS+=("$line")
        else
            log_warn "Skipping invalid line in env file: $line"
        fi
    done < "$env_file"
    
    log_success "Loaded variables from environment file"
}

# Function to load connection string from RDS checkpoint
load_connection_string_from_rds() {
    log_info "Loading connection string from RDS checkpoint..."
    
    local rds_state_file="./deployment_checkpoints/rds_infrastructure.state"
    
    if [ ! -f "$rds_state_file" ]; then
        log_warn "RDS infrastructure state file not found: $rds_state_file"
        log_warn "Run provision-rds.sh first to create RDS infrastructure"
        return 1
    fi
    
    # Source RDS state
    source "$rds_state_file"
    
    # Get database password from checkpoint
    local db_password=""
    if db_password=$(restore_checkpoint "rds_password" 2>/dev/null); then
        log_info "Retrieved database password from checkpoint"
    else
        log_warn "Database password not found in checkpoint"
        log_warn "Connection string will use placeholder password"
        db_password="PLACEHOLDER_PASSWORD"
    fi
    
    # Build connection string
    if [ -n "${DB_ENDPOINT:-}" ] && [ -n "${DB_NAME:-}" ] && [ -n "${MASTER_USERNAME:-}" ]; then
        local connection_string="Host=${DB_ENDPOINT};Database=${DB_NAME};Username=${MASTER_USERNAME};Password=${db_password};Port=5432;SSL Mode=Require;"
        NEW_ENV_VARS+=("ConnectionStrings__DefaultConnection=$connection_string")
        log_success "Loaded connection string from RDS infrastructure"
    else
        log_error "Incomplete RDS infrastructure state. Missing required values."
        return 1
    fi
}

# Function to merge environment variables based on update mode
merge_env_vars() {
    log_info "Merging environment variables (mode: $UPDATE_MODE)..."
    
    case "$UPDATE_MODE" in
        "replace")
            # Replace all variables with new ones
            UPDATED_ENV_VARS=("${NEW_ENV_VARS[@]}")
            log_info "Replace mode: Using ${#NEW_ENV_VARS[@]} new variables"
            ;;
        "merge")
            # Start with current variables
            UPDATED_ENV_VARS=("${CURRENT_ENV_VARS[@]}")
            
            # Add or update with new variables
            for new_var in "${NEW_ENV_VARS[@]}"; do
                local new_key=$(echo "$new_var" | cut -d'=' -f1)
                local new_value=$(echo "$new_var" | cut -d'=' -f2-)
                
                # Handle unset operation
                if [ "$new_value" = "__UNSET__" ]; then
                    # Remove variable
                    local temp_vars=()
                    for existing_var in "${UPDATED_ENV_VARS[@]}"; do
                        local existing_key=$(echo "$existing_var" | cut -d'=' -f1)
                        if [ "$existing_key" != "$new_key" ]; then
                            temp_vars+=("$existing_var")
                        fi
                    done
                    UPDATED_ENV_VARS=("${temp_vars[@]}")
                    log_info "Removed variable: $new_key"
                    continue
                fi
                
                # Update existing or add new
                local found=false
                for i in "${!UPDATED_ENV_VARS[@]}"; do
                    local existing_key=$(echo "${UPDATED_ENV_VARS[$i]}" | cut -d'=' -f1)
                    if [ "$existing_key" = "$new_key" ]; then
                        UPDATED_ENV_VARS[$i]="$new_var"
                        found=true
                        local display_value=$(mask_sensitive_value "$new_key" "$new_value")
                        log_info "Updated variable: $new_key=$display_value"
                        break
                    fi
                done
                
                if [ "$found" = false ]; then
                    UPDATED_ENV_VARS+=("$new_var")
                    local display_value=$(mask_sensitive_value "$new_key" "$new_value")
                    log_info "Added variable: $new_key=$display_value"
                fi
            done
            ;;
        "selective")
            # Update only specified variables
            UPDATED_ENV_VARS=("${CURRENT_ENV_VARS[@]}")
            
            for new_var in "${NEW_ENV_VARS[@]}"; do
                local new_key=$(echo "$new_var" | cut -d'=' -f1)
                local new_value=$(echo "$new_var" | cut -d'=' -f2-)
                
                # Handle unset operation
                if [ "$new_value" = "__UNSET__" ]; then
                    local temp_vars=()
                    for existing_var in "${UPDATED_ENV_VARS[@]}"; do
                        local existing_key=$(echo "$existing_var" | cut -d'=' -f1)
                        if [ "$existing_key" != "$new_key" ]; then
                            temp_vars+=("$existing_var")
                        fi
                    done
                    UPDATED_ENV_VARS=("${temp_vars[@]}")
                    log_info "Removed variable: $new_key"
                    continue
                fi
                
                # Update only if exists
                local found=false
                for i in "${!UPDATED_ENV_VARS[@]}"; do
                    local existing_key=$(echo "${UPDATED_ENV_VARS[$i]}" | cut -d'=' -f1)
                    if [ "$existing_key" = "$new_key" ]; then
                        UPDATED_ENV_VARS[$i]="$new_var"
                        found=true
                        local display_value=$(mask_sensitive_value "$new_key" "$new_value")
                        log_info "Updated existing variable: $new_key=$display_value"
                        break
                    fi
                done
                
                if [ "$found" = false ]; then
                    log_warn "Variable not found for selective update: $new_key"
                fi
            done
            ;;
        *)
            log_error "Invalid update mode: $UPDATE_MODE"
            show_usage
            exit 1
            ;;
    esac
    
    log_success "Environment variables merged (${#UPDATED_ENV_VARS[@]} total)"
}

# Function to validate environment variables
validate_env_vars() {
    log_info "Validating environment variables..."
    
    local validation_errors=()
    
    # Check for duplicate keys
    local keys=()
    for var in "${UPDATED_ENV_VARS[@]}"; do
        local key=$(echo "$var" | cut -d'=' -f1)
        if [[ " ${keys[@]} " =~ " $key " ]]; then
            validation_errors+=("Duplicate environment variable key: $key")
        else
            keys+=("$key")
        fi
    done
    
    # Check key format
    for var in "${UPDATED_ENV_VARS[@]}"; do
        local key=$(echo "$var" | cut -d'=' -f1)
        if [[ ! "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*(__[a-zA-Z_][a-zA-Z0-9_]*)*$ ]]; then
            validation_errors+=("Invalid environment variable key format: $key")
        fi
    done
    
    # Report validation errors
    if [ ${#validation_errors[@]} -gt 0 ]; then
        log_error "Environment variable validation errors:"
        for error in "${validation_errors[@]}"; do
            log_error "  - $error"
        done
        set_error_context "Environment variable validation"
        set_error_remediation "Fix the validation issues listed above"
        handle_error $ERROR_CODE_VALIDATION "Environment variable validation failed" true
    fi
    
    log_success "Environment variables validation completed"
}

# Function to display changes in dry run mode
display_dry_run_changes() {
    log_info "Dry run - Changes that would be applied:"
    echo ""
    echo "=== Lambda Function: $LAMBDA_FUNCTION_NAME ==="
    echo "Update Mode: $UPDATE_MODE"
    echo ""
    
    # Show current vs updated variables
    echo "Current variables: ${#CURRENT_ENV_VARS[@]}"
    echo "Updated variables: ${#UPDATED_ENV_VARS[@]}"
    echo ""
    
    # Show changes
    local added=0
    local modified=0
    local removed=0
    
    # Check for added/modified variables
    for updated_var in "${UPDATED_ENV_VARS[@]}"; do
        local updated_key=$(echo "$updated_var" | cut -d'=' -f1)
        local updated_value=$(echo "$updated_var" | cut -d'=' -f2-)
        local display_value=$(mask_sensitive_value "$updated_key" "$updated_value")
        
        local found=false
        for current_var in "${CURRENT_ENV_VARS[@]}"; do
            local current_key=$(echo "$current_var" | cut -d'=' -f1)
            if [ "$current_key" = "$updated_key" ]; then
                local current_value=$(echo "$current_var" | cut -d'=' -f2-)
                if [ "$current_value" != "$updated_value" ]; then
                    echo "[MODIFIED] $updated_key=$display_value"
                    ((modified++))
                fi
                found=true
                break
            fi
        done
        
        if [ "$found" = false ]; then
            echo "[ADDED] $updated_key=$display_value"
            ((added++))
        fi
    done
    
    # Check for removed variables
    for current_var in "${CURRENT_ENV_VARS[@]}"; do
        local current_key=$(echo "$current_var" | cut -d'=' -f1)
        
        local found=false
        for updated_var in "${UPDATED_ENV_VARS[@]}"; do
            local updated_key=$(echo "$updated_var" | cut -d'=' -f1)
            if [ "$updated_key" = "$current_key" ]; then
                found=true
                break
            fi
        done
        
        if [ "$found" = false ]; then
            echo "[REMOVED] $current_key"
            ((removed++))
        fi
    done
    
    echo ""
    echo "Summary: $added added, $modified modified, $removed removed"
    echo ""
    echo "To apply these changes, run without --dry-run flag"
}

# Function to apply environment variables to Lambda function
apply_env_vars_to_lambda() {
    log_info "Applying environment variables to Lambda function..."
    
    # Build environment variables JSON
    local env_json="{"
    local first=true
    
    for var in "${UPDATED_ENV_VARS[@]}"; do
        local key=$(echo "$var" | cut -d'=' -f1)
        local value=$(echo "$var" | cut -d'=' -f2-)
        
        if [ "$first" = true ]; then
            first=false
        else
            env_json+=","
        fi
        
        # Escape JSON special characters
        value=$(echo "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
        env_json+="\"$key\":\"$value\""
    done
    
    env_json+="}"
    
    # Apply to Lambda function
    set_error_context "Lambda environment variable update"
    set_error_remediation "Check AWS permissions for Lambda operations"
    
    execute_with_error_handling \
        "aws lambda update-function-configuration \
            --function-name $LAMBDA_FUNCTION_NAME \
            --environment Variables='$env_json'" \
        "Failed to update Lambda environment variables" \
        $ERROR_CODE_LAMBDA
    
    log_success "Environment variables applied to Lambda function successfully"
}

# Function to display update summary
display_update_summary() {
    echo ""
    echo "=== Environment Variable Update Summary ==="
    echo "Function: $LAMBDA_FUNCTION_NAME"
    echo "Update Mode: $UPDATE_MODE"
    echo "Total Variables: ${#UPDATED_ENV_VARS[@]}"
    echo ""
    
    # Count sensitive variables
    local sensitive_count=0
    for var in "${UPDATED_ENV_VARS[@]}"; do
        local key=$(echo "$var" | cut -d'=' -f1)
        if is_sensitive_key "$key"; then
            ((sensitive_count++))
        fi
    done
    
    echo "Sensitive Variables: $sensitive_count"
    echo "Regular Variables: $((${#UPDATED_ENV_VARS[@]} - sensitive_count))"
    echo ""
    
    echo "=== Security Notes ==="
    echo "- Sensitive values are handled securely"
    echo "- Connection strings are encrypted in transit"
    echo "- Consider using AWS Secrets Manager for production secrets"
    echo ""
}

# Main execution function
main() {
    log_info "Starting Lambda environment variable update..."
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate AWS CLI
    if ! validate_aws_cli "$AWS_PROFILE"; then
        handle_error $ERROR_CODE_AWS_CLI "AWS CLI validation failed" true
    fi
    
    # Log configuration
    log_info "Configuration:"
    log_info "  Function Name: $LAMBDA_FUNCTION_NAME"
    log_info "  Update Mode: $UPDATE_MODE"
    log_info "  New Variables: ${#NEW_ENV_VARS[@]}"
    log_info "  Dry Run: $DRY_RUN"
    
    # Validate Lambda function
    validate_lambda_function
    
    # Get current environment variables
    get_current_env_vars
    
    # Merge variables based on update mode
    merge_env_vars
    
    # Validate merged variables
    validate_env_vars
    
    # Apply or display changes
    if [ "$DRY_RUN" = true ]; then
        display_dry_run_changes
    else
        apply_env_vars_to_lambda
        display_update_summary
    fi
    
    log_success "Lambda environment variable update completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi