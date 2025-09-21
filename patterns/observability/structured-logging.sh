#!/usr/bin/env bash
# shellcheck shell=bash
#--------------------------------------------------------------------------------------------------
# SCRIPT:       structured-logging.sh
# PURPOSE:      Demonstrates structured logging patterns for enterprise observability
# VERSION:      1.0.0
# REPOSITORY:   https://github.com/vintagedon/enterprise-aiops-bash
# LICENSE:      MIT
# USAGE:        ./structured-logging.sh --service web-app --environment production --operation deploy
#
# NOTES:
#   This script demonstrates structured logging patterns that integrate with modern
#   observability platforms and provide rich context for monitoring and debugging.
#--------------------------------------------------------------------------------------------------

# --- Strict Mode & Security ---
set -Eeuo pipefail
IFS=$'\n\t'
umask 027

# --- Globals ---
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly START_TS="$(date -u +%FT%TZ)"

# Observability context variables
readonly TRACE_ID="${TRACE_ID:-$(uuidgen 2>/dev/null || openssl rand -hex 16)}"
readonly SPAN_ID="${SPAN_ID:-$(openssl rand -hex 8)}"
readonly SERVICE_NAME="${SERVICE_NAME:-$(basename "$0" .sh)}"
readonly SERVICE_VERSION="${SERVICE_VERSION:-1.0.0}"

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
SERVICE=""
ENVIRONMENT=""
OPERATION=""
DURATION_START=""

#--------------------------------------------------------------------------------------------------
# Enhanced structured logging with observability context
# @param $1    Log level (DEBUG, INFO, WARN, ERROR)
# @param $2    Message
# @param $3... Additional key-value pairs (key value key value...)
#--------------------------------------------------------------------------------------------------
log_structured() {
  local level="$1"; shift
  local message="$1"; shift
  local ts; ts="$(date -u +%FT%TZ)"
  
  # Build base structured log entry
  local log_entry
  log_entry=$(jq -n \
    --arg timestamp "$ts" \
    --arg level "$level" \
    --arg message "$message" \
    --arg script "$SCRIPT_NAME" \
    --arg service "$SERVICE_NAME" \
    --arg version "$SERVICE_VERSION" \
    --arg trace_id "$TRACE_ID" \
    --arg span_id "$SPAN_ID" \
    --arg pid "$BASHPID" \
    '{
      timestamp: $timestamp,
      level: $level,
      message: $message,
      service: {
        name: $service,
        version: $version
      },
      trace: {
        trace_id: $trace_id,
        span_id: $span_id
      },
      process: {
        script: $script,
        pid: ($pid | tonumber)
      }
    }')
  
  # Add custom fields from arguments
  while [[ $# -gt 1 ]]; do
    local key="$1"
    local value="$2"
    log_entry=$(echo "$log_entry" | jq --arg k "$key" --arg v "$value" '.custom[$k] = $v')
    shift 2
  done
  
  # Add environment context if available
  [[ -n "${SERVICE:-}" ]] && log_entry=$(echo "$log_entry" | jq --arg s "$SERVICE" '.context.service = $s')
  [[ -n "${ENVIRONMENT:-}" ]] && log_entry=$(echo "$log_entry" | jq --arg e "$ENVIRONMENT" '.context.environment = $e')
  [[ -n "${OPERATION:-}" ]] && log_entry=$(echo "$log_entry" | jq --arg o "$OPERATION" '.context.operation = $o')
  
  printf "%s\n" "$log_entry" >&2
}

#--------------------------------------------------------------------------------------------------
# Log performance metrics with timing information
# @param $1    Metric name
# @param $2    Duration in seconds (optional, calculated if not provided)
# @param $3... Additional metric labels
#--------------------------------------------------------------------------------------------------
log_metric() {
  local metric_name="$1"; shift
  local duration="${1:-}"; shift || true
  
  # Calculate duration if not provided and DURATION_START is set
  if [[ -z "$duration" && -n "${DURATION_START:-}" ]]; then
    local end_time
    end_time=$(date +%s)
    duration=$((end_time - DURATION_START))
