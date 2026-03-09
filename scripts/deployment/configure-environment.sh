#!/bin/bash

# Configuration Conversion Utility
# Converts appsettings.json to Lambda environment variables
# Implements nested configuration key flattening (e.g., AWS__Region)
# Validates configuration and provides error reporting
# Preserves all existing configuration sections

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILITIES_DIR="$SCRIPT_DIR/../utilities"
source "$UTILITIES_DIR/logging.sh"
source "$UTILITIES_DIR/error-handling.sh"
source "$UTILITIES_DIR/validate-aws-cli.sh"

# Default configuration values
DEFAULT_CONFIG_FILE="code/TestDeployLambda/BE/RAG.APIs/appsettings.json"
DEFAULT_ENVIRONMENT_FILE="code/TestDeployLambda/BE/RAG.APIs/appsettings.Development.json"

# Configuration variables
CONFIG_FILE="${CONFIG_FILE:-$DEFAULT_CONFIG_FILE}"
ENVIRONMENT_FILE="${ENVIRONMENT_FILE:-$DEFAULT_ENVIRONMENT_FILE}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-lambda}"  # lambda, env, json
DRY_RUN="${DRY_RUN:-false}"

# Resource naming
ENVIRONMENT="${ENVIRONMENT:-dev}"
PROJECT_NAME="${PROJECT_NAME:-myapp}"
LAMBDA_FUNCTION_NAME="$PROJECT_NAME-$ENVIRONMENT-api"

# Global variables
CONVERTED_VARS=()
SENSITIVE_KEYS=("password" "secret" "key" "token" "connectionstring")
VALIDATION_ERRORS=()

# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Converts appsettings.json configuration to Lambda environment variables with nested key flattening.

OPTIONS:
    --config-file FILE         Path to appsettings.json (default: $DEFAULT_CONFIG_FILE)
    --environment-file FILE    Path to appsettings.{env}.json (default: $DEFAULT_ENVIRONMENT_FILE)
    --function-name NAME       Lambda function name (default: $PROJECT_NAME-$ENVIRONMENT-api)
    --environment ENV          Environment name (default: dev)
    --project-name NAME        Project name (default: myapp)
    --output-format FORMAT     Output format: lambda, env, json (default: lambda)
    --dry-run                  Show converted variables without applying them
    --aws-profile PROFILE      AWS profile to use
    --help                     Show this help message

OUTPUT FORMATS:
    lambda    - Apply directly to Lambda function environment variables
    env       - Output as shell environment variable exports
    json      - Output as JSON object

EXAMPLES:
    # Convert and apply to Lambda function
    $0 --function-name webapp-prod-api

    # Dry run to see converted variables
    $0 --dry-run --output-format env

    # Convert custom configuration files
    $0 --config-file custom-appsettings.json --environment-file custom-appsettings.prod.json

    # Output as JSON for further processing
    $0 --output-format json > lambda-env-vars.json

CONFIGURATION FLATTENING:
    Nested JSON keys are flattened using double underscores (__):
    
    Input JSON:
    {
      "ConnectionStrings": {
        "DefaultConnection": "..."
      },
      "AWS": {
        "Region": "us-east-1",
        "UserPoolId": "..."
      }
    }
    
    Output Environment Variables:
    ConnectionStrings__DefaultConnection=...
    AWS__Region=us-east-1
    AWS__UserPoolId=...

SECURITY NOTES:
    - Sensitive values (passwords, keys, tokens) are handled securely
    - Connection strings are automatically detected as sensitive
    - Use AWS Secrets Manager for production secrets

EOF
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config-file)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --environment-file)
                ENVIRONMENT_FILE="$2"
                shift 2
                ;;
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
            --output-format)
                OUTPUT_FORMAT="$2"
                shift 2
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
}

# Function to validate configuration files
validate_config_files() {
    log_info "Validating configuration files..."
    
    # Check main configuration file
    validate_file_exists "$CONFIG_FILE" "main configuration file"
    
    # Check if it's valid JSON
    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        set_error_context "Configuration file validation"
        set_error_remediation "Ensure $CONFIG_FILE contains valid JSON"
        handle_error $ERROR_CODE_VALIDATION "Invalid JSON in configuration file: $CONFIG_FILE" true
    fi
    
    # Check environment-specific file (optional)
    if [ -f "$ENVIRONMENT_FILE" ]; then
        log_info "Found environment-specific configuration: $ENVIRONMENT_FILE"
        if ! jq empty "$ENVIRONMENT_FILE" 2>/dev/null; then
            set_error_context "Environment configuration file validation"
            set_error_remediation "Ensure $ENVIRONMENT_FILE contains valid JSON"
            handle_error $ERROR_CODE_VALIDATION "Invalid JSON in environment configuration file: $ENVIRONMENT_FILE" true
        fi
    else
        log_info "No environment-specific configuration found (optional): $ENVIRONMENT_FILE"
    fi
    
    log_success "Configuration files validated"
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

# Function to flatten JSON recursively
flatten_json() {
    local json_file="$1"
    local prefix="${2:-}"
    
    # Use jq to flatten the JSON with proper key formatting
    jq -r --arg prefix "$prefix" '
        def flatten($prefix):
            . as $in
            | reduce paths(scalars) as $path (
                {};
                . + {
                    ($prefix + ($path | map(tostring) | join("__"))): ($in | getpath($path))
                }
            );
        flatten($prefix) | to_entries[] | "\(.key)=\(.value)"
    ' "$json_file"
}

# Function to merge configuration files
merge_configurations() {
    log_info "Merging configuration files..."
    
    local temp_merged="/tmp/merged-config.json"
    
    if [ -f "$ENVIRONMENT_FILE" ]; then
        # Merge base config with environment-specific config
        # Environment-specific values override base values
        jq -s '.[0] * .[1]' "$CONFIG_FILE" "$ENVIRONMENT_FILE" > "$temp_merged"
        log_info "Merged base and environment-specific configurations"
    else
        # Use only base configuration
        cp "$CONFIG_FILE" "$temp_merged"
        log_info "Using base configuration only"
    fi
    
    echo "$temp_merged"
}

# Function to convert configuration to environment variables
convert_to_env_vars() {
    log_info "Converting configuration to environment variables..."
    
    local merged_config=$(merge_configurations)
    local flattened_vars
    
    # Flatten the merged configuration
    flattened_vars=$(flatten_json "$merged_config")
    
    # Process each variable
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            local key=$(echo "$line" | cut -d'=' -f1)
            local value=$(echo "$line" | cut -d'=' -f2-)
            
            # Skip empty values
            if [ -z "$value" ] || [ "$value" = "null" ]; then
                log_debug "Skipping empty value for key: $key"
                continue
            fi
            
            # Remove quotes from JSON string values
            value=$(echo "$value" | sed 's/^"//;s/"$//')
            
            # Validate key format
            if [[ ! "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*(__[a-zA-Z_][a-zA-Z0-9_]*)*$ ]]; then
                VALIDATION_ERRORS+=("Invalid environment variable key format: $key")
                continue
            fi
            
            # Check for sensitive data
            local is_sensitive=false
            if is_sensitive_key "$key"; then
                is_sensitive=true
                log_debug "Detected sensitive key: $key"
            fi
            
            # Store the converted variable
            CONVERTED_VARS+=("$key=$value")
            
            if [ "$is_sensitive" = true ]; then
                log_debug "Added sensitive variable: $key=***"
            else
                log_debug "Added variable: $key=$value"
            fi
        fi
    done <<< "$flattened_vars"
    
    # Clean up temporary file
    rm -f "$merged_config"
    
    log_success "Configuration converted to ${#CONVERTED_VARS[@]} environment variables"
}

# Function to validate converted variables
validate_converted_vars() {
    log_info "Validating converted environment variables..."
    
    # Check for required variables
    local required_vars=("ASPNETCORE_ENVIRONMENT")
    local missing_required=()
    
    for required in "${required_vars[@]}"; do
        local found=false
        for var in "${CONVERTED_VARS[@]}"; do
            if [[ "$var" == "$required="* ]]; then
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            missing_required+=("$required")
        fi
    done
    
    # Add ASPNETCORE_ENVIRONMENT if missing
    if [[ " ${missing_required[@]} " =~ " ASPNETCORE_ENVIRONMENT " ]]; then
        log_info "Adding missing ASPNETCORE_ENVIRONMENT=$ENVIRONMENT"
        CONVERTED_VARS+=("ASPNETCORE_ENVIRONMENT=$ENVIRONMENT")
    fi
    
    # Check for duplicate keys
    local keys=()
    for var in "${CONVERTED_VARS[@]}"; do
        local key=$(echo "$var" | cut -d'=' -f1)
        if [[ " ${keys[@]} " =~ " $key " ]]; then
            VALIDATION_ERRORS+=("Duplicate environment variable key: $key")
        else
            keys+=("$key")
        fi
    done
    
    # Report validation errors
    if [ ${#VALIDATION_ERRORS[@]} -gt 0 ]; then
        log_error "Configuration validation errors found:"
        for error in "${VALIDATION_ERRORS[@]}"; do
            log_error "  - $error"
        done
        set_error_context "Configuration validation"
        set_error_remediation "Fix the configuration issues listed above"
        handle_error $ERROR_CODE_VALIDATION "Configuration validation failed" true
    fi
    
    log_success "Environment variables validation completed"
}

# Function to output variables in different formats
output_variables() {
    case "$OUTPUT_FORMAT" in
        "env")
            output_env_format
            ;;
        "json")
            output_json_format
            ;;
        "lambda")
            if [ "$DRY_RUN" = true ]; then
                output_lambda_format_dry_run
            else
                apply_to_lambda_function
            fi
            ;;
        *)
            log_error "Invalid output format: $OUTPUT_FORMAT"
            show_usage
            exit 1
            ;;
    esac
}

# Function to output in shell environment format
output_env_format() {
    log_info "Outputting environment variables in shell format:"
    echo ""
    echo "# Environment variables converted from appsettings.json"
    echo "# Generated on $(date)"
    echo ""
    
    for var in "${CONVERTED_VARS[@]}"; do
        local key=$(echo "$var" | cut -d'=' -f1)
        local value=$(echo "$var" | cut -d'=' -f2-)
        
        # Escape special characters for shell
        value=$(printf '%q' "$value")
        
        if is_sensitive_key "$key"; then
            echo "export $key=*** # Sensitive value hidden"
        else
            echo "export $key=$value"
        fi
    done
    echo ""
}

# Function to output in JSON format
output_json_format() {
    log_info "Outputting environment variables in JSON format:"
    echo ""
    echo "{"
    
    local first=true
    for var in "${CONVERTED_VARS[@]}"; do
        local key=$(echo "$var" | cut -d'=' -f1)
        local value=$(echo "$var" | cut -d'=' -f2-)
        
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        
        # Escape JSON special characters
        value=$(echo "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
        
        if is_sensitive_key "$key"; then
            echo -n "  \"$key\": \"*** Sensitive value hidden ***\""
        else
            echo -n "  \"$key\": \"$value\""
        fi
    done
    
    echo ""
    echo "}"
    echo ""
}

# Function to show Lambda format in dry run
output_lambda_format_dry_run() {
    log_info "Lambda environment variables (dry run):"
    echo ""
    echo "The following environment variables would be applied to Lambda function: $LAMBDA_FUNCTION_NAME"
    echo ""
    
    for var in "${CONVERTED_VARS[@]}"; do
        local key=$(echo "$var" | cut -d'=' -f1)
        local value=$(echo "$var" | cut -d'=' -f2-)
        
        if is_sensitive_key "$key"; then
            echo "  $key=*** (sensitive value hidden)"
        else
            echo "  $key=$value"
        fi
    done
    
    echo ""
    echo "Total variables: ${#CONVERTED_VARS[@]}"
    echo ""
    echo "To apply these variables, run without --dry-run flag"
}

# Function to apply variables to Lambda function
apply_to_lambda_function() {
    log_info "Applying environment variables to Lambda function: $LAMBDA_FUNCTION_NAME"
    
    # Check if Lambda function exists
    if ! aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        set_error_context "Lambda function validation"
        set_error_remediation "Ensure Lambda function exists or run provision-lambda.sh first"
        handle_error $ERROR_CODE_LAMBDA "Lambda function not found: $LAMBDA_FUNCTION_NAME" true
    fi
    
    # Build environment variables JSON
    local env_json="{"
    local first=true
    
    for var in "${CONVERTED_VARS[@]}"; do
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
    
    # Display summary
    echo ""
    echo "=== Environment Variables Applied ==="
    echo "Function: $LAMBDA_FUNCTION_NAME"
    echo "Total variables: ${#CONVERTED_VARS[@]}"
    echo ""
    
    local sensitive_count=0
    for var in "${CONVERTED_VARS[@]}"; do
        local key=$(echo "$var" | cut -d'=' -f1)
        if is_sensitive_key "$key"; then
            ((sensitive_count++))
        fi
    done
    
    echo "Sensitive variables: $sensitive_count"
    echo "Regular variables: $((${#CONVERTED_VARS[@]} - sensitive_count))"
    echo ""
}

# Function to display configuration summary
display_config_summary() {
    log_info "Configuration conversion summary:"
    echo ""
    echo "=== Configuration Files ==="
    echo "Base config: $CONFIG_FILE"
    if [ -f "$ENVIRONMENT_FILE" ]; then
        echo "Environment config: $ENVIRONMENT_FILE"
    else
        echo "Environment config: None (using base only)"
    fi
    echo ""
    echo "=== Conversion Results ==="
    echo "Total variables: ${#CONVERTED_VARS[@]}"
    echo "Output format: $OUTPUT_FORMAT"
    echo "Dry run: $DRY_RUN"
    echo ""
    
    if [ ${#VALIDATION_ERRORS[@]} -gt 0 ]; then
        echo "=== Validation Errors ==="
        for error in "${VALIDATION_ERRORS[@]}"; do
            echo "  - $error"
        done
        echo ""
    fi
}

# Main execution function
main() {
    log_info "Starting configuration conversion..."
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate AWS CLI if needed
    if [ "$OUTPUT_FORMAT" = "lambda" ] && [ "$DRY_RUN" = false ]; then
        if ! validate_aws_cli "$AWS_PROFILE"; then
            handle_error $ERROR_CODE_AWS_CLI "AWS CLI validation failed" true
        fi
    fi
    
    # Log configuration
    log_info "Configuration:"
    log_info "  Config file: $CONFIG_FILE"
    log_info "  Environment file: $ENVIRONMENT_FILE"
    log_info "  Function name: $LAMBDA_FUNCTION_NAME"
    log_info "  Output format: $OUTPUT_FORMAT"
    log_info "  Dry run: $DRY_RUN"
    
    # Validate configuration files
    validate_config_files
    
    # Convert configuration
    convert_to_env_vars
    validate_converted_vars
    
    # Output results
    output_variables
    
    # Display summary
    display_config_summary
    
    log_success "Configuration conversion completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi