#!/usr/bin/env bash
# shellcheck shell=bash
#--------------------------------------------------------------------------------------------------
# SCRIPT:       file-operations.sh
# PURPOSE:      Demonstrates idempotent file operation patterns for enterprise automation
# VERSION:      1.0.0
# REPOSITORY:   https://github.com/vintagedon/enterprise-aiops-bash
# LICENSE:      MIT
# USAGE:        ./file-operations.sh --config-dir /etc/myapp --backup-dir /var/backups/myapp
#
# NOTES:
#   This script demonstrates idempotent patterns for common file operations that are
#   safe to run multiple times without causing unintended side effects.
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
CONFIG_DIR=""
BACKUP_DIR=""

#--------------------------------------------------------------------------------------------------
# Idempotent directory creation - safe to run multiple times
#--------------------------------------------------------------------------------------------------
create_directory_safe() {
  local dir_path="$1"
  local permissions="${2:-755}"
  
  log_debug "Creating directory: $dir_path with permissions $permissions"
  
  # Idempotent: mkdir -p succeeds even if directory exists
  run mkdir -p "$dir_path"
  
  # Only change permissions if they're different
  local current_perms
  if [[ -d "$dir_path" ]]; then
    current_perms="$(stat -c '%a' "$dir_path" 2>/dev/null || echo "unknown")"
    if [[ "$current_perms" != "$permissions" ]]; then
      log_info "Updating directory permissions: $dir_path ($current_perms -> $permissions)"
      run chmod "$permissions" "$dir_path"
    else
      log_debug "Directory permissions already correct: $dir_path ($permissions)"
    fi
  fi
}

#--------------------------------------------------------------------------------------------------
# Idempotent file backup - only backup if source is newer or backup doesn't exist
#--------------------------------------------------------------------------------------------------
backup_file_safe() {
  local source_file="$1"
  local backup_file="$2"
  
  [[ -f "$source_file" ]] || die "Source file does not exist: $source_file"
  
  # Create backup directory if needed
  local backup_parent
  backup_parent="$(dirname "$backup_file")"
  create_directory_safe "$backup_parent"
  
  # Idempotent: Only backup if needed
  if [[ ! -f "$backup_file" ]]; then
    log_info "Creating initial backup: $source_file -> $backup_file"
    run cp "$source_file" "$backup_file"
  elif [[ "$source_file" -nt "$backup_file" ]]; then
    log_info "Updating backup (source is newer): $source_file -> $backup_file"
    run cp "$source_file" "$backup_file"
  else
    log_debug "Backup is current: $backup_file"
  fi
}

#--------------------------------------------------------------------------------------------------
# Idempotent configuration line addition - only add if line doesn't exist
#--------------------------------------------------------------------------------------------------
ensure_config_line() {
  local config_file="$1"
  local config_line="$2"
  local comment="${3:-# Added by $(basename "$0")}"
  
  [[ -f "$config_file" ]] || die "Configuration file does not exist: $config_file"
  
  # Idempotent: Check if line already exists
  if grep -qF "$config_line" "$config_file"; then
    log_debug "Configuration line already present: $config_line"
  else
    log_info "Adding configuration line to $config_file: $config_line"
    backup_file_safe "$config_file" "${config_file}.bak"
    run bash -c "echo '$comment' >> '$config_file'"
    run bash -c "echo '$config_line' >> '$config_file'"
  fi
}

#--------------------------------------------------------------------------------------------------
# Idempotent symbolic link creation - safe force creation
#--------------------------------------------------------------------------------------------------
create_symlink_safe() {
  local target="$1"
  local link_name="$2"
  
  [[ -e "$target" ]] || die "Link target does not exist: $target"
  
  # Create parent directory if needed
  local link_parent
  link_parent="$(dirname "$link_name")"
  create_directory_safe "$link_parent"
  
  # Idempotent: Remove existing link/file and create new one
  if [[ -L "$link_name" ]]; then
    local current_target
    current_target="$(readlink "$link_name")"
    if [[ "$current_target" == "$target" ]]; then
      log_debug "Symbolic link already correct: $link_name -> $target"
      return 0
    else
      log_info "Updating symbolic link: $link_name ($current_target -> $target)"
    fi
  elif [[ -e "$link_name" ]]; then
    log_warn "Removing existing file to create symbolic link: $link_name"
  else
    log_info "Creating symbolic link: $link_name -> $target"
  fi
  
  # Force creation - removes existing file/link
  run ln -sfn "$target" "$link_name"
}

#--------------------------------------------------------------------------------------------------
# Idempotent file template processing - only update if template is newer
#--------------------------------------------------------------------------------------------------
process_template_safe() {
  local template_file="$1"
  local output_file="$2"
  local var_prefix="${3:-TEMPLATE_}"
  
  [[ -f "$template_file" ]] || die "Template file does not exist: $template_file"
  
  # Create output directory if needed
  local output_parent
  output_parent="$(dirname "$output_file")"
  create_directory_safe "$output_parent"
  
  # Idempotent: Only process if template is newer or output doesn't exist
  if [[ ! -f "$output_file" ]] || [[ "$template_file" -nt "$output_file" ]]; then
    log_info "Processing template: $template_file -> $output_file"
    backup_file_safe "$output_file" "${output_file}.bak" 2>/dev/null || true
    
    # Simple variable substitution using envsubst pattern
    # Export variables with the specified prefix for template processing
    local temp_file
    temp_file="$(mktemp)"
    
    # Process template - replace ${TEMPLATE_VAR} with actual values
    run envsubst < "$template_file" > "$temp_file"
    run mv "$temp_file" "$output_file"
    
    log_info "Template processed successfully: $output_file"
  else
    log_debug "Template output is current: $output_file"
  fi
}

usage() {
  local code="${1:-0}"
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS] --config-dir <path> --backup-dir <path>

Demonstrates idempotent file operation patterns for enterprise automation.

Options:
  --config-dir <path>    Directory for configuration files (required)
  --backup-dir <path>    Directory for file backups (required)
  -d, --dry-run          Show actions without executing
  -v, --verbose          Enable verbose (debug) logging
  -h, --help             Show this help

Examples:
  $SCRIPT_NAME --config-dir /etc/myapp --backup-dir /var/backups/myapp
  $SCRIPT_NAME --config-dir /opt/app/etc --backup-dir /opt/app/backups --dry-run

This script demonstrates:
  - Safe directory creation with permission management
  - Idempotent file backup operations
  - Configuration line management
  - Symbolic link creation and updates
  - Template processing with change detection
EOF
  exit "$code"
}

parse_args() {
  [[ $# -eq 0 ]] && usage 1
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config-dir)  [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; CONFIG_DIR="$2"; shift 2 ;;
      --backup-dir)  [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; BACKUP_DIR="$2"; shift 2 ;;
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
  
  # Validate required arguments
  [[ -n "$CONFIG_DIR" ]] || { log_error "Config directory is required."; usage 1; }
  [[ -n "$BACKUP_DIR" ]] || { log_error "Backup directory is required."; usage 1; }
  
  log_info "Starting idempotent file operations demonstration"
  log_debug "CONFIG_DIR=${CONFIG_DIR}" "BACKUP_DIR=${BACKUP_DIR}" "DRY_RUN=${DRY_RUN}"
  
  # Demonstrate idempotent patterns
  
  # 1. Create directory structure
  log_info "=== Demonstrating directory creation ==="
  create_directory_safe "$CONFIG_DIR"
  create_directory_safe "$BACKUP_DIR"
  create_directory_safe "$CONFIG_DIR/templates"
  create_directory_safe "$CONFIG_DIR/processed" "750"
  
  # 2. Create sample files for demonstration
  log_info "=== Creating sample files ==="
  local sample_config="$CONFIG_DIR/app.conf"
  local sample_template="$CONFIG_DIR/templates/service.conf.template"
  
  if [[ "$DRY_RUN" -eq 0 ]]; then
    # Create sample configuration file
    cat > "$sample_config" <<EOF
# Sample application configuration
app_name=myapp
app_version=1.0.0
log_level=INFO
EOF
    
    # Create sample template
    cat > "$sample_template" <<EOF
# Generated configuration for \${TEMPLATE_SERVICE_NAME}
service_name=\${TEMPLATE_SERVICE_NAME}
service_port=\${TEMPLATE_SERVICE_PORT}
service_env=\${TEMPLATE_SERVICE_ENV}
EOF
  fi
  
  # 3. Demonstrate backup operations
  log_info "=== Demonstrating backup operations ==="
  backup_file_safe "$sample_config" "$BACKUP_DIR/app.conf.backup"
  
  # 4. Demonstrate configuration management
  log_info "=== Demonstrating configuration management ==="
  ensure_config_line "$sample_config" "debug_mode=false" "# Added by automation"
  ensure_config_line "$sample_config" "maintenance_window=02:00-04:00"
  
  # 5. Demonstrate symbolic links
  log_info "=== Demonstrating symbolic link management ==="
  create_symlink_safe "$sample_config" "$CONFIG_DIR/current.conf"
  create_symlink_safe "$BACKUP_DIR" "$CONFIG_DIR/backups"
  
  # 6. Demonstrate template processing
  log_info "=== Demonstrating template processing ==="
  export TEMPLATE_SERVICE_NAME="web-server"
  export TEMPLATE_SERVICE_PORT="8080"
  export TEMPLATE_SERVICE_ENV="production"
  
  process_template_safe "$sample_template" "$CONFIG_DIR/processed/web-server.conf"
  
  log_info "Idempotent file operations demonstration completed successfully"
  log_info "Results can be found in: $CONFIG_DIR"
  log_info "Backups are stored in: $BACKUP_DIR"
}

# --- Invocation ---
main "$@"