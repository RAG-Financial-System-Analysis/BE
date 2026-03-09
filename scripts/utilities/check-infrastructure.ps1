# AWS Infrastructure Detection and Validation Script (PowerShell)
# Detects existing AWS resources and validates their status
# 
# Usage: .\check-infrastructure.ps1 -Environment <environment> [options]
#
# Requirements: 3.3

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("development", "staging", "production")]
    [string]$Environment,
    
    [string]$AwsProfile = "",
    [string]$AwsRegion = "us-east-1",
    [ValidateSet("ERROR", "WARN", "INFO", "DEBUG")]
    [string]$LogLevel = "INFO",
    [ValidateSet("text", "json", "summary")]
    [string]$OutputFormat = "text",
    [switch]$CheckHealth,
    [switch]$Verbose,
    [switch]$Help
)

# Script metadata
$SCRIPT_NAME = "Infrastructure Detection"
$SCRIPT_VERSION = "1.0.0"

# Get script directory and import utilities
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$SCRIPT_DIR\logging.ps1"

# Infrastructure status tracking
$InfrastructureStatus = @{}
$ResourceDetails = @{}

# Function to display usage information
function Show-Usage {
    @"
Usage: .\check-infrastructure.ps1 -Environment <ENVIRONMENT> [OPTIONS]

DESCRIPTION:
    Detects existing AWS infrastructure resources and validates their status.
    Checks RDS instances, Lambda functions, VPC resources, and their health.

REQUIRED PARAMETERS:
    -Environment <ENV>          Target environment to check
                               development|staging|production

OPTIONS:
    -AwsProfile <PROFILE>       AWS CLI profile to use (optional)
    -AwsRegion <REGION>         AWS region (default: us-east-1)
    -LogLevel <LEVEL>           Logging level: ERROR|WARN|INFO|DEBUG (default: INFO)
    -OutputFormat <FORMAT>      Output format: text|json|summary (default: text)
    -CheckHealth               Perform health checks on detected resources
    -Verbose                   Show detailed resource information
    -Help                      Show this help message

EXAMPLES:
    # Basic infrastructure check
    .\check-infrastructure.ps1 -Environment production

    # Detailed check with health validation
    .\check-infrastructure.ps1 -Environment staging -CheckHealth -Verbose

    # JSON output for automation
    .\check-infrastructure.ps1 -Environment development -OutputFormat json

EXIT CODES:
    0 - Infrastructure found and healthy
    1 - No infrastructure found
    2 - Infrastructure found but unhealthy
    3 - AWS CLI or permission errors
    4 - Invalid arguments
"@
}

# Function to test AWS CLI availability and credentials
function Test-AwsCliSetup {
    try {
        $null = Get-Command aws -ErrorAction Stop
    } catch {
        Write-LogError "AWS CLI not found. Please install AWS CLI v2."
        return $false
    }
    
    try {
        $null = aws sts get-caller-identity 2>$null
        return $true
    } catch {
        Write-LogError "AWS credentials not configured or invalid."
        Write-LogError "Run 'aws configure' to set up credentials."
        return $false
    }
}

# Function to check RDS instances
function Get-RdsInstances {
    Write-LogInfo "Checking RDS instances for environment: $Environment"
    
    try {
        $rdsInstances = aws rds describe-db-instances --query "DBInstances[?contains(DBInstanceIdentifier, '$Environment')].[DBInstanceIdentifier,DBInstanceStatus,Endpoint.Address,Endpoint.Port,Engine,EngineVersion,DBInstanceClass,AllocatedStorage]" --output text 2>$null
        
        if ($rdsInstances) {
            $instanceCount = 0
            $rdsInstances -split "`n" | ForEach-Object {
                if ($_.Trim()) {
                    $fields = $_ -split "`t"
                    if ($fields.Count -ge 8) {
                        $instanceCount++
                        $InfrastructureStatus["rds"] = "found"
                        $ResourceDetails["rds_${instanceCount}_id"] = $fields[0]
                        $ResourceDetails["rds_${instanceCount}_status"] = $fields[1]
                        $ResourceDetails["rds_${instanceCount}_endpoint"] = $fields[2]
                        $ResourceDetails["rds_${instanceCount}_port"] = $fields[3]
                        $ResourceDetails["rds_${instanceCount}_engine"] = $fields[4]
                        $ResourceDetails["rds_${instanceCount}_version"] = $fields[5]
                        $ResourceDetails["rds_${instanceCount}_class"] = $fields[6]
                        $ResourceDetails["rds_${instanceCount}_storage"] = $fields[7]
                        
                        Write-LogInfo "Found RDS instance: $($fields[0]) (Status: $($fields[1]))"
                        
                        if ($Verbose) {
                            Write-LogInfo "  Endpoint: $($fields[2]):$($fields[3])"
                            Write-LogInfo "  Engine: $($fields[4]) $($fields[5])"
                            Write-LogInfo "  Instance Class: $($fields[6])"
                            Write-LogInfo "  Storage: $($fields[7])GB"
                        }
                    }
                }
            }
            $ResourceDetails["rds_count"] = $instanceCount
        } else {
            $InfrastructureStatus["rds"] = "not_found"
            $ResourceDetails["rds_count"] = 0
            Write-LogInfo "No RDS instances found for environment: $Environment"
        }
    } catch {
        Write-LogError "Error checking RDS instances: $($_.Exception.Message)"
        $InfrastructureStatus["rds"] = "error"
        $ResourceDetails["rds_count"] = 0
    }
}

# Function to check Lambda functions
function Get-LambdaFunctions {
    Write-LogInfo "Checking Lambda functions for environment: $Environment"
    
    try {
        $lambdaFunctions = aws lambda list-functions --query "Functions[?contains(FunctionName, '$Environment')].[FunctionName,Runtime,State,LastModified,MemorySize,Timeout]" --output text 2>$null
        
        if ($lambdaFunctions) {
            $functionCount = 0
            $lambdaFunctions -split "`n" | ForEach-Object {
                if ($_.Trim()) {
                    $fields = $_ -split "`t"
                    if ($fields.Count -ge 6) {
                        $functionCount++
                        $InfrastructureStatus["lambda"] = "found"
                        $ResourceDetails["lambda_${functionCount}_name"] = $fields[0]
                        $ResourceDetails["lambda_${functionCount}_runtime"] = $fields[1]
                        $ResourceDetails["lambda_${functionCount}_state"] = $fields[2]
                        $ResourceDetails["lambda_${functionCount}_modified"] = $fields[3]
                        $ResourceDetails["lambda_${functionCount}_memory"] = $fields[4]
                        $ResourceDetails["lambda_${functionCount}_timeout"] = $fields[5]
                        
                        Write-LogInfo "Found Lambda function: $($fields[0]) (State: $($fields[2]))"
                        
                        if ($Verbose) {
                            Write-LogInfo "  Runtime: $($fields[1])"
                            Write-LogInfo "  Memory: $($fields[4])MB, Timeout: $($fields[5])s"
                            Write-LogInfo "  Last Modified: $($fields[3])"
                        }
                    }
                }
            }
            $ResourceDetails["lambda_count"] = $functionCount
        } else {
            $InfrastructureStatus["lambda"] = "not_found"
            $ResourceDetails["lambda_count"] = 0
            Write-LogInfo "No Lambda functions found for environment: $Environment"
        }
    } catch {
        Write-LogError "Error checking Lambda functions: $($_.Exception.Message)"
        $InfrastructureStatus["lambda"] = "error"
        $ResourceDetails["lambda_count"] = 0
    }
}

# Function to check VPC resources
function Get-VpcResources {
    Write-LogInfo "Checking VPC resources for environment: $Environment"
    
    try {
        $vpcs = aws ec2 describe-vpcs --filters "Name=tag:Environment,Values=$Environment" --query "Vpcs[*].[VpcId,State,CidrBlock]" --output text 2>$null
        
        if ($vpcs) {
            $vpcCount = 0
            $vpcs -split "`n" | ForEach-Object {
                if ($_.Trim()) {
                    $fields = $_ -split "`t"
                    if ($fields.Count -ge 3) {
                        $vpcCount++
                        $InfrastructureStatus["vpc"] = "found"
                        $ResourceDetails["vpc_${vpcCount}_id"] = $fields[0]
                        $ResourceDetails["vpc_${vpcCount}_state"] = $fields[1]
                        $ResourceDetails["vpc_${vpcCount}_cidr"] = $fields[2]
                        
                        Write-LogInfo "Found VPC: $($fields[0]) (State: $($fields[1]))"
                        
                        if ($Verbose) {
                            Write-LogInfo "  CIDR Block: $($fields[2])"
                        }
                    }
                }
            }
            $ResourceDetails["vpc_count"] = $vpcCount
        } else {
            $InfrastructureStatus["vpc"] = "not_found"
            $ResourceDetails["vpc_count"] = 0
            Write-LogInfo "No VPC resources found for environment: $Environment"
        }
    } catch {
        Write-LogError "Error checking VPC resources: $($_.Exception.Message)"
        $InfrastructureStatus["vpc"] = "error"
        $ResourceDetails["vpc_count"] = 0
    }
}

# Function to check IAM roles
function Get-IamRoles {
    Write-LogInfo "Checking IAM roles for environment: $Environment"
    
    try {
        $iamRoles = aws iam list-roles --query "Roles[?contains(RoleName, '$Environment')].[RoleName,CreateDate,Arn]" --output text 2>$null
        
        if ($iamRoles) {
            $roleCount = 0
            $iamRoles -split "`n" | ForEach-Object {
                if ($_.Trim()) {
                    $fields = $_ -split "`t"
                    if ($fields.Count -ge 3) {
                        $roleCount++
                        $InfrastructureStatus["iam"] = "found"
                        $ResourceDetails["iam_${roleCount}_name"] = $fields[0]
                        $ResourceDetails["iam_${roleCount}_created"] = $fields[1]
                        $ResourceDetails["iam_${roleCount}_arn"] = $fields[2]
                        
                        Write-LogInfo "Found IAM role: $($fields[0])"
                        
                        if ($Verbose) {
                            Write-LogInfo "  ARN: $($fields[2])"
                            Write-LogInfo "  Created: $($fields[1])"
                        }
                    }
                }
            }
            $ResourceDetails["iam_count"] = $roleCount
        } else {
            $InfrastructureStatus["iam"] = "not_found"
            $ResourceDetails["iam_count"] = 0
            Write-LogInfo "No IAM roles found for environment: $Environment"
        }
    } catch {
        Write-LogError "Error checking IAM roles: $($_.Exception.Message)"
        $InfrastructureStatus["iam"] = "error"
        $ResourceDetails["iam_count"] = 0
    }
}

# Function to perform health checks
function Test-ResourceHealth {
    if (-not $CheckHealth) {
        return 0
    }
    
    Write-LogInfo "Performing health checks on detected resources..."
    
    $healthIssues = 0
    
    # Health check RDS instances
    if ($InfrastructureStatus["rds"] -eq "found") {
        $rdsCount = $ResourceDetails["rds_count"]
        for ($i = 1; $i -le $rdsCount; $i++) {
            $dbId = $ResourceDetails["rds_${i}_id"]
            $status = $ResourceDetails["rds_${i}_status"]
            
            if ($status -ne "available") {
                Write-LogWarn "RDS instance $dbId is not available (Status: $status)"
                $healthIssues++
            } else {
                Write-LogSuccess "RDS instance $dbId is healthy"
            }
        }
    }
    
    # Health check Lambda functions
    if ($InfrastructureStatus["lambda"] -eq "found") {
        $lambdaCount = $ResourceDetails["lambda_count"]
        for ($i = 1; $i -le $lambdaCount; $i++) {
            $functionName = $ResourceDetails["lambda_${i}_name"]
            $state = $ResourceDetails["lambda_${i}_state"]
            
            if ($state -ne "Active") {
                Write-LogWarn "Lambda function $functionName is not active (State: $state)"
                $healthIssues++
            } else {
                Write-LogSuccess "Lambda function $functionName is healthy"
            }
        }
    }
    
    # Health check VPC resources
    if ($InfrastructureStatus["vpc"] -eq "found") {
        $vpcCount = $ResourceDetails["vpc_count"]
        for ($i = 1; $i -le $vpcCount; $i++) {
            $vpcId = $ResourceDetails["vpc_${i}_id"]
            $state = $ResourceDetails["vpc_${i}_state"]
            
            if ($state -ne "available") {
                Write-LogWarn "VPC $vpcId is not available (State: $state)"
                $healthIssues++
            } else {
                Write-LogSuccess "VPC $vpcId is healthy"
            }
        }
    }
    
    if ($healthIssues -gt 0) {
        Write-LogWarn "Found $healthIssues health issues in infrastructure"
        return 2
    } else {
        Write-LogSuccess "All detected resources are healthy"
        return 0
    }
}

# Function to output results
function Write-Results {
    switch ($OutputFormat) {
        "text" {
            Write-Host ""
            Write-Host "========================================"
            Write-Host "Infrastructure Detection Results"
            Write-Host "========================================"
            Write-Host "Environment: $Environment"
            Write-Host "AWS Region: $AwsRegion"
            Write-Host "Check Time: $(Get-Date)"
            Write-Host ""
            
            $totalResources = 0
            @("rds", "lambda", "vpc", "iam") | ForEach-Object {
                if ($InfrastructureStatus[$_] -eq "found") {
                    $count = $ResourceDetails["${_}_count"]
                    Write-Host "$_`: $count resource(s) found"
                    $totalResources += $count
                } else {
                    Write-Host "$_`: No resources found"
                }
            }
            
            Write-Host ""
            Write-Host "Total Resources: $totalResources"
            
            if ($totalResources -gt 0) {
                Write-Host "Infrastructure Status: EXISTS"
            } else {
                Write-Host "Infrastructure Status: NOT_FOUND"
            }
            
            Write-Host "========================================"
        }
        "json" {
            $jsonOutput = @{
                environment = $Environment
                region = $AwsRegion
                check_time = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
                infrastructure_status = @{}
                total_resources = 0
            }
            
            @("rds", "lambda", "vpc", "iam") | ForEach-Object {
                if ($InfrastructureStatus[$_] -eq "found") {
                    $count = $ResourceDetails["${_}_count"]
                    $jsonOutput.infrastructure_status[$_] = @{
                        status = "found"
                        count = $count
                    }
                    $jsonOutput.total_resources += $count
                } else {
                    $jsonOutput.infrastructure_status[$_] = @{
                        status = "not_found"
                        count = 0
                    }
                }
            }
            
            $jsonOutput.exists = $jsonOutput.total_resources -gt 0
            
            Write-Host ($jsonOutput | ConvertTo-Json -Depth 3)
        }
        "summary" {
            $totalResources = 0
            @("rds", "lambda", "vpc", "iam") | ForEach-Object {
                if ($InfrastructureStatus[$_] -eq "found") {
                    $totalResources += $ResourceDetails["${_}_count"]
                }
            }
            
            if ($totalResources -gt 0) {
                Write-Host "EXISTS"
            } else {
                Write-Host "NOT_FOUND"
            }
        }
    }
}

# Function to determine exit code
function Get-ExitCode {
    $totalResources = 0
    @("rds", "lambda", "vpc", "iam") | ForEach-Object {
        if ($InfrastructureStatus[$_] -eq "found") {
            $totalResources += $ResourceDetails["${_}_count"]
        }
    }
    
    if ($totalResources -eq 0) {
        return 1  # No infrastructure found
    }
    
    if ($CheckHealth) {
        return (Test-ResourceHealth)
    }
    
    return 0  # Infrastructure found
}

# Main execution
try {
    if ($Help) {
        Show-Usage
        exit 0
    }

    # Set up logging
    Set-LogLevel $LogLevel

    # Configure AWS environment
    if ($AwsProfile) {
        $env:AWS_PROFILE = $AwsProfile
    }
    $env:AWS_DEFAULT_REGION = $AwsRegion

    Write-LogInfo "Starting infrastructure detection for environment: $Environment"

    # Test AWS CLI setup
    if (-not (Test-AwsCliSetup)) {
        exit 3
    }

    # Initialize tracking
    $InfrastructureStatus = @{}
    $ResourceDetails = @{}

    # Perform infrastructure checks
    Get-RdsInstances
    Get-LambdaFunctions
    Get-VpcResources
    Get-IamRoles

    # Output results
    Write-Results

    # Exit with appropriate code
    exit (Get-ExitCode)

} catch {
    Write-LogError "Infrastructure detection failed: $($_.Exception.Message)"
    exit 3
}