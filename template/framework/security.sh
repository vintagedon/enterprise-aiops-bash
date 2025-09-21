#!/usr/bin/env bash
# shellcheck shell=bash
#--------------------------------------------------------------------------------------------------
# SCRIPT:       security.sh
# PURPOSE:      Error and exit handlers with diagnostics for both humans and AI agents.
# VERSION:      1.1.0
# REPOSITORY:   https://github.com/vintagedon/enterprise-aiops-bash
# LICENSE:      MIT
# USAGE:        source "framework/security.sh"
#
# NOTES:
#   These trap handlers provide context-rich failure information. When JSON logging
#   is enabled, it emits a structured error object that can be programmatically
#   parsed by an AIOps platform or an autonomous agent for remediation.
#--------------------------------------------------------------------------------------------------

#--------------------------------------------------------------------------------------------------
# The global ERR trap handler, triggered whenever a command fails.
# It captures the failure context and logs it before exiting the script.
#
# @param $1  (from trap) The line number where the error occurred ($LINENO).
# @param $2  (from trap) The command that failed ($BASH_COMMAND).
# @param $3  (from trap) The exit code of the failed command ($?).
#--------------------------------------------------------------------------------------------------
on_err() {
  local line="${1:-?}" cmd="${2:-?}" rc="${3:-1}" ts
  ts="$(date -u +%FT%TZ)"

  # Human-readable output for engineers.
  log_error "Failed at line ${line}: ${cmd} (exit ${rc})"

  # Machine-readable output for AI agents and automation platforms.
  if command -v jq >/dev/null 2_1 && [[ "${LOG_FORMAT:-text}" == "json" ]]; then
    printf '{"timestamp":"%s","level":"ERROR","event":"script_error","line":%s,"command":%s,"exit_code":%s}\n' \
      "$ts" "$line" "$(printf '%s' "$cmd" | jq -Rs .)" "$rc" >&2
  fi

  # Diagnostics: Provide a basic stack trace to show the function call chain.
  local i=0
  while caller $i >&2; do ((i++)); done
  exit "$rc"
}

#--------------------------------------------------------------------------------------------------
# The global EXIT trap handler, triggered when the script exits for any reason.
# Primarily used for debug logging to record the script's final exit code and timing.
#--------------------------------------------------------------------------------------------------
on_exit() {
  local rc=$?
  log_debug "Exit ${rc}; started ${START_TS:-unknown}; finished $(date -u +%FT%TZ)"
}