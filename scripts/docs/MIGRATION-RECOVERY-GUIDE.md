# Migration Recovery Guide - Hướng dẫn khôi phục Migration

Tài liệu này cung cấp hướng dẫn chi tiết về cách khôi phục từ các lỗi migration và thực hiện rollback an toàn.

## 📋 Tổng quan

Entity Framework migrations có thể gặp sự cố do nhiều nguyên nhân:
- Connection string không đúng
- Database schema conflicts
- Data integrity issues
- Network connectivity problems
- Permission issues

## 🔍 Chẩn đoán Migration Issues

### 1. Kiểm tra Migration Status
```bash
# Check current migration status
./scripts/migration/run-migrations.sh --dry-run --verbose

# Connect to database và check migration history
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "SELECT * FROM \"__EFMigrationsHistory\" ORDER BY \"MigrationId\";"
```

### 2. Validate Database Connection
```bash
# Test basic connectivity
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "SELECT version();"

# Test from Lambda environment
aws lambda invoke \
  --function-name myapp-production-api \
  --payload '{"action": "test-db-connection"}' \
  response.json
```

### 3. Check Migration Files
```bash
# List available migrations
find . -name "*Migrations*" -type f -name "*.cs" | sort

# Check for migration conflicts
grep -r "CreateTable\|DropTable" Migrations/
```

## 🚨 Common Migration Failures

### Failure 1: "Database does not exist"

**Triệu chứng:**
```
Npgsql.PostgresException: 3D000: database "appdb" does not exist
```

**Giải pháp:**
```bash
# 1. Connect to postgres database
psql -h $RDS_ENDPOINT -U dbadmin -d postgres

# 2. Create database
CREATE DATABASE appdb;
\q

# 3. Run migrations again
./scripts/migration/run-migrations.sh --environment production
```

### Failure 2: "Table already exists"

**Triệu chứng:**
```
Npgsql.PostgresException: 42P07: relation "Users" already exists
```

**Giải pháp:**
```bash
# Option 1: Mark migration as applied (if table structure matches)
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "
INSERT INTO \"__EFMigrationsHistory\" (\"MigrationId\", \"ProductVersion\") 
VALUES ('20241208143022_CreateUsersTable', '8.0.0');"

# Option 2: Drop existing table (CAUTION: Data loss)
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "DROP TABLE IF EXISTS \"Users\";"

# Option 3: Rename existing table
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "ALTER TABLE \"Users\" RENAME TO \"Users_backup\";"
```

### Failure 3: "Foreign key constraint violation"

**Triệu chứng:**
```
Npgsql.PostgresException: 23503: insert or update on table violates foreign key constraint
```

**Giải pháp:**
```bash
# 1. Check foreign key constraints
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "
SELECT 
    tc.table_name, 
    kcu.column_name, 
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name 
FROM 
    information_schema.table_constraints AS tc 
    JOIN information_schema.key_column_usage AS kcu
      ON tc.constraint_name = kcu.constraint_name
    JOIN information_schema.constraint_column_usage AS ccu
      ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY';"

# 2. Temporarily disable foreign key checks (PostgreSQL doesn't support this directly)
# Instead, drop and recreate constraints
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "
ALTER TABLE child_table DROP CONSTRAINT fk_constraint_name;
-- Run your migration
ALTER TABLE child_table ADD CONSTRAINT fk_constraint_name 
    FOREIGN KEY (column_name) REFERENCES parent_table(id);"
```

### Failure 4: "Connection timeout"

**Triệu chứng:**
```
System.TimeoutException: Timeout expired. The timeout period elapsed prior to completion
```

**Giải pháp:**
```bash
# 1. Increase connection timeout
export CONNECTION_TIMEOUT=300

# 2. Check RDS instance status
aws rds describe-db-instances --db-instance-identifier myapp-production-db \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Available:AvailabilityZone}'

# 3. Check security groups
RDS_SG=$(aws rds describe-db-instances \
  --db-instance-identifier myapp-production-db \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)

aws ec2 describe-security-groups --group-ids $RDS_SG

# 4. Test connectivity from Lambda
./scripts/migration/run-migrations.sh --test-connection-only
```

## 🔄 Migration Rollback Procedures

### 1. Safe Rollback (Recommended)

#### Step 1: Backup Current State
```bash
# Create database snapshot
aws rds create-db-snapshot \
  --db-instance-identifier myapp-production-db \
  --db-snapshot-identifier myapp-production-backup-$(date +%Y%m%d-%H%M%S)

# Export current schema
pg_dump -h $RDS_ENDPOINT -U dbadmin -d appdb --schema-only > schema-backup.sql

# Export data (if needed)
pg_dump -h $RDS_ENDPOINT -U dbadmin -d appdb --data-only > data-backup.sql
```

#### Step 2: Identify Target Migration
```bash
# List migration history
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "
SELECT \"MigrationId\", \"ProductVersion\" 
FROM \"__EFMigrationsHistory\" 
ORDER BY \"MigrationId\";"

# Choose target migration (the one you want to rollback TO)
TARGET_MIGRATION="20241208143022_InitialCreate"
```

#### Step 3: Execute Rollback
```bash
# Use our rollback script
./scripts/migration/rollback-migrations.sh \
  --target-migration $TARGET_MIGRATION \
  --environment production \
  --backup-first

# Or manual rollback
dotnet ef database update $TARGET_MIGRATION \
  --connection "Host=$RDS_ENDPOINT;Database=appdb;Username=dbadmin;Password=$DB_PASSWORD"
```

### 2. Emergency Rollback (Fast Recovery)

#### Complete Database Restore
```bash
# 1. Stop application traffic
aws lambda update-function-configuration \
  --function-name myapp-production-api \
  --environment Variables='{MAINTENANCE_MODE=true}'

# 2. Restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier myapp-production-db-restored \
  --db-snapshot-identifier myapp-production-backup-20241208-143022

# 3. Update connection strings
./scripts/deployment/update-lambda-environment.sh \
  --function-name myapp-production-api \
  --db-endpoint myapp-production-db-restored.xyz.ap-southeast-1.rds.amazonaws.com

# 4. Re-enable application
aws lambda update-function-configuration \
  --function-name myapp-production-api \
  --environment Variables='{MAINTENANCE_MODE=false}'
```

### 3. Selective Rollback (Specific Tables)

```bash
# 1. Identify affected tables
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "
SELECT tablename FROM pg_tables WHERE schemaname = 'public';"

# 2. Backup specific tables
pg_dump -h $RDS_ENDPOINT -U dbadmin -d appdb -t Users -t Orders > tables-backup.sql

# 3. Drop and recreate specific tables
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "
DROP TABLE IF EXISTS \"Users\" CASCADE;
DROP TABLE IF EXISTS \"Orders\" CASCADE;"

# 4. Restore from backup
psql -h $RDS_ENDPOINT -U dbadmin -d appdb < tables-backup.sql

# 5. Update migration history
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "
DELETE FROM \"__EFMigrationsHistory\" 
WHERE \"MigrationId\" > '$TARGET_MIGRATION';"
```

## 🛠️ Advanced Recovery Techniques

### 1. Migration Repair

#### Fix Corrupted Migration History
```bash
# 1. Check for inconsistencies
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "
SELECT 
    m.\"MigrationId\",
    CASE 
        WHEN t.table_name IS NOT NULL THEN 'Table exists'
        ELSE 'Table missing'
    END as status
FROM \"__EFMigrationsHistory\" m
LEFT JOIN information_schema.tables t 
    ON t.table_name = REPLACE(SPLIT_PART(m.\"MigrationId\", '_', 2), 'Create', '')
WHERE t.table_schema = 'public' OR t.table_schema IS NULL;"

# 2. Remove invalid migration entries
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "
DELETE FROM \"__EFMigrationsHistory\" 
WHERE \"MigrationId\" = 'INVALID_MIGRATION_ID';"

# 3. Add missing migration entries
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "
INSERT INTO \"__EFMigrationsHistory\" (\"MigrationId\", \"ProductVersion\") 
VALUES ('20241208143022_MissingMigration', '8.0.0');"
```

#### Rebuild Migration History
```bash
# 1. Backup current data
pg_dump -h $RDS_ENDPOINT -U dbadmin -d appdb --data-only > data-backup.sql

# 2. Drop migration history table
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "DROP TABLE \"__EFMigrationsHistory\";"

# 3. Run initial migration
dotnet ef database update \
  --connection "Host=$RDS_ENDPOINT;Database=appdb;Username=dbadmin;Password=$DB_PASSWORD"

# 4. Restore data if needed
psql -h $RDS_ENDPOINT -U dbadmin -d appdb < data-backup.sql
```

### 2. Data Migration Recovery

#### Handle Data Loss During Migration
```bash
# 1. Check for data backup
ls -la ./migration-backups/

# 2. Restore specific data
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "
COPY \"Users\" FROM '/path/to/users-backup.csv' 
WITH (FORMAT csv, HEADER true);"

# 3. Verify data integrity
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "
SELECT COUNT(*) as total_users FROM \"Users\";
SELECT COUNT(*) as users_with_email FROM \"Users\" WHERE \"Email\" IS NOT NULL;"
```

#### Fix Data Type Mismatches
```bash
# 1. Identify type mismatches
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "
SELECT column_name, data_type, is_nullable
FROM information_schema.columns 
WHERE table_name = 'Users' AND table_schema = 'public';"

# 2. Fix data types
psql -h $RDS_ENDPOINT -U dbadmin -d appdb -c "
ALTER TABLE \"Users\" 
ALTER COLUMN \"CreatedAt\" TYPE timestamp with time zone 
USING \"CreatedAt\"::timestamp with time zone;"
```

## 🔧 Automated Recovery Scripts

### 1. Migration Health Check Script
```bash
#!/bin/bash
# scripts/migration/health-check.sh

set -euo pipefail

source "$(dirname "$0")/../utilities/logging.sh"

check_migration_health() {
    local environment="$1"
    local connection_string="$2"
    
    log_info "Checking migration health for $environment"
    
    # Check database connectivity
    if ! psql "$connection_string" -c "SELECT 1;" &>/dev/null; then
        log_error "Database connection failed"
        return 1
    fi
    
    # Check migration table exists
    if ! psql "$connection_string" -c "SELECT 1 FROM \"__EFMigrationsHistory\" LIMIT 1;" &>/dev/null; then
        log_error "Migration history table not found"
        return 1
    fi
    
    # Check for orphaned migrations
    local orphaned_count=$(psql "$connection_string" -t -c "
        SELECT COUNT(*) FROM \"__EFMigrationsHistory\" m
        LEFT JOIN information_schema.tables t 
            ON t.table_name = REPLACE(SPLIT_PART(m.\"MigrationId\", '_', 2), 'Create', '')
        WHERE t.table_name IS NULL AND m.\"MigrationId\" LIKE '%Create%';" | tr -d ' ')
    
    if [ "$orphaned_count" -gt 0 ]; then
        log_warn "Found $orphaned_count orphaned migrations"
    fi
    
    log_success "Migration health check passed"
    return 0
}

# Usage
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_migration_health "$1" "$2"
fi
```

### 2. Automatic Backup Before Migration
```bash
#!/bin/bash
# scripts/migration/backup-before-migration.sh

set -euo pipefail

source "$(dirname "$0")/../utilities/logging.sh"

backup_before_migration() {
    local environment="$1"
    local db_identifier="$2"
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local snapshot_id="${db_identifier}-pre-migration-${timestamp}"
    
    log_info "Creating backup snapshot: $snapshot_id"
    
    # Create RDS snapshot
    aws rds create-db-snapshot \
        --db-instance-identifier "$db_identifier" \
        --db-snapshot-identifier "$snapshot_id"
    
    # Wait for snapshot completion
    log_info "Waiting for snapshot to complete..."
    aws rds wait db-snapshot-completed \
        --db-snapshot-identifier "$snapshot_id"
    
    log_success "Backup snapshot created: $snapshot_id"
    echo "$snapshot_id"
}

# Usage
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    backup_before_migration "$1" "$2"
fi
```

### 3. Migration Recovery Automation
```bash
#!/bin/bash
# scripts/migration/auto-recovery.sh

set -euo pipefail

source "$(dirname "$0")/../utilities/logging.sh"

auto_recover_migration() {
    local environment="$1"
    local error_type="$2"
    local connection_string="$3"
    
    log_info "Starting automatic recovery for $error_type"
    
    case "$error_type" in
        "connection_timeout")
            log_info "Retrying with increased timeout"
            export CONNECTION_TIMEOUT=600
            ./scripts/migration/run-migrations.sh --environment "$environment" --retry
            ;;
        "table_exists")
            log_info "Attempting to sync migration history"
            sync_migration_history "$connection_string"
            ;;
        "foreign_key_violation")
            log_info "Attempting to resolve foreign key issues"
            resolve_foreign_key_issues "$connection_string"
            ;;
        *)
            log_error "Unknown error type: $error_type"
            return 1
            ;;
    esac
}

sync_migration_history() {
    local connection_string="$1"
    
    # Get list of existing tables
    local existing_tables=$(psql "$connection_string" -t -c "
        SELECT tablename FROM pg_tables WHERE schemaname = 'public';" | tr -d ' ')
    
    # Check which migrations should be marked as applied
    for table in $existing_tables; do
        local migration_pattern="%Create${table}%"
        psql "$connection_string" -c "
            INSERT INTO \"__EFMigrationsHistory\" (\"MigrationId\", \"ProductVersion\")
            SELECT m.\"MigrationId\", '8.0.0'
            FROM (VALUES ('$(find_migration_for_table "$table")')) AS m(\"MigrationId\")
            WHERE NOT EXISTS (
                SELECT 1 FROM \"__EFMigrationsHistory\" 
                WHERE \"MigrationId\" = m.\"MigrationId\"
            );" || true
    done
}

# Usage
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    auto_recover_migration "$1" "$2" "$3"
fi
```

## 📊 Migration Monitoring

### 1. CloudWatch Metrics
```bash
# Create custom metric for migration success/failure
aws cloudwatch put-metric-data \
  --namespace "DeploymentAutomation/Migrations" \
  --metric-data MetricName=MigrationSuccess,Value=1,Unit=Count

aws cloudwatch put-metric-data \
  --namespace "DeploymentAutomation/Migrations" \
  --metric-data MetricName=MigrationFailure,Value=1,Unit=Count
```

### 2. Migration Alerts
```bash
# Create CloudWatch alarm for migration failures
aws cloudwatch put-metric-alarm \
  --alarm-name "MigrationFailures" \
  --alarm-description "Alert on migration failures" \
  --metric-name MigrationFailure \
  --namespace "DeploymentAutomation/Migrations" \
  --statistic Sum \
  --period 300 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions arn:aws:sns:ap-southeast-1:ACCOUNT_ID:migration-alerts
```

## 🚨 Emergency Procedures

### Complete System Recovery
```bash
#!/bin/bash
# Emergency recovery procedure

# 1. Stop all traffic
aws lambda update-function-configuration \
  --function-name myapp-production-api \
  --environment Variables='{MAINTENANCE_MODE=true}'

# 2. Restore from latest known good snapshot
LATEST_SNAPSHOT=$(aws rds describe-db-snapshots \
  --db-instance-identifier myapp-production-db \
  --query 'DBSnapshots[?Status==`available`]|sort_by(@, &SnapshotCreateTime)[-1].DBSnapshotIdentifier' \
  --output text)

aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier myapp-production-db-emergency \
  --db-snapshot-identifier "$LATEST_SNAPSHOT"

# 3. Wait for restore completion
aws rds wait db-instance-available \
  --db-instance-identifier myapp-production-db-emergency

# 4. Update connection strings
NEW_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier myapp-production-db-emergency \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

./scripts/deployment/update-lambda-environment.sh \
  --function-name myapp-production-api \
  --db-endpoint "$NEW_ENDPOINT"

# 5. Re-enable traffic
aws lambda update-function-configuration \
  --function-name myapp-production-api \
  --environment Variables='{MAINTENANCE_MODE=false}'

echo "Emergency recovery completed. New DB endpoint: $NEW_ENDPOINT"
```

## 📚 Best Practices

### 1. Pre-Migration Checklist
- [ ] Create database backup/snapshot
- [ ] Test migration on staging environment
- [ ] Verify rollback procedure
- [ ] Check database disk space
- [ ] Validate connection strings
- [ ] Review migration scripts for potential issues

### 2. During Migration
- [ ] Monitor migration progress
- [ ] Watch for error messages
- [ ] Check database performance metrics
- [ ] Verify application functionality

### 3. Post-Migration
- [ ] Validate data integrity
- [ ] Run application tests
- [ ] Monitor performance metrics
- [ ] Document any issues encountered
- [ ] Clean up old backups (after verification)

---

**Lưu ý**: Luôn test migration procedures trên staging environment trước khi áp dụng lên production. Giữ backup và có kế hoạch rollback rõ ràng.