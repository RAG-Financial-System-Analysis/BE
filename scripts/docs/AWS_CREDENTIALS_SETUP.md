# AWS Credentials Setup Guide

## Quick Setup (One-Time Only)

You only need to configure AWS credentials **ONCE** on your machine:

```bash
aws configure
```

This will prompt you for:
- AWS Access Key ID
- AWS Secret Access Key  
- Default region (e.g., `ap-southeast-1`)
- Default output format (just press Enter for default)

## Where Credentials Are Saved

After running `aws configure`, your credentials are permanently saved to:

- **`~/.aws/credentials`** - Contains your access keys
- **`~/.aws/config`** - Contains your default region and other settings

## No Need to Ignore These Files

These files are meant to be persistent on your machine. **Do NOT add them to .gitignore** - they stay on your local machine only.

## Automatic Detection

Our deployment scripts automatically detect AWS credentials from multiple sources:

1. **AWS CLI Configuration** (recommended)
   - `~/.aws/credentials` 
   - `~/.aws/config`

2. **Environment Variables**
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_DEFAULT_REGION`

3. **AWS Profiles**
   - `AWS_PROFILE` environment variable

4. **IAM Roles** (when running on EC2)

## Verification

To verify your credentials are working:

```bash
aws sts get-caller-identity
```

This should return your AWS account information.

## Security Best Practices

- Rotate access keys every 90 days
- Use least privilege permissions
- Enable MFA (Multi-Factor Authentication) if possible
- Never commit credentials to version control

## Troubleshooting

If you get credential errors:

1. **First time setup**: Run `aws configure`
2. **Existing setup**: Check if credentials expired
3. **Multiple profiles**: Set `AWS_PROFILE` environment variable
4. **Permission issues**: Verify IAM user has required permissions

## Required AWS Permissions

Your AWS user needs these permissions for deployment:

- RDS: Create, modify, delete instances
- Lambda: Create, update, invoke functions
- API Gateway: Create, deploy APIs
- IAM: Create roles and policies
- CloudWatch: Create log groups
- S3: Create buckets (for Lambda deployment packages)