# Hướng Dẫn Deployment cho RAG System - Simplified Architecture

## 🏗️ Kiến Trúc Deployment Đơn Giản

### Không Sử Dụng VPC
Scripts đã được tối ưu để **KHÔNG sử dụng VPC** nhằm:
- ✅ Đơn giản hóa deployment
- ✅ Lambda có thể truy cập trực tiếp Cognito và external APIs
- ✅ Frontend có thể truy cập RDS public endpoint
- ✅ Giảm chi phí (không cần NAT Gateway)
- ✅ Tăng tốc cold start của Lambda

### Kiến Trúc Hệ Thống
```
Internet
    ↓
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Frontend      │────│   Lambda API     │────│   RDS Public    │
│   (React/Vue)   │    │   (No VPC)       │    │   (PostgreSQL)  │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ↓
                       ┌──────────────────┐
                       │   AWS Cognito    │
                       │   (User Auth)    │
                       └──────────────────┘
```

## 📁 Cấu Trúc Dự Án

```
BE/
├── RAG.APIs/              # Main API project (Lambda entry point)
├── RAG.Application/       # Application layer
├── RAG.Domain/           # Domain layer  
├── RAG.Infrastructure/   # Infrastructure layer
├── Database/             # Database scripts
├── appsettings.json      # Configuration
├── RAG-System.slnx       # Solution file
└── scripts/              # Deployment scripts
    ├── infrastructure/   # AWS resource provisioning
    ├── deployment/       # Application deployment
    ├── migration/        # Database migrations
    └── utilities/        # Helper scripts
```

## 📋 Cấu Hình Deployment

### Tạo File Cấu Hình
```bash
# Tạo file config deployment
cat > deployment-config.env << EOF
# RAG System Deployment Configuration
PROJECT_NAME="rag-system"
SOLUTION_FILE="RAG-System.slnx"
MAIN_PROJECT="RAG.APIs"
MAIN_PROJECT_PATH="RAG.APIs/RAG.APIs.csproj"
DATABASE_SCRIPT="Database/scriptDB_final.sql"
APPSETTINGS_FILE="RAG.APIs/appsettings.json"

# AWS Configuration
AWS_REGION="ap-southeast-1"
LAMBDA_RUNTIME="dotnet8"
LAMBDA_MEMORY="1024"
LAMBDA_TIMEOUT="30"

# Database Configuration (Public Access)
DB_ENGINE="postgres"
DB_VERSION="16.13"
DB_INSTANCE_CLASS="db.t3.micro"
DB_NAME="appdb"
DB_PUBLIC_ACCESS="true"
EOF
```

### Cấu Hình AWS CLI
```bash
# Cấu hình AWS credentials
aws configure
# AWS Access Key ID: [Your Access Key]
# AWS Secret Access Key: [Your Secret Key]  
# Default region name: ap-southeast-1
# Default output format: json

# Hoặc sử dụng profile
aws configure --profile rag-system
export AWS_PROFILE=rag-system
```

## 🚀 Deployment Commands

### 1. Thiết Lập Ban Đầu
```bash
# Validate AWS setup
./scripts/utilities/validate-aws-cli.sh

# Test build dự án
dotnet build RAG-System.slnx
```

### 2. Deploy Infrastructure (Lần Đầu)
```bash
# Deploy RDS PostgreSQL (Public Access)
./scripts/infrastructure/provision-rds.sh \
  --environment production \
  --project-name rag-system \
  --instance-class db.t3.micro \
  --storage 20

# Deploy Lambda Function (No VPC)
./scripts/infrastructure/provision-lambda.sh \
  --environment production \
  --project-name rag-system \
  --memory 1024 \
  --timeout 30
```

### 3. Deploy Application Code
```bash
# Full deployment (infrastructure + application)
./scripts/deploy.sh \
  --mode initial \
  --environment production \
  --project-name rag-system \
  --aws-region ap-southeast-1

# Update deployment (code only)
./scripts/deploy.sh \
  --mode update \
  --environment production \
  --project-name rag-system
```

### 4. Database Setup
```bash
# Run migrations
./scripts/migration/run-migrations.sh \
  --environment production

# Seed initial data (if needed)
./scripts/migration/seed-data.sh \
  --environment production
```

## 🔧 Lợi Ích Của Kiến Trúc Không VPC

### RDS Public Access
- ✅ Frontend có thể kết nối trực tiếp từ browser (với CORS)
- ✅ Developers có thể kết nối từ local development
- ✅ Không cần bastion host hoặc VPN
- ✅ Đơn giản hóa network configuration

### Lambda No VPC
- ✅ Cold start nhanh hơn (không có VPC overhead)
- ✅ Truy cập trực tiếp AWS services (Cognito, S3, etc.)
- ✅ Có thể gọi external APIs mà không cần NAT Gateway
- ✅ Giảm complexity và cost

### Security Considerations
- 🔒 RDS security group chỉ mở port 5432
- 🔒 Strong password generation và SSL required
- 🔒 Lambda IAM role với least privilege
- 🔒 Cognito authentication cho API access

## 🔍 Connection Strings và Configuration

### Database Connection String
```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=<RDS_ENDPOINT>;Database=appdb;Username=dbadmin;Password=<PASSWORD>;Port=5432;SSL Mode=Require;"
  },
  "AWS": {
    "Region": "ap-southeast-1",
    "Cognito": {
      "UserPoolId": "<USER_POOL_ID>",
      "ClientId": "<CLIENT_ID>"
    }
  }
}
```

### Frontend Configuration
```javascript
// Frontend có thể kết nối trực tiếp RDS (nếu cần)
const dbConfig = {
  host: '<RDS_ENDPOINT>',
  database: 'appdb',
  port: 5432,
  ssl: { rejectUnauthorized: false }
};

// Lambda API endpoint
const apiEndpoint = 'https://<LAMBDA_FUNCTION_URL>';
```

## 📋 Deployment Workflow

### Development → Staging → Production
```bash
# 1. Development (Local)
dotnet run --project RAG.APIs
# Test với local database hoặc staging database

# 2. Deploy to Staging
./scripts/deploy.sh --mode initial --environment staging --project-name rag-system-staging

# 3. Test Staging
curl https://<staging-lambda-url>/swagger
# Test all API endpoints

# 4. Deploy to Production  
./scripts/deploy.sh --mode initial --environment production --project-name rag-system

# 5. Verify Production
curl https://<production-lambda-url>/health
```

### Update Workflow
```bash
# 1. Code changes
git pull origin main

# 2. Build and test
dotnet build RAG-System.slnx

# 3. Update staging
./scripts/deploy.sh --mode update --environment staging --project-name rag-system-staging

# 4. Test staging
# Run integration tests

# 5. Update production
./scripts/deploy.sh --mode update --environment production --project-name rag-system
```

## 🔍 Monitoring và Troubleshooting

### Xem Logs
```bash
# Deployment logs (organized in logs/ directory)
ls -la logs/
cat logs/deployment_*.log

# Lambda logs trên AWS
aws logs tail /aws/lambda/rag-system-production-api --follow

# RDS logs
aws rds describe-db-log-files --db-instance-identifier rag-system-production-db
```

### Health Check Scripts
```bash
# Check infrastructure status
./scripts/utilities/check-infrastructure.sh \
  --environment production \
  --project-name rag-system

# Test database connectivity
psql -h <RDS_ENDPOINT> -U dbadmin -d appdb -c "SELECT version();"

# Test Lambda function
aws lambda invoke \
  --function-name rag-system-production-api \
  --payload '{"test": "health-check"}' \
  response.json
```

### Common Issues và Solutions

#### 1. RDS Connection Issues
```bash
# Check security group
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=rag-system-production-rds-sg"

# Test connectivity
telnet <RDS_ENDPOINT> 5432

# Check RDS status
aws rds describe-db-instances \
  --db-instance-identifier rag-system-production-db
```

#### 2. Lambda Cold Start Issues
```bash
# Increase memory allocation
aws lambda update-function-configuration \
  --function-name rag-system-production-api \
  --memory-size 1024

# Check execution duration
aws logs filter-log-events \
  --log-group-name /aws/lambda/rag-system-production-api \
  --filter-pattern "REPORT"
```

#### 3. Build/Deployment Issues
```bash
# Clean build
dotnet clean RAG-System.slnx
dotnet restore RAG-System.slnx
dotnet build RAG-System.slnx --configuration Release

# Check deployment package
unzip -l rag-system-deployment.zip | head -20
```

## 🎯 Production Checklist

### Pre-Deployment
- [ ] AWS CLI configured và tested
- [ ] Code reviewed và merged
- [ ] Local build successful
- [ ] Database migrations tested on staging
- [ ] Environment variables configured

### Deployment
- [ ] RDS instance provisioned
- [ ] Lambda function created
- [ ] Database migrations applied
- [ ] Application code deployed
- [ ] Environment variables updated

### Post-Deployment
- [ ] API endpoints responding
- [ ] Database connectivity verified
- [ ] CloudWatch logs showing no errors
- [ ] Performance metrics within acceptable range
- [ ] Security groups properly configured

## 💡 Best Practices

### Security
- Use strong passwords for RDS
- Enable SSL/TLS for all connections
- Regularly rotate credentials
- Monitor CloudWatch for suspicious activity
- Use least privilege IAM policies

### Performance
- Monitor Lambda cold starts
- Optimize database queries
- Use connection pooling
- Consider provisioned concurrency for high-traffic functions

### Cost Optimization
- Use appropriate instance sizes
- Monitor AWS costs regularly
- Clean up unused resources
- Use reserved instances for predictable workloads

## 📞 Support

Nếu gặp vấn đề:
1. Check logs: `cat deployment_errors.log`
2. Validate AWS: `./scripts/utilities/validate-aws-cli.sh`
3. Check infrastructure: `./scripts/utilities/check-infrastructure.sh`
4. Review AWS Console để kiểm tra resources