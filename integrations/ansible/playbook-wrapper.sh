#!/usr/bin/env bash
# shellcheck shell=bash
#--------------------------------------------------------------------------------------------------
# SCRIPT:       playbook-wrapper.sh
# PURPOSE:      Ansible playbook wrapper with enterprise framework integration
# VERSION:      1.0.0
# REPOSITORY:   https://github.com/vintagedon/enterprise-aiops-bash
# LICENSE:      MIT
# USAGE:        ./playbook-wrapper.sh --playbook site.yml --inventory production --extra-vars env=prod
#
# NOTES:
#   This wrapper provides enterprise-grade Ansible execution with comprehensive logging,
#   security validation, and operational controls using the framework foundation.
#--------------------------------------------------------------------------------------------------

# --- Strict Mode & Security ---
set -Eeuo pipefail
IFS=$'\n\t'
umask 027

# --- Globals ---
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly START_TS="$(date -u +%FT%TZ)"

# Ansible-specific configuration
ANSIBLE_PLAYBOOK_PATH="${ANSIBLE_PLAYBOOK_PATH:-}"
ANSIBLE_INVENTORY="${ANSIBLE_INVENTORY:-}"
ANSIBLE_CONFIG="${ANSIBLE_CONFIG:-ansible.cfg}"
ANSIBLE_VAULT_PASSWORD_FILE="${ANSIBLE_VAULT_PASSWORD_FILE:-}"
ANSIBLE_EXTRA_VARS="${ANSIBLE_EXTRA_VARS:-}"
ANSIBLE_TAGS="${ANSIBLE_TAGS:-}"
ANSIBLE_SKIP_TAGS="${ANSIBLE_SKIP_TAGS:-}"
ANSIBLE_LIMIT="${ANSIBLE_LIMIT:-}"
ANSIBLE_CHECK_MODE="${ANSIBLE_CHECK_MODE:-0}"
ANSIBLE_DIFF_MODE="${ANSIBLE_DIFF_MODE:-0}"
ANSIBLE_VERBOSITY="${ANSIBLE_VERBOSITY:-1}"

# Framework integration
VERBOSE=0
DRY_RUN=0
READ_ONLY=0

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

#--------------------------------------------------------------------------------------------------
# Validates Ansible installation and configuration
#--------------------------------------------------------------------------------------------------
validate_ansible_environment() {
  log_info "Validating Ansible environment"
  
  # Check Ansible installation
  require_cmd ansible-playbook ansible-inventory
  
  # Validate Ansible version
  local ansible_version
  ansible_version=$(ansible --version | head -1 | awk '{print $2}' || echo "unknown")
  log_info "Ansible version: $ansible_version"
  
  # Check configuration file
  if [[ -n "$ANSIBLE_CONFIG" && -f "$ANSIBLE_CONFIG" ]]; then
    log_info "Using Ansible config: $ANSIBLE_CONFIG"
  else
    log_debug "No custom Ansible config specified, using defaults"
  fi
  
  # Validate Python installation for Ansible
  if ! python3 -c "import ansible" 2>/dev/null; then
    log_warn "Ansible Python module not found, may cause issues"
  fi
  
  log_debug "Ansible environment validation completed"
}

#--------------------------------------------------------------------------------------------------
# Validates playbook file and syntax
# @param $1  Path to playbook file
#--------------------------------------------------------------------------------------------------
validate_playbook() {
  local playbook_path="$1"
  
  [[ -n "$playbook_path" ]] || die "Playbook path cannot be empty"
  [[ -f "$playbook_path" ]] || die "Playbook file not found: $playbook_path"
  [[ -r "$playbook_path" ]] || die "Playbook file not readable: $playbook_path"
  
  log_info "Validating playbook: $playbook_path"
  
  # Check YAML syntax
  if command -v yamllint >/dev/null 2>&1; then
    if ! yamllint "$playbook_path" >/dev/null 2>&1; then
      log_warn "YAML syntax issues detected in playbook (yamllint)"
    fi
  fi
  
  # Ansible syntax check
  log_debug "Running Ansible syntax check"
  if run ansible-playbook --syntax-check "$playbook_path" >/dev/null 2>&1; then
    log_debug "Playbook syntax validation passed"
  else
    die "Playbook syntax validation failed: $playbook_path"
  fi
}

#--------------------------------------------------------------------------------------------------
# Validates inventory file and configuration
# @param $1  Path to inventory file or directory
#--------------------------------------------------------------------------------------------------
validate_inventory() {
  local inventory_path="$1"
  
  [[ -n "$inventory_path" ]] || die "Inventory path cannot be empty"
  
  if [[ -f "$inventory_path" ]]; then
    [[ -r "$inventory_path" ]] || die "Inventory file not readable: $inventory_path"
    log_debug "Using inventory file: $inventory_path"
  elif [[ -d "$inventory_path" ]]; then
    [[ -r "$inventory_path" ]] || die "Inventory directory not accessible: $inventory_path"
    log_debug "Using inventory directory: $inventory_path"
  else
    die "Inventory path not found: $inventory_path"
  fi
  
  log_info "Validating inventory: $inventory_path"
  
  # Test inventory parsing
  if run ansible-inventory -i "$inventory_path" --list >/dev/null 2>&1; then
    log_debug "Inventory validation passed"
  else
    die "Inventory validation failed: $inventory_path"
  fi
  
  # Count hosts for operational awareness
  local host_count
  host_count=$(ansible-inventory -i "$inventory_path" --list 2>/dev/null | jq '[.._meta.hostvars | keys] | flatten | unique | length' 2>/dev/null || echo "unknown")
  log_info "Target hosts in inventory: $host_count"
}

#--------------------------------------------------------------------------------------------------
# Validates and sanitizes extra variables
# @param $1  Extra variables string
#--------------------------------------------------------------------------------------------------
validate_extra_vars() {
  local extra_vars="$1"
  
  [[ -n "$extra_vars" ]] || return 0  # Empty is valid
  
  log_debug "Validating extra variables: $extra_vars"
  
  # Check for shell metacharacters
  if [[ "$extra_vars" =~ [;&|<>$`()] ]]; then
    die "Dangerous characters detected in extra variables: $extra_vars"
  fi
  
  # Validate JSON format if it looks like JSON
  if [[ "$extra_vars" =~ ^\{.*\}$ ]]; then
    if ! echo "$extra_vars" | jq . >/dev/null 2>&1; then
      die "Invalid JSON format in extra variables: $extra_vars"
    fi
    log_debug "Extra variables JSON validation passed"
  fi
  
  # Validate key=value format if it looks like that
  if [[ "$extra_vars" =~ ^[a-zA-Z0-9_]+=.* ]]; then
    # Simple key=value validation
    if ! [[ "$extra_vars" =~ ^[a-zA-Z0-9_,=\ \"\'.-]+$ ]]; then
      die "Invalid characters in key=value extra variables: $extra_vars"
    fi
    log_debug "Extra variables key=value validation passed"
  fi
}

#--------------------------------------------------------------------------------------------------
# Executes Ansible playbook with comprehensive logging and error handling
# @param $1  Playbook path
# @param $2  Inventory path
#--------------------------------------------------------------------------------------------------
execute_ansible_playbook() {
  local playbook_path="$1"
  local inventory_path="$2"
  local execution_id="ansible_$(date +%s)_$$"
  local start_time end_time duration
  local ansible_command=()
  local ansible_output_file ansible_error_file
  
  log_info "Starting Ansible playbook execution: $playbook_path"
  
  # Create temporary files for output capture
  ansible_output_file=$(mktemp "/tmp/ansible_output_${execution_id}.XXXXXX")
  ansible_error_file=$(mktemp "/tmp/ansible_error_${execution_id}.XXXXXX")
  
  # Build Ansible command
  ansible_command=(
    "ansible-playbook"
    "-i" "$inventory_path"
    "$playbook_path"
  )
  
  # Add verbosity
  local verbosity_flags=""
  for ((i=1; i<=ANSIBLE_VERBOSITY; i++)); do
    verbosity_flags="${verbosity_flags}v"
  done
  if [[ -n "$verbosity_flags" ]]; then
    ansible_command+=("-${verbosity_flags}")
  fi
  
  # Add operational flags
  if [[ "$ANSIBLE_CHECK_MODE" -eq 1 ]] || [[ "$DRY_RUN" -eq 1 ]]; then
    ansible_command+=("--check")
    log_info "Running in check mode (dry-run)"
  fi
  
  if [[ "$ANSIBLE_DIFF_MODE" -eq 1 ]]; then
    ansible_command+=("--diff")
  fi
  
  # Add optional parameters
  if [[ -n "$ANSIBLE_VAULT_PASSWORD_FILE" ]]; then
    [[ -f "$ANSIBLE_VAULT_PASSWORD_FILE" ]] || die "Vault password file not found: $ANSIBLE_VAULT_PASSWORD_FILE"
    ansible_command+=("--vault-password-file" "$ANSIBLE_VAULT_PASSWORD_FILE")
  fi
  
  if [[ -n "$ANSIBLE_EXTRA_VARS" ]]; then
    validate_extra_vars "$ANSIBLE_EXTRA_VARS"
    ansible_command+=("--extra-vars" "$ANSIBLE_EXTRA_VARS")
  fi
  
  if [[ -n "$ANSIBLE_TAGS" ]]; then
    ansible_command+=("--tags" "$ANSIBLE_TAGS")
  fi
  
  if [[ -n "$ANSIBLE_SKIP_TAGS" ]]; then
    ansible_command+=("--skip-tags" "$ANSIBLE_SKIP_TAGS")
  fi
  
  if [[ -n "$ANSIBLE_LIMIT" ]]; then
    ansible_command+=("--limit" "$ANSIBLE_LIMIT")
  fi
  
  # Log execution details
  start_time=$(date +%s)
  log_structured "INFO" "Ansible execution started" \
    "execution_id" "$execution_id" \
    "playbook_path" "$playbook_path" \
    "inventory_path" "$inventory_path" \
    "check_mode" "$([[ "$ANSIBLE_CHECK_MODE" -eq 1 || "$DRY_RUN" -eq 1 ]] && echo "true" || echo "false")" \
    "command" "${ansible_command[*]}"
  
  # Execute Ansible playbook
  local exit_code=0
  "${ansible_command[@]}" >"$ansible_output_file" 2>"$ansible_error_file" || exit_code=$?
  
  # Calculate execution time
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  
  # Process output
  local ansible_stdout ansible_stderr
  ansible_stdout=$(cat "$ansible_output_file" 2>/dev/null || echo "")
  ansible_stderr=$(cat "$ansible_error_file" 2>/dev/null || echo "")
  
  # Parse Ansible results if successful
  local task_stats=""
  if [[ "$exit_code" -eq 0 ]]; then
    # Extract task statistics from Ansible output
    task_stats=$(echo "$ansible_stdout" | grep -E "^PLAY RECAP" -A 20 | tail -n +2 || echo "")
  fi
  
  # Determine execution status
  local status="success"
  local status_message="Playbook executed successfully"
  
  if [[ "$exit_code" -ne 0 ]]; then
    status="error"
    status_message="Playbook execution failed with exit code $exit_code"
  fi
  
  # Log execution completion
  log_structured "INFO" "Ansible execution completed" \
    "execution_id" "$execution_id" \
    "playbook_path" "$playbook_path" \
    "status" "$status" \
    "exit_code" "$exit_code" \
    "duration_seconds" "$duration" \
    "task_statistics" "$task_stats"
  
  # Output results
  if [[ "$VERBOSE" -eq 1 ]] || [[ "$exit_code" -ne 0 ]]; then
    log_info "Ansible stdout:"
    echo "$ansible_stdout"
    
    if [[ -n "$ansible_stderr" ]]; then
      log_warn "Ansible stderr:"
      echo "$ansible_stderr"
    fi
  fi
  
  # Clean up temporary files
  rm -f "$ansible_output_file" "$ansible_error_file"
  
  # Report final status
  if [[ "$exit_code" -eq 0 ]]; then
    log_info "Ansible playbook execution completed successfully"
  else
    log_error "Ansible playbook execution failed"
  fi
  
  return "$exit_code"
}

#--------------------------------------------------------------------------------------------------
# Lists available playbooks in the current directory
#--------------------------------------------------------------------------------------------------
list_available_playbooks() {
  log_info "Available Ansible playbooks:"
  
  local playbook_count=0
  local playbook_file
  
  # Find YAML files that look like playbooks
  while IFS= read -r -d '' playbook_file; do
    if grep -q "^\s*-\s*hosts:\|^\s*-\s*name:" "$playbook_file" 2>/dev/null; then
      local playbook_name
      playbook_name=$(basename "$playbook_file")
      
      # Extract description if available
      local description
      description=$(grep "^# Description:" "$playbook_file" | sed 's/^# Description: *//' || echo "No description")
      
      log_info "  $playbook_name - $description"
      ((playbook_count++))
    fi
  done < <(find . -maxdepth 2 -name "*.yml" -o -name "*.yaml" -print0 2>/dev/null)
  
  if [[ "$playbook_count" -eq 0 ]]; then
    log_warn "No Ansible playbooks found in current directory"
  else
    log_info "Total playbooks found: $playbook_count"
  fi
}

usage() {
  local code="${1:-0}"
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS] --playbook <path> --inventory <path>

Enterprise Ansible playbook wrapper with comprehensive logging and validation.

Required Options:
  --playbook <path>         Path to Ansible playbook file
  --inventory <path>        Path to inventory file or directory

Optional Ansible Options:
  --extra-vars <vars>       Extra variables (key=value or JSON format)
  --tags <tags>             Only run plays and tasks tagged with these values
  --skip-tags <tags>        Skip plays and tasks with these tags
  --limit <pattern>         Limit execution to specific hosts/groups
  --vault-password-file <f> Vault password file for encrypted content
  --check                   Run in check mode (dry-run)
  --diff                    Show differences for changed files

Framework Options:
  -d, --dry-run             Enable dry-run mode (implies --check)
  -v, --verbose             Enable verbose output and debug logging
  --read-only               Read-only mode (same as --check)
  -h, --help                Show this help

Environment Variables:
  ANSIBLE_CONFIG            Path to Ansible configuration file
  ANSIBLE_VERBOSITY         Ansible verbosity level (1-4, default: 1)

Examples:
  # Basic playbook execution
  $SCRIPT_NAME --playbook site.yml --inventory production

  # Check mode with extra variables
  $SCRIPT_NAME --playbook deploy.yml --inventory staging \\
               --extra-vars "app_version=1.2.3 environment=staging" --check

  # Limited execution with tags
  $SCRIPT_NAME --playbook maintenance.yml --inventory production \\
               --tags "database,backup" --limit "db-servers"

  # List available playbooks
  $SCRIPT_NAME --list-playbooks

This wrapper provides:
  - Comprehensive input validation and security checks
  - Structured logging with execution tracking
  - Integration with enterprise framework patterns
  - Safe execution controls and operational modes
EOF
  exit "$code"
}

parse_args() {
  [[ $# -eq 0 ]] && usage 1
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --playbook)         [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; ANSIBLE_PLAYBOOK_PATH="$2"; shift 2 ;;
      --inventory)        [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; ANSIBLE_INVENTORY="$2"; shift 2 ;;
      --extra-vars)       [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; ANSIBLE_EXTRA_VARS="$2"; shift 2 ;;
      --tags)             [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; ANSIBLE_TAGS="$2"; shift 2 ;;
      --skip-tags)        [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; ANSIBLE_SKIP_TAGS="$2"; shift 2 ;;
      --limit)            [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; ANSIBLE_LIMIT="$2"; shift 2 ;;
      --vault-password-file) [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; ANSIBLE_VAULT_PASSWORD_FILE="$2"; shift 2 ;;
      --check)            ANSIBLE_CHECK_MODE=1; shift ;;
      --diff)             ANSIBLE_DIFF_MODE=1; shift ;;
      --list-playbooks)   list_available_playbooks; exit 0 ;;
      -d|--dry-run)       DRY_RUN=1; ANSIBLE_CHECK_MODE=1; shift ;;
      -v|--verbose)       VERBOSE=1; LOG_LEVEL=10; ANSIBLE_VERBOSITY=2; shift ;;
      --read-only)        READ_ONLY=1; ANSIBLE_CHECK_MODE=1; shift ;;
      -h|--help)          usage 0 ;;
      --) shift; break ;;
      -*) die "Unknown option: $1" ;;
      *)  break ;;
    esac
  done
}

main() {
  parse_args "$@"
  
  # Validate required parameters
  [[ -n "$ANSIBLE_PLAYBOOK_PATH" ]] || { log_error "Playbook path is required."; usage 1; }
  [[ -n "$ANSIBLE_INVENTORY" ]] || { log_error "Inventory path is required."; usage 1; }
  
  log_info "Starting Ansible playbook wrapper: $SCRIPT_NAME"
  log_debug "Configuration: playbook=$ANSIBLE_PLAYBOOK_PATH, inventory=$ANSIBLE_INVENTORY, check_mode=$ANSIBLE_CHECK_MODE"
  
  # Validate environment and inputs
  validate_ansible_environment
  validate_playbook "$ANSIBLE_PLAYBOOK_PATH"
  validate_inventory "$ANSIBLE_INVENTORY"
  
  # Execute playbook
  execute_ansible_playbook "$ANSIBLE_PLAYBOOK_PATH" "$ANSIBLE_INVENTORY"
  
  log_info "Ansible playbook wrapper completed successfully"
}

# --- Invocation ---
main "$@"
