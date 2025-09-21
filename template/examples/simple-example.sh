#!/usr/bin/env bash
# shellcheck shell=bash
#--------------------------------------------------------------------------------------------------
# SCRIPT:       simple-example.sh
# PURPOSE:      Simple example demonstrating enterprise template usage patterns
# VERSION:      1.0.0
# REPOSITORY:   https://github.com/vintagedon/enterprise-aiops-bash
# LICENSE:      MIT
# USAGE:        ./simple-example.sh --target-file /path/to/file --operation backup
#
# NOTES:
#   This example demonstrates basic usage of the Enterprise AIOps Bash Framework
#   for common automation tasks. It serves as a starting point for new scripts.
#--------------------------------------------------------------------------------------------------

# --- Strict Mode & Security ---
set -Eeuo pipefail
IFS=$'\n\t'
umask 027

# --- Globals ---
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly START_TS="$(date -u +%FT%TZ)"

# --- Source Core Framework ---
for lib in "../framework/logging.sh" "../framework/security.sh" "../framework/validation.sh"; do
  if ! source "${SCRIPT_DIR}/${lib}"; then
    echo "FATAL: Could not source required library: ${lib}" >&2
    exit 1
  fi
done

# --- Traps ---
trap 'on_err $LINENO "$BASH_COMMAND" $?' ERR
trap 'on_exit' EXIT

# --- Script-Specific Variables ---
VERBOSE=0
DRY_RUN=0
TARGET_FILE=""
OPERATION=""
BACKUP_DIR="${BACKUP_DIR:-/var/backups}"

#--------------------------------------------------------------------------------------------------
# Demonstrates basic file backup operation using framework patterns
# @param $1  Source file path
# @param $2  Backup directory
#--------------------------------------------------------------------------------------------------
backup_file() {
  local source_file="$1"
  local backup_dir="$2"
  local backup_filename backup_path
  
  log_info "Starting file backup operation"
  
  # Validate inputs
  [[ -f "$source_file" ]] || die "Source file does not exist: $source_file"
  [[ -r "$source_file" ]] || die "Source file not readable: $source_file"
  
  # Create backup directory if needed
  if [[ ! -d "$backup_dir" ]]; then
    log_info "Creating backup directory: $backup_dir"
    run mkdir -p "$backup_dir"
  fi
  
  # Generate backup filename with timestamp
  backup_filename="$(basename "$source_file").backup.$(date +%Y%m%d_%H%M%S)"
  backup_path="$backup_dir/$backup_filename"
  
  log_info "Backing up file: $source_file -> $backup_path"
  run cp "$source_file" "$backup_path"
  
  log_info "Backup completed successfully: $backup_path"
}

#--------------------------------------------------------------------------------------------------
# Demonstrates file analysis operation with structured output
# @param $1  File path to analyze
#--------------------------------------------------------------------------------------------------
analyze_file() {
  local file_path="$1"
  local file_size file_type file_perms file_modified
  
  log_info "Starting file analysis operation"
  
  # Validate input
  [[ -f "$file_path" ]] || die "File does not exist: $file_path"
  [[ -r "$file_path" ]] || die "File not readable: $file_path"
  
  # Gather file information
  file_size=$(stat -c%s "$file_path" 2>/dev/null || echo "unknown")
  file_type=$(file -b "$file_path" 2>/dev/null || echo "unknown")
  file_perms=$(stat -c%a "$file_path" 2>/dev/null || echo "unknown")
  file_modified=$(stat -c%y "$file_path" 2>/dev/null || echo "unknown")
  
  log_info "File analysis results:"
  log_info "  File: $file_path"
  log_info "  Size: $file_size bytes"
  log_info "  Type: $file_type"
  log_info "  Permissions: $file_perms"
  log_info "  Modified: $file_modified"
  
  # Demonstrate conditional logic based on file size
  if [[ "$file_size" != "unknown" ]] && [[ "$file_size" -gt 1048576 ]]; then
    log_warn "Large file detected (>1MB): $file_path"
  fi
  
  log_info "File analysis completed successfully"
}

#--------------------------------------------------------------------------------------------------
# Demonstrates system information gathering
#--------------------------------------------------------------------------------------------------
gather_system_info() {
  local hostname uptime load_avg disk_usage
  
  log_info "Gathering system information"
  
  hostname=$(hostname 2>/dev/null || echo "unknown")
  uptime=$(uptime -p 2>/dev/null || echo "unknown")
  load_avg=$(uptime | awk -F'load average:' '{ print $2 }' 2>/dev/null || echo "unknown")
  disk_usage=$(df -h / | tail -1 | awk '{print $5}' 2>/dev/null || echo "unknown")
  
  log_info "System information:"
  log_info "  Hostname: $hostname"
  log_info "  Uptime: $uptime"
  log_info "  Load Average: $load_avg"
  log_info "  Root Disk Usage: $disk_usage"
  
  log_info "System information gathering completed"
}

usage() {
  local code="${1:-0}"
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS] --target-file <path> --operation <type>

Simple example demonstrating enterprise template usage patterns.

Options:
  --target-file <path>   File to operate on (required)
  --operation <type>     Operation type: backup, analyze, or sysinfo (required)
  --backup-dir <path>    Backup directory (default: /var/backups)
  -d, --dry-run          Show actions without executing
  -v, --verbose          Enable verbose (debug) logging
  -h, --help             Show this help

Operations:
  backup      Create a timestamped backup of the target file
  analyze     Analyze file properties and report information
  sysinfo     Gather and display system information (ignores target-file)

Examples:
  $SCRIPT_NAME --target-file /etc/hosts --operation backup
  $SCRIPT_NAME --target-file /var/log/syslog --operation analyze --verbose
  $SCRIPT_NAME --target-file /dev/null --operation sysinfo --dry-run
  
  # Custom backup directory
  $SCRIPT_NAME --target-file /etc/nginx/nginx.conf --operation backup \\
               --backup-dir /opt/backups

This example demonstrates:
  - Basic framework integration
  - Input validation and error handling
  - Structured logging output
  - Safe command execution patterns
  - Common automation operations
EOF
  exit "$code"
}

parse_args() {
  [[ $# -eq 0 ]] && usage 1
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target-file)  [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; TARGET_FILE="$2"; shift 2 ;;
      --operation)    [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; OPERATION="$2"; shift 2 ;;
      --backup-dir)   [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; BACKUP_DIR="$2"; shift 2 ;;
      -d|--dry-run)   DRY_RUN=1; shift ;;
      -v|--verbose)   VERBOSE=1; LOG_LEVEL=10; shift ;;
      -h|--help)      usage 0 ;;
      --) shift; break ;;
      -*) die "Unknown option: $1" ;;
      *)  break ;;
    esac
  done
}

main() {
  parse_args "$@"
  
  # Validate required parameters
  [[ -n "$TARGET_FILE" ]] || { log_error "Target file is required."; usage 1; }
  [[ -n "$OPERATION" ]] || { log_error "Operation is required."; usage 1; }
  
  # Validate operation type
  case "$OPERATION" in
    backup|analyze|sysinfo) ;;
    *) die "Invalid operation: $OPERATION (use backup, analyze, or sysinfo)" ;;
  esac
  
  log_info "Starting $SCRIPT_NAME"
  log_debug "TARGET_FILE=$TARGET_FILE" "OPERATION=$OPERATION" "DRY_RUN=$DRY_RUN" "BACKUP_DIR=$BACKUP_DIR"
  
  # Execute requested operation
  case "$OPERATION" in
    backup)
      backup_file "$TARGET_FILE" "$BACKUP_DIR"
      ;;
    analyze)
      analyze_file "$TARGET_FILE"
      ;;
    sysinfo)
      log_info "System information operation (target-file parameter ignored)"
      gather_system_info
      ;;
  esac
  
  log_info "$SCRIPT_NAME completed successfully"
}

# --- Invocation ---
main "$@"
