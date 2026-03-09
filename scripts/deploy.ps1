# AWS Deployment Automation - Master Deployment Script (PowerShell)
# Orchestrates the entire deployment process with mode selection and environment support
# 
# Usage: .\deploy.ps1 -Mode <initial|update|cleanup> -Environment <development|staging|production> [options]
#
# Requirements: 3.1, 3.2, 4.3

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("initial", "update", "cleanup")]
    [string]$Mode,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet("development", "staging", "production")]
    [string]$Environment,
    
    [string]$AwsProfile = "",
    [string]$AwsRegion = "us-east-1",
    [ValidateSet("ERROR", "WARN", "INFO", "DEBUG")]
    [string]$LogLevel = "INFO",
    [string]$ConfigFile = "",
    [switch]$DryRun,
    [switch]$Force,
    [switch]$SkipValidation,
    [switch]$Help,
    [switch]$Version
)

# Script metadata
$SCRIPT_NAME = "AWS Deployment Automation"
$SCRIPT_VERSION = "1.0.0"
$SCRIPT_AUTHOR = "AWS Deployment Automation System"

# Get script directory
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

# Import utility modules
. "$SCRIPT_DIR\utilities\logging.ps1"
. "$SCRIPT_DIR\utilities\error-handling.ps1"

# Function to display script header
function Show-Header {
    Write-Host "========================================"
    Write-Host "$SCRIPT_NAME v$SCRIPT_VERSION"
    Write-Host "========================================"
    Write-Host ""
}

# Function to display usage information
function Show-Usage {
    @"
Usage: .\deploy.ps1 -Mode <MODE> -Environment <ENVIRONMENT> [OPTIONS]

DESCRIPTION:
    Master deployment script for AWS infrastructure and .NET 10 application deployment.
    Supports initial infrastructure provisioning, code updates, and cleanup operations.

REQUIRED PARAMETERS:
    -Mode <MODE>                Deployment mode (required)
                               initial  - Provision infrastructure and deploy code
                               update   - Deploy code changes only (no infrastructure)
                               cleanup  - Remove all provisioned resources

    -Environment <ENV>          Target environment (required)
                               development - Development environment
                               staging     - Staging environment  
                               production  - Production environment

OPTIONS:
    -AwsProfile <PROFILE>       AWS CLI profile to use (optional)
    -AwsRegion <REGION>         AWS region (default: us-east-1)
    -LogLevel <LEVEL>           Logging level: ERROR|WARN|INFO|DEBUG (default: INFO)
    -ConfigFile <FILE>          Custom configuration file path (optional)
    -DryRun                     Show what would be done without executing
    -Force                      Skip confirmation prompts
    -SkipValidation             Skip AWS CLI and permissions validation
    -Help                       Show this help message
    -Version                    Show version information

EXAMPLES:
    # Initial deployment to production
    .\deploy.ps1 -Mode initial -Environment production

    # Update deployment with specific AWS profile
    .\deploy.ps1 -Mode update -Environment staging -AwsProfile my-profile

    # Cleanup with debug logging
    .\deploy.ps1 -Mode cleanup -Environment development -LogLevel DEBUG

    # Dry run to see what would be deployed
    .\deploy.ps1 -Mode initial -Environment production -DryRun

For detailed documentation, see: $SCRIPT_DIR\README.md
"@
}

# Function to display version information
function Show-Version {
    Write-Host "$SCRIPT_NAME v$SCRIPT_VERSION"
    Write-Host "Author: $SCRIPT_AUTHOR"
    Write-Host ""
    Write-Host "Dependencies:"
    
    try {
        $awsVersion = aws --version 2>&1 | Select-Object -First 1
        Write-Host "  - AWS CLI: $awsVersion"
    } catch {
        Write-Host "  - AWS CLI: Not installed"
    }
    
    try {
        $dotnetVersion = dotnet --version 2>$null
        Write-Host "  - .NET: $dotnetVersion"
    } catch {
        Write-Host "  - .NET: Not installed"
    }
    
    Write-Host "  - PowerShell: $($PSVersionTable.PSVersion)"
}

# Function to validate prerequisites
function Test-Prerequisites {
    if ($SkipValidation) {
        Write-LogWarn "Skipping AWS CLI validation (-SkipValidation flag used)"
        return $true
    }

    Write-LogInfo "Validating prerequisites..."

    # Check AWS CLI
    try {
        $null = Get-Command aws -ErrorAction Stop
        Write-LogSuccess "AWS CLI found"
    } catch {
        Write-LogError "AWS CLI not found. Please install AWS CLI v2."
        return $false
    }

    # Test AWS credentials
    try {
        $null = aws sts get-caller-identity 2>$null
        Write-LogSuccess "AWS credentials validated"
    } catch {
        Write-LogError "AWS credentials not configured or invalid."
        Write-LogError "Run 'aws configure' to set up credentials."
        return $false
    }

    # Check .NET SDK
    try {
        $dotnetVersion = dotnet --version 2>$null
        Write-LogSuccess ".NET SDK found - Version: $dotnetVersion"
    } catch {
        Write-LogWarn ".NET SDK not found. Required for Lambda deployment."
        Write-LogWarn "Install from: https://dotnet.microsoft.com/download"
    }

    Write-LogSuccess "Prerequisites validation completed"
    return $true
}

# Function to check existing infrastructure using detection script
function Test-ExistingInfrastructure {
    Write-LogInfo "Checking existing infrastructure using detection script..."

    $checkScript = Join-Path $SCRIPT_DIR "utilities\check-infrastructure.ps1"
    
    if (-not (Test-Path $checkScript)) {
        Write-LogError "Infrastructure detection script not found: $checkScript"
        return $false
    }

    # Build command arguments
    $checkArgs = @(
        "-Environment", $Environment,
        "-OutputFormat", "summary"
    )
    
    if ($AwsProfile) {
        $checkArgs += "-AwsProfile", $AwsProfile
    }
    
    if ($AwsRegion) {
        $checkArgs += "-AwsRegion", $AwsRegion
    }
    
    if ($LogLevel -eq "DEBUG") {
        $checkArgs += "-LogLevel", "DEBUG"
    }

    Write-LogDebug "Running infrastructure check: $checkScript $($checkArgs -join ' ')"

    try {
        $checkResult = & $checkScript @checkArgs 2>&1
        $exitCode = $LASTEXITCODE
        
        switch ($checkResult) {
            "EXISTS" {
                Write-LogInfo "Existing infrastructure detected for environment: $Environment"
                return $true
            }
            "NOT_FOUND" {
                Write-LogInfo "No existing infrastructure found for environment: $Environment"
                return $false
            }
            default {
                Write-LogWarn "Unexpected infrastructure check result: $checkResult"
                return $false
            }
        }
    } catch {
        Write-LogError "Infrastructure detection script failed: $($_.Exception.Message)"
        
        switch ($LASTEXITCODE) {
            1 {
                Write-LogInfo "No infrastructure found (confirmed by detection script)"
                return $false
            }
            2 {
                Write-LogWarn "Infrastructure found but has health issues"
                Write-LogWarn "Proceeding with caution - some resources may be unhealthy"
                return $true
            }
            3 {
                Write-LogError "AWS CLI or permission errors detected"
                throw "Infrastructure detection failed due to AWS CLI issues"
            }
            4 {
                Write-LogError "Invalid arguments passed to infrastructure detection script"
                throw "Infrastructure detection script argument error"
            }
            default {
                Write-LogError "Unknown error from infrastructure detection script"
                return $false
            }
        }
    }
}

# Function to validate deployment mode against infrastructure state
function Test-DeploymentMode {
    Write-LogInfo "Validating deployment mode '$Mode' against infrastructure state..."

    switch ($Mode) {
        "initial" {
            if (Test-ExistingInfrastructure) {
                Write-LogWarn "Infrastructure already exists for environment '$Environment'"
                Write-LogWarn "Initial deployment will recreate all resources"
                return $true
            } else {
                Write-LogInfo "No existing infrastructure found - initial deployment is appropriate"
                return $true
            }
        }
        "update" {
            if (-not (Test-ExistingInfrastructure)) {
                Write-LogError "Update deployment requested but no infrastructure exists for environment '$Environment'"
                Write-LogError ""
                Write-LogError "RESOLUTION STEPS:"
                Write-LogError "1. Run initial deployment first:"
                Write-LogError "   .\deploy.ps1 -Mode initial -Environment $Environment"
                Write-LogError ""
                Write-LogError "2. Or check if you're using the correct environment name"
                Write-LogError "   Available environments: development, staging, production"
                Write-LogError ""
                Write-LogError "3. Verify AWS region and profile settings:"
                Write-LogError "   Current region: $AwsRegion"
                Write-LogError "   Current profile: $(if ($AwsProfile) { $AwsProfile } else { 'default' })"
                
                throw "No infrastructure exists for update deployment"
            } else {
                Write-LogSuccess "Infrastructure exists - update deployment is valid"
                return $true
            }
        }
        "cleanup" {
            if (-not (Test-ExistingInfrastructure)) {
                Write-LogWarn "No infrastructure found for environment '$Environment'"
                Write-LogInfo "Nothing to clean up - this is not an error"
                return $true
            } else {
                Write-LogInfo "Infrastructure exists - cleanup deployment is valid"
                return $true
            }
        }
        default {
            Write-LogError "Invalid deployment mode: $Mode"
            Write-LogError "Valid modes: initial, update, cleanup"
            throw "Invalid deployment mode specified"
        }
    }
}

# Function to confirm destructive operations
function Confirm-Operation {
    param(
        [string]$Operation,
        [string]$Message,
        [string]$AdditionalInfo = ""
    )

    if ($Force) {
        Write-LogInfo "Skipping confirmation (-Force flag used)"
        return $true
    }

    if ($DryRun) {
        Write-LogInfo "[DRY RUN] Would confirm: $Operation"
        return $true
    }

    Write-Host ""
    Write-Host "========================================"
    Write-Host "CONFIRMATION REQUIRED"
    Write-Host "========================================"
    Write-Host "Operation: $Operation"
    Write-Host "Environment: $Environment"
    Write-Host "AWS Region: $AwsRegion"
    Write-Host "AWS Profile: $(if ($AwsProfile) { $AwsProfile } else { 'default' })"
    Write-Host ""
    Write-LogWarn $Message
    
    if ($AdditionalInfo) {
        Write-Host ""
        Write-Host $AdditionalInfo
    }
    
    Write-Host ""
    Write-Host "This action cannot be undone!"
    Write-Host ""
    
    # Enhanced confirmation for critical operations
    if ($Operation -match "Recreation|Cleanup") {
        Write-Host "Type 'yes' to confirm, or anything else to cancel:"
        $response = Read-Host ">"
        
        if ($response -eq "yes") {
            Write-Host ""
            Write-Host "Are you absolutely sure? This will permanently affect your $Environment environment."
            Write-Host "Type 'CONFIRM' to proceed:"
            $finalResponse = Read-Host ">"
            
            if ($finalResponse -eq "CONFIRM") {
                Write-LogInfo "Operation confirmed by user with double confirmation"
                return $true
            } else {
                Write-LogInfo "Operation cancelled - second confirmation not provided"
                exit 0
            }
        } else {
            Write-LogInfo "Operation cancelled by user"
            exit 0
        }
    } else {
        Write-Host "Type 'yes' to continue, or anything else to cancel:"
        $response = Read-Host ">"
        
        if ($response -match "^(yes|YES|y|Y)$") {
            Write-LogInfo "Operation confirmed by user"
            return $true
        } else {
            Write-LogInfo "Operation cancelled by user"
            exit 0
        }
    }
}

# Function to execute initial deployment
function Invoke-InitialDeployment {
    Write-LogInfo "Starting initial deployment for environment: $Environment"

    if ($DryRun) {
        Write-LogInfo "[DRY RUN] Would execute initial deployment with the following steps:"
        Write-LogInfo "[DRY RUN]   1. Validate deployment mode and infrastructure state"
        Write-LogInfo "[DRY RUN]   2. Confirm infrastructure recreation if needed"
        Write-LogInfo "[DRY RUN]   3. Provision RDS PostgreSQL instance"
        Write-LogInfo "[DRY RUN]   4. Create Lambda functions and IAM roles"
        Write-LogInfo "[DRY RUN]   5. Set up VPC networking and security groups"
        Write-LogInfo "[DRY RUN]   6. Run Entity Framework migrations"
        Write-LogInfo "[DRY RUN]   7. Deploy .NET 10 application code"
        Write-LogInfo "[DRY RUN]   8. Configure environment variables"
        return
    }

    # Validate deployment mode
    Test-DeploymentMode

    # If infrastructure exists, get confirmation for recreation
    if (Test-ExistingInfrastructure) {
        $checkScript = Join-Path $SCRIPT_DIR "utilities\check-infrastructure.ps1"
        $detailedArgs = @(
            "-Environment", $Environment,
            "-OutputFormat", "text"
        )
        
        if ($AwsProfile) { $detailedArgs += "-AwsProfile", $AwsProfile }
        if ($AwsRegion) { $detailedArgs += "-AwsRegion", $AwsRegion }
        
        try {
            $infrastructureDetails = & $checkScript @detailedArgs 2>$null
        } catch {
            $infrastructureDetails = "Unable to get detailed infrastructure information"
        }
        
        Confirm-Operation "Infrastructure Recreation" `
            "Existing infrastructure will be DESTROYED and recreated.`nThis may cause DATA LOSS and service interruption." `
            "Current Infrastructure:`n$infrastructureDetails"
    }

    # Placeholder implementations
    Write-LogInfo "Step 1: Provisioning AWS infrastructure..."
    Write-LogWarn "Infrastructure provisioning scripts not yet implemented (Task 3.x)"
    
    Write-LogInfo "Step 2: Running database migrations..."
    Write-LogWarn "Database migration scripts not yet implemented (Task 5.x)"
    
    Write-LogInfo "Step 3: Deploying Lambda functions..."
    Write-LogWarn "Lambda deployment scripts not yet implemented (Task 6.x)"

    Write-LogSuccess "Initial deployment completed for environment: $Environment"
}

# Function to execute update deployment
function Invoke-UpdateDeployment {
    Write-LogInfo "Starting update deployment for environment: $Environment"

    if ($DryRun) {
        Write-LogInfo "[DRY RUN] Would execute update deployment with the following steps:"
        Write-LogInfo "[DRY RUN]   1. Validate existing infrastructure"
        Write-LogInfo "[DRY RUN]   2. Deploy updated application code"
        Write-LogInfo "[DRY RUN]   3. Update Lambda environment variables"
        Write-LogInfo "[DRY RUN]   4. Run any pending migrations"
        return
    }

    # Validate deployment mode
    Test-DeploymentMode

    # Placeholder implementations
    Write-LogInfo "Step 1: Deploying code updates..."
    Write-LogWarn "Code deployment scripts not yet implemented (Task 6.x)"
    
    Write-LogInfo "Step 2: Updating configurations..."
    Write-LogWarn "Configuration update scripts not yet implemented (Task 6.x)"

    Write-LogSuccess "Update deployment completed for environment: $Environment"
}

# Function to execute cleanup deployment
function Invoke-CleanupDeployment {
    Write-LogInfo "Starting cleanup for environment: $Environment"

    if ($DryRun) {
        Write-LogInfo "[DRY RUN] Would execute cleanup with the following steps:"
        Write-LogInfo "[DRY RUN]   1. Validate existing infrastructure"
        Write-LogInfo "[DRY RUN]   2. Remove Lambda functions"
        Write-LogInfo "[DRY RUN]   3. Delete RDS instance (with confirmation)"
        Write-LogInfo "[DRY RUN]   4. Clean up VPC resources"
        Write-LogInfo "[DRY RUN]   5. Remove IAM roles and policies"
        Write-LogInfo "[DRY RUN]   6. Delete deployment artifacts"
        return
    }

    # Validate deployment mode
    Test-DeploymentMode

    # If no infrastructure exists, nothing to clean up
    if (-not (Test-ExistingInfrastructure)) {
        Write-LogInfo "No infrastructure found for environment: $Environment - nothing to clean up"
        return
    }

    # Get detailed infrastructure information
    $checkScript = Join-Path $SCRIPT_DIR "utilities\check-infrastructure.ps1"
    $detailedArgs = @(
        "-Environment", $Environment,
        "-OutputFormat", "text"
    )
    
    if ($AwsProfile) { $detailedArgs += "-AwsProfile", $AwsProfile }
    if ($AwsRegion) { $detailedArgs += "-AwsRegion", $AwsRegion }
    
    try {
        $infrastructureDetails = & $checkScript @detailedArgs 2>$null
    } catch {
        $infrastructureDetails = "Unable to get detailed infrastructure information"
    }

    Confirm-Operation "Infrastructure Cleanup" `
        "This will PERMANENTLY DELETE all AWS resources for environment '$Environment'.`nThis action CANNOT BE UNDONE and WILL RESULT IN DATA LOSS." `
        "Resources to be deleted:`n$infrastructureDetails"

    # Placeholder implementation
    Write-LogInfo "Step 1: Cleaning up AWS resources..."
    Write-LogWarn "Cleanup scripts not yet implemented (Task 9.x)"

    Write-LogSuccess "Cleanup completed for environment: $Environment"
}

# Function to execute deployment based on mode
function Invoke-Deployment {
    switch ($Mode) {
        "initial" { Invoke-InitialDeployment }
        "update" { Invoke-UpdateDeployment }
        "cleanup" { Invoke-CleanupDeployment }
        default { throw "Invalid deployment mode: $Mode" }
    }
}

# Function to display deployment summary
function Show-DeploymentSummary {
    Write-Host ""
    Write-Host "========================================"
    Write-Host "Deployment Summary"
    Write-Host "========================================"
    Write-Host "Mode: $Mode"
    Write-Host "Environment: $Environment"
    Write-Host "AWS Profile: $(if ($AwsProfile) { $AwsProfile } else { 'default' })"
    Write-Host "AWS Region: $AwsRegion"
    Write-Host "Dry Run: $DryRun"
    Write-Host ""
    Write-Host "For troubleshooting, see: $SCRIPT_DIR\README.md"
    Write-Host "========================================"
}

# Main execution
try {
    # Handle help and version flags
    if ($Help) {
        Show-Usage
        exit 0
    }

    if ($Version) {
        Show-Version
        exit 0
    }

    # Show header
    Show-Header

    # Set up logging
    Set-LogLevel $LogLevel

    # Configure AWS environment
    if ($AwsProfile) {
        $env:AWS_PROFILE = $AwsProfile
    }
    $env:AWS_DEFAULT_REGION = $AwsRegion

    Write-LogInfo "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    Write-LogInfo "Mode: $Mode, Environment: $Environment"

    # Validate prerequisites
    if (-not (Test-Prerequisites)) {
        throw "Prerequisites validation failed"
    }

    # Execute deployment
    Invoke-Deployment

    # Show summary
    Show-DeploymentSummary

    Write-LogSuccess "Deployment script completed successfully"

} catch {
    Write-LogError "Deployment failed: $($_.Exception.Message)"
    exit 1
}