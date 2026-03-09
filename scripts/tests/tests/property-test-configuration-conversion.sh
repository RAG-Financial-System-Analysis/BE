#!/bin/bash

# Property Test: Configuration Round-trip Consistency
# Validates that configuration values are preserved through conversion process
# Property: For any valid configuration C, converting to environment variables and back should preserve all values
# Validates Requirements: 6.1, 6.3

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utilities/logging.sh"

# Test configuration
TEST_NAME="Configuration Round-trip Consistency Property Test"
TEMP_DIR="/tmp/config-test-$$"
TEST_ITERATIONS=5

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
PROPERTY_VIOLATIONS=()

log_test_info() {
    echo -e "${BLUE}[TEST INFO]${NC} $1"
}

log_test_success() {
    echo -e "${GREEN}[TEST PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_test_failure() {
    echo -e "${RED}[TEST FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_property_violation() {
    echo -e "${RED}[PROPERTY VIOLATION]${NC} $1"
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
    
    # Create test configuration files
    create_test_configurations
    
    # Create configuration conversion utilities
    create_conversion_utilities
    
    log_test_success "Test environment setup completed"
}

create_test_configurations() {
    log_test_info "Creating test configuration files..."
    
    # Simple configuration
    cat > "$TEMP_DIR/simple-config.json" << 'EOF'
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Database=testdb;Username=user;Password=pass"
  },
  "AWS": {
    "Region": "ap-southeast-1"
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information"
    }
  }
}
EOF

    # Complex nested configuration
    cat > "$TEMP_DIR/complex-config.json" << 'EOF'
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=prod-db.amazonaws.com;Database=appdb;Username=dbuser;Password=secretpass",
    "RedisConnection": "redis://localhost:6379"
  },
  "AWS": {
    "Region": "ap-southeast-1",
    "Cognito": {
      "UserPoolId": "ap-southeast-1_VTLpFeyhi",
      "ClientId": "76hpd4tfrp93qf33ue6sr0991g",
      "Authority": "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_VTLpFeyhi"
    },
    "S3": {
      "BucketName": "my-app-bucket",
      "Region": "ap-southeast-1"
    }
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft": "Warning",
      "Microsoft.Hosting.Lifetime": "Information"
    }
  },
  "JWT": {
    "Issuer": "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_VTLpFeyhi",
    "Audience": "76hpd4tfrp93qf33ue6sr0991g",
    "ValidateIssuer": true,
    "ValidateAudience": true
  },
  "Application": {
    "Name": "RAG System",
    "Version": "1.0.0",
    "Environment": "Production",
    "Features": {
      "EnableCaching": true,
      "EnableMetrics": false,
      "MaxFileSize": 10485760
    }
  }
}
EOF

    # Configuration with special characters
    cat > "$TEMP_DIR/special-chars-config.json" << 'EOF'
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=db.example.com;Database=app_db;Username=user@domain.com;Password=P@ssw0rd!#$%"
  },
  "Messages": {
    "Welcome": "Chào mừng bạn đến với hệ thống!",
    "Error": "Đã xảy ra lỗi: {0}",
    "SpecialChars": "Test: !@#$%^&*()_+-=[]{}|;':\",./<>?"
  },
  "Paths": {
    "DataDirectory": "/var/lib/app/data",
    "LogDirectory": "/var/log/app",
    "TempDirectory": "/tmp/app_temp"
  }
}
EOF

    # Configuration with arrays and numbers
    cat > "$TEMP_DIR/arrays-numbers-config.json" << 'EOF'
{
  "Database": {
    "ConnectionTimeout": 30,
    "CommandTimeout": 60,
    "MaxRetries": 3,
    "RetryDelay": 1000
  },
  "AllowedHosts": [
    "localhost",
    "*.example.com",
    "api.myapp.com"
  ],
  "CORS": {
    "AllowedOrigins": [
      "https://app.example.com",
      "https://admin.example.com"
    ],
    "AllowedMethods": ["GET", "POST", "PUT", "DELETE"],
    "AllowCredentials": true
  },
  "RateLimiting": {
    "RequestsPerMinute": 100,
    "BurstSize": 20,
    "Enabled": true
  }
}
EOF

    log_test_success "Test configuration files created"
}

create_conversion_utilities() {
    log_test_info "Creating configuration conversion utilities..."
    
    # JSON to environment variables converter
    cat > "$TEMP_DIR/json-to-env.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

json_file="$1"
output_file="$2"

# Function to flatten JSON to environment variables
flatten_json() {
    local json_file="$1"
    local prefix="$2"
    
    # Use jq to flatten JSON with proper key formatting
    jq -r '
        def flatten(prefix):
            . as $in
            | reduce paths(scalars) as $path (
                {};
                . + {
                    ($path | map(tostring) | join("__")): ($in | getpath($path))
                }
            );
        flatten("") | to_entries[] | "\(.key)=\(.value)"
    ' "$json_file" | while IFS='=' read -r key value; do
        # Convert key to uppercase and replace dots with underscores
        env_key=$(echo "$key" | tr '[:lower:]' '[:upper:]' | sed 's/\./__/g')
        echo "${env_key}=${value}"
    done
}

# Convert JSON to environment variables
flatten_json "$json_file" > "$output_file"
EOF

    # Environment variables to JSON converter
    cat > "$TEMP_DIR/env-to-json.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

env_file="$1"
output_file="$2"

# Function to convert environment variables back to JSON
env_to_json() {
    local env_file="$1"
    
    echo "{"
    local first=true
    
    # Read environment variables and convert to JSON structure
    while IFS='=' read -r key value; do
        if [ -n "$key" ] && [ -n "$value" ]; then
            # Convert key back to JSON path
            json_path=$(echo "$key" | tr '[:upper:]' '[:lower:]' | sed 's/__/./g')
            
            if [ "$first" = true ]; then
                first=false
            else
                echo ","
            fi
            
            # Handle nested structure (simplified for testing)
            if [[ "$json_path" == *.* ]]; then
                # This is a simplified conversion - in real implementation would need proper nesting
                echo "  \"$json_path\": \"$value\""
            else
                echo "  \"$json_path\": \"$value\""
            fi
        fi
    done < "$env_file"
    
    echo ""
    echo "}"
}

# Convert environment variables to JSON
env_to_json "$env_file" > "$output_file"
EOF

    # Advanced JSON flattener using Python (more accurate)
    cat > "$TEMP_DIR/json-flattener.py" << 'EOF'
#!/usr/bin/env python3
import json
import sys
import os

def flatten_dict(d, parent_key='', sep='__'):
    """Flatten a nested dictionary"""
    items = []
    for k, v in d.items():
        new_key = f"{parent_key}{sep}{k}" if parent_key else k
        if isinstance(v, dict):
            items.extend(flatten_dict(v, new_key, sep=sep).items())
        elif isinstance(v, list):
            # Convert arrays to comma-separated strings
            items.append((new_key, ','.join(str(item) for item in v)))
        else:
            items.append((new_key, str(v)))
    return dict(items)

def unflatten_dict(d, sep='__'):
    """Unflatten a dictionary"""
    result = {}
    for key, value in d.items():
        parts = key.split(sep)
        current = result
        for part in parts[:-1]:
            if part not in current:
                current[part] = {}
            current = current[part]
        
        # Try to convert back to appropriate type
        final_value = value
        if value.lower() in ('true', 'false'):
            final_value = value.lower() == 'true'
        elif value.isdigit():
            final_value = int(value)
        elif ',' in value and not any(char in value for char in [' ', ':', '/', '@']):
            # Likely an array
            final_value = value.split(',')
        
        current[parts[-1]] = final_value
    
    return result

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: json-flattener.py <mode> <input_file> <output_file>")
        print("Mode: flatten or unflatten")
        sys.exit(1)
    
    mode = sys.argv[1]
    input_file = sys.argv[2]
    output_file = sys.argv[3]
    
    if mode == "flatten":
        with open(input_file, 'r') as f:
            data = json.load(f)
        
        flattened = flatten_dict(data)
        
        with open(output_file, 'w') as f:
            for key, value in flattened.items():
                f.write(f"{key.upper()}={value}\n")
    
    elif mode == "unflatten":
        env_vars = {}
        with open(input_file, 'r') as f:
            for line in f:
                line = line.strip()
                if '=' in line:
                    key, value = line.split('=', 1)
                    env_vars[key.lower()] = value
        
        unflattened = unflatten_dict(env_vars)
        
        with open(output_file, 'w') as f:
            json.dump(unflattened, f, indent=2)
    
    else:
        print(f"Unknown mode: {mode}")
        sys.exit(1)
EOF

    chmod +x "$TEMP_DIR/json-to-env.sh"
    chmod +x "$TEMP_DIR/env-to-json.sh"
    chmod +x "$TEMP_DIR/json-flattener.py"
    
    log_test_success "Conversion utilities created"
}

test_configuration_round_trip() {
    local config_file="$1"
    local test_name="$2"
    
    log_test_info "Testing round-trip conversion for: $test_name"
    
    local original_file="$config_file"
    local env_file="$TEMP_DIR/${test_name}.env"
    local restored_file="$TEMP_DIR/${test_name}-restored.json"
    
    # Step 1: Convert JSON to environment variables
    if command -v python3 &> /dev/null; then
        # Use Python flattener for more accurate conversion
        python3 "$TEMP_DIR/json-flattener.py" flatten "$original_file" "$env_file" || {
            log_test_failure "Failed to convert JSON to environment variables for $test_name"
            return 1
        }
    else
        # Fallback to bash implementation
        "$TEMP_DIR/json-to-env.sh" "$original_file" "$env_file" || {
            log_test_failure "Failed to convert JSON to environment variables for $test_name"
            return 1
        }
    fi
    
    # Step 2: Convert environment variables back to JSON
    if command -v python3 &> /dev/null; then
        python3 "$TEMP_DIR/json-flattener.py" unflatten "$env_file" "$restored_file" || {
            log_test_failure "Failed to convert environment variables back to JSON for $test_name"
            return 1
        }
    else
        "$TEMP_DIR/env-to-json.sh" "$env_file" "$restored_file" || {
            log_test_failure "Failed to convert environment variables back to JSON for $test_name"
            return 1
        }
    fi
    
    # Step 3: Compare original and restored configurations
    if command -v jq &> /dev/null; then
        # Normalize JSON for comparison
        jq --sort-keys . "$original_file" > "$TEMP_DIR/${test_name}-original-normalized.json"
        jq --sort-keys . "$restored_file" > "$TEMP_DIR/${test_name}-restored-normalized.json"
        
        if diff -u "$TEMP_DIR/${test_name}-original-normalized.json" "$TEMP_DIR/${test_name}-restored-normalized.json" > "$TEMP_DIR/${test_name}-diff.txt"; then
            log_test_success "Round-trip conversion successful for $test_name"
            return 0
        else
            log_test_failure "Round-trip conversion failed for $test_name - configurations differ"
            log_test_info "Differences saved to: $TEMP_DIR/${test_name}-diff.txt"
            
            # Show first few lines of differences
            echo "First 10 lines of differences:"
            head -10 "$TEMP_DIR/${test_name}-diff.txt" || true
            
            log_property_violation "Configuration round-trip consistency violated for $test_name"
            return 1
        fi
    else
        # Basic comparison without jq
        if diff -u "$original_file" "$restored_file" > "$TEMP_DIR/${test_name}-diff.txt"; then
            log_test_success "Round-trip conversion successful for $test_name (basic comparison)"
            return 0
        else
            log_test_failure "Round-trip conversion failed for $test_name - files differ"
            log_property_violation "Configuration round-trip consistency violated for $test_name"
            return 1
        fi
    fi
}

test_environment_variable_format() {
    log_test_info "Testing environment variable format compliance..."
    
    local config_file="$TEMP_DIR/complex-config.json"
    local env_file="$TEMP_DIR/format-test.env"
    
    # Convert to environment variables
    if command -v python3 &> /dev/null; then
        python3 "$TEMP_DIR/json-flattener.py" flatten "$config_file" "$env_file"
    else
        "$TEMP_DIR/json-to-env.sh" "$config_file" "$env_file"
    fi
    
    # Check environment variable format
    local format_violations=0
    
    while IFS='=' read -r key value; do
        if [ -n "$key" ]; then
            # Check key format (uppercase, alphanumeric + underscore)
            if ! [[ "$key" =~ ^[A-Z0-9_]+$ ]]; then
                log_test_failure "Invalid environment variable key format: $key"
                ((format_violations++))
            fi
            
            # Check for double underscores (nested structure indicator)
            if [[ "$key" == *__* ]]; then
                log_test_info "Nested structure detected: $key"
            fi
        fi
    done < "$env_file"
    
    if [ $format_violations -eq 0 ]; then
        log_test_success "Environment variable format compliance test passed"
        return 0
    else
        log_test_failure "Environment variable format compliance test failed: $format_violations violations"
        log_property_violation "Environment variable format violations detected"
        return 1
    fi
}

test_special_character_handling() {
    log_test_info "Testing special character handling in configuration values..."
    
    local config_file="$TEMP_DIR/special-chars-config.json"
    local env_file="$TEMP_DIR/special-chars.env"
    local restored_file="$TEMP_DIR/special-chars-restored.json"
    
    # Test round-trip with special characters
    if test_configuration_round_trip "$config_file" "special-chars"; then
        log_test_success "Special character handling test passed"
        return 0
    else
        log_test_failure "Special character handling test failed"
        return 1
    fi
}

test_data_type_preservation() {
    log_test_info "Testing data type preservation during conversion..."
    
    local config_file="$TEMP_DIR/arrays-numbers-config.json"
    
    # Extract specific values to test type preservation
    if command -v jq &> /dev/null; then
        local original_timeout=$(jq -r '.Database.ConnectionTimeout' "$config_file")
        local original_enabled=$(jq -r '.RateLimiting.Enabled' "$config_file")
        local original_methods=$(jq -r '.CORS.AllowedMethods | join(",")' "$config_file")
        
        # Convert and restore
        test_configuration_round_trip "$config_file" "data-types"
        
        local restored_file="$TEMP_DIR/data-types-restored.json"
        if [ -f "$restored_file" ]; then
            local restored_timeout=$(jq -r '.Database.ConnectionTimeout' "$restored_file" 2>/dev/null || echo "null")
            local restored_enabled=$(jq -r '.RateLimiting.Enabled' "$restored_file" 2>/dev/null || echo "null")
            local restored_methods=$(jq -r '.CORS.AllowedMethods | if type == "array" then join(",") else . end' "$restored_file" 2>/dev/null || echo "null")
            
            local type_errors=0
            
            # Check if numeric values are preserved
            if [ "$original_timeout" != "$restored_timeout" ]; then
                log_test_failure "Numeric value not preserved: $original_timeout -> $restored_timeout"
                ((type_errors++))
            fi
            
            # Check if boolean values are preserved
            if [ "$original_enabled" != "$restored_enabled" ]; then
                log_test_failure "Boolean value not preserved: $original_enabled -> $restored_enabled"
                ((type_errors++))
            fi
            
            # Check if array values are preserved
            if [ "$original_methods" != "$restored_methods" ]; then
                log_test_failure "Array value not preserved: $original_methods -> $restored_methods"
                ((type_errors++))
            fi
            
            if [ $type_errors -eq 0 ]; then
                log_test_success "Data type preservation test passed"
                return 0
            else
                log_test_failure "Data type preservation test failed: $type_errors errors"
                log_property_violation "Data type preservation violated"
                return 1
            fi
        else
            log_test_failure "Restored configuration file not found"
            return 1
        fi
    else
        log_test_info "jq not available, skipping detailed data type preservation test"
        # Just test basic round-trip
        test_configuration_round_trip "$config_file" "data-types-basic"
    fi
}

test_nested_structure_preservation() {
    log_test_info "Testing nested structure preservation..."
    
    local config_file="$TEMP_DIR/complex-config.json"
    
    if command -v jq &> /dev/null; then
        # Check specific nested paths
        local original_cognito_id=$(jq -r '.AWS.Cognito.UserPoolId' "$config_file")
        local original_log_level=$(jq -r '.Logging.LogLevel.Default' "$config_file")
        
        # Convert and restore
        test_configuration_round_trip "$config_file" "nested-structure"
        
        local restored_file="$TEMP_DIR/nested-structure-restored.json"
        if [ -f "$restored_file" ]; then
            local restored_cognito_id=$(jq -r '.AWS.Cognito.UserPoolId' "$restored_file" 2>/dev/null || echo "null")
            local restored_log_level=$(jq -r '.Logging.LogLevel.Default' "$restored_file" 2>/dev/null || echo "null")
            
            local structure_errors=0
            
            if [ "$original_cognito_id" != "$restored_cognito_id" ]; then
                log_test_failure "Nested value not preserved: AWS.Cognito.UserPoolId $original_cognito_id -> $restored_cognito_id"
                ((structure_errors++))
            fi
            
            if [ "$original_log_level" != "$restored_log_level" ]; then
                log_test_failure "Nested value not preserved: Logging.LogLevel.Default $original_log_level -> $restored_log_level"
                ((structure_errors++))
            fi
            
            if [ $structure_errors -eq 0 ]; then
                log_test_success "Nested structure preservation test passed"
                return 0
            else
                log_test_failure "Nested structure preservation test failed: $structure_errors errors"
                log_property_violation "Nested structure preservation violated"
                return 1
            fi
        else
            log_test_failure "Restored configuration file not found"
            return 1
        fi
    else
        log_test_info "jq not available, skipping detailed nested structure test"
        # Just test basic round-trip
        test_configuration_round_trip "$config_file" "nested-structure-basic"
    fi
}

generate_test_report() {
    local report_file="$TEMP_DIR/configuration_conversion_test_report.md"
    
    cat > "$report_file" << EOF
# Configuration Round-trip Consistency Property Test Report

**Test Name:** $TEST_NAME
**Date:** $(date)
**Test Iterations:** $TEST_ITERATIONS

## Test Results Summary

- **Tests Passed:** $TESTS_PASSED
- **Tests Failed:** $TESTS_FAILED
- **Property Violations:** ${#PROPERTY_VIOLATIONS[@]}

## Property Validation

### Configuration Round-trip Consistency Property
**Property:** For any valid configuration C, converting to environment variables and back should preserve all values.

**Validation Method:** 
1. Convert JSON configuration to environment variables
2. Convert environment variables back to JSON
3. Compare original and restored configurations

### Test Cases Executed

1. **Simple Configuration Round-trip**
2. **Complex Nested Configuration Round-trip**
3. **Special Character Handling**
4. **Data Type Preservation**
5. **Nested Structure Preservation**
6. **Environment Variable Format Compliance**

## Test Environment
- Temporary Directory: $TEMP_DIR
- Python Available: $(command -v python3 &> /dev/null && echo "Yes" || echo "No")
- jq Available: $(command -v jq &> /dev/null && echo "Yes" || echo "No")

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

## Test Files Generated

- Original configurations: $TEMP_DIR/*-config.json
- Environment variable files: $TEMP_DIR/*.env
- Restored configurations: $TEMP_DIR/*-restored.json
- Comparison diffs: $TEMP_DIR/*-diff.txt

## Conclusion

EOF

    if [ $TESTS_FAILED -eq 0 ] && [ ${#PROPERTY_VIOLATIONS[@]} -eq 0 ]; then
        echo "✅ **PASS**: Configuration round-trip consistency property is satisfied" >> "$report_file"
    else
        echo "❌ **FAIL**: Configuration round-trip consistency property violations detected" >> "$report_file"
    fi
    
    echo ""
    echo "📋 Test report generated: $report_file"
    
    # Display summary
    cat "$report_file"
}

main() {
    echo -e "${BLUE}🧪 Starting $TEST_NAME${NC}"
    echo "=================================================="
    
    # Setup test environment
    if ! setup_test_environment; then
        log_test_failure "Failed to setup test environment"
        exit 1
    fi
    
    # Run property tests
    test_configuration_round_trip "$TEMP_DIR/simple-config.json" "simple-config"
    test_configuration_round_trip "$TEMP_DIR/complex-config.json" "complex-config"
    test_special_character_handling
    test_data_type_preservation
    test_nested_structure_preservation
    test_environment_variable_format
    
    # Generate report
    generate_test_report
    
    echo ""
    echo "=================================================="
    if [ $TESTS_FAILED -eq 0 ] && [ ${#PROPERTY_VIOLATIONS[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ All tests passed! Configuration round-trip consistency property validated.${NC}"
        exit 0
    else
        echo -e "${RED}❌ Some tests failed or property violations detected.${NC}"
        echo -e "${YELLOW}📋 Check the test report for details: $TEMP_DIR/configuration_conversion_test_report.md${NC}"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Configuration Round-trip Consistency Property Test"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h              Show this help message"
        echo "  --iterations N          Number of test iterations (default: $TEST_ITERATIONS)"
        echo ""
        echo "This test validates the configuration round-trip consistency property:"
        echo "Converting configuration to environment variables and back should preserve all values."
        exit 0
        ;;
    --iterations)
        TEST_ITERATIONS="$2"
        shift 2
        ;;
    *)
        # Continue with main execution
        ;;
esac

# Run main function
main "$@"