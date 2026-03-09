#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utilities/logging.sh"

set_log_level "INFO"

log_info "Starting debug test"

# Simple test function
test_simple() {
    log_info "Running simple test"
    return 0
}

# Test runner
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    log_info "Running test: $test_name"
    
    set +e
    $test_function
    local result=$?
    set -e
    
    if [ $result -eq 0 ]; then
        log_success "✓ PASS: $test_name"
    else
        log_error "✗ FAIL: $test_name"
    fi
    
    return $result
}

log_info "About to run test"
run_test "Simple Test" test_simple
log_info "Test completed"

log_info "Debug test finished"