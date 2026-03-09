# AWS Permissions Guide - Hướng dẫn phân quyền AWS

Tài liệu này cung cấp hướng dẫn chi tiết về cách cấu hình permissions AWS cho hệ thống deployment automation.

## 📋 Tổng quan

Hệ thống deployment automation cần các permissions sau:
- **RDS**: Tạo và quản lý database instances
- **Lambda**: Deploy và quản lý functions
- **EC2/VPC**: Tạo và quản lý network infrastructure
- **IAM**: Tạo và quản lý roles/policies
- **Cognito**: Quản lý user pools và authentication
- **CloudWatch**: Logging và monitoring

## 🔐 Minimum Required Permissions

### IAM Policy Template
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RDSPermissions",
      "Effect": "Allow",
      "Action": [
        "rds:CreateDBInstance",
        "rds:CreateDBSubnetGroup",
        "rds:DescribeDBInstances",
        "rds:DescribeDBSubnetGroups",
        "rds:ModifyDBInstance",
        "rds:DeleteDBInstance",
        "rds:DeleteDBSubnetGroup",
        "rds:AddTagsToResource",
        "rds:ListTagsForResource",
        "rds:CreateDBSnapshot",
        "rds:DescribeDBSnapshots"
      ],
      "Resource": "*"
    },
    {
      "Sid": "LambdaPermissions",
      "Effect": "Allow",
      "Action": [
        "lambda:CreateFunction",
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration",
        "lambda:GetFunction",
        "lambda:ListFunctions",
        "lambda:DeleteFunction",
        "lambda:InvokeFunction",
        "lambda:TagResource",
        "lambda:UntagResource",
        "lambda:ListTags",
        "lambda:PublishVersion",
        "lambda:CreateAlias",
        "lambda:UpdateAlias"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2VPCPermissions",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc",
        "ec2:CreateSubnet",
        "ec2:CreateSecurityGroup",
        "ec2:CreateInternetGateway",
        "ec2:CreateNatGateway",
        "ec2:CreateRouteTable",
        "ec2:CreateRoute",
        "ec2:AttachInternetGateway",
        "ec2:AssociateRouteTable",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeInternetGateways",
        "ec2:DescribeNatGateways",
        "ec2:DescribeRouteTables",
        "ec2:DescribeAvailabilityZones",
        "ec2:CreateTags",
        "ec2:DescribeTags",
        "ec2:DeleteVpc",
        "ec2:DeleteSubnet",
        "ec2:DeleteSecurityGroup",
        "ec2:DeleteInternetGateway",
        "ec2:DeleteNatGateway",
        "ec2:DeleteRouteTable",
        "ec2:DetachInternetGateway",
        "ec2:DisassociateRouteTable",
        "ec2:AllocateAddress",
        "ec2:ReleaseAddress",
        "ec2:DescribeAddresses"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMPermissions",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:CreatePolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:GetRole",
        "iam:GetPolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListRoles",
        "iam:ListPolicies",
        "iam:DeleteRole",
        "iam:DeletePolicy",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:PassRole",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:ListPolicyVersions",
        "iam:SetDefaultPolicyVersion"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CognitoPermissions",
      "Effect": "Allow",
      "Action": [
        "cognito-idp:DescribeUserPool",
        "cognito-idp:DescribeUserPoolClient",
        "cognito-idp:ListUserPools",
        "cognito-idp:ListUserPoolClients",
        "cognito-idp:AdminGetUser",
        "cognito-idp:AdminListGroupsForUser",
        "cognito-idp:AdminGetUserAttributes",
        "cognito-idp:ListUsers"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogsPermissions",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:FilterLogEvents"
      ],
      "Resource": "*"
    },
    {
      "Sid": "STSPermissions",
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

## 🏢 Managed Policies (Recommended)

### Production Environment
```bash
# Attach managed policies (easier to manage)
aws iam attach-user-policy \
  --user-name deployment-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess

aws iam attach-user-policy \
  --user-name deployment-user \
  --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess

aws iam attach-user-policy \
  --user-name deployment-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

aws iam attach-user-policy \
  --user-name deployment-user \
  --policy-arn arn:aws:iam::aws:policy/IAMFullAccess

aws iam attach-user-policy \
  --user-name deployment-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonCognitoPowerUser

aws iam attach-user-policy \
  --user-name deployment-user \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
```

### Development Environment (Restricted)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": ["us-east-1", "ap-southeast-1"]
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "lambda:*"
      ],
      "Resource": "arn:aws:lambda:*:*:function:*-dev-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "ec2:Region": ["us-east-1", "ap-southeast-1"]
        }
      }
    }
  ]
}
```

## 👥 IAM User Setup

### 1. Create Deployment User
```bash
# Create IAM user
aws iam create-user --user-name aws-deployment-automation

# Create access key
aws iam create-access-key --user-name aws-deployment-automation
```

### 2. Attach Policies
```bash
# Option 1: Use managed policies (recommended)
aws iam attach-user-policy \
  --user-name aws-deployment-automation \
  --policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess

# Option 2: Create custom policy
aws iam create-policy \
  --policy-name AWSDeploymentAutomationPolicy \
  --policy-document file://deployment-policy.json

aws iam attach-user-policy \
  --user-name aws-deployment-automation \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/AWSDeploymentAutomationPolicy
```

### 3. Configure AWS CLI
```bash
aws configure --profile deployment
# Enter the access key and secret from step 1
```

## 🏢 IAM Role Setup (Recommended for EC2/Lambda)

### 1. Create Deployment Role
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### 2. Create Role with CLI
```bash
# Create trust policy file
cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create role
aws iam create-role \
  --role-name AWSDeploymentAutomationRole \
  --assume-role-policy-document file://trust-policy.json

# Attach policies
aws iam attach-role-policy \
  --role-name AWSDeploymentAutomationRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess

# Create instance profile
aws iam create-instance-profile \
  --instance-profile-name AWSDeploymentAutomationProfile

aws iam add-role-to-instance-profile \
  --instance-profile-name AWSDeploymentAutomationProfile \
  --role-name AWSDeploymentAutomationRole
```

## 🔒 Security Best Practices

### 1. Principle of Least Privilege
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:CreateDBInstance",
        "rds:DescribeDBInstances"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "rds:db-instance-class": ["db.t3.micro", "db.t3.small"]
        }
      }
    }
  ]
}
```

### 2. Resource-Based Restrictions
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "lambda:*",
      "Resource": [
        "arn:aws:lambda:*:*:function:myapp-*",
        "arn:aws:lambda:*:*:function:*-dev-*",
        "arn:aws:lambda:*:*:function:*-staging-*",
        "arn:aws:lambda:*:*:function:*-production-*"
      ]
    }
  ]
}
```

### 3. Time-Based Access
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "DateGreaterThan": {
          "aws:CurrentTime": "2024-01-01T00:00:00Z"
        },
        "DateLessThan": {
          "aws:CurrentTime": "2024-12-31T23:59:59Z"
        }
      }
    }
  ]
}
```

### 4. IP-Based Restrictions
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "IpAddress": {
          "aws:SourceIp": [
            "203.0.113.0/24",
            "198.51.100.0/24"
          ]
        }
      }
    }
  ]
}
```

## 🌍 Multi-Region Permissions

### Cross-Region Deployment
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:*",
        "lambda:*",
        "ec2:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": [
            "us-east-1",
            "ap-southeast-1",
            "ap-northeast-1"
          ]
        }
      }
    }
  ]
}
```

## 🔍 Permission Testing

### 1. Test Basic Permissions
```bash
# Test AWS CLI access
aws sts get-caller-identity

# Test RDS permissions
aws rds describe-db-instances --max-items 1

# Test Lambda permissions
aws lambda list-functions --max-items 1

# Test EC2 permissions
aws ec2 describe-vpcs --max-items 1
```

### 2. Use IAM Policy Simulator
```bash
# Simulate policy
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT_ID:user/deployment-user \
  --action-names rds:CreateDBInstance \
  --resource-arns "*"
```

### 3. Automated Permission Check
```bash
# Use our validation script
./scripts/utilities/validate-aws-cli.sh permissions
```

## 🚨 Common Permission Issues

### Issue 1: "Access Denied" on RDS
```bash
# Check RDS permissions
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT_ID:user/deployment-user \
  --action-names rds:CreateDBInstance,rds:CreateDBSubnetGroup \
  --resource-arns "*"
```

### Issue 2: Lambda Role Cannot Be Assumed
```bash
# Check trust policy
aws iam get-role --role-name myapp-production-lambda-role \
  --query 'Role.AssumeRolePolicyDocument'

# Update trust policy if needed
aws iam update-assume-role-policy \
  --role-name myapp-production-lambda-role \
  --policy-document file://lambda-trust-policy.json
```

### Issue 3: VPC Creation Failed
```bash
# Check VPC limits
aws ec2 describe-account-attributes \
  --attribute-names max-vpcs

# Check current VPC count
aws ec2 describe-vpcs --query 'length(Vpcs)'
```

## 📊 Permission Monitoring

### 1. CloudTrail Setup
```bash
# Create CloudTrail for API monitoring
aws cloudtrail create-trail \
  --name deployment-automation-trail \
  --s3-bucket-name my-cloudtrail-bucket

aws cloudtrail start-logging \
  --name deployment-automation-trail
```

### 2. CloudWatch Alarms
```bash
# Create alarm for failed API calls
aws cloudwatch put-metric-alarm \
  --alarm-name "DeploymentPermissionFailures" \
  --alarm-description "Alert on permission failures" \
  --metric-name ErrorCount \
  --namespace AWS/CloudTrail \
  --statistic Sum \
  --period 300 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold
```

## 🔄 Permission Rotation

### 1. Access Key Rotation
```bash
# Create new access key
NEW_KEY=$(aws iam create-access-key --user-name deployment-user)

# Update AWS CLI configuration
aws configure set aws_access_key_id NEW_ACCESS_KEY --profile deployment
aws configure set aws_secret_access_key NEW_SECRET_KEY --profile deployment

# Test new key
aws sts get-caller-identity --profile deployment

# Delete old key
aws iam delete-access-key --user-name deployment-user --access-key-id OLD_ACCESS_KEY
```

### 2. Role Rotation
```bash
# Create new role
aws iam create-role \
  --role-name AWSDeploymentAutomationRole-v2 \
  --assume-role-policy-document file://trust-policy.json

# Copy policies from old role
OLD_POLICIES=$(aws iam list-attached-role-policies \
  --role-name AWSDeploymentAutomationRole \
  --query 'AttachedPolicies[].PolicyArn' \
  --output text)

for policy in $OLD_POLICIES; do
  aws iam attach-role-policy \
    --role-name AWSDeploymentAutomationRole-v2 \
    --policy-arn $policy
done
```

## 📋 Environment-Specific Permissions

### Development Environment
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:*",
        "lambda:*",
        "ec2:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:RequestTag/Environment": "dev*"
        }
      }
    }
  ]
}
```

### Production Environment
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:CreateDBInstance",
        "rds:ModifyDBInstance",
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/Environment": "production"
        }
      }
    },
    {
      "Effect": "Deny",
      "Action": [
        "rds:DeleteDBInstance",
        "lambda:DeleteFunction"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/Environment": "production"
        }
      }
    }
  ]
}
```

## 🔧 Troubleshooting Commands

### Debug Permission Issues
```bash
# Check current user/role
aws sts get-caller-identity

# List attached policies
aws iam list-attached-user-policies --user-name deployment-user

# Get policy document
aws iam get-policy-version \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/PolicyName \
  --version-id v1

# Check CloudTrail for denied actions
aws logs filter-log-events \
  --log-group-name CloudTrail/DeploymentAutomation \
  --filter-pattern "ERROR Denied"
```

---

**Lưu ý**: Luôn tuân thủ nguyên tắc "least privilege" và thường xuyên review permissions để đảm bảo bảo mật.