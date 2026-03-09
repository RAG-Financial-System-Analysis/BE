# Scripts Tự Động Hóa Triển Khai AWS

Thư mục này chứa tất cả các scripts để tự động hóa việc provisioning AWS infrastructure và triển khai ứng dụng .NET 10.

## 🚀 Hướng Dẫn Sử Dụng Nhanh

### 📁 Vị Trí Đặt Folder Scripts
Đặt folder `scripts` này trong thư mục gốc của dự án .NET của bạn:
```
your-project/
├── src/                    # Code .NET của bạn
├── scripts/               # Folder scripts này
│   ├── deploy.sh
│   ├── infrastructure/
│   ├── deployment/
│   └── ...
├── appsettings.json       # File cấu hình .NET
└── your-project.sln
```

### 🔧 Thiết Lập Ban Đầu (Chỉ làm 1 lần)

1. **Cài đặt AWS CLI:**
   ```bash
   # Windows (PowerShell)
   winget install Amazon.AWSCLI
   
   # macOS
   brew install awscli
   
   # Linux
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install
   ```

2. **Cấu hình AWS credentials:**
   ```bash
   aws configure
   # Nhập: Access Key ID, Secret Access Key, Region (vd: ap-southeast-1), Output format (json)
   ```

3. **Kiểm tra thiết lập:**
   ```bash
   cd your-project
   chmod +x scripts/utilities/validate-aws-cli.sh
   ./scripts/utilities/validate-aws-cli.sh
   ```

### 🎯 Triển Khai Lần Đầu (Initial Deployment)

```bash
cd your-project

# Bước 1: Tạo infrastructure AWS (RDS, Lambda, VPC, IAM)
./scripts/deploy.sh --mode initial --environment production --project-name myapp

# Hoặc với environment khác
./scripts/deploy.sh --mode initial --environment staging --project-name myapp-staging
```

**Quá trình này sẽ:**
- Tạo VPC và subnets
- Tạo RDS PostgreSQL database
- Tạo Lambda function
- Thiết lập IAM roles và permissions
- Deploy code .NET lên Lambda
- Chạy database migrations
- Cấu hình environment variables

### 🔄 Cập Nhật Code (Update Deployment)

Khi bạn có code mới cần deploy:

```bash
cd your-project

# Chỉ deploy code mới, không thay đổi infrastructure
./scripts/deploy.sh --mode update --environment production --project-name myapp
```

**Quá trình này sẽ:**
- Build và package code .NET mới
- Upload lên Lambda function hiện có
- Chạy database migrations mới (nếu có)
- Cập nhật environment variables (nếu cần)

### 📊 Xem Logs và Monitoring

1. **Xem logs deployment:**
   ```bash
   # Logs chính
   cat deployment.log
   
   # Logs lỗi
   cat deployment_errors.log
   
   # Logs theo thời gian thực
   tail -f deployment.log
   ```

2. **Xem logs Lambda trên AWS:**
   ```bash
   # Xem logs Lambda function
   aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/myapp"
   
   # Xem logs chi tiết
   aws logs tail /aws/lambda/myapp-production --follow
   ```

3. **Kiểm tra trạng thái infrastructure:**
   ```bash
   ./scripts/utilities/check-infrastructure.sh --environment production --project-name myapp
   ```

### 🛠️ Bảo Trì và Troubleshooting

1. **Kiểm tra trạng thái hệ thống:**
   ```bash
   # Kiểm tra tất cả resources
   ./scripts/utilities/check-infrastructure.sh --environment production
   
   # Kiểm tra chỉ RDS
   aws rds describe-db-instances --query "DBInstances[?contains(DBInstanceIdentifier, 'myapp')]"
   
   # Kiểm tra chỉ Lambda
   aws lambda list-functions --query "Functions[?contains(FunctionName, 'myapp')]"
   ```

2. **Rollback khi có lỗi:**
   ```bash
   # Rollback tự động
   ./scripts/deploy.sh --mode rollback --environment production --project-name myapp
   
   # Rollback chỉ Lambda code
   ./scripts/utilities/rollback-deployment.sh --scope lambda --environment production
   ```

3. **Dọn dẹp resources (cẩn thận!):**
   ```bash
   # Xem trước sẽ xóa gì
   ./scripts/infrastructure/cleanup-infrastructure.sh --dry-run --environment staging
   
   # Xóa thật (không thể hoàn tác!)
   ./scripts/infrastructure/cleanup-infrastructure.sh --environment staging --force
   ```

### 🔍 Các Lệnh Hữu Ích Khác

1. **Dry run (xem trước không thực hiện):**
   ```bash
   ./scripts/deploy.sh --mode initial --environment staging --dry-run
   ```

2. **Liệt kê checkpoints:**
   ```bash
   ./scripts/deploy.sh --list-checkpoints
   ```

3. **Resume từ checkpoint:**
   ```bash
   ./scripts/deploy.sh --mode resume --environment production --checkpoint rds_provisioned
   ```

4. **Chạy chỉ migrations:**
   ```bash
   ./scripts/migration/run-migrations.sh --connection-string "your-connection-string"
   ```

### ⚠️ Lưu Ý Quan Trọng

- **Environment names:** Sử dụng `development`, `staging`, hoặc `production`
- **Project names:** Chỉ dùng chữ cái, số và dấu gạch ngang
- **Backup:** Luôn backup database trước khi deploy production
- **Testing:** Test trên staging trước khi deploy production
- **Costs:** Monitor AWS costs, đặc biệt RDS và Lambda usage

## 📋 Scenarios Thường Gặp

### Scenario 1: Lần đầu setup dự án mới
```bash
# 1. Clone/tạo dự án .NET
git clone your-repo
cd your-project

# 2. Copy folder scripts vào dự án
# (Đặt scripts/ ở cùng level với src/)

# 3. Thiết lập AWS
aws configure

# 4. Validate setup
./scripts/utilities/validate-aws-cli.sh

# 5. Deploy lần đầu
./scripts/deploy.sh --mode initial --environment staging --project-name myapp-staging
```

### Scenario 2: Developer deploy code mới hàng ngày
```bash
# 1. Pull code mới
git pull origin main

# 2. Build và test local (optional)
dotnet build
dotnet test

# 3. Deploy lên staging
./scripts/deploy.sh --mode update --environment staging --project-name myapp-staging

# 4. Test trên staging
# ... test your app ...

# 5. Deploy lên production (nếu OK)
./scripts/deploy.sh --mode update --environment production --project-name myapp
```

### Scenario 3: Có lỗi cần rollback
```bash
# 1. Phát hiện lỗi sau deploy
# 2. Rollback ngay lập tức
./scripts/deploy.sh --mode rollback --environment production --project-name myapp

# 3. Kiểm tra logs để tìm nguyên nhân
cat deployment_errors.log
aws logs tail /aws/lambda/myapp-production --since 1h

# 4. Fix code và deploy lại
git commit -m "fix: issue xyz"
./scripts/deploy.sh --mode update --environment production --project-name myapp
```

### Scenario 4: Database migration mới
```bash
# 1. Tạo migration mới trong .NET project
dotnet ef migrations add NewFeature

# 2. Deploy (sẽ tự động chạy migrations)
./scripts/deploy.sh --mode update --environment staging --project-name myapp-staging

# 3. Nếu migration fail, rollback
./scripts/migration/rollback-migrations.sh --target-migration PreviousMigration
```

### Scenario 5: Monitoring và maintenance
```bash
# Hàng ngày - kiểm tra health
./scripts/utilities/check-infrastructure.sh --environment production

# Hàng tuần - xem logs
aws logs tail /aws/lambda/myapp-production --since 7d > weekly-logs.txt

# Hàng tháng - kiểm tra costs
aws ce get-cost-and-usage --time-period Start=2024-01-01,End=2024-01-31 --granularity MONTHLY --metrics BlendedCost
```

### Scenario 6: Cleanup environment cũ
```bash
# 1. Backup data quan trọng trước
aws rds create-db-snapshot --db-instance-identifier myapp-old --db-snapshot-identifier myapp-old-backup

# 2. Xem trước sẽ xóa gì
./scripts/infrastructure/cleanup-infrastructure.sh --dry-run --environment old-env

# 3. Xóa (cẩn thận!)
./scripts/infrastructure/cleanup-infrastructure.sh --environment old-env --force
```

## 🔧 Troubleshooting Thường Gặp

### Lỗi: "AWS CLI not configured"
```bash
# Giải pháp:
aws configure
# Nhập access key, secret key, region
```

### Lỗi: "Permission denied"
```bash
# Giải pháp:
chmod +x scripts/deploy.sh
chmod +x scripts/**/*.sh
```

### Lỗi: "RDS instance already exists"
```bash
# Giải pháp 1: Sử dụng mode update thay vì initial
./scripts/deploy.sh --mode update --environment production --project-name myapp

# Giải pháp 2: Cleanup và tạo lại
./scripts/infrastructure/cleanup-infrastructure.sh --scope rds --environment production
./scripts/deploy.sh --mode initial --environment production --project-name myapp
```

### Lỗi: "Lambda deployment package too large"
```bash
# Giải pháp: Optimize package size
# 1. Kiểm tra dependencies không cần thiết
# 2. Sử dụng trimming trong .NET
# 3. Exclude files không cần thiết
```

### Lỗi: "Database connection failed"
```bash
# Giải pháp:
# 1. Kiểm tra security groups
aws ec2 describe-security-groups --filters "Name=group-name,Values=*myapp*"

# 2. Kiểm tra RDS status
aws rds describe-db-instances --db-instance-identifier myapp-production

# 3. Test connection từ Lambda
aws lambda invoke --function-name myapp-production --payload '{"test":"connection"}' response.json
```

## 📞 Hỗ Trợ và Liên Hệ

### Khi gặp vấn đề:
1. **Kiểm tra logs:** `cat deployment_errors.log`
2. **Validate AWS setup:** `./scripts/utilities/validate-aws-cli.sh`
3. **Kiểm tra infrastructure:** `./scripts/utilities/check-infrastructure.sh`
4. **Xem AWS Console** để kiểm tra resources trực tiếp

### Files logs quan trọng:
- `deployment.log` - Logs chính của deployment
- `deployment_errors.log` - Logs lỗi chi tiết
- `/aws/lambda/function-name` - Logs Lambda trên CloudWatch

### Useful AWS CLI commands:
```bash
# Xem tất cả resources của project
aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=myapp

# Xem costs hiện tại
aws ce get-cost-and-usage --time-period Start=2024-01-01,End=2024-01-31 --granularity MONTHLY --metrics BlendedCost

# Xem Lambda logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/"
```

## Cấu Trúc Thư Mục

```
scripts/
├── deploy.sh                    # Script điều phối triển khai chính với tính năng khôi phục
├── infrastructure/              # Scripts provisioning AWS infrastructure
│   ├── provision-rds.sh        # Provisioning RDS PostgreSQL
│   ├── provision-lambda.sh     # Provisioning Lambda function
│   ├── configure-iam.sh        # Thiết lập IAM roles và policies
│   └── cleanup-infrastructure.sh # Dọn dẹp tài nguyên toàn diện
├── deployment/                  # Scripts triển khai ứng dụng
│   ├── deploy-lambda.sh        # Triển khai code Lambda
│   ├── configure-environment.sh # Cấu hình environment variables
│   └── update-lambda-environment.sh # Cập nhật Lambda environment
├── migration/                   # Scripts migration database
│   ├── run-migrations.sh       # Chạy Entity Framework migrations
│   ├── seed-data.sh            # Seeding database
│   └── rollback-migrations.sh  # Rollback migrations
├── utilities/                   # Scripts tiện ích cốt lõi
│   ├── logging.sh              # Tiện ích logging với timestamp và log levels
│   ├── validate-aws-cli.sh     # Validation AWS CLI và kiểm tra credentials
│   ├── error-handling.sh       # Framework xử lý lỗi toàn diện
│   ├── rollback-deployment.sh  # Hệ thống rollback deployment
│   ├── resume-deployment.sh    # Tiếp tục deployments bị gián đoạn
│   └── check-infrastructure.sh # Validation trạng thái infrastructure
└── README.md                   # File này
```

## Script Triển Khai Chính

Script `deploy.sh` cung cấp điều phối triển khai toàn diện với các tính năng khôi phục nâng cao:

### Các Chế Độ Triển Khai
- **initial**: Provisioning infrastructure đầy đủ và triển khai code
- **update**: Chỉ triển khai code mà không thay đổi infrastructure
- **cleanup**: Xóa tài nguyên hoàn toàn với xác nhận
- **rollback**: Rollback thông minh dựa trên phân tích lỗi
- **resume**: Tiếp tục từ checkpoint thành công cuối cùng

### Tính Năng Khôi Phục
- **Tự động tạo checkpoint** trong các bước triển khai
- **Phân tích lỗi thông minh** với hướng dẫn khắc phục cụ thể
- **Logging toàn diện** với context lỗi chi tiết
- **Khả năng rollback** cho tất cả các thành phần triển khai
- **Chức năng resume** từ bất kỳ checkpoint nào

### Ví Dụ Sử Dụng
```bash
# Triển khai ban đầu với tính năng khôi phục
./scripts/deploy.sh --mode initial --environment production

# Rollback deployment thất bại
./scripts/deploy.sh --mode rollback --environment production --force

# Resume từ checkpoint
./scripts/deploy.sh --mode resume --environment production --checkpoint rds_provisioned

# Liệt kê các checkpoint có sẵn
./scripts/deploy.sh --list-checkpoints

# Dry run để xem trước các hành động
./scripts/deploy.sh --mode initial --environment staging --dry-run
```

## Tiện Ích Cốt Lõi

### Tiện Ích Logging (`utilities/logging.sh`)

Cung cấp logging nhất quán trên tất cả deployment scripts với:
- Hỗ trợ timestamp
- Các mức log (ERROR, WARN, INFO, DEBUG, SUCCESS)
- Output console có mã màu
- File logging để debugging
- Cấu hình được các mức log và đường dẫn file

**Cách sử dụng:**
```bash
source scripts/utilities/logging.sh

log_info "Bắt đầu quá trình triển khai"
log_warn "Đây là thông báo cảnh báo"
log_error "Đây là thông báo lỗi"
log_success "Hoạt động hoàn thành thành công"
```

**Environment Variables:**
- `LOG_LEVEL`: Đặt mức log (1=ERROR, 2=WARN, 3=INFO, 4=DEBUG)
- `LOG_FILE`: Đặt đường dẫn file log tùy chỉnh (mặc định: ./deployment.log)

### Validation AWS CLI (`utilities/validate-aws-cli.sh`)

Validate thiết lập AWS CLI trước các hoạt động triển khai:
- Kiểm tra cài đặt AWS CLI
- Validate credentials và permissions
- Xác minh cấu hình region

### Framework Xử Lý Lỗi (`utilities/error-handling.sh`)

Hệ thống xử lý lỗi toàn diện với:
- Thông báo lỗi chi tiết với context và các bước khắc phục
- Hệ thống mã lỗi để nhận dạng lỗi nhất quán
- Logging lỗi toàn diện vào files để debugging
- Đăng ký và thực thi hàm cleanup tự động
- Hệ thống checkpoint để theo dõi trạng thái triển khai
- Phân tích lỗi AWS cụ thể và hướng dẫn

**Tính Năng Chính:**
- **18 mã lỗi riêng biệt** cho các loại lỗi khác nhau
- **Thông báo lỗi có context** với các bước khắc phục cụ thể
- **Logging lỗi tự động** với chi tiết môi trường và hệ thống
- **Tạo và khôi phục checkpoint** cho các hoạt động recovery
- **Phân tích lỗi AWS** với hướng dẫn cụ thể cho các vấn đề thường gặp

**Cách sử dụng:**
```bash
source scripts/utilities/error-handling.sh

# Đặt context lỗi để báo cáo tốt hơn
set_error_context "RDS provisioning"
set_error_remediation "Kiểm tra AWS RDS limits và các instances hiện có"

# Xử lý lỗi với thông tin chi tiết
handle_error $ERROR_CODE_INFRASTRUCTURE "RDS provisioning thất bại" true

# Tạo checkpoints để recovery
create_checkpoint "rds_provisioned" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Đăng ký cleanup functions
register_cleanup_function cleanup_temp_files
```

## Hệ Thống Recovery và Rollback

### Dọn Dẹp Infrastructure (`infrastructure/cleanup-infrastructure.sh`)

Dọn dẹp tài nguyên AWS toàn diện với:
- **Khám phá tài nguyên thông minh** trên tất cả các dịch vụ AWS
- **Dọn dẹp có phạm vi** (all, lambda, rds, iam, vpc)
- **Chế độ dry-run** để xem trước các xóa
- **Chế độ force** để dọn dẹp tự động
- **Báo cáo dọn dẹp chi tiết** với theo dõi thành công/thất bại

**Cách sử dụng:**
```bash
# Dọn dẹp đầy đủ với xác nhận
./scripts/infrastructure/cleanup-infrastructure.sh --environment production

# Dry run để xem những gì sẽ bị xóa
./scripts/infrastructure/cleanup-infrastructure.sh --dry-run --environment staging

# Force cleanup không có prompts
./scripts/infrastructure/cleanup-infrastructure.sh --force --environment dev

# Chỉ dọn dẹp tài nguyên cụ thể
./scripts/infrastructure/cleanup-infrastructure.sh --scope lambda --environment production
```

### Rollback Deployment (`utilities/rollback-deployment.sh`)

Hệ thống rollback thông minh với:
- **Phân tích lỗi tự động** dựa trên trạng thái deployment
- **Rollback phiên bản Lambda** về các phiên bản hoạt động trước đó
- **Rollback migration database** với hướng dẫn khôi phục snapshot
- **Dọn dẹp infrastructure một phần** cho provisioning thất bại
- **Rollback có phạm vi** để recovery có mục tiêu

**Cách sử dụng:**
```bash
# Rollback tự động dựa trên trạng thái deployment
./scripts/utilities/rollback-deployment.sh --environment production

# Rollback các thành phần cụ thể
./scripts/utilities/rollback-deployment.sh --scope lambda --environment staging

# Rollback về checkpoint cụ thể
./scripts/utilities/rollback-deployment.sh --checkpoint rds_provisioned --environment dev
```

### Resume Deployment (`utilities/resume-deployment.sh`)

Resume các deployments bị gián đoạn với:
- **Phát hiện checkpoint tự động** từ bước thành công cuối cùng
- **Validation trạng thái infrastructure** trước khi resume
- **Xác định hành động thông minh** dựa trên checkpoint
- **Theo dõi tiến độ** với tạo checkpoint mới

**Cách sử dụng:**
```bash
# Resume từ checkpoint cuối cùng
./scripts/utilities/resume-deployment.sh --environment production --mode initial

# Resume từ checkpoint cụ thể
./scripts/utilities/resume-deployment.sh --checkpoint lambda_provisioned --environment staging

# Liệt kê các checkpoint có sẵn
./scripts/utilities/resume-deployment.sh --list-checkpoints
```
- Kiểm tra các permissions dịch vụ AWS cần thiết

**Cách sử dụng:**
```bash
source scripts/utilities/validate-aws-cli.sh

# Validate với profile mặc định
validate_aws_cli

# Validate với profile cụ thể
validate_aws_cli "my-profile"

# Hiển thị hướng dẫn thiết lập
show_aws_setup_instructions
```

### Framework Xử Lý Lỗi (`utilities/error-handling.sh`)

Cung cấp báo cáo và xử lý lỗi nhất quán:
- Mã lỗi chuẩn hóa
- Thông báo lỗi có nhận thức context
- Thực thi hàm cleanup tự động
- Checkpoints khôi phục lỗi
- Xử lý lỗi AWS cụ thể

**Cách sử dụng:**
```bash
source scripts/utilities/error-handling.sh

# Đặt context lỗi để báo cáo tốt hơn
set_error_context "RDS provisioning"
set_error_remediation "Kiểm tra giới hạn dịch vụ AWS RDS và permissions"

# Đăng ký cleanup functions
register_cleanup_function "cleanup_rds_resources"

# Thực thi commands với xử lý lỗi
execute_with_error_handling "aws rds create-db-instance ..." "Thất bại tạo RDS instance"

# Xử lý lỗi cụ thể
handle_error $ERROR_CODE_INFRASTRUCTURE "Tạo RDS instance thất bại"
```

## Yêu Cầu Tiên Quyết

Trước khi sử dụng các scripts này, đảm bảo bạn có:

1. **AWS CLI v2** được cài đặt và cấu hình
2. **AWS credentials hợp lệ** với các permissions cần thiết
3. **Bash shell** (người dùng Windows có thể sử dụng Git Bash hoặc WSL)
4. **IAM permissions phù hợp** cho:
   - Amazon RDS (tạo, sửa đổi, xóa instances)
   - AWS Lambda (tạo, cập nhật, invoke functions)
   - Amazon EC2/VPC (tạo, sửa đổi tài nguyên mạng)
   - IAM (tạo, sửa đổi roles và policies)

## Bắt Đầu

1. Validate thiết lập AWS CLI của bạn:
   ```bash
   ./scripts/utilities/validate-aws-cli.sh
   ```

2. Kiểm tra output validation và giải quyết mọi vấn đề trước khi tiến hành triển khai.

## Xử Lý Lỗi

Tất cả scripts sử dụng framework xử lý lỗi tập trung cung cấp:
- Thông báo lỗi chi tiết với context
- Cleanup tự động khi thất bại
- Logging lỗi để debugging
- Recovery checkpoints cho deployments một phần

Error logs được lưu vào `deployment_errors.log` để troubleshooting.

## Logging

Tất cả hoạt động script được log vào `deployment.log` theo mặc định. Bạn có thể:
- Thay đổi mức log: `export LOG_LEVEL=4` (cho mức DEBUG)
- Thay đổi file log: `export LOG_FILE="/path/to/custom.log"`
- Xóa logs: Sử dụng hàm `clear_log` từ logging.sh

## Hỗ Trợ

Đối với các vấn đề hoặc câu hỏi:
1. Kiểm tra error logs trong `deployment_errors.log`
2. Review cấu hình AWS CLI với `aws configure list`
3. Xác minh AWS permissions với validation script
4. Tham khảo phần troubleshooting trong tài liệu dự án chính