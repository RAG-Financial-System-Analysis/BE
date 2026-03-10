#!/bin/bash

# Error Handling Framework
# Provides consistent error reporting and handling across all deployment scripts

# Source logging utility
UTILITIES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$UTILITIES_DIR/logging.sh"

# Error codes for consistent error identification (only declare if not already set)
if [ -z "${ERROR_CODE_GENERAL:-}" ]; then
    readonly ERROR_CODE_GENERAL=1
    readonly ERROR_CODE_AWS_CLI=2
    readonly ERROR_CODE_AWS_CREDENTIALS=3
    readonly ERROR_CODE_AWS_PERMISSIONS=4
    readonly ERROR_CODE_INFRASTRUCTURE=5
    readonly ERROR_CODE_DATABASE=6
    readonly ERROR_CODE_LAMBDA=7
    readonly ERROR_CODE_CONFIGURATION=8
    readonly ERROR_CODE_VALIDATION=9
    readonly ERROR_CODE_ROLLBACK=10
    readonly ERROR_CODE_NETWORK=11
    readonly ERROR_CODE_TIMEOUT=12
    readonly ERROR_CODE_RESOURCE_LIMIT=13
    readonly ERROR_CODE_DEPENDENCY=14
    readonly ERROR_CODE_MIGRATION=15
    readonly ERROR_CODE_DEPLOYMENT=16
    readonly ERROR_CODE_CLEANUP=17
    readonly ERROR_CODE_CHECKPOINT=18
fi

# Global variables for error tracking
ERROR_CONTEXT=""
ERROR_REMEDIATION=""
CLEANUP_FUNCTIONS=()
ERROR_LOG_FILE=""
DEPLOYMENT_STATE_FILE=""

# Initialize error logging
initialize_error_logging() {
    local log_dir="${LOG_DIR:-./logs}"
    mkdir -p "$log_dir"
    ERROR_LOG_FILE="$log_dir/deployment_errors_$(date +%Y%m%d_%H%M%S).log"
    DEPLOYMENT_STATE_FILE="$log_dir/deployment_state.json"
    
    # Create initial error log header
    {
        echo "=== DEPLOYMENT ERROR LOG ==="
        echo "Started: $(get_timestamp)"
        echo "Script: ${BASH_SOURCE[1]}"
        echo "Environment: ${ENVIRONMENT:-unknown}"
        echo "Mode: ${MODE:-unknown}"
        echo "=========================="
        echo ""
    } > "$ERROR_LOG_FILE"
    
    log_debug "Error logging initialized: $ERROR_LOG_FILE"
}

# Function to set error context for better error reporting
set_error_context() {
    ERROR_CONTEXT="$1"
    log_debug "Error context set: $ERROR_CONTEXT"
}

# Function to set remediation steps for errors
set_error_remediation() {
    ERROR_REMEDIATION="$1"
    log_debug "Error remediation set: $ERROR_REMEDIATION"
}

# Function to register cleanup functions
register_cleanup_function() {
    local cleanup_function="$1"
    CLEANUP_FUNCTIONS+=("$cleanup_function")
    log_debug "Registered cleanup function: $cleanup_function"
}

# Function to execute all registered cleanup functions
execute_cleanup() {
    if [ ${#CLEANUP_FUNCTIONS[@]} -gt 0 ]; then
        log_info "Executing cleanup functions..."
        for cleanup_function in "${CLEANUP_FUNCTIONS[@]}"; do
            log_debug "Executing cleanup function: $cleanup_function"
            if command -v "$cleanup_function" &> /dev/null; then
                "$cleanup_function" || log_warn "Cleanup function '$cleanup_function' failed"
            else
                log_warn "Cleanup function '$cleanup_function' not found"
            fi
        done
        log_info "Cleanup completed"
    fi
}

# Function to handle errors with context and remediation
handle_error() {
    local error_code="$1"
    local error_message="$2"
    local exit_script="${3:-true}"
    
    # Initialize error logging if not already done
    if [ -z "$ERROR_LOG_FILE" ]; then
        initialize_error_logging
    fi
    
    log_error "Error occurred (Code: $error_code): $error_message"
    
    if [ -n "$ERROR_CONTEXT" ]; then
        log_error "Context: $ERROR_CONTEXT"
    fi
    
    if [ -n "$ERROR_REMEDIATION" ]; then
        log_error "Remediation: $ERROR_REMEDIATION"
    fi
    
    # Get detailed error information
    local error_details=$(get_error_details "$error_code")
    if [ -n "$error_details" ]; then
        log_error "Details: $error_details"
    fi
    
    # Execute cleanup functions
    execute_cleanup
    
    # Log comprehensive error details to file for debugging
    {
        echo "=== ERROR REPORT ==="
        echo "Timestamp: $(get_timestamp)"
        echo "Error Code: $error_code"
        echo "Error Message: $error_message"
        echo "Context: $ERROR_CONTEXT"
        echo "Remediation: $ERROR_REMEDIATION"
        echo "Details: $error_details"
        echo "Script: ${BASH_SOURCE[1]}"
        echo "Function: ${FUNCNAME[1]}"
        echo "Line: ${BASH_LINENO[0]}"
        echo "Environment: ${ENVIRONMENT:-unknown}"
        echo "Mode: ${MODE:-unknown}"
        echo "Working Directory: $(pwd)"
        echo "User: $(whoami)"
        echo "System: $(uname -a)"
        echo "AWS Profile: ${AWS_PROFILE:-default}"
        echo "AWS Region: ${AWS_DEFAULT_REGION:-unknown}"
        echo "===================="
        echo ""
    } >> "$ERROR_LOG_FILE"
    
    # Update deployment state with error information
    update_deployment_state "error" "$error_code" "$error_message"
    
    if [ "$exit_script" = true ]; then
        log_error "Deployment failed. Check error log: $ERROR_LOG_FILE"
        exit "$error_code"
    fi
}

# Function to get detailed error information based on error code
get_error_details() {
    local error_code="$1"
    
    case "$error_code" in
        $ERROR_CODE_GENERAL)
            echo "General error occurred. Check logs for specific details."
            ;;
        $ERROR_CODE_AWS_CLI)
            echo "AWS CLI command failed. Verify AWS CLI installation and configuration."
            ;;
        $ERROR_CODE_AWS_CREDENTIALS)
            echo "AWS credentials issue. Run 'aws configure' or check AWS_PROFILE environment variable."
            ;;
        $ERROR_CODE_AWS_PERMISSIONS)
            echo "Insufficient AWS permissions. Contact AWS administrator or check IAM policies."
            ;;
        $ERROR_CODE_INFRASTRUCTURE)
            echo "Infrastructure provisioning failed. Check AWS service limits and existing resources."
            ;;
        $ERROR_CODE_DATABASE)
            echo "Database operation failed. Check RDS instance status and connectivity."
            ;;
        $ERROR_CODE_LAMBDA)
            echo "Lambda function operation failed. Check function configuration and deployment package."
            ;;
        $ERROR_CODE_CONFIGURATION)
            echo "Configuration error. Verify appsettings.json and environment variables."
            ;;
        $ERROR_CODE_VALIDATION)
            echo "Validation failed. Check input parameters and required dependencies."
            ;;
        $ERROR_CODE_ROLLBACK)
            echo "Rollback operation failed. Manual cleanup may be required."
            ;;
        $ERROR_CODE_NETWORK)
            echo "Network connectivity issue. Check VPC configuration and security groups."
            ;;
        $ERROR_CODE_TIMEOUT)
            echo "Operation timed out. Check resource availability and network connectivity."
            ;;
        $ERROR_CODE_RESOURCE_LIMIT)
            echo "AWS resource limit exceeded. Request limit increase or clean up existing resources."
            ;;
        $ERROR_CODE_DEPENDENCY)
            echo "Dependency not found or incompatible. Check required tools and versions."
            ;;
        $ERROR_CODE_MIGRATION)
            echo "Database migration failed. Check migration scripts and database connectivity."
            ;;
        $ERROR_CODE_DEPLOYMENT)
            echo "Deployment operation failed. Check deployment package and target configuration."
            ;;
        $ERROR_CODE_CLEANUP)
            echo "Cleanup operation failed. Some resources may need manual removal."
            ;;
        $ERROR_CODE_CHECKPOINT)
            echo "Checkpoint operation failed. Recovery state may be inconsistent."
            ;;
        *)
            echo "Unknown error code: $error_code"
            ;;
    esac
}

# Function to update deployment state for recovery purposes
update_deployment_state() {
    local state="$1"
    local error_code="${2:-}"
    local error_message="${3:-}"
    
    if [ -z "$DEPLOYMENT_STATE_FILE" ]; then
        initialize_error_logging
    fi
    
    local timestamp=$(get_timestamp)
    local state_data="{
        \"timestamp\": \"$timestamp\",
        \"state\": \"$state\",
        \"environment\": \"${ENVIRONMENT:-unknown}\",
        \"mode\": \"${MODE:-unknown}\",
        \"error_code\": \"$error_code\",
        \"error_message\": \"$error_message\",
        \"context\": \"$ERROR_CONTEXT\",
        \"remediation\": \"$ERROR_REMEDIATION\"
    }"
    
    echo "$state_data" > "$DEPLOYMENT_STATE_FILE"
    log_debug "Deployment state updated: $state"
}

# Function to get current deployment state
get_deployment_state() {
    if [ -f "$DEPLOYMENT_STATE_FILE" ]; then
        cat "$DEPLOYMENT_STATE_FILE"
    else
        echo "{\"state\": \"unknown\"}"
    fi
}

# Function to handle AWS CLI errors with enhanced error parsing
handle_aws_error() {
    local aws_command="$1"
    local error_output="$2"
    
    set_error_context "AWS CLI command failed: $aws_command"
    
    # Parse common AWS error patterns and provide specific remediation
    if echo "$error_output" | grep -q "InvalidUserID.NotFound"; then
        set_error_remediation "Check AWS credentials and ensure the user/role exists. Run 'aws sts get-caller-identity' to verify."
        handle_error $ERROR_CODE_AWS_CREDENTIALS "AWS user/role not found" true
    elif echo "$error_output" | grep -q "UnauthorizedOperation"; then
        set_error_remediation "Check IAM permissions for the operation: $aws_command. Contact AWS administrator for required policies."
        handle_error $ERROR_CODE_AWS_PERMISSIONS "Insufficient AWS permissions" true
    elif echo "$error_output" | grep -q "InvalidParameterValue"; then
        set_error_remediation "Check command parameters and AWS resource limits. Verify parameter values match AWS requirements."
        handle_error $ERROR_CODE_VALIDATION "Invalid AWS parameter value" true
    elif echo "$error_output" | grep -q "ResourceAlreadyExists"; then
        set_error_remediation "Resource already exists. Use update mode or delete existing resource first."
        handle_error $ERROR_CODE_INFRASTRUCTURE "AWS resource already exists" true
    elif echo "$error_output" | grep -q "LimitExceeded"; then
        set_error_remediation "AWS service limit exceeded. Request limit increase through AWS Support or clean up existing resources."
        handle_error $ERROR_CODE_RESOURCE_LIMIT "AWS service limit exceeded" true
    elif echo "$error_output" | grep -q "Throttling"; then
        set_error_remediation "AWS API throttling detected. Wait a few minutes and retry the operation."
        handle_error $ERROR_CODE_TIMEOUT "AWS API throttling" true
    elif echo "$error_output" | grep -q "NetworkError\|ConnectTimeoutError"; then
        set_error_remediation "Network connectivity issue. Check internet connection and AWS service status."
        handle_error $ERROR_CODE_NETWORK "Network connectivity error" true
    elif echo "$error_output" | grep -q "NoCredentialsError"; then
        set_error_remediation "AWS credentials not configured. Please configure using one of these methods:
        
Method 1 - AWS CLI configure:
  aws configure

Method 2 - Environment variables:
  export AWS_ACCESS_KEY_ID=your-access-key
  export AWS_SECRET_ACCESS_KEY=your-secret-key
  export AWS_DEFAULT_REGION=ap-southeast-1

Method 3 - AWS Profile:
  export AWS_PROFILE=your-profile-name

Method 4 - Check existing credentials:
  aws sts get-caller-identity"
        handle_error $ERROR_CODE_AWS_CREDENTIALS "AWS credentials not found" true
    else
        set_error_remediation "Check AWS CLI configuration, network connectivity, and service status at https://status.aws.amazon.com/"
        handle_error $ERROR_CODE_AWS_CLI "AWS CLI command failed: $error_output" true
    fi
}

# Function to validate required environment variables
validate_required_vars() {
    local required_vars=("$@")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        local missing_list=$(IFS=', '; echo "${missing_vars[*]}")
        set_error_context "Required environment variables validation"
        set_error_remediation "Set the following environment variables: $missing_list"
        handle_error $ERROR_CODE_VALIDATION "Missing required environment variables: $missing_list" true
    fi
}

# Function to validate file existence
validate_file_exists() {
    local file_path="$1"
    local file_description="${2:-file}"
    
    if [ ! -f "$file_path" ]; then
        set_error_context "File validation"
        set_error_remediation "Ensure the $file_description exists at: $file_path"
        handle_error $ERROR_CODE_VALIDATION "$file_description not found: $file_path" true
    fi
}

# Function to validate directory existence
validate_directory_exists() {
    local dir_path="$1"
    local dir_description="${2:-directory}"
    
    if [ ! -d "$dir_path" ]; then
        set_error_context "Directory validation"
        set_error_remediation "Ensure the $dir_description exists at: $dir_path"
        handle_error $ERROR_CODE_VALIDATION "$dir_description not found: $dir_path" true
    fi
}

# Function to execute command with error handling
execute_with_error_handling() {
    local command="$1"
    local error_message="$2"
    local error_code="${3:-$ERROR_CODE_GENERAL}"
    
    log_debug "Executing command: $command"
    
    local output
    local exit_code
    
    # Execute command and capture output and exit code
    output=$(eval "$command" 2>&1)
    exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_error "Command failed with exit code $exit_code: $command"
        log_error "Command output: $output"
        
        # Handle AWS CLI specific errors
        if echo "$command" | grep -q "^aws "; then
            handle_aws_error "$command" "$output"
        else
            set_error_context "Command execution"
            set_error_remediation "$error_message"
            handle_error "$error_code" "Command failed: $command" true
        fi
    fi
    
    echo "$output"
    return $exit_code
}

# Function to create error recovery checkpoint
create_checkpoint() {
    local checkpoint_name="$1"
    local checkpoint_data="$2"
    
    local checkpoint_dir="./deployment_checkpoints"
    mkdir -p "$checkpoint_dir"
    
    local checkpoint_file="$checkpoint_dir/${checkpoint_name}.checkpoint"
    echo "$checkpoint_data" > "$checkpoint_file"
    
    log_info "Created checkpoint: $checkpoint_name"
    log_debug "Checkpoint data saved to: $checkpoint_file"
}

# Function to restore from error recovery checkpoint
restore_checkpoint() {
    local checkpoint_name="$1"
    local checkpoint_file="./deployment_checkpoints/${checkpoint_name}.checkpoint"
    
    if [ -f "$checkpoint_file" ]; then
        log_info "Restoring from checkpoint: $checkpoint_name"
        cat "$checkpoint_file"
        return 0
    else
        log_warn "Checkpoint not found: $checkpoint_name"
        return 1
    fi
}

# Function to clean up checkpoints
cleanup_checkpoints() {
    local checkpoint_dir="./deployment_checkpoints"
    if [ -d "$checkpoint_dir" ]; then
        log_info "Cleaning up deployment checkpoints..."
        rm -rf "$checkpoint_dir"
        log_success "Deployment checkpoints cleaned up"
    fi
}

# Trap to handle script interruption and cleanup
trap 'handle_error $ERROR_CODE_GENERAL "Script interrupted" true' INT TERM

# Export functions and constants for use in other scripts
export -f set_error_context set_error_remediation register_cleanup_function
export -f execute_cleanup handle_error handle_aws_error get_error_details
export -f validate_required_vars validate_file_exists validate_directory_exists
export -f execute_with_error_handling create_checkpoint restore_checkpoint cleanup_checkpoints
export -f initialize_error_logging update_deployment_state get_deployment_state

export ERROR_CODE_GENERAL ERROR_CODE_AWS_CLI ERROR_CODE_AWS_CREDENTIALS
export ERROR_CODE_AWS_PERMISSIONS ERROR_CODE_INFRASTRUCTURE ERROR_CODE_DATABASE
export ERROR_CODE_LAMBDA ERROR_CODE_CONFIGURATION ERROR_CODE_VALIDATION ERROR_CODE_ROLLBACK
export ERROR_CODE_NETWORK ERROR_CODE_TIMEOUT ERROR_CODE_RESOURCE_LIMIT ERROR_CODE_DEPENDENCY
export ERROR_CODE_MIGRATION ERROR_CODE_DEPLOYMENT ERROR_CODE_CLEANUP ERROR_CODE_CHECKPOINT