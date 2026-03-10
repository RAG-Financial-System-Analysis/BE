#!/bin/bash

# Quick API test script
API_URL="https://si0l0toalc.execute-api.ap-southeast-1.amazonaws.com/production"

echo "Testing API endpoints..."

echo "1. Testing swagger endpoint:"
curl -s "$API_URL/swagger" | head -c 100
echo -e "\n"

echo "2. Testing auth register (should show role error):"
curl -X POST "$API_URL/api/auth/register" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"Test123!","fullName":"Test User"}' \
  -w "\nHTTP Status: %{http_code}\n"

echo -e "\n3. Testing any endpoint to trigger Lambda initialization:"
curl -s "$API_URL/api/companies" -w "\nHTTP Status: %{http_code}\n"