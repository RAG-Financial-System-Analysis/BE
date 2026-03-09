# Hướng Dẫn Tích Hợp Scripts Deployment cho RAG System

## 🏗️ Cấu Trúc Dự Án Hiện Tại

```
BE copy/
├── RAG.APIs/              # Main API project (Lambda entry point)
├── RAG.Application/       # Application layer
├── RAG.Domain/           # Domain layer  
├── RAG.Infrastructure/   # Infrastructure layer
├── Database/             # Database scripts
├── appsettings.json      # Configuration
├── RAG-System.slnx       # Solution file
└── scripts/              # 👈 Đặt folder scripts ở đây
```

## 📁 Cách Tích Hợp Scripts

### Bước 1: Copy Scripts vào Dự Án
```bash
# Từ thư mục gốc (SWD/)
cp -r scripts/ "code/TestDeployLambda/BE copy/"

# Hoặc trên Windows
xcopy scripts "code\TestDeployLambda\BE copy\scripts" /E /I
```

### Bước 2: Cấu Hình Scripts cho Dự Án RAG

Tạo file cấu hình deployment:

```bash
# Tạo file config deployment
cat > "code/TestDeployLambda/BE copy/deployment-config.env" << EOF
# RAG System Deployment Configuration
PROJECT_NAME="rag-system"
SOLUTION_FILE="RAG-System.slnx"
MAIN_PROJECT="RAG.APIs"
MAIN_PROJECT_PATH="RAG.APIs/RAG.APIs.csproj"
DATABASE_SCRIPT="Database/scriptDB_final.sql"
APPSETTINGS_FILE="RAG.APIs/appsettings.json"

# AWS Configuration
AWS_REGION="ap-southeast-1"
LAMBDA_RUNTIME="dotnet10"
LAMBDA_MEMORY="1024"
LAMBDA_TIMEOUT="30"

# Database Configuration  
DB_ENGINE="postgres"
DB_VERSION="16.4"
DB_INSTANCE_CLASS="db.t3.micro"
DB_NAME="RAG-System"
EOF
```

## 🚀 Cách Sử Dụng với Dự Án RAG

### Thiết Lập Ban Đầu

```bash
# 1. Di chuyển vào thư mục dự án
cd "code/TestDeployLambda/BE copy"

# 2. Load configuration
source deployment-config.env

# 3. Validate AWS setup
./scripts/utilities/validate-aws-cli.sh

# 4. Test build dự án
dotnet build RAG-System.slnx
```

### Deploy Lần Đầu (Initial Deployment)

```bash
# Deploy toàn bộ infrastructure + application
./scripts/deploy.sh \
  --mode initial \
  --environment production \
  --project-name rag-system \
  --aws-region ap-southeast-1

# Hoặc deploy staging trước
./scripts/deploy.sh \
  --mode initial \
  --environment staging \
  --project-name rag-system-staging \
  --aws-region ap-southeast-1
```

### Cập Nhật Code (Update Deployment)

```bash
# Sau khi có code mới
git pull origin main

# Build và test local
dotnet build RAG-System.slnx
dotnet test  # nếu có tests

# Deploy code mới
./scripts/deploy.sh \
  --mode update \
  --environment production \
  --project-name rag-system
```

### Database Migrations

```bash
# Tạo migration mới (trong RAG.Infrastructure)
cd RAG.Infrastructure
dotnet ef migrations add NewFeatureMigration --startup-project ../RAG.APIs

# Deploy với migration
cd ..
./scripts/deploy.sh --mode update --environment staging --project-name rag-system-staging
```

## 🔧 Tùy Chỉnh Scripts cho RAG System

### 1. Cập Nhật Lambda Deployment Script

Tạo file override cho Lambda deployment:

```bash
cat > scripts/deployment/deploy-lambda-rag.sh << 'EOF'
#!/bin/bash
# Custom Lambda deployment for RAG System

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/utilities/logging.sh"
source "$SCRIPT_DIR/utilities/error-handling.sh"

# RAG-specific configuration
SOLUTION_FILE="RAG-System.slnx"
MAIN_PROJECT="RAG.APIs"
OUTPUT_DIR="publish"

deploy_rag_lambda() {
    local function_name="$1"
    local environment="$2"
    
    log_info "Building RAG System for Lambda deployment..."
    
    # Clean previous builds
    rm -rf "$OUTPUT_DIR"
    
    # Build and publish
    dotnet publish "$MAIN_PROJECT" \
        --configuration Release \
        --runtime linux-x64 \
        --self-contained false \
        --output "$OUTPUT_DIR" \
        /p:PublishReadyToRun=true
    
    # Create deployment package
    cd "$OUTPUT_DIR"
    zip -r "../rag-system-deployment.zip" .
    cd ..
    
    # Deploy to Lambda
    aws lambda update-function-code \
        --function-name "$function_name" \
        --zip-file "fileb://rag-system-deployment.zip"
    
    log_success "RAG System deployed to Lambda: $function_name"
}

# Execute if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    deploy_rag_lambda "$@"
fi
EOF

chmod +x scripts/deployment/deploy-lambda-rag.sh
```

### 2. Cập Nhật Database Migration Script

```bash
cat > scripts/migration/run-migrations-rag.sh << 'EOF'
#!/bin/bash
# Custom migration runner for RAG System

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/utilities/logging.sh"

run_rag_migrations() {
    local connection_string="$1"
    
    log_info "Running RAG System migrations..."
    
    # Run EF migrations from Infrastructure project
    cd RAG.Infrastructure
    
    dotnet ef database update \
        --startup-project ../RAG.APIs \
        --connection "$connection_string"
    
    cd ..
    
    log_success "RAG System migrations completed"
}

# Execute if called directly  
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_rag_migrations "$@"
fi
EOF

chmod +x scripts/migration/run-migrations-rag.sh
```

## 📋 Workflow Deployment cho RAG System

### Development Workflow
```bash
# 1. Develop locally
dotnet run --project RAG.APIs

# 2. Test với local database
# (Sử dụng connection string trong appsettings.Development.json)

# 3. Deploy lên staging
./scripts/deploy.sh --mode update --environment staging --project-name rag-system-staging

# 4. Test trên staging
curl https://your-staging-api.amazonaws.com/swagger

# 5. Deploy lên production
./scripts/deploy.sh --mode update --environment production --project-name rag-system
```

### Production Deployment Checklist
- [ ] Code đã được review và merge vào main branch
- [ ] Tests đã pass (nếu có)
- [ ] Database migrations đã được test trên staging
- [ ] Backup database production (nếu cần)
- [ ] Deploy lên staging và test trước
- [ ] Deploy lên production
- [ ] Verify API endpoints hoạt động
- [ ] Check CloudWatch logs

## 🔍 Monitoring và Troubleshooting

### Xem Logs
```bash
# Logs deployment
cat deployment.log

# Logs Lambda trên AWS
aws logs tail /aws/lambda/rag-system-production --follow

# Logs RDS (nếu có)
aws rds describe-db-log-files --db-instance-identifier rag-system-production
```

### Health Check
```bash
# Check infrastructure
./scripts/utilities/check-infrastructure.sh --environment production --project-name rag-system

# Test API endpoints
curl https://your-api.amazonaws.com/swagger
curl https://your-api.amazonaws.com/health  # nếu có health endpoint
```

### Common Issues

1. **Build Error**: 
   ```bash
   # Clean và rebuild
   dotnet clean RAG-System.slnx
   dotnet build RAG-System.slnx
   ```

2. **Migration Error**:
   ```bash
   # Check connection string
   ./scripts/utilities/check-infrastructure.sh --environment production
   
   # Manual migration
   cd RAG.Infrastructure
   dotnet ef database update --startup-project ../RAG.APIs
   ```

3. **Lambda Cold Start**:
   - Tăng memory allocation trong deployment config
   - Sử dụng provisioned concurrency (tốn phí)

## 🎯 Next Steps

1. **Setup CI/CD**: Tích hợp scripts vào GitHub Actions hoặc Azure DevOps
2. **Monitoring**: Setup CloudWatch alarms và notifications
3. **Security**: Review IAM permissions và security groups
4. **Performance**: Monitor Lambda performance và optimize
5. **Backup**: Setup automated database backups

## 📞 Support

Nếu gặp vấn đề:
1. Check logs: `cat deployment_errors.log`
2. Validate AWS: `./scripts/utilities/validate-aws-cli.sh`
3. Check infrastructure: `./scripts/utilities/check-infrastructure.sh`
4. Review AWS Console để kiểm tra resources