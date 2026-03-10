# RAG System AWS Deployment Guide

Complete guide for deploying the RAG System to AWS using Lambda, RDS, and API Gateway.

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Deployment Steps](#detailed-deployment-steps)
- [Configuration](#configuration)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)

## 🎯 Overview

This deployment guide covers the complete RAG System deployment to AWS with the following architecture:

- **RDS PostgreSQL**: Database for storing application data
- **AWS Lambda**: .NET 10 serverless function hosting the API
- **API Gateway**: REST API endpoint for client access
- **AWS Cognito**: User authentication and authorization

### Deployment Order

The deployment follows this specific order to ensure dependencies are met:

1. 🗄️ **Deploy RDS Database**
2. ⚡ **Deploy Lambda Function**
3. 🔄 **Run Database Migrations** (from Lambda to DB)
4. 🌱 **Trigger DbInitializer** (automatically seeds roles, analytics types, and users)
5. � **Deploy API Gateway**
6. 🧪 **Run Tests**

## 🔧 Prerequisites

### Required Software

- **AWS CLI** v2.0+ with flexible credential configuration (see below)
- **.NET SDK** 8.0+ (for building .NET 10 applications)
- **PostgreSQL Client** (psql) for database operations
- **Bash** shell (Git Bash on Windows)

### AWS Credentials Setup (One-Time Configuration)

**⚠️ QUAN TRỌNG: Bạn chỉ cần cấu hình AWS credentials MỘT LẦN duy nhất. Sau đó tất cả các lần deploy sẽ tự động sử dụng credentials đã lưu.**

The deployment scripts support multiple AWS credential configuration methods and will automatically detect which method you're using:

#### Method 1: AWS CLI Configuration (Recommended - Chỉ cần làm 1 lần)
```bash
aws configure
```
**Nhập thông tin khi được hỏi:**
- AWS Access Key ID: [your-access-key]
- AWS Secret Access Key: [your-secret-key]
- Default region name: `ap-southeast-1` (Singapore - gần Việt Nam nhất)
- Default output format: `json`

**📁 Credentials được lưu tại:**
- `~/.aws/credentials` - chứa Access Key ID và Secret Access Key
- `~/.aws/config` - chứa region và các cấu hình khác

**🔒 Bảo mật:**
- Các file này ở ngoài project, không bao giờ bị commit vào git
- Không cần ignore vì chúng ở trong thư mục home của user
- Tự động được sử dụng cho tất cả AWS CLI commands

#### Method 2: Environment Variables (Temporary)
```bash
export AWS_ACCESS_KEY_ID=your_access_key_id
export AWS_SECRET_ACCESS_KEY=your_secret_access_key
export AWS_DEFAULT_REGION=ap-southeast-1
```

#### Method 3: AWS Profiles (Multiple accounts)
```bash
aws configure --profile <profile-name>
export AWS_PROFILE=<profile-name>
```

#### Method 4: IAM Roles (EC2/Lambda instances)
- Attach IAM role to EC2 instance
- No additional configuration needed

#### Method 5: AWS SSO (Organizations)
```bash
aws configure sso
```

**🔍 Kiểm tra credentials đã cấu hình:**
```bash
aws sts get-caller-identity
./scripts/tests/test-credential-detection.sh
```

### AWS Permissions Required
```bash
aws configure sso
```

**Verification**: Test your credentials with:
```bash
aws sts get-caller-identity
```

**Note**: The scripts will automatically detect and use whichever credential method you have configured. You don't need to run `aws configure` if you already have credentials set up via environment variables, profiles, or IAM roles.

### AWS Permissions

Your AWS user/role needs the following permissions:

- **RDS**: Full access for database creation and management
- **Lambda**: Full access for function deployment and configuration
- **API Gateway**: Full access for API creation and management
- **IAM**: Permissions to create and manage service roles
- **CloudWatch**: Access for logging and monitoring

### Configuration Files

The deployment system uses two main configuration files:

1. **`deployment-config.env`** - **Deployment parameters and infrastructure settings**
2. **`RAG.APIs/appsettings.json`** - **Application configuration and database settings**

#### Deployment Configuration (`deployment-config.env`)

This file contains all deployment parameters:

```bash
# Basic settings
ENVIRONMENT=dev
PROJECT_NAME=myapp
AWS_DEFAULT_REGION=ap-southeast-1

# Lambda settings
LAMBDA_RUNTIME=dotnet10
LAMBDA_MEMORY_SIZE=512
LAMBDA_TIMEOUT=30

# RDS settings
RDS_INSTANCE_CLASS=db.t3.micro
RDS_ALLOCATED_STORAGE=20
RDS_MULTI_AZ=false

# Deployment options
SKIP_TESTS=false
SKIP_SEEDING=false
```

#### Application Configuration (`appsettings.json`)

This file contains application-specific settings:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Port=5432;Database=RAGSystem;Username=postgres;Password=12345678"
  },
  "AWS": {
    "Region": "ap-southeast-1",
    "UserPoolId": "your-user-pool-id",
    "ClientId": "your-client-id"
  }
}
```

#### Managing Configuration

Use the configuration management script:

```bash
# Show current configuration
./scripts/manage-config.sh show

# Create environment-specific configurations
./scripts/manage-config.sh create --template production --output ./production-config.env

# Validate configuration
./scripts/manage-config.sh validate

# Edit configuration
./scripts/manage-config.sh edit
```

## 🚀 Quick Start

For a complete deployment with default settings:

```bash
# Navigate to the backend directory
cd code/TestDeployLambda/BE

# Run full stack deployment
./scripts/deploy-full-stack.sh
```

This will deploy everything with default settings:
- Environment: `dev`
- Project: `myapp`
- All components included

## 📖 Detailed Deployment Steps

### Step 1: Deploy RDS Database

```bash
./scripts/infrastructure/provision-rds.sh --environment dev --project-name myapp
```

**What this does:**
- Creates RDS PostgreSQL instance
- Configures security groups for Lambda access
- Sets up database with credentials from appsettings.json
- Creates deployment checkpoint for tracking

**Expected Output:**
- RDS instance identifier: `myapp-dev-db`
- Database endpoint saved to checkpoint file
- Database ready for connections

### Step 2: Deploy Lambda Function

```bash
# Provision Lambda infrastructure
./scripts/infrastructure/provision-lambda.sh --environment dev --project-name myapp

# Deploy application code
./scripts/deployment/deploy-lambda.sh --environment dev --project-name myapp
```

**What this does:**
- Creates IAM role for Lambda execution
- Provisions Lambda function with .NET 10 runtime
- Builds and packages .NET application
- Deploys code to Lambda
- Configures environment variables

**Expected Output:**
- Lambda function: `myapp-dev-api`
- Function ARN saved to checkpoint
- Application ready to receive requests

### Step 3: Run Database Migrations

```bash
./scripts/migration/run-migrations.sh --environment dev --project-name myapp
```

**What this does:**
- Triggers Lambda function to run Entity Framework migrations
- Creates all database tables and schema
- Applies any pending migrations

**Expected Output:**
- Database schema created
- Migration history table populated
- All tables ready for data

### Step 4: Trigger DbInitializer

```bash
./scripts/database/trigger-db-initializer.sh --function-name myapp-dev-api
```

**What this does:**
- Triggers Lambda function to run DbInitializer
- DbInitializer automatically seeds:
  - **Admin and Analyst roles**
  - **5 analytics types** (RISK, TREND, COMPARISON, OPPORTUNITY, EXECUTIVE)
  - **Default users** in both AWS Cognito and Database:
    - `admin@rag.com` → Admin role
    - `analyst@rag.com` → Analyst role
  - **User synchronization** between Cognito and Database

**Expected Output:**
- 2 roles created (Admin, Analyst)
- 5 analytics types created
- 2 default users created in both Cognito and Database
- Users properly linked with roles

### Step 5: Deploy API Gateway

```bash
./scripts/infrastructure/provision-api-gateway.sh --environment dev --project-name myapp
```

**What this does:**
- Creates REST API Gateway
- Configures Lambda integration
- Sets up CORS for frontend access
- Creates deployment stage

**Expected Output:**
- API Gateway URL available
- Swagger documentation accessible
- API ready for client requests

### Step 6: Run Tests

```bash
# Test Lambda-RDS connection
./scripts/tests/test-lambda-db-connection.sh

# Test API endpoints
./scripts/testing/test-api.sh

# Test user roles and authentication
./scripts/testing/test-user-roles.sh
```

**What this does:**
- Verifies Lambda can connect to RDS
- Tests API endpoints are responding
- Validates authentication and authorization
- Confirms role-based access control

## ⚙️ Configuration

### Environment Variables

The deployment uses these key environment variables:

```bash
# Deployment Configuration
ENVIRONMENT=dev                    # dev, staging, production
PROJECT_NAME=myapp                # Your project name
SKIP_TESTS=false                  # Skip tests during deployment
SKIP_SEEDING=false               # Skip database seeding

# AWS Configuration (from appsettings.json)
AWS__Region=ap-southeast-1
AWS__UserPoolId=your-user-pool-id
AWS__ClientId=your-client-id
```

### Database Configuration

Database settings are read from `appsettings.json`:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Port=5432;Database=RAGSystem;Username=postgres;Password=12345678"
  }
}
```

**Note**: The deployment scripts automatically replace `localhost` with the actual RDS endpoint.

### Custom Deployment Options

```bash
# Production deployment
./scripts/deploy-full-stack.sh --environment production --project-name myrag

# Development without tests
./scripts/deploy-full-stack.sh --skip-tests

# Deployment without seeding (for existing databases)
./scripts/deploy-full-stack.sh --skip-seeding
```

## 🧪 Testing

### Default User Accounts

After deployment, these accounts are available:

| Email             | Password        | Role    | Access Level                       |
| ----------------- | --------------- | ------- | ---------------------------------- |
| `admin@rag.com`   | `Admin@123!!`   | Admin   | Full access to all endpoints       |
| `analyst@rag.com` | `Analyst@123!!` | Analyst | Limited access, no admin endpoints |

### API Endpoints

The deployed API provides these key endpoints:

- **Swagger Documentation**: `{API_URL}/swagger`
- **Authentication**: `{API_URL}/api/auth/login`
- **User Registration**: `{API_URL}/api/auth/register`
- **Admin Panel**: `{API_URL}/api/admin/users` (Admin only)

### Testing Commands

```bash
# Test login with admin account
curl -X POST "{API_URL}/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@rag.com","password":"Admin@123!!"}'

# Test admin endpoint (requires admin token)
curl -H "Authorization: Bearer {ACCESS_TOKEN}" \
  "{API_URL}/api/admin/users"
```

## 🔍 Troubleshooting

### Common Issues

#### 1. Lambda Function Not Found
```
Error: Lambda function not found: myapp-dev-api
```
**Solution**: Deploy Lambda infrastructure first:
```bash
./scripts/infrastructure/provision-lambda.sh
```

#### 2. Database Connection Failed
```
Error: Could not connect to database
```
**Solutions**:
- Check RDS instance is running
- Verify security group allows Lambda access
- Confirm connection string is correct

#### 3. Roles Not Found Error
```
Error: Hệ thống chưa có Role 'Analyst'
```
**Solution**: Run database seeding:
```bash
./scripts/database/seed-roles-direct.sh
./scripts/database/seed-default-users.sh
```

#### 4. AWS Permissions Denied
```
Error: User is not authorized to perform: lambda:GetFunction
```
**Solution**: Ensure your AWS user has the required permissions listed in Prerequisites.

### Debugging Steps

1. **Check deployment logs**:
   ```bash
   ls -la logs/
   tail -f logs/deployment_*.log
   ```

2. **Verify AWS resources**:
   ```bash
   aws rds describe-db-instances --db-instance-identifier myapp-dev-db
   aws lambda get-function --function-name myapp-dev-api
   ```

3. **Test database connectivity**:
   ```bash
   psql "postgresql://postgres:password@endpoint:5432/RAGSystem"
   ```

4. **Check Lambda logs**:
   ```bash
   aws logs tail /aws/lambda/myapp-dev-api --follow
   ```

## 🧹 Cleanup

### Clean Temporary Files

```bash
# Clean temporary files only
./scripts/cleanup-deployment.sh

# Clean everything except AWS resources
./scripts/cleanup-deployment.sh --all

# Clean specific categories
./scripts/cleanup-deployment.sh --clean-logs --clean-temp
```

### Destroy AWS Resources

**⚠️ WARNING**: This will permanently delete all AWS resources!

```bash
# Destroy all AWS resources
./scripts/cleanup-deployment.sh --destroy-aws --environment dev --project-name myapp
```

This will delete:
- RDS database instance
- Lambda function
- API Gateway
- IAM roles

## 📁 File Structure

After deployment, your file structure will look like this:

```
code/TestDeployLambda/BE/
├── scripts/
│   ├── deploy-full-stack.sh          # Master deployment script
│   ├── cleanup-deployment.sh         # Cleanup script
│   ├── database/                     # Database seeding scripts
│   │   ├── seed-roles-direct.sh
│   │   └── seed-default-users.sh
│   ├── deployment/                   # Application deployment
│   ├── infrastructure/               # AWS infrastructure
│   ├── migration/                    # Database migrations
│   │   └── run-migrations.sh
│   ├── setup/                        # Setup and configuration scripts
│   │   └── setup-deployment.sh
│   ├── testing/                      # Test scripts
│   │   ├── test-api.sh
│   │   └── test-user-roles.sh
│   ├── tests/                        # Integration tests
│   ├── temp/                         # Temporary files (JSON, build artifacts)
│   └── utilities/                    # Shared utilities
├── deployment_checkpoints/           # Deployment state files
├── logs/                            # Deployment logs
└── RAG.APIs/                        # Application source code
```

## 🎯 Next Steps

After successful deployment:

1. **Configure Frontend**: Update frontend configuration to use the API Gateway URL
2. **Set up CI/CD**: Implement automated deployment pipeline
3. **Monitor**: Set up CloudWatch alarms and monitoring
4. **Security**: Review and harden security settings for production
5. **Backup**: Configure automated database backups
6. **SSL**: Set up custom domain with SSL certificate

## 📞 Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review deployment logs in the `logs/` directory
3. Verify AWS resource status in the AWS Console
4. Check application logs in CloudWatch

---

**Last Updated**: March 2026  
**Version**: 2.0  
**Deployment Architecture**: AWS Lambda + RDS + API Gateway