# RAG System Backend - AWS Deployment

Complete .NET 10 backend system for RAG (Retrieval-Augmented Generation) deployed on AWS serverless architecture.

## 🏗️ Architecture

- **AWS Lambda**: .NET 10 serverless API hosting
- **RDS PostgreSQL**: Managed database service
- **API Gateway**: REST API endpoint management
- **AWS Cognito**: User authentication and authorization
- **CloudWatch**: Logging and monitoring

## 🚀 Quick Start

### One-Command Deployment

```bash
# Deploy everything with default settings (FIRST TIME DEPLOYMENT)
./scripts/deploy-full-stack.sh
```

This deploys the complete stack in the correct order:
1. RDS PostgreSQL database
2. Lambda .NET 10 function
3. Database migrations (from Lambda to DB)
4. Database seeding via DbInitializer (Roles → Users → Analytics Types)
5. API Gateway with Swagger documentation
6. Tests and validation

### Code Update Only

```bash
# Update Lambda code only (SUBSEQUENT DEPLOYMENTS)
./scripts/deploy-update-only.sh
```

This updates only the Lambda function code without:
- ❌ Creating new infrastructure
- ❌ Running database migrations
- ❌ Seeding database data

### Custom Deployment

```bash
# Production deployment (first time)
./scripts/deploy-full-stack.sh --environment production --project-name myrag

# Development without tests
./scripts/deploy-full-stack.sh --skip-tests

# Code update for production
./scripts/deploy-update-only.sh --environment production --project-name myrag
```

## 📋 Prerequisites

- **AWS CLI** v2.0+ with flexible credential configuration (environment variables, profiles, IAM roles, or `aws configure`)
- **.NET SDK** 8.0+ (for building .NET 10 applications)
- **PostgreSQL Client** (psql) for database operations
- **Bash Shell** (Git Bash on Windows)

**AWS Credentials**: The scripts automatically detect credentials from multiple sources - no need to run `aws configure` if you already have credentials via environment variables, profiles, or IAM roles.

## 📁 Project Structure

```
RAG-System-Backend/
├── 📂 RAG.APIs/                     # Main API project (.NET 10)
├── 📂 RAG.Application/              # Application layer
├── 📂 RAG.Domain/                   # Domain entities and DTOs
├── 📂 RAG.Infrastructure/           # Data access and external services
├── 📂 scripts/                     # 🚀 Deployment and management scripts
│   ├── deploy-full-stack.sh        #   └── Master deployment script
│   ├── cleanup-deployment.sh       #   └── Cleanup and resource management
│   ├── database/                   #   └── Database seeding scripts
│   ├── deployment/                 #   └── Application deployment
│   ├── infrastructure/             #   └── AWS infrastructure provisioning
│   ├── migration/                  #   └── Database migrations
│   ├── setup/                      #   └── Setup and configuration scripts
│   ├── testing/                    #   └── Testing and validation scripts
│   ├── temp/                       #   └── Temporary files (JSON, build artifacts)
│   └── utilities/                  #   └── Shared utilities
├── 📂 deployment_checkpoints/       # Deployment state tracking
├── 📂 logs/                        # Deployment and error logs
├── 📄 DEPLOYMENT_GUIDE.md  # 📖 Complete deployment guide
└── 📄 README.md              # This file
```

## 🔧 Configuration

### Deployment Configuration

All deployment parameters are managed through the `deployment-config.env` file. This provides centralized configuration management and makes it easy to maintain different settings for different environments.

#### Configuration File Structure

The configuration file includes:

```bash
# Basic deployment settings
ENVIRONMENT=dev
PROJECT_NAME=myapp
AWS_DEFAULT_REGION=ap-southeast-1

# Lambda configuration
LAMBDA_RUNTIME=dotnet10
LAMBDA_MEMORY_SIZE=512
LAMBDA_TIMEOUT=30

# RDS configuration
RDS_INSTANCE_CLASS=db.t3.micro
RDS_ALLOCATED_STORAGE=20
RDS_MULTI_AZ=false

# Deployment options
SKIP_TESTS=false
SKIP_SEEDING=false
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

### Database Configuration

Configure your database settings in `RAG.APIs/appsettings.json`:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Port=5432;Database=RAGSystem;Username=postgres;Password=*****"
  },
  "AWS": {
    "Region": "ap-southeast-1",
    "UserPoolId": "your-user-pool-id",
    "ClientId": "your-client-id"
  }
}
```

**Note**: The deployment scripts automatically read database configuration from `appsettings.json` and replace `localhost` with the actual RDS endpoint.

### Environment Variables

Key environment variables for deployment:

```bash
ENVIRONMENT=dev                    # dev, staging, production
PROJECT_NAME=myapp                # Your project identifier
SKIP_TESTS=false                  # Skip tests during deployment
SKIP_SEEDING=false               # Skip database seeding
```

## 🎯 Default Users

After deployment, these accounts are automatically created:

| Email             | Password | Role    | Access Level       |
| ----------------- | -------- | ------- | ------------------ |
| `admin@rag.com`   | ``       | Admin   | Full system access |
| `analyst@rag.com` | ``       | Analyst | Limited access     |

## 🌐 API Endpoints

The deployed system provides:

- **Swagger Documentation**: `{API_URL}/swagger`
- **Authentication**: `{API_URL}/api/auth/login`
- **User Management**: `{API_URL}/api/admin/users` (Admin only)
- **Analytics**: `{API_URL}/api/analytics/*`
- **Chat**: `{API_URL}/api/chat/*`
- **Companies**: `{API_URL}/api/companies/*`

## 🧪 Testing

### Quick API Test

```bash
# Test API endpoints
./scripts/tests/test-api.sh

# Test user authentication and roles
./scripts/tests/test-user-roles.sh

# Test Lambda-RDS connectivity
./scripts/tests/test-lambda-db-connection.sh

# Test AWS credential detection
./scripts/tests/test-credential-detection.sh
```

### Manual Testing

```bash
# Login with admin account
curl -X POST "{API_URL}/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@rag.com","password":""}'

# Access admin endpoint with token
curl -H "Authorization: Bearer {ACCESS_TOKEN}" \
  "{API_URL}/api/admin/users"
```

## 🔍 Monitoring and Debugging

### View Deployment Logs

```bash
# List recent logs
ls -la logs/

# Follow deployment logs
tail -f logs/deployment_*.log

# View Lambda logs (requires AWS CLI)
aws logs tail /aws/lambda/myapp-dev-api --follow
```

### Check AWS Resources

```bash
# Check RDS status
aws rds describe-db-instances --db-instance-identifier myapp-dev-db

# Check Lambda function
aws lambda get-function --function-name myapp-dev-api

# Check API Gateway
aws apigateway get-rest-apis
```

## 🧹 Cleanup

### Clean Temporary Files

```bash
# Clean temporary files only
./scripts/cleanup-deployment.sh

# Clean everything except AWS resources
./scripts/cleanup-deployment.sh --all
```

### Destroy AWS Resources

**⚠️ WARNING**: This permanently deletes all AWS resources!

```bash
./scripts/cleanup-deployment.sh --destroy-aws --environment dev
```

## 🔧 Development

### Local Development

```bash
# Run locally with development settings
cd RAG.APIs
dotnet run --environment Development
```

### Database Migrations

```bash
# Add new migration
dotnet ef migrations add MigrationName -p RAG.Infrastructure -s RAG.APIs

# Update database
dotnet ef database update -p RAG.Infrastructure -s RAG.APIs
```

### Building for Lambda

```bash
# Build for Lambda deployment
cd RAG.APIs
dotnet publish -c Release -r linux-x64 --self-contained false
```

## 📖 Documentation

- **[Complete Deployment Guide](DEPLOYMENT_GUIDE.md)** - Detailed deployment instructions
- **[Scripts Documentation](scripts/README.md)** - All deployment scripts explained
- **[API Documentation](RAG.APIs/README.md)** - API endpoints and usage

## 🔒 Security

### Production Considerations

- **AWS Secrets Manager**: Store sensitive configuration
- **VPC**: Deploy Lambda in private VPC for enhanced security
- **SSL/TLS**: Use custom domain with SSL certificate
- **IAM**: Follow principle of least privilege
- **Monitoring**: Set up CloudWatch alarms

### Authentication Flow

1. User registers/logs in via AWS Cognito
2. Cognito returns JWT tokens
3. API validates JWT tokens for protected endpoints
4. Role-based access control enforces permissions

## 🚀 Deployment Environments

### Development
```bash
./scripts/deploy-full-stack.sh --environment dev
```
- Uses development configuration
- Includes test data seeding
- Enables detailed logging

### Production
```bash
./scripts/deploy-full-stack.sh --environment production --project-name myrag
```
- Uses production configuration
- Optimized for performance
- Enhanced security settings

## 📊 Features

- **User Authentication**: AWS Cognito integration
- **Role-Based Access**: Admin and Analyst roles
- **Database Management**: Entity Framework with PostgreSQL
- **API Documentation**: Swagger/OpenAPI integration
- **Logging**: Structured logging with CloudWatch
- **Error Handling**: Comprehensive error handling and validation
- **Testing**: Automated testing suite
- **Monitoring**: Health checks and metrics

## 🔄 CI/CD Integration

The deployment scripts are designed to integrate with CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Deploy to AWS
  run: |
    ./scripts/deploy-full-stack.sh \
      --environment ${{ github.ref_name }} \
      --project-name myrag \
      --skip-tests
```

## 📞 Support

### Troubleshooting

1. **Check deployment logs**: `logs/deployment_*.log`
2. **Verify AWS resources**: Use AWS Console
3. **Test connectivity**: Run test scripts
4. **Check Lambda logs**: CloudWatch logs

### Common Issues

- **Permission Denied**: Ensure AWS CLI has proper permissions
- **Database Connection**: Verify RDS security groups
- **Lambda Timeout**: Check function timeout settings
- **API Gateway**: Verify Lambda integration

## 🎯 Next Steps

After successful deployment:

1. **Configure Frontend**: Update frontend to use API Gateway URL
2. **Set up Monitoring**: Configure CloudWatch alarms
3. **Implement CI/CD**: Automate deployments
4. **Security Hardening**: Review and enhance security settings
5. **Performance Optimization**: Monitor and optimize performance

---

**Version**: 2.0  
**Last Updated**: March 2026  
**Architecture**: AWS Serverless (.NET 10 + Lambda + RDS + API Gateway)  
**Deployment**: Fully Automated