#!/usr/bin/env bash
# shellcheck shell=bash
#--------------------------------------------------------------------------------------------------
# SCRIPT:       (Your Script Name)
# PURPOSE:      (Purpose of your script)
# VERSION:      1.1.0
# REPOSITORY:   https://github.com/vintagedon/enterprise-aiops-bash
# LICENSE:      MIT
# AUTHOR:       (Your Name)
# USAGE:        (Usage examples)
#
# NOTES:
#   This is the main template for creating new automation scripts. It sources the
#   core framework to provide robust logging, error handling, and security features
#   out of the box.
#--------------------------------------------------------------------------------------------------

# --- Strict Mode & Security ---
# Why: These settings prevent common scripting errors and enforce best practices.
set -Eeuo pipefail # -E: ERR traps inherited, -e: exit on error, -u: unset vars are errors, -o pipefail: pipelines fail
IFS=$'\n\t'      # Why: Prevents word-splitting on spaces.
umask 027          # Why: Restrictive default file permissions (rw-r-----).

# --- Globals ---
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly START_TS="$(date -u +%FT%TZ)"

# --- Source Core Framework (Defensive) ---
# Why: Loads the framework libraries. The check ensures the script fails if its components are missing.
for lib in "framework/logging.sh" "framework/security.sh" "framework/validation.sh"; do
  if ! source "${SCRIPT_DIR}/${lib}"; then
    ts="$(date -u +%FT%TZ)"
    # UX: Try to provide a consistent error format even if the logging library failed to load.
    if [[ "${LOG_FORMAT:-text}" == "json" ]] && command -v jq >/dev/null 2_1; then
      printf '{"timestamp":"%s","level":"ERROR","event":"bootstrap","message":%s}\n' \
        "$ts" "$(printf 'Could not source library: %s' "$lib" | jq -Rs .)" >&2
    else
      echo "FATAL: Could not source required library: ${lib}" >&2
    fi
    exit 1
  fi
done

# --- Traps ---
# Why: Set traps *after* sourcing the handlers that define them.
trap 'on_err $LINENO "$BASH_COMMAND" $?' ERR
trap 'on_exit' EXIT

# --- Script-Specific Defaults ---
VERBOSE=0
DRY_RUN=0
READ_ONLY=${READ_ONLY:-0} # 1 = block mutator commands
# Note: LOG_FORMAT / LOG_LEVEL are inherited from logging.sh

INPUT_FILE="" # Example variable

# Security: A list of commands known to alter system state. Used by run() in read-only mode.
readonly _MUTATORS=("rm" "mv" "chmod" "chown" "dd" "mkfs" "systemctl" "apt" "apt-get" "yum" "zypper" "kubectl" "helm" "terraform" "ansible-playbook")

#--------------------------------------------------------------------------------------------------
# Checks for the presence of shell metacharacters in a string.
#
# @param $* The string to check.
# @return     0 if metacharacters are found, 1 otherwise.
#--------------------------------------------------------------------------------------------------
_is_meta_present() {
  [[ "$*" == *";"* || "$*" == *"&"* || "$*" == *"|"* || "$*" == *">"* || "$*" == *"<"* ]]
}

#--------------------------------------------------------------------------------------------------
# A governed command executor that provides a security and safety wrapper.
# This is the core "actuator" of the framework, designed to be safely called by AI agents
# by enforcing read-only mode, explicit command allow-lists, and argument sanitization.
#
# @param --allow <csv>  (Optional) A comma-separated list of command basenames permitted
#                         to run (e.g., "awk,cat,sed").
# @param $1             The command to execute (e.g., "/usr/bin/awk").
# @param $2...          The arguments to pass to the command.
#
# @stdout The standard output of the executed command.
# @stderr The standard error of the executed command, plus log lines from the framework.
#
# @example
#   run --allow "awk,cat" awk '{print $1}' myfile.txt
#   run ls -l /tmp
#--------------------------------------------------------------------------------------------------
run() {
  local allow_csv="" raw_cmd base_cmd
  if [[ "${1:-}" == "--allow" ]]; then
    allow_csv="$2"; shift 2
  fi
  raw_cmd="${1:-}"; shift || true
  [[ -n "$raw_cmd" ]] || die "run(): missing command"

  # Security: Unwrap sudo to apply checks to the actual command, not the wrapper.
  if [[ "$raw_cmd" == "sudo" ]]; then
    raw_cmd="${1:-}"; shift || true
    [[ -n "$raw_cmd" ]] || die "run(): sudo without a command"
  fi

  # Why: Use the basename for checks to make them independent of the full path.
  base_cmd="$(basename -- "$raw_cmd")"

  # Security: Block shell metacharacters to prevent command injection from tainted arguments.
  if _is_meta_present "$*"; then
    die "run(): shell metacharacters are not allowed in arguments"
  fi

  # Safety: Enforce READ_ONLY mode by blocking known mutator commands.
  if [[ "$READ_ONLY" -eq 1 ]]; then
    local m
    for m in "${_MUTATORS[@]}"; do
      [[ "$base_cmd" == "$m" ]] && die "READ_ONLY=1: refusing mutator '$base_cmd'"
    done
  fi

  # Security: Enforce the explicit allow-list if one was provided.
  if [[ -n "$allow_csv" ]]; then
    IFS=',' read -r -a allow <<<"$allow_csv"
    local ok=1 a
    for a in "${allow[@]}"; do
      [[ "$base_cmd" == "$a" ]] && ok=0 && break
    done
    (( ok == 0 )) || die "Command '$base_cmd' not in allow-list"
  fi

  # Core Logic: Execute for real or log the intent in a dry run.
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "DRY RUN: $base_cmd $*"
  else
    log_info "RUN: $base_cmd $*"
    "$raw_cmd" "$@"
  fi
}

usage() {
  local code="${1:-0}"
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS] --file <path>

Options:
  -f, --file <path>   Path to the input file. (Required)
  -d, --dry-run       Show actions without executing.
  -v, --verbose       Enable verbose (debug) logging. (Sets --log-level 10)
      --read-only     Block mutating commands (safer than dry-run for diagnostics).
      --log-json      Emit JSON logs (uses jq if available; falls back to text).
      --log-level N   10=DEBUG, 20=INFO, 30=WARN, 40=ERROR (default: 20)
  -h, --help          Show this help.

Examples:
  $SCRIPT_NAME --file ./data.txt --dry-run --verbose
  $SCRIPT_NAME --file ./data.txt --read-only --log-json
EOF
  exit "$code"
}

parse_args() {
  [[ $# -eq 0 ]] && usage 1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--file)    [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; INPUT_FILE="$2"; shift 2 ;;
      -d|--dry-run) DRY_RUN=1; shift ;;
      -v|--verbose) VERBOSE=1; LOG_LEVEL=10; shift ;;
      -read-only)  READ_ONLY=1; shift ;;
      -log-json)   LOG_FORMAT="json"; shift ;;
      -log-level)  [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; LOG_LEVEL="$2"; shift 2 ;;
      -h|-help)    usage 0 ;;
      --) shift; break ;;
      -*) die "Unknown option: $1" ;;
      *)  break ;;
    esac
  done
}

main() {
  parse_args "$@"

  # Pre-flight Checks: Fail fast if dependencies or conditions aren't met.
  [[ "$LOG_FORMAT" == "json" ]] && require_cmd jq || true
  require_cmd awk # Example dependency for this script's logic.

  [[ -n "$INPUT_FILE" ]] || { log_error "Input file is required."; usage 1; }
  [[ -f "$INPUT_FILE" && -r "$INPUT_FILE" ]] || die "File not readable: $INPUT_FILE"

  log_info "Starting ${SCRIPT_NAME}"
  log_debug "SCRIPT_DIR=${SCRIPT_DIR}" "INPUT_FILE=${INPUT_FILE}" "DRY_RUN=${DRY_RUN}" \
            "READ_ONLY=${READ_ONLY}" "LOG_FORMAT=${LOG_FORMAT}" "LOG_LEVEL=${LOG_LEVEL}"

  # --- START SCRIPT LOGIC ---
  # Example: Use the governed runner, explicitly allowing only safe, non-mutating tools.
  run --allow "awk,cat,sed" awk 'NR<=5{print NR ":" $0}' -- "$INPUT_FILE"
  # --- END SCRIPT LOGIC ---

  log_info "Completed successfully."
}

# --- Invocation ---
# Why: Pass all script arguments to the main function to start execution.
main "$@"