#!/usr/bin/env bash
# shellcheck shell=bash
#--------------------------------------------------------------------------------------------------
# SCRIPT:       iac-wrapper.sh
# PURPOSE:      Terraform Infrastructure as Code wrapper with enterprise framework integration
# VERSION:      1.0.0
# REPOSITORY:   https://github.com/vintagedon/enterprise-aiops-bash
# LICENSE:      MIT
# USAGE:        ./iac-wrapper.sh --action plan --workspace production --var-file prod.tfvars
#
# NOTES:
#   This wrapper provides enterprise-grade Terraform execution with comprehensive logging,
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

# Terraform-specific configuration
TERRAFORM_ACTION="${TERRAFORM_ACTION:-}"
TERRAFORM_WORKSPACE="${TERRAFORM_WORKSPACE:-default}"
TERRAFORM_CONFIG_DIR="${TERRAFORM_CONFIG_DIR:-.}"
TERRAFORM_VAR_FILE="${TERRAFORM_VAR_FILE:-}"
TERRAFORM_BACKEND_CONFIG="${TERRAFORM_BACKEND_CONFIG:-}"
TERRAFORM_PARALLELISM="${TERRAFORM_PARALLELISM:-10}"
TERRAFORM_AUTO_APPROVE="${TERRAFORM_AUTO_APPROVE:-0}"
TERRAFORM_REFRESH="${TERRAFORM_REFRESH:-1}"
TERRAFORM_LOCK="${TERRAFORM_LOCK:-1}"
TERRAFORM_LOCK_TIMEOUT="${TERRAFORM_LOCK_TIMEOUT:-300s}"
TERRAFORM_TARGET="${TERRAFORM_TARGET:-}"
TERRAFORM_VAR="${TERRAFORM_VAR:-}"

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
# Validates Terraform installation and configuration
#--------------------------------------------------------------------------------------------------
validate_terraform_environment() {
  log_info "Validating Terraform environment"
  
  # Check Terraform installation
  require_cmd terraform
  
  # Validate Terraform version
  local terraform_version
  terraform_version=$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || echo "unknown")
  log_info "Terraform version: $terraform_version"
  
  # Verify minimum version (1.0+)
  if [[ "$terraform_version" != "unknown" ]]; then
    local major_version
    major_version=$(echo "$terraform_version" | cut -d'.' -f1)
    if [[ "$major_version" -lt 1 ]]; then
      log_warn "Terraform version is older than 1.0, some features may not work correctly"
    fi
  fi
  
  # Check configuration directory
  [[ -d "$TERRAFORM_CONFIG_DIR" ]] || die "Terraform configuration directory not found: $TERRAFORM_CONFIG_DIR"
  [[ -r "$TERRAFORM_CONFIG_DIR" ]] || die "Terraform configuration directory not readable: $TERRAFORM_CONFIG_DIR"
  
  # Verify Terraform files exist
  if ! find "$TERRAFORM_CONFIG_DIR" -name "*.tf" -type f | head -1 | grep -q .; then
    die "No Terraform configuration files (.tf) found in: $TERRAFORM_CONFIG_DIR"
  fi
  
  log_debug "Terraform environment validation completed"
}

#--------------------------------------------------------------------------------------------------
# Validates Terraform configuration syntax
# @param $1  Configuration directory path
#--------------------------------------------------------------------------------------------------
validate_terraform_config() {
  local config_dir="$1"
  
  log_info "Validating Terraform configuration: $config_dir"
  
  # Change to configuration directory
  cd "$config_dir" || die "Cannot access configuration directory: $config_dir"
  
  # Initialize if needed (for validation only)
  if [[ ! -d ".terraform" ]]; then
    log_debug "Initializing Terraform for validation"
    if ! run terraform init -backend=false >/dev/null 2>&1; then
      log_warn "Terraform init failed, proceeding with format validation only"
    fi
  fi
  
  # Validate format
  log_debug "Checking Terraform format"
  if ! terraform fmt -check=true -diff=false >/dev/null 2>&1; then
    log_warn "Terraform configuration formatting issues detected"
    if [[ "$VERBOSE" -eq 1 ]]; then
      terraform fmt -check=true -diff=true
    fi
  fi
  
  # Validate configuration
  log_debug "Validating Terraform configuration syntax"
  if run terraform validate >/dev/null 2>&1; then
    log_debug "Terraform configuration validation passed"
  else
    die "Terraform configuration validation failed"
  fi
}

#--------------------------------------------------------------------------------------------------
# Validates workspace name and switches to it
# @param $1  Workspace name
#--------------------------------------------------------------------------------------------------
validate_and_select_workspace() {
  local workspace_name="$1"
  
  [[ -n "$workspace_name" ]] || die "Workspace name cannot be empty"
  
  # Validate workspace name format
  if ! [[ "$workspace_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    die "Invalid workspace name format: $workspace_name (alphanumeric, underscore, hyphen only)"
  fi
  
  log_info "Managing Terraform workspace: $workspace_name"
  
  # Get current workspace
  local current_workspace
  current_workspace=$(terraform workspace show 2>/dev/null || echo "unknown")
  
  if [[ "$current_workspace" == "$workspace_name" ]]; then
    log_debug "Already in correct workspace: $workspace_name"
  else
    # List available workspaces
    local available_workspaces
    available_workspaces=$(terraform workspace list 2>/dev/null | sed 's/^[* ] //' | tr '\n' ' ')
    
    # Check if workspace exists
    if echo "$available_workspaces" | grep -qw "$workspace_name"; then
      log_info "Switching to existing workspace: $workspace_name"
      run terraform workspace select "$workspace_name"
    else
      log_info "Creating new workspace: $workspace_name"
      run terraform workspace new "$workspace_name"
    fi
  fi
  
  # Verify workspace selection
  current_workspace=$(terraform workspace show)
  [[ "$current_workspace" == "$workspace_name" ]] || die "Failed to select workspace: $workspace_name"
  
  log_debug "Workspace validation completed: $workspace_name"
}

#--------------------------------------------------------------------------------------------------
# Validates variable files and variables
# @param $1  Variable file path (optional)
# @param $2  Variable string (optional)
#--------------------------------------------------------------------------------------------------
validate_terraform_variables() {
  local var_file="$1"
  local var_string="$2"
  
  # Validate variable file if provided
  if [[ -n "$var_file" ]]; then
    [[ -f "$var_file" ]] || die "Variable file not found: $var_file"
    [[ -r "$var_file" ]] || die "Variable file not readable: $var_file"
    
    log_debug "Validating variable file: $var_file"
    
    # Check file format (should be .tfvars or .json)
    if [[ "$var_file" =~ \.(tfvars|json)$ ]]; then
      # Validate JSON format if it's a .json file
      if [[ "$var_file" =~ \.json$ ]]; then
        if ! jq . "$var_file" >/dev/null 2>&1; then
          die "Invalid JSON format in variable file: $var_file"
        fi
      fi
      log_debug "Variable file format validation passed"
    else
      log_warn "Variable file should have .tfvars or .json extension: $var_file"
    fi
  fi
  
  # Validate variable string if provided
  if [[ -n "$var_string" ]]; then
    log_debug "Validating variable string"
    
    # Check for dangerous characters
    if [[ "$var_string" =~ [;&|<>$`()] ]]; then
      die "Dangerous characters detected in variable string: $var_string"
    fi
    
    # Validate key=value format
    if ! [[ "$var_string" =~ ^[a-zA-Z0-9_]+=.* ]]; then
      die "Invalid variable format (expected key=value): $var_string"
    fi
    
    log_debug "Variable string validation passed"
  fi
}

#--------------------------------------------------------------------------------------------------
# Executes Terraform initialization with comprehensive logging
#--------------------------------------------------------------------------------------------------
execute_terraform_init() {
  local execution_id="terraform_init_$(date +%s)_$$"
  local start_time end_time duration
  local init_command=("terraform" "init")
  local init_output_file init_error_file
  
  log_info "Starting Terraform initialization"
  
  # Create temporary files for output capture
  init_output_file=$(mktemp "/tmp/terraform_init_output_${execution_id}.XXXXXX")
  init_error_file=$(mktemp "/tmp/terraform_init_error_${execution_id}.XXXXXX")
  
  # Add backend configuration if provided
  if [[ -n "$TERRAFORM_BACKEND_CONFIG" ]]; then
    [[ -f "$TERRAFORM_BACKEND_CONFIG" ]] || die "Backend config file not found: $TERRAFORM_BACKEND_CONFIG"
    init_command+=("-backend-config=$TERRAFORM_BACKEND_CONFIG")
  fi
  
  # Add additional init options
  init_command+=("-input=false")
  
  # Log execution start
  start_time=$(date +%s)
  log_structured "INFO" "Terraform init started" \
    "execution_id" "$execution_id" \
    "command" "${init_command[*]}" \
    "config_dir" "$TERRAFORM_CONFIG_DIR"
  
  # Execute initialization
  local exit_code=0
  "${init_command[@]}" >"$init_output_file" 2>"$init_error_file" || exit_code=$?
  
  # Calculate execution time
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  
  # Process output
  local init_stdout init_stderr
  init_stdout=$(cat "$init_output_file" 2>/dev/null || echo "")
  init_stderr=$(cat "$init_error_file" 2>/dev/null || echo "")
  
  # Log execution completion
  log_structured "INFO" "Terraform init completed" \
    "execution_id" "$execution_id" \
    "exit_code" "$exit_code" \
    "duration_seconds" "$duration" \
    "status" "$([[ "$exit_code" -eq 0 ]] && echo "success" || echo "error")"
  
  # Output results if verbose or failed
  if [[ "$VERBOSE" -eq 1 ]] || [[ "$exit_code" -ne 0 ]]; then
    log_info "Terraform init output:"
    echo "$init_stdout"
    
    if [[ -n "$init_stderr" ]]; then
      log_warn "Terraform init stderr:"
      echo "$init_stderr"
    fi
  fi
  
  # Clean up temporary files
  rm -f "$init_output_file" "$init_error_file"
  
  if [[ "$exit_code" -eq 0 ]]; then
    log_info "Terraform initialization completed successfully"
  else
    die "Terraform initialization failed"
  fi
}

#--------------------------------------------------------------------------------------------------
# Executes Terraform plan with comprehensive analysis
#--------------------------------------------------------------------------------------------------
execute_terraform_plan() {
  local execution_id="terraform_plan_$(date +%s)_$$"
  local start_time end_time duration
  local plan_command=("terraform" "plan")
  local plan_output_file plan_error_file plan_file
  
  log_info "Starting Terraform plan execution"
  
  # Create temporary files
  plan_output_file=$(mktemp "/tmp/terraform_plan_output_${execution_id}.XXXXXX")
  plan_error_file=$(mktemp "/tmp/terraform_plan_error_${execution_id}.XXXXXX")
  plan_file="/tmp/terraform_plan_${execution_id}.tfplan"
  
  # Build plan command
  plan_command+=("-out=$plan_file")
  plan_command+=("-input=false")
  plan_command+=("-detailed-exitcode")
  
  # Add parallelism
  plan_command+=("-parallelism=$TERRAFORM_PARALLELISM")
  
  # Add refresh option
  if [[ "$TERRAFORM_REFRESH" -eq 0 ]]; then
    plan_command+=("-refresh=false")
  fi
  
  # Add lock options
  if [[ "$TERRAFORM_LOCK" -eq 0 ]]; then
    plan_command+=("-lock=false")
  else
    plan_command+=("-lock-timeout=$TERRAFORM_LOCK_TIMEOUT")
  fi
  
  # Add variable file
  if [[ -n "$TERRAFORM_VAR_FILE" ]]; then
    validate_terraform_variables "$TERRAFORM_VAR_FILE" ""
    plan_command+=("-var-file=$TERRAFORM_VAR_FILE")
  fi
  
  # Add individual variables
  if [[ -n "$TERRAFORM_VAR" ]]; then
    validate_terraform_variables "" "$TERRAFORM_VAR"
    plan_command+=("-var=$TERRAFORM_VAR")
  fi
  
  # Add target if specified
  if [[ -n "$TERRAFORM_TARGET" ]]; then
    plan_command+=("-target=$TERRAFORM_TARGET")
  fi
  
  # Log execution start
  start_time=$(date +%s)
  log_structured "INFO" "Terraform plan started" \
    "execution_id" "$execution_id" \
    "command" "${plan_command[*]}" \
    "workspace" "$TERRAFORM_WORKSPACE" \
    "plan_file" "$plan_file"
  
  # Execute plan
  local exit_code=0
  "${plan_command[@]}" >"$plan_output_file" 2>"$plan_error_file" || exit_code=$?
  
  # Calculate execution time
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  
  # Process output
  local plan_stdout plan_stderr
  plan_stdout=$(cat "$plan_output_file" 2>/dev/null || echo "")
  plan_stderr=$(cat "$plan_error_file" 2>/dev/null || echo "")
  
  # Analyze plan results
  local plan_status="unknown"
  local changes_detected=0
  
  case "$exit_code" in
    0)
      plan_status="no_changes"
      ;;
    1)
      plan_status="error"
      ;;
    2)
      plan_status="changes_detected"
      changes_detected=1
      ;;
  esac
  
  # Extract change statistics from plan output
  local add_count change_count destroy_count
  add_count=$(echo "$plan_stdout" | grep -c "will be created" || echo "0")
  change_count=$(echo "$plan_stdout" | grep -c "will be updated" || echo "0")
  destroy_count=$(echo "$plan_stdout" | grep -c "will be destroyed" || echo "0")
  
  # Log execution completion
  log_structured "INFO" "Terraform plan completed" \
    "execution_id" "$execution_id" \
    "exit_code" "$exit_code" \
    "duration_seconds" "$duration" \
    "plan_status" "$plan_status" \
    "changes_detected" "$changes_detected" \
    "add_count" "$add_count" \
    "change_count" "$change_count" \
    "destroy_count" "$destroy_count"
  
  # Always show plan output for review
  log_info "Terraform plan output:"
  echo "$plan_stdout"
  
  if [[ -n "$plan_stderr" ]]; then
    log_warn "Terraform plan stderr:"
    echo "$plan_stderr"
  fi
  
  # Clean up temporary files but keep plan file for apply
  rm -f "$plan_output_file" "$plan_error_file"
  
  if [[ "$exit_code" -eq 0 || "$exit_code" -eq 2 ]]; then
    log_info "Terraform plan completed successfully"
    echo "$plan_file"  # Return plan file path for apply
  else
    rm -f "$plan_file"
    die "Terraform plan failed"
  fi
}

#--------------------------------------------------------------------------------------------------
# Executes Terraform apply with safety controls
# @param $1  Plan file path
#--------------------------------------------------------------------------------------------------
execute_terraform_apply() {
  local plan_file="$1"
  local execution_id="terraform_apply_$(date +%s)_$$"
  local start_time end_time duration
  local apply_command=("terraform" "apply")
  local apply_output_file apply_error_file
  
  [[ -f "$plan_file" ]] || die "Plan file not found for apply: $plan_file"
  
  log_info "Starting Terraform apply execution"
  
  # Safety check for auto-approve
  if [[ "$TERRAFORM_AUTO_APPROVE" -eq 0 && "$DRY_RUN" -eq 0 ]]; then
    log_warn "Apply requires manual approval. Use --auto-approve to skip confirmation."
    echo "Do you want to apply these changes? (yes/no): "
    read -r confirmation
    if [[ "$confirmation" != "yes" ]]; then
      log_info "Apply cancelled by user"
      rm -f "$plan_file"
      return 0
    fi
  fi
  
  # Create temporary files
  apply_output_file=$(mktemp "/tmp/terraform_apply_output_${execution_id}.XXXXXX")
  apply_error_file=$(mktemp "/tmp/terraform_apply_error_${execution_id}.XXXXXX")
  
  # Build apply command
  apply_command+=("$plan_file")
  apply_command+=("-input=false")
  
  # Add parallelism
  apply_command+=("-parallelism=$TERRAFORM_PARALLELISM")
  
  # Skip apply in dry-run mode
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "DRY RUN: Would execute: ${apply_command[*]}"
    rm -f "$plan_file"
    return 0
  fi
  
  # Log execution start
  start_time=$(date +%s)
  log_structured "INFO" "Terraform apply started" \
    "execution_id" "$execution_id" \
    "command" "${apply_command[*]}" \
    "workspace" "$TERRAFORM_WORKSPACE" \
    "plan_file" "$plan_file"
  
  # Execute apply
  local exit_code=0
  "${apply_command[@]}" >"$apply_output_file" 2>"$apply_error_file" || exit_code=$?
  
  # Calculate execution time
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  
  # Process output
  local apply_stdout apply_stderr
  apply_stdout=$(cat "$apply_output_file" 2>/dev/null || echo "")
  apply_stderr=$(cat "$apply_error_file" 2>/dev/null || echo "")
  
  # Extract apply statistics
  local applied_count destroyed_count
  applied_count=$(echo "$apply_stdout" | grep -c "Creation complete\|Modifications complete" || echo "0")
  destroyed_count=$(echo "$apply_stdout" | grep -c "Destruction complete" || echo "0")
  
  # Log execution completion
  log_structured "INFO" "Terraform apply completed" \
    "execution_id" "$execution_id" \
    "exit_code" "$exit_code" \
    "duration_seconds" "$duration" \
    "status" "$([[ "$exit_code" -eq 0 ]] && echo "success" || echo "error")" \
    "applied_count" "$applied_count" \
    "destroyed_count" "$destroyed_count"
  
  # Show apply output
  log_info "Terraform apply output:"
  echo "$apply_stdout"
  
  if [[ -n "$apply_stderr" ]]; then
    log_warn "Terraform apply stderr:"
    echo "$apply_stderr"
  fi
  
  # Clean up temporary files
  rm -f "$apply_output_file" "$apply_error_file" "$plan_file"
  
  if [[ "$exit_code" -eq 0 ]]; then
    log_info "Terraform apply completed successfully"
  else
    die "Terraform apply failed"
  fi
}

#--------------------------------------------------------------------------------------------------
# Executes Terraform destroy with safety controls
#--------------------------------------------------------------------------------------------------
execute_terraform_destroy() {
  local execution_id="terraform_destroy_$(date +%s)_$$"
  local start_time end_time duration
  local destroy_command=("terraform" "destroy")
  local destroy_output_file destroy_error_file
  
  log_warn "Starting Terraform destroy execution - THIS WILL DELETE INFRASTRUCTURE"
  
  # Safety confirmation
  if [[ "$TERRAFORM_AUTO_APPROVE" -eq 0 && "$DRY_RUN" -eq 0 ]]; then
    log_warn "Destroy will permanently delete infrastructure. This action cannot be undone."
    echo "Type 'DELETE' to confirm destruction: "
    read -r confirmation
    if [[ "$confirmation" != "DELETE" ]]; then
      log_info "Destroy cancelled by user"
      return 0
    fi
  fi
  
  # Create temporary files
  destroy_output_file=$(mktemp "/tmp/terraform_destroy_output_${execution_id}.XXXXXX")
  destroy_error_file=$(mktemp "/tmp/terraform_destroy_error_${execution_id}.XXXXXX")
  
  # Build destroy command
  destroy_command+=("-input=false")
  destroy_command+=("-parallelism=$TERRAFORM_PARALLELISM")
  
  # Add auto-approve if enabled
  if [[ "$TERRAFORM_AUTO_APPROVE" -eq 1 ]]; then
    destroy_command+=("-auto-approve")
  fi
  
  # Add variable file
  if [[ -n "$TERRAFORM_VAR_FILE" ]]; then
    destroy_command+=("-var-file=$TERRAFORM_VAR_FILE")
  fi
  
  # Add individual variables
  if [[ -n "$TERRAFORM_VAR" ]]; then
    destroy_command+=("-var=$TERRAFORM_VAR")
  fi
  
  # Add target if specified
  if [[ -n "$TERRAFORM_TARGET" ]]; then
    destroy_command+=("-target=$TERRAFORM_TARGET")
  fi
  
  # Skip destroy in dry-run mode
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "DRY RUN: Would execute: ${destroy_command[*]}"
    return 0
  fi
  
  # Log execution start
  start_time=$(date +%s)
  log_structured "INFO" "Terraform destroy started" \
    "execution_id" "$execution_id" \
    "command" "${destroy_command[*]}" \
    "workspace" "$TERRAFORM_WORKSPACE"
  
  # Execute destroy
  local exit_code=0
  "${destroy_command[@]}" >"$destroy_output_file" 2>"$destroy_error_file" || exit_code=$?
  
  # Calculate execution time
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  
  # Process output
  local destroy_stdout destroy_stderr
  destroy_stdout=$(cat "$destroy_output_file" 2>/dev/null || echo "")
  destroy_stderr=$(cat "$destroy_error_file" 2>/dev/null || echo "")
  
  # Extract destroy statistics
  local destroyed_count
  destroyed_count=$(echo "$destroy_stdout" | grep -c "Destruction complete" || echo "0")
  
  # Log execution completion
  log_structured "INFO" "Terraform destroy completed" \
    "execution_id" "$execution_id" \
    "exit_code" "$exit_code" \
    "duration_seconds" "$duration" \
    "status" "$([[ "$exit_code" -eq 0 ]] && echo "success" || echo "error")" \
    "destroyed_count" "$destroyed_count"
  
  # Show destroy output
  log_info "Terraform destroy output:"
  echo "$destroy_stdout"
  
  if [[ -n "$destroy_stderr" ]]; then
    log_warn "Terraform destroy stderr:"
    echo "$destroy_stderr"
  fi
  
  # Clean up temporary files
  rm -f "$destroy_output_file" "$destroy_error_file"
  
  if [[ "$exit_code" -eq 0 ]]; then
    log_info "Terraform destroy completed successfully"
  else
    die "Terraform destroy failed"
  fi
}

usage() {
  local code="${1:-0}"
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS] --action <action> [--workspace <name>]

Enterprise Terraform wrapper with comprehensive logging and operational controls.

Required Options:
  --action <action>         Terraform action: init, plan, apply, destroy, plan-apply

Optional Terraform Options:
  --workspace <name>        Terraform workspace (default: default)
  --config-dir <path>       Terraform configuration directory (default: .)
  --var-file <path>         Variables file (.tfvars or .json)
  --var <key=value>         Individual variable
  --backend-config <path>   Backend configuration file
  --target <resource>       Target specific resource
  --parallelism <n>         Parallel operations (default: 10)
  --lock-timeout <time>     Lock timeout (default: 300s)
  --no-refresh              Skip state refresh
  --no-lock                 Disable state locking
  --auto-approve            Skip manual approval for apply/destroy

Framework Options:
  -d, --dry-run             Enable dry-run mode (plan only)
  -v, --verbose             Enable verbose output and debug logging
  --read-only               Read-only mode (plan and validate only)
  -h, --help                Show this help

Actions:
  init                      Initialize Terraform configuration
  plan                      Create execution plan
  apply                     Apply changes from plan
  destroy                   Destroy infrastructure
  plan-apply                Plan and apply in sequence (if changes detected)

Examples:
  # Initialize and plan
  $SCRIPT_NAME --action init --workspace production
  $SCRIPT_NAME --action plan --workspace production --var-file prod.tfvars

  # Plan and apply with approval
  $SCRIPT_NAME --action plan-apply --workspace staging --var-file staging.tfvars

  # Destroy with confirmation
  $SCRIPT_NAME --action destroy --workspace development --auto-approve

  # Dry-run mode
  $SCRIPT_NAME --action plan --workspace production --dry-run

This wrapper provides:
  - Comprehensive input validation and security checks
  - Structured logging with execution tracking
  - Workspace management and validation
  - Safe execution controls and approval gates
  - Integration with enterprise framework patterns
EOF
  exit "$code"
}

parse_args() {
  [[ $# -eq 0 ]] && usage 1
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --action)           [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; TERRAFORM_ACTION="$2"; shift 2 ;;
      --workspace)        [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; TERRAFORM_WORKSPACE="$2"; shift 2 ;;
      --config-dir)       [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; TERRAFORM_CONFIG_DIR="$2"; shift 2 ;;
      --var-file)         [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; TERRAFORM_VAR_FILE="$2"; shift 2 ;;
      --var)              [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; TERRAFORM_VAR="$2"; shift 2 ;;
      --backend-config)   [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; TERRAFORM_BACKEND_CONFIG="$2"; shift 2 ;;
      --target)           [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; TERRAFORM_TARGET="$2"; shift 2 ;;
      --parallelism)      [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; TERRAFORM_PARALLELISM="$2"; shift 2 ;;
      --lock-timeout)     [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; TERRAFORM_LOCK_TIMEOUT="$2"; shift 2 ;;
      --no-refresh)       TERRAFORM_REFRESH=0; shift ;;
      --no-lock)          TERRAFORM_LOCK=0; shift ;;
      --auto-approve)     TERRAFORM_AUTO_APPROVE=1; shift ;;
      -d|--dry-run)       DRY_RUN=1; shift ;;
      -v|--verbose)       VERBOSE=1; LOG_LEVEL=10; shift ;;
      --read-only)        READ_ONLY=1; shift ;;
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
  [[ -n "$TERRAFORM_ACTION" ]] || { log_error "Action is required."; usage 1; }
  
  # Validate action
  case "$TERRAFORM_ACTION" in
    init|plan|apply|destroy|plan-apply) ;;
    *) die "Invalid action: $TERRAFORM_ACTION (use init, plan, apply, destroy, or plan-apply)" ;;
  esac
  
  log_info "Starting Terraform wrapper: $SCRIPT_NAME"
  log_debug "Configuration: action=$TERRAFORM_ACTION, workspace=$TERRAFORM_WORKSPACE, config_dir=$TERRAFORM_CONFIG_DIR"
  
  # Validate environment
  validate_terraform_environment
  validate_terraform_config "$TERRAFORM_CONFIG_DIR"
  
  # Change to configuration directory
  cd "$TERRAFORM_CONFIG_DIR" || die "Cannot access configuration directory: $TERRAFORM_CONFIG_DIR"
  
  # Handle read-only mode
  if [[ "$READ_ONLY" -eq 1 ]]; then
    case "$TERRAFORM_ACTION" in
      apply|destroy)
        log_warn "Read-only mode: changing $TERRAFORM_ACTION to plan"
        TERRAFORM_ACTION="plan"
        ;;
    esac
  fi
  
  # Execute action
  case "$TERRAFORM_ACTION" in
    init)
      execute_terraform_init
      ;;
    plan)
      execute_terraform_init
      validate_and_select_workspace "$TERRAFORM_WORKSPACE"
      execute_terraform_plan
      ;;
    apply)
      die "Apply action requires a plan file. Use plan-apply for complete workflow."
      ;;
    destroy)
      execute_terraform_init
      validate_and_select_workspace "$TERRAFORM_WORKSPACE"
      execute_terraform_destroy
      ;;
    plan-apply)
      execute_terraform_init
      validate_and_select_workspace "$TERRAFORM_WORKSPACE"
      local plan_file
      plan_file=$(execute_terraform_plan)
      if [[ -n "$plan_file" && -f "$plan_file" ]]; then
        execute_terraform_apply "$plan_file"
      else
        log_info "No changes detected, skipping apply"
      fi
      ;;
  esac
  
  log_info "Terraform wrapper completed successfully"
}

# --- Invocation ---
main "$@"
