#!/bin/bash

# Configuration Loading Utility
# Loads deployment configuration from deployment-config.env file
# Provides validation and default values

# Source logging utility
UTILITIES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$UTILITIES_DIR/logging.sh"

# Default configuration file path
DEFAULT_CONFIG_FILE="./deployment-config.env"
CONFIG_FILE="${CONFIG_FILE:-$DEFAULT_CONFIG_FILE}"

# Function to load deployment configuration
load_deployment_config() {
    local config_file="${1:-$CONFIG_FILE}"
    
    log_info "Loading deployment configuration..."
    
    # Check if config file exists
    if [[ ! -f "$config_file" ]]; then
        log_warn "Configuration file not found: $config_file"
        log_info "Creating default configuration file..."
        create_default_config "$config_file"
    fi
    
    # Load configuration file
    log_debug "Loading configuration from: $config_file"
    
    # Source the config file, ignoring comments and empty lines
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
            continue
        fi
        
        # Export the variable
        if [[ "$line" =~ ^[[:space:]]*([A-Z_][A-Z0-9_]*)=(.*)$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local var_value="${BASH_REMATCH[2]}"
            
            # Remove quotes if present
            var_value=$(echo "$var_value" | sed 's/^["'\'']\|["'\'']$//g')
            
            # Export the variable
            export "$var_name"="$var_value"
            log_debug "Loaded: $var_name=$var_value"
        fi
    done < "$config_file"
    
    # Validate and set defaults
    validate_and_set_defaults
    
    log_success "Configuration loaded successfully"
    log_info "Environment: $ENVIRONMENT, Project: $PROJECT_NAME, Region: $AWS_DEFAULT_REGION"
}

# Function to validate configuration and set defaults
validate_and_set_defaults() {
    log_debug "Validating configuration and setting defaults..."
    
    # Basic deployment settings
    export ENVIRONMENT="${ENVIRONMENT:-dev}"
    export PROJECT_NAME="${PROJECT_NAME:-myragapp}"
    export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-southeast-1}"
    
    # Lambda configuration
    export LAMBDA_RUNTIME="${LAMBDA_RUNTIME:-dotnet10}"
    export LAMBDA_MEMORY_SIZE="${LAMBDA_MEMORY_SIZE:-512}"
    export LAMBDA_TIMEOUT="${LAMBDA_TIMEOUT:-30}"
    export LAMBDA_HANDLER="${LAMBDA_HANDLER:-RAG.APIs::RAG.APIs.LambdaEntryPoint::FunctionHandlerAsync}"
    
    # RDS configuration
    export RDS_INSTANCE_CLASS="${RDS_INSTANCE_CLASS:-db.t3.micro}"
    export RDS_ALLOCATED_STORAGE="${RDS_ALLOCATED_STORAGE:-20}"
    export RDS_MAX_ALLOCATED_STORAGE="${RDS_MAX_ALLOCATED_STORAGE:-100}"
    export RDS_ENGINE_VERSION="${RDS_ENGINE_VERSION:-15.4}"
    export RDS_BACKUP_RETENTION_PERIOD="${RDS_BACKUP_RETENTION_PERIOD:-7}"
    export RDS_MULTI_AZ="${RDS_MULTI_AZ:-false}"
    export RDS_STORAGE_ENCRYPTED="${RDS_STORAGE_ENCRYPTED:-true}"
    export RDS_PUBLICLY_ACCESSIBLE="${RDS_PUBLICLY_ACCESSIBLE:-true}"
    
    # API Gateway configuration
    export API_GATEWAY_STAGE="${API_GATEWAY_STAGE:-production}"
    export API_GATEWAY_DESCRIPTION="${API_GATEWAY_DESCRIPTION:-RAG System API Gateway}"
    export API_GATEWAY_LOGGING_ENABLED="${API_GATEWAY_LOGGING_ENABLED:-true}"
    export API_GATEWAY_THROTTLE_RATE="${API_GATEWAY_THROTTLE_RATE:-1000}"
    export API_GATEWAY_THROTTLE_BURST="${API_GATEWAY_THROTTLE_BURST:-2000}"
    
    # Deployment options
    export SKIP_TESTS="${SKIP_TESTS:-false}"
    export SKIP_SEEDING="${SKIP_SEEDING:-false}"
    export SKIP_CLEANUP="${SKIP_CLEANUP:-false}"
    export VERBOSE_LOGGING="${VERBOSE_LOGGING:-false}"
    
    # Cost optimization
    export AUTO_CLEANUP_RESOURCES="${AUTO_CLEANUP_RESOURCES:-false}"
    export USE_SPOT_INSTANCES="${USE_SPOT_INSTANCES:-false}"
    
    # Security settings
    export ENABLE_VPC="${ENABLE_VPC:-false}"
    export VPC_CIDR_BLOCK="${VPC_CIDR_BLOCK:-10.0.0.0/16}"
    export RDS_SSL_ENABLED="${RDS_SSL_ENABLED:-true}"
    
    # Monitoring and logging
    export CLOUDWATCH_LOG_RETENTION_DAYS="${CLOUDWATCH_LOG_RETENTION_DAYS:-14}"
    export ENABLE_DETAILED_MONITORING="${ENABLE_DETAILED_MONITORING:-false}"
    export ENABLE_XRAY_TRACING="${ENABLE_XRAY_TRACING:-false}"
    
    # Advanced settings
    export CUSTOM_DOMAIN_NAME="${CUSTOM_DOMAIN_NAME:-}"
    export SSL_CERTIFICATE_ARN="${SSL_CERTIFICATE_ARN:-}"
    export CUSTOM_TAGS="${CUSTOM_TAGS:-Environment=$ENVIRONMENT,Project=$PROJECT_NAME}"
    
    # Validate critical settings
    validate_critical_settings
}

# Function to validate critical configuration settings
validate_critical_settings() {
    local validation_errors=()
    
    # Validate environment
    if [[ ! "$ENVIRONMENT" =~ ^(dev|development|staging|stage|prod|production)$ ]]; then
        validation_errors+=("Invalid ENVIRONMENT: $ENVIRONMENT (must be: dev, development, staging, stage, prod, production)")
    fi
    
    # Validate project name
    if [[ ! "$PROJECT_NAME" =~ ^[a-z0-9-]+$ ]]; then
        validation_errors+=("Invalid PROJECT_NAME: $PROJECT_NAME (must contain only lowercase letters, numbers, and hyphens)")
    fi
    
    # Validate AWS region
    if [[ ! "$AWS_DEFAULT_REGION" =~ ^[a-z]{2,3}-[a-z]+-[0-9]+$ ]]; then
        validation_errors+=("Invalid AWS_DEFAULT_REGION: $AWS_DEFAULT_REGION (must be valid AWS region format)")
    fi
    
    # Validate Lambda memory size
    if [[ ! "$LAMBDA_MEMORY_SIZE" =~ ^[0-9]+$ ]] || [[ "$LAMBDA_MEMORY_SIZE" -lt 128 ]] || [[ "$LAMBDA_MEMORY_SIZE" -gt 10240 ]]; then
        validation_errors+=("Invalid LAMBDA_MEMORY_SIZE: $LAMBDA_MEMORY_SIZE (must be between 128 and 10240 MB)")
    fi
    
    # Validate Lambda timeout
    if [[ ! "$LAMBDA_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$LAMBDA_TIMEOUT" -lt 1 ]] || [[ "$LAMBDA_TIMEOUT" -gt 900 ]]; then
        validation_errors+=("Invalid LAMBDA_TIMEOUT: $LAMBDA_TIMEOUT (must be between 1 and 900 seconds)")
    fi
    
    # Validate RDS allocated storage
    if [[ ! "$RDS_ALLOCATED_STORAGE" =~ ^[0-9]+$ ]] || [[ "$RDS_ALLOCATED_STORAGE" -lt 20 ]]; then
        validation_errors+=("Invalid RDS_ALLOCATED_STORAGE: $RDS_ALLOCATED_STORAGE (must be at least 20 GB)")
    fi
    
    # Report validation errors
    if [[ ${#validation_errors[@]} -gt 0 ]]; then
        log_error "Configuration validation failed:"
        for error in "${validation_errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi
    
    log_debug "Configuration validation passed"
    return 0
}

# Function to create default configuration file
create_default_config() {
    local config_file="$1"
    
    log_info "Creating default configuration file: $config_file"
    
    # Copy from the template if it exists, otherwise create basic config
    if [[ -f "./deployment-config.env" ]]; then
        cp "./deployment-config.env" "$config_file"
    else
        cat > "$config_file" << 'EOF'
# RAG System Deployment Configuration
# Basic configuration - modify as needed

# Basic settings
ENVIRONMENT=dev
PROJECT_NAME=myapp
AWS_DEFAULT_REGION=ap-southeast-1

# Lambda settings
LAMBDA_RUNTIME=dotnet10
LAMBDA_MEMORY_SIZE=512
LAMBDA_TIMEOUT=30

# RDS settings
RDS_INSTANCE_CLASS=db.t3.micro
RDS_ALLOCATED_STORAGE=20

# Deployment options
SKIP_TESTS=false
SKIP_SEEDING=false
EOF
    fi
    
    log_success "Default configuration file created: $config_file"
}

# Function to display current configuration
show_deployment_config() {
    log_info "Current Deployment Configuration:"
    echo ""
    echo "=== Basic Settings ==="
    echo "Environment: $ENVIRONMENT"
    echo "Project Name: $PROJECT_NAME"
    echo "AWS Region: $AWS_DEFAULT_REGION"
    echo ""
    echo "=== Lambda Configuration ==="
    echo "Runtime: $LAMBDA_RUNTIME"
    echo "Memory: ${LAMBDA_MEMORY_SIZE}MB"
    echo "Timeout: ${LAMBDA_TIMEOUT}s"
    echo "Handler: $LAMBDA_HANDLER"
    echo ""
    echo "=== RDS Configuration ==="
    echo "Instance Class: $RDS_INSTANCE_CLASS"
    echo "Storage: ${RDS_ALLOCATED_STORAGE}GB"
    echo "Multi-AZ: $RDS_MULTI_AZ"
    echo "Publicly Accessible: $RDS_PUBLICLY_ACCESSIBLE"
    echo ""
    echo "=== API Gateway Configuration ==="
    echo "Stage: $API_GATEWAY_STAGE"
    echo "Throttle Rate: $API_GATEWAY_THROTTLE_RATE req/s"
    echo "Throttle Burst: $API_GATEWAY_THROTTLE_BURST"
    echo ""
    echo "=== Deployment Options ==="
    echo "Skip Tests: $SKIP_TESTS"
    echo "Skip Seeding: $SKIP_SEEDING"
    echo "Verbose Logging: $VERBOSE_LOGGING"
    echo ""
}

# Function to validate configuration file
validate_config_file() {
    local config_file="${1:-$CONFIG_FILE}"
    
    log_info "Validating configuration file: $config_file"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Load and validate
    if load_deployment_config "$config_file"; then
        log_success "Configuration file is valid"
        show_deployment_config
        return 0
    else
        log_error "Configuration file validation failed"
        return 1
    fi
}

# Export functions for use in other scripts
export -f load_deployment_config validate_and_set_defaults validate_critical_settings
export -f create_default_config show_deployment_config validate_config_file