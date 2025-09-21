#!/usr/bin/env bash
# shellcheck shell=bash
#--------------------------------------------------------------------------------------------------
# SCRIPT:       input-validation.sh
# PURPOSE:      Demonstrates security input validation patterns for enterprise automation
# VERSION:      1.0.0
# REPOSITORY:   https://github.com/vintagedon/enterprise-aiops-bash
# LICENSE:      MIT
# USAGE:        ./input-validation.sh --hostname server01 --port 8080 --config-file /etc/app.conf
#
# NOTES:
#   This script demonstrates comprehensive input validation patterns that should be used
#   when accepting parameters from AI agents, user input, or external systems.
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
for lib in "../../template/framework/logging.sh" "../../template/framework/security.sh" "../../template/framework/validation.sh"; do
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
HOSTNAME=""
PORT=""
CONFIG_FILE=""
EMAIL=""
TIMEOUT=""

#--------------------------------------------------------------------------------------------------
# Validates that input contains only alphanumeric characters, hyphens, and underscores
# @param $1  The input string to validate
# @param $2  The field name for error messages
#--------------------------------------------------------------------------------------------------
validate_alphanumeric_safe() {
  local input="$1"
  local field_name="${2:-field}"
  
  [[ -n "$input" ]] || die "Empty input not allowed for $field_name"
  
  # Allow only alphanumeric, hyphens, and underscores
  if [[ ! "$input" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    die "Invalid characters in $field_name: '$input' (only alphanumeric, underscore, hyphen allowed)"
  fi
  
  log_debug "Validation passed for $field_name: $input"
}

#--------------------------------------------------------------------------------------------------
# Validates hostname format according to RFC standards
# @param $1  The hostname to validate
#--------------------------------------------------------------------------------------------------
validate_hostname_format() {
  local hostname="$1"
  
  [[ -n "$hostname" ]] || die "Hostname cannot be empty"
  
  # Length check
  [[ ${#hostname} -le 253 ]] || die "Hostname too long: ${#hostname} characters (max 253)"
  
  # RFC-compliant hostname pattern
  if ! [[ "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    die "Invalid hostname format: '$hostname'"
  fi
  
  # Additional security checks
  [[ "$hostname" != *".."* ]] || die "Hostname contains consecutive dots: '$hostname'"
  [[ "$hostname" != "localhost" ]] || die "Localhost not allowed in automation context"
  
  log_debug "Hostname validation passed: $hostname"
}

#--------------------------------------------------------------------------------------------------
# Validates port number range and format
# @param $1  The port number to validate
#--------------------------------------------------------------------------------------------------
validate_port_number() {
  local port="$1"
  
  [[ -n "$port" ]] || die "Port number cannot be empty"
  
  # Check if it's a valid integer
  if ! [[ "$port" =~ ^[0-9]+$ ]]; then
    die "Port must be a positive integer: '$port'"
  fi
  
  # Check port range (1-65535)
  if [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
    die "Port number out of range: $port (must be 1-65535)"
  fi
  
  # Check for privileged ports in automation context
  if [[ "$port" -lt 1024 ]]; then
    log_warn "Using privileged port: $port (requires elevated privileges)"
  fi
  
  log_debug "Port validation passed: $port"
}

#--------------------------------------------------------------------------------------------------
# Validates file path for safety and existence
# @param $1  The file path to validate
# @param $2  Access mode to check (r=readable, w=writable, x=executable)
#--------------------------------------------------------------------------------------------------
validate_file_path() {
  local file_path="$1"
  local access_mode="${2:-r}"
  
  [[ -n "$file_path" ]] || die "File path cannot be empty"
  
  # Security: Prevent path traversal attacks
  if [[ "$file_path" =~ \.\./|\.\.\\ ]]; then
    die "Path traversal detected in file path: '$file_path'"
  fi
  
  # Normalize path to absolute
  local abs_path
  abs_path="$(realpath -m "$file_path" 2>/dev/null)" || die "Invalid file path: '$file_path'"
  
  # Security: Ensure path is within expected boundaries
  case "$abs_path" in
    /etc/*|/opt/*|/var/*|/home/*|/tmp/*)
      log_debug "File path within allowed directories: $abs_path"
      ;;
    *)
      log_warn "File path outside typical automation directories: $abs_path"
      ;;
  esac
  
  # Check existence and permissions based on access mode
  case "$access_mode" in
    r|read)
      [[ -f "$abs_path" ]] || die "File does not exist: '$abs_path'"
      [[ -r "$abs_path" ]] || die "File not readable: '$abs_path'"
      ;;
    w|write)
      if [[ -f "$abs_path" ]]; then
        [[ -w "$abs_path" ]] || die "File not writable: '$abs_path'"
      else
        local parent_dir
        parent_dir="$(dirname "$abs_path")"
        [[ -d "$parent_dir" ]] || die "Parent directory does not exist: '$parent_dir'"
        [[ -w "$parent_dir" ]] || die "Cannot write to parent directory: '$parent_dir'"
      fi
      ;;
    x|execute)
      [[ -f "$abs_path" ]] || die "File does not exist: '$abs_path'"
      [[ -x "$abs_path" ]] || die "File not executable: '$abs_path'"
      ;;
    *)
      die "Invalid access mode: '$access_mode' (use r, w, or x)"
      ;;
  esac
  
  log_debug "File path validation passed: $abs_path ($access_mode access)"
}

#--------------------------------------------------------------------------------------------------
# Validates email address format (basic RFC-compatible pattern)
# @param $1  The email address to validate
#--------------------------------------------------------------------------------------------------
validate_email_format() {
  local email="$1"
  
  [[ -n "$email" ]] || die "Email address cannot be empty"
  
  # Length check
  [[ ${#email} -le 254 ]] || die "Email address too long: ${#email} characters (max 254)"
  
  # Basic RFC-compatible email pattern
  local email_pattern='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
  if ! [[ "$email" =~ $email_pattern ]]; then
    die "Invalid email format: '$email'"
  fi
  
  # Additional security checks
  [[ "$email" != *".."* ]] || die "Email contains consecutive dots: '$email'"
  [[ "$email" == *"@"*"."* ]] || die "Email missing domain: '$email'"
  
  log_debug "Email validation passed: $email"
}

#--------------------------------------------------------------------------------------------------
# Validates timeout value (seconds) with reasonable limits
# @param $1  The timeout value to validate
#--------------------------------------------------------------------------------------------------
validate_timeout() {
  local timeout="$1"
  
  [[ -n "$timeout" ]] || die "Timeout value cannot be empty"
  
  # Check if it's a valid integer
  if ! [[ "$timeout" =~ ^[0-9]+$ ]]; then
    die "Timeout must be a positive integer: '$timeout'"
  fi
  
  # Check reasonable timeout range (1 second to 24 hours)
  if [[ "$timeout" -lt 1 ]] || [[ "$timeout" -gt 86400 ]]; then
    die "Timeout out of range: $timeout seconds (must be 1-86400)"
  fi
  
  # Warn for very short timeouts
  if [[ "$timeout" -lt 5 ]]; then
    log_warn "Very short timeout: $timeout seconds (may cause premature failures)"
  fi
  
  log_debug "Timeout validation passed: $timeout seconds"
}

#--------------------------------------------------------------------------------------------------
# Validates string length within specified bounds
# @param $1  The string to validate
# @param $2  Minimum length
# @param $3  Maximum length
# @param $4  Field name for error messages
#--------------------------------------------------------------------------------------------------
validate_string_length() {
  local input="$1"
  local min_length="$2"
  local max_length="$3"
  local field_name="${4:-field}"
  
  local actual_length=${#input}
  
  if [[ "$actual_length" -lt "$min_length" ]]; then
    die "$field_name too short: $actual_length characters (minimum $min_length)"
  fi
  
  if [[ "$actual_length" -gt "$max_length" ]]; then
    die "$field_name too long: $actual_length characters (maximum $max_length)"
  fi
  
  log_debug "String length validation passed for $field_name: $actual_length characters"
}

#--------------------------------------------------------------------------------------------------
# Demonstrates shell metacharacter detection for command injection prevention
# @param $1  The input string to check
#--------------------------------------------------------------------------------------------------
validate_no_shell_metacharacters() {
  local input="$1"
  local field_name="${2:-input}"
  
  # Check for dangerous shell metacharacters
  local dangerous_chars=';&|<>$`()\{}[]'
  local char
  
  for (( i=0; i<${#dangerous_chars}; i++ )); do
    char="${dangerous_chars:$i:1}"
    if [[ "$input" == *"$char"* ]]; then
      die "Dangerous character '$char' detected in $field_name: '$input'"
    fi
  done
  
  # Check for command substitution patterns
  if [[ "$input" =~ \$\(.*\) ]] || [[ "$input" =~ `.*` ]]; then
    die "Command substitution detected in $field_name: '$input'"
  fi
  
  log_debug "Shell metacharacter validation passed for $field_name"
}

usage() {
  local code="${1:-0}"
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Demonstrates comprehensive input validation patterns for enterprise automation.

Options:
  --hostname <name>      Server hostname (required)
  --port <number>        Port number 1-65535 (required)
  --config-file <path>   Configuration file path (required)
  --email <address>      Email address (optional)
  --timeout <seconds>    Timeout in seconds 1-86400 (optional)
  -d, --dry-run          Show actions without executing
  -v, --verbose          Enable verbose (debug) logging
  -h, --help             Show this help

Examples:
  $SCRIPT_NAME --hostname web01.example.com --port 8080 --config-file /etc/app.conf
  $SCRIPT_NAME --hostname api-server --port 3000 --config-file /opt/app/config.yml \\
               --email admin@company.com --timeout 300

This script demonstrates:
  - Hostname format validation
  - Port number range checking
  - File path security validation
  - Email format verification
  - Timeout value validation
  - Shell metacharacter detection
EOF
  exit "$code"
}

parse_args() {
  [[ $# -eq 0 ]] && usage 1
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --hostname)    [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; HOSTNAME="$2"; shift 2 ;;
      --port)        [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; PORT="$2"; shift 2 ;;
      --config-file) [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; CONFIG_FILE="$2"; shift 2 ;;
      --email)       [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; EMAIL="$2"; shift 2 ;;
      --timeout)     [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; TIMEOUT="$2"; shift 2 ;;
      -d|--dry-run)  DRY_RUN=1; shift ;;
      -v|--verbose)  VERBOSE=1; LOG_LEVEL=10; shift ;;
      -h|--help)     usage 0 ;;
      --) shift; break ;;
      -*) die "Unknown option: $1" ;;
      *)  break ;;
    esac
  done
}

main() {
  parse_args "$@"
  
  log_info "Starting input validation demonstration"
  
  # Validate required parameters
  [[ -n "$HOSTNAME" ]] || { log_error "Hostname is required."; usage 1; }
  [[ -n "$PORT" ]] || { log_error "Port is required."; usage 1; }
  [[ -n "$CONFIG_FILE" ]] || { log_error "Config file is required."; usage 1; }
  
  log_info "=== Validating Required Parameters ==="
  
  # Validate hostname
  log_info "Validating hostname: $HOSTNAME"
  validate_hostname_format "$HOSTNAME"
  validate_no_shell_metacharacters "$HOSTNAME" "hostname"
  validate_string_length "$HOSTNAME" 1 253 "hostname"
  
  # Validate port
  log_info "Validating port: $PORT"
  validate_port_number "$PORT"
  validate_no_shell_metacharacters "$PORT" "port"
  
  # Validate config file
  log_info "Validating config file: $CONFIG_FILE"
  validate_file_path "$CONFIG_FILE" "r"
  validate_no_shell_metacharacters "$CONFIG_FILE" "config file path"
  
  # Validate optional parameters if provided
  if [[ -n "$EMAIL" ]]; then
    log_info "=== Validating Optional Email Parameter ==="
    log_info "Validating email: $EMAIL"
    validate_email_format "$EMAIL"
    validate_no_shell_metacharacters "$EMAIL" "email"
    validate_string_length "$EMAIL" 1 254 "email"
  fi
  
  if [[ -n "$TIMEOUT" ]]; then
    log_info "=== Validating Optional Timeout Parameter ==="
    log_info "Validating timeout: $TIMEOUT"
    validate_timeout "$TIMEOUT"
    validate_no_shell_metacharacters "$TIMEOUT" "timeout"
  fi
  
  log_info "=== All Input Validation Passed ==="
  log_info "✓ Hostname: $HOSTNAME"
  log_info "✓ Port: $PORT"
  log_info "✓ Config File: $CONFIG_FILE"
  [[ -n "$EMAIL" ]] && log_info "✓ Email: $EMAIL"
  [[ -n "$TIMEOUT" ]] && log_info "✓ Timeout: $TIMEOUT seconds"
  
  # Demonstrate safe usage of validated inputs
  log_info "=== Demonstrating Safe Usage of Validated Inputs ==="
  
  # Example: Safe command construction using validated inputs
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "DRY RUN: Would connect to $HOSTNAME:$PORT using config $CONFIG_FILE"
    [[ -n "$EMAIL" ]] && log_info "DRY RUN: Would send notifications to $EMAIL"
    [[ -n "$TIMEOUT" ]] && log_info "DRY RUN: Would use timeout of $TIMEOUT seconds"
  else
    # In a real script, these validated parameters would be safely used
    log_info "Validated parameters ready for safe usage in automation operations"
    log_info "All inputs have been sanitized and verified for security"
  fi
  
  log_info "Input validation demonstration completed successfully"
}

# --- Invocation ---
main "$@"