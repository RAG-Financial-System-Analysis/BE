#!/bin/bash

# Clean Sensitive Data Script
# Removes sensitive information from files before committing to Git

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "🧹 Cleaning sensitive data from project files..."

# Function to create safe version of a file
create_safe_version() {
    local source_file="$1"
    local safe_file="$2"
    local description="$3"
    
    if [[ -f "$source_file" ]]; then
        echo "📝 Creating safe version: $description"
        
        # Create safe version with placeholders
        sed -e 's/sk-proj-[A-Za-z0-9_-]*/your-openai-api-key/g' \
            -e 's/AIzaSy[A-Za-z0-9_-]*/your-gemini-api-key/g' \
            -e 's/AKIAY2BZWOTC[A-Za-z0-9]*/your-aws-access-key/g' \
            -e 's/HqUQ8GK9K[A-Za-z0-9\/+]*/your-aws-secret-key/g' \
            -e 's/ap-southeast-1_[A-Za-z0-9]*/your-cognito-user-pool-id/g' \
            -e 's/76hpd4tfrp93qf33ue6sr0991g/your-cognito-client-id/g' \
            -e 's/myragapp-dev-db\.czk4eg4k0je6\.ap-southeast-1\.rds\.amazonaws\.com/your-rds-endpoint.region.rds.amazonaws.com/g' \
            -e 's/12345678/your-db-password/g' \
            -e 's/Admin@123!!/YourSecureAdminPassword/g' \
            -e 's/Analyst@123!!/YourSecureAnalystPassword/g' \
            -e 's/admin@rag\.com/admin@yourdomain.com/g' \
            -e 's/analyst@rag\.com/analyst@yourdomain.com/g' \
            -e 's/rag-system-12345/your-s3-bucket-name/g' \
            "$source_file" > "$safe_file"
        
        echo "✅ Created: $safe_file"
    else
        echo "⚠️  Source file not found: $source_file"
    fi
}

# Clean database scripts with hardcoded values
echo "🗄️  Cleaning database scripts..."

# Create safe versions of database scripts
if [[ -f "$PROJECT_ROOT/scripts/database/test-seed.sh" ]]; then
    echo "📝 Creating safe database test script..."
    cat > "$PROJECT_ROOT/scripts/database/test-seed.sh.example" << 'EOF'
#!/bin/bash

# Simple test script for seeding - EXAMPLE
echo "Testing new seeding flow..."

# Configuration - REPLACE WITH YOUR VALUES
USER_POOL_ID="your-cognito-user-pool-id"
CLIENT_ID="your-cognito-client-id"
DB_HOST="your-rds-endpoint.region.rds.amazonaws.com"
DB_PORT="5432"
DB_NAME="RAGSystem"
DB_USERNAME="postgres"
DB_PASSWORD="your-db-password"

echo "✅ Configuration loaded"
echo "Database: $DB_HOST:$DB_PORT/$DB_NAME"
echo "User Pool: $USER_POOL_ID"

# Test database connection
echo "Testing database connection..."
PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -d "$DB_NAME" -U "$DB_USERNAME" -p "$DB_PORT" -c "SELECT 1;" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ Database connection successful"
else
    echo "❌ Database connection failed"
    exit 1
fi

# Test AWS CLI
echo "Testing AWS CLI..."
aws sts get-caller-identity > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✅ AWS CLI working"
else
    echo "❌ AWS CLI failed"
    exit 1
fi

echo "🎉 All tests passed! Ready for seeding."
EOF
    echo "✅ Created: scripts/database/test-seed.sh.example"
fi

if [[ -f "$PROJECT_ROOT/scripts/database/create-missing-tables.sh" ]]; then
    echo "📝 Creating safe database creation script..."
    sed -e 's/myragapp-dev-db\.czk4eg4k0je6\.ap-southeast-1\.rds\.amazonaws\.com/your-rds-endpoint.region.rds.amazonaws.com/g' \
        -e 's/12345678/your-db-password/g' \
        "$PROJECT_ROOT/scripts/database/create-missing-tables.sh" > "$PROJECT_ROOT/scripts/database/create-missing-tables.sh.example"
    echo "✅ Created: scripts/database/create-missing-tables.sh.example"
fi

# Update README files to remove sensitive information
echo "📚 Cleaning README files..."

if [[ -f "$PROJECT_ROOT/scripts/database/README.md" ]]; then
    echo "📝 Cleaning database README..."
    sed -e 's/myragapp-dev-db\.czk4eg4k0je6\.ap-southeast-1\.rds\.amazonaws\.com/your-rds-endpoint.region.rds.amazonaws.com/g' \
        -e 's/ap-southeast-1_VTLpFeyhi/your-cognito-user-pool-id/g' \
        -e 's/76hpd4tfrp93qf33ue6sr0991g/your-cognito-client-id/g' \
        -e 's/12345678/your-db-password/g' \
        -e 's/Admin@123!!/YourSecureAdminPassword/g' \
        -e 's/Analyst@123!!/YourSecureAnalystPassword/g' \
        -e 's/admin@rag\.com/admin@yourdomain.com/g' \
        -e 's/analyst@rag\.com/analyst@yourdomain.com/g' \
        "$PROJECT_ROOT/scripts/database/README.md" > "$PROJECT_ROOT/scripts/database/README.md.tmp"
    mv "$PROJECT_ROOT/scripts/database/README.md.tmp" "$PROJECT_ROOT/scripts/database/README.md"
    echo "✅ Cleaned: scripts/database/README.md"
fi

# Clean test files
echo "🧪 Cleaning test files..."

find "$PROJECT_ROOT/scripts/tests" -name "*.sh" -type f | while read -r test_file; do
    if grep -q "Admin@123\|Analyst@123\|12345678" "$test_file" 2>/dev/null; then
        echo "📝 Cleaning: $test_file"
        sed -i.bak -e 's/Admin@123!!/YourSecureAdminPassword/g' \
                   -e 's/Analyst@123!!/YourSecureAnalystPassword/g' \
                   -e 's/admin@rag\.com/admin@yourdomain.com/g' \
                   -e 's/analyst@rag\.com/analyst@yourdomain.com/g' \
                   "$test_file"
        rm -f "$test_file.bak"
        echo "✅ Cleaned: $test_file"
    fi
done

# Create security checklist
echo "📋 Creating security checklist..."
cat > "$PROJECT_ROOT/SECURITY-CHECKLIST.md" << 'EOF'
# Security Checklist

Before committing to Git, ensure:

## ✅ Configuration Files
- [ ] `deployment-config.env` is in .gitignore
- [ ] `lambda-env.json` is in .gitignore  
- [ ] `appsettings.json` is in .gitignore
- [ ] Example files (*.example) are created and safe

## ✅ API Keys & Secrets
- [ ] No OpenAI API keys (sk-proj-*)
- [ ] No Gemini API keys (AIzaSy*)
- [ ] No AWS Access Keys (AKIA*)
- [ ] No AWS Secret Keys
- [ ] No database passwords

## ✅ Infrastructure Details
- [ ] No RDS endpoints
- [ ] No Cognito User Pool IDs
- [ ] No Cognito Client IDs
- [ ] No S3 bucket names with real data

## ✅ User Credentials
- [ ] No hardcoded passwords (Admin@123!!, Analyst@123!!)
- [ ] No real email addresses in examples

## ✅ Files to Check
- [ ] scripts/deployment-config.env → .gitignore
- [ ] lambda-env.json → .gitignore
- [ ] RAG.APIs/appsettings.json → .gitignore
- [ ] scripts/database/*.sh → cleaned or .gitignore
- [ ] scripts/tests/*.sh → cleaned
- [ ] All README.md files → cleaned

## ✅ Safe to Commit
- [ ] Only .example files with placeholders
- [ ] No sensitive data in any committed files
- [ ] .gitignore properly configured
EOF

echo ""
echo "🎉 Sensitive data cleaning completed!"
echo ""
echo "📋 Next steps:"
echo "1. Review the created .example files"
echo "2. Check SECURITY-CHECKLIST.md"
echo "3. Verify .gitignore is working: git status"
echo "4. Test with: git add . --dry-run"
echo ""
echo "⚠️  IMPORTANT: Review all files before committing!"