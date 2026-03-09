#!/bin/bash

# RDS PostgreSQL Provisioning Script
# Creates RDS PostgreSQL 16 instance with cost-optimized configuration
# Implements VPC and subnet creation for RDS placement
# Configures security groups for Lambda-to-RDS communication

set -euo pipefail

# Initialize AWS_PROFILE with default value if not set
AWS_PROFILE="${AWS_PROFILE:-}"

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILITIES_DIR="$SCRIPT_DIR/../utilities"
source "$UTILITIES_DIR/logging.sh"
source "$UTILITIES_DIR/error-handling.sh"
source "$UTILITIES_DIR/validate-aws-cli.sh"

# Default configuration values (cost-optimized)
DEFAULT_DB_INSTANCE_CLASS="db.t3.micro"
DEFAULT_ALLOCATED_STORAGE="20"
DEFAULT_ENGINE="postgres"
DEFAULT_ENGINE_VERSION="16.13"
DEFAULT_DB_NAME="appdb"
DEFAULT_MASTER_USERNAME="dbadmin"
DEFAULT_VPC_CIDR="10.0.0.0/16"
DEFAULT_SUBNET_CIDR_1="10.0.1.0/24"
DEFAULT_SUBNET_CIDR_2="10.0.2.0/24"

# Configuration variables
DB_INSTANCE_CLASS="${DB_INSTANCE_CLASS:-$DEFAULT_DB_INSTANCE_CLASS}"
ALLOCATED_STORAGE="${ALLOCATED_STORAGE:-$DEFAULT_ALLOCATED_STORAGE}"
ENGINE="${ENGINE:-$DEFAULT_ENGINE}"
ENGINE_VERSION="${ENGINE_VERSION:-$DEFAULT_ENGINE_VERSION}"
DB_NAME="${DB_NAME:-$DEFAULT_DB_NAME}"
MASTER_USERNAME="${MASTER_USERNAME:-$DEFAULT_MASTER_USERNAME}"
VPC_CIDR="${VPC_CIDR:-$DEFAULT_VPC_CIDR}"
SUBNET_CIDR_1="${SUBNET_CIDR_1:-$DEFAULT_SUBNET_CIDR_1}"
SUBNET_CIDR_2="${SUBNET_CIDR_2:-$DEFAULT_SUBNET_CIDR_2}"

# Resource naming
ENVIRONMENT="${ENVIRONMENT:-dev}"
PROJECT_NAME="${PROJECT_NAME:-myapp}"
VPC_NAME="$PROJECT_NAME-$ENVIRONMENT-vpc"
SUBNET_NAME_1="$PROJECT_NAME-$ENVIRONMENT-subnet-1"
SUBNET_NAME_2="$PROJECT_NAME-$ENVIRONMENT-subnet-2"
DB_SUBNET_GROUP_NAME="$PROJECT_NAME-$ENVIRONMENT-db-subnet-group"
SECURITY_GROUP_NAME="$PROJECT_NAME-$ENVIRONMENT-rds-sg"
DB_INSTANCE_IDENTIFIER="$PROJECT_NAME-$ENVIRONMENT-db"

# Global variables for resource tracking
VPC_ID=""
SUBNET_ID_1=""
SUBNET_ID_2=""
SECURITY_GROUP_ID=""
DB_ENDPOINT=""
# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Provisions RDS PostgreSQL 16 instance with cost-optimized configuration.

OPTIONS:
    --instance-class CLASS      DB instance class (default: $DEFAULT_DB_INSTANCE_CLASS)
    --storage SIZE             Allocated storage in GB (default: $DEFAULT_ALLOCATED_STORAGE)
    --db-name NAME             Database name (default: $DEFAULT_DB_NAME)
    --username USERNAME        Master username (default: $DEFAULT_MASTER_USERNAME)
    --environment ENV          Environment name (default: dev)
    --project-name NAME        Project name (default: myapp)
    --vpc-cidr CIDR           VPC CIDR block (default: $DEFAULT_VPC_CIDR)
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

EOF
}

# Function to parse command line arguments
parse_arguments() {
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
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --project-name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --vpc-cidr)
                VPC_CIDR="$2"
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
    
    # Update resource names after parsing arguments
    VPC_NAME="$PROJECT_NAME-$ENVIRONMENT-vpc"
    SUBNET_NAME_1="$PROJECT_NAME-$ENVIRONMENT-subnet-1"
    SUBNET_NAME_2="$PROJECT_NAME-$ENVIRONMENT-subnet-2"
    DB_SUBNET_GROUP_NAME="$PROJECT_NAME-$ENVIRONMENT-db-subnet-group"
    SECURITY_GROUP_NAME="$PROJECT_NAME-$ENVIRONMENT-rds-sg"
    DB_INSTANCE_IDENTIFIER="$PROJECT_NAME-$ENVIRONMENT-db"
}
# Function to generate secure random password
generate_db_password() {
    # Generate a 16-character password with letters, numbers, and safe special characters
    local password=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-16)
    echo "$password"
}

# Function to check if VPC already exists
check_existing_vpc() {
    log_info "Checking for existing VPC: $VPC_NAME"
    
    local vpc_id=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=$VPC_NAME" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$vpc_id" != "None" ] && [ "$vpc_id" != "null" ]; then
        log_info "Found existing VPC: $vpc_id"
        VPC_ID="$vpc_id"
        return 0
    fi
    
    return 1
}

# Function to create VPC
create_vpc() {
    if check_existing_vpc; then
        log_info "Using existing VPC: $VPC_ID"
        return 0
    fi
    
    log_info "Creating VPC with CIDR: $VPC_CIDR"
    set_error_context "VPC creation"
    set_error_remediation "Check AWS permissions for EC2 VPC operations and ensure CIDR block is valid"
    
    local output=$(execute_with_error_handling \
        "aws ec2 create-vpc --cidr-block $VPC_CIDR --query 'Vpc.VpcId' --output text" \
        "Failed to create VPC" \
        $ERROR_CODE_INFRASTRUCTURE)
    
    VPC_ID="$output"
    log_success "Created VPC: $VPC_ID"
    
    # Tag the VPC
    execute_with_error_handling \
        "aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=$VPC_NAME Key=Environment,Value=$ENVIRONMENT Key=Project,Value=$PROJECT_NAME" \
        "Failed to tag VPC" \
        $ERROR_CODE_INFRASTRUCTURE
    
    # Enable DNS hostnames and resolution
    execute_with_error_handling \
        "aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames" \
        "Failed to enable DNS hostnames" \
        $ERROR_CODE_INFRASTRUCTURE
    
    execute_with_error_handling \
        "aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support" \
        "Failed to enable DNS support" \
        $ERROR_CODE_INFRASTRUCTURE
    
    log_success "VPC configuration completed"
    
    # Register cleanup function
    register_cleanup_function "cleanup_vpc"
}

# Function to get availability zones
get_availability_zones() {
    # Don't use log_info here as it will interfere with the return value
    local azs=$(aws ec2 describe-availability-zones \
        --filters "Name=state,Values=available" \
        --query 'AvailabilityZones[0:2].ZoneName' \
        --output text)
    
    echo "$azs"
}
# Function to check if subnet already exists
check_existing_subnet() {
    local subnet_name="$1"
    
    # Don't use log_info here as it will interfere with the return value
    local subnet_id=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=$subnet_name" "Name=vpc-id,Values=$VPC_ID" \
        --query 'Subnets[0].SubnetId' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$subnet_id" != "None" ] && [ "$subnet_id" != "null" ]; then
        # Log after echoing the subnet ID to avoid contamination
        echo "$subnet_id"
        return 0
    fi
    
    return 1
}

# Function to create subnets
create_subnets() {
    log_info "Creating subnets for RDS deployment"
    
    # Get availability zones
    log_info "Getting available availability zones"
    local azs=($(get_availability_zones))
    if [ ${#azs[@]} -lt 2 ]; then
        handle_error $ERROR_CODE_INFRASTRUCTURE "Need at least 2 availability zones for RDS subnet group" true
    fi
    
    local az1="${azs[0]}"
    local az2="${azs[1]}"
    
    log_info "Using availability zones: $az1, $az2"
    
    # Create first subnet
    if ! SUBNET_ID_1=$(check_existing_subnet "$SUBNET_NAME_1"); then
        log_info "Creating subnet 1: $SUBNET_CIDR_1 in $az1"
        set_error_context "Subnet 1 creation"
        set_error_remediation "Check VPC CIDR block and subnet CIDR conflicts"
        
        SUBNET_ID_1=$(execute_with_error_handling \
            "aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $SUBNET_CIDR_1 --availability-zone $az1 --query 'Subnet.SubnetId' --output text" \
            "Failed to create subnet 1" \
            $ERROR_CODE_INFRASTRUCTURE)
        
        # Tag subnet 1
        execute_with_error_handling \
            "aws ec2 create-tags --resources $SUBNET_ID_1 --tags Key=Name,Value=$SUBNET_NAME_1 Key=Environment,Value=$ENVIRONMENT Key=Project,Value=$PROJECT_NAME Key=Type,Value=private" \
            "Failed to tag subnet 1" \
            $ERROR_CODE_INFRASTRUCTURE
        
        log_success "Created subnet 1: $SUBNET_ID_1"
        register_cleanup_function "cleanup_subnet_1"
    else
        log_info "Found existing subnet: $SUBNET_NAME_1 ($SUBNET_ID_1)"
    fi
    
    # Create second subnet
    if ! SUBNET_ID_2=$(check_existing_subnet "$SUBNET_NAME_2"); then
        log_info "Creating subnet 2: $SUBNET_CIDR_2 in $az2"
        set_error_context "Subnet 2 creation"
        set_error_remediation "Check VPC CIDR block and subnet CIDR conflicts"
        
        SUBNET_ID_2=$(execute_with_error_handling \
            "aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $SUBNET_CIDR_2 --availability-zone $az2 --query 'Subnet.SubnetId' --output text" \
            "Failed to create subnet 2" \
            $ERROR_CODE_INFRASTRUCTURE)
        
        # Tag subnet 2
        execute_with_error_handling \
            "aws ec2 create-tags --resources $SUBNET_ID_2 --tags Key=Name,Value=$SUBNET_NAME_2 Key=Environment,Value=$ENVIRONMENT Key=Project,Value=$PROJECT_NAME Key=Type,Value=private" \
            "Failed to tag subnet 2" \
            $ERROR_CODE_INFRASTRUCTURE
        
        log_success "Created subnet 2: $SUBNET_ID_2"
        register_cleanup_function "cleanup_subnet_2"
    else
        log_info "Found existing subnet: $SUBNET_NAME_2 ($SUBNET_ID_2)"
    fi
    
    log_success "Subnets created successfully"
}
# Function to check if security group already exists
check_existing_security_group() {
    log_info "Checking for existing security group: $SECURITY_GROUP_NAME"
    
    local sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" "Name=vpc-id,Values=$VPC_ID" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$sg_id" != "None" ] && [ "$sg_id" != "null" ]; then
        log_info "Found existing security group: $sg_id"
        SECURITY_GROUP_ID="$sg_id"
        return 0
    fi
    
    return 1
}

# Function to create security group for RDS
create_security_group() {
    if check_existing_security_group; then
        log_info "Using existing security group: $SECURITY_GROUP_ID"
        return 0
    fi
    
    log_info "Creating security group for RDS: $SECURITY_GROUP_NAME"
    set_error_context "Security group creation"
    set_error_remediation "Check AWS permissions for EC2 security group operations"
    
    SECURITY_GROUP_ID=$(execute_with_error_handling \
        "aws ec2 create-security-group --group-name $SECURITY_GROUP_NAME --description 'Security group for RDS PostgreSQL access from Lambda' --vpc-id $VPC_ID --query 'GroupId' --output text" \
        "Failed to create security group" \
        $ERROR_CODE_INFRASTRUCTURE)
    
    log_success "Created security group: $SECURITY_GROUP_ID"
    
    # Tag the security group
    execute_with_error_handling \
        "aws ec2 create-tags --resources $SECURITY_GROUP_ID --tags Key=Name,Value=$SECURITY_GROUP_NAME Key=Environment,Value=$ENVIRONMENT Key=Project,Value=$PROJECT_NAME" \
        "Failed to tag security group" \
        $ERROR_CODE_INFRASTRUCTURE
    
    # Add inbound rule for PostgreSQL (port 5432) from VPC CIDR
    log_info "Adding PostgreSQL access rule to security group"
    execute_with_error_handling \
        "aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 5432 --cidr $VPC_CIDR" \
        "Failed to add PostgreSQL access rule" \
        $ERROR_CODE_INFRASTRUCTURE
    
    log_success "Security group configuration completed"
    register_cleanup_function "cleanup_security_group"
}

# Function to check if DB subnet group already exists
check_existing_db_subnet_group() {
    log_info "Checking for existing DB subnet group: $DB_SUBNET_GROUP_NAME"
    
    local subnet_group_exists=$(aws rds describe-db-subnet-groups \
        --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" \
        --query 'DBSubnetGroups[0].DBSubnetGroupName' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$subnet_group_exists" != "None" ] && [ "$subnet_group_exists" != "null" ]; then
        log_info "Found existing DB subnet group: $subnet_group_exists"
        return 0
    fi
    
    return 1
}

# Function to create DB subnet group
create_db_subnet_group() {
    if check_existing_db_subnet_group; then
        log_info "Using existing DB subnet group: $DB_SUBNET_GROUP_NAME"
        return 0
    fi
    
    log_info "Creating DB subnet group: $DB_SUBNET_GROUP_NAME"
    set_error_context "DB subnet group creation"
    set_error_remediation "Check AWS permissions for RDS operations and ensure subnets exist"
    
    execute_with_error_handling \
        "aws rds create-db-subnet-group --db-subnet-group-name $DB_SUBNET_GROUP_NAME --db-subnet-group-description 'Subnet group for $PROJECT_NAME $ENVIRONMENT RDS instance' --subnet-ids $SUBNET_ID_1 $SUBNET_ID_2 --tags Key=Name,Value=$DB_SUBNET_GROUP_NAME Key=Environment,Value=$ENVIRONMENT Key=Project,Value=$PROJECT_NAME" \
        "Failed to create DB subnet group" \
        $ERROR_CODE_INFRASTRUCTURE
    
    log_success "Created DB subnet group: $DB_SUBNET_GROUP_NAME"
    register_cleanup_function "cleanup_db_subnet_group"
}
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
    
    # Create RDS instance with cost-optimized settings
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
            --vpc-security-group-ids $SECURITY_GROUP_ID \
            --db-subnet-group-name $DB_SUBNET_GROUP_NAME \
            --no-multi-az \
            --no-publicly-accessible \
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

cleanup_db_subnet_group() {
    if [ -n "$DB_SUBNET_GROUP_NAME" ]; then
        log_info "Cleaning up DB subnet group: $DB_SUBNET_GROUP_NAME"
        aws rds delete-db-subnet-group \
            --db-subnet-group-name "$DB_SUBNET_GROUP_NAME" &>/dev/null || true
    fi
}

cleanup_security_group() {
    if [ -n "$SECURITY_GROUP_ID" ]; then
        log_info "Cleaning up security group: $SECURITY_GROUP_ID"
        aws ec2 delete-security-group \
            --group-id "$SECURITY_GROUP_ID" &>/dev/null || true
    fi
}

cleanup_subnet_1() {
    if [ -n "$SUBNET_ID_1" ]; then
        log_info "Cleaning up subnet 1: $SUBNET_ID_1"
        aws ec2 delete-subnet \
            --subnet-id "$SUBNET_ID_1" &>/dev/null || true
    fi
}

cleanup_subnet_2() {
    if [ -n "$SUBNET_ID_2" ]; then
        log_info "Cleaning up subnet 2: $SUBNET_ID_2"
        aws ec2 delete-subnet \
            --subnet-id "$SUBNET_ID_2" &>/dev/null || true
    fi
}

cleanup_vpc() {
    if [ -n "$VPC_ID" ]; then
        log_info "Cleaning up VPC: $VPC_ID"
        aws ec2 delete-vpc \
            --vpc-id "$VPC_ID" &>/dev/null || true
    fi
}

# Function to save infrastructure state
save_infrastructure_state() {
    local state_file="./deployment_checkpoints/rds_infrastructure.state"
    mkdir -p "$(dirname "$state_file")"
    
    cat > "$state_file" << EOF
# RDS Infrastructure State
# Generated on $(date)
VPC_ID="$VPC_ID"
SUBNET_ID_1="$SUBNET_ID_1"
SUBNET_ID_2="$SUBNET_ID_2"
SECURITY_GROUP_ID="$SECURITY_GROUP_ID"
DB_SUBNET_GROUP_NAME="$DB_SUBNET_GROUP_NAME"
DB_INSTANCE_IDENTIFIER="$DB_INSTANCE_IDENTIFIER"
DB_ENDPOINT="$DB_ENDPOINT"
ENVIRONMENT="$ENVIRONMENT"
PROJECT_NAME="$PROJECT_NAME"
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
    echo ""
    echo "=== Infrastructure Details ==="
    echo "VPC ID: $VPC_ID"
    echo "Subnet IDs: $SUBNET_ID_1, $SUBNET_ID_2"
    echo "Security Group ID: $SECURITY_GROUP_ID"
    echo "DB Subnet Group: $DB_SUBNET_GROUP_NAME"
    echo ""
    echo "=== Security Notes ==="
    echo "- Database is in private subnets (not publicly accessible)"
    echo "- Security group allows access only from VPC CIDR: $VPC_CIDR"
    echo "- Master password is saved in deployment checkpoint"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Configure Lambda functions to use this VPC"
    echo "2. Update connection strings with endpoint: $DB_ENDPOINT"
    echo "3. Run database migrations"
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
    log_info "  VPC CIDR: $VPC_CIDR"
    
    # Create infrastructure components
    create_vpc
    create_subnets
    create_security_group
    create_db_subnet_group
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