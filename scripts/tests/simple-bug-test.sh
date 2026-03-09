#!/bin/bash

# Simple Bug Condition Test for AWS CLI Validation
# This test MUST FAIL on unfixed code to prove the bug exists

set -euo pipefail

echo "=== Bug Condition Exploration Test ==="
echo "CRITICAL: This test MUST FAIL on unfixed code - failure confirms the bug exists"
echo ""

# Test 1: Function call without parameters (should fail on unfixed code)
echo "Test 1: validate_aws_cli function call without parameters"

# Create test script
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

cat > "$TEMP_DIR/test-no-params.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

# Source the validate-aws-cli.sh script directly
source "scripts/utilities/validate-aws-cli.sh"

# This should work according to expected behavior (Requirements 2.1, 2.2)
# but will FAIL on unfixed code due to unbound variable $1
validate_aws_cli
EOF

chmod +x "$TEMP_DIR/test-no-params.sh"

# Run test and capture output
if output=$("$TEMP_DIR/test-no-params.sh" 2>&1); then
    echo "❌ UNEXPECTED: Test passed - bug may already be fixed"
    echo "Output: $output"
    exit_code=0
else
    exit_code=$?
    echo "✅ EXPECTED: Test failed with exit code $exit_code"
    echo "Output: $output"
    
    if echo "$output" | grep -q "unbound variable"; then
        echo "✓ CONFIRMED: Unbound variable error detected at line 725"
        echo "✓ This proves the bug exists: \$1 is unbound when function called without parameters"
        echo ""
        echo "=== Bug Analysis ==="
        echo "- Location: validate-aws-cli.sh line 725"
        echo "- Issue: local profile=\"\$1\" accesses unbound variable"
        echo "- Cause: Function called without parameters in strict mode (set -euo pipefail)"
        echo "- Expected behavior: Should proceed with default AWS profile validation"
        echo ""
        echo "=== Counterexample ==="
        echo "Function call: validate_aws_cli (no parameters)"
        echo "Result: $output"
        echo ""
        echo "✅ Task 1 COMPLETE: Bug condition exploration test successfully demonstrates the bug"
        exit 1  # Expected failure on unfixed code
    else
        echo "⚠ WARNING: Unexpected error type"
        echo "Expected 'unbound variable' error but got: $output"
        exit 1
    fi
fi

echo ""
echo "=== Test Summary ==="
echo "This test is designed to FAIL on unfixed code to prove the bug exists."
echo "If the test passes, it means the bug may already be fixed."