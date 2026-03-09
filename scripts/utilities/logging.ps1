# PowerShell Logging Utilities
# Provides consistent logging functionality for PowerShell deployment scripts

# Global logging configuration
$Global:LogLevel = "INFO"
$Global:LogFile = $null

# Log level constants
$LOG_LEVELS = @{
    "ERROR" = 0
    "WARN"  = 1
    "INFO"  = 2
    "DEBUG" = 3
}

# Function to set log level
function Set-LogLevel {
    param([string]$Level)
    
    if ($LOG_LEVELS.ContainsKey($Level.ToUpper())) {
        $Global:LogLevel = $Level.ToUpper()
    } else {
        Write-Warning "Invalid log level: $Level. Using INFO."
        $Global:LogLevel = "INFO"
    }
}

# Function to set log file
function Set-LogFile {
    param([string]$FilePath)
    $Global:LogFile = $FilePath
}

# Function to write log message
function Write-LogMessage {
    param(
        [string]$Level,
        [string]$Message,
        [string]$Color = "White"
    )
    
    $currentLevel = $LOG_LEVELS[$Global:LogLevel]
    $messageLevel = $LOG_LEVELS[$Level]
    
    if ($messageLevel -le $currentLevel) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [$Level] $Message"
        
        # Write to console with color
        Write-Host $logEntry -ForegroundColor $Color
        
        # Write to log file if configured
        if ($Global:LogFile) {
            Add-Content -Path $Global:LogFile -Value $logEntry
        }
    }
}

# Logging functions
function Write-LogError {
    param([string]$Message)
    Write-LogMessage "ERROR" $Message "Red"
}

function Write-LogWarn {
    param([string]$Message)
    Write-LogMessage "WARN" $Message "Yellow"
}

function Write-LogInfo {
    param([string]$Message)
    Write-LogMessage "INFO" $Message "White"
}

function Write-LogDebug {
    param([string]$Message)
    Write-LogMessage "DEBUG" $Message "Gray"
}

function Write-LogSuccess {
    param([string]$Message)
    Write-LogMessage "INFO" $Message "Green"
}