#!/bin/bash

# Configuration Management Script
# Helps manage deployment configuration files

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILITIES_DIR="$SCRIPT_DIR/utilities"
source "$UTILITIES_DIR/logging.sh"
source "$UTILITIES_DIR/load-config.sh"

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Manages deployment configuration files for the RAG System.

COMMANDS:
    show                      Display current configuration
    validate                  Validate configuration file
    create                    Create new configuration file
    copy                      Copy configuration to new file
    edit                      Open configuration file in editor
    compare                   Compare two configuration files
    help                      Show this help message

OPTIONS:
    --config FILE            Configuration file path (default: ./deployment-config.env)
    --output FILE            Output file path (for create/copy commands)
    --template TYPE          Template type for create command (dev, staging, production)

EXAMPLES:
    # Show current configuration
    $0 show

    # Validate configuration file
    $0 validate --config ./my-config.env

    # Create production configuration
    $0 create --template production --output ./production-config.env

    # Copy and modify configuration
    $0 copy --config ./deployment-config.env --output ./staging-config.env

    # Edit configuration file
    $0 edit --config ./deployment-config.env

    # Compare two configurations
    $0 compare --config ./dev-config.env --output ./prod-config.env

EOF
}

# Function to show configuration
show_config() {
    local config_file="${1:-./deployment-config.env}"
    
    log_info "Loading configuration from: $config_file"
    
    if load_deployment_config "$config_file"; then
        show_deployment_config
    else
        log_error "Failed to load configuration"
        exit 1
    fi
}

# Function to validate configuration
validate_config() {
    local config_file="${1:-./deployment-config.env}"
    
    log_info "Validating configuration file: $config_file"
    
    if validate_config_file "$config_file"; then
        log_success "✅ Configuration is valid"
        exit 0
    else
        log_error "❌ Configuration validation failed"
        exit 1
    fi
}

# Function to create new configuration file
create_config() {
    local template_type="${1:-dev}"
    local output_file="${2:-./deployment-config-$template_type.env}"
    
    log_info "Creating $template_type configuration: $output_file"
    
    case "$template_type" in
        "dev"|"development")
            create_dev_config "$output_file"
            ;;
        "staging"|"stage")
            create_staging_config "$output_file"
            ;;
        "prod"|"production")
            create_production_config "$output_file"
            ;;
        *)
            log_error "Unknown template type: $template_type"
            log_error "Available templates: dev, staging, production"
            exit 1
            ;;
    esac
    
    log_success "Configuration file created: $output_file"
}

# Function to create development configuration
create_dev_config() {
    local output_file="$1"
    
    cat > "$output_file" << 'EOF'
# RAG System Development Configuration
# Optimized for development and testing

# Basic settings
ENVIRONMENT=dev
PROJECT_NAME=myapp-dev
AWS_DEFAULT_REGION=ap-southeast-1

# Lambda settings (cost-optimized)
LAMBDA_RUNTIME=dotnet10
LAMBDA_MEMORY_SIZE=512
LAMBDA_TIMEOUT=30
LAMBDA_HANDLER=RAG.APIs::RAG.APIs.LambdaEntryPoint::FunctionHandlerAsync

# RDS settings (minimal cost)
RDS_INSTANCE_CLASS=db.t3.micro
RDS_ALLOCATED_STORAGE=20
RDS_MAX_ALLOCATED_STORAGE=50
RDS_ENGINE_VERSION=15.4
RDS_BACKUP_RETENTION_PERIOD=1
RDS_MULTI_AZ=false
RDS_STORAGE_ENCRYPTED=true
RDS_PUBLICLY_ACCESSIBLE=true

# API Gateway settings
API_GATEWAY_STAGE=dev
API_GATEWAY_DESCRIPTION="RAG System Development API"
API_GATEWAY_LOGGING_ENABLED=true
API_GATEWAY_THROTTLE_RATE=100
API_GATEWAY_THROTTLE_BURST=200

# Development options
SKIP_TESTS=false
SKIP_SEEDING=false
SKIP_CLEANUP=false
VERBOSE_LOGGING=true

# Cost optimization for development
AUTO_CLEANUP_RESOURCES=false
USE_SPOT_INSTANCES=false

# Security (relaxed for development)
ENABLE_VPC=false
RDS_SSL_ENABLED=true

# Monitoring (minimal for cost)
CLOUDWATCH_LOG_RETENTION_DAYS=7
ENABLE_DETAILED_MONITORING=false
ENABLE_XRAY_TRACING=false

# Tags
CUSTOM_TAGS="Environment=development,Owner=DevTeam,Purpose=Testing"
EOF
}

# Function to create staging configuration
create_staging_config() {
    local output_file="$1"
    
    cat > "$output_file" << 'EOF'
# RAG System Staging Configuration
# Balanced configuration for staging environment

# Basic settings
ENVIRONMENT=staging
PROJECT_NAME=myapp-staging
AWS_DEFAULT_REGION=ap-southeast-1

# Lambda settings (balanced)
LAMBDA_RUNTIME=dotnet10
LAMBDA_MEMORY_SIZE=1024
LAMBDA_TIMEOUT=60
LAMBDA_HANDLER=RAG.APIs::RAG.APIs.LambdaEntryPoint::FunctionHandlerAsync

# RDS settings (balanced)
RDS_INSTANCE_CLASS=db.t3.small
RDS_ALLOCATED_STORAGE=50
RDS_MAX_ALLOCATED_STORAGE=200
RDS_ENGINE_VERSION=15.4
RDS_BACKUP_RETENTION_PERIOD=7
RDS_MULTI_AZ=false
RDS_STORAGE_ENCRYPTED=true
RDS_PUBLICLY_ACCESSIBLE=true

# API Gateway settings
API_GATEWAY_STAGE=staging
API_GATEWAY_DESCRIPTION="RAG System Staging API"
API_GATEWAY_LOGGING_ENABLED=true
API_GATEWAY_THROTTLE_RATE=500
API_GATEWAY_THROTTLE_BURST=1000

# Staging options
SKIP_TESTS=false
SKIP_SEEDING=false
SKIP_CLEANUP=false
VERBOSE_LOGGING=false

# Cost optimization
AUTO_CLEANUP_RESOURCES=false
USE_SPOT_INSTANCES=false

# Security
ENABLE_VPC=false
RDS_SSL_ENABLED=true

# Monitoring
CLOUDWATCH_LOG_RETENTION_DAYS=14
ENABLE_DETAILED_MONITORING=false
ENABLE_XRAY_TRACING=true

# Tags
CUSTOM_TAGS="Environment=staging,Owner=DevTeam,Purpose=PreProduction"
EOF
}

# Function to create production configuration
create_production_config() {
    local output_file="$1"
    
    cat > "$output_file" << 'EOF'
# RAG System Production Configuration
# Optimized for production performance and reliability

# Basic settings
ENVIRONMENT=production
PROJECT_NAME=myapp-prod
AWS_DEFAULT_REGION=ap-southeast-1

# Lambda settings (performance optimized)
LAMBDA_RUNTIME=dotnet10
LAMBDA_MEMORY_SIZE=2048
LAMBDA_TIMEOUT=120
LAMBDA_HANDLER=RAG.APIs::RAG.APIs.LambdaEntryPoint::FunctionHandlerAsync

# RDS settings (production grade)
RDS_INSTANCE_CLASS=db.t3.medium
RDS_ALLOCATED_STORAGE=100
RDS_MAX_ALLOCATED_STORAGE=1000
RDS_ENGINE_VERSION=15.4
RDS_BACKUP_RETENTION_PERIOD=30
RDS_MULTI_AZ=true
RDS_STORAGE_ENCRYPTED=true
RDS_PUBLICLY_ACCESSIBLE=false

# API Gateway settings
API_GATEWAY_STAGE=production
API_GATEWAY_DESCRIPTION="RAG System Production API"
API_GATEWAY_LOGGING_ENABLED=true
API_GATEWAY_THROTTLE_RATE=2000
API_GATEWAY_THROTTLE_BURST=5000

# Production options
SKIP_TESTS=false
SKIP_SEEDING=false
SKIP_CLEANUP=true
VERBOSE_LOGGING=false

# Cost optimization
AUTO_CLEANUP_RESOURCES=false
USE_SPOT_INSTANCES=false

# Security (enhanced)
ENABLE_VPC=true
VPC_CIDR_BLOCK=10.0.0.0/16
RDS_SSL_ENABLED=true

# Monitoring (comprehensive)
CLOUDWATCH_LOG_RETENTION_DAYS=90
ENABLE_DETAILED_MONITORING=true
ENABLE_XRAY_TRACING=true

# Tags
CUSTOM_TAGS="Environment=production,Owner=DevTeam,CostCenter=Engineering,Backup=Required"
EOF
}

# Function to copy configuration file
copy_config() {
    local source_file="${1:-./deployment-config.env}"
    local output_file="${2:-./deployment-config-copy.env}"
    
    if [[ ! -f "$source_file" ]]; then
        log_error "Source configuration file not found: $source_file"
        exit 1
    fi
    
    log_info "Copying configuration from $source_file to $output_file"
    cp "$source_file" "$output_file"
    log_success "Configuration copied successfully"
}

# Function to edit configuration file
edit_config() {
    local config_file="${1:-./deployment-config.env}"
    
    # Determine editor
    local editor="${EDITOR:-nano}"
    if command -v code &> /dev/null; then
        editor="code"
    elif command -v vim &> /dev/null; then
        editor="vim"
    fi
    
    log_info "Opening configuration file in $editor: $config_file"
    
    if [[ ! -f "$config_file" ]]; then
        log_warn "Configuration file not found, creating default..."
        create_default_config "$config_file"
    fi
    
    "$editor" "$config_file"
}

# Function to compare configuration files
compare_config() {
    local file1="${1:-./deployment-config.env}"
    local file2="${2:-./deployment-config-production.env}"
    
    if [[ ! -f "$file1" ]]; then
        log_error "First configuration file not found: $file1"
        exit 1
    fi
    
    if [[ ! -f "$file2" ]]; then
        log_error "Second configuration file not found: $file2"
        exit 1
    fi
    
    log_info "Comparing configurations:"
    log_info "  File 1: $file1"
    log_info "  File 2: $file2"
    echo ""
    
    if command -v diff &> /dev/null; then
        diff -u "$file1" "$file2" || true
    else
        log_warn "diff command not available, showing files side by side"
        echo "=== $file1 ==="
        cat "$file1"
        echo ""
        echo "=== $file2 ==="
        cat "$file2"
    fi
}

# Main execution
main() {
    local command="${1:-help}"
    local config_file="./deployment-config.env"
    local output_file=""
    local template_type="dev"
    
    # Parse arguments
    shift || true
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                config_file="$2"
                shift 2
                ;;
            --output)
                output_file="$2"
                shift 2
                ;;
            --template)
                template_type="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Execute command
    case "$command" in
        "show")
            show_config "$config_file"
            ;;
        "validate")
            validate_config "$config_file"
            ;;
        "create")
            if [[ -z "$output_file" ]]; then
                output_file="./deployment-config-$template_type.env"
            fi
            create_config "$template_type" "$output_file"
            ;;
        "copy")
            if [[ -z "$output_file" ]]; then
                output_file="./deployment-config-copy.env"
            fi
            copy_config "$config_file" "$output_file"
            ;;
        "edit")
            edit_config "$config_file"
            ;;
        "compare")
            if [[ -z "$output_file" ]]; then
                log_error "Second file required for comparison. Use --output FILE"
                exit 1
            fi
            compare_config "$config_file" "$output_file"
            ;;
        "help"|*)
            show_usage
            ;;
    esac
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi