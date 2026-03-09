# Tối Ưu Chi Phí và Validation AWS CLI

Tài liệu này mô tả các tiện ích tối ưu chi phí và validation AWS CLI được implement cho hệ thống tự động hóa triển khai AWS.

## Tổng Quan

Hệ thống bao gồm hai tiện ích chính:

1. **Tiện Ích Tối Ưu Chi Phí** (`cost-optimization.sh`) - Cung cấp phát hiện AWS free tier, ước tính chi phí, và khuyến nghị tối ưu
2. **Enhanced AWS CLI Validation** (`validate-aws-cli.sh`) - Validation toàn diện thiết lập AWS CLI với hướng dẫn chi tiết

## Tính Năng Tối Ưu Chi Phí

### Phát Hiện Free Tier
- Tự động phát hiện các cấu hình đủ điều kiện AWS free tier
- Validates cấu hình resources theo free tier limits
- Cung cấp cảnh báo khi cấu hình vượt quá free tier eligibility

### Ước Tính Chi Phí
- Ước tính chi phí hàng tháng cho RDS và Lambda resources
- Hỗ trợ nhiều AWS regions với regional cost factors
- Cung cấp cost breakdowns và comparisons

### Tạo Cấu Hình
- Tạo cấu hình tối ưu chi phí cho các environments khác nhau
- Hỗ trợ light, medium, và heavy workload types
- Tự động điều chỉnh settings cho production vs development

### Báo Cáo Chi Phí
- Tạo báo cáo ước tính chi phí toàn diện ở định dạng Markdown
- Bao gồm so sánh chi phí theo region
- Cung cấp cân nhắc Vietnamese context cho lựa chọn region

## Tính Năng AWS CLI Validation

### Validation Toàn Diện
- Kiểm tra cài đặt và phiên bản AWS CLI
- Testing cấu hình và validity của credentials
- Validation cấu hình region và accessibility
- Kiểm tra permissions chi tiết với hướng dẫn khắc phục

### Enhanced Permission Checking
- Test specific AWS service permissions cần thiết cho deployment
- Cung cấp error messages chi tiết với remediation steps
- Bao gồm IAM policy recommendations cho missing permissions

### Quản Lý Profile
- Validates AWS profiles với comprehensive checking
- Liệt kê và phân tích tất cả configured profiles
- Cung cấp hướng dẫn profile switching và management

### Hướng Dẫn Thiết Lập
- Hướng dẫn thiết lập AWS CLI toàn diện
- Hướng dẫn cài đặt theo platform
- Cân nhắc Vietnamese context cho lựa chọn region
- Security best practices và recommendations

## Ví Dụ Sử Dụng

### Tối Ưu Chi Phí

```bash
# Tạo cấu hình RDS tối ưu chi phí
./scripts/utilities/cost-optimization.sh config --resource rds --environment production --workload medium

# Ước tính Lambda costs
./scripts/utilities/cost-optimization.sh estimate --resource lambda --config "memory_size=512,timeout=30"

# Tạo báo cáo chi phí toàn diện
./scripts/utilities/cost-optimization.sh report --environment production --region ap-southeast-1 --output prod-costs.md

# Validate cost settings
./scripts/utilities/cost-optimization.sh validate --resource rds --config "instance_class=db.t3.micro,storage_size=20"

# Lấy cost recommendations
./scripts/utilities/cost-optimization.sh recommendations --environment dev
```

### AWS CLI Validation

```bash
# Basic validation
./scripts/utilities/validate-aws-cli.sh

# Validate profile cụ thể
./scripts/utilities/validate-aws-cli.sh validate --profile production

# Hiển thị hướng dẫn thiết lập
./scripts/utilities/validate-aws-cli.sh setup

# Liệt kê tất cả profiles
./scripts/utilities/validate-aws-cli.sh profiles

# Chạy diagnostics
./scripts/utilities/validate-aws-cli.sh diagnostics

# Chỉ kiểm tra permissions
./scripts/utilities/validate-aws-cli.sh permissions --profile dev
```

## Tích Hợp Với Deployment Scripts

Cả hai tiện ích được thiết kế để tích hợp seamlessly với các deployment automation scripts hiện có:

- Infrastructure provisioning scripts sử dụng cost-optimized configurations theo mặc định
- AWS CLI validation được thực hiện trước bất kỳ deployment operations nào
- Cost estimation có thể chạy trước infrastructure provisioning để preview costs
- Permission validation đảm bảo IAM setup phù hợp trước deployment

## Cân Nhắc Vietnamese Context

### Khuyến Nghị Region
1. **ap-southeast-1 (Singapore)**: Latency tốt nhất (~50-80ms), chi phí cao hơn ~15%
2. **ap-northeast-1 (Tokyo)**: Latency tốt (~80-120ms), chi phí cao hơn ~12%  
3. **us-east-1 (N. Virginia)**: Chi phí thấp nhất, latency cao hơn (~200-250ms)

### Quản Lý Chi Phí
- Monitoring tỷ giá (USD sang VND) cho budget planning
- Scheduling giờ làm việc cho development environments
- Tích hợp AWS Cost Explorer cho detailed analysis

## Security Best Practices

### Quản Lý Credentials
- Không bao giờ share hoặc commit access keys vào version control
- Sử dụng IAM roles thay vì access keys khi có thể
- Rotate access keys thường xuyên (mỗi 90 ngày)
- Enable MFA để bảo mật thêm

### Quản Lý Permissions
- Tuân theo nguyên tắc least privilege
- Sử dụng managed policies khi có thể
- Regular permission audits và reviews
- Tách biệt development và production credentials

## Chiến Lược Tối Ưu Chi Phí

### Development Environment
- Sử dụng instance sizes nhỏ nhất (db.t3.micro, 512MB Lambda)
- Disable backups và encryption
- Single-AZ deployments
- Stop resources khi không sử dụng

### Production Environment
- Enable backups và encryption (security vs cost trade-off)
- Cân nhắc Reserved Instances cho predictable workloads
- Monitor và thiết lập billing alerts
- Sử dụng Auto Scaling để tối ưu resource usage

## Troubleshooting

### Các Vấn Đề Thường Gặp
1. **bc command not found**: Cost optimization utility sử dụng shell arithmetic thay vì bc để compatibility
2. **AWS CLI not found**: Tuân theo comprehensive setup instructions được cung cấp
3. **Permission denied**: Kiểm tra IAM policies và liên hệ AWS administrator
4. **Invalid region**: Xác minh region format và accessibility

### Nhận Trợ Giúp
- Chạy utilities với flag `--help` cho detailed usage information
- Kiểm tra log files cho detailed error messages
- Sử dụng diagnostic commands cho system analysis
- Tham khảo AWS documentation cho service-specific issues