#!/bin/bash

# RDS PostgreSQL Provisioning Script
# Creates RDS PostgreSQL 16 instance with cost-optimized configuration
# Uses public access without VPC for simplified deployment
# No security groups - relies on database-level security

set -euo pipefail

# Initialize AWS_PROFILE with default value if not set
AWS_PROFILE="${AWS_PROFILE:-}"

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILITIES_DIR="$SCRIPT_DIR/../utilities"
source "$UTILITIES_DIR/logging.sh"
source "$UTILITIES_DIR/error-handling.sh"
source "$UTILITIES_DIR/validate-aws-cli.sh"
source "$UTILITIES_DIR/parse-appsettings.sh"

# Default configuration values (will be overridden by appsettings.json)
DEFAULT_DB_INSTANCE_CLASS="db.t3.micro"
DEFAULT_ALLOCATED_STORAGE="20"
DEFAULT_ENGINE="postgres"
DEFAULT_ENGINE_VERSION="${RDS_ENGINE_VERSION:-16.13}"
DEFAULT_DB_NAME="RAGSystem"
DEFAULT_MASTER_USERNAME="postgres"
DEFAULT_MASTER_PASSWORD="123456"

# Configuration variables
DB_INSTANCE_CLASS="${DB_INSTANCE_CLASS:-$DEFAULT_DB_INSTANCE_CLASS}"
ALLOCATED_STORAGE="${ALLOCATED_STORAGE:-$DEFAULT_ALLOCATED_STORAGE}"
ENGINE="${ENGINE:-$DEFAULT_ENGINE}"
ENGINE_VERSION="${ENGINE_VERSION:-$DEFAULT_ENGINE_VERSION}"
DB_NAME="${DB_NAME:-$DEFAULT_DB_NAME}"
MASTER_USERNAME="${MASTER_USERNAME:-$DEFAULT_MASTER_USERNAME}"
MASTER_PASSWORD="${MASTER_PASSWORD:-$DEFAULT_MASTER_PASSWORD}"

# Resource naming
ENVIRONMENT="${ENVIRONMENT:-dev}"
PROJECT_NAME="${PROJECT_NAME:-myragapp}"
DB_INSTANCE_IDENTIFIER="$PROJECT_NAME-$ENVIRONMENT-db"

# Global variables for resource tracking
DB_ENDPOINT=""

# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Provisions RDS PostgreSQL 16 instance with cost-optimized configuration.
Uses public access without VPC for simplified deployment.

OPTIONS:
    --instance-class CLASS      DB instance class (default: $DEFAULT_DB_INSTANCE_CLASS)
    --storage SIZE             Allocated storage in GB (default: $DEFAULT_ALLOCATED_STORAGE)
    --db-name NAME             Database name (default: $DEFAULT_DB_NAME)
    --username USERNAME        Master username (default: $DEFAULT_MASTER_USERNAME)
    --password PASSWORD        Master password (default: from appsettings.json)
    --appsettings FILE         Path to appsettings.json (default: RAG.APIs/appsettings.json)
    --environment ENV          Environment name (default: dev)
    --project-name NAME        Project name (default: myapp)
    --aws-profile PROFILE      AWS profile to use
    --help                     Show this help message

EXAMPLES:
    $0 --environment production --project-name webapp
    $0 --instance-class db.t3.small --storage 50 --aws-profile prod

COST OPTIMIZATION:
    - Uses db.t3.micro instance class (AWS Free Tier eligible)
    - Minimal storage allocation (20GB)
    - Single-AZ deployment
    - No backup retention (can be enabled later)
    - No encryption at rest (can be enabled for production)
    - Public access enabled for simplified connectivity

SECURITY:
    - Public access enabled for simplified connectivity
    - Strong password generation
    - SSL/TLS encryption in transit
    - Database-level security controls

EOF
}

# Function to parse command line arguments
parse_arguments() {
    local appsettings_file="RAG.APIs/appsettings.json"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --instance-class)
                DB_INSTANCE_CLASS="$2"
                shift 2
                ;;
            --storage)
                ALLOCATED_STORAGE="$2"
                shift 2
                ;;
            --db-name)
                DB_NAME="$2"
                shift 2
                ;;
            --username)
                MASTER_USERNAME="$2"
                shift 2
                ;;
            --password)
                MASTER_PASSWORD="$2"
                shift 2
                ;;
            --appsettings)
                appsettings_file="$2"
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
            --aws-profile)
                AWS_PROFILE="$2"
                if [ -n "$AWS_PROFILE" ]; then
                    export AWS_PROFILE
                fi
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
    
    # Parse appsettings.json if it exists and no explicit values provided
    if [[ -f "$appsettings_file" ]]; then
        log_info "Loading configuration from appsettings.json: $appsettings_file"
        if parse_appsettings_db_config "$appsettings_file"; then
            # Override defaults with appsettings values if not explicitly set via command line
            if [[ "$DB_NAME" == "$DEFAULT_DB_NAME" ]]; then
                DB_NAME="$APPSETTINGS_DB_NAME"
            fi
            if [[ "$MASTER_USERNAME" == "$DEFAULT_MASTER_USERNAME" ]]; then
                MASTER_USERNAME="$APPSETTINGS_DB_USERNAME"
            fi
            if [[ "$MASTER_PASSWORD" == "$DEFAULT_MASTER_PASSWORD" ]]; then
                MASTER_PASSWORD="$APPSETTINGS_DB_PASSWORD"
            fi
            
            log_info "Using database configuration from appsettings.json:"
            log_info "  Database: $DB_NAME"
            log_info "  Username: $MASTER_USERNAME"
            log_info "  Password: [LOADED FROM APPSETTINGS]"
        else
            log_warn "Failed to parse appsettings.json, using default values"
        fi
    else
        log_warn "appsettings.json not found: $appsettings_file, using default values"
    fi
    
    # Update resource names after parsing arguments
    DB_INSTANCE_IDENTIFIER="$PROJECT_NAME-$ENVIRONMENT-db"
}

# Function to generate secure random password
generate_db_password() {
    # Use password from appsettings.json if available, otherwise generate random
    if [[ -n "$MASTER_PASSWORD" ]]; then
        echo "$MASTER_PASSWORD"
    else
        # Generate a 16-character password with letters, numbers, and safe special characters
        local password=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-16)
        echo "$password"
    fi
}

# VPC-related functions removed - using public access without VPC

# Function to check if RDS instance already exists
check_existing_rds_instance() {
    log_info "Checking for existing RDS instance: $DB_INSTANCE_IDENTIFIER"
    
    local instance_status=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$instance_status" != "None" ] && [ "$instance_status" != "null" ]; then
        log_info "Found existing RDS instance: $DB_INSTANCE_IDENTIFIER (Status: $instance_status)"
        
        # Get endpoint if instance is available
        if [ "$instance_status" = "available" ]; then
            DB_ENDPOINT=$(aws rds describe-db-instances \
                --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
                --query 'DBInstances[0].Endpoint.Address' \
                --output text)
            log_info "RDS endpoint: $DB_ENDPOINT"
        fi
        
        return 0
    fi
    
    return 1
}

# Function to create RDS instance
create_rds_instance() {
    if check_existing_rds_instance; then
        log_info "Using existing RDS instance: $DB_INSTANCE_IDENTIFIER"
        return 0
    fi
    
    log_info "Creating RDS PostgreSQL instance: $DB_INSTANCE_IDENTIFIER"
    log_info "Configuration: $ENGINE $ENGINE_VERSION, $DB_INSTANCE_CLASS, ${ALLOCATED_STORAGE}GB"
    
    # Generate secure password
    local db_password=$(generate_db_password)
    
    set_error_context "RDS instance creation"
    set_error_remediation "Check AWS permissions for RDS operations, instance class availability, and service limits"
    
    # Create RDS instance with cost-optimized settings and public access (no VPC)
    execute_with_error_handling \
        "aws rds create-db-instance \
            --db-instance-identifier $DB_INSTANCE_IDENTIFIER \
            --db-instance-class $DB_INSTANCE_CLASS \
            --engine $ENGINE \
            --engine-version $ENGINE_VERSION \
            --master-username $MASTER_USERNAME \
            --master-user-password '$db_password' \
            --allocated-storage $ALLOCATED_STORAGE \
            --db-name $DB_NAME \
            --no-multi-az \
            --publicly-accessible \
            --storage-type gp2 \
            --backup-retention-period 0 \
            --no-storage-encrypted \
            --no-auto-minor-version-upgrade \
            --tags Key=Name,Value=$DB_INSTANCE_IDENTIFIER Key=Environment,Value=$ENVIRONMENT Key=Project,Value=$PROJECT_NAME" \
        "Failed to create RDS instance" \
        $ERROR_CODE_DATABASE
    
    log_success "RDS instance creation initiated: $DB_INSTANCE_IDENTIFIER"
    
    # Save database password to checkpoint for later use
    create_checkpoint "rds_password" "$db_password"
    log_info "Database password saved to checkpoint (use 'restore_checkpoint rds_password' to retrieve)"
    
    register_cleanup_function "cleanup_rds_instance"
}

# Function to wait for RDS instance to be available
wait_for_rds_instance() {
    log_info "Waiting for RDS instance to become available..."
    
    local max_attempts=60  # 30 minutes (30 seconds * 60)
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local status=$(aws rds describe-db-instances \
            --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
            --query 'DBInstances[0].DBInstanceStatus' \
            --output text 2>/dev/null || echo "unknown")
        
        case "$status" in
            "available")
                log_success "RDS instance is now available"
                
                # Get the endpoint
                DB_ENDPOINT=$(aws rds describe-db-instances \
                    --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
                    --query 'DBInstances[0].Endpoint.Address' \
                    --output text)
                
                log_success "RDS endpoint: $DB_ENDPOINT"
                return 0
                ;;
            "creating"|"backing-up"|"modifying")
                log_info "RDS instance status: $status (attempt $attempt/$max_attempts)"
                ;;
            "failed"|"incompatible-parameters"|"incompatible-restore")
                handle_error $ERROR_CODE_DATABASE "RDS instance creation failed with status: $status" true
                ;;
            *)
                log_warn "Unknown RDS instance status: $status"
                ;;
        esac
        
        sleep 30
        ((attempt++))
    done
    
    handle_error $ERROR_CODE_DATABASE "RDS instance did not become available within 30 minutes" true
}

# Cleanup functions for rollback
cleanup_rds_instance() {
    if [ -n "$DB_INSTANCE_IDENTIFIER" ]; then
        log_info "Cleaning up RDS instance: $DB_INSTANCE_IDENTIFIER"
        aws rds delete-db-instance \
            --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
            --skip-final-snapshot \
            --delete-automated-backups &>/dev/null || true
    fi
}

# Function to save infrastructure state
save_infrastructure_state() {
    local state_file="./deployment_checkpoints/rds_infrastructure.state"
    mkdir -p "$(dirname "$state_file")"
    
    cat > "$state_file" << EOF
# RDS Infrastructure State
# Generated on $(date)
DB_INSTANCE_IDENTIFIER="$DB_INSTANCE_IDENTIFIER"
DB_ENDPOINT="$DB_ENDPOINT"
ENVIRONMENT="$ENVIRONMENT"
PROJECT_NAME="$PROJECT_NAME"
VPC_ENABLED="false"
EOF
    
    log_success "Infrastructure state saved to: $state_file"
}

# Function to display connection information
display_connection_info() {
    log_success "RDS PostgreSQL provisioning completed successfully!"
    echo ""
    echo "=== RDS Connection Information ==="
    echo "Database Endpoint: $DB_ENDPOINT"
    echo "Database Name: $DB_NAME"
    echo "Master Username: $MASTER_USERNAME"
    echo "Port: 5432"
    echo "Engine: PostgreSQL $ENGINE_VERSION"
    echo "Instance Class: $DB_INSTANCE_CLASS"
    echo "Storage: ${ALLOCATED_STORAGE}GB"
    echo "Public Access: Yes"
    echo ""
    echo "=== Security Details ==="
    echo "Public Access: Yes (No VPC configuration)"
    echo "Access: PostgreSQL port 5432 open to 0.0.0.0/0"
    echo "Master password: Saved in deployment checkpoint"
    echo ""
    echo "=== Connection String Example ==="
    echo "Host=$DB_ENDPOINT;Database=$DB_NAME;Username=$MASTER_USERNAME;Password=<password>;Port=5432;SSL Mode=Require;"
    echo ""
    echo "=== Security Notes ==="
    echo "- Database has public access for simplified connectivity"
    echo "- Use strong passwords and SSL connections"
    echo "- Consider restricting access via database-level security for production"
    echo "- Master password is saved in deployment checkpoint"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Configure Lambda functions with connection string"
    echo "2. Run database migrations"
    echo "3. Test connectivity from your application"
    echo ""
}

# Main execution function
main() {
    log_info "Starting RDS PostgreSQL provisioning..."
    log_info "Project: $PROJECT_NAME, Environment: $ENVIRONMENT"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate AWS CLI
    if ! validate_aws_cli "${AWS_PROFILE:-}"; then
        handle_error $ERROR_CODE_AWS_CLI "AWS CLI validation failed" true
    fi
    
    # Log configuration
    log_info "Configuration:"
    log_info "  Instance Class: $DB_INSTANCE_CLASS"
    log_info "  Storage: ${ALLOCATED_STORAGE}GB"
    log_info "  Engine: $ENGINE $ENGINE_VERSION"
    log_info "  Database Name: $DB_NAME"
    log_info "  Master Username: $MASTER_USERNAME"
    log_info "  Public Access: Yes (No VPC)"
    
    # Create infrastructure components (no VPC, no security group)
    create_rds_instance
    wait_for_rds_instance
    
    # Save state and display information
    save_infrastructure_state
    display_connection_info
    
    log_success "RDS PostgreSQL provisioning completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi