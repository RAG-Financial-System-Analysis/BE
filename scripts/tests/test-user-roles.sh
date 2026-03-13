#!/bin/bash

# Test user roles by logging in and checking JWT token content

API_URL="https://si0l0toalc.execute-api.ap-southeast-1.amazonaws.com/production"

echo "🔐 Testing user roles..."

echo ""
echo "=== Testing Admin User ==="
echo "Email: admin@yourdomain.com"
echo "Password: YourSecureAdminPassword"

ADMIN_RESPONSE=$(curl -s -X POST "$API_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@yourdomain.com","password":"YourSecureAdminPassword"}')

if echo "$ADMIN_RESPONSE" | grep -q "accessToken"; then
    echo "✅ Admin login successful"
    
    # Extract access token
    ADMIN_TOKEN=$(echo "$ADMIN_RESPONSE" | grep -o '"accessToken":"[^"]*' | cut -d'"' -f4)
    
    # Test authenticated endpoint
    echo "🔍 Testing authenticated endpoint with admin token..."
    ADMIN_PROFILE=$(curl -s -H "Authorization: Bearer $ADMIN_TOKEN" "$API_URL/api/auth/profile")
    
    echo "Admin Profile Response:"
    echo "$ADMIN_PROFILE" | head -c 200
    echo "..."
else
    echo "❌ Admin login failed"
    echo "$ADMIN_RESPONSE"
fi

echo ""
echo "=== Testing Analyst User ==="
echo "Email: analyst@yourdomain.com"
echo "Password: YourSecureAnalystPassword"

ANALYST_RESPONSE=$(curl -s -X POST "$API_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"analyst@yourdomain.com","password":"YourSecureAnalystPassword"}')

if echo "$ANALYST_RESPONSE" | grep -q "accessToken"; then
    echo "✅ Analyst login successful"
    
    # Extract access token
    ANALYST_TOKEN=$(echo "$ANALYST_RESPONSE" | grep -o '"accessToken":"[^"]*' | cut -d'"' -f4)
    
    # Test authenticated endpoint
    echo "🔍 Testing authenticated endpoint with analyst token..."
    ANALYST_PROFILE=$(curl -s -H "Authorization: Bearer $ANALYST_TOKEN" "$API_URL/api/auth/profile")
    
    echo "Analyst Profile Response:"
    echo "$ANALYST_PROFILE" | head -c 200
    echo "..."
else
    echo "❌ Analyst login failed"
    echo "$ANALYST_RESPONSE"
fi

echo ""
echo "=== Testing Role-based Access ==="

if [ ! -z "$ADMIN_TOKEN" ]; then
    echo "🔍 Testing admin-only endpoint with admin token..."
    ADMIN_ACCESS=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $ADMIN_TOKEN" "$API_URL/api/admin/users")
    echo "Admin endpoint response:"
    echo "$ADMIN_ACCESS"
fi

if [ ! -z "$ANALYST_TOKEN" ]; then
    echo "🔍 Testing admin-only endpoint with analyst token (should fail)..."
    ANALYST_ACCESS=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $ANALYST_TOKEN" "$API_URL/api/admin/users")
    echo "Analyst trying admin endpoint:"
    echo "$ANALYST_ACCESS"
fi

echo ""
echo "🎉 Role testing completed!"