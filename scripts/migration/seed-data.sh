#!/bin/bash

# =============================================================================
# Database Seeding Script
# =============================================================================
# This script seeds the database with initial data including roles, users,
# and analytics types. It implements idempotent seeding logic to prevent
# duplicate data and includes data validation.
#
# Usage:
#   ./seed-data.sh [OPTIONS]
#
# Options:
#   --connection-string <string>  Database connection string (required)
#   --project-path <path>         Path to the .NET project (default: code/TestDeployLambda/BE)
#   --startup-project <path>      Startup project path (default: RAG.APIs)
#   --environment <env>           Environment (development|staging|production)
#   --admin-email <email>         Admin user email (default: admin@rag.com)
#   --admin-password <password>   Admin user password (default: Admin@123!!)
#   --analyst-email <email>       Analyst user email (default: analyst@rag.com)
#   --analyst-password <password> Analyst user password (default: Analyst@123!!)
#   --skip-cognito               Skip Cognito user creation
#   --dry-run                    Show what would be executed without running
#   --verbose                    Enable verbose logging
#   --help                       Show this help message
#
# Requirements: 2.2
# =============================================================================

set -euo pipefail

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../utilities/logging.sh"
source "${SCRIPT_DIR}/../utilities/error-handling.sh"

# Default configuration
DEFAULT_PROJECT_PATH="code/TestDeployLambda/BE"
DEFAULT_STARTUP_PROJECT="RAG.APIs"
DEFAULT_ENVIRONMENT="production"
DEFAULT_ADMIN_EMAIL="admin@rag.com"
DEFAULT_ADMIN_PASSWORD="Admin@123!!"
DEFAULT_ANALYST_EMAIL="analyst@rag.com"
DEFAULT_ANALYST_PASSWORD="Analyst@123!!"

CONNECTION_STRING=""
PROJECT_PATH=""
STARTUP_PROJECT=""
ENVIRONMENT=""
ADMIN_EMAIL=""
ADMIN_PASSWORD=""
ANALYST_EMAIL=""
ANALYST_PASSWORD=""
SKIP_COGNITO=false
DRY_RUN=false
VERBOSE=false

# =============================================================================
# Helper Functions
# =============================================================================

show_help() {
    cat << EOF
Database Seeding Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --connection-string <string>  Database connection string (required)
    --project-path <path>         Path to the .NET project (default: $DEFAULT_PROJECT_PATH)
    --startup-project <path>      Startup project path (default: $DEFAULT_STARTUP_PROJECT)
    --environment <env>           Environment (development|staging|production, default: $DEFAULT_ENVIRONMENT)
    --admin-email <email>         Admin user email (default: $DEFAULT_ADMIN_EMAIL)
    --admin-password <password>   Admin user password (default: $DEFAULT_ADMIN_PASSWORD)
    --analyst-email <email>       Analyst user email (default: $DEFAULT_ANALYST_EMAIL)
    --analyst-password <password> Analyst user password (default: $DEFAULT_ANALYST_PASSWORD)
    --skip-cognito               Skip Cognito user creation (useful for local development)
    --dry-run                    Show what would be executed without running
    --verbose                    Enable verbose logging
    --help                       Show this help message

EXAMPLES:
    # Seed with default users
    $0 --connection-string "Host=mydb.amazonaws.com;Port=5432;Database=RAG-System;Username=postgres;Password=mypass"
    
    # Seed with custom admin credentials
    $0 --connection-string "..." --admin-email "admin@company.com" --admin-password "SecurePass123!"
    
    # Dry run to see what would be seeded
    $0 --connection-string "..." --dry-run
    
    # Skip Cognito for local development
    $0 --connection-string "..." --skip-cognito

SEEDED DATA:
    - System roles (Admin, Analyst)
    - Analytics types (Risk, Trend, Comparison, Opportunity, Executive)
    - Default users (Admin and Analyst with Cognito integration)

REQUIREMENTS:
    - .NET 10 SDK installed
    - Database with applied migrations
    - AWS Cognito configuration (unless --skip-cognito is used)
    - Valid connection string with proper permissions

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --connection-string)
                CONNECTION_STRING="$2"
                shift 2
                ;;
            --project-path)
                PROJECT_PATH="$2"
                shift 2
                ;;
            --startup-project)
                STARTUP_PROJECT="$2"
                shift 2
                ;;
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --admin-email)
                ADMIN_EMAIL="$2"
                shift 2
                ;;
            --admin-password)
                ADMIN_PASSWORD="$2"
                shift 2
                ;;
            --analyst-email)
                ANALYST_EMAIL="$2"
                shift 2
                ;;
            --analyst-password)
                ANALYST_PASSWORD="$2"
                shift 2
                ;;
            --skip-cognito)
                SKIP_COGNITO=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Set defaults
    PROJECT_PATH="${PROJECT_PATH:-$DEFAULT_PROJECT_PATH}"
    STARTUP_PROJECT="${STARTUP_PROJECT:-$DEFAULT_STARTUP_PROJECT}"
    ENVIRONMENT="${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}"
    ADMIN_EMAIL="${ADMIN_EMAIL:-$DEFAULT_ADMIN_EMAIL}"
    ADMIN_PASSWORD="${ADMIN_PASSWORD:-$DEFAULT_ADMIN_PASSWORD}"
    ANALYST_EMAIL="${ANALYST_EMAIL:-$DEFAULT_ANALYST_EMAIL}"
    ANALYST_PASSWORD="${ANALYST_PASSWORD:-$DEFAULT_ANALYST_PASSWORD}"

    # Validate required parameters
    if [[ -z "$CONNECTION_STRING" ]]; then
        log_error "Connection string is required. Use --connection-string option."
        show_help
        exit 1
    fi

    # Validate environment
    if [[ ! "$ENVIRONMENT" =~ ^(development|staging|production)$ ]]; then
        log_error "Invalid environment: $ENVIRONMENT. Must be development, staging, or production."
        exit 1
    fi
}

validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check if .NET SDK is installed
    if ! command -v dotnet &> /dev/null; then
        log_error ".NET SDK is not installed or not in PATH"
        log_error "Please install .NET 10 SDK: https://dotnet.microsoft.com/download"
        exit 1
    fi

    # Check .NET version
    local dotnet_version
    dotnet_version=$(dotnet --version)
    log_info "Found .NET SDK version: $dotnet_version"

    # Check if project path exists
    if [[ ! -d "$PROJECT_PATH" ]]; then
        log_error "Project path does not exist: $PROJECT_PATH"
        exit 1
    fi

    # Check if startup project exists
    local startup_project_path="$PROJECT_PATH/$STARTUP_PROJECT"
    if [[ ! -d "$startup_project_path" ]]; then
        log_error "Startup project does not exist: $startup_project_path"
        exit 1
    fi

    # Check if Infrastructure project exists (contains DbContext)
    local infrastructure_project="$PROJECT_PATH/RAG.Infrastructure"
    if [[ ! -d "$infrastructure_project" ]]; then
        log_error "Infrastructure project does not exist: $infrastructure_project"
        exit 1
    fi

    log_success "Prerequisites validation completed"
}

validate_database_connection() {
    log_info "Validating database connection..."

    # Test database connectivity using a simple query
    local test_query="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';"
    
    # Extract database details from connection string
    local host port database username password
    
    if [[ $CONNECTION_STRING =~ Host=([^;]+) ]]; then
        host="${BASH_REMATCH[1]}"
    else
        log_error "Could not extract host from connection string"
        return 1
    fi

    if [[ $CONNECTION_STRING =~ Port=([^;]+) ]]; then
        port="${BASH_REMATCH[1]}"
    else
        port="5432"
    fi

    if [[ $CONNECTION_STRING =~ Database=([^;]+) ]]; then
        database="${BASH_REMATCH[1]}"
    else
        log_error "Could not extract database name from connection string"
        return 1
    fi

    if [[ $CONNECTION_STRING =~ Username=([^;]+) ]]; then
        username="${BASH_REMATCH[1]}"
    else
        log_error "Could not extract username from connection string"
        return 1
    fi

    if [[ $CONNECTION_STRING =~ Password=([^;]+) ]]; then
        password="${BASH_REMATCH[1]}"
    fi

    log_info "Testing connection to: $host:$port/$database as $username"

    # Test connectivity with psql if available
    if command -v psql &> /dev/null; then
        export PGPASSWORD="$password"
        
        if timeout 10 psql -h "$host" -p "$port" -U "$username" -d "$database" -c "$test_query" &> /dev/null; then
            log_success "Database connectivity test passed"
        else
            log_error "Database connectivity test failed"
            unset PGPASSWORD
            return 1
        fi
        
        unset PGPASSWORD
    else
        log_warning "psql not available, skipping direct connectivity test"
    fi
}

validate_database_schema() {
    log_info "Validating database schema..."

    # Check if required tables exist
    local required_tables=("roles" "users" "analytics_type")
    local host port database username password
    
    # Parse connection string
    if [[ $CONNECTION_STRING =~ Host=([^;]+) ]]; then host="${BASH_REMATCH[1]}"; fi
    if [[ $CONNECTION_STRING =~ Port=([^;]+) ]]; then port="${BASH_REMATCH[1]}"; else port="5432"; fi
    if [[ $CONNECTION_STRING =~ Database=([^;]+) ]]; then database="${BASH_REMATCH[1]}"; fi
    if [[ $CONNECTION_STRING =~ Username=([^;]+) ]]; then username="${BASH_REMATCH[1]}"; fi
    if [[ $CONNECTION_STRING =~ Password=([^;]+) ]]; then password="${BASH_REMATCH[1]}"; fi

    if command -v psql &> /dev/null; then
        export PGPASSWORD="$password"
        
        for table in "${required_tables[@]}"; do
            local table_exists
            table_exists=$(psql -h "$host" -p "$port" -U "$username" -d "$database" \
                -t -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '$table');" 2>/dev/null | xargs)
            
            if [[ "$table_exists" == "t" ]]; then
                log_info "✓ Table '$table' exists"
            else
                log_error "✗ Required table '$table' does not exist"
                log_error "Please run migrations first using run-migrations.sh"
                unset PGPASSWORD
                return 1
            fi
        done
        
        unset PGPASSWORD
        log_success "Database schema validation completed"
    else
        log_warning "psql not available, skipping schema validation"
    fi
}

create_seeding_program() {
    log_info "Creating temporary seeding program..."

    local seeding_program_path="$PROJECT_PATH/SeedingProgram.cs"
    
    cat > "$seeding_program_path" << 'EOF'
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using RAG.Infrastructure.Database;
using Amazon.CognitoIdentityProvider;
using System;
using System.Threading.Tasks;

namespace SeedingProgram
{
    class Program
    {
        static async Task Main(string[] args)
        {
            if (args.Length < 1)
            {
                Console.WriteLine("Usage: dotnet run <connection-string> [admin-email] [admin-password] [analyst-email] [analyst-password] [skip-cognito]");
                Environment.Exit(1);
            }

            var connectionString = args[0];
            var adminEmail = args.Length > 1 ? args[1] : "admin@rag.com";
            var adminPassword = args.Length > 2 ? args[2] : "Admin@123!!";
            var analystEmail = args.Length > 3 ? args[3] : "analyst@rag.com";
            var analystPassword = args.Length > 4 ? args[4] : "Analyst@123!!";
            var skipCognito = args.Length > 5 && args[5].ToLower() == "true";

            try
            {
                // Build configuration
                var configuration = new ConfigurationBuilder()
                    .AddInMemoryCollection(new Dictionary<string, string>
                    {
                        {"ConnectionStrings:DefaultConnection", connectionString},
                        {"AdminUser:Email", adminEmail},
                        {"AdminUser:Password", adminPassword},
                        {"AdminUser:FullName", "System Administrator"},
                        {"AnalystUser:Email", analystEmail},
                        {"AnalystUser:Password", analystPassword},
                        {"AnalystUser:FullName", "System Analyst"},
                        {"AWS:Region", Environment.GetEnvironmentVariable("AWS_REGION") ?? "ap-southeast-1"},
                        {"AWS:UserPoolId", Environment.GetEnvironmentVariable("AWS_USER_POOL_ID") ?? ""},
                        {"AWS:ClientId", Environment.GetEnvironmentVariable("AWS_CLIENT_ID") ?? ""}
                    })
                    .Build();

                // Setup services
                var services = new ServiceCollection();
                
                // Add logging
                services.AddLogging(builder => builder.AddConsole().SetMinimumLevel(LogLevel.Information));
                
                // Add DbContext
                services.AddDbContext<ApplicationDbContext>(options =>
                    options.UseNpgsql(connectionString, x => x.UseVector()));
                
                // Add AWS Cognito if not skipping
                if (!skipCognito)
                {
                    services.AddAWSService<IAmazonCognitoIdentityProvider>();
                }
                else
                {
                    // Add a mock Cognito service for local development
                    services.AddSingleton<IAmazonCognitoIdentityProvider>(provider => null);
                }
                
                services.AddSingleton<IConfiguration>(configuration);
                services.AddScoped<DbInitializer>();

                var serviceProvider = services.BuildServiceProvider();
                
                Console.WriteLine("Starting database seeding...");
                
                // Test database connection
                using (var scope = serviceProvider.CreateScope())
                {
                    var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
                    await context.Database.OpenConnectionAsync();
                    Console.WriteLine("✓ Database connection successful");
                    await context.Database.CloseConnectionAsync();
                }
                
                // Run seeding
                using (var scope = serviceProvider.CreateScope())
                {
                    var initializer = scope.ServiceProvider.GetRequiredService<DbInitializer>();
                    
                    if (skipCognito)
                    {
                        Console.WriteLine("⚠ Skipping Cognito integration (--skip-cognito flag used)");
                    }
                    
                    await initializer.InitializeAsync();
                }
                
                Console.WriteLine("✓ Database seeding completed successfully");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"✗ Seeding failed: {ex.Message}");
                if (ex.InnerException != null)
                {
                    Console.WriteLine($"Inner exception: {ex.InnerException.Message}");
                }
                Environment.Exit(1);
            }
        }
    }
}
EOF

    echo "$seeding_program_path"
}

create_seeding_project() {
    log_info "Creating temporary seeding project..."

    local seeding_project_path="$PROJECT_PATH/SeedingProgram.csproj"
    
    cat > "$seeding_project_path" << EOF
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.EntityFrameworkCore" Version="10.0.0" />
    <PackageReference Include="Microsoft.Extensions.Configuration" Version="8.0.0" />
    <PackageReference Include="Microsoft.Extensions.Configuration.Json" Version="8.0.0" />
    <PackageReference Include="Microsoft.Extensions.DependencyInjection" Version="8.0.0" />
    <PackageReference Include="Microsoft.Extensions.Logging" Version="8.0.0" />
    <PackageReference Include="Microsoft.Extensions.Logging.Console" Version="8.0.0" />
    <PackageReference Include="AWSSDK.Extensions.NETCore.Setup" Version="3.7.301" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="RAG.Infrastructure/RAG.Infrastructure.csproj" />
  </ItemGroup>
</Project>
EOF

    echo "$seeding_project_path"
}

run_seeding() {
    log_info "Running database seeding..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN - Would seed the following data:"
        log_info "  - System roles: Admin, Analyst"
        log_info "  - Analytics types: Risk, Trend, Comparison, Opportunity, Executive"
        log_info "  - Admin user: $ADMIN_EMAIL"
        log_info "  - Analyst user: $ANALYST_EMAIL"
        if [[ "$SKIP_COGNITO" == "true" ]]; then
            log_info "  - Cognito integration: SKIPPED"
        else
            log_info "  - Cognito integration: ENABLED"
        fi
        return 0
    fi

    # Create temporary seeding program and project
    local seeding_program seeding_project
    seeding_program=$(create_seeding_program)
    seeding_project=$(create_seeding_project)

    # Set environment variables for AWS if not skipping Cognito
    if [[ "$SKIP_COGNITO" != "true" ]]; then
        # Try to get AWS configuration from appsettings.json
        local appsettings_file="$PROJECT_PATH/$STARTUP_PROJECT/appsettings.json"
        if [[ -f "$appsettings_file" ]]; then
            log_info "Reading AWS configuration from appsettings.json..."
            
            # Extract AWS configuration using basic text processing
            local aws_region aws_user_pool_id aws_client_id
            aws_region=$(grep -o '"Region"[[:space:]]*:[[:space:]]*"[^"]*"' "$appsettings_file" | cut -d'"' -f4 || echo "")
            aws_user_pool_id=$(grep -o '"UserPoolId"[[:space:]]*:[[:space:]]*"[^"]*"' "$appsettings_file" | cut -d'"' -f4 || echo "")
            aws_client_id=$(grep -o '"ClientId"[[:space:]]*:[[:space:]]*"[^"]*"' "$appsettings_file" | cut -d'"' -f4 || echo "")
            
            if [[ -n "$aws_region" ]]; then
                export AWS_REGION="$aws_region"
                log_info "Set AWS_REGION=$aws_region"
            fi
            
            if [[ -n "$aws_user_pool_id" ]]; then
                export AWS_USER_POOL_ID="$aws_user_pool_id"
                log_info "Set AWS_USER_POOL_ID=$aws_user_pool_id"
            fi
            
            if [[ -n "$aws_client_id" ]]; then
                export AWS_CLIENT_ID="$aws_client_id"
                log_info "Set AWS_CLIENT_ID=$aws_client_id"
            fi
        fi
    fi

    # Run the seeding program
    local seeding_args=("$CONNECTION_STRING" "$ADMIN_EMAIL" "$ADMIN_PASSWORD" "$ANALYST_EMAIL" "$ANALYST_PASSWORD")
    if [[ "$SKIP_COGNITO" == "true" ]]; then
        seeding_args+=("true")
    else
        seeding_args+=("false")
    fi

    log_info "Executing seeding program..."
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Command: dotnet run --project SeedingProgram.csproj -- ${seeding_args[*]}"
    fi

    local seeding_output
    if seeding_output=$(cd "$PROJECT_PATH" && dotnet run --project SeedingProgram.csproj -- "${seeding_args[@]}" 2>&1); then
        log_success "Database seeding completed successfully"
        if [[ "$VERBOSE" == "true" ]]; then
            log_info "Seeding output:"
            echo "$seeding_output" | while IFS= read -r line; do
                log_info "  $line"
            done
        fi
    else
        log_error "Database seeding failed:"
        log_error "$seeding_output"
        return 1
    fi

    # Clean up temporary files
    log_info "Cleaning up temporary files..."
    rm -f "$seeding_program" "$seeding_project"
    
    # Clean up any generated directories
    if [[ -d "$PROJECT_PATH/bin" ]]; then
        rm -rf "$PROJECT_PATH/bin"
    fi
    if [[ -d "$PROJECT_PATH/obj" ]]; then
        rm -rf "$PROJECT_PATH/obj"
    fi
}

verify_seeded_data() {
    log_info "Verifying seeded data..."

    local host port database username password
    
    # Parse connection string
    if [[ $CONNECTION_STRING =~ Host=([^;]+) ]]; then host="${BASH_REMATCH[1]}"; fi
    if [[ $CONNECTION_STRING =~ Port=([^;]+) ]]; then port="${BASH_REMATCH[1]}"; else port="5432"; fi
    if [[ $CONNECTION_STRING =~ Database=([^;]+) ]]; then database="${BASH_REMATCH[1]}"; fi
    if [[ $CONNECTION_STRING =~ Username=([^;]+) ]]; then username="${BASH_REMATCH[1]}"; fi
    if [[ $CONNECTION_STRING =~ Password=([^;]+) ]]; then password="${BASH_REMATCH[1]}"; fi

    if command -v psql &> /dev/null; then
        export PGPASSWORD="$password"
        
        # Check roles
        local role_count
        role_count=$(psql -h "$host" -p "$port" -U "$username" -d "$database" \
            -t -c "SELECT COUNT(*) FROM roles;" 2>/dev/null | xargs)
        log_info "Roles in database: $role_count"
        
        # Check analytics types
        local analytics_type_count
        analytics_type_count=$(psql -h "$host" -p "$port" -U "$username" -d "$database" \
            -t -c "SELECT COUNT(*) FROM analytics_type;" 2>/dev/null | xargs)
        log_info "Analytics types in database: $analytics_type_count"
        
        # Check users
        local user_count
        user_count=$(psql -h "$host" -p "$port" -U "$username" -d "$database" \
            -t -c "SELECT COUNT(*) FROM users;" 2>/dev/null | xargs)
        log_info "Users in database: $user_count"
        
        # List created users
        log_info "Created users:"
        psql -h "$host" -p "$port" -U "$username" -d "$database" \
            -c "SELECT email, fullname, (SELECT name FROM roles WHERE id = users.roleid) as role FROM users;" 2>/dev/null | while IFS= read -r line; do
            log_info "  $line"
        done
        
        unset PGPASSWORD
        log_success "Data verification completed"
    else
        log_warning "psql not available, skipping data verification"
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    log_info "Starting Database Seeding Script"
    log_info "Script: $0"
    log_info "Arguments: $*"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Enable verbose logging if requested
    if [[ "$VERBOSE" == "true" ]]; then
        set -x
    fi
    
    # Validate prerequisites
    validate_prerequisites
    
    # Validate database connection
    if ! validate_database_connection; then
        log_error "Database connection validation failed"
        exit 1
    fi
    
    # Validate database schema (skip in dry run)
    if [[ "$DRY_RUN" != "true" ]]; then
        if ! validate_database_schema; then
            log_error "Database schema validation failed"
            exit 1
        fi
    fi
    
    # Run seeding
    if ! run_seeding; then
        log_error "Database seeding failed"
        exit 1
    fi
    
    # Verify seeded data (skip in dry run)
    if [[ "$DRY_RUN" != "true" ]]; then
        verify_seeded_data
    fi
    
    log_success "Database seeding script completed successfully"
}

# Execute main function with all arguments
main "$@"