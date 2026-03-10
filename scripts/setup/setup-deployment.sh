#!/bin/bash

# Setup Deployment Scripts for RAG System
# Tự động tích hợp deployment scripts vào dự án RAG

set -euo pipefail

echo "🚀 Setting up deployment scripts for RAG System..."

# Get current directory
CURRENT_DIR="$(pwd)"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "📁 Project root: $PROJECT_ROOT"

# Step 1: Copy scripts if not exists
if [ ! -d "$PROJECT_ROOT/scripts" ]; then
    echo "📋 Copying deployment scripts..."
    
    # Try to find scripts in parent directories
    SCRIPTS_SOURCE=""
    
    # Check if we're in the BE copy directory and scripts exist in SWD root
    if [ -d "../../scripts" ]; then
        SCRIPTS_SOURCE="../../scripts"
    elif [ -d "../../../scripts" ]; then
        SCRIPTS_SOURCE="../../../scripts"
    else
        echo "❌ Cannot find scripts directory. Please copy scripts folder to $PROJECT_ROOT/"
        echo "   Expected location: $PROJECT_ROOT/scripts/"
        exit 1
    fi
    
    echo "   Copying from: $SCRIPTS_SOURCE"
    cp -r "$SCRIPTS_SOURCE" "$PROJECT_ROOT/"
    echo "✅ Scripts copied successfully"
else
    echo "✅ Scripts directory already exists"
fi

# Step 2: Make scripts executable
echo "🔧 Making scripts executable..."
find "$PROJECT_ROOT/scripts" -name "*.sh" -exec chmod +x {} \;
echo "✅ Scripts are now executable"

# Step 3: Create deployment configuration
echo "⚙️ Creating deployment configuration..."

cat > "$PROJECT_ROOT/deployment-config.env" << 'EOF'
# RAG System Deployment Configuration
PROJECT_NAME="rag-system"
SOLUTION_FILE="RAG-System.slnx"
MAIN_PROJECT="RAG.APIs"
MAIN_PROJECT_PATH="RAG.APIs/RAG.APIs.csproj"
DATABASE_SCRIPT="Database/scriptDB_final.sql"
APPSETTINGS_FILE="RAG.APIs/appsettings.json"

# AWS Configuration (from your appsettings.json)
AWS_REGION="ap-southeast-1"
LAMBDA_RUNTIME="dotnet10"
LAMBDA_MEMORY="1024"
LAMBDA_TIMEOUT="30"

# Database Configuration  
DB_ENGINE="postgres"
DB_VERSION="16.4"
DB_INSTANCE_CLASS="db.t3.micro"
DB_NAME="RAG-System"

# Cognito Configuration (from your appsettings.json)
COGNITO_USER_POOL_ID="ap-southeast-1_VTLpFeyhi"
COGNITO_CLIENT_ID="76hpd4tfrp93qf33ue6sr0991g"

# S3 Configuration
S3_BUCKET_NAME="rag-system-12345"
EOF

echo "✅ Deployment configuration created"

# Step 4: Create RAG-specific deployment wrapper
echo "🎯 Creating RAG-specific deployment wrapper..."

cat > "$PROJECT_ROOT/deploy-rag.sh" << 'EOF'
#!/bin/bash

# RAG System Deployment Wrapper
# Simplified deployment commands for RAG System

set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/deployment-config.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_usage() {
    echo -e "${BLUE}RAG System Deployment Tool${NC}"
    echo ""
    echo "Usage: $0 <command> [environment]"
    echo ""
    echo "Commands:"
    echo "  setup                    - Setup AWS CLI and validate configuration"
    echo "  deploy-staging          - Deploy to staging environment"
    echo "  deploy-production       - Deploy to production environment"
    echo "  update-staging          - Update code on staging"
    echo "  update-production       - Update code on production"
    echo "  rollback-staging        - Rollback staging deployment"
    echo "  rollback-production     - Rollback production deployment"
    echo "  cleanup-staging         - Cleanup staging resources"
    echo "  logs-staging           - View staging logs"
    echo "  logs-production        - View production logs"
    echo "  status                 - Check infrastructure status"
    echo ""
    echo "Examples:"
    echo "  $0 setup"
    echo "  $0 deploy-staging"
    echo "  $0 update-production"
    echo "  $0 logs-production"
}

setup_aws() {
    echo -e "${BLUE}🔧 Setting up AWS CLI...${NC}"
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}❌ AWS CLI is not installed${NC}"
        echo "Please install AWS CLI first:"
        echo "  Windows: winget install Amazon.AWSCLI"
        echo "  macOS: brew install awscli"
        echo "  Linux: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi
    
    # Validate AWS configuration
    ./scripts/utilities/validate-aws-cli.sh
}

deploy_environment() {
    local env="$1"
    local project_name="${PROJECT_NAME}-${env}"
    
    echo -e "${BLUE}🚀 Deploying RAG System to ${env}...${NC}"
    
    # Build project first
    echo -e "${YELLOW}📦 Building RAG System...${NC}"
    dotnet build "$SOLUTION_FILE" --configuration Release
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Build failed${NC}"
        exit 1
    fi
    
    # Deploy using main script
    ./scripts/deploy.sh \
        --mode initial \
        --environment "$env" \
        --project-name "$project_name" \
        --aws-region "$AWS_REGION"
}

update_environment() {
    local env="$1"
    local project_name="${PROJECT_NAME}-${env}"
    
    echo -e "${BLUE}🔄 Updating RAG System on ${env}...${NC}"
    
    # Build project first
    echo -e "${YELLOW}📦 Building RAG System...${NC}"
    dotnet build "$SOLUTION_FILE" --configuration Release
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Build failed${NC}"
        exit 1
    fi
    
    # Update using main script
    ./scripts/deploy.sh \
        --mode update \
        --environment "$env" \
        --project-name "$project_name" \
        --aws-region "$AWS_REGION"
}

rollback_environment() {
    local env="$1"
    local project_name="${PROJECT_NAME}-${env}"
    
    echo -e "${YELLOW}⏪ Rolling back RAG System on ${env}...${NC}"
    
    ./scripts/deploy.sh \
        --mode rollback \
        --environment "$env" \
        --project-name "$project_name" \
        --force
}

cleanup_environment() {
    local env="$1"
    
    echo -e "${RED}🗑️ Cleaning up ${env} resources...${NC}"
    echo -e "${YELLOW}⚠️ This will delete all AWS resources for ${env}!${NC}"
    read -p "Are you sure? (yes/no): " confirm
    
    if [ "$confirm" = "yes" ]; then
        ./scripts/infrastructure/cleanup-infrastructure.sh \
            --environment "$env" \
            --force
    else
        echo "Cleanup cancelled"
    fi
}

view_logs() {
    local env="$1"
    local function_name="${PROJECT_NAME}-${env}"
    
    echo -e "${BLUE}📋 Viewing logs for ${env}...${NC}"
    
    # Try to get Lambda function name
    local lambda_name=$(aws lambda list-functions \
        --query "Functions[?contains(FunctionName, '${function_name}')].FunctionName" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$lambda_name" ]; then
        echo "Lambda function: $lambda_name"
        aws logs tail "/aws/lambda/$lambda_name" --follow
    else
        echo -e "${YELLOW}⚠️ Lambda function not found for ${env}${NC}"
        echo "Available functions:"
        aws lambda list-functions --query "Functions[].FunctionName" --output table
    fi
}

check_status() {
    echo -e "${BLUE}📊 Checking RAG System status...${NC}"
    
    for env in staging production; do
        echo -e "\n${YELLOW}=== $env Environment ===${NC}"
        ./scripts/utilities/check-infrastructure.sh \
            --environment "$env" \
            --project-name "${PROJECT_NAME}-${env}" || true
    done
}

# Main command handling
case "${1:-}" in
    setup)
        setup_aws
        ;;
    deploy-staging)
        deploy_environment "staging"
        ;;
    deploy-production)
        deploy_environment "production"
        ;;
    update-staging)
        update_environment "staging"
        ;;
    update-production)
        update_environment "production"
        ;;
    rollback-staging)
        rollback_environment "staging"
        ;;
    rollback-production)
        rollback_environment "production"
        ;;
    cleanup-staging)
        cleanup_environment "staging"
        ;;
    logs-staging)
        view_logs "staging"
        ;;
    logs-production)
        view_logs "production"
        ;;
    status)
        check_status
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
EOF

chmod +x "$PROJECT_ROOT/deploy-rag.sh"
echo "✅ RAG deployment wrapper created"

# Step 5: Create quick start guide
echo "📖 Creating quick start guide..."

cat > "$PROJECT_ROOT/QUICK_START.md" << 'EOF'
# RAG System - Quick Start Deployment

## 🚀 Bắt Đầu Nhanh

### 1. Thiết Lập Lần Đầu
```bash
# Setup AWS CLI và validate
./deploy-rag.sh setup
```

### 2. Deploy Lần Đầu
```bash
# Deploy lên staging trước
./deploy-rag.sh deploy-staging

# Nếu OK, deploy lên production
./deploy-rag.sh deploy-production
```

### 3. Cập Nhật Code Hàng Ngày
```bash
# Update staging
./deploy-rag.sh update-staging

# Update production
./deploy-rag.sh update-production
```

### 4. Monitoring
```bash
# Xem logs staging
./deploy-rag.sh logs-staging

# Xem logs production  
./deploy-rag.sh logs-production

# Check status tất cả environments
./deploy-rag.sh status
```

### 5. Troubleshooting
```bash
# Rollback nếu có lỗi
./deploy-rag.sh rollback-production

# Cleanup environment (cẩn thận!)
./deploy-rag.sh cleanup-staging
```

## 📋 Checklist Deploy Production

- [ ] Code đã được test trên staging
- [ ] Database migrations đã được verify
- [ ] Backup production database (nếu cần)
- [ ] Deploy và test trên staging trước
- [ ] Deploy lên production
- [ ] Verify API endpoints
- [ ] Check logs và monitoring

## 🔗 Useful Links

- AWS Console: https://console.aws.amazon.com/
- Lambda Functions: https://console.aws.amazon.com/lambda/
- RDS Databases: https://console.aws.amazon.com/rds/
- CloudWatch Logs: https://console.aws.amazon.com/cloudwatch/
EOF

echo "✅ Quick start guide created"

# Step 6: Validate setup
echo "🔍 Validating setup..."

# Check if .NET is available
if command -v dotnet &> /dev/null; then
    echo "✅ .NET CLI is available"
    dotnet --version
else
    echo "⚠️ .NET CLI not found - please install .NET 10 SDK"
fi

# Check if solution file exists
if [ -f "$PROJECT_ROOT/$SOLUTION_FILE" ]; then
    echo "✅ Solution file found: $SOLUTION_FILE"
else
    echo "⚠️ Solution file not found: $SOLUTION_FILE"
fi

# Check if main project exists
if [ -f "$PROJECT_ROOT/$MAIN_PROJECT_PATH" ]; then
    echo "✅ Main project found: $MAIN_PROJECT_PATH"
else
    echo "⚠️ Main project not found: $MAIN_PROJECT_PATH"
fi

echo ""
echo "🎉 Setup completed successfully!"
echo ""
echo "Next steps:"
echo "1. Run: ./deploy-rag.sh setup"
echo "2. Run: ./deploy-rag.sh deploy-staging"
echo "3. Test your staging API"
echo "4. Run: ./deploy-rag.sh deploy-production"
echo ""
echo "📖 Read QUICK_START.md for detailed instructions"
echo "📖 Read DEPLOYMENT_GUIDE.md for advanced usage"