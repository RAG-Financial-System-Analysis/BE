# Database Seeding Scripts

This directory contains scripts for seeding the RAG System database with initial data.

## Overview

The seeding process has been redesigned to replace the problematic DbInitializer with a more reliable shell-based approach.

## Scripts

### Main Scripts

- **`seed-all-data.sh`** - Main entry point for complete database seeding
- **`seed-users-complete.sh`** - Comprehensive user seeding with Cognito integration
- **`test-seed.sh`** - Test prerequisites before seeding

### Password Management Scripts

- **`set-admin-password.sh`** - Set permanent password for admin user in Cognito
- **`set-analyst-password.sh`** - Set permanent password for analyst user in Cognito

### Legacy Scripts

- **`trigger-db-initializer.sh`** - Legacy DbInitializer trigger (may fail)

## Usage

### Complete Database Seeding

```bash
# Full seeding (roles, analytics types, users)
bash scripts/database/seed-all-data.sh \
  --user-pool-id your-cognito-user-pool-id \
  --client-id your-cognito-client-id

# Skip user creation (roles and analytics only)
bash scripts/database/seed-all-data.sh \
  --user-pool-id your-cognito-user-pool-id \
  --client-id your-cognito-client-id \
  --skip-users

# Database only (skip Cognito)
bash scripts/database/seed-all-data.sh \
  --user-pool-id your-cognito-user-pool-id \
  --client-id your-cognito-client-id \
  --skip-cognito
```

### User-Only Seeding

```bash
# Create users in both Cognito and Database
bash scripts/database/seed-users-complete.sh \
  --user-pool-id your-cognito-user-pool-id \
  --client-id your-cognito-client-id

# Database users only
bash scripts/database/seed-users-complete.sh \
  --user-pool-id your-cognito-user-pool-id \
  --client-id your-cognito-client-id \
  --skip-cognito
```

### Password Management

```bash
# Set permanent passwords for users
bash scripts/database/set-admin-password.sh
bash scripts/database/set-analyst-password.sh
```

### Testing Prerequisites

```bash
# Test database connection and AWS CLI
bash scripts/database/test-seed.sh
```

## Seeded Data

### Roles
- **Admin** (ID: 99999999-9999-9999-9999-999999999999) - System Administrator
- **Analyst** (ID: 66666666-6666-6666-6666-666666666666) - Financial Analyst

### Analytics Types
- **RISK** - Risk Analysis (Phân tích rủi ro tài chính)
- **TREND** - Trend Analysis (Phân tích xu hướng phát triển)
- **COMPARISON** - Comparative Analysis (So sánh giữa các công ty)
- **OPPORTUNITY** - Opportunity Analysis (Phân tích cơ hội đầu tư)
- **EXECUTIVE** - Executive Summary (Tóm tắt tổng quan)

### Default Users
- **admin@yourdomain.com** - Admin role, Password: `YourSecureAdminPassword`
- **analyst@yourdomain.com** - Analyst role, Password: `YourSecureAnalystPassword`

## Configuration

Scripts read configuration from `../deployment-config.env`:

```bash
# AWS Configuration
AWS_USER_POOL_ID=your-cognito-user-pool-id
AWS_CLIENT_ID=your-cognito-client-id
AWS_DEFAULT_REGION=ap-southeast-1

# Database Configuration
DB_HOST=your-rds-endpoint.region.rds.amazonaws.com
DB_PORT=5432
DB_NAME=RAGSystem
DB_USERNAME=postgres
DB_PASSWORD=your-db-password

# User Configuration
ADMIN_USER_EMAIL=admin@yourdomain.com
ADMIN_USER_PASSWORD=YourSecureAdminPassword
ADMIN_USER_FULLNAME=System Admin

ANALYST_USER_EMAIL=analyst@yourdomain.com
ANALYST_USER_PASSWORD=YourSecureAnalystPassword
ANALYST_USER_FULLNAME=System Analyst
```

## Prerequisites

- AWS CLI configured with appropriate permissions
- PostgreSQL client (`psql`) installed
- Access to RDS database
- Access to Cognito User Pool

## Troubleshooting

### Common Issues

1. **Database connection failed**
   - Check RDS instance is running
   - Verify security group allows connections
   - Confirm database credentials

2. **AWS CLI errors**
   - Run `aws configure` to set credentials
   - Verify IAM permissions for Cognito and RDS

3. **User already exists errors**
   - Scripts handle conflicts gracefully with `ON CONFLICT DO NOTHING`
   - Check existing users before seeding

### Verification

After seeding, verify results:

```bash
# Check database users
PGPASSWORD=your-db-password psql -h your-rds-endpoint.region.rds.amazonaws.com \
  -d RAGSystem -U postgres -p 5432 \
  -c "SELECT u.email, u.fullname, r.name as role FROM users u JOIN roles r ON u.roleid = r.id;"

# Check Cognito users
aws cognito-idp list-users --user-pool-id your-cognito-user-pool-id --region ap-southeast-1
```

## Migration from DbInitializer

If DbInitializer is failing:

1. Run `test-seed.sh` to verify prerequisites
2. Use `seed-all-data.sh` for complete seeding
3. Verify results with database queries
4. Update deployment scripts to use new seeding approach

This approach provides more reliable seeding with better error handling and logging.