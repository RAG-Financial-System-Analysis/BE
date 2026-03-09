# Scripts Migration Database

Thư mục này chứa các scripts để quản lý Entity Framework database migrations cho ứng dụng .NET 10 RAG System.

## Tổng Quan Scripts

### 1. `run-migrations.sh`
Thực thi Entity Framework migrations với validation database connectivity, error handling, và rollback capabilities phù hợp.

**Tính năng:**
- Validation database connectivity
- Tự động tạo backup trước migrations
- Thực thi migration với error handling phù hợp
- Khả năng rollback cho migrations thất bại
- Quản lý connection string và bảo mật
- Dry-run mode để testing

**Cách sử dụng:**
```bash
# Chạy migrations với connection string
./run-migrations.sh --connection-string "Host=mydb.amazonaws.com;Port=5432;Database=RAG-System;Username=postgres;Password=mypass"

# Rollback về migration cụ thể
./run-migrations.sh --connection-string "..." --rollback-to "20260303161754_initDb"

# Dry run để xem những gì sẽ được thực thi
./run-migrations.sh --connection-string "..." --dry-run
```

### 2. `seed-data.sh`
Seeds database với dữ liệu ban đầu bao gồm roles, users, và analytics types với logic idempotent.

**Tính năng:**
- Logic seeding idempotent để ngăn duplicate data
- Validation dữ liệu trước khi seeding
- Tích hợp Cognito để tạo user
- Hỗ trợ custom user credentials
- Cấu hình theo environment
- Dry-run mode để testing

**Dữ liệu được Seed:**
- System roles (Admin, Analyst)
- Analytics types (Risk, Trend, Comparison, Opportunity, Executive)
- Default users với Cognito integration

**Cách sử dụng:**
```bash
# Seed với default users
./seed-data.sh --connection-string "Host=mydb.amazonaws.com;..."

# Seed với custom admin credentials
./seed-data.sh --connection-string "..." --admin-email "admin@company.com" --admin-password "SecurePass123!"

# Skip Cognito cho local development
./seed-data.sh --connection-string "..." --skip-cognito
```

### 3. `rollback-migrations.sh`
Cung cấp khả năng rollback cho Entity Framework migrations với validation và safety checks phù hợp.

**Tính năng:**
- Migration rollback về các điểm cụ thể
- Safety confirmations và validation
- Database backup tùy chọn trước rollback
- Visualization rollback plan
- Force mode cho automated scenarios

**Cách sử dụng:**
```bash
# Rollback về migration cụ thể
./rollback-migrations.sh --connection-string "..." --target-migration "20260303161754_initDb"

# Rollback với backup
./rollback-migrations.sh --connection-string "..." --target-migration "InitialCreate" --backup

# Rollback tất cả migrations
./rollback-migrations.sh --connection-string "..." --target-migration "0"
```

## Yêu Cầu Tiên Quyết

### Yêu Cầu Hệ Thống
- .NET 10 SDK được cài đặt
- Entity Framework Core tools (`dotnet tool install --global dotnet-ef`)
- PostgreSQL client tools (tùy chọn, cho direct database operations)
- AWS CLI được cấu hình (cho Cognito integration)

### Yêu Cầu Database
- PostgreSQL 16 database có thể truy cập
- Connection string hợp lệ với permissions phù hợp
- Database schema được tạo thông qua migrations

### Yêu Cầu AWS (cho seeding với Cognito)
- AWS Cognito User Pool được cấu hình
- AWS credentials được cấu hình qua AWS CLI hoặc environment variables
- IAM permissions phù hợp cho Cognito operations

## Cấu Hình

### Định Dạng Connection String
```
Host=<hostname>;Port=<port>;Database=<database>;Username=<username>;Password=<password>
```

### Environment Variables (cho Cognito integration)
```bash
export AWS_REGION="ap-southeast-1"
export AWS_USER_POOL_ID="ap-southeast-1_VTLpFeyhi"
export AWS_CLIENT_ID="76hpd4tfrp93qf33ue6sr0991g"
```

### Cấu Trúc Project
Các scripts mong đợi cấu trúc project sau:
```
code/TestDeployLambda/BE/
├── RAG.APIs/                 # Startup project
├── RAG.Infrastructure/       # Chứa DbContext và migrations
├── RAG.Domain/              # Domain entities
└── RAG.Application/         # Application layer
```

## Quy Trình Thường Gặp

### Thiết Lập Database Ban Đầu
```bash
# 1. Chạy migrations để tạo schema
./run-migrations.sh --connection-string "Host=..."

# 2. Seed dữ liệu ban đầu
./seed-data.sh --connection-string "Host=..."
```

### Quy Trình Development
```bash
# Test migrations mà không apply
./run-migrations.sh --connection-string "Host=..." --dry-run

# Apply migrations
./run-migrations.sh --connection-string "Host=..."

# Seed development data (skip Cognito)
./seed-data.sh --connection-string "Host=..." --skip-cognito
```

### Triển Khai Production
```bash
# Tạo backup và chạy migrations
./run-migrations.sh --connection-string "Host=..." --verbose

# Seed production data với custom credentials
./seed-data.sh --connection-string "Host=..." \
  --admin-email "admin@company.com" \
  --admin-password "SecurePassword123!" \
  --environment production
```

### Kịch Bản Rollback
```bash
# Tạo backup và rollback về migration trước đó
./rollback-migrations.sh --connection-string "Host=..." \
  --target-migration "20260303161754_initDb" \
  --backup
```

## Xử Lý Lỗi

### Các Vấn Đề Thường Gặp và Giải Pháp

**1. Vấn Đề Connection String**
- Xác minh host, port, database name, username, và password
- Kiểm tra network connectivity tới database
- Đảm bảo database tồn tại và user có permissions phù hợp

**2. Migration Failures**
- Kiểm tra cài đặt Entity Framework tools: `dotnet ef --version`
- Xác minh cấu trúc project và references
- Kiểm tra database permissions cho schema changes

**3. Seeding Failures**
- Xác minh database schema tồn tại (chạy migrations trước)
- Kiểm tra cấu hình AWS Cognito cho user creation
- Sử dụng `--skip-cognito` cho local development không có AWS

**4. Vấn Đề Cognito Integration**
- Xác minh AWS credentials: `aws sts get-caller-identity`
- Kiểm tra cấu hình User Pool ID và Client ID
- Đảm bảo IAM permissions phù hợp cho Cognito operations

## Cân Nhắc Bảo Mật

### Bảo Mật Connection String
- Không bao giờ commit connection strings có passwords vào version control
- Sử dụng environment variables hoặc secure configuration management
- Rotate database passwords thường xuyên

### AWS Credentials
- Sử dụng IAM roles khi có thể thay vì access keys
- Tuân theo nguyên tắc least privilege cho Cognito permissions
- Rotate AWS access keys thường xuyên

### Bảo Mật Backup
- Backup files có thể chứa sensitive data
- Lưu trữ backups ở locations an toàn
- Implement backup retention policies

## Logging và Monitoring

### Log Levels
- `INFO`: Thông tin hoạt động chung
- `SUCCESS`: Hoạt động thành công
- `WARNING`: Vấn đề không nghiêm trọng
- `ERROR`: Lỗi nghiêm trọng

### Verbose Mode
Sử dụng flag `--verbose` cho detailed operation logs:
```bash
./run-migrations.sh --connection-string "..." --verbose
```

### Log Files
Scripts sử dụng console output. Để persistent logging, redirect output:
```bash
./run-migrations.sh --connection-string "..." 2>&1 | tee migration.log
```

## Tích Hợp Với Deployment Pipeline

### AWS Lambda Deployment
Các scripts này tích hợp với hệ thống AWS deployment automation:

1. **Infrastructure Provisioning**: RDS instance được tạo
2. **Migration Execution**: `run-migrations.sh` applies schema
3. **Data Seeding**: `seed-data.sh` khởi tạo data
4. **Lambda Deployment**: Application được deploy với updated connection strings

### Environment Variables Update
Sau migration và seeding thành công, cập nhật Lambda environment variables:
```bash
# Connection string sẽ được cập nhật trong Lambda configuration
# AWS Cognito settings sẽ được preserve từ appsettings.json
```

## Troubleshooting

### Debug Mode
Enable debug mode cho detailed execution information:
```bash
set -x  # Enable bash debug mode
./run-migrations.sh --connection-string "..." --verbose
```

### Manual Verification
Xác minh database state manually:
```bash
# Connect tới database
psql "Host=...;Port=5432;Database=RAG-System;Username=postgres"

# Kiểm tra migrations table
SELECT * FROM __EFMigrationsHistory;

# Kiểm tra seeded data
SELECT * FROM roles;
SELECT * FROM users;
SELECT * FROM analytics_type;
```

### Recovery Procedures
Nếu migrations thất bại:
1. Kiểm tra error logs cho specific issues
2. Sử dụng rollback script nếu cần: `./rollback-migrations.sh`
3. Restore từ backup nếu có
4. Liên hệ system administrator cho complex issues

## Requirements Traceability

Các scripts này thỏa mãn các requirements sau:

- **Requirement 2.1**: Migration execution sau RDS provisioning
- **Requirement 2.2**: Basic data seeding (roles và users)
- **Requirement 2.3**: Migration rollback on failure
- **Requirement 2.4**: Database connectivity verification
- **Requirement 2.5**: Connection string updates (được xử lý bởi deployment system)

## Hỗ Trợ

Đối với issues hoặc câu hỏi:
1. Kiểm tra README này cho common solutions
2. Review script help: `./script-name.sh --help`
3. Kiểm tra logs cho detailed error information
4. Tham khảo tài liệu deployment system chính