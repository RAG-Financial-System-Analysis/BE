#!/bin/bash

# Complete User Seeding Script
# Creates users in both Cognito and Database with proper integration
# This replaces the DbInitializer when it fails

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILITIES_DIR="$SCRIPT_DIR/../utilities"
source "$UTILITIES_DIR/logging.sh"
source "$UTILITIES_DIR/error-handling.sh"

# Load configuration
CONFIG_FILE="$SCRIPT_DIR/../deployment-config.env"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    log_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Configuration variables
USER_POOL_ID="${AWS_USER_POOL_ID:-}"
CLIENT_ID="${AWS_CLIENT_ID:-}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-RAGSystem}"
DB_USERNAME="${DB_USERNAME:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-12345678}"

# Default users configuration
ADMIN_EMAIL="${ADMIN_USER_EMAIL:-admin@rag.com}"
ADMIN_PASSWORD="${ADMIN_USER_PASSWORD:-Admin@123!!}"
ADMIN_FULLNAME="${ADMIN_USER_FULLNAME:-System Admin}"

ANALYST_EMAIL="${ANALYST_USER_EMAIL:-analyst@rag.com}"
ANALYST_PASSWORD="${ANALYST_USER_PASSWORD:-Analyst@123!!}"
ANALYST_FULLNAME="${ANALYST_USER_FULLNAME:-System Analyst}"

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Complete user seeding script that creates users in both Cognito and Database.

OPTIONS:
    --user-pool-id ID         AWS Cognito User Pool ID (required)
    --client-id ID            AWS Cognito Client ID (required)
    --db-host HOST            Database host (default: from config)
    --db-port PORT            Database port (default: from config)
    --db-name NAME            Database name (default: from config)
    --db-user USER            Database username (default: from config)
    --db-password PASS        Database password (default: from config)
    --skip-cognito            Skip Cognito user creation
    --skip-database           Skip database user creation
    --help                    Show this help message

DESCRIPTION:
    This script creates default users (admin and analyst) in both:
    1. AWS Cognito User Pool (for authentication)
    2. PostgreSQL Database (for application data)
    
    It ensures proper integration between Cognito and Database users.

EXAMPLES:
    # Full seeding with auto-detected config
    $0 --user-pool-id ap-southeast-1_VTLpFeyhi --client-id 76hpd4tfrp93qf33ue6sr0991g

    # Skip Cognito (database only)
    $0 --user-pool-id ap-southeast-1_VTLpFeyhi --client-id 76hpd4tfrp93qf33ue6sr0991g --skip-cognito

EOF
}

# Parse arguments
SKIP_COGNITO=false
SKIP_DATABASE=false

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --user-pool-id)
                USER_POOL_ID="$2"
                shift 2
                ;;
            --client-id)
                CLIENT_ID="$2"
                shift 2
                ;;
            --db-host)
                DB_HOST="$2"
                shift 2
                ;;
            --db-port)
                DB_PORT="$2"
                shift 2
                ;;
            --db-name)
                DB_NAME="$2"
                shift 2
                ;;
            --db-user)
                DB_USERNAME="$2"
                shift 2
                ;;
            --db-password)
                DB_PASSWORD="$2"
                shift 2
                ;;
            --skip-cognito)
                SKIP_COGNITO=true
                shift
                ;;
            --skip-database)
                SKIP_DATABASE=true
                shift
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
    
    if [[ -z "$USER_POOL_ID" || -z "$CLIENT_ID" ]]; then
        log_error "User Pool ID and Client ID are required"
        show_usage
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check PostgreSQL client
    if ! command -v psql &> /dev/null; then
        log_error "PostgreSQL client (psql) is not installed"
        exit 1
    fi
    
    # Test AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to ensure roles exist in database
ensure_roles_exist() {
    log_info "Ensuring roles exist in database..."
    
    local connection_string="postgresql://$DB_USERNAME:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME"
    
    # Check if roles table exists and has data
    local role_count
    role_count=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -d "$DB_NAME" -U "$DB_USERNAME" -p "$DB_PORT" -t -c "SELECT COUNT(*) FROM roles;" 2>/dev/null | xargs || echo "0")
    
    if [[ "$role_count" -lt 2 ]]; then
        log_info "Creating default roles..."
        
        PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -d "$DB_NAME" -U "$DB_USERNAME" -p "$DB_PORT" -c "
            INSERT INTO roles (id, name, description, createdat) VALUES 
            ('99999999-9999-9999-9999-999999999999', 'Admin', 'System Administrator', CURRENT_TIMESTAMP),
            ('66666666-6666-6666-6666-666666666666', 'Analyst', 'Financial Analyst', CURRENT_TIMESTAMP)
            ON CONFLICT (id) DO NOTHING;
        " || {
            log_error "Failed to create roles in database"
            return 1
        }
        
        log_success "Roles created in database"
    else
        log_info "Roles already exist in database"
    fi
}

# Function to create user in Cognito
create_cognito_user() {
    local email="$1"
    local password="$2"
    local fullname="$3"
    
    log_info "Creating user in Cognito: $email"
    
    # Check if user already exists
    if aws cognito-idp admin-get-user --user-pool-id "$USER_POOL_ID" --username "$email" --region "$AWS_DEFAULT_REGION" &>/dev/null; then
        log_info "User $email already exists in Cognito"
        
        # Get the user's sub
        local user_sub
        user_sub=$(aws cognito-idp admin-get-user --user-pool-id "$USER_POOL_ID" --username "$email" --region "$AWS_DEFAULT_REGION" --query 'UserAttributes[?Name==`sub`].Value' --output text)
        echo "$user_sub"
        return 0
    fi
    
    # Create user
    local create_result
    create_result=$(aws cognito-idp admin-create-user \
        --user-pool-id "$USER_POOL_ID" \
        --username "$email" \
        --user-attributes "Name=email,Value=$email" "Name=name,Value=$fullname" \
        --temporary-password "TempPass123!" \
        --message-action "SUPPRESS" \
        --region "$AWS_DEFAULT_REGION" 2>/dev/null) || {
        log_error "Failed to create user $email in Cognito"
        return 1
    }
    
    # Extract user sub
    local user_sub
    user_sub=$(echo "$create_result" | grep -o '"Value": "[^"]*"' | grep -A1 '"Name": "sub"' | tail -1 | cut -d'"' -f4)
    
    # Set permanent password
    aws cognito-idp admin-set-user-password \
        --user-pool-id "$USER_POOL_ID" \
        --username "$email" \
        --password "$password" \
        --permanent \
        --region "$AWS_DEFAULT_REGION" || {
        log_error "Failed to set permanent password for user $email"
        return 1
    }
    
    log_success "User $email created in Cognito with sub: $user_sub"
    echo "$user_sub"
}

# Function to create user in database
create_database_user() {
    local email="$1"
    local fullname="$2"
    local role_name="$3"
    local cognito_sub="$4"
    
    log_info "Creating user in database: $email"
    
    # Get role ID
    local role_id
    role_id=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -d "$DB_NAME" -U "$DB_USERNAME" -p "$DB_PORT" -t -c "SELECT id FROM roles WHERE name = '$role_name';" | xargs)
    
    if [[ -z "$role_id" ]]; then
        log_error "Role $role_name not found in database"
        return 1
    fi
    
    # Check if user already exists
    local existing_user
    existing_user=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -d "$DB_NAME" -U "$DB_USERNAME" -p "$DB_PORT" -t -c "SELECT email FROM users WHERE email = '$email';" | xargs || echo "")
    
    if [[ -n "$existing_user" ]]; then
        log_info "User $email already exists in database, updating Cognito sub..."
        
        PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -d "$DB_NAME" -U "$DB_USERNAME" -p "$DB_PORT" -c "
            UPDATE users SET cognitosub = '$cognito_sub' WHERE email = '$email';
        " || {
            log_error "Failed to update user $email in database"
            return 1
        }
        
        log_success "User $email updated in database"
        return 0
    fi
    
    # Create new user
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -d "$DB_NAME" -U "$DB_USERNAME" -p "$DB_PORT" -c "
        INSERT INTO users (roleid, email, cognitosub, fullname, isactive, createdat) 
        VALUES ('$role_id', '$email', '$cognito_sub', '$fullname', true, CURRENT_TIMESTAMP);
    " || {
        log_error "Failed to create user $email in database"
        return 1
    }
    
    log_success "User $email created in database"
}

# Function to seed a single user
seed_user() {
    local email="$1"
    local password="$2"
    local fullname="$3"
    local role="$4"
    
    log_info "🌱 Seeding user: $email ($role)"
    
    local cognito_sub=""
    
    # Create in Cognito
    if [[ "$SKIP_COGNITO" == false ]]; then
        cognito_sub=$(create_cognito_user "$email" "$password" "$fullname")
        if [[ $? -ne 0 ]]; then
            log_error "Failed to create user $email in Cognito"
            return 1
        fi
    else
        log_info "Skipping Cognito creation for $email"
    fi
    
    # Create in Database
    if [[ "$SKIP_DATABASE" == false ]]; then
        create_database_user "$email" "$fullname" "$role" "$cognito_sub"
        if [[ $? -ne 0 ]]; then
            log_error "Failed to create user $email in database"
            return 1
        fi
    else
        log_info "Skipping database creation for $email"
    fi
    
    log_success "✅ User $email seeded successfully"
}

# Function to verify seeding results
verify_seeding() {
    log_info "Verifying seeding results..."
    
    # Check database users
    log_info "Users in database:"
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -d "$DB_NAME" -U "$DB_USERNAME" -p "$DB_PORT" -c "
        SELECT u.email, u.fullname, r.name as role, 
               CASE WHEN u.cognitosub IS NOT NULL THEN 'Yes' ELSE 'No' END as has_cognito_sub
        FROM users u 
        JOIN roles r ON u.roleid = r.id 
        ORDER BY u.email;
    " || log_warn "Could not verify database users"
    
    # Check Cognito users (if not skipped)
    if [[ "$SKIP_COGNITO" == false ]]; then
        log_info "Checking Cognito users..."
        
        for email in "$ADMIN_EMAIL" "$ANALYST_EMAIL"; do
            if aws cognito-idp admin-get-user --user-pool-id "$USER_POOL_ID" --username "$email" --region "$AWS_DEFAULT_REGION" &>/dev/null; then
                log_info "✅ $email exists in Cognito"
            else
                log_warn "❌ $email not found in Cognito"
            fi
        done
    fi
}

# Function to display summary
display_summary() {
    log_success "🎉 User Seeding Completed!"
    echo ""
    echo "=== Seeding Summary ==="
    echo "User Pool ID: $USER_POOL_ID"
    echo "Database: $DB_HOST:$DB_PORT/$DB_NAME"
    echo ""
    echo "=== Created Users ==="
    echo "✅ $ADMIN_EMAIL (Admin) - Password: $ADMIN_PASSWORD"
    echo "✅ $ANALYST_EMAIL (Analyst) - Password: $ANALYST_PASSWORD"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Test login with created users"
    echo "2. Verify role-based access control"
    echo "3. Test API endpoints with authentication"
    echo ""
}

# Main execution function
main() {
    log_info "🌱 Starting Complete User Seeding Process..."
    
    # Parse arguments
    parse_arguments "$@"
    
    log_info "Configuration:"
    log_info "  User Pool ID: $USER_POOL_ID"
    log_info "  Client ID: $CLIENT_ID"
    log_info "  Database: $DB_HOST:$DB_PORT/$DB_NAME"
    log_info "  Skip Cognito: $SKIP_COGNITO"
    log_info "  Skip Database: $SKIP_DATABASE"
    
    # Check prerequisites
    check_prerequisites
    
    # Ensure roles exist
    if [[ "$SKIP_DATABASE" == false ]]; then
        ensure_roles_exist
    fi
    
    # Seed users
    seed_user "$ADMIN_EMAIL" "$ADMIN_PASSWORD" "$ADMIN_FULLNAME" "Admin"
    seed_user "$ANALYST_EMAIL" "$ANALYST_PASSWORD" "$ANALYST_FULLNAME" "Analyst"
    
    # Verify results
    verify_seeding
    
    # Display summary
    display_summary
    
    log_success "🌱 User seeding completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi