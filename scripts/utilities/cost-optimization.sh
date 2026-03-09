#!/bin/bash

# Cost Optimization Configuration Utility
# Implements AWS free tier resource selection and cost-optimized configurations
# Provides cost estimation and reporting functionality
# Documents cost implications for different configurations

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/logging.sh"

# AWS Free Tier Limits (as of 2024)
declare -A FREE_TIER_LIMITS=(
    ["rds_hours"]="750"           # 750 hours per month
    ["rds_storage"]="20"          # 20 GB SSD storage
    ["lambda_requests"]="1000000" # 1M requests per month
    ["lambda_compute"]="400000"   # 400,000 GB-seconds per month
    ["ec2_hours"]="750"           # 750 hours per month (t2.micro/t3.micro)
)

# Cost-optimized configurations
declare -A RDS_COST_CONFIG=(
    ["instance_class"]="db.t3.micro"
    ["storage_type"]="gp2"
    ["storage_size"]="20"
    ["multi_az"]="false"
    ["backup_retention"]="0"
    ["storage_encrypted"]="false"
    ["auto_minor_version_upgrade"]="false"
    ["deletion_protection"]="false"
)

declare -A LAMBDA_COST_CONFIG=(
    ["memory_size"]="512"         # MB - cost-effective for most workloads
    ["timeout"]="30"              # seconds - sufficient for DB operations
    ["reserved_concurrency"]=""   # No reserved concurrency to avoid costs
    ["provisioned_concurrency"]="0" # No provisioned concurrency
)

declare -A EC2_COST_CONFIG=(
    ["instance_type"]="t3.micro"  # Free tier eligible
    ["ebs_volume_type"]="gp2"     # General purpose SSD
    ["ebs_volume_size"]="8"       # Minimum size
    ["monitoring"]="false"        # No detailed monitoring
)

# Regional cost factors (relative to us-east-1)
declare -A REGIONAL_COST_FACTORS=(
    ["us-east-1"]="1.00"
    ["us-west-2"]="1.05"
    ["eu-west-1"]="1.10"
    ["ap-southeast-1"]="1.15"     # Singapore - closest to Vietnam
    ["ap-northeast-1"]="1.12"     # Tokyo
)
# Function to check if resource is free tier eligible
is_free_tier_eligible() {
    local resource_type="$1"
    local configuration="$2"
    
    case "$resource_type" in
        "rds")
            local instance_class=$(echo "$configuration" | grep -o 'instance_class=[^,]*' | cut -d= -f2)
            local storage_size=$(echo "$configuration" | grep -o 'storage_size=[^,]*' | cut -d= -f2)
            
            if [ "$instance_class" = "db.t3.micro" ] && [ "$storage_size" -le "20" ]; then
                return 0
            fi
            ;;
        "lambda")
            # Lambda is always free tier eligible up to usage limits
            return 0
            ;;
        "ec2")
            local instance_type=$(echo "$configuration" | grep -o 'instance_type=[^,]*' | cut -d= -f2)
            if [ "$instance_type" = "t3.micro" ] || [ "$instance_type" = "t2.micro" ]; then
                return 0
            fi
            ;;
    esac
    
    return 1
}

# Function to get cost-optimized RDS configuration
get_rds_cost_config() {
    local environment="${1:-dev}"
    local workload_type="${2:-light}"  # light, medium, heavy
    
    if [ "${LOG_LEVEL:-INFO}" != "ERROR" ]; then
        log_info "Generating cost-optimized RDS configuration for $environment environment"
    fi
    
    local config=""
    
    case "$workload_type" in
        "light")
            config="instance_class=db.t3.micro,storage_size=20,storage_type=gp2"
            ;;
        "medium")
            config="instance_class=db.t3.small,storage_size=50,storage_type=gp2"
            ;;
        "heavy")
            config="instance_class=db.t3.medium,storage_size=100,storage_type=gp2"
            ;;
    esac
    
    # Add common cost optimization settings
    config="$config,multi_az=false,backup_retention=0,storage_encrypted=false"
    
    # Production environment adjustments
    if [ "$environment" = "production" ]; then
        config=$(echo "$config" | sed 's/backup_retention=0/backup_retention=7/')
        config=$(echo "$config" | sed 's/storage_encrypted=false/storage_encrypted=true/')
        if [ "${LOG_LEVEL:-INFO}" != "ERROR" ]; then
            log_warn "Production environment: Enabled backups and encryption (additional costs apply)"
        fi
    fi
    
    echo "$config"
}

# Function to get cost-optimized Lambda configuration
get_lambda_cost_config() {
    local environment="${1:-dev}"
    local workload_type="${2:-light}"  # light, medium, heavy
    
    if [ "${LOG_LEVEL:-INFO}" != "ERROR" ]; then
        log_info "Generating cost-optimized Lambda configuration for $environment environment"
    fi
    
    local memory_size timeout
    
    case "$workload_type" in
        "light")
            memory_size="512"
            timeout="30"
            ;;
        "medium")
            memory_size="1024"
            timeout="60"
            ;;
        "heavy")
            memory_size="2048"
            timeout="300"
            ;;
    esac
    
    echo "memory_size=$memory_size,timeout=$timeout,reserved_concurrency=,provisioned_concurrency=0"
}
# Function to estimate monthly costs
estimate_monthly_cost() {
    local resource_type="$1"
    local configuration="$2"
    local region="${3:-us-east-1}"
    local usage_hours="${4:-730}"  # Default: full month
    
    local base_cost=0
    local regional_factor_int=100  # Use integer arithmetic (100 = 1.00)
    
    # Get regional factor as integer (multiply by 100)
    case "$region" in
        "us-east-1") regional_factor_int=100 ;;
        "us-west-2") regional_factor_int=105 ;;
        "eu-west-1") regional_factor_int=110 ;;
        "ap-southeast-1") regional_factor_int=115 ;;
        "ap-northeast-1") regional_factor_int=112 ;;
        *) regional_factor_int=100 ;;
    esac
    
    case "$resource_type" in
        "rds")
            local instance_class=$(echo "$configuration" | grep -o 'instance_class=[^,]*' | cut -d= -f2)
            local storage_size=$(echo "$configuration" | grep -o 'storage_size=[^,]*' | cut -d= -f2)
            
            # RDS instance costs (cents per hour to avoid floating point)
            local hourly_cost_cents=0
            case "$instance_class" in
                "db.t3.micro") hourly_cost_cents=2 ;;  # $0.017 * 100 = 1.7, rounded to 2
                "db.t3.small") hourly_cost_cents=3 ;;  # $0.034 * 100 = 3.4, rounded to 3
                "db.t3.medium") hourly_cost_cents=7 ;; # $0.068 * 100 = 6.8, rounded to 7
                *) hourly_cost_cents=0 ;;
            esac
            
            # Calculate instance cost in cents
            local instance_cost_cents=$((hourly_cost_cents * usage_hours))
            
            # Add storage costs (11.5 cents per GB per month for gp2)
            local storage_cost_cents=$((storage_size * 12))  # $0.115 * 100 = 11.5, rounded to 12
            base_cost=$((instance_cost_cents + storage_cost_cents))
            ;;
        "lambda")
            local memory_size=$(echo "$configuration" | grep -o 'memory_size=[^,]*' | cut -d= -f2)
            local requests="${5:-100000}"  # Default: 100K requests per month
            
            # Lambda pricing: very small costs, use simplified calculation
            # Assume 1 second average duration, calculate GB-seconds
            local gb_seconds=$((memory_size * requests / 1024))
            
            # Compute cost (simplified): $0.0000166667 per GB-second + $0.20 per 1M requests
            # Convert to cents: 0.00167 cents per GB-second + 20 cents per 1M requests
            local compute_cost_cents=$((gb_seconds * 167 / 100000))  # Simplified calculation
            local request_cost_cents=$((requests * 20 / 1000000))
            base_cost=$((compute_cost_cents + request_cost_cents))
            ;;
    esac
    
    # Apply regional factor
    local total_cost_cents=$((base_cost * regional_factor_int / 100))
    
    # Convert back to dollars and format
    local dollars=$((total_cost_cents / 100))
    local cents=$((total_cost_cents % 100))
    
    printf "%d.%02d" "$dollars" "$cents"
}

# Function to check free tier usage
check_free_tier_usage() {
    local resource_type="$1"
    local configuration="$2"
    local usage_hours="${3:-730}"
    
    log_info "Checking free tier eligibility for $resource_type"
    
    case "$resource_type" in
        "rds")
            if is_free_tier_eligible "$resource_type" "$configuration"; then
                if [ "$usage_hours" -le "${FREE_TIER_LIMITS[rds_hours]}" ]; then
                    log_success "RDS usage ($usage_hours hours) is within free tier limits (${FREE_TIER_LIMITS[rds_hours]} hours)"
                    return 0
                else
                    log_warn "RDS usage ($usage_hours hours) exceeds free tier limits (${FREE_TIER_LIMITS[rds_hours]} hours)"
                    local excess_hours=$((usage_hours - FREE_TIER_LIMITS[rds_hours]))
                    log_warn "Excess hours: $excess_hours (will incur charges)"
                fi
            else
                log_warn "RDS configuration is not free tier eligible"
            fi
            ;;
        "lambda")
            log_success "Lambda is free tier eligible up to ${FREE_TIER_LIMITS[lambda_requests]} requests and ${FREE_TIER_LIMITS[lambda_compute]} GB-seconds per month"
            return 0
            ;;
    esac
    
    return 1
}

# Function to generate cost optimization recommendations
generate_cost_recommendations() {
    local environment="$1"
    local current_config="$2"
    
    log_info "Generating cost optimization recommendations for $environment environment"
    
    echo ""
    echo "=== Cost Optimization Recommendations ==="
    echo ""
    
    # General recommendations
    echo "1. Resource Sizing:"
    echo "   - Start with smallest instance sizes and scale up based on actual usage"
    echo "   - Use AWS CloudWatch to monitor resource utilization"
    echo "   - Consider scheduled scaling for predictable workloads"
    echo ""
    
    echo "2. Free Tier Utilization:"
    echo "   - RDS: Use db.t3.micro with ≤20GB storage for free tier eligibility"
    echo "   - Lambda: First 1M requests and 400,000 GB-seconds are free monthly"
    echo "   - EC2: 750 hours of t3.micro instances are free monthly"
    echo ""
    
    echo "3. Regional Considerations:"
    echo "   - us-east-1: Lowest cost region (baseline)"
    echo "   - ap-southeast-1: ~15% higher costs (closest to Vietnam)"
    echo "   - Consider data transfer costs for cross-region access"
    echo ""
    
    echo "4. Environment-Specific Optimizations:"
    if [ "$environment" = "development" ]; then
        echo "   Development Environment:"
        echo "   - Use smallest instance sizes"
        echo "   - Disable backups and encryption"
        echo "   - Consider stopping resources when not in use"
        echo "   - Use single-AZ deployments"
    elif [ "$environment" = "production" ]; then
        echo "   Production Environment:"
        echo "   - Enable backups and encryption (security vs cost trade-off)"
        echo "   - Consider Reserved Instances for predictable workloads"
        echo "   - Monitor and set up billing alerts"
        echo "   - Use Auto Scaling to optimize resource usage"
    fi
    echo ""
}
# Function to create cost estimation report
create_cost_report() {
    local environment="$1"
    local region="${2:-us-east-1}"
    local workload_type="${3:-light}"
    local output_file="${4:-cost-estimation-report.md}"
    
    log_info "Creating cost estimation report for $environment environment"
    
    # Get optimized configurations (suppress logging for clean report)
    local rds_config=$(LOG_LEVEL=ERROR get_rds_cost_config "$environment" "$workload_type")
    local lambda_config=$(LOG_LEVEL=ERROR get_lambda_cost_config "$environment" "$workload_type")
    
    # Estimate costs
    local rds_cost=$(estimate_monthly_cost "rds" "$rds_config" "$region")
    local lambda_cost=$(estimate_monthly_cost "lambda" "$lambda_config" "$region" "730" "100000")
    
    # Calculate total cost using shell arithmetic
    local rds_cost_cents=$(echo "$rds_cost" | sed 's/\.//' | sed 's/^0*//')
    local lambda_cost_cents=$(echo "$lambda_cost" | sed 's/\.//' | sed 's/^0*//')
    rds_cost_cents=${rds_cost_cents:-0}
    lambda_cost_cents=${lambda_cost_cents:-0}
    local total_cost_cents=$((rds_cost_cents + lambda_cost_cents))
    local total_cost_dollars=$((total_cost_cents / 100))
    local total_cost_remainder=$((total_cost_cents % 100))
    local total_cost=$(printf "%d.%02d" "$total_cost_dollars" "$total_cost_remainder")
    
    # Create report
    cat > "$output_file" << EOF
# AWS Deployment Cost Estimation Report

**Generated on:** $(date)  
**Environment:** $environment  
**Region:** $region  
**Workload Type:** $workload_type  

## Cost Summary

| Service | Configuration | Monthly Cost (USD) | Free Tier Eligible |
|---------|---------------|-------------------|-------------------|
| RDS PostgreSQL | $(echo "$rds_config" | tr ',' ' ') | \$${rds_cost} | $(is_free_tier_eligible "rds" "$rds_config" && echo "Yes" || echo "No") |
| Lambda | $(echo "$lambda_config" | tr ',' ' ') | \$${lambda_cost} | Yes (up to limits) |
| **Total** | | **\$$(printf "%s" "$total_cost")** | |

## Configuration Details

### RDS PostgreSQL
\`\`\`
$(echo "$rds_config" | tr ',' '\n' | sed 's/^/  /')
\`\`\`

### Lambda Function
\`\`\`
$(echo "$lambda_config" | tr ',' '\n' | sed 's/^/  /')
\`\`\`

## Free Tier Analysis

### RDS PostgreSQL
- **Free Tier Limit:** 750 hours per month (db.t3.micro)
- **Storage Limit:** 20 GB SSD storage
- **Current Config:** $(is_free_tier_eligible "rds" "$rds_config" && echo "Eligible" || echo "Not eligible")

### Lambda
- **Free Tier Limits:**
  - 1,000,000 requests per month
  - 400,000 GB-seconds of compute time per month
- **Estimated Usage:** 100,000 requests (well within limits)

## Cost Optimization Recommendations

### Immediate Optimizations
1. **Use Free Tier Resources:** Current configuration $(is_free_tier_eligible "rds" "$rds_config" && echo "utilizes" || echo "does not utilize") RDS free tier
2. **Regional Selection:** $region has a cost factor of ${REGIONAL_COST_FACTORS[$region]:-1.00}x compared to us-east-1
3. **Resource Scheduling:** Consider stopping development resources when not in use

### Long-term Optimizations
1. **Reserved Instances:** For production workloads, consider 1-year Reserved Instances for ~30% savings
2. **Monitoring:** Set up CloudWatch billing alerts at \$10, \$25, and \$50 thresholds
3. **Auto Scaling:** Implement Lambda concurrency controls and RDS connection pooling

## Regional Cost Comparison

| Region | Cost Factor | Monthly Total |
|--------|-------------|---------------|
| us-east-1 | 1.00x | \$$(estimate_monthly_cost "rds" "$rds_config" "us-east-1") + \$$(estimate_monthly_cost "lambda" "$lambda_config" "us-east-1") |
| us-west-2 | 1.05x | \$$(estimate_monthly_cost "rds" "$rds_config" "us-west-2") + \$$(estimate_monthly_cost "lambda" "$lambda_config" "us-west-2") |
| ap-southeast-1 | 1.15x | \$$(estimate_monthly_cost "rds" "$rds_config" "ap-southeast-1") + \$$(estimate_monthly_cost "lambda" "$lambda_config" "ap-southeast-1") |

## Vietnamese Context Considerations

### Recommended Regions for Vietnam
1. **ap-southeast-1 (Singapore):** Lowest latency, ~15% higher costs
2. **ap-northeast-1 (Tokyo):** Good latency, ~12% higher costs
3. **us-east-1 (Virginia):** Lowest cost, higher latency

### Cost Management Tips
- Monitor exchange rates (USD to VND) for budget planning
- Consider business hours scheduling for development environments
- Use AWS Cost Explorer for detailed cost analysis

---
*This report provides estimates based on AWS pricing as of 2024. Actual costs may vary based on usage patterns, data transfer, and other factors.*
EOF

    log_success "Cost estimation report created: $output_file"
    echo "Report location: $(pwd)/$output_file"
}

# Function to validate cost optimization settings
validate_cost_settings() {
    local resource_type="$1"
    local configuration="$2"
    
    log_info "Validating cost optimization settings for $resource_type"
    
    case "$resource_type" in
        "rds")
            local instance_class=$(echo "$configuration" | grep -o 'instance_class=[^,]*' | cut -d= -f2)
            local storage_size=$(echo "$configuration" | grep -o 'storage_size=[^,]*' | cut -d= -f2)
            local multi_az=$(echo "$configuration" | grep -o 'multi_az=[^,]*' | cut -d= -f2)
            
            # Validate instance class
            case "$instance_class" in
                "db.t3.micro"|"db.t3.small"|"db.t3.medium")
                    log_success "Instance class $instance_class is cost-optimized"
                    ;;
                *)
                    log_warn "Instance class $instance_class may not be cost-optimized"
                    ;;
            esac
            
            # Validate storage size
            if [ "$storage_size" -le 100 ]; then
                log_success "Storage size ${storage_size}GB is reasonable for cost optimization"
            else
                log_warn "Storage size ${storage_size}GB is large - consider if all storage is needed"
            fi
            
            # Validate Multi-AZ
            if [ "$multi_az" = "false" ]; then
                log_success "Single-AZ deployment reduces costs"
            else
                log_warn "Multi-AZ deployment increases costs (~2x)"
            fi
            ;;
        "lambda")
            local memory_size=$(echo "$configuration" | grep -o 'memory_size=[^,]*' | cut -d= -f2)
            local timeout=$(echo "$configuration" | grep -o 'timeout=[^,]*' | cut -d= -f2)
            
            # Validate memory size
            if [ "$memory_size" -le 1024 ]; then
                log_success "Memory size ${memory_size}MB is cost-optimized"
            else
                log_warn "Memory size ${memory_size}MB is high - monitor if all memory is utilized"
            fi
            
            # Validate timeout
            if [ "$timeout" -le 60 ]; then
                log_success "Timeout ${timeout}s is reasonable"
            else
                log_warn "Timeout ${timeout}s is high - consider optimizing function performance"
            fi
            ;;
    esac
}
# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Cost optimization utility for AWS deployment automation.

COMMANDS:
    config          Generate cost-optimized configuration
    estimate        Estimate monthly costs
    report          Create detailed cost estimation report
    validate        Validate cost optimization settings
    recommendations Generate cost optimization recommendations

OPTIONS:
    --environment ENV       Environment (dev, staging, production)
    --region REGION         AWS region (default: us-east-1)
    --workload TYPE         Workload type (light, medium, heavy)
    --resource TYPE         Resource type (rds, lambda, ec2)
    --config CONFIG         Resource configuration string
    --output FILE           Output file for reports
    --help                  Show this help message

EXAMPLES:
    # Generate RDS cost-optimized config for production
    $0 config --resource rds --environment production --workload medium

    # Estimate Lambda costs
    $0 estimate --resource lambda --config "memory_size=512,timeout=30"

    # Create comprehensive cost report
    $0 report --environment production --region ap-southeast-1 --output prod-costs.md

    # Validate RDS configuration
    $0 validate --resource rds --config "instance_class=db.t3.micro,storage_size=20"

    # Get cost recommendations
    $0 recommendations --environment dev

EOF
}

# Main function to handle command-line interface
main() {
    local command=""
    local environment="dev"
    local region="us-east-1"
    local workload_type="light"
    local resource_type=""
    local configuration=""
    local output_file=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            config|estimate|report|validate|recommendations)
                command="$1"
                shift
                ;;
            --environment)
                environment="$2"
                shift 2
                ;;
            --region)
                region="$2"
                shift 2
                ;;
            --workload)
                workload_type="$2"
                shift 2
                ;;
            --resource)
                resource_type="$2"
                shift 2
                ;;
            --config)
                configuration="$2"
                shift 2
                ;;
            --output)
                output_file="$2"
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
    
    # Execute command
    case "$command" in
        "config")
            if [ -z "$resource_type" ]; then
                log_error "Resource type is required for config command"
                exit 1
            fi
            
            case "$resource_type" in
                "rds")
                    get_rds_cost_config "$environment" "$workload_type"
                    ;;
                "lambda")
                    get_lambda_cost_config "$environment" "$workload_type"
                    ;;
                *)
                    log_error "Unsupported resource type: $resource_type"
                    exit 1
                    ;;
            esac
            ;;
        "estimate")
            if [ -z "$resource_type" ] || [ -z "$configuration" ]; then
                log_error "Resource type and configuration are required for estimate command"
                exit 1
            fi
            
            local cost=$(estimate_monthly_cost "$resource_type" "$configuration" "$region")
            echo "Estimated monthly cost: \$${cost} USD"
            ;;
        "report")
            local report_file="${output_file:-cost-estimation-report.md}"
            create_cost_report "$environment" "$region" "$workload_type" "$report_file"
            ;;
        "validate")
            if [ -z "$resource_type" ] || [ -z "$configuration" ]; then
                log_error "Resource type and configuration are required for validate command"
                exit 1
            fi
            
            validate_cost_settings "$resource_type" "$configuration"
            ;;
        "recommendations")
            generate_cost_recommendations "$environment" "$configuration"
            ;;
        "")
            log_error "Command is required"
            show_usage
            exit 1
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Export functions for use in other scripts
export -f is_free_tier_eligible get_rds_cost_config get_lambda_cost_config
export -f estimate_monthly_cost check_free_tier_usage validate_cost_settings
export -f generate_cost_recommendations create_cost_report

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi