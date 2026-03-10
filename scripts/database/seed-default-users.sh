#!/bin/bash

# Seed default users into database with correct roles
# These users already exist in AWS Cognito, we just need to add them to database

echo "🔧 Seeding default users into database..."

# Database connection details
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
    exit 1
fi

echo "🔍 Testing database connection..."
if ! psql "$CONN_STR" -c "SELECT 1;" &> /dev/null; then
    echo "❌ Cannot connect to database."
    exit 1
fi

echo "✅ Database connection successful!"

echo "🔍 Checking existing users and roles..."

# Show current users and roles
psql "$CONN_STR" << 'EOF'
-- Show current roles
SELECT 'CURRENT ROLES:' as info;
SELECT id, name, description FROM roles ORDER BY name;

-- Show current users
SELECT 'CURRENT USERS:' as info;
SELECT u.email, u.fullname, r.name as role_name, u.cognitosub 
FROM users u 
LEFT JOIN roles r ON u.roleid = r.id 
ORDER BY u.email;
EOF

echo ""
echo "🔧 Seeding default users..."

# Get role IDs
ADMIN_ROLE_ID=$(psql "$CONN_STR" -t -c "SELECT id FROM roles WHERE name = 'Admin';" | xargs)
ANALYST_ROLE_ID=$(psql "$CONN_STR" -t -c "SELECT id FROM roles WHERE name = 'Analyst';" | xargs)

echo "Admin Role ID: $ADMIN_ROLE_ID"
echo "Analyst Role ID: $ANALYST_ROLE_ID"

if [ -z "$ADMIN_ROLE_ID" ] || [ -z "$ANALYST_ROLE_ID" ]; then
    echo "❌ Roles not found. Please run seed-roles-direct.sh first."
    exit 1
fi

# Insert default users with correct roles and Cognito subs
psql "$CONN_STR" << EOF
-- Insert admin user if not exists
INSERT INTO users (id, email, fullname, roleid, cognitosub, isactive, createdat)
SELECT gen_random_uuid(), 'admin@rag.com', 'System Admin', '$ADMIN_ROLE_ID', '597a056c-3001-7060-873f-d3d5a6325c5b', true, NOW()
WHERE NOT EXISTS (SELECT 1 FROM users WHERE email = 'admin@rag.com');

-- Insert analyst user if not exists  
INSERT INTO users (id, email, fullname, roleid, cognitosub, isactive, createdat)
SELECT gen_random_uuid(), 'analyst@rag.com', 'System Analyst', '$ANALYST_ROLE_ID', '29da45ac-0071-70be-c7fb-d38f1572a6ed', true, NOW()
WHERE NOT EXISTS (SELECT 1 FROM users WHERE email = 'analyst@rag.com');

-- Show results
SELECT 'SEEDED USERS:' as info;
SELECT u.email, u.fullname, r.name as role_name, u.cognitosub, u.isactive
FROM users u 
JOIN roles r ON u.roleid = r.id 
WHERE u.email IN ('admin@rag.com', 'analyst@rag.com')
ORDER BY u.email;
EOF

if [ $? -eq 0 ]; then
    echo "✅ Default users seeded successfully!"
else
    echo "❌ Failed to seed default users"
    exit 1
fi

echo ""
echo "🔍 Verifying all users..."

# Show all users with roles
psql "$CONN_STR" << 'EOF'
SELECT 'ALL USERS WITH ROLES:' as info;
SELECT u.email, u.fullname, r.name as role_name, u.isactive, u.createdat
FROM users u 
JOIN roles r ON u.roleid = r.id 
ORDER BY r.name, u.email;

-- Count by role
SELECT 'USER COUNT BY ROLE:' as info;
SELECT r.name as role_name, COUNT(u.id) as user_count
FROM roles r
LEFT JOIN users u ON r.id = u.roleid
GROUP BY r.id, r.name
ORDER BY r.name;
EOF

echo ""
echo "🎉 Default users seeding completed successfully!"
echo ""
echo "📋 Summary:"
echo "   ✅ admin@rag.com → Admin role"
echo "   ✅ analyst@rag.com → Analyst role"
echo ""
echo "🔄 Next steps:"
echo "   1. Test login with admin@rag.com / Admin@123!!"
echo "   2. Test login with analyst@rag.com / Analyst@123!!"
echo "   3. Verify role-based access in API"