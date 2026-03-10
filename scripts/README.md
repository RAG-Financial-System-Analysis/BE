# RAG System Deployment Scripts

This directory contains all deployment and management scripts for the RAG System AWS deployment.

## 📁 Directory Structure

```
scripts/
├── deploy-full-stack.sh              # 🚀 Master deployment script (FIRST TIME)
├── deploy-update-only.sh             # 🔄 Code update script (SUBSEQUENT DEPLOYMENTS)
├── cleanup-deployment.sh             # 🧹 Cleanup and resource management
├── database/                         # 🗄️ Database management
│   ├── trigger-db-initializer.sh    #   ├── Trigger DbInitializer to seed all data
│   ├── seed-roles-direct.sh         #   ├── [LEGACY] Direct seed roles and analytics types
│   └── seed-default-users.sh        #   └── [LEGACY] Direct seed default admin/analyst users
├── deployment/                       # 📦 Application deployment
│   ├── deploy-lambda.sh             #   ├── Deploy Lambda function code
│   └── configure-environment.sh     #   └── Configure Lambda environment variables
├── infrastructure/                   # 🏗️ AWS infrastructure provisioning
│   ├── provision-rds.sh             #   ├── Deploy RDS PostgreSQL database
│   ├── provision-lambda.sh          #   ├── Provision Lambda function infrastructure
│   └── provision-api-gateway.sh     #   └── Deploy API Gateway
├── integration/                      # 🔗 Integration scripts
├── migration/                        # 🔄 Database migrations
│   └── run-migrations.sh            #   └── Run Entity Framework migrations
├── testing/                          # 🧪 Testing and validation scripts
│   ├── test-api.sh                  #   ├── Test API endpoints
│   ├── test-user-roles.sh           #   ├── Test authentication and roles
│   ├── test-lambda-db-connection.sh #   ├── Test Lambda-RDS connectivity
│   ├── test-credential-detection.sh #   ├── Test AWS credential detection
│   └── run-all-tests.sh             #   └── Run all test suites
├── setup/                           # ⚙️ Setup and configuration
│   └── setup-deployment.sh         #   └── Initial project setup
├── temp/                            # 📁 Temporary files (JSON, build artifacts)
└── utilities/                       # 🛠️ Shared utilities
    ├── logging.sh                   #   ├── Logging functions
    ├── error-handling.sh            #   ├── Error handling utilities
    ├── validate-aws-cli.sh          #   ├── AWS CLI validation
    └── parse-appsettings.sh         #   └── Configuration parsing
```

## 🚀 Quick Start

### Full Deployment (Recommended for First Time)

Deploy everything with one command:

```bash
./deploy-full-stack.sh
```

### Code Update Only (For Subsequent Deployments)

Update Lambda code without touching infrastructure or database:

```bash
./deploy-update-only.sh
```

This runs the complete deployment pipeline:
1. 🗄️ Deploy RDS Database
2. ⚡ Deploy Lambda Function
3. 🔄 Run Database Migrations (from Lambda to DB)
4. 🌱 Trigger DbInitializer (automatically seeds roles, analytics types, and users)
5. 🌐 Deploy API Gateway
6. 🧪 Run Tests

### Custom Deployment Options

```bash
# Production deployment
./deploy-full-stack.sh --environment production --project-name myrag

# Development without tests
./deploy-full-stack.sh --skip-tests

# Skip database seeding (for existing databases)
./deploy-full-stack.sh --skip-seeding
```

## 📖 Individual Script Usage

### Infrastructure Scripts

```bash
# Deploy RDS database
./infrastructure/provision-rds.sh --environment dev

# Deploy Lambda infrastructure
./infrastructure/provision-lambda.sh --environment dev

# Deploy API Gateway
./infrastructure/provision-api-gateway.sh --environment dev
```

### Application Deployment

```bash
# Deploy Lambda function code
./deployment/deploy-lambda.sh --environment dev

# Configure Lambda environment variables
./deployment/configure-environment.sh --function-name myapp-dev-api
```

### Database Management

```bash
# Run Entity Framework migrations
./migration/run-migrations.sh --environment dev

# Trigger DbInitializer to seed all data (roles, analytics types, users)
./database/trigger-db-initializer.sh --function-name myapp-dev-api
```

### Testing

```bash
# Test Lambda-RDS connection
./tests/test-lambda-db-connection.sh

# Test API endpoints
./tests/test-api.sh

# Test user authentication and roles
./tests/test-user-roles.sh

# Test AWS credential detection
./tests/test-credential-detection.sh

# Run all tests
./tests/run-all-tests.sh
```

## 🧹 Cleanup

### Clean Temporary Files

```bash
# Clean temporary files only (default)
./cleanup-deployment.sh

# Clean everything except AWS resources
./cleanup-deployment.sh --all

# Clean specific categories
./cleanup-deployment.sh --clean-logs --clean-temp --clean-checkpoints
```

### Destroy AWS Resources

**⚠️ WARNING**: This permanently deletes all AWS resources!

```bash
./cleanup-deployment.sh --destroy-aws --environment dev
```

## ⚙️ Configuration

### Environment Variables

Scripts use these environment variables:

```bash
ENVIRONMENT=dev                    # Deployment environment
PROJECT_NAME=myapp                # Project identifier
SKIP_TESTS=false                  # Skip tests during deployment
SKIP_SEEDING=false               # Skip database seeding
```

### AWS Configuration

Ensure AWS CLI is configured:

```bash
aws configure
# or
export AWS_ACCESS_KEY_ID=your-key
export AWS_SECRET_ACCESS_KEY=your-secret
export AWS_DEFAULT_REGION=ap-southeast-1
```

**Note**: All other configuration is automatically read from `RAG.APIs/appsettings.json`. No additional configuration files are needed.

## 🔍 Deployment Order

**IMPORTANT**: Scripts must be run in this specific order for first-time deployment:

1. **Infrastructure**: `provision-rds.sh` → `provision-lambda.sh`
2. **Application**: `deploy-lambda.sh`
3. **Database**: `run-migrations.sh` (from Lambda to DB)
4. **Seeding**: `trigger-db-initializer.sh` (DbInitializer seeds roles, analytics types, users automatically)
5. **Gateway**: `provision-api-gateway.sh`
6. **Testing**: `test-*` scripts

The `deploy-full-stack.sh` script handles this order automatically and is the recommended deployment method.

## 📁 File Management

### Temporary Files

Scripts create temporary files in:
- `temp/` directory (auto-created)
- Root-level JSON files (auto-cleaned)

### Logs

Deployment logs are stored in:
- `../logs/` - Deployment logs
- `../deployment_logs/` - Detailed deployment logs
- `../deployment_checkpoints/` - State tracking files

### Cleanup

Use `cleanup-deployment.sh` to manage temporary files and logs.

## 🛠️ Utilities

### Shared Functions

All scripts use shared utilities from `utilities/`:

- **logging.sh**: Colored logging functions (`log_info`, `log_success`, `log_error`)
- **error-handling.sh**: Error handling and cleanup functions
- **validate-aws-cli.sh**: AWS CLI validation and setup
- **parse-appsettings.sh**: Configuration file parsing

### Error Handling

All scripts include:
- Automatic error detection (`set -euo pipefail`)
- Cleanup on exit
- Detailed error messages with remediation steps
- Rollback capabilities where applicable

## 🔧 Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure scripts are executable
   ```bash
   chmod +x scripts/*.sh scripts/*/*.sh
   ```

2. **AWS Credentials**: The scripts support flexible credential detection
   
   **Automatic Detection**: Scripts automatically detect credentials from:
   - AWS CLI configuration (`aws configure`)
   - Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
   - AWS profiles (`AWS_PROFILE`)
   - IAM roles (EC2/Lambda instance profiles)
   - AWS credentials files (`~/.aws/credentials`, `~/.aws/config`)
   
   **Verification**: Test any credential method with:
   ```bash
   aws sts get-caller-identity
   ```
   
   **No Configuration Required**: If you already have AWS credentials set up via any method, you don't need to run `aws configure`.

3. **Dependencies**: Check prerequisites
   ```bash
   # Required: AWS CLI, .NET SDK, PostgreSQL client
   aws --version
   dotnet --version
   psql --version
   ```

### Debug Mode

Enable verbose logging:
```bash
export DEBUG=true
./deploy-full-stack.sh
```

### Log Files

Check deployment logs:
```bash
ls -la ../logs/
tail -f ../logs/deployment_*.log
```

## 📋 Prerequisites

Before running any scripts:

- ✅ AWS CLI v2.0+ installed and configured
- ✅ .NET SDK 8.0+ installed
- ✅ PostgreSQL client (psql) installed
- ✅ Bash shell available
- ✅ AWS permissions for RDS, Lambda, API Gateway, IAM

## 🎯 Default Outputs

After successful deployment:

- **RDS Database**: `{project}-{env}-db` (e.g., `myapp-dev-db`)
- **Lambda Function**: `{project}-{env}-api` (e.g., `myapp-dev-api`)
- **API Gateway**: REST API with Swagger documentation
- **Default Users**:
  - Admin: `admin@rag.com` / `Admin@123!!`
  - Analyst: `analyst@rag.com` / `Analyst@123!!`

## 📞 Support

For issues:
1. Check script logs in `../logs/`
2. Verify AWS resource status in AWS Console
3. Run individual scripts with `--help` for usage information
4. Check CloudWatch logs for Lambda function issues

---

**Last Updated**: March 2026  
**Scripts Version**: 2.0