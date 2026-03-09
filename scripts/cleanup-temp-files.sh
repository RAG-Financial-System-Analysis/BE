#!/bin/bash

# Cleanup Temporary Files
# Removes log files, temporary files, and other artifacts created during testing

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utilities/logging.sh"

# Function to cleanup log files
cleanup_log_files() {
    log_info "Cleaning up log files..."
    
    # Remove deployment log files from logs directory
    find ./logs -name "deployment_*.log" -type f -delete 2>/dev/null || true
    find ./logs -name "*_errors.log" -type f -delete 2>/dev/null || true
    find ./logs -name "deployment.log" -type f -delete 2>/dev/null || true
    
    # Remove any remaining log files in root directory (legacy cleanup)
    find . -maxdepth 1 -name "deployment_*.log" -type f -delete 2>/dev/null || true
    find . -maxdepth 1 -name "*_errors.log" -type f -delete 2>/dev/null || true
    find . -maxdepth 1 -name "deployment.log" -type f -delete 2>/dev/null || true
    
    # Remove test output files
    find /tmp -name "*test*$$*" -type f -delete 2>/dev/null || true
    find /tmp -name "*validation*$$*" -type f -delete 2>/dev/null || true
    find /tmp -name "*deployment*$$*" -type f -delete 2>/dev/null || true
    
    log_success "Log files cleaned up"
}

# Function to cleanup directories
cleanup_directories() {
    log_info "Cleaning up temporary directories..."
    
    # Remove log directories
    [ -d "logs" ] && rm -rf logs
    [ -d "deployment_logs" ] && rm -rf deployment_logs
    [ -d "deployment_checkpoints" ] && rm -rf deployment_checkpoints
    
    log_success "Temporary directories cleaned up"
}

# Function to cleanup test reports (optional)
cleanup_test_reports() {
    local keep_reports="${1:-false}"
    
    if [ "$keep_reports" = "false" ]; then
        log_info "Cleaning up test reports..."
        
        find . -name "*test-report.md" -type f -delete 2>/dev/null || true
        find . -name "*validation-report.md" -type f -delete 2>/dev/null || true
        find . -name "end-to-end-integration-test-report.md" -type f -delete 2>/dev/null || true
        find . -name "complete-workflow-test-report.md" -type f -delete 2>/dev/null || true
        find . -name "deployment-idempotency-property-test-report.md" -type f -delete 2>/dev/null || true
        find . -name "final-system-validation-report.md" -type f -delete 2>/dev/null || true
        
        log_success "Test reports cleaned up"
    else
        log_info "Keeping test reports (--keep-reports specified)"
    fi
}

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Cleanup temporary files, logs, and test artifacts.

OPTIONS:
    --keep-reports      Keep test report files
    --help, -h          Show this help message

EXAMPLES:
    # Clean up everything
    $0

    # Clean up but keep test reports
    $0 --keep-reports

EOF
}

# Main execution
main() {
    local keep_reports=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --keep-reports)
                keep_reports=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log_info "Starting cleanup of temporary files..."
    
    # Run cleanup functions
    cleanup_log_files
    cleanup_directories
    cleanup_test_reports "$keep_reports"
    
    log_success "Cleanup completed successfully!"
    log_info "All temporary files and logs have been removed."
}

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi