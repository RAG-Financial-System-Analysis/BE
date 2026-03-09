#!/bin/bash

# Fix color variable conflicts in test scripts
# This script updates color variable names to use unique prefixes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔧 Fixing color variable conflicts in test scripts..."

# List of test files that need color variable fixes
test_files=(
    "property-test-configuration-conversion.sh"
    "unit-test-infrastructure-detection.sh"
    "property-test-cost-optimization.sh"
    "property-test-deployment-idempotency.sh"
    "unit-test-cognito-integration.sh"
    "integration-test-end-to-end.sh"
)

# Function to fix color variables in a file
fix_color_variables() {
    local file="$1"
    local prefix="$2"
    
    if [ ! -f "$file" ]; then
        echo "⚠️  File not found: $file"
        return 1
    fi
    
    echo "🔧 Fixing color variables in $(basename "$file") with prefix '$prefix'..."
    
    # Replace color variable declarations
    sed -i "s/^RED='/readonly ${prefix}_RED='/g" "$file"
    sed -i "s/^GREEN='/readonly ${prefix}_GREEN='/g" "$file"
    sed -i "s/^YELLOW='/readonly ${prefix}_YELLOW='/g" "$file"
    sed -i "s/^BLUE='/readonly ${prefix}_BLUE='/g" "$file"
    sed -i "s/^NC='/readonly ${prefix}_NC='/g" "$file"
    
    # Replace color variable usage in functions
    sed -i "s/\${RED}/\${${prefix}_RED}/g" "$file"
    sed -i "s/\${GREEN}/\${${prefix}_GREEN}/g" "$file"
    sed -i "s/\${YELLOW}/\${${prefix}_YELLOW}/g" "$file"
    sed -i "s/\${BLUE}/\${${prefix}_BLUE}/g" "$file"
    sed -i "s/\${NC}/\${${prefix}_NC}/g" "$file"
    
    echo "✅ Fixed color variables in $(basename "$file")"
}

# Fix each test file with a unique prefix
fix_color_variables "$SCRIPT_DIR/property-test-configuration-conversion.sh" "CONFIG"
fix_color_variables "$SCRIPT_DIR/unit-test-infrastructure-detection.sh" "INFRA"
fix_color_variables "$SCRIPT_DIR/property-test-cost-optimization.sh" "COST"
fix_color_variables "$SCRIPT_DIR/property-test-deployment-idempotency.sh" "DEPLOY"
fix_color_variables "$SCRIPT_DIR/unit-test-cognito-integration.sh" "COGNITO"
fix_color_variables "$SCRIPT_DIR/integration-test-end-to-end.sh" "E2E"

echo ""
echo "✅ All color variable conflicts have been fixed!"
echo "🧪 Test scripts are now ready to run without conflicts."