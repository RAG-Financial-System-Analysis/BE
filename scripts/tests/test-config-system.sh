#!/bin/bash

# Test script for the new configuration system
# This script demonstrates how to use the deployment configuration

set -euo pipefail

echo "=== Testing Deployment Configuration System ==="
echo ""

# Test 1: Show default configuration
echo "🔍 Test 1: Show Default Configuration"
./scripts/manage-config.sh show
echo ""

# Test 2: Validate configuration
echo "🔍 Test 2: Validate Configuration"
./scripts/manage-config.sh validate
echo ""

# Test 3: Create production configuration
echo "🔍 Test 3: Create Production Configuration"
./scripts/manage-config.sh create --template production --output ./test-production-config.env
echo "Production config created: test-production-config.env"
echo ""

# Test 4: Show production configuration
echo "🔍 Test 4: Show Production Configuration"
./scripts/manage-config.sh show --config ./test-production-config.env
echo ""

# Test 5: Compare configurations
echo "🔍 Test 5: Compare Configurations"
echo "Comparing default vs production:"
./scripts/manage-config.sh compare --config ./deployment-config.env --output ./test-production-config.env
echo ""

# Test 6: Test deployment script with custom config
echo "🔍 Test 6: Test Deployment Script with Custom Config"
echo "Testing deployment script help with custom config:"
./scripts/deploy-full-stack.sh --config ./test-production-config.env --show-config
echo ""

# Cleanup
echo "🧹 Cleaning up test files..."
rm -f ./test-production-config.env
echo ""

echo "=== Configuration System Test Complete ==="
echo ""
echo "💡 Usage Examples:"
echo "   # Deploy with default config"
echo "   ./scripts/deploy-full-stack.sh"
echo ""
echo "   # Deploy with custom config"
echo "   ./scripts/deploy-full-stack.sh --config ./production-config.env"
echo ""
echo "   # Create and use production config"
echo "   ./scripts/manage-config.sh create --template production --output ./prod-config.env"
echo "   ./scripts/deploy-full-stack.sh --config ./prod-config.env"
echo ""
echo "   # Override specific settings"
echo "   ./scripts/deploy-full-stack.sh --environment production --project-name myrag"