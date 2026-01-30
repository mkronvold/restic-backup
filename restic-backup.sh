#!/bin/bash

# restic-backup.sh - A comprehensive backup script using restic
# Supports multiple directories, selective backup/restore, and logging

set -euo pipefail

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Config file search order: 1) ~/.restic/restic-backup.conf 2) ./restic-backup.conf
if [ -z "${CONFIG_FILE:-}" ]; then
    if [ -f "$HOME/.restic/restic-backup.conf" ]; then
        CONFIG_FILE="$HOME/.restic/restic-backup.conf"
    else
        CONFIG_FILE="$SCRIPT_DIR/restic-backup.conf"
    fi
fi

LOG_FILE="${LOG_FILE:-$HOME/.restic/restic-backup.log}"
TEMP_FILES=()

# Cleanup function for temporary files
cleanup() {
    local exit_code=$?
    if [ ${#TEMP_FILES[@]} -gt 0 ]; then
        for temp_file in "${TEMP_FILES[@]}"; do
            [ -f "$temp_file" ] && rm -f "$temp_file"
        done
    fi
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Log rotation - keep last 10 log files
rotate_logs() {
    local max_logs=10
    local log_size_limit=$((10 * 1024 * 1024))  # 10MB
    
    # Check if log file exists and exceeds size limit
    if [ -f "$LOG_FILE" ] && [ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt $log_size_limit ]; then
        # Rotate existing logs
        for i in $(seq $((max_logs - 1)) -1 1); do
            if [ -f "${LOG_FILE}.$i" ]; then
                mv "${LOG_FILE}.$i" "${LOG_FILE}.$((i + 1))"
            fi
        done
        
        # Rotate current log
        mv "$LOG_FILE" "${LOG_FILE}.1"
        
        # Remove oldest log if exceeds max_logs
        if [ -f "${LOG_FILE}.$((max_logs + 1))" ]; then
            rm -f "${LOG_FILE}.$((max_logs + 1))"
        fi
    fi
}

# Color codes for terminal output
if [ -t 1 ]; then
    # Terminal supports colors
    COLOR_RESET='\033[0m'
    COLOR_RED='\033[0;31m'
    COLOR_GREEN='\033[0;32m'
    COLOR_YELLOW='\033[0;33m'
    COLOR_BLUE='\033[0;34m'
    COLOR_CYAN='\033[0;36m'
else
    # No color support
    COLOR_RESET=''
    COLOR_RED=''
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_BLUE=''
    COLOR_CYAN=''
fi

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_line="[$timestamp] [$level] $message"
    
    # Color code for terminal output
    local color=""
    case "$level" in
        SUCCESS)
            color="${COLOR_GREEN}"
            ;;
        FAILURE)
            color="${COLOR_RED}"
            ;;
        INFO)
            if [[ "$message" == ATTEMPT:* ]]; then
                color="${COLOR_CYAN}"
            elif [[ "$message" == SIZE:* ]]; then
                color="${COLOR_YELLOW}"
            else
                color="${COLOR_BLUE}"
            fi
            ;;
    esac
    
    # Print to terminal with color, log to file without color
    echo -e "${color}${log_line}${COLOR_RESET}"
    echo "$log_line" >> "$LOG_FILE"
}

log_attempt() {
    log "INFO" "ATTEMPT: $*"
}

log_success() {
    log "SUCCESS" "$*"
}

log_failure() {
    log "FAILURE" "$*"
}

log_size() {
    log "INFO" "SIZE: $*"
}

# Dependency checker
check_dependencies() {
    log "INFO" "Checking dependencies..."
    
    if ! command -v restic &> /dev/null; then
        log_failure "restic is not installed or not in PATH"
        exit 1
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_failure "Config file not found: $CONFIG_FILE"
        exit 1
    fi
    
    log_success "All dependencies satisfied"
}

# Load configuration
load_config() {
    log "INFO" "Loading configuration from $CONFIG_FILE"
    
    if [ ! -r "$CONFIG_FILE" ]; then
        log_failure "Cannot read config file: $CONFIG_FILE"
        exit 1
    fi
    
    # Source the config file
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    
    # Validate required variables
    if [ -z "${RESTIC_REPOSITORY:-}" ]; then
        log_failure "RESTIC_REPOSITORY not defined in config"
        exit 1
    fi
    
    if [ -z "${RESTIC_PASSWORD:-}" ] && [ -z "${RESTIC_PASSWORD_FILE:-}" ]; then
        log_failure "Either RESTIC_PASSWORD or RESTIC_PASSWORD_FILE must be defined"
        exit 1
    fi
    
    if [ -z "${BACKUP_TARGETS:-}" ]; then
        log_failure "BACKUP_TARGETS not defined in config"
        exit 1
    fi
    
    # Export for restic
    export RESTIC_REPOSITORY
    export RESTIC_PASSWORD
    export RESTIC_PASSWORD_FILE
    
    log_success "Configuration loaded successfully"
}

# Check repository access
check_repository() {
    log "INFO" "Checking repository access..."
    
    if ! restic snapshots --quiet &> /dev/null; then
        log_failure "Cannot access repository: $RESTIC_REPOSITORY"
        exit 1
    fi
    
    log_success "Repository access confirmed"
}

# Backup a single directory
backup_single() {
    local target="$1"
    local target_name="${2:-$(basename "$target")}"
    
    if [ ! -d "$target" ]; then
        log_failure "Directory does not exist: $target"
        return 1
    fi
    
    log_attempt "Backing up $target_name: $target"
    
    local stats_file=$(mktemp)
    TEMP_FILES+=("$stats_file")
    
    if restic backup "$target" --tag "$target_name" --json 2>&1 | tee "$stats_file" | tail -n 1 > /dev/null; then
        # Parse the last line (summary) for statistics
        local summary=$(tail -n 1 "$stats_file")
        local files_new=$(echo "$summary" | grep -oP '"files_new":\s*\K[0-9]+' || echo "0")
        local files_changed=$(echo "$summary" | grep -oP '"files_changed":\s*\K[0-9]+' || echo "0")
        local files_unmodified=$(echo "$summary" | grep -oP '"files_unmodified":\s*\K[0-9]+' || echo "0")
        local data_added=$(echo "$summary" | grep -oP '"data_added":\s*\K[0-9]+' || echo "0")
        local total_files=$((files_new + files_changed + files_unmodified))
        
        log_success "Backup completed for $target_name"
        log_size "Files: $total_files (new: $files_new, changed: $files_changed, unmodified: $files_unmodified)"
        log_size "Data added: $(numfmt --to=iec-i --suffix=B $data_added 2>/dev/null || echo "${data_added} bytes")"
        return 0
    else
        log_failure "Backup failed for $target_name: $target"
        return 1
    fi
}

# Backup all configured directories
backup_all() {
    log_attempt "Starting backup of all configured targets"
    local success_count=0
    local failure_count=0
    
    IFS=':' read -ra TARGETS <<< "$BACKUP_TARGETS"
    for target in "${TARGETS[@]}"; do
        # Disable exit on error for individual backups
        set +e
        backup_single "$target"
        local result=$?
        set -e
        
        if [ $result -eq 0 ]; then
            success_count=$((success_count + 1))
        else
            failure_count=$((failure_count + 1))
        fi
    done
    
    log "INFO" "Backup summary: $success_count successful, $failure_count failed"
    
    # Run automatic retention cleanup if enabled
    if [ "${AUTO_PRUNE:-true}" = "true" ]; then
        prune_snapshots
    fi
    
    if [ $failure_count -gt 0 ]; then
        return 1
    fi
    return 0
}

# Prune old snapshots based on retention policy
prune_snapshots() {
    log_attempt "Applying retention policy and pruning old snapshots"
    
    local prune_args=()
    
    # Build prune arguments from config
    if [ -n "${KEEP_LAST:-}" ] && [ "${KEEP_LAST}" -gt 0 ]; then
        prune_args+=(--keep-last "${KEEP_LAST}")
    fi
    
    if [ -n "${KEEP_HOURLY:-}" ] && [ "${KEEP_HOURLY}" -gt 0 ]; then
        prune_args+=(--keep-hourly "${KEEP_HOURLY}")
    fi
    
    if [ -n "${KEEP_DAILY:-}" ] && [ "${KEEP_DAILY}" -gt 0 ]; then
        prune_args+=(--keep-daily "${KEEP_DAILY}")
    fi
    
    if [ -n "${KEEP_WEEKLY:-}" ] && [ "${KEEP_WEEKLY}" -gt 0 ]; then
        prune_args+=(--keep-weekly "${KEEP_WEEKLY}")
    fi
    
    if [ -n "${KEEP_MONTHLY:-}" ] && [ "${KEEP_MONTHLY}" -gt 0 ]; then
        prune_args+=(--keep-monthly "${KEEP_MONTHLY}")
    fi
    
    if [ -n "${KEEP_YEARLY:-}" ] && [ "${KEEP_YEARLY}" -gt 0 ]; then
        prune_args+=(--keep-yearly "${KEEP_YEARLY}")
    fi
    
    # If no retention policy defined, skip pruning
    if [ ${#prune_args[@]} -eq 0 ]; then
        log "INFO" "No retention policy defined, skipping prune"
        return 0
    fi
    
    # Run forget and prune
    if restic forget "${prune_args[@]}" --prune 2>&1 | tee -a "$LOG_FILE" | tail -1 > /dev/null; then
        log_success "Retention policy applied and old snapshots pruned"
        return 0
    else
        log_failure "Failed to prune snapshots"
        return 1
    fi
}

# List snapshots
list_snapshots() {
    local tag="${1:-}"
    
    log_attempt "Listing snapshots${tag:+ for tag: $tag}"
    
    if [ -n "$tag" ]; then
        restic snapshots --tag "$tag"
    else
        restic snapshots
    fi
}

# Show current configuration (with masked password)
show_config() {
    echo "=== Current Configuration ==="
    echo ""
    echo "Config file: $CONFIG_FILE"
    echo "Log file: $LOG_FILE"
    echo ""
    echo "Repository:"
    echo "  RESTIC_REPOSITORY: ${RESTIC_REPOSITORY:-<not set>}"
    
    if [ -n "${RESTIC_PASSWORD:-}" ]; then
        echo "  RESTIC_PASSWORD: ********"
    fi
    
    if [ -n "${RESTIC_PASSWORD_FILE:-}" ]; then
        echo "  RESTIC_PASSWORD_FILE: ${RESTIC_PASSWORD_FILE}"
        if [ -f "${RESTIC_PASSWORD_FILE}" ]; then
            echo "    (file exists, password: ********)"
        else
            echo "    (file not found!)"
        fi
    fi
    
    echo ""
    echo "Backup Targets:"
    if [ -n "${BACKUP_TARGETS:-}" ]; then
        IFS=':' read -ra TARGETS <<< "$BACKUP_TARGETS"
        for target in "${TARGETS[@]}"; do
            if [ -d "$target" ]; then
                echo "  ✓ $target"
            else
                echo "  ✗ $target (not found)"
            fi
        done
    else
        echo "  <not set>"
    fi
    
    echo ""
    echo "Retention Policy:"
    echo "  AUTO_PRUNE: ${AUTO_PRUNE:-true}"
    echo "  KEEP_LAST: ${KEEP_LAST:-<not set>}"
    echo "  KEEP_HOURLY: ${KEEP_HOURLY:-<not set>}"
    echo "  KEEP_DAILY: ${KEEP_DAILY:-<not set>}"
    echo "  KEEP_WEEKLY: ${KEEP_WEEKLY:-<not set>}"
    echo "  KEEP_MONTHLY: ${KEEP_MONTHLY:-<not set>}"
    echo "  KEEP_YEARLY: ${KEEP_YEARLY:-<not set>}"
    
    if [ -z "${KEEP_LAST:-}${KEEP_HOURLY:-}${KEEP_DAILY:-}${KEEP_WEEKLY:-}${KEEP_MONTHLY:-}${KEEP_YEARLY:-}" ]; then
        echo "  (No retention policy configured - old snapshots will not be pruned)"
    fi
    
    echo ""
}

# Restore a single snapshot
restore_snapshot() {
    local snapshot_id="$1"
    local restore_path="${2:-}"
    local tag="${3:-}"
    
    log_attempt "Restoring snapshot $snapshot_id${tag:+ (tag: $tag)}"
    
    local restore_args=()
    if [ -n "$restore_path" ]; then
        restore_args+=(--target "$restore_path")
        log "INFO" "Restore destination: $restore_path"
    fi
    
    if [ -n "$tag" ]; then
        restore_args+=(--tag "$tag")
    fi
    
    local stats_file=$(mktemp)
    TEMP_FILES+=("$stats_file")
    
    if restic restore "$snapshot_id" "${restore_args[@]}" 2>&1 | tee "$stats_file"; then
        local files_restored=$(grep -oP 'restoring \K[0-9]+(?= files)' "$stats_file" | tail -n 1 || echo "unknown")
        local size_restored=$(grep -oP 'restored \K[0-9.]+ [A-Z]+' "$stats_file" | tail -n 1 || echo "unknown")
        
        log_success "Restore completed for snapshot $snapshot_id"
        log_size "Files restored: $files_restored, Size: $size_restored"
        return 0
    else
        log_failure "Restore failed for snapshot $snapshot_id"
        return 1
    fi
}

# Restore latest snapshot for a specific tag
restore_latest() {
    local tag="$1"
    local restore_path="${2:-}"
    
    log_attempt "Restoring latest snapshot for tag: $tag"
    
    local snapshot_id=$(restic snapshots --tag "$tag" --json | grep -oP '"short_id":\s*"\K[^"]+' | head -n 1)
    
    if [ -z "$snapshot_id" ]; then
        log_failure "No snapshots found for tag: $tag"
        return 1
    fi
    
    restore_snapshot "$snapshot_id" "$restore_path" "$tag"
}

# Restore all targets to their original or alternative locations
restore_all() {
    local restore_base="${1:-/}"
    
    log_attempt "Starting full restore to: $restore_base"
    local success_count=0
    local failure_count=0
    
    IFS=':' read -ra TARGETS <<< "$BACKUP_TARGETS"
    for target in "${TARGETS[@]}"; do
        local target_name=$(basename "$target")
        local restore_path=""
        
        if [ "$restore_base" != "/" ]; then
            restore_path="$restore_base"
        fi
        
        # Disable exit on error for individual restores
        set +e
        restore_latest "$target_name" "$restore_path"
        local result=$?
        set -e
        
        if [ $result -eq 0 ]; then
            success_count=$((success_count + 1))
        else
            failure_count=$((failure_count + 1))
        fi
    done
    
    log "INFO" "Restore summary: $success_count successful, $failure_count failed"
    
    if [ $failure_count -gt 0 ]; then
        return 1
    fi
    return 0
}

# Display brief usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] COMMAND

A comprehensive backup script using restic.

COMMANDS:
    backup <target|all>          Backup a specific target or all targets
    list [tag]                   List all snapshots or snapshots for a tag
    restore <snapshot> [path]    Restore a specific snapshot to optional path
    restore-latest <tag> [path]  Restore latest snapshot for tag to optional path
    restore-all [path]           Restore all targets to optional base path
    prune                        Manually apply retention policy and prune snapshots
    check                        Check repository integrity
    config                       Show current configuration (with masked password)

OPTIONS:
    -c, --config FILE            Use specified config file (default: ~/.restic/restic-backup.conf)
    -l, --log FILE               Use specified log file (default: ~/.restic/restic-backup.log)
    -h, --help                   Show detailed help
    
ENVIRONMENT:
    CONFIG_FILE                  Override default config file location
    LOG_FILE                     Override default log file location

Examples:
    $0 backup all
    $0 backup /home/user/documents
    $0 list
    $0 restore abc123 /tmp/restore
    $0 restore-latest documents /tmp/restore
    $0 restore-all /mnt/recovery

EOF
}

# Display detailed help
help() {
    usage
    cat << EOF

CONFIGURATION FILE FORMAT:
    The configuration file should be a bash script that sets the following variables:
    
    RESTIC_REPOSITORY       Repository location (local path, sftp://, s3://, etc.)
    RESTIC_PASSWORD         Repository password (or use RESTIC_PASSWORD_FILE)
    RESTIC_PASSWORD_FILE    Path to file containing repository password
    BACKUP_TARGETS          Colon-separated list of directories to backup
    
    Optional retention policy (for automatic pruning):
    AUTO_PRUNE              Enable/disable automatic pruning after backup (default: true)
    KEEP_LAST               Keep last N snapshots
    KEEP_HOURLY             Keep last N hourly snapshots
    KEEP_DAILY              Keep last N daily snapshots
    KEEP_WEEKLY             Keep last N weekly snapshots
    KEEP_MONTHLY            Keep last N monthly snapshots
    KEEP_YEARLY             Keep last N yearly snapshots
    
    Default location: ~/.restic/restic-backup.conf
    Fallback: ./restic-backup.conf
    
Example config file:
    RESTIC_REPOSITORY="/backup/restic-repo"
    RESTIC_PASSWORD="my-secure-password"
    BACKUP_TARGETS="/home/user/documents:/home/user/pictures:/etc"
    
    # Retention policy
    KEEP_LAST=7
    KEEP_DAILY=14
    KEEP_WEEKLY=8
    KEEP_MONTHLY=12
    KEEP_YEARLY=3

LOGGING:
    Default log location: ~/.restic/restic-backup.log
    All operations are logged to the log file with timestamps.
    Log entries include attempt status, success/failure, and size information.
    
    Log Rotation:
    - Logs are automatically rotated when they exceed 10MB
    - Keeps last 10 rotated logs (*.log.1 through *.log.10)
    - Oldest logs are automatically removed

For more information, visit: https://restic.readthedocs.io/

EOF
}

# Main command processing
main() {
    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -l|--log)
                LOG_FILE="$2"
                shift 2
                ;;
            -h|--help)
                help
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done
    
    # Require at least one command
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi
    
    local command="$1"
    shift
    
    # Rotate logs before starting operations
    rotate_logs
    
    # Config command doesn't need repository access
    if [ "$command" = "config" ]; then
        check_dependencies
        load_config
        show_config
        return 0
    fi
    
    # Initialize for all other commands
    check_dependencies
    load_config
    check_repository
    
    # Process commands
    case "$command" in
        backup)
            if [ $# -eq 0 ]; then
                echo "Error: backup requires a target or 'all'"
                usage
                exit 1
            fi
            
            local target="$1"
            if [ "$target" = "all" ]; then
                backup_all
            else
                backup_single "$target"
            fi
            ;;
            
        list)
            list_snapshots "${1:-}"
            ;;
            
        restore)
            if [ $# -eq 0 ]; then
                echo "Error: restore requires a snapshot ID"
                usage
                exit 1
            fi
            
            restore_snapshot "$1" "${2:-}"
            ;;
            
        restore-latest)
            if [ $# -eq 0 ]; then
                echo "Error: restore-latest requires a tag"
                usage
                exit 1
            fi
            
            restore_latest "$1" "${2:-}"
            ;;
            
        restore-all)
            restore_all "${1:-/}"
            ;;
            
        prune)
            prune_snapshots
            ;;
            
        check)
            log_attempt "Checking repository integrity"
            if restic check; then
                log_success "Repository check passed"
            else
                log_failure "Repository check failed"
                exit 1
            fi
            ;;
            
        *)
            echo "Error: unknown command '$command'"
            usage
            exit 1
            ;;
    esac
}

main "$@"
