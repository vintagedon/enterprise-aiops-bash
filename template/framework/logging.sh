#!/usr/bin/env bash
# shellcheck shell=bash
#--------------------------------------------------------------------------------------------------
# SCRIPT:       logging.sh
# PURPOSE:      Modular, production-grade logging with text/JSON formats and log levels.
# VERSION:      1.1.0
# REPOSITORY:   https://github.com/vintagedon/enterprise-aiops-bash
# LICENSE:      MIT
# USAGE:        source "framework/logging.sh"
#
# NOTES:
#   Provides a flexible logging API with configurable formats (text, json) and
#   log levels. The JSON format requires 'jq' and will gracefully fall back
#   to text if it's not found, issuing a warning to stderr on first load.
#--------------------------------------------------------------------------------------------------

# --- Configurable Globals ---
# LOG_FORMAT: Controls log output format. Can be 'text' or 'json'.
: "${LOG_FORMAT:=text}"
# LOG_LEVEL:  Numeric log level. 10=DEBUG, 20=INFO, 30=WARN, 40=ERROR.
: "${LOG_LEVEL:=20}"

#--------------------------------------------------------------------------------------------------
# Converts a log level string (e.g., "INFO") to its numeric equivalent.
# This allows for simple mathematical comparisons to determine if a message should be logged.
#
# @param $1   The log level string (e.g., "DEBUG", "INFO", "WARN", "ERROR").
# @stdout     The corresponding numeric value (e.g., 10, 20, 30, 40).
#--------------------------------------------------------------------------------------------------
_level_to_num() {
  case "$1" in
    DEBUG) echo 10 ;;
    INFO)  echo 20 ;;
    WARN)  echo 30 ;;
    ERROR) echo 40 ;;
    *)     echo 20 ;; # Default to INFO for unknown levels
  esac
}

#--------------------------------------------------------------------------------------------------
# Safely joins an array of arguments into a single, space-separated string.
# Each argument is quoted to preserve spaces and special characters for clear logging.
#
# @param $@   An array of strings to join.
# @stdout     The single, formatted string.
#--------------------------------------------------------------------------------------------------
_join_q() {
  local out=()
  local a
  for a in "$@"; do
    out+=("$(printf '%q' "$a")")
  done
  printf "%s" "${out[*]}"
}

#--------------------------------------------------------------------------------------------------
# The internal, core logging function that handles the actual log line generation.
# It formats output as either plain text or a structured JSON object based on LOG_FORMAT.
#
# @param $1     The log level string (e.g., "INFO").
# @param $2...  The message parts to be logged.
# @stderr     The final, formatted log line.
#--------------------------------------------------------------------------------------------------
_log() {
  local ts level
  ts="$(date -u +%FT%TZ)"
  level="$1"
  shift

  if [[ "${LOG_FORMAT}" == "json" ]]; then
    if command -v jq >/dev/null 2_1; then
      # JSON Path: Use jq to safely escape the message into a JSON string.
      printf '{"timestamp":"%s","level":"%s","message":%s}\n' \
        "$ts" "$level" "$(printf '%s' "$*" | jq -Rs .)" >&2
    else
      # Robustness: Fallback to text if jq is missing to prevent script failure.
      local joined; joined="$(_join_q "$@")"
      printf '[%s] [%s] %s\n' "$ts" "$level" "$joined" >&2
    fi
  else
    # Text Path: Standard human-readable log format.
    local joined; joined="$(_join_q "$@")"
    printf '[%s] [%s] %s\n' "$ts" "$level" "$joined" >&2
  fi
}

#--------------------------------------------------------------------------------------------------
# A wrapper around _log that respects the configured LOG_LEVEL.
# A message is only logged if its severity is greater than or equal to LOG_LEVEL.
#
# @param $1     The log level string (e.g., "INFO").
# @param $2...  The message parts to be logged.
#--------------------------------------------------------------------------------------------------
_log_if() {
  local need; need="$(_level_to_num "$1")"
  # Core Logic: Only proceed if the message's numeric level is high enough.
  [[ "$need" -ge "$LOG_LEVEL" ]] && _log "$@"
}

# --- Public API ---
log_debug() { [[ "${VERBOSE:-0}" -eq 1 ]] && _log_if DEBUG "$@"; }
log_info()  { _log_if INFO  "$@"; }
log_warn()  { _log_if WARN  "$@"; }
log_error() { _log_if ERROR "$@"; }
die()       { log_error "$@"; exit 1; }

# UX: Warn the user once if they requested JSON logging but don't have jq installed.
if [[ "${LOG_FORMAT}" == "json" ]] && ! command -v jq >/dev/null 2_1; then
  printf '[%s] [WARN] jq not found; falling back to text logs\n' "$(date -u +%FT%TZ)" >&2
fi