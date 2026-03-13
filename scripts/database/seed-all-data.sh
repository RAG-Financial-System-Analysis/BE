#!/bin/bash

# Complete Database Seeding Script
# Seeds roles, analytics types, and users with Cognito integration
# This is the main entry point for database seeding

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

# Configuration
USER_POOL_ID="${AWS_USER_POOL_ID:-}"
CLIENT_ID="${AWS_CLIENT_ID:-}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-RAGSystem}"
DB_USERNAME="${DB_USERNAME:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-12345678}"

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Complete database seeding script that seeds all required data:
1. Roles (Admin, Analyst)
2. Analytics Types (RISK, TREND, COMPARISON, OPPORTUNITY, EXECUTIVE)
3. Users (admin@rag.com, analyst@rag.com) in both Cognito and Database

OPTIONS:
    --user-pool-id ID         AWS Cognito User Pool ID (required)
    --client-id ID            AWS Cognito Client ID (required)
    --skip-roles              Skip role seeding
    --skip-analytics          Skip analytics types seeding
    --skip-users              Skip user seeding
    --skip-cognito            Skip Cognito user creation (database only)
    --help                    Show this help message

EXAMPLES:
    # Full seeding
    $0 --user-pool-id ap-southeast-1_VTLpFeyhi --client-id 76hpd4tfrp93qf33ue6sr0991g

    # Skip users (roles and analytics only)
    $0 --user-pool-id ap-southeast-1_VTLpFeyhi --client-id 76hpd4tfrp93qf33ue6sr0991g --skip-users

EOF
}

# Parse arguments
SKIP_ROLES=false
SKIP_ANALYTICS=false
SKIP_USERS=false
SKIP_COGNITO=false

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
            --skip-roles)
                SKIP_ROLES=true
                shift
                ;;
            --skip-analytics)
                SKIP_ANALYTICS=true
                shift
                ;;
            --skip-users)
                SKIP_USERS=true
                shift
                ;;
            --skip-cognito)
                SKIP_COGNITO=true
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
}

# Function to seed roles
seed_roles() {
    if [[ "$SKIP_ROLES" == true ]]; then
        log_info "Skipping role seeding"
        return 0
    fi
    
    log_info "🔑 Seeding roles..."
    
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -d "$DB_NAME" -U "$DB_USERNAME" -p "$DB_PORT" -c "
        INSERT INTO roles (id, name, description, createdat) VALUES 
        ('99999999-9999-9999-9999-999999999999', 'Admin', 'System Administrator', CURRENT_TIMESTAMP),
        ('66666666-6666-6666-6666-666666666666', 'Analyst', 'Financial Analyst', CURRENT_TIMESTAMP)
        ON CONFLICT (id) DO NOTHING;
    " || {
        log_error "Failed to seed roles"
        return 1
    }
    
    log_success "✅ Roles seeded successfully"
}

# Function to seed analytics types
seed_analytics_types() {
    if [[ "$SKIP_ANALYTICS" == true ]]; then
        log_info "Skipping analytics types seeding"
        return 0
    fi
    
    log_info "📊 Seeding analytics types..."
    
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -d "$DB_NAME" -U "$DB_USERNAME" -p "$DB_PORT" -c "
        INSERT INTO analytics_type (id, code, name, description, createdat) VALUES 
        (gen_random_uuid(), 'RISK', 'Risk Analysis', 'Phân tích rủi ro tài chính', CURRENT_TIMESTAMP),
        (gen_random_uuid(), 'TREND', 'Trend Analysis', 'Phân tích xu hướng phát triển', CURRENT_TIMESTAMP),
        (gen_random_uuid(), 'COMPARISON', 'Comparative Analysis', 'So sánh giữa các công ty', CURRENT_TIMESTAMP),
        (gen_random_uuid(), 'OPPORTUNITY', 'Opportunity Analysis', 'Phân tích cơ hội đầu tư', CURRENT_TIMESTAMP),
        (gen_random_uuid(), 'EXECUTIVE', 'Executive Summary', 'Tóm tắt tổng quan', CURRENT_TIMESTAMP)
        ON CONFLICT (code) DO NOTHING;
    " || {
        log_error "Failed to seed analytics types"
        return 1
    }
    
    log_success "✅ Analytics types seeded successfully"
}

# Function to seed users
seed_users() {
    if [[ "$SKIP_USERS" == true ]]; then
        log_info "Skipping user seeding"
        return 0
    fi
    
    log_info "👥 Seeding users..."
    
    local user_script="$SCRIPT_DIR/seed-users-complete.sh"
    local args="--user-pool-id $USER_POOL_ID --client-id $CLIENT_ID"
    
    if [[ "$SKIP_COGNITO" == true ]]; then
        args="$args --skip-cognito"
    fi
    
    bash "$user_script" $args || {
        log_error "Failed to seed users"
        return 1
    }
    
    log_success "✅ Users seeded successfully"
}

# Function to verify all seeding
verify_all_seeding() {
    log_info "🔍 Verifying all seeded data..."
    
    # Check roles
    local role_count
    role_count=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -d "$DB_NAME" -U "$DB_USERNAME" -p "$DB_PORT" -t -c "SELECT COUNT(*) FROM roles;" | xargs)
    log_info "Roles in database: $role_count"
    
    # Check analytics types
    local analytics_count
    analytics_count=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -d "$DB_NAME" -U "$DB_USERNAME" -p "$DB_PORT" -t -c "SELECT COUNT(*) FROM analytics_type;" | xargs)
    log_info "Analytics types in database: $analytics_count"
    
    # Check users
    local user_count
    user_count=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -d "$DB_NAME" -U "$DB_USERNAME" -p "$DB_PORT" -t -c "SELECT COUNT(*) FROM users;" | xargs)
    log_info "Users in database: $user_count"
    
    # Show summary
    log_info "Database seeding summary:"
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -d "$DB_NAME" -U "$DB_USERNAME" -p "$DB_PORT" -c "
        SELECT 'Roles' as type, COUNT(*)::text as count FROM roles
        UNION ALL
        SELECT 'Analytics Types' as type, COUNT(*)::text as count FROM analytics_type
        UNION ALL
        SELECT 'Users' as type, COUNT(*)::text as count FROM users;
    "
}

# Function to display final summary
display_final_summary() {
    log_success "🎉 Complete Database Seeding Finished!"
    echo ""
    echo "=== Seeding Summary ==="
    echo "Database: $DB_HOST:$DB_PORT/$DB_NAME"
    echo "User Pool: $USER_POOL_ID"
    echo ""
    echo "=== Seeded Data ==="
    echo "✅ Roles: Admin, Analyst"
    echo "✅ Analytics Types: RISK, TREND, COMPARISON, OPPORTUNITY, EXECUTIVE"
    echo "✅ Users: admin@rag.com (Admin), analyst@rag.com (Analyst)"
    echo ""
    echo "=== Login Credentials ==="
    echo "Admin: admin@rag.com / Admin@123!!"
    echo "Analyst: analyst@rag.com / Analyst@123!!"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Test user authentication"
    echo "2. Verify API endpoints"
    echo "3. Test role-based access control"
    echo "4. Deploy frontend application"
    echo ""
}

# Main execution function
main() {
    log_info "🌱 Starting Complete Database Seeding Process..."
    
    # Parse arguments
    parse_arguments "$@"
    
    if [[ -z "$USER_POOL_ID" || -z "$CLIENT_ID" ]]; then
        log_error "User Pool ID and Client ID are required"
        show_usage
        exit 1
    fi
    
    log_info "Configuration:"
    log_info "  Database: $DB_HOST:$DB_PORT/$DB_NAME"
    log_info "  User Pool: $USER_POOL_ID"
    log_info "  Client ID: $CLIENT_ID"
    log_info "  Skip Roles: $SKIP_ROLES"
    log_info "  Skip Analytics: $SKIP_ANALYTICS"
    log_info "  Skip Users: $SKIP_USERS"
    log_info "  Skip Cognito: $SKIP_COGNITO"
    
    # Execute seeding steps
    seed_roles
    seed_analytics_types
    seed_users
    
    # Verify results
    verify_all_seeding
    
    # Display summary
    display_final_summary
    
    log_success "🌱 Complete database seeding finished successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi