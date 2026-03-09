# PowerShell Error Handling Utilities
# Provides consistent error handling functionality for PowerShell deployment scripts

# Error code constants
$ERROR_CODE_SUCCESS = 0
$ERROR_CODE_GENERAL = 1
$ERROR_CODE_VALIDATION = 2
$ERROR_CODE_AWS_CLI = 3
$ERROR_CODE_INFRASTRUCTURE = 4
$ERROR_CODE_DEPLOYMENT = 5
$ERROR_CODE_MIGRATION = 6
$ERROR_CODE_CONFIGURATION = 7

# Global error context
$Global:ErrorContext = ""
$Global:ErrorRemediation = ""

# Function to set error context
function Set-ErrorContext {
    param([string]$Context)
    $Global:ErrorContext = $Context
}

# Function to set error remediation
function Set-ErrorRemediation {
    param([string]$Remediation)
    $Global:ErrorRemediation = $Remediation
}

# Function to handle errors with context
function Invoke-ErrorHandler {
    param(
        [int]$ErrorCode,
        [string]$Message,
        [bool]$Fatal = $false
    )
    
    Write-LogError "Error occurred: $Message"
    
    if ($Global:ErrorContext) {
        Write-LogError "Context: $Global:ErrorContext"
    }
    
    if ($Global:ErrorRemediation) {
        Write-LogError "Remediation: $Global:ErrorRemediation"
    }
    
    if ($Fatal) {
        Write-LogError "Fatal error - exiting with code $ErrorCode"
        exit $ErrorCode
    }
    
    return $ErrorCode
}