# Hướng Dẫn Tích Hợp AWS Cognito

Hướng dẫn này bao gồm các tiện ích tích hợp AWS Cognito cho hệ thống tự động hóa triển khai, bao gồm validation cấu hình, thiết lập IAM permissions, và troubleshooting.

## Tổng Quan

Tích hợp Cognito cung cấp:
- **Configuration Validation**: Validates UserPoolId, ClientId, và JWT settings
- **IAM Permission Management**: Cấu hình Lambda roles với Cognito access phù hợp
- **Connectivity Testing**: Test Cognito service accessibility và JWT validation endpoints
- **Error Handling**: Comprehensive error reporting và remediation guidance

## Tiện Ích

### 1. Cognito Configuration Validation (`validate-cognito.sh`)

Validates cấu hình Cognito từ appsettings.json hoặc environment variables.

#### Ví Dụ Sử Dụng

```bash
# Validate cấu hình từ appsettings.json
./scripts/utilities/validate-cognito.sh validate --config appsettings.json

# Kiểm tra specific Cognito resources
./scripts/utilities/validate-cognito.sh check \
  --user-pool-id us-east-1_abcdef123 \
  --client-id 1234567890abcdefghijklmnop

# Tạo configuration template
./scripts/utilities/validate-cognito.sh template --output cognito-config.json

# Kiểm tra required AWS permissions
./scripts/utilities/validate-cognito.sh permissions

# Hiển thị setup guidance
./scripts/utilities/validate-cognito.sh setup
```

#### Validation Checks

- ✅ User Pool ID format validation (`region_randomstring`)
- ✅ App Client ID format validation (26 character alphanumeric)
- ✅ User Pool existence và accessibility
- ✅ App Client existence và configuration
- ✅ JWT issuer URL validation
- ✅ JWT validation endpoint connectivity
- ✅ AWS permissions cho Cognito operations

### 2. Cognito IAM Configuration (`configure-cognito-iam.sh`)

Quản lý IAM roles và policies cho Cognito access từ Lambda functions.

#### Ví Dụ Sử Dụng

```bash
# Tạo complete Lambda role với Cognito permissions
./scripts/utilities/configure-cognito-iam.sh configure-role \
  --role MyLambdaRole \
  --environment production

# Chỉ tạo Cognito policy
./scripts/utilities/configure-cognito-iam.sh create-policy \
  --name MyCognitoPolicy \
  --type full

# Attach existing policy vào role
./scripts/utilities/configure-cognito-iam.sh attach-policy \
  --role MyLambdaRole \
  --policy MyCognitoPolicy

# Validate role permissions
./scripts/utilities/configure-cognito-iam.sh validate-role \
  --role MyLambdaRole \
  --user-pool-id us-east-1_abcdef123

# Remove Cognito permissions
./scripts/utilities/configure-cognito-iam.sh remove-permissions \
  --role MyLambdaRole
```

#### Policy Types

- **full**: Complete Cognito admin permissions (create, update, delete users)
- **readonly**: Read-only permissions (get user info, list users)

## Định Dạng Cấu Hình

### Cấu Trúc appsettings.json

```json
{
  "AWS": {
    "Region": "us-east-1",
    "Cognito": {
      "UserPoolId": "us-east-1_abcdef123",
      "ClientId": "1234567890abcdefghijklmnop"
    }
  },
  "JWT": {
    "Issuer": "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_abcdef123",
    "Audience": "1234567890abcdefghijklmnop",
    "ValidateIssuer": true,
    "ValidateAudience": true,
    "ValidateLifetime": true,
    "ClockSkew": "00:05:00"
  }
}
```

### Environment Variables

```bash
export AWS_REGION="us-east-1"
export AWS_COGNITO_USER_POOL_ID="us-east-1_abcdef123"
export AWS_COGNITO_CLIENT_ID="1234567890abcdefghijklmnop"
export JWT_ISSUER="https://cognito-idp.us-east-1.amazonaws.com/us-east-1_abcdef123"
export JWT_AUDIENCE="1234567890abcdefghijklmnop"
```

## Tích Hợp Với Deployment Scripts

### Tích Hợp Tự Động

Tích hợp Cognito được tự động bao gồm khi provisioning Lambda functions:

```bash
# Lambda provisioning tự động bao gồm Cognito permissions
./scripts/infrastructure/provision-lambda.sh \
  --environment production \
  --project-name myapp
```

### Tích Hợp Manual

Đối với Lambda functions hiện có, cấu hình Cognito permissions manually:

```bash
# Cấu hình Cognito permissions cho existing Lambda role
./scripts/utilities/configure-cognito-iam.sh configure-role \
  --role existing-lambda-role \
  --environment production
```

## Required AWS Permissions

### Cho Deployment Scripts

Deployment scripts yêu cầu các IAM permissions này:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cognito-idp:DescribeUserPool",
        "cognito-idp:DescribeUserPoolClient",
        "cognito-idp:ListUserPools",
        "cognito-idp:ListUserPoolClients"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:CreatePolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:DeleteRole",
        "iam:DeletePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:TagRole"
      ],
      "Resource": "*"
    }
  ]
}
```

### Cho Lambda Functions

Lambda functions nhận các Cognito permissions này:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cognito-idp:AdminGetUser",
        "cognito-idp:AdminListGroupsForUser",
        "cognito-idp:AdminGetUserAttributes",
        "cognito-idp:ListUsers",
        "cognito-idp:AdminCreateUser",
        "cognito-idp:AdminSetUserPassword",
        "cognito-idp:AdminUpdateUserAttributes",
        "cognito-idp:AdminDeleteUser"
      ],
      "Resource": "arn:aws:cognito-idp:*:*:userpool/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cognito-idp:DescribeUserPool",
        "cognito-idp:DescribeUserPoolClient"
      ],
      "Resource": "*"
    }
  ]
}
```

## Troubleshooting

### Các Vấn Đề Thường Gặp

#### 1. Invalid User Pool ID Format

**Lỗi**: `Invalid User Pool ID format: invalid-id`

**Giải pháp**: 
- User Pool ID phải tuân theo format: `region_randomstring`
- Ví dụ: `us-east-1_abcdef123`
- Kiểm tra AWS Console → Cognito → User Pools cho correct ID

#### 2. Invalid Client ID Format

**Lỗi**: `Invalid Client ID format: invalid-client-id`

**Giải pháp**:
- Client ID phải là 26 character lowercase alphanumeric string
- Kiểm tra AWS Console → Cognito → User Pools → App Integration → App Clients

#### 3. User Pool Not Found

**Lỗi**: `User Pool not found or not accessible`

**Giải pháp**:
1. Xác minh User Pool ID đúng
2. Kiểm tra AWS region matches User Pool region
3. Đảm bảo AWS credentials có Cognito permissions
4. Xác minh User Pool tồn tại trong AWS Console

#### 4. JWT Validation Endpoint Failed

**Lỗi**: `JWT validation endpoint returned HTTP 404`

**Giải pháp**:
1. Xác minh User Pool ID đúng
2. Kiểm tra network connectivity
3. Đảm bảo User Pool ở correct region
4. Test endpoint manually: `curl https://cognito-idp.{region}.amazonaws.com/{userPoolId}/.well-known/jwks.json`

#### 5. Missing Cognito Permissions

**Lỗi**: `Missing Cognito permissions detected`

**Giải pháp**:
1. Attach `AmazonCognitoPowerUser` managed policy
2. Tạo custom policy với required permissions
3. Liên hệ AWS administrator cho permission assignment

### Diagnostic Commands

```bash
# Test AWS CLI và Cognito access
aws cognito-idp list-user-pools --max-results 1

# Test specific User Pool
aws cognito-idp describe-user-pool --user-pool-id YOUR_USER_POOL_ID

# Test JWT endpoint
curl -s "https://cognito-idp.us-east-1.amazonaws.com/YOUR_USER_POOL_ID/.well-known/jwks.json"

# Validate configuration
./scripts/utilities/validate-cognito.sh validate --config appsettings.json

# Kiểm tra IAM role permissions
./scripts/utilities/configure-cognito-iam.sh validate-role --role YOUR_LAMBDA_ROLE
```

## Cân Nhắc Vietnamese Context

### Lựa Chọn Region

Đối với người dùng Việt Nam, cân nhắc các regions này:

1. **ap-southeast-1 (Singapore)**: 
   - Latency thấp nhất (~50-80ms)
   - Chi phí cao hơn ~15% so với us-east-1
   - Khuyến nghị cho production

2. **ap-northeast-1 (Tokyo)**:
   - Latency tốt (~80-120ms)
   - Chi phí cao hơn ~12% so với us-east-1
   - Lựa chọn thay thế

3. **us-east-1 (N. Virginia)**:
   - Latency cao nhất (~200-250ms)
   - Chi phí thấp nhất (baseline)
   - Tốt cho development/testing

### Ví Dụ Cấu Hình Cho Việt Nam

```json
{
  "AWS": {
    "Region": "ap-southeast-1",
    "Cognito": {
      "UserPoolId": "ap-southeast-1_abcdef123",
      "ClientId": "1234567890abcdefghijklmnop"
    }
  },
  "JWT": {
    "Issuer": "https://cognito-idp.ap-southeast-1.amazonaws.com/ap-southeast-1_abcdef123",
    "Audience": "1234567890abcdefghijklmnop",
    "ValidateIssuer": true,
    "ValidateAudience": true,
    "ValidateLifetime": true,
    "ClockSkew": "00:05:00"
  }
}
```

### Tối Ưu Chi Phí

- Sử dụng ap-southeast-1 cho production (cân bằng latency và cost)
- Sử dụng us-east-1 cho development/testing (chi phí thấp nhất)
- Monitor token expiration settings cho user experience
- Cân nhắc local compliance requirements

## Integration Testing

### Test Cognito Configuration

```bash
# Full validation test
./scripts/utilities/validate-cognito.sh validate --config appsettings.json

# Expected output:
# ✅ User Pool ID format is valid
# ✅ Client ID format is valid
# ✅ User Pool exists and is accessible
# ✅ App Client exists and is accessible
# ✅ JWT validation endpoint is accessible
# ✅ Cognito configuration validation passed
```

### Test Lambda Role Permissions

```bash
# Validate Lambda role có Cognito permissions
./scripts/utilities/configure-cognito-iam.sh validate-role \
  --role myapp-production-lambda-role \
  --user-pool-id ap-southeast-1_abcdef123

# Expected output:
# ✅ Cognito policies found on role
# ✅ Lambda role has Cognito permissions
```

### End-to-End Test

```bash
# Deploy Lambda với Cognito integration
./scripts/infrastructure/provision-lambda.sh \
  --environment production \
  --project-name myapp

# Validate deployment
./scripts/utilities/validate-cognito.sh check \
  --user-pool-id ap-southeast-1_abcdef123 \
  --client-id 1234567890abcdefghijklmnop

# Test Lambda role
./scripts/utilities/configure-cognito-iam.sh validate-role \
  --role myapp-production-lambda-role
```

## Hỗ Trợ và Resources

### AWS Documentation

- [Amazon Cognito Developer Guide](https://docs.aws.amazon.com/cognito/latest/developerguide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [IAM User Guide](https://docs.aws.amazon.com/iam/latest/userguide/)

### Troubleshooting Resources

- AWS CloudWatch Logs cho Lambda function errors
- AWS CloudTrail cho API call debugging
- AWS IAM Policy Simulator cho permission testing

### Nhận Trợ Giúp

1. Kiểm tra tài liệu này cho common issues
2. Chạy diagnostic commands để identify problems
3. Review AWS CloudWatch logs cho detailed error messages
4. Liên hệ AWS support cho service-specific issues

---

*Hướng dẫn này là một phần của AWS Deployment Automation System. Để biết thêm thông tin, xem file README.md chính.*