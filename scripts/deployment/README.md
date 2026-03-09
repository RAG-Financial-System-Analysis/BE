# Scripts Triển Khai Lambda

Thư mục này chứa các scripts để triển khai ứng dụng .NET 10 lên AWS Lambda và quản lý cấu hình của chúng.

## Tổng Quan Scripts

### 1. deploy-lambda.sh
**Mục đích**: Triển khai ứng dụng .NET 10 lên AWS Lambda với packaging và dependencies phù hợp.

**Tính năng chính**:
- Build ứng dụng .NET cho Lambda runtime (linux-x64)
- Tạo deployment packages với tất cả dependencies
- Hỗ trợ cả triển khai ban đầu và cập nhật chỉ code
- Xử lý packages lớn qua S3 upload
- Cấu hình runtime settings và resource allocation phù hợp

**Ví dụ sử dụng**:
```bash
# Triển khai ban đầu
./deploy-lambda.sh --environment production --project-name webapp

# Cập nhật chỉ code (nhanh hơn cho development)
./deploy-lambda.sh --update-mode --function-name webapp-prod-api

# Cấu hình tùy chỉnh
./deploy-lambda.sh --memory 1024 --timeout 60 --aws-profile prod
```

### 2. configure-environment.sh
**Mục đích**: Chuyển đổi appsettings.json thành Lambda environment variables với flattening nested keys.

**Tính năng chính**:
- Flatten nested JSON configuration sử dụng double underscores (__)
- Merge base và environment-specific configuration files
- Validate configuration và cung cấp error reporting
- Hỗ trợ nhiều output formats (Lambda, shell env, JSON)
- Xử lý sensitive values một cách an toàn

**Ví dụ Configuration Flattening**:
```json
// Input: appsettings.json
{
  "ConnectionStrings": {
    "DefaultConnection": "..."
  },
  "AWS": {
    "Region": "us-east-1",
    "UserPoolId": "..."
  }
}

// Output: Environment Variables
ConnectionStrings__DefaultConnection=...
AWS__Region=us-east-1
AWS__UserPoolId=...
```

**Ví dụ sử dụng**:
```bash
# Convert và apply vào Lambda function
./configure-environment.sh --function-name webapp-prod-api

# Dry run để xem converted variables
./configure-environment.sh --dry-run --output-format env

# Output dưới dạng JSON để xử lý thêm
./configure-environment.sh --output-format json > lambda-env-vars.json
```

### 3. update-lambda-environment.sh
**Mục đích**: Cập nhật Lambda environment variables với xử lý an toàn các sensitive values.

**Tính năng chính**:
- Nhiều update modes (merge, replace, selective)
- Xử lý an toàn các sensitive configuration values
- Cập nhật connection string sau RDS provisioning
- Hỗ trợ cập nhật individual variables
- Dry run mode để preview changes

**Ví dụ sử dụng**:
```bash
# Cập nhật connection string từ RDS provisioning
./update-lambda-environment.sh --from-rds --function-name webapp-prod-api

# Set individual variables
./update-lambda-environment.sh --set "AWS__Region=us-east-1" --set "OpenAI__Model=gpt-4"

# Load từ configuration file
./update-lambda-environment.sh --config-file lambda-env-vars.json --update-mode merge

# Dry run để xem changes
./update-lambda-environment.sh --from-rds --dry-run
```

## Yêu Cầu Tiên Quyết

### Yêu Cầu Hệ Thống
- **Linux/macOS/Windows với Git Bash**: Scripts được viết bằng Bash
- **.NET 8 SDK**: Cần thiết để build ứng dụng .NET 10
- **AWS CLI**: Được cấu hình với permissions phù hợp
- **jq**: JSON processor (cho configure-environment.sh)

### Yêu Cầu AWS
- Lambda infrastructure đã được provisioned (chạy `../infrastructure/provision-lambda.sh` trước)
- IAM permissions phù hợp cho Lambda operations
- RDS infrastructure (tùy chọn, cho database connectivity)

### Lệnh Cài Đặt
```bash
# Cài đặt .NET 8 SDK (ví dụ cho Ubuntu)
wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y dotnet-sdk-8.0

# Cài đặt jq (ví dụ cho Ubuntu)
sudo apt-get install -y jq

# Cài đặt AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

## Quy Trình Triển Khai

### Triển Khai Ban Đầu
1. **Provision Infrastructure**: Chạy infrastructure scripts trước
   ```bash
   ../infrastructure/provision-rds.sh --environment production
   ../infrastructure/provision-lambda.sh --environment production
   ```

2. **Deploy Application**: Triển khai ứng dụng .NET của bạn
   ```bash
   ./deploy-lambda.sh --environment production --project-name myapp
   ```

3. **Configure Environment**: Convert và apply configuration
   ```bash
   ./configure-environment.sh --function-name myapp-production-api
   ```

4. **Update Connection String**: Sau RDS provisioning
   ```bash
   ./update-lambda-environment.sh --from-rds --function-name myapp-production-api
   ```

### Cập Nhật Development
Để iterations development nhanh hơn, sử dụng code-only updates:
```bash
# Chỉ cập nhật application code
./deploy-lambda.sh --update-mode --function-name myapp-dev-api

# Cập nhật specific environment variables
./update-lambda-environment.sh --set "OpenAI__Model=gpt-4-turbo" --function-name myapp-dev-api
```

## Cân Nhắc Bảo Mật

### Xử Lý Dữ Liệu Nhạy Cảm
- **Connection Strings**: Tự động phát hiện và mask trong logs
- **API Keys**: Phát hiện bằng keywords (key, secret, token, password)
- **AWS Secrets Manager**: Khuyến nghị cho production secrets
- **Environment Variables**: Được mã hóa khi truyền tới Lambda

### Best Practices
1. **Sử dụng AWS Secrets Manager** cho production secrets thay vì environment variables
2. **Rotate credentials** thường xuyên
3. **Sử dụng least privilege** IAM policies
4. **Monitor CloudWatch logs** cho security events
5. **Enable AWS CloudTrail** cho audit logging

## Troubleshooting

### Các Vấn Đề Thường Gặp

#### 1. "Lambda function not found"
**Giải pháp**: Chạy infrastructure provisioning trước
```bash
../infrastructure/provision-lambda.sh --environment <env> --project-name <name>
```

#### 2. "Invalid JSON in configuration file"
**Giải pháp**: Validate file appsettings.json của bạn
```bash
jq empty code/TestDeployLambda/BE/RAG.APIs/appsettings.json
```

#### 3. "Package size exceeds limit"
**Giải pháp**: Script tự động sử dụng S3 cho packages lớn, đảm bảo S3 permissions được cấu hình

#### 4. ".NET SDK not found"
**Giải pháp**: Cài đặt .NET 8 SDK
```bash
# Kiểm tra phiên bản hiện tại
dotnet --version

# Cài đặt nếu thiếu (xem phần Prerequisites)
```

#### 5. "AWS CLI validation failed"
**Giải pháp**: Cấu hình AWS CLI
```bash
aws configure
# hoặc
aws configure --profile <profile-name>
```

### Debug Mode
Enable debug logging để troubleshooting:
```bash
export LOG_LEVEL=4  # Debug level
./deploy-lambda.sh --help
```

### Log Files
Scripts tạo log files để debugging:
- `deployment.log`: General deployment logs
- `deployment_errors.log`: Error details với context

## Tích Hợp Với Các Scripts Khác

### Infrastructure Scripts
- **provision-rds.sh**: Tạo database infrastructure
- **provision-lambda.sh**: Tạo Lambda infrastructure
- **configure-iam.sh**: Thiết lập IAM roles và policies

### Migration Scripts
- **run-migrations.sh**: Thực thi database migrations
- **seed-data.sh**: Seeds dữ liệu ban đầu

### Utility Scripts
- **validate-aws-cli.sh**: Validates cấu hình AWS CLI
- **logging.sh**: Cung cấp logging utilities
- **error-handling.sh**: Cung cấp error handling framework

## Ví Dụ Cấu Hình

### Cấu Trúc appsettings.json
```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "AllowedHosts": "*",
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Port=5432;Database=MyApp;Username=user;Password=pass"
  },
  "AWS": {
    "Region": "us-east-1",
    "UserPoolId": "us-east-1_XXXXXXXXX",
    "ClientId": "xxxxxxxxxxxxxxxxxxxxxxxxxx",
    "S3BucketName": "my-app-bucket"
  },
  "OpenAI": {
    "ApiKey": "sk-...",
    "Model": "gpt-4",
    "MaxToken": 1000
  }
}
```

### Cấu Hình Theo Environment
```json
// appsettings.Production.json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=prod-db.amazonaws.com;Port=5432;Database=MyApp;Username=produser;Password=prodpass"
  },
  "AWS": {
    "Region": "us-east-1"
  },
  "OpenAI": {
    "Model": "gpt-4-turbo"
  }
}
```

## Tối Ưu Hóa Performance

### Cấu Hình Lambda
- **Memory**: Bắt đầu với 512MB, tăng nếu cần
- **Timeout**: 30s cho hầu hết operations, 60s+ cho heavy processing
- **Runtime**: Sử dụng dotnet8 (gần nhất với .NET 10)

### Tối Ưu Package
- **Exclude**: .pdb files, .xml documentation files
- **Include**: Chỉ necessary dependencies
- **Compress**: Automatic zip compression

### Tối Ưu Cold Start
- **Provisioned Concurrency**: Cho production workloads
- **Connection Pooling**: Cho database connections
- **Dependency Injection**: Tối ưu service registration

## Monitoring và Logging

### Tích Hợp CloudWatch
Tất cả Lambda functions tự động log vào CloudWatch:
```bash
# Xem logs
aws logs tail /aws/lambda/<function-name> --follow

# Filter logs
aws logs filter-events --log-group-name /aws/lambda/<function-name> --filter-pattern "ERROR"
```

### Custom Metrics
Scripts hỗ trợ custom logging levels và file output cho monitoring integration.

## Hỗ Trợ và Bảo Trì

### Tương Thích Phiên Bản
- **.NET**: Hỗ trợ ứng dụng .NET 8+
- **AWS Lambda**: Tương thích với Lambda runtimes hiện tại
- **AWS CLI**: Yêu cầu AWS CLI v2

### Updates và Patches
Scripts được thiết kế để forward-compatible. Update paths:
1. Test trong development environment
2. Validate với dry-run mode
3. Deploy lên staging
4. Deploy lên production

Đối với issues hoặc feature requests, tham khảo tài liệu dự án chính.