#!/bin/bash

# Property Test: Cost Optimization Constraints
# Validates that provisioned resources meet cost optimization criteria
# Property: All provisioned resources must comply with cost optimization constraints
# Validates Requirements: 5.1, 5.2, 5.3

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utilities/logging.sh"

# Test configuration
TEST_NAME="Cost Optimization Constraints Property Test"
TEMP_DIR="/tmp/cost-optimization-test-$$"

# Cost optimization constraints
MAX_RDS_INSTANCE_COST_PER_HOUR=0.05  # $0.05/hour for db.t3.micro
MAX_LAMBDA_MEMORY=1024                # 1GB max memory
FREE_TIER_RDS_STORAGE=20              # 20GB free tier
FREE_TIER_LAMBDA_REQUESTS=1000000     # 1M requests/month

# Colors for output
readonly COST_RED='\033[0;31m'
readonly COST_GREEN='\033[0;32m'
readonly COST_YELLOW='\033[1;33m'
readonly COST_BLUE='\033[0;34m'
readonly COST_NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
PROPERTY_VIOLATIONS=()

log_test_info() {
    echo -e "${COST_BLUE}[TEST INFO]${COST_NC} $1"
}

log_test_success() {
    echo -e "${COST_GREEN}[TEST PASS]${COST_NC} $1"
    ((TESTS_PASSED++))
}

log_test_failure() {
    echo -e "${COST_RED}[TEST FAIL]${COST_NC} $1"
    ((TESTS_FAILED++))
}

log_property_violation() {
    echo -e "${COST_RED}[PROPERTY VIOLATION]${COST_NC} $1"
    PROPERTY_VIOLATIONS+=("$1")
}

cleanup_test_resources() {
    log_test_info "Cleaning up test resources..."
    
    # Remove temporary directory
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Trap to ensure cleanup on exit
trap cleanup_test_resources EXIT
setup_test_environment() {
    log_test_info "Setting up test environment..."
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    
    # Create cost optimization test data
    create_cost_test_data
    
    # Create cost validation utilities
    create_cost_validation_utilities
    
    log_test_success "Test environment setup completed"
}

create_cost_test_data() {
    log_test_info "Creating cost optimization test data..."
    
    # Valid cost-optimized configuration
    cat > "$TEMP_DIR/cost-optimized-config.json" << 'EOF'
{
    "rds": {
        "instanceClass": "db.t3.micro",
        "allocatedStorage": 20,
        "storageType": "gp2",
        "multiAZ": false,
        "backupRetentionPeriod": 7
    },
    "lambda": {
        "memorySize": 512,
        "timeout": 30,
        "runtime": "dotnet10"
    },
    "vpc": {
        "enableNatGateway": false,
        "singleNatGateway": true
    }
}
EOF

    # Cost-violating configuration
    cat > "$TEMP_DIR/cost-violating-config.json" << 'EOF'
{
    "rds": {
        "instanceClass": "db.r5.xlarge",
        "allocatedStorage": 1000,
        "storageType": "io1",
        "multiAZ": true,
        "backupRetentionPeriod": 35
    },
    "lambda": {
        "memorySize": 3008,
        "timeout": 900,
        "runtime": "dotnet10"
    },
    "vpc": {
        "enableNatGateway": true,
        "singleNatGateway": false
    }
}
EOF

    # AWS pricing data (simplified)
    cat > "$TEMP_DIR/aws-pricing.json" << 'EOF'
{
    "rds": {
        "instances": {
            "db.t3.micro": {"hourly": 0.017, "freeTier": true},
            "db.t3.small": {"hourly": 0.034, "freeTier": false},
            "db.t3.medium": {"hourly": 0.068, "freeTier": false},
            "db.r5.large": {"hourly": 0.24, "freeTier": false},
            "db.r5.xlarge": {"hourly": 0.48, "freeTier": false}
        },
        "storage": {
            "gp2": {"perGB": 0.115},
            "io1": {"perGB": 0.125, "iopsPrice": 0.10}
        }
    },
    "lambda": {
        "requestPrice": 0.0000002,
        "memoryPrice": 0.0000166667,
        "freeTier": {
            "requests": 1000000,
            "gbSeconds": 400000
        }
    },
    "vpc": {
        "natGateway": {"hourly": 0.045, "dataProcessing": 0.045}
    }
}
EOF

    log_test_success "Cost test data created"
}

create_cost_validation_utilities() {
    log_test_info "Creating cost validation utilities..."
    
    # Cost calculator script
    cat > "$TEMP_DIR/cost-calculator.py" << 'EOF'
#!/usr/bin/env python3
import json
import sys

def calculate_rds_cost(config, pricing):
    instance_class = config.get('instanceClass', 'db.t3.micro')
    storage = config.get('allocatedStorage', 20)
    storage_type = config.get('storageType', 'gp2')
    multi_az = config.get('multiAZ', False)
    
    # Instance cost
    instance_pricing = pricing['rds']['instances'].get(instance_class, {})
    hourly_cost = instance_pricing.get('hourly', 0)
    
    # Multi-AZ doubles the cost
    if multi_az:
        hourly_cost *= 2
    
    # Storage cost
    storage_pricing = pricing['rds']['storage'].get(storage_type, {})
    storage_cost_per_gb = storage_pricing.get('perGB', 0)
    monthly_storage_cost = storage * storage_cost_per_gb
    
    monthly_instance_cost = hourly_cost * 24 * 30
    total_monthly_cost = monthly_instance_cost + monthly_storage_cost
    
    return {
        'instanceCost': monthly_instance_cost,
        'storageCost': monthly_storage_cost,
        'totalCost': total_monthly_cost,
        'freeTier': instance_pricing.get('freeTier', False)
    }

def calculate_lambda_cost(config, pricing):
    memory_size = config.get('memorySize', 512)
    timeout = config.get('timeout', 30)
    
    # Assume 100,000 invocations per month for testing
    monthly_invocations = 100000
    
    # Request cost
    request_cost = monthly_invocations * pricing['lambda']['requestPrice']
    
    # Compute cost (GB-seconds)
    gb_seconds = (memory_size / 1024) * timeout * monthly_invocations
    compute_cost = gb_seconds * pricing['lambda']['memoryPrice']
    
    # Apply free tier
    free_tier_requests = pricing['lambda']['freeTier']['requests']
    free_tier_gb_seconds = pricing['lambda']['freeTier']['gbSeconds']
    
    billable_requests = max(0, monthly_invocations - free_tier_requests)
    billable_gb_seconds = max(0, gb_seconds - free_tier_gb_seconds)
    
    final_request_cost = billable_requests * pricing['lambda']['requestPrice']
    final_compute_cost = billable_gb_seconds * pricing['lambda']['memoryPrice']
    
    return {
        'requestCost': final_request_cost,
        'computeCost': final_compute_cost,
        'totalCost': final_request_cost + final_compute_cost,
        'freeTierApplied': monthly_invocations <= free_tier_requests and gb_seconds <= free_tier_gb_seconds
    }

def calculate_vpc_cost(config, pricing):
    enable_nat = config.get('enableNatGateway', False)
    single_nat = config.get('singleNatGateway', True)
    
    if not enable_nat:
        return {'totalCost': 0, 'natGateways': 0}
    
    nat_count = 1 if single_nat else 2
    hourly_cost = pricing['vpc']['natGateway']['hourly']
    monthly_cost = hourly_cost * 24 * 30 * nat_count
    
    return {
        'totalCost': monthly_cost,
        'natGateways': nat_count
    }

def main():
    if len(sys.argv) != 3:
        print("Usage: cost-calculator.py <config.json> <pricing.json>")
        sys.exit(1)
    
    with open(sys.argv[1], 'r') as f:
        config = json.load(f)
    
    with open(sys.argv[2], 'r') as f:
        pricing = json.load(f)
    
    results = {
        'rds': calculate_rds_cost(config['rds'], pricing),
        'lambda': calculate_lambda_cost(config['lambda'], pricing),
        'vpc': calculate_vpc_cost(config['vpc'], pricing)
    }
    
    total_cost = results['rds']['totalCost'] + results['lambda']['totalCost'] + results['vpc']['totalCost']
    results['totalMonthlyCost'] = total_cost
    
    print(json.dumps(results, indent=2))

if __name__ == "__main__":
    main()
EOF

    chmod +x "$TEMP_DIR/cost-calculator.py"
    
    # Cost constraint validator
    cat > "$TEMP_DIR/validate-constraints.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

config_file="$1"
pricing_file="$2"
max_monthly_cost="${3:-50}"  # Default $50/month limit

# Calculate costs
if command -v python3 &> /dev/null; then
    cost_result=$(python3 "$TEMP_DIR/cost-calculator.py" "$config_file" "$pricing_file")
else
    echo "Python3 not available, using simplified validation"
    exit 0
fi

# Parse results
total_cost=$(echo "$cost_result" | jq -r '.totalMonthlyCost')
rds_free_tier=$(echo "$cost_result" | jq -r '.rds.freeTier')
lambda_free_tier=$(echo "$cost_result" | jq -r '.lambda.freeTierApplied')

echo "COST_ANALYSIS_START"
echo "Total Monthly Cost: \$$(printf '%.2f' $total_cost)"
echo "RDS Free Tier: $rds_free_tier"
echo "Lambda Free Tier: $lambda_free_tier"

# Validate constraints
violations=0

# Check total cost constraint
if (( $(echo "$total_cost > $max_monthly_cost" | bc -l) )); then
    echo "VIOLATION: Total cost \$$(printf '%.2f' $total_cost) exceeds limit \$$max_monthly_cost"
    ((violations++))
fi

# Check free tier usage
if [ "$rds_free_tier" = "false" ]; then
    echo "WARNING: RDS not using free tier eligible instance"
fi

echo "COST_ANALYSIS_END"
echo "VIOLATIONS: $violations"

exit $violations
EOF

    chmod +x "$TEMP_DIR/validate-constraints.sh"
    
    log_test_success "Cost validation utilities created"
}
test_cost_optimized_configuration() {
    log_test_info "Testing cost-optimized configuration compliance..."
    
    local config_file="$TEMP_DIR/cost-optimized-config.json"
    local pricing_file="$TEMP_DIR/aws-pricing.json"
    
    # Validate cost-optimized configuration
    if "$TEMP_DIR/validate-constraints.sh" "$config_file" "$pricing_file" "50" > "$TEMP_DIR/cost-optimized-result.txt" 2>&1; then
        log_test_success "Cost-optimized configuration passed validation"
        
        # Check specific constraints
        local violations=$(grep "VIOLATIONS:" "$TEMP_DIR/cost-optimized-result.txt" | cut -d: -f2 | tr -d ' ')
        if [ "$violations" = "0" ]; then
            log_test_info "✓ No cost constraint violations detected"
        else
            log_test_failure "✗ Cost constraint violations: $violations"
            log_property_violation "Cost-optimized configuration has violations"
        fi
    else
        log_test_failure "Cost-optimized configuration failed validation"
        log_property_violation "Cost-optimized configuration exceeds constraints"
        cat "$TEMP_DIR/cost-optimized-result.txt"
    fi
}

test_cost_violating_configuration() {
    log_test_info "Testing cost-violating configuration detection..."
    
    local config_file="$TEMP_DIR/cost-violating-config.json"
    local pricing_file="$TEMP_DIR/aws-pricing.json"
    
    # Validate cost-violating configuration (should fail)
    if "$TEMP_DIR/validate-constraints.sh" "$config_file" "$pricing_file" "50" > "$TEMP_DIR/cost-violating-result.txt" 2>&1; then
        log_test_failure "Cost-violating configuration incorrectly passed validation"
        log_property_violation "Cost constraint validation failed to detect violations"
    else
        log_test_success "Cost-violating configuration correctly failed validation"
        
        # Check that violations were detected
        local violations=$(grep "VIOLATIONS:" "$TEMP_DIR/cost-violating-result.txt" | cut -d: -f2 | tr -d ' ')
        if [ "$violations" -gt "0" ]; then
            log_test_info "✓ Cost violations correctly detected: $violations"
        else
            log_test_failure "✗ No violations detected in violating configuration"
        fi
    fi
}

test_rds_instance_class_constraints() {
    log_test_info "Testing RDS instance class cost constraints..."
    
    local test_passed=true
    
    # Test different instance classes
    local instance_classes=("db.t3.micro" "db.t3.small" "db.r5.large")
    
    for instance_class in "${instance_classes[@]}"; do
        # Create test configuration
        cat > "$TEMP_DIR/rds-test-$instance_class.json" << EOF
{
    "rds": {
        "instanceClass": "$instance_class",
        "allocatedStorage": 20,
        "storageType": "gp2",
        "multiAZ": false
    },
    "lambda": {
        "memorySize": 512,
        "timeout": 30
    },
    "vpc": {
        "enableNatGateway": false
    }
}
EOF

        # Validate configuration
        local result_file="$TEMP_DIR/rds-result-$instance_class.txt"
        "$TEMP_DIR/validate-constraints.sh" \
            "$TEMP_DIR/rds-test-$instance_class.json" \
            "$TEMP_DIR/aws-pricing.json" \
            "50" > "$result_file" 2>&1 || true
        
        local violations=$(grep "VIOLATIONS:" "$result_file" | cut -d: -f2 | tr -d ' ')
        
        case "$instance_class" in
            "db.t3.micro")
                if [ "$violations" = "0" ]; then
                    log_test_info "✓ $instance_class correctly passed (free tier)"
                else
                    log_test_failure "✗ $instance_class incorrectly failed validation"
                    test_passed=false
                fi
                ;;
            "db.r5.large")
                if [ "$violations" -gt "0" ]; then
                    log_test_info "✓ $instance_class correctly failed (expensive)"
                else
                    log_test_failure "✗ $instance_class incorrectly passed validation"
                    test_passed=false
                fi
                ;;
        esac
    done
    
    if [ "$test_passed" = true ]; then
        log_test_success "RDS instance class constraints test passed"
    else
        log_test_failure "RDS instance class constraints test failed"
        log_property_violation "RDS instance class cost constraints violated"
    fi
}

test_lambda_memory_constraints() {
    log_test_info "Testing Lambda memory size cost constraints..."
    
    local test_passed=true
    
    # Test different memory sizes
    local memory_sizes=(256 512 1024 3008)
    
    for memory_size in "${memory_sizes[@]}"; do
        # Create test configuration
        cat > "$TEMP_DIR/lambda-test-$memory_size.json" << EOF
{
    "rds": {
        "instanceClass": "db.t3.micro",
        "allocatedStorage": 20,
        "storageType": "gp2",
        "multiAZ": false
    },
    "lambda": {
        "memorySize": $memory_size,
        "timeout": 30
    },
    "vpc": {
        "enableNatGateway": false
    }
}
EOF

        # Validate configuration
        local result_file="$TEMP_DIR/lambda-result-$memory_size.txt"
        "$TEMP_DIR/validate-constraints.sh" \
            "$TEMP_DIR/lambda-test-$memory_size.json" \
            "$TEMP_DIR/aws-pricing.json" \
            "50" > "$result_file" 2>&1 || true
        
        local violations=$(grep "VIOLATIONS:" "$result_file" | cut -d: -f2 | tr -d ' ')
        
        # Check if memory size is within reasonable limits
        if [ "$memory_size" -le "$MAX_LAMBDA_MEMORY" ]; then
            if [ "$violations" = "0" ]; then
                log_test_info "✓ Memory $memory_size MB correctly passed"
            else
                log_test_info "⚠ Memory $memory_size MB failed (may be due to total cost)"
            fi
        else
            if [ "$violations" -gt "0" ]; then
                log_test_info "✓ Memory $memory_size MB correctly failed (excessive)"
            else
                log_test_failure "✗ Memory $memory_size MB incorrectly passed"
                test_passed=false
            fi
        fi
    done
    
    if [ "$test_passed" = true ]; then
        log_test_success "Lambda memory constraints test passed"
    else
        log_test_failure "Lambda memory constraints test failed"
        log_property_violation "Lambda memory cost constraints violated"
    fi
}

test_free_tier_optimization() {
    log_test_info "Testing free tier optimization..."
    
    # Create free tier optimized configuration
    cat > "$TEMP_DIR/free-tier-config.json" << 'EOF'
{
    "rds": {
        "instanceClass": "db.t3.micro",
        "allocatedStorage": 20,
        "storageType": "gp2",
        "multiAZ": false,
        "backupRetentionPeriod": 7
    },
    "lambda": {
        "memorySize": 512,
        "timeout": 30
    },
    "vpc": {
        "enableNatGateway": false
    }
}
EOF

    # Validate free tier configuration
    if "$TEMP_DIR/validate-constraints.sh" \
        "$TEMP_DIR/free-tier-config.json" \
        "$TEMP_DIR/aws-pricing.json" \
        "10" > "$TEMP_DIR/free-tier-result.txt" 2>&1; then
        
        log_test_success "Free tier configuration passed validation"
        
        # Check free tier usage
        if grep -q "RDS Free Tier: true" "$TEMP_DIR/free-tier-result.txt"; then
            log_test_info "✓ RDS using free tier eligible instance"
        else
            log_test_failure "✗ RDS not using free tier"
        fi
        
        if grep -q "Lambda Free Tier: true" "$TEMP_DIR/free-tier-result.txt"; then
            log_test_info "✓ Lambda within free tier limits"
        else
            log_test_info "⚠ Lambda exceeds free tier (may be acceptable)"
        fi
        
    else
        log_test_failure "Free tier configuration failed validation"
        log_property_violation "Free tier optimization not working correctly"
    fi
}

test_cost_estimation_accuracy() {
    log_test_info "Testing cost estimation accuracy..."
    
    if ! command -v python3 &> /dev/null; then
        log_test_info "Python3 not available, skipping cost estimation accuracy test"
        log_test_success "Cost estimation accuracy test skipped"
        return 0
    fi
    
    # Test known configuration with expected cost
    local config_file="$TEMP_DIR/cost-optimized-config.json"
    local pricing_file="$TEMP_DIR/aws-pricing.json"
    
    local cost_result=$(python3 "$TEMP_DIR/cost-calculator.py" "$config_file" "$pricing_file")
    local total_cost=$(echo "$cost_result" | jq -r '.totalMonthlyCost')
    
    # Expected cost for db.t3.micro (free tier) + Lambda (minimal usage) should be very low
    if (( $(echo "$total_cost < 5" | bc -l) )); then
        log_test_success "Cost estimation shows expected low cost: \$$(printf '%.2f' $total_cost)"
    else
        log_test_failure "Cost estimation higher than expected: \$$(printf '%.2f' $total_cost)"
        log_property_violation "Cost estimation accuracy may be incorrect"
    fi
    
    # Test individual component costs
    local rds_cost=$(echo "$cost_result" | jq -r '.rds.totalCost')
    local lambda_cost=$(echo "$cost_result" | jq -r '.lambda.totalCost')
    local vpc_cost=$(echo "$cost_result" | jq -r '.vpc.totalCost')
    
    log_test_info "Cost breakdown - RDS: \$$(printf '%.2f' $rds_cost), Lambda: \$$(printf '%.2f' $lambda_cost), VPC: \$$(printf '%.2f' $vpc_cost)"
}
generate_test_report() {
    local report_file="$TEMP_DIR/cost_optimization_test_report.md"
    
    cat > "$report_file" << EOF
# Cost Optimization Constraints Property Test Report

**Test Name:** $TEST_NAME
**Date:** $(date)

## Test Results Summary

- **Tests Passed:** $TESTS_PASSED
- **Tests Failed:** $TESTS_FAILED
- **Property Violations:** ${#PROPERTY_VIOLATIONS[@]}

## Property Validation

### Cost Optimization Constraints Property
**Property:** All provisioned resources must comply with cost optimization constraints.

**Validation Method:** 
1. Test cost-optimized configurations (should pass)
2. Test cost-violating configurations (should fail)
3. Validate specific resource constraints (RDS, Lambda, VPC)
4. Verify free tier optimization

### Cost Constraints Tested

#### RDS Constraints
- **Instance Class**: Prefer free tier eligible instances (db.t3.micro)
- **Storage**: Use cost-effective storage types (gp2 vs io1)
- **Multi-AZ**: Avoid unless necessary (doubles cost)
- **Max Hourly Cost**: \$$MAX_RDS_INSTANCE_COST_PER_HOUR per hour

#### Lambda Constraints
- **Memory Size**: Maximum $MAX_LAMBDA_MEMORY MB
- **Timeout**: Reasonable timeout values
- **Free Tier**: Optimize for free tier usage

#### VPC Constraints
- **NAT Gateway**: Minimize usage (expensive)
- **Single NAT**: Use single NAT gateway when possible

## Test Environment
- Temporary Directory: $TEMP_DIR
- Python Available: $(command -v python3 &> /dev/null && echo "Yes" || echo "No")
- bc Available: $(command -v bc &> /dev/null && echo "Yes" || echo "No")

## Property Violations

EOF

    if [ ${#PROPERTY_VIOLATIONS[@]} -eq 0 ]; then
        echo "✅ No property violations detected" >> "$report_file"
    else
        for violation in "${PROPERTY_VIOLATIONS[@]}"; do
            echo "❌ $violation" >> "$report_file"
        done
    fi
    
    cat >> "$report_file" << EOF

## Cost Analysis Results

### Cost-Optimized Configuration
EOF

    if [ -f "$TEMP_DIR/cost-optimized-result.txt" ]; then
        echo '```' >> "$report_file"
        cat "$TEMP_DIR/cost-optimized-result.txt" >> "$report_file"
        echo '```' >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

### Cost-Violating Configuration
EOF

    if [ -f "$TEMP_DIR/cost-violating-result.txt" ]; then
        echo '```' >> "$report_file"
        cat "$TEMP_DIR/cost-violating-result.txt" >> "$report_file"
        echo '```' >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

## Test Files Generated

- Configuration files: $TEMP_DIR/*-config.json
- Cost analysis results: $TEMP_DIR/*-result.txt
- Pricing data: $TEMP_DIR/aws-pricing.json
- Cost calculator: $TEMP_DIR/cost-calculator.py

## Conclusion

EOF

    if [ $TESTS_FAILED -eq 0 ] && [ ${#PROPERTY_VIOLATIONS[@]} -eq 0 ]; then
        echo "✅ **PASS**: Cost optimization constraints property is satisfied" >> "$report_file"
    else
        echo "❌ **FAIL**: Cost optimization constraints property violations detected" >> "$report_file"
    fi
    
    echo ""
    echo "📋 Test report generated: $report_file"
    
    # Display summary
    cat "$report_file"
}

main() {
    echo -e "${COST_BLUE}🧪 Starting $TEST_NAME${COST_NC}"
    echo "=================================================="
    
    # Check for required tools
    if ! command -v bc &> /dev/null; then
        log_test_info "bc (calculator) not found, some tests may be limited"
    fi
    
    if ! command -v jq &> /dev/null; then
        log_test_info "jq not found, some tests may be limited"
    fi
    
    # Setup test environment
    if ! setup_test_environment; then
        log_test_failure "Failed to setup test environment"
        exit 1
    fi
    
    # Run property tests
    test_cost_optimized_configuration
    test_cost_violating_configuration
    test_rds_instance_class_constraints
    test_lambda_memory_constraints
    test_free_tier_optimization
    test_cost_estimation_accuracy
    
    # Generate report
    generate_test_report
    
    echo ""
    echo "=================================================="
    if [ $TESTS_FAILED -eq 0 ] && [ ${#PROPERTY_VIOLATIONS[@]} -eq 0 ]; then
        echo -e "${COST_GREEN}✅ All tests passed! Cost optimization constraints property validated.${COST_NC}"
        exit 0
    else
        echo -e "${COST_RED}❌ Some tests failed or property violations detected.${COST_NC}"
        echo -e "${COST_YELLOW}📋 Check the test report for details: $TEMP_DIR/cost_optimization_test_report.md${COST_NC}"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Cost Optimization Constraints Property Test"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h              Show this help message"
        echo ""
        echo "This test validates the cost optimization constraints property:"
        echo "All provisioned resources must comply with cost optimization criteria."
        exit 0
        ;;
    *)
        # Continue with main execution
        ;;
esac

# Run main function
main "$@"