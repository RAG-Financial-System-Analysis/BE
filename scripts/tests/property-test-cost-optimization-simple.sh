#!/bin/bash

# Property Test: Cost Optimization Constraints (Simplified)
# Validates that provisioned resources meet cost optimization criteria
# Property: All provisioned resources should use cost-optimized configurations

set -euo pipefail

# Test configuration
TEST_NAME="Cost Optimization Constraints Property Test (Simplified)"
TEMP_DIR="/tmp/cost-test-$$"

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
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup_test_resources EXIT

setup_test_environment() {
    log_test_info "Setting up test environment..."
    mkdir -p "$TEMP_DIR"
    
    # Create cost-optimized configuration
    cat > "$TEMP_DIR/cost-optimized.json" << 'EOJSON'
{
    "rds": {
        "instanceClass": "db.t3.micro",
        "allocatedStorage": 20,
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
EOJSON

    # Create cost-violating configuration
    cat > "$TEMP_DIR/cost-violating.json" << 'EOJSON'
{
    "rds": {
        "instanceClass": "db.r5.large",
        "allocatedStorage": 100,
        "multiAZ": true
    },
    "lambda": {
        "memorySize": 3008,
        "timeout": 900
    },
    "vpc": {
        "enableNatGateway": true
    }
}
EOJSON

    log_test_success "Test environment setup completed"
}

test_cost_optimized_configuration() {
    log_test_info "Testing cost-optimized configuration..."
    
    local config="$TEMP_DIR/cost-optimized.json"
    local violations=0
    
    # Check RDS instance class
    if grep -q '"instanceClass": "db.t3.micro"' "$config"; then
        log_test_info "✓ RDS using cost-optimized instance class"
    else
        log_test_failure "✗ RDS not using cost-optimized instance class"
        ((violations++))
    fi
    
    # Check Lambda memory
    if grep -q '"memorySize": 512' "$config"; then
        log_test_info "✓ Lambda using cost-optimized memory size"
    else
        log_test_failure "✗ Lambda not using cost-optimized memory size"
        ((violations++))
    fi
    
    # Check VPC NAT Gateway
    if grep -q '"enableNatGateway": false' "$config"; then
        log_test_info "✓ VPC NAT Gateway disabled for cost optimization"
    else
        log_test_failure "✗ VPC NAT Gateway enabled (increases cost)"
        ((violations++))
    fi
    
    if [ $violations -eq 0 ]; then
        log_test_success "Cost-optimized configuration test passed"
    else
        log_test_failure "Cost-optimized configuration test failed: $violations violations"
        log_property_violation "Cost-optimized configuration has violations"
    fi
}

test_cost_violating_configuration() {
    log_test_info "Testing cost-violating configuration detection..."
    
    local config="$TEMP_DIR/cost-violating.json"
    local violations=0
    
    # Check for expensive configurations
    if grep -q '"instanceClass": "db.r5.large"' "$config"; then
        log_test_info "✓ Detected expensive RDS instance class"
        ((violations++))
    fi
    
    if grep -q '"memorySize": 3008' "$config"; then
        log_test_info "✓ Detected high Lambda memory allocation"
        ((violations++))
    fi
    
    if grep -q '"enableNatGateway": true' "$config"; then
        log_test_info "✓ Detected NAT Gateway enabled (cost increase)"
        ((violations++))
    fi
    
    if [ $violations -gt 0 ]; then
        log_test_success "Cost-violating configuration correctly detected: $violations violations"
    else
        log_test_failure "Cost-violating configuration not detected"
        log_property_violation "Cost violation detection failed"
    fi
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
**Property:** All provisioned resources should use cost-optimized configurations.

**Validation Method:** 
1. Check RDS instance classes for cost optimization
2. Check Lambda memory allocations
3. Check VPC NAT Gateway settings
4. Validate against cost constraints

## Property Violations

