#!/bin/bash

# Parse appsettings.json utility
# Extracts database configuration from appsettings.json

set -euo pipefail

# Source logging utility
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"

# Function to parse connection string from appsettings.json
parse_appsettings_db_config() {
    local appsettings_file="$1"
    
    if [[ ! -f "$appsettings_file" ]]; then
        log_error "appsettings.json not found: $appsettings_file"
        return 1
    fi
    
    log_info "Parsing database configuration from: $appsettings_file"
    
    # Extract connection string using grep and sed (no jq required)
    local connection_string
    connection_string=$(grep -o '"DefaultConnection"[[:space:]]*:[[:space:]]*"[^"]*"' "$appsettings_file" | sed 's/.*"DefaultConnection"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    
    if [[ -z "$connection_string" ]]; then
        log_error "No DefaultConnection found in appsettings.json"
        return 1
    fi
    
    log_info "Found connection string: $connection_string"
    
    # Parse connection string components
    local host port database username password
    
    # Extract Host
    if [[ $connection_string =~ Host=([^;]+) ]]; then
        host="${BASH_REMATCH[1]}"
    else
        host="localhost"
    fi
    
    # Extract Port
    if [[ $connection_string =~ Port=([^;]+) ]]; then
        port="${BASH_REMATCH[1]}"
    else
        port="5432"
    fi
    
    # Extract Database
    if [[ $connection_string =~ Database=([^;]+) ]]; then
        database="${BASH_REMATCH[1]}"
    else
        log_error "Database name not found in connection string"
        return 1
    fi
    
    # Extract Username
    if [[ $connection_string =~ Username=([^;]+) ]]; then
        username="${BASH_REMATCH[1]}"
    else
        log_error "Username not found in connection string"
        return 1
    fi
    
    # Extract Password
    if [[ $connection_string =~ Password=([^;]+) ]]; then
        password="${BASH_REMATCH[1]}"
    else
        log_error "Password not found in connection string"
        return 1
    fi
    
    # Export variables for use in other scripts
    export APPSETTINGS_DB_HOST="$host"
    export APPSETTINGS_DB_PORT="$port"
    export APPSETTINGS_DB_NAME="$database"
    export APPSETTINGS_DB_USERNAME="$username"
    export APPSETTINGS_DB_PASSWORD="$password"
    
    log_success "Database configuration parsed successfully:"
    log_info "  Host: $host"
    log_info "  Port: $port"
    log_info "  Database: $database"
    log_info "  Username: $username"
    log_info "  Password: [HIDDEN]"
    
    return 0
}

# Function to get AWS region from appsettings.json
parse_appsettings_aws_config() {
    local appsettings_file="$1"
    
    if [[ ! -f "$appsettings_file" ]]; then
        log_error "appsettings.json not found: $appsettings_file"
        return 1
    fi
    
    # Extract AWS region using grep and sed
    local aws_region
    aws_region=$(grep -o '"Region"[[:space:]]*:[[:space:]]*"[^"]*"' "$appsettings_file" | sed 's/.*"Region"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    
    if [[ -n "$aws_region" ]]; then
        export APPSETTINGS_AWS_REGION="$aws_region"
        log_info "AWS Region from appsettings: $aws_region"
    else
        log_warn "No AWS Region found in appsettings.json"
    fi
    
    return 0
}

# Function to display parsed configuration
show_parsed_config() {
    echo ""
    echo "=== Parsed Configuration from appsettings.json ==="
    echo "Database Host: ${APPSETTINGS_DB_HOST:-Not set}"
    echo "Database Port: ${APPSETTINGS_DB_PORT:-Not set}"
    echo "Database Name: ${APPSETTINGS_DB_NAME:-Not set}"
    echo "Database Username: ${APPSETTINGS_DB_USERNAME:-Not set}"
    echo "Database Password: ${APPSETTINGS_DB_PASSWORD:+[SET]}${APPSETTINGS_DB_PASSWORD:-Not set}"
    echo "AWS Region: ${APPSETTINGS_AWS_REGION:-Not set}"
    echo ""
}

# Main function for standalone usage
main() {
    local appsettings_file="${1:-RAG.APIs/appsettings.json}"
    
    log_info "Parsing appsettings.json configuration..."
    
    if parse_appsettings_db_config "$appsettings_file"; then
        parse_appsettings_aws_config "$appsettings_file"
        show_parsed_config
        log_success "Configuration parsing completed successfully"
    else
        log_error "Failed to parse appsettings.json configuration"
        exit 1
    fi
}

# Export functions for use in other scripts
export -f parse_appsettings_db_config parse_appsettings_aws_config show_parsed_config

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi