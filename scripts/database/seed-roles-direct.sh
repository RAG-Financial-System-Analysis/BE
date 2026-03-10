#!/bin/bash

# Direct database seeding script for roles and analytics types
# This bypasses the Lambda DbInitializer and seeds data directly to RDS

echo "🔧 Seeding roles and analytics types directly to RDS database..."

# Database connection details from appsettings.json
DB_HOST="rag-system-production-db.czk4eg4k0je6.ap-southeast-1.rds.amazonaws.com"
DB_NAME="RAGSystem"
DB_USER="postgres"
DB_PASS="12345678"
DB_PORT="5432"

# Connection string
CONN_STR="postgresql://$DB_USER:$DB_PASS@$DB_HOST:$DB_PORT/$DB_NAME?sslmode=require"

echo "📊 Database: $DB_HOST/$DB_NAME"

# Check if psql is available
if ! command -v psql &> /dev/null; then
    echo "❌ psql not found. Please install PostgreSQL client."
    echo "   Windows: Download from https://www.postgresql.org/download/windows/"
    echo "   Ubuntu: sudo apt-get install postgresql-client"
    echo "   macOS: brew install postgresql"
    exit 1
fi

echo "🔍 Testing database connection..."
if ! psql "$CONN_STR" -c "SELECT 1;" &> /dev/null; then
    echo "❌ Cannot connect to database. Please check:"
    echo "   - Database is running and accessible"
    echo "   - Connection details are correct"
    echo "   - Network connectivity"
    exit 1
fi

echo "✅ Database connection successful!"

echo "🔧 Seeding Roles..."

# Insert roles if they don't exist
psql "$CONN_STR" << 'EOF'
-- Insert Admin role if not exists
INSERT INTO "roles" ("id", "name", "description", "createdat")
SELECT gen_random_uuid(), 'Admin', 'Administrator role', NOW()
WHERE NOT EXISTS (SELECT 1 FROM "roles" WHERE "name" = 'Admin');

-- Insert Analyst role if not exists  
INSERT INTO "roles" ("id", "name", "description", "createdat")
SELECT gen_random_uuid(), 'Analyst', 'Analyst role', NOW()
WHERE NOT EXISTS (SELECT 1 FROM "roles" WHERE "name" = 'Analyst');

-- Check inserted roles
SELECT "name", "description", "createdat" FROM "roles" ORDER BY "name";
EOF

if [ $? -eq 0 ]; then
    echo "✅ Roles seeded successfully!"
else
    echo "❌ Failed to seed roles"
    exit 1
fi

echo "🔧 Seeding Analytics Types..."

# Insert analytics types if they don't exist
psql "$CONN_STR" << 'EOF'
-- Insert analytics types if not exist
INSERT INTO "analytics_type" ("id", "code", "name", "description", "createdat")
SELECT gen_random_uuid(), 'RISK', 'Risk Analysis', 'Phân tích rủi ro tài chính', NOW()
WHERE NOT EXISTS (SELECT 1 FROM "analytics_type" WHERE "code" = 'RISK');

INSERT INTO "analytics_type" ("id", "code", "name", "description", "createdat")
SELECT gen_random_uuid(), 'TREND', 'Trend Analysis', 'Phân tích xu hướng phát triển', NOW()
WHERE NOT EXISTS (SELECT 1 FROM "analytics_type" WHERE "code" = 'TREND');

INSERT INTO "analytics_type" ("id", "code", "name", "description", "createdat")
SELECT gen_random_uuid(), 'COMPARISON', 'Comparative Analysis', 'So sánh giữa các công ty', NOW()
WHERE NOT EXISTS (SELECT 1 FROM "analytics_type" WHERE "code" = 'COMPARISON');

INSERT INTO "analytics_type" ("id", "code", "name", "description", "createdat")
SELECT gen_random_uuid(), 'OPPORTUNITY', 'Opportunity Analysis', 'Phân tích cơ hội đầu tư', NOW()
WHERE NOT EXISTS (SELECT 1 FROM "analytics_type" WHERE "code" = 'OPPORTUNITY');

INSERT INTO "analytics_type" ("id", "code", "name", "description", "createdat")
SELECT gen_random_uuid(), 'EXECUTIVE', 'Executive Summary', 'Tóm tắt tổng quan', NOW()
WHERE NOT EXISTS (SELECT 1 FROM "analytics_type" WHERE "code" = 'EXECUTIVE');

-- Check inserted analytics types
SELECT "code", "name", "description" FROM "analytics_type" ORDER BY "code";
EOF

if [ $? -eq 0 ]; then
    echo "✅ Analytics Types seeded successfully!"
else
    echo "❌ Failed to seed analytics types"
    exit 1
fi

echo "🔍 Verifying seeded data..."

# Verify the data
psql "$CONN_STR" << 'EOF'
-- Count roles
SELECT 'roles' as table_name, COUNT(*) as count FROM "roles"
UNION ALL
SELECT 'analytics_type' as table_name, COUNT(*) as count FROM "analytics_type"
ORDER BY table_name;

-- Show all roles
SELECT 'ROLES:' as info;
SELECT "name", "description" FROM "roles" ORDER BY "name";

-- Show all analytics types  
SELECT 'ANALYTICS TYPES:' as info;
SELECT "code", "name" FROM "analytics_type" ORDER BY "code";
EOF

echo ""
echo "🎉 Database seeding completed successfully!"
echo ""
echo "📋 Summary:"
echo "   ✅ Roles table populated"
echo "   ✅ AnalyticsTypes table populated"
echo ""
echo "🔄 Next steps:"
echo "   1. Test user registration API"
echo "   2. Verify Lambda can now create users"
echo "   3. Check API endpoints work correctly"