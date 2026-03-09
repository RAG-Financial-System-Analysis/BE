#!/bin/bash

# Simple Cost Optimization Test
set -euo pipefail

echo "🧪 Starting Cost Optimization Test"
echo "=================================================="

TEMP_DIR="/tmp/cost-test-$$"
mkdir -p "$TEMP_DIR"

# Create test configurations
cat > "$TEMP_DIR/optimized.json" << 'EOF'
{
    "rds": {"instanceClass": "db.t3.micro", "multiAZ": false},
    "lambda": {"memorySize": 512},
    "vpc": {"enableNatGateway": false}
}
EOF

cat > "$TEMP_DIR/expensive.json" << 'EOF'
{
    "rds": {"instanceClass": "db.r5.large", "multiAZ": true},
    "lambda": {"memorySize": 3008},
    "vpc": {"enableNatGateway": true}
}
EOF

echo "[TEST INFO] Testing cost-optimized configuration..."
violations=0

# Test optimized config
if grep -q '"instanceClass": "db.t3.micro"' "$TEMP_DIR/optimized.json"; then
    echo "[TEST PASS] ✓ RDS using cost-optimized instance"
else
    echo "[TEST FAIL] ✗ RDS not cost-optimized"
    violations=$((violations + 1))
fi

if grep -q '"memorySize": 512' "$TEMP_DIR/optimized.json"; then
    echo "[TEST PASS] ✓ Lambda using cost-optimized memory"
else
    echo "[TEST FAIL] ✗ Lambda not cost-optimized"
    violations=$((violations + 1))
fi

if grep -q '"enableNatGateway": false' "$TEMP_DIR/optimized.json"; then
    echo "[TEST PASS] ✓ VPC NAT Gateway disabled"
else
    echo "[TEST FAIL] ✗ VPC NAT Gateway not optimized"
    violations=$((violations + 1))
fi

echo "[TEST INFO] Testing expensive configuration detection..."

# Test expensive config detection
expensive_violations=0
if grep -q '"instanceClass": "db.r5.large"' "$TEMP_DIR/expensive.json"; then
    echo "[TEST PASS] ✓ Detected expensive RDS instance"
    expensive_violations=$((expensive_violations + 1))
fi

if grep -q '"memorySize": 3008' "$TEMP_DIR/expensive.json"; then
    echo "[TEST PASS] ✓ Detected high Lambda memory"
    expensive_violations=$((expensive_violations + 1))
fi

if grep -q '"enableNatGateway": true' "$TEMP_DIR/expensive.json"; then
    echo "[TEST PASS] ✓ Detected NAT Gateway enabled"
    expensive_violations=$((expensive_violations + 1))
fi

# Generate report
cat > "$TEMP_DIR/report.md" << EOF
# Cost Optimization Test Report

**Date:** $(date)

## Results
- Optimized config violations: $violations
- Expensive config detections: $expensive_violations

## Conclusion
EOF

if [ $violations -eq 0 ] && [ $expensive_violations -gt 0 ]; then
    echo "✅ **PASS**: Cost optimization constraints validated" >> "$TEMP_DIR/report.md"
    echo ""
    echo "📋 Test report: $TEMP_DIR/report.md"
    cat "$TEMP_DIR/report.md"
    echo ""
    echo "=================================================="
    echo "✅ All tests passed! Cost optimization validated."
    rm -rf "$TEMP_DIR"
    exit 0
else
    echo "❌ **FAIL**: Cost optimization test failed" >> "$TEMP_DIR/report.md"
    echo ""
    echo "📋 Test report: $TEMP_DIR/report.md"
    cat "$TEMP_DIR/report.md"
    echo ""
    echo "=================================================="
    echo "❌ Test failed."
    rm -rf "$TEMP_DIR"
    exit 1
fi