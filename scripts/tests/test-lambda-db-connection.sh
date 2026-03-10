#!/bin/bash

# Test Lambda-RDS Connection Script
# Tests if Lambda function can connect to RDS database and run queries

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILITIES_DIR="$SCRIPT_DIR/../utilities"
source "$UTILITIES_DIR/logging.sh"
source "$UTILITIES_DIR/error-handling.sh"

# Configuration
LAMBDA_FUNCTION_NAME="${LAMBDA_FUNCTION_NAME:-myapp-dev-api}"
API_GATEWAY_URL="${API_GATEWAY_URL:-}"
TEST_TIMEOUT=30

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Tests Lambda function connection to RDS database.

OPTIONS:
    --function-name NAME       Lambda function name (default: $LAMBDA_FUNCTION_NAME)
    --api-url URL             API Gateway URL for testing
    --timeout SECONDS         Test timeout in seconds (default: $TEST_TIMEOUT)
    --help                    Show this help message

EXAMPLES:
    $0 --function-name myapp-dev-api
    $0 --api-url https://api-id.execute-api.region.amazonaws.com/stage

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
            --api-url)
                API_GATEWAY_URL="$2"
                shift 2
                ;;
            --timeout)
                TEST_TIMEOUT="$2"
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
}

# Function to get API Gateway URL from infrastructure state
get_api_gateway_url() {
    local state_file="./deployment_checkpoints/api_gateway_infrastructure.state"
    
    if [[ -f "$state_file" ]]; then
        local api_url
        api_url=$(grep "^API_URL=" "$state_file" | cut -d'=' -f2 | tr -d '"')
        if [[ -n "$api_url" ]]; then
            API_GATEWAY_URL="$api_url"
            log_info "Found API Gateway URL: $API_GATEWAY_URL"
        fi
    fi
}

# Function to test Lambda function directly
test_lambda_function_direct() {
    log_info "Testing Lambda function directly: $LAMBDA_FUNCTION_NAME"
    
    # Create test event for database connection
    local test_event='{
        "httpMethod": "GET",
        "path": "/health",
        "headers": {
            "Content-Type": "application/json"
        },
        "body": null,
        "isBase64Encoded": false
    }'
    
    log_info "Invoking Lambda function with health check event..."
    
    local response
    if response=$(aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload "$test_event" \
        --cli-read-timeout "$TEST_TIMEOUT" \
        --cli-connect-timeout 10 \
        response.json 2>&1); then
        
        log_success "Lambda function invoked successfully"
        
        # Check response
        if [[ -f "response.json" ]]; then
            log_info "Lambda response:"
            cat response.json | jq . 2>/dev/null || cat response.json
            
            # Check if response indicates successful database connection
            if grep -q "200" response.json 2>/dev/null; then
                log_success "Lambda function appears to be working (HTTP 200)"
                return 0
            elif grep -q "database\|connection\|timeout" response.json 2>/dev/null; then
                log_warn "Lambda response may indicate database connection issues"
                return 1
            else
                log_info "Lambda function responded, checking for errors..."
                if grep -q "errorMessage\|errorType" response.json 2>/dev/null; then
                    log_error "Lambda function returned an error"
                    return 1
                fi
            fi
        fi
        
        return 0
    else
        log_error "Failed to invoke Lambda function:"
        log_error "$response"
        return 1
    fi
}

# Function to test via API Gateway
test_api_gateway() {
    if [[ -z "$API_GATEWAY_URL" ]]; then
        log_warn "No API Gateway URL provided, skipping API Gateway test"
        return 0
    fi
    
    log_info "Testing via API Gateway: $API_GATEWAY_URL"
    
    # Test health endpoint
    local health_url="$API_GATEWAY_URL/health"
    log_info "Testing health endpoint: $health_url"
    
    local response_code
    if response_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time "$TEST_TIMEOUT" "$health_url"); then
        case "$response_code" in
            200)
                log_success "API Gateway health check passed (HTTP $response_code)"
                return 0
                ;;
            404)
                log_warn "Health endpoint not found (HTTP $response_code) - this is expected if no health endpoint exists"
                ;;
            500|502|503|504)
                log_error "API Gateway returned server error (HTTP $response_code) - possible database connection issue"
                return 1
                ;;
            *)
                log_warn "API Gateway returned HTTP $response_code"
                ;;
        esac
    else
        log_error "Failed to connect to API Gateway"
        return 1
    fi
    
    # Test root endpoint
    log_info "Testing root endpoint: $API_GATEWAY_URL/"
    if response_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time "$TEST_TIMEOUT" "$API_GATEWAY_URL/"); then
        case "$response_code" in
            200|404)
                log_info "API Gateway is responding (HTTP $response_code)"
                ;;
            500|502|503|504)
                log_error "API Gateway server error (HTTP $response_code) - possible Lambda or database issue"
                return 1
                ;;
            *)
                log_info "API Gateway responded with HTTP $response_code"
                ;;
        esac
    fi
    
    return 0
}

# Function to check Lambda environment variables
check_lambda_environment() {
    log_info "Checking Lambda environment variables..."
    
    local env_vars
    if env_vars=$(aws lambda get-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Environment.Variables' \
        --output json 2>/dev/null); then
        
        log_info "Lambda environment variables:"
        echo "$env_vars" | jq .
        
        # Check for database connection string
        if echo "$env_vars" | jq -e '.ConnectionStrings__DefaultConnection' >/dev/null 2>&1; then
            log_success "Database connection string found in Lambda environment"
            
            # Extract and validate connection string
            local conn_str
            conn_str=$(echo "$env_vars" | jq -r '.ConnectionStrings__DefaultConnection')
            
            if [[ "$conn_str" == *"Host="* && "$conn_str" == *"Database="* ]]; then
                log_success "Connection string appears to be properly formatted"
                
                # Extract database details
                local host database
                if [[ $conn_str =~ Host=([^;]+) ]]; then
                    host="${BASH_REMATCH[1]}"
                    log_info "Database host: $host"
                fi
                
                if [[ $conn_str =~ Database=([^;]+) ]]; then
                    database="${BASH_REMATCH[1]}"
                    log_info "Database name: $database"
                fi
                
                return 0
            else
                log_error "Connection string appears to be malformed"
                return 1
            fi
        else
            log_error "No database connection string found in Lambda environment"
            return 1
        fi
    else
        log_error "Failed to get Lambda function configuration"
        return 1
    fi
}

# Function to check RDS instance status
check_rds_status() {
    log_info "Checking RDS instance status..."
    
    # Try to find RDS instance from infrastructure state
    local state_file="./deployment_checkpoints/rds_infrastructure.state"
    local db_identifier=""
    
    if [[ -f "$state_file" ]]; then
        db_identifier=$(grep "^DB_INSTANCE_IDENTIFIER=" "$state_file" | cut -d'=' -f2 | tr -d '"')
    fi
    
    if [[ -z "$db_identifier" ]]; then
        log_warn "Could not find RDS instance identifier from state file"
        return 1
    fi
    
    log_info "Checking RDS instance: $db_identifier"
    
    local rds_status
    if rds_status=$(aws rds describe-db-instances \
        --db-instance-identifier "$db_identifier" \
        --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address,PubliclyAccessible:PubliclyAccessible}' \
        --output json 2>/dev/null); then
        
        log_info "RDS instance details:"
        echo "$rds_status" | jq .
        
        local status
        status=$(echo "$rds_status" | jq -r '.Status')
        
        if [[ "$status" == "available" ]]; then
            log_success "RDS instance is available"
            return 0
        else
            log_warn "RDS instance status: $status"
            return 1
        fi
    else
        log_error "Failed to get RDS instance status"
        return 1
    fi
}

# Function to test database connection directly
test_database_connection() {
    log_info "Testing direct database connection..."
    
    # Get connection details from Lambda environment
    local env_vars
    if ! env_vars=$(aws lambda get-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Environment.Variables.ConnectionStrings__DefaultConnection' \
        --output text 2>/dev/null); then
        log_error "Could not get connection string from Lambda"
        return 1
    fi
    
    if [[ "$env_vars" == "None" || -z "$env_vars" ]]; then
        log_error "No connection string found in Lambda environment"
        return 1
    fi
    
    log_info "Testing database connectivity with psql (if available)..."
    
    if command -v psql &> /dev/null; then
        log_info "Testing connection with psql..."
        if timeout 10 psql "$env_vars" -c "SELECT 1;" &> /dev/null; then
            log_success "Direct database connection successful"
            
            # Test if migrations table exists
            if timeout 10 psql "$env_vars" -c "SELECT COUNT(*) FROM \"__EFMigrationsHistory\";" &> /dev/null; then
                log_success "Database migrations table found - migrations have been applied"
                
                # Get migration count
                local migration_count
                migration_count=$(timeout 10 psql "$env_vars" -t -c "SELECT COUNT(*) FROM \"__EFMigrationsHistory\";" 2>/dev/null | xargs)
                log_info "Number of applied migrations: $migration_count"
                
                return 0
            else
                log_warn "Migrations table not found - database may not be properly initialized"
                return 1
            fi
        else
            log_error "Direct database connection failed"
            return 1
        fi
    else
        log_warn "psql not available, skipping direct database test"
        return 0
    fi
}

# Main function
main() {
    log_info "Starting Lambda-RDS connection test..."
    
    parse_arguments "$@"
    
    # Get API Gateway URL if not provided
    if [[ -z "$API_GATEWAY_URL" ]]; then
        get_api_gateway_url
    fi
    
    local test_results=()
    local overall_success=true
    
    # Test 1: Check Lambda environment variables
    log_info "=== Test 1: Lambda Environment Variables ==="
    if check_lambda_environment; then
        test_results+=("✅ Lambda environment variables")
    else
        test_results+=("❌ Lambda environment variables")
        overall_success=false
    fi
    
    # Test 2: Check RDS status
    log_info "=== Test 2: RDS Instance Status ==="
    if check_rds_status; then
        test_results+=("✅ RDS instance status")
    else
        test_results+=("❌ RDS instance status")
        overall_success=false
    fi
    
    # Test 3: Test direct database connection
    log_info "=== Test 3: Direct Database Connection ==="
    if test_database_connection; then
        test_results+=("✅ Direct database connection")
    else
        test_results+=("❌ Direct database connection")
        overall_success=false
    fi
    
    # Test 4: Test Lambda function directly
    log_info "=== Test 4: Lambda Function Direct Test ==="
    if test_lambda_function_direct; then
        test_results+=("✅ Lambda function direct test")
    else
        test_results+=("❌ Lambda function direct test")
        overall_success=false
    fi
    
    # Test 5: Test via API Gateway
    log_info "=== Test 5: API Gateway Test ==="
    if test_api_gateway; then
        test_results+=("✅ API Gateway test")
    else
        test_results+=("❌ API Gateway test")
        overall_success=false
    fi
    
    # Display results
    echo ""
    echo "=== Test Results Summary ==="
    for result in "${test_results[@]}"; do
        echo "  $result"
    done
    echo ""
    
    if [[ "$overall_success" == "true" ]]; then
        log_success "All tests passed! Lambda-RDS connection is working properly."
        return 0
    else
        log_error "Some tests failed. Please check the issues above."
        return 1
    fi
}

# Cleanup function
cleanup() {
    rm -f response.json
}

trap cleanup EXIT

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi