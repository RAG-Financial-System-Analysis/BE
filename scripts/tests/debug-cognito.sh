#!/bin/bash

echo "🔍 Debugging Cognito validation..."

TEMP_DIR="/tmp/cognito-debug-$$"
mkdir -p "$TEMP_DIR"

# Create invalid config
cat > "$TEMP_DIR/invalid.json" << 'EOF'
{
  "AWS": {
    "Region": "ap-southeast-1",
    "Cognito": {
      "UserPoolId": "",
      "ClientId": "invalid-client-id"
    }
  }
}
EOF

# Create validation script
cat > "$TEMP_DIR/validate.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

config_file="$1"
echo "VALIDATION_START"
validation_errors=0

if grep -q '"UserPoolId"' "$config_file" && grep -q '"ClientId"' "$config_file"; then
    user_pool_id=$(grep '"UserPoolId"' "$config_file" | sed 's/.*"UserPoolId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    client_id=$(grep '"ClientId"' "$config_file" | sed 's/.*"ClientId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    
    echo "UserPoolId: '$user_pool_id'"
    echo "ClientId: '$client_id'"
    
    if [ -z "$user_pool_id" ]; then
        echo "ERROR: UserPoolId is empty"
        validation_errors=$((validation_errors + 1))
    fi
    
    if [ -z "$client_id" ]; then
        echo "ERROR: ClientId is empty"
        validation_errors=$((validation_errors + 1))
    fi
else
    echo "ERROR: Required fields missing"
    validation_errors=$((validation_errors + 1))
fi

echo "VALIDATION_END"
echo "ERRORS: $validation_errors"
exit $validation_errors
EOF

chmod +x "$TEMP_DIR/validate.sh"

echo "Running validation on invalid config..."
if "$TEMP_DIR/validate.sh" "$TEMP_DIR/invalid.json"; then
    echo "❌ Validation PASSED (should have failed)"
    exit_code=0
else
    echo "✅ Validation FAILED (correct behavior)"
    exit_code=$?
fi

echo "Exit code: $exit_code"

# Cleanup
rm -rf "$TEMP_DIR"

if [ $exit_code -eq 0 ]; then
    echo "❌ Problem: validation should fail but didn't"
    exit 1
else
    echo "✅ Validation working correctly"
    exit 0
fi