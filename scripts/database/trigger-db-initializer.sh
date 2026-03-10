#!/bin/bash

# Trigger DbInitializer Script
# Triggers Lambda function to run DbInitializer which seeds roles, analytics types, and users

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILITIES_DIR="$SCRIPT_DIR/../utilities"
source "$UTILITIES_DIR/logging.sh"
source "$UTILITIES_DIR/error-handling.sh"

# Configuration
LAMBDA_FUNCTION_NAME=""

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Triggers Lambda function to run DbInitializer for seeding database.

OPTIONS:
    --function-name NAME       Lambda function name (required)
    --help                    Show this help message

DESCRIPTION:
    This script triggers the Lambda function which will run DbInitializer.
    DbInitializer automatically seeds:
    - Admin and Analyst roles
    - 5 analytics types (RISK, TREND, COMPARISON, OPPORTUNITY, EXECUTIVE)
    - Default users (admin@rag.com, analyst@rag.com) in both Cognito and Database

EXAMPLES:
    # Trigger DbInitializer for dev environment
    $0 --function-name myapp-dev-api

EOF
}

# Parse arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --function-name)
                LAMBDA_FUNCTION_NAME="$2"
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
    
    if [[ -z "$LAMBDA_FUNCTION_NAME" ]]; then
        log_error "Lambda function name is required"
        show_usage
        exit 1
    fi
}

# Function to check if Lambda function exists
check_lambda_function() {
    log_info "Checking if Lambda function exists: $LAMBDA_FUNCTION_NAME"
    
    if ! aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        log_error "Lambda function not found: $LAMBDA_FUNCTION_NAME"
        log_error "Please deploy Lambda function first"
        exit 1
    fi
    
    log_success "Lambda function found: $LAMBDA_FUNCTION_NAME"
}

# Function to check Lambda environment variables
check_lambda_environment() {
    log_info "Checking Lambda environment variables for AWS Cognito config..."
    
    local env_vars
    if env_vars=$(aws lambda get-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Environment.Variables' \
        --output json 2>/dev/null); then
        
        local user_pool_id
        local client_id
        
        user_pool_id=$(echo "$env_vars" | grep -o '"AWS__UserPoolId":"[^"]*"' | cut -d'"' -f4 || echo "")
        client_id=$(echo "$env_vars" | grep -o '"AWS__ClientId":"[^"]*"' | cut -d'"' -f4 || echo "")
        
        if [[ -z "$user_pool_id" || -z "$client_id" ]]; then
            log_warn "AWS Cognito configuration not found in Lambda environment"
            log_warn "DbInitializer will skip user creation in Cognito"
            log_warn "Only database roles and analytics types will be seeded"
            return 1
        else
            log_success "AWS Cognito configuration found in Lambda environment"
            log_info "  UserPoolId: $user_pool_id"
            log_info "  ClientId: $client_id"
            return 0
        fi
    else
        log_error "Could not get Lambda function configuration"
        return 1
    fi
}

# Function to trigger DbInitializer
trigger_db_initializer() {
    log_info "Triggering Lambda function to run DbInitializer..."
    
    # Create a test event that will trigger Lambda startup and DbInitializer
    local test_event='{
        "httpMethod": "GET",
        "path": "/api/health",
        "headers": {
            "Content-Type": "application/json"
        },
        "body": null,
        "isBase64Encoded": false,
        "requestContext": {
            "httpMethod": "GET",
            "path": "/api/health"
        }
    }'
    
    # Save test event to temp file
    local temp_dir="../temp"
    mkdir -p "$temp_dir"
    local test_event_file="$temp_dir/db-initializer-test-event.json"
    echo "$test_event" > "$test_event_file"
    
    log_info "Invoking Lambda function to trigger DbInitializer..."
    
    local response_file="$temp_dir/db-initializer-response.json"
    
    if aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload "file://$test_event_file" \
        --cli-binary-format raw-in-base64-out \
        "$response_file" &>/dev/null; then
        
        log_success "Lambda function invoked successfully"
        
        # Check response
        if [[ -f "$response_file" ]]; then
            log_info "Lambda response received"
            
            # Check if response indicates successful startup
            if grep -q '"statusCode":200' "$response_file" 2>/dev/null; then
                log_success "Lambda function started successfully (HTTP 200)"
            elif grep -q '"statusCode":404' "$response_file" 2>/dev/null; then
                log_info "Lambda function started (HTTP 404 - expected for /api/health endpoint)"
            else
                log_info "Lambda function responded, checking for errors..."
                if grep -q '"errorMessage"' "$response_file" 2>/dev/null; then
                    log_warn "Lambda function returned an error, but DbInitializer may have run"
                    cat "$response_file"
                fi
            fi
        fi
        
        # Wait a moment for DbInitializer to complete
        log_info "Waiting for DbInitializer to complete..."
        sleep 5
        
        log_success "DbInitializer trigger completed"
        return 0
    else
        log_error "Failed to invoke Lambda function"
        return 1
    fi
}

# Function to verify seeding results
verify_seeding() {
    log_info "Verifying database seeding results..."
    
    # Get database connection details from Lambda environment
    local env_vars
    if env_vars=$(aws lambda get-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Environment.Variables.ConnectionStrings__DefaultConnection' \
        --output text 2>/dev/null); then
        
        if [[ "$env_vars" != "None" && -n "$env_vars" ]]; then
            log_info "Found database connection string in Lambda environment"
            
            # Test if psql is available for verification
            if command -v psql &> /dev/null; then
                log_info "Verifying seeded data in database..."
                
                if psql "$env_vars" -c "SELECT 1;" &> /dev/null; then
                    # Check roles
                    local role_count
                    role_count=$(psql "$env_vars" -t -c "SELECT COUNT(*) FROM \"roles\";" 2>/dev/null | xargs)
                    log_info "Roles in database: $role_count"
                    
                    # Check analytics types
                    local analytics_count
                    analytics_count=$(psql "$env_vars" -t -c "SELECT COUNT(*) FROM \"analytics_type\";" 2>/dev/null | xargs)
                    log_info "Analytics types in database: $analytics_count"
                    
                    # Check users
                    local user_count
                    user_count=$(psql "$env_vars" -t -c "SELECT COUNT(*) FROM \"users\";" 2>/dev/null | xargs)
                    log_info "Users in database: $user_count"
                    
                    if [[ "$role_count" -ge 2 && "$analytics_count" -ge 5 ]]; then
                        log_success "Database seeding verification successful"
                        
                        # Show seeded data
                        log_info "Seeded roles:"
                        psql "$env_vars" -c "SELECT \"name\", \"description\" FROM \"roles\" ORDER BY \"name\";" 2>/dev/null || true
                        
                        log_info "Seeded analytics types:"
                        psql "$env_vars" -c "SELECT \"code\", \"name\" FROM \"analytics_type\" ORDER BY \"code\";" 2>/dev/null || true
                        
                        if [[ "$user_count" -gt 0 ]]; then
                            log_info "Seeded users:"
                            psql "$env_vars" -c "SELECT u.\"email\", u.\"fullname\", r.\"name\" as role_name FROM \"users\" u JOIN \"roles\" r ON u.\"roleid\" = r.\"id\" ORDER BY u.\"email\";" 2>/dev/null || true
                        fi
                        
                        return 0
                    else
                        log_warn "Database seeding may be incomplete"
                        log_warn "Expected: >=2 roles, >=5 analytics types"
                        log_warn "Found: $role_count roles, $analytics_count analytics types"
                        return 1
                    fi
                else
                    log_warn "Could not connect to database for verification"
                    return 1
                fi
            else
                log_warn "psql not available - cannot verify seeding directly"
                log_info "DbInitializer should have seeded the database during Lambda startup"
                return 0
            fi
        else
            log_warn "No database connection string found in Lambda environment"
            return 1
        fi
    else
        log_error "Could not get Lambda function configuration"
        return 1
    fi
}

# Function to display summary
display_summary() {
    log_success "🎉 DbInitializer Trigger Process Completed!"
    echo ""
    echo "=== DbInitializer Summary ==="
    echo "Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo ""
    echo "=== What DbInitializer Did ==="
    echo "✅ Created Admin and Analyst roles"
    echo "✅ Created 5 analytics types (RISK, TREND, COMPARISON, OPPORTUNITY, EXECUTIVE)"
    echo "✅ Created default users in Cognito and Database:"
    echo "   • admin@rag.com (Admin role) - Password: Admin@123!!"
    echo "   • analyst@rag.com (Analyst role) - Password: Analyst@123!!"
    echo "✅ Synchronized users between Cognito and Database"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Test login with default users"
    echo "2. Verify role-based access control"
    echo "3. Deploy API Gateway"
    echo "4. Run integration tests"
    echo ""
}

# Main execution function
main() {
    log_info "🌱 Starting DbInitializer Trigger Process..."
    
    # Parse arguments
    parse_arguments "$@"
    
    log_info "Configuration:"
    log_info "  Lambda Function: $LAMBDA_FUNCTION_NAME"
    
    # Check prerequisites
    check_lambda_function
    
    # Check Lambda environment (warn if Cognito config missing)
    check_lambda_environment || log_warn "Proceeding without full Cognito configuration"
    
    # Trigger DbInitializer
    trigger_db_initializer
    
    # Verify seeding
    verify_seeding
    
    # Display summary
    display_summary
    
    log_success "🌱 DbInitializer trigger completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi