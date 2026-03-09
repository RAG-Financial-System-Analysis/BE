#!/bin/bash

# Logging Utility Script
# Provides consistent logging across all deployment scripts with timestamp and log level support

# Color codes for different log levels (only declare if not already set)
if [ -z "${RED:-}" ]; then
    readonly RED='\033[0;31m'
    readonly YELLOW='\033[1;33m'
    readonly GREEN='\033[0;32m'
    readonly BLUE='\033[0;34m'
    readonly NC='\033[0m' # No Color
fi

# Log levels (only declare if not already set)
if [ -z "${LOG_LEVEL_ERROR:-}" ]; then
    readonly LOG_LEVEL_ERROR=1
    readonly LOG_LEVEL_WARN=2
    readonly LOG_LEVEL_INFO=3
    readonly LOG_LEVEL_DEBUG=4
fi

# Default log level (can be overridden by environment variable)
LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}

# Log file path (can be overridden by environment variable)
LOG_FILE=${LOG_FILE:-"./logs/deployment_$(date +%Y%m%d_%H%M%S).log"}

# Function to get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to write log entry to file
write_to_file() {
    local level="$1"
    local message="$2"
    local timestamp=$(get_timestamp)
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Write to log file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Function to log error messages
log_error() {
    local message="$1"
    if [ "${LOG_LEVEL:-3}" -ge "${LOG_LEVEL_ERROR:-1}" ]; then
        echo -e "${RED}[ERROR]${NC} $message" >&2
        write_to_file "ERROR" "$message"
    fi
}

# Function to log warning messages
log_warn() {
    local message="$1"
    if [ "${LOG_LEVEL:-3}" -ge "${LOG_LEVEL_WARN:-2}" ]; then
        echo -e "${YELLOW}[WARN]${NC} $message"
        write_to_file "WARN" "$message"
    fi
}

# Function to log info messages
log_info() {
    local message="$1"
    if [ "${LOG_LEVEL:-3}" -ge "${LOG_LEVEL_INFO:-3}" ]; then
        echo -e "${GREEN}[INFO]${NC} $message"
        write_to_file "INFO" "$message"
    fi
}

# Function to log debug messages
log_debug() {
    local message="$1"
    if [ "${LOG_LEVEL:-3}" -ge "${LOG_LEVEL_DEBUG:-4}" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $message"
        write_to_file "DEBUG" "$message"
    fi
}

# Function to log success messages
log_success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $message"
    write_to_file "SUCCESS" "$message"
}

# Function to set log level
set_log_level() {
    case "$1" in
        "ERROR"|"error"|"1")
            LOG_LEVEL=$LOG_LEVEL_ERROR
            ;;
        "WARN"|"warn"|"2")
            LOG_LEVEL=$LOG_LEVEL_WARN
            ;;
        "INFO"|"info"|"3")
            LOG_LEVEL=$LOG_LEVEL_INFO
            ;;
        "DEBUG"|"debug"|"4")
            LOG_LEVEL=$LOG_LEVEL_DEBUG
            ;;
        *)
            log_warn "Invalid log level: $1. Using default INFO level."
            LOG_LEVEL=$LOG_LEVEL_INFO
            ;;
    esac
    log_debug "Log level set to: $LOG_LEVEL"
}

# Function to set log file path
set_log_file() {
    LOG_FILE="$1"
    log_debug "Log file set to: $LOG_FILE"
}

# Function to clear log file
clear_log() {
    > "$LOG_FILE"
    log_info "Log file cleared: $LOG_FILE"
}

# Function to display log file location
show_log_location() {
    echo "Log file location: $LOG_FILE"
}

# Export functions for use in other scripts
export -f log_error log_warn log_info log_debug log_success
export -f set_log_level set_log_file clear_log show_log_location
export -f get_timestamp write_to_file