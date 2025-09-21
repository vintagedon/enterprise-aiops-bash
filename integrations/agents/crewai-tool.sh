#!/usr/bin/env bash
# shellcheck shell=bash
#--------------------------------------------------------------------------------------------------
# SCRIPT:       crewai-tool.sh
# PURPOSE:      CrewAI tool integration for enterprise bash framework
# VERSION:      1.0.0
# REPOSITORY:   https://github.com/vintagedon/enterprise-aiops-bash
# LICENSE:      MIT
# USAGE:        source integrations/agents/crewai-tool.sh
#
# NOTES:
#   This script provides a CrewAI tool interface that wraps enterprise bash scripts
#   for safe execution by AI agents with comprehensive logging and validation.
#--------------------------------------------------------------------------------------------------

# --- Strict Mode & Security ---
set -Eeuo pipefail
IFS=$'\n\t'
umask 027

# --- Globals ---
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly START_TS="$(date -u +%FT%TZ)"

# CrewAI tool configuration
CREWAI_TOOL_NAME="${CREWAI_TOOL_NAME:-enterprise_bash_executor}"
CREWAI_TOOL_DESCRIPTION="${CREWAI_TOOL_DESCRIPTION:-Execute enterprise bash scripts with safety validation}"
CREWAI_SCRIPT_DIR="${CREWAI_SCRIPT_DIR:-../../template/examples}"
CREWAI_ALLOWED_SCRIPTS="${CREWAI_ALLOWED_SCRIPTS:-simple-example.sh}"
CREWAI_DRY_RUN_DEFAULT="${CREWAI_DRY_RUN_DEFAULT:-1}"
CREWAI_MAX_EXECUTION_TIME="${CREWAI_MAX_EXECUTION_TIME:-300}"

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
# Validates that a script is allowed to be executed by AI agents
# @param $1  Script name to validate
#--------------------------------------------------------------------------------------------------
validate_allowed_script() {
  local script_name="$1"
  local allowed_scripts_array
  
  [[ -n "$script_name" ]] || die "Script name cannot be empty"
  
  # Convert allowed scripts to array
  IFS=',' read -r -a allowed_scripts_array <<< "$CREWAI_ALLOWED_SCRIPTS"
  
  # Check if script is in allowed list
  local script_allowed=0
  for allowed_script in "${allowed_scripts_array[@]}"; do
    if [[ "$script_name" == "$allowed_script" ]]; then
      script_allowed=1
      break
    fi
  done
  
  [[ "$script_allowed" -eq 1 ]] || die "Script not in allowed list: $script_name"
  
  # Validate script exists and is executable
  local script_path="${CREWAI_SCRIPT_DIR}/${script_name}"
  [[ -f "$script_path" ]] || die "Script file not found: $script_path"
  [[ -x "$script_path" ]] || die "Script not executable: $script_path"
  
  log_debug "Script validation passed: $script_name"
}

#--------------------------------------------------------------------------------------------------
# Validates AI agent input parameters for security
# @param $@  Parameters to validate
#--------------------------------------------------------------------------------------------------
validate_agent_parameters() {
  local param
  
  for param in "$@"; do
    # Check for shell metacharacters
    if [[ "$param" =~ [;&|<>$`(){}[\]\\] ]]; then
      die "Dangerous characters detected in parameter: $param"
    fi
    
    # Check parameter length (prevent buffer overflow attacks)
    if [[ ${#param} -gt 1000 ]]; then
      die "Parameter too long (${#param} characters): ${param:0:50}..."
    fi
    
    # Log parameter for audit trail
    log_debug "Parameter validated: $param"
  done
}

#--------------------------------------------------------------------------------------------------
# Executes an enterprise bash script with AI agent safety controls
# @param $1  Script name
# @param $@  Script parameters
# @return    JSON response with execution results
#--------------------------------------------------------------------------------------------------
execute_enterprise_script() {
  local script_name="$1"
  shift
  local script_params=("$@")
  
  log_info "AI agent requesting script execution: $script_name"
  
  # Validate script and parameters
  validate_allowed_script "$script_name"
  validate_agent_parameters "${script_params[@]}"
  
  local script_path="${CREWAI_SCRIPT_DIR}/${script_name}"
  local execution_id="exec_$(date +%s)_$$"
  local start_time end_time duration
  local output_file error_file
  local exit_code=0
  
  # Create temporary files for output capture
  output_file=$(mktemp "/tmp/crewai_output_${execution_id}.XXXXXX")
  error_file=$(mktemp "/tmp/crewai_error_${execution_id}.XXXXXX")
  
  # Log execution start
  start_time=$(date +%s)
  log_structured "INFO" "Script execution started" \
    "execution_id" "$execution_id" \
    "script_name" "$script_name" \
    "parameters" "${script_params[*]}" \
    "agent_context" "crewai"
  
  # Execute script with timeout and output capture
  local execution_command=(
    timeout "$CREWAI_MAX_EXECUTION_TIME"
    "$script_path"
    "--dry-run"  # Force dry-run for AI agent safety
    "${script_params[@]}"
  )
  
  # Override dry-run if explicitly allowed
  if [[ "$CREWAI_DRY_RUN_DEFAULT" -eq 0 ]]; then
    execution_command=(
      timeout "$CREWAI_MAX_EXECUTION_TIME"
      "$script_path"
      "${script_params[@]}"
    )
  fi
  
  # Execute with output capture
  "${execution_command[@]}" >"$output_file" 2>"$error_file" || exit_code=$?
  
  # Calculate execution time
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  
  # Process results
  local stdout_content stderr_content
  stdout_content=$(cat "$output_file" 2>/dev/null || echo "")
  stderr_content=$(cat "$error_file" 2>/dev/null || echo "")
  
  # Determine execution status
  local status="success"
  local status_message="Script executed successfully"
  
  if [[ "$exit_code" -eq 124 ]]; then
    status="timeout"
    status_message="Script execution timed out after ${CREWAI_MAX_EXECUTION_TIME} seconds"
  elif [[ "$exit_code" -ne 0 ]]; then
    status="error"
    status_message="Script execution failed with exit code $exit_code"
  fi
  
  # Log execution completion
  log_structured "INFO" "Script execution completed" \
    "execution_id" "$execution_id" \
    "script_name" "$script_name" \
    "status" "$status" \
    "exit_code" "$exit_code" \
    "duration_seconds" "$duration"
  
  # Generate JSON response for CrewAI
  local response
  response=$(jq -n \
    --arg execution_id "$execution_id" \
    --arg script_name "$script_name" \
    --arg status "$status" \
    --arg status_message "$status_message" \
    --arg exit_code "$exit_code" \
    --arg duration "$duration" \
    --arg stdout "$stdout_content" \
    --arg stderr "$stderr_content" \
    --argjson dry_run "$CREWAI_DRY_RUN_DEFAULT" \
    '{
      execution_id: $execution_id,
      script_name: $script_name,
      status: $status,
      status_message: $status_message,
      exit_code: ($exit_code | tonumber),
      duration_seconds: ($duration | tonumber),
      dry_run_mode: $dry_run,
      output: {
        stdout: $stdout,
        stderr: $stderr
      },
      timestamp: now | strftime("%Y-%m-%dT%H:%M:%SZ")
    }')
  
  # Clean up temporary files
  rm -f "$output_file" "$error_file"
  
  # Return JSON response
  echo "$response"
  
  return "$exit_code"
}

#--------------------------------------------------------------------------------------------------
# Lists available scripts that can be executed by AI agents
# @return    JSON array of available scripts with metadata
#--------------------------------------------------------------------------------------------------
list_available_scripts() {
  log_info "AI agent requesting available scripts list"
  
  local scripts_array=()
  local allowed_scripts_array
  
  # Convert allowed scripts to array
  IFS=',' read -r -a allowed_scripts_array <<< "$CREWAI_ALLOWED_SCRIPTS"
  
  # Build script information array
  for script_name in "${allowed_scripts_array[@]}"; do
    local script_path="${CREWAI_SCRIPT_DIR}/${script_name}"
    
    if [[ -f "$script_path" && -x "$script_path" ]]; then
      # Extract script metadata
      local script_purpose script_version
      script_purpose=$(grep "^# PURPOSE:" "$script_path" | sed 's/^# PURPOSE:[[:space:]]*//' || echo "No description available")
      script_version=$(grep "^# VERSION:" "$script_path" | sed 's/^# VERSION:[[:space:]]*//' || echo "unknown")
      
      # Add script to array
      local script_info
      script_info=$(jq -n \
        --arg name "$script_name" \
        --arg purpose "$script_purpose" \
        --arg version "$script_version" \
        --arg path "$script_path" \
        --argjson dry_run_enforced "$CREWAI_DRY_RUN_DEFAULT" \
        '{
          name: $name,
          purpose: $purpose,
          version: $version,
          path: $path,
          dry_run_enforced: $dry_run_enforced,
          max_execution_time: 300
        }')
      
      scripts_array+=("$script_info")
    fi
  done
  
  # Generate JSON response
  local response
  response=$(jq -n \
    --argjson scripts "$(printf '%s\n' "${scripts_array[@]}" | jq -s .)" \
    --arg tool_name "$CREWAI_TOOL_NAME" \
    --arg tool_description "$CREWAI_TOOL_DESCRIPTION" \
    '{
      tool_name: $tool_name,
      tool_description: $tool_description,
      available_scripts: $scripts,
      script_count: ($scripts | length),
      security_features: [
        "Input validation",
        "Command sanitization", 
        "Execution timeout",
        "Dry-run enforcement",
        "Audit logging"
      ]
    }')
  
  echo "$response"
}

#--------------------------------------------------------------------------------------------------
# Retrieves script usage information for AI agent context
# @param $1  Script name
# @return    JSON object with usage information
#--------------------------------------------------------------------------------------------------
get_script_usage() {
  local script_name="$1"
  
  [[ -n "$script_name" ]] || die "Script name required for usage information"
  
  log_info "AI agent requesting usage information for: $script_name"
  
  # Validate script
  validate_allowed_script "$script_name"
  
  local script_path="${CREWAI_SCRIPT_DIR}/${script_name}"
  local usage_output
  
  # Extract usage information by running script with --help
  usage_output=$("$script_path" --help 2>&1 || echo "Usage information not available")
  
  # Generate JSON response
  local response
  response=$(jq -n \
    --arg script_name "$script_name" \
    --arg usage_text "$usage_output" \
    --argjson dry_run_enforced "$CREWAI_DRY_RUN_DEFAULT" \
    '{
      script_name: $script_name,
      usage_information: $usage_text,
      dry_run_enforced: $dry_run_enforced,
      security_notes: [
        "All parameters are validated for security",
        "Execution is limited by timeout",
        "All operations are logged for audit",
        "Dry-run mode is enforced by default"
      ]
    }')
  
  echo "$response"
}

#--------------------------------------------------------------------------------------------------
# Main CrewAI tool interface function
# @param $1  Action (execute|list|usage)
# @param $@  Additional parameters based on action
#--------------------------------------------------------------------------------------------------
crewai_tool_main() {
  local action="$1"
  shift || die "Action required (execute|list|usage)"
  
  case "$action" in
    execute)
      local script_name="$1"
      shift || die "Script name required for execute action"
      execute_enterprise_script "$script_name" "$@"
      ;;
    list)
      list_available_scripts
      ;;
    usage)
      local script_name="$1"
      shift || die "Script name required for usage action"
      get_script_usage "$script_name"
      ;;
    *)
      die "Unknown action: $action (use execute|list|usage)"
      ;;
  esac
}

# Tool initialization message
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  log_info "CrewAI Enterprise Bash Tool initialized"
  log_info "Tool name: $CREWAI_TOOL_NAME"
  log_info "Allowed scripts: $CREWAI_ALLOWED_SCRIPTS"
  log_info "Dry-run default: $CREWAI_DRY_RUN_DEFAULT"
  
  # If arguments provided, execute tool
  if [[ $# -gt 0 ]]; then
    crewai_tool_main "$@"
  else
    echo "CrewAI Enterprise Bash Tool"
    echo "Usage: $0 {execute|list|usage} [parameters...]"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 usage simple-example.sh"
    echo "  $0 execute simple-example.sh --target-file /etc/hosts --operation analyze"
  fi
fi
