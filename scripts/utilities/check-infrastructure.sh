#!/bin/bash

# AWS Infrastructure Detection and Validation Script
# Detects existing AWS resources and validates their status
# 
# Usage: ./check-infrastructure.sh --environment <environment> [options]
#
# Requirements: 3.3

set -euo pipefail

# Script directory and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"
source "$SCRIPT_DIR/error-handling.sh"

# Script metadata
readonly SCRIPT_NAME="Infrastructure Detection"
readonly SCRIPT_VERSION="1.0.0"

# Default values
DEFAULT_ENVIRONMENT="development"
DEFAULT_LOG_LEVEL="INFO"
DEFAULT_AWS_REGION="us-east-1"

# Global variables
ENVIRONMENT=""
AWS_PROFILE=""
AWS_REGION=""
LOG_LEVEL=""
OUTPUT_FORMAT="text"
CHECK_HEALTH=false
VERBOSE=false

# Infrastructure status tracking
declare -A INFRASTRUCTURE_STATUS
declare -A RESOURCE_DETAILS

# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 --environment <ENVIRONMENT> [OPTIONS]

DESCRIPTION:
    Detects existing AWS infrastructure resources and validates their status.
    Checks RDS instances, Lambda functions, VPC resources, and their health.

REQUIRED ARGUMENTS:
    --environment, -e <ENV>     Target environment to check
                               development|staging|production

OPTIONS:
    --aws-profile <PROFILE>     AWS CLI profile to use (optional)
    --aws-region <REGION>       AWS region (default: $DEFAULT_AWS_REGION)
    --log-level <LEVEL>         Logging level: ERROR|WARN|INFO|DEBUG (default: INFO)
    --output-format <FORMAT>    Output format: text|json|summary (default: text)
    --check-health             Perform health checks on detected resources
    --verbose, -v              Show detailed resource information
    --help, -h                 Show this help message

EXAMPLES:
    # Basic infrastructure check
    $0 --environment production

    # Detailed check with health validation
    $0 --environment staging --check-health --verbose

    # JSON output for automation
    $0 --environment development --output-format json

EXIT CODES:
    0 - Infrastructure found and healthy
    1 - No infrastructure found
    2 - Infrastructure found but unhealthy
    3 - AWS CLI or permission errors
    4 - Invalid arguments
EOF
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --environment|-e)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --aws-profile)
                AWS_PROFILE="$2"
                shift 2
                ;;
            --aws-region)
                AWS_REGION="$2"
                shift 2
                ;;
            --log-level)
                LOG_LEVEL="$2"
                shift 2
                ;;
            --output-format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --check-health)
                CHECK_HEALTH=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_usage
                exit 4
                ;;
        esac
    done
}

# Function to validate arguments
validate_arguments() {
    if [ -z "$ENVIRONMENT" ]; then
        log_error "Environment is required. Use --environment <development|staging|production>"
        exit 4
    fi

    case "$ENVIRONMENT" in
        development|staging|production)
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT"
            exit 4
            ;;
    esac

    case "$OUTPUT_FORMAT" in
        text|json|summary)
            ;;
        *)
            log_error "Invalid output format: $OUTPUT_FORMAT"
            exit 4
            ;;
    esac
}

# Function to set defaults and configure AWS
set_defaults() {
    ENVIRONMENT=${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}
    LOG_LEVEL=${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}
    AWS_REGION=${AWS_REGION:-$DEFAULT_AWS_REGION}

    set_log_level "$LOG_LEVEL"
    export AWS_DEFAULT_REGION="$AWS_REGION"

    if [ -n "$AWS_PROFILE" ]; then
        export AWS_PROFILE="$AWS_PROFILE"
    fi
}

# Function to check RDS instances
check_rds_instances() {
    log_info "Checking RDS instances for environment: $ENVIRONMENT"
    
    local rds_instances
    local instance_count=0
    
    # Query RDS instances that match the environment naming pattern
    rds_instances=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(DBInstanceIdentifier, '$ENVIRONMENT')].[DBInstanceIdentifier,DBInstanceStatus,Endpoint.Address,Endpoint.Port,Engine,EngineVersion,DBInstanceClass,AllocatedStorage]" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$rds_instances" ]; then
        while IFS=$'\t' read -r db_id status endpoint port engine version instance_class storage; do
            if [ -n "$db_id" ]; then
                instance_count=$((instance_count + 1))
                INFRASTRUCTURE_STATUS["rds"]="found"
                RESOURCE_DETAILS["rds_${instance_count}_id"]="$db_id"
                RESOURCE_DETAILS["rds_${instance_count}_status"]="$status"
                RESOURCE_DETAILS["rds_${instance_count}_endpoint"]="$endpoint"
                RESOURCE_DETAILS["rds_${instance_count}_port"]="$port"
                RESOURCE_DETAILS["rds_${instance_count}_engine"]="$engine"
                RESOURCE_DETAILS["rds_${instance_count}_version"]="$version"
                RESOURCE_DETAILS["rds_${instance_count}_class"]="$instance_class"
                RESOURCE_DETAILS["rds_${instance_count}_storage"]="$storage"
                
                log_info "Found RDS instance: $db_id (Status: $status)"
                
                if [ "$VERBOSE" = true ]; then
                    log_info "  Endpoint: $endpoint:$port"
                    log_info "  Engine: $engine $version"
                    log_info "  Instance Class: $instance_class"
                    log_info "  Storage: ${storage}GB"
                fi
            fi
        done <<< "$rds_instances"
        
        RESOURCE_DETAILS["rds_count"]="$instance_count"
    else
        INFRASTRUCTURE_STATUS["rds"]="not_found"
        RESOURCE_DETAILS["rds_count"]="0"
        log_info "No RDS instances found for environment: $ENVIRONMENT"
    fi
}

# Function to check Lambda functions
check_lambda_functions() {
    log_info "Checking Lambda functions for environment: $ENVIRONMENT"
    
    local lambda_functions
    local function_count=0
    
    # Query Lambda functions that match the environment naming pattern
    lambda_functions=$(aws lambda list-functions \
        --query "Functions[?contains(FunctionName, '$ENVIRONMENT')].[FunctionName,Runtime,State,LastModified,MemorySize,Timeout]" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$lambda_functions" ]; then
        while IFS=$'\t' read -r function_name runtime state last_modified memory timeout; do
            if [ -n "$function_name" ]; then
                function_count=$((function_count + 1))
                INFRASTRUCTURE_STATUS["lambda"]="found"
                RESOURCE_DETAILS["lambda_${function_count}_name"]="$function_name"
                RESOURCE_DETAILS["lambda_${function_count}_runtime"]="$runtime"
                RESOURCE_DETAILS["lambda_${function_count}_state"]="$state"
                RESOURCE_DETAILS["lambda_${function_count}_modified"]="$last_modified"
                RESOURCE_DETAILS["lambda_${function_count}_memory"]="$memory"
                RESOURCE_DETAILS["lambda_${function_count}_timeout"]="$timeout"
                
                log_info "Found Lambda function: $function_name (State: $state)"
                
                if [ "$VERBOSE" = true ]; then
                    log_info "  Runtime: $runtime"
                    log_info "  Memory: ${memory}MB, Timeout: ${timeout}s"
                    log_info "  Last Modified: $last_modified"
                fi
            fi
        done <<< "$lambda_functions"
        
        RESOURCE_DETAILS["lambda_count"]="$function_count"
    else
        INFRASTRUCTURE_STATUS["lambda"]="not_found"
        RESOURCE_DETAILS["lambda_count"]="0"
        log_info "No Lambda functions found for environment: $ENVIRONMENT"
    fi
}

# Function to check VPC resources
check_vpc_resources() {
    log_info "Checking VPC resources for environment: $ENVIRONMENT"
    
    local vpcs
    local vpc_count=0
    
    # Query VPCs that match the environment naming pattern
    vpcs=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Environment,Values=$ENVIRONMENT" \
        --query "Vpcs[*].[VpcId,State,CidrBlock]" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$vpcs" ]; then
        while IFS=$'\t' read -r vpc_id state cidr_block; do
            if [ -n "$vpc_id" ]; then
                vpc_count=$((vpc_count + 1))
                INFRASTRUCTURE_STATUS["vpc"]="found"
                RESOURCE_DETAILS["vpc_${vpc_count}_id"]="$vpc_id"
                RESOURCE_DETAILS["vpc_${vpc_count}_state"]="$state"
                RESOURCE_DETAILS["vpc_${vpc_count}_cidr"]="$cidr_block"
                
                log_info "Found VPC: $vpc_id (State: $state)"
                
                if [ "$VERBOSE" = true ]; then
                    log_info "  CIDR Block: $cidr_block"
                    
                    # Check subnets in this VPC
                    local subnets
                    subnets=$(aws ec2 describe-subnets \
                        --filters "Name=vpc-id,Values=$vpc_id" \
                        --query "Subnets[*].[SubnetId,State,CidrBlock,AvailabilityZone]" \
                        --output text 2>/dev/null || echo "")
                    
                    if [ -n "$subnets" ]; then
                        log_info "  Subnets:"
                        while IFS=$'\t' read -r subnet_id subnet_state subnet_cidr az; do
                            if [ -n "$subnet_id" ]; then
                                log_info "    $subnet_id ($subnet_state) - $subnet_cidr in $az"
                            fi
                        done <<< "$subnets"
                    fi
                fi
            fi
        done <<< "$vpcs"
        
        RESOURCE_DETAILS["vpc_count"]="$vpc_count"
    else
        INFRASTRUCTURE_STATUS["vpc"]="not_found"
        RESOURCE_DETAILS["vpc_count"]="0"
        log_info "No VPC resources found for environment: $ENVIRONMENT"
    fi
}

# Function to check IAM roles
check_iam_roles() {
    log_info "Checking IAM roles for environment: $ENVIRONMENT"
    
    local iam_roles
    local role_count=0
    
    # Query IAM roles that match the environment naming pattern
    iam_roles=$(aws iam list-roles \
        --query "Roles[?contains(RoleName, '$ENVIRONMENT')].[RoleName,CreateDate,Arn]" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$iam_roles" ]; then
        while IFS=$'\t' read -r role_name create_date arn; do
            if [ -n "$role_name" ]; then
                role_count=$((role_count + 1))
                INFRASTRUCTURE_STATUS["iam"]="found"
                RESOURCE_DETAILS["iam_${role_count}_name"]="$role_name"
                RESOURCE_DETAILS["iam_${role_count}_created"]="$create_date"
                RESOURCE_DETAILS["iam_${role_count}_arn"]="$arn"
                
                log_info "Found IAM role: $role_name"
                
                if [ "$VERBOSE" = true ]; then
                    log_info "  ARN: $arn"
                    log_info "  Created: $create_date"
                fi
            fi
        done <<< "$iam_roles"
        
        RESOURCE_DETAILS["iam_count"]="$role_count"
    else
        INFRASTRUCTURE_STATUS["iam"]="not_found"
        RESOURCE_DETAILS["iam_count"]="0"
        log_info "No IAM roles found for environment: $ENVIRONMENT"
    fi
}

# Function to perform health checks
perform_health_checks() {
    if [ "$CHECK_HEALTH" != true ]; then
        return 0
    fi
    
    log_info "Performing health checks on detected resources..."
    
    local health_issues=0
    
    # Health check RDS instances
    if [ "${INFRASTRUCTURE_STATUS[rds]:-}" = "found" ]; then
        local rds_count="${RESOURCE_DETAILS[rds_count]:-0}"
        for ((i=1; i<=rds_count; i++)); do
            local db_id="${RESOURCE_DETAILS[rds_${i}_id]:-}"
            local status="${RESOURCE_DETAILS[rds_${i}_status]:-}"
            
            if [ "$status" != "available" ]; then
                log_warn "RDS instance $db_id is not available (Status: $status)"
                health_issues=$((health_issues + 1))
            else
                log_success "RDS instance $db_id is healthy"
            fi
        done
    fi
    
    # Health check Lambda functions
    if [ "${INFRASTRUCTURE_STATUS[lambda]:-}" = "found" ]; then
        local lambda_count="${RESOURCE_DETAILS[lambda_count]:-0}"
        for ((i=1; i<=lambda_count; i++)); do
            local function_name="${RESOURCE_DETAILS[lambda_${i}_name]:-}"
            local state="${RESOURCE_DETAILS[lambda_${i}_state]:-}"
            
            if [ "$state" != "Active" ]; then
                log_warn "Lambda function $function_name is not active (State: $state)"
                health_issues=$((health_issues + 1))
            else
                log_success "Lambda function $function_name is healthy"
            fi
        done
    fi
    
    # Health check VPC resources
    if [ "${INFRASTRUCTURE_STATUS[vpc]:-}" = "found" ]; then
        local vpc_count="${RESOURCE_DETAILS[vpc_count]:-0}"
        for ((i=1; i<=vpc_count; i++)); do
            local vpc_id="${RESOURCE_DETAILS[vpc_${i}_id]:-}"
            local state="${RESOURCE_DETAILS[vpc_${i}_state]:-}"
            
            if [ "$state" != "available" ]; then
                log_warn "VPC $vpc_id is not available (State: $state)"
                health_issues=$((health_issues + 1))
            else
                log_success "VPC $vpc_id is healthy"
            fi
        done
    fi
    
    if [ $health_issues -gt 0 ]; then
        log_warn "Found $health_issues health issues in infrastructure"
        return 2
    else
        log_success "All detected resources are healthy"
        return 0
    fi
}

# Function to output results in text format
output_text_format() {
    echo ""
    echo "========================================"
    echo "Infrastructure Detection Results"
    echo "========================================"
    echo "Environment: $ENVIRONMENT"
    echo "AWS Region: $AWS_REGION"
    echo "Check Time: $(date)"
    echo ""
    
    # Summary
    local total_resources=0
    for service in rds lambda vpc iam; do
        if [ "${INFRASTRUCTURE_STATUS[$service]:-}" = "found" ]; then
            local count="${RESOURCE_DETAILS[${service}_count]:-0}"
            echo "$service: $count resource(s) found"
            total_resources=$((total_resources + count))
        else
            echo "$service: No resources found"
        fi
    done
    
    echo ""
    echo "Total Resources: $total_resources"
    
    if [ $total_resources -gt 0 ]; then
        echo "Infrastructure Status: EXISTS"
    else
        echo "Infrastructure Status: NOT_FOUND"
    fi
    
    echo "========================================"
}

# Function to output results in JSON format
output_json_format() {
    local json_output="{"
    json_output+='"environment":"'$ENVIRONMENT'",'
    json_output+='"region":"'$AWS_REGION'",'
    json_output+='"check_time":"'$(date -Iseconds)'",'
    json_output+='"infrastructure_status":{'
    
    local service_json=""
    for service in rds lambda vpc iam; do
        if [ -n "$service_json" ]; then
            service_json+=","
        fi
        
        if [ "${INFRASTRUCTURE_STATUS[$service]:-}" = "found" ]; then
            local count="${RESOURCE_DETAILS[${service}_count]:-0}"
            service_json+='"'$service'":{"status":"found","count":'$count'}'
        else
            service_json+='"'$service'":{"status":"not_found","count":0}'
        fi
    done
    
    json_output+="$service_json"
    json_output+='},'
    
    # Calculate total resources
    local total_resources=0
    for service in rds lambda vpc iam; do
        if [ "${INFRASTRUCTURE_STATUS[$service]:-}" = "found" ]; then
            local count="${RESOURCE_DETAILS[${service}_count]:-0}"
            total_resources=$((total_resources + count))
        fi
    done
    
    json_output+='"total_resources":'$total_resources','
    
    if [ $total_resources -gt 0 ]; then
        json_output+='"exists":true'
    else
        json_output+='"exists":false'
    fi
    
    json_output+="}"
    
    echo "$json_output"
}

# Function to output results in summary format
output_summary_format() {
    local total_resources=0
    for service in rds lambda vpc iam; do
        if [ "${INFRASTRUCTURE_STATUS[$service]:-}" = "found" ]; then
            local count="${RESOURCE_DETAILS[${service}_count]:-0}"
            total_resources=$((total_resources + count))
        fi
    done
    
    if [ $total_resources -gt 0 ]; then
        echo "EXISTS"
    else
        echo "NOT_FOUND"
    fi
}

# Function to output results based on format
output_results() {
    case "$OUTPUT_FORMAT" in
        text)
            output_text_format
            ;;
        json)
            output_json_format
            ;;
        summary)
            output_summary_format
            ;;
    esac
}

# Function to determine exit code
determine_exit_code() {
    local total_resources=0
    for service in rds lambda vpc iam; do
        if [ "${INFRASTRUCTURE_STATUS[$service]:-}" = "found" ]; then
            local count="${RESOURCE_DETAILS[${service}_count]:-0}"
            total_resources=$((total_resources + count))
        fi
    done
    
    if [ $total_resources -eq 0 ]; then
        return 1  # No infrastructure found
    fi
    
    if [ "$CHECK_HEALTH" = true ]; then
        perform_health_checks
        return $?  # Return health check result
    fi
    
    return 0  # Infrastructure found
}

# Main execution function
main() {
    # Parse arguments
    parse_arguments "$@"
    
    # Validate arguments
    validate_arguments
    
    # Set defaults
    set_defaults
    
    log_info "Starting infrastructure detection for environment: $ENVIRONMENT"
    
    # Initialize status tracking
    INFRASTRUCTURE_STATUS=()
    RESOURCE_DETAILS=()
    
    # Check AWS CLI availability
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI v2."
        exit 3
    fi
    
    # Test AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid."
        log_error "Run 'aws configure' to set up credentials."
        exit 3
    fi
    
    # Perform infrastructure checks
    check_rds_instances
    check_lambda_functions
    check_vpc_resources
    check_iam_roles
    
    # Output results
    output_results
    
    # Determine and return appropriate exit code
    determine_exit_code
    exit $?
}

# Execute main function with all arguments
main "$@"