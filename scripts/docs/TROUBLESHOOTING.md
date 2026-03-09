# Hướng dẫn khắc phục sự cố - AWS Deployment Automation

Tài liệu này cung cấp hướng dẫn chi tiết để khắc phục các sự cố thường gặp khi sử dụng hệ thống AWS Deployment Automation.

## 📋 Mục lục

1. [AWS Permissions Issues](#aws-permissions-issues)
2. [RDS Database Problems](#rds-database-problems)
3. [Lambda Deployment Issues](#lambda-deployment-issues)
4. [Migration Failures](#migration-failures)
5. [Cognito Integration Problems](#cognito-integration-problems)
6. [Network và VPC Issues](#network-và-vpc-issues)
7. [Cost và Billing Issues](#cost-và-billing-issues)
8. [Recovery Procedures](#recovery-procedures)

## 🔐 AWS Permissions Issues

### Lỗi: "Unable to locate credentials"

**Triệu chứng:**
```
Unable to locate credentials. You can configure credentials by running "aws configure".
```

**Nguyên nhân:**
- AWS CLI chưa được cấu hình
- Credentials không hợp lệ hoặc đã hết hạn
- Environment variables không được set

**Giải pháp:**

#### 1. Cấu hình AWS CLI cơ bản
```bash
aws configure
# Nhập:
# AWS Access Key ID: YOUR_ACCESS_KEY
# AWS Secret Access Key: YOUR_SECRET_KEY
# Default region name: ap-southeast-1
# Default output format: json
```

#### 2. Sử dụng Environment Variables
```bash
export AWS_ACCESS_KEY_ID="your_access_key"
export AWS_SECRET_ACCESS_KEY="your_secret_key"
export AWS_DEFAULT_REGION="ap-southeast-1"
```

#### 3. Sử dụng AWS Profile
```bash
aws configure --profile production
export AWS_PROFILE=production
```

#### 4. Kiểm tra credentials
```bash
aws sts get-caller-identity
```

### Lỗi: "Access Denied" hoặc "UnauthorizedOperation"

**Triệu chứng:**
```
An error occurred (UnauthorizedOperation) when calling the CreateVpc operation: 
You are not authorized to perform this operation.
```

**Nguyên nhân:**
- IAM user/role thiếu permissions cần thiết
- Policy restrictions
- Resource-based policies

**Giải pháp:**

#### 1. Kiểm tra permissions hiện tại
```bash
./scripts/utilities/validate-aws-cli.sh permissions
```

#### 2. Attach required managed policies
```bash
# Qua AWS Console: IAM → Users → [Your User] → Permissions
# Hoặc qua CLI (cần admin access):
aws iam attach-user-policy \
  --user-name YOUR_USERNAME \
  --policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess

aws iam attach-user-policy \
  --user-name YOUR_USERNAME \
  --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess

aws iam attach-user-policy \
  --user-name YOUR_USERNAME \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

aws iam attach-user-policy \
  --user-name YOUR_USERNAME \
  --policy-arn arn:aws:iam::aws:policy/IAMFullAccess
```

#### 3. Custom policy cho deployment
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:*",
        "lambda:*",
        "ec2:*",
        "iam:*",
        "cognito-idp:*",
        "logs:*",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

### Lỗi: "Region not supported"

**Triệu chứng:**
```
The specified region is not supported for this operation.
```

**Giải pháp:**
```bash
# Kiểm tra region hiện tại
aws configure get region

# Set region phù hợp
aws configure set region ap-southeast-1

# Hoặc sử dụng environment variable
export AWS_DEFAULT_REGION=ap-southeast-1
```

## 🗄️ RDS Database Problems

### Lỗi: RDS Instance Creation Failed

**Triệu chứng:**
```
An error occurred (DBSubnetGroupNotFoundFault) when calling the CreateDBInstance operation: 
DBSubnetGroup doesn't exist
```

**Nguyên nhân:**
- VPC hoặc subnets chưa được tạo
- DB subnet group không tồn tại
- Security groups chưa được cấu hình

**Giải pháp:**

#### 1. Kiểm tra VPC infrastructure
```bash
./scripts/utilities/check-infrastructure.sh --environment production --project-name myapp
```

#### 2. Tạo lại infrastructure từ đầu
```bash
./scripts/deploy.sh --mode cleanup --environment production --project-name myapp
./scripts/deploy.sh --mode initial --environment production --project-name myapp
```

#### 3. Tạo RDS riêng biệt
```bash
./scripts/infrastructure/provision-rds.sh \
  --environment production \
  --project-name myapp \
  --force-recreate
```

### Lỗi: Database Connection Timeout

**Triệu chứng:**
```
could not connect to server: Connection timed out
```

**Nguyên nhân:**
- Security groups không cho phép kết nối
- RDS instance không trong VPC đúng
- Network ACLs blocking traffic

**Giải pháp:**

#### 1. Kiểm tra RDS status
```bash
aws rds describe-db-instances --db-instance-identifier myapp-production-db
```

#### 2. Kiểm tra security groups
```bash
# Lấy security group ID của RDS
RDS_SG=$(aws rds describe-db-instances \
  --db-instance-identifier myapp-production-db \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)

# Kiểm tra inbound rules
aws ec2 describe-security-groups --group-ids $RDS_SG
```

#### 3. Test connection từ Lambda
```bash
# Deploy test Lambda function
./scripts/migration/run-migrations.sh --dry-run --verbose
```

### Lỗi: "Database does not exist"

**Triệu chứng:**
```
FATAL: database "appdb" does not exist
```

**Giải pháp:**

#### 1. Tạo database manually
```bash
# Connect to RDS instance
psql -h myapp-production-db.xyz.ap-southeast-1.rds.amazonaws.com \
     -U dbadmin \
     -d postgres

# Tạo database
CREATE DATABASE appdb;
\q
```

#### 2. Chạy lại migrations
```bash
./scripts/migration/run-migrations.sh --environment production
```

## 🚀 Lambda Deployment Issues

### Lỗi: Lambda Function Creation Failed

**Triệu chứng:**
```
An error occurred (InvalidParameterValueException) when calling the CreateFunction operation: 
The role defined for the function cannot be assumed by Lambda.
```

**Nguyên nhân:**
- IAM role chưa được tạo hoặc không đúng
- Trust policy không cho phép Lambda assume role
- Role chưa propagate

**Giải pháp:**

#### 1. Kiểm tra IAM role
```bash
aws iam get-role --role-name myapp-production-lambda-role
```

#### 2. Tạo lại Lambda role
```bash
./scripts/infrastructure/configure-iam.sh \
  --environment production \
  --project-name myapp
```

#### 3. Wait và retry
```bash
# Wait for role propagation
sleep 30
./scripts/infrastructure/provision-lambda.sh \
  --environment production \
  --project-name myapp
```

### Lỗi: Lambda Deployment Package Too Large

**Triệu chứng:**
```
An error occurred (RequestEntityTooLargeException) when calling the UpdateFunctionCode operation: 
Request must be smaller than 69905067 bytes for the UpdateFunctionCode operation
```

**Giải pháp:**

#### 1. Optimize deployment package
```bash
# Remove unnecessary files
find . -name "*.pdb" -delete
find . -name "*.xml" -delete

# Use trimmed publish
dotnet publish -c Release --self-contained false -o publish/
```

#### 2. Use S3 for large packages
```bash
# Upload to S3
aws s3 cp deployment.zip s3://my-deployment-bucket/

# Deploy from S3
aws lambda update-function-code \
  --function-name myapp-production-api \
  --s3-bucket my-deployment-bucket \
  --s3-key deployment.zip
```

### Lỗi: Lambda Cold Start Issues

**Triệu chứng:**
- Lambda functions timeout on first request
- Slow response times

**Giải pháp:**

#### 1. Increase timeout
```bash
aws lambda update-function-configuration \
  --function-name myapp-production-api \
  --timeout 60
```

#### 2. Increase memory
```bash
aws lambda update-function-configuration \
  --function-name myapp-production-api \
  --memory-size 1024
```

#### 3. Implement warming strategy
```bash
# Create CloudWatch event to warm Lambda
aws events put-rule \
  --name lambda-warmer \
  --schedule-expression "rate(5 minutes)"
```

## 🔄 Migration Failures

### Lỗi: Entity Framework Migration Failed

**Triệu chứng:**
```
System.InvalidOperationException: No database provider has been configured for this DbContext.
```

**Nguyên nhân:**
- Connection string không đúng
- Database provider không được cấu hình
- Environment variables không được set

**Giải pháp:**

#### 1. Kiểm tra connection string
```bash
# Test connection
./scripts/migration/run-migrations.sh --dry-run --verbose
```

#### 2. Update connection string
```bash
# Get RDS endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier myapp-production-db \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

# Update Lambda environment variables
./scripts/deployment/update-lambda-environment.sh \
  --function-name myapp-production-api \
  --connection-string "Host=$RDS_ENDPOINT;Database=appdb;Username=dbadmin;Password=YOUR_PASSWORD"
```

#### 3. Manual migration
```bash
# Connect to database và run migrations manually
dotnet ef database update --connection "Host=...;Database=...;Username=...;Password=..."
```

### Lỗi: Migration Rollback Failed

**Triệu chứng:**
```
The migration '20241208143022_InitialCreate' has already been applied to the database.
```

**Giải pháp:**

#### 1. Check migration history
```bash
# Connect to database
psql -h $RDS_ENDPOINT -U dbadmin -d appdb

# Check migrations table
SELECT * FROM "__EFMigrationsHistory";
\q
```

#### 2. Manual rollback
```bash
./scripts/migration/rollback-migrations.sh \
  --target-migration 20241208143022_InitialCreate \
  --environment production
```

#### 3. Reset migrations (CAUTION: Data loss)
```bash
# Drop and recreate database
./scripts/migration/run-migrations.sh --reset --environment production
```

## 🔐 Cognito Integration Problems

### Lỗi: Invalid User Pool ID

**Triệu chứng:**
```
An error occurred (ResourceNotFoundException) when calling the DescribeUserPool operation: 
User pool ap-southeast-1_abcdef123 does not exist.
```

**Giải pháp:**

#### 1. Validate Cognito configuration
```bash
./scripts/utilities/validate-cognito.sh validate --config appsettings.json
```

#### 2. Check User Pool exists
```bash
aws cognito-idp list-user-pools --max-results 10
```

#### 3. Update configuration
```json
{
  "AWS": {
    "Cognito": {
      "UserPoolId": "CORRECT_USER_POOL_ID",
      "ClientId": "CORRECT_CLIENT_ID"
    }
  }
}
```

### Lỗi: JWT Token Validation Failed

**Triệu chứng:**
```
System.SecurityTokens.SecurityTokenValidationException: IDX10205: Issuer validation failed.
```

**Giải pháp:**

#### 1. Check JWT configuration
```bash
./scripts/utilities/validate-cognito.sh check \
  --user-pool-id ap-southeast-1_abcdef123 \
  --client-id 1234567890abcdefghijklmnop
```

#### 2. Update JWT issuer
```json
{
  "JWT": {
    "Issuer": "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_abcdef123",
    "Audience": "1234567890abcdefghijklmnop"
  }
}
```

#### 3. Test JWT endpoint
```bash
curl -s "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_abcdef123/.well-known/jwks.json"
```

## 🌐 Network và VPC Issues

### Lỗi: VPC Creation Failed

**Triệu chứng:**
```
An error occurred (VpcLimitExceeded) when calling the CreateVpc operation: 
The maximum number of VPCs has been reached.
```

**Giải pháp:**

#### 1. Check VPC limits
```bash
aws ec2 describe-vpcs --query 'Vpcs[*].{VpcId:VpcId,State:State}'
```

#### 2. Delete unused VPCs
```bash
# List và delete unused VPCs
aws ec2 describe-vpcs --filters "Name=state,Values=available" \
  --query 'Vpcs[?IsDefault==`false`].VpcId' --output text

# Delete specific VPC (CAUTION)
aws ec2 delete-vpc --vpc-id vpc-12345678
```

#### 3. Use existing VPC
```bash
./scripts/infrastructure/provision-rds.sh \
  --vpc-id vpc-existing123 \
  --subnet-ids subnet-123,subnet-456
```

### Lỗi: Lambda VPC Configuration Issues

**Triệu chứng:**
```
Lambda function could not connect to RDS instance
```

**Giải pháp:**

#### 1. Check Lambda VPC configuration
```bash
aws lambda get-function-configuration \
  --function-name myapp-production-api \
  --query 'VpcConfig'
```

#### 2. Update Lambda VPC settings
```bash
aws lambda update-function-configuration \
  --function-name myapp-production-api \
  --vpc-config SubnetIds=subnet-123,subnet-456,SecurityGroupIds=sg-123
```

#### 3. Check NAT Gateway
```bash
# Lambda cần NAT Gateway để access internet
aws ec2 describe-nat-gateways
```

## 💰 Cost và Billing Issues

### Lỗi: Unexpected High Costs

**Triệu chứng:**
- AWS bill cao hơn expected
- Cost alerts được trigger

**Giải pháp:**

#### 1. Analyze costs
```bash
./scripts/utilities/cost-optimization.sh report \
  --environment production \
  --region ap-southeast-1 \
  --output cost-analysis.md
```

#### 2. Check running resources
```bash
# Check RDS instances
aws rds describe-db-instances --query 'DBInstances[*].{ID:DBInstanceIdentifier,Status:DBInstanceStatus,Class:DBInstanceClass}'

# Check Lambda invocations
aws logs filter-log-events \
  --log-group-name /aws/lambda/myapp-production-api \
  --start-time $(date -d '1 day ago' +%s)000
```

#### 3. Optimize resources
```bash
# Stop RDS for development
aws rds stop-db-instance --db-instance-identifier myapp-dev-db

# Reduce Lambda memory
aws lambda update-function-configuration \
  --function-name myapp-dev-api \
  --memory-size 256
```

### Lỗi: Free Tier Exceeded

**Triệu chứng:**
```
You have exceeded your free tier usage for RDS
```

**Giải pháp:**

#### 1. Check free tier usage
```bash
./scripts/utilities/cost-optimization.sh validate \
  --resource rds \
  --config "instance_class=db.t3.micro,storage_size=20"
```

#### 2. Optimize for free tier
```bash
# Use smallest instance
./scripts/infrastructure/provision-rds.sh \
  --instance-class db.t3.micro \
  --storage-size 20 \
  --environment development
```

## 🔧 Recovery Procedures

### Complete System Recovery

#### 1. Backup Current State
```bash
# Export current configuration
./scripts/utilities/check-infrastructure.sh \
  --environment production \
  --export-config backup-config.json
```

#### 2. Clean Deployment
```bash
# Complete cleanup
./scripts/deploy.sh --mode cleanup --environment production --force

# Fresh deployment
./scripts/deploy.sh --mode initial --environment production
```

#### 3. Restore Data
```bash
# Restore database from backup
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier myapp-production-db-restored \
  --db-snapshot-identifier myapp-production-db-snapshot-20241208
```

### Partial Recovery

#### 1. Infrastructure Only
```bash
# Recreate infrastructure
./scripts/infrastructure/provision-rds.sh --force-recreate
./scripts/infrastructure/provision-lambda.sh --force-recreate
```

#### 2. Application Only
```bash
# Redeploy application
./scripts/deployment/deploy-lambda.sh --force-update
./scripts/migration/run-migrations.sh
```

### Rollback to Previous Version

#### 1. Lambda Rollback
```bash
# List versions
aws lambda list-versions-by-function --function-name myapp-production-api

# Rollback to previous version
aws lambda update-alias \
  --function-name myapp-production-api \
  --name LIVE \
  --function-version 2
```

#### 2. Database Rollback
```bash
./scripts/migration/rollback-migrations.sh \
  --target-migration PreviousMigrationName \
  --environment production
```

## 🔍 Debug Tools và Commands

### Logging và Monitoring
```bash
# Enable debug mode
export LOG_LEVEL=DEBUG

# View deployment logs
tail -f ./deployment_logs/debug.log

# View AWS CloudTrail events
aws logs filter-log-events \
  --log-group-name CloudTrail/AWSDeploymentAutomation \
  --start-time $(date -d '1 hour ago' +%s)000
```

### Network Debugging
```bash
# Test VPC connectivity
aws ec2 describe-vpc-peering-connections
aws ec2 describe-route-tables
aws ec2 describe-security-groups

# Test Lambda network access
aws lambda invoke \
  --function-name myapp-production-api \
  --payload '{"test": "network"}' \
  response.json
```

### Database Debugging
```bash
# Test database connection
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "SELECT version();"

# Check database performance
aws rds describe-db-instances \
  --db-instance-identifier myapp-production-db \
  --query 'DBInstances[0].{Status:DBInstanceStatus,MultiAZ:MultiAZ,StorageType:StorageType}'
```

## 📞 Escalation Procedures

### Level 1: Self-Service
1. Check this troubleshooting guide
2. Run diagnostic scripts
3. Check AWS service health dashboard

### Level 2: Community Support
1. Search GitHub issues
2. Post in GitHub discussions
3. Check AWS forums

### Level 3: Professional Support
1. AWS Support (if you have support plan)
2. Contact system maintainers
3. Commercial support options

## 📚 Additional Resources

### AWS Documentation
- [AWS Troubleshooting Guide](https://docs.aws.amazon.com/general/latest/gr/aws_troubleshooting.html)
- [RDS Troubleshooting](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Troubleshooting.html)
- [Lambda Troubleshooting](https://docs.aws.amazon.com/lambda/latest/dg/troubleshooting.html)

### Tools
- [AWS CLI Troubleshooting](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-troubleshooting.html)
- [AWS CloudFormation Troubleshooting](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/troubleshooting.html)

---

**Lưu ý**: Nếu bạn gặp sự cố không có trong tài liệu này, hãy tạo GitHub issue với thông tin chi tiết về lỗi, logs, và môi trường để được hỗ trợ.