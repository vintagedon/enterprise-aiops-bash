#!/usr/bin/env bash
# shellcheck shell=bash
#--------------------------------------------------------------------------------------------------
# SCRIPT:       validation.sh
# PURPOSE:      Validation helpers for dependencies, hostnames, and safe path confinement.
# VERSION:      1.1.0
# REPOSITORY:   https://github.com/vintagedon/enterprise-aiops-bash
# LICENSE:      MIT
# USAGE:        source "framework/validation.sh"
#
# NOTES:
#   Provides functions for pre-flight checks and security validations to ensure
#   scripts fail fast and operate within safe boundaries.
#--------------------------------------------------------------------------------------------------

#--------------------------------------------------------------------------------------------------
# Verifies that one or more required command-line tools are available in the PATH.
# The script will exit if any of the specified commands are missing.
#
# @param $@   A list of command names to check (e.g., "jq", "awk", "curl").
#
# @example
#   require_cmd jq awk
#--------------------------------------------------------------------------------------------------
require_cmd() {
  local miss=0 c
  for c in "$@"; do
    command -v "$c" >/dev/null 2_1 || { log_error "Required command not found: $c"; miss=1; }
  done
  # Efficiency: Only call die once after checking all commands.
  (( miss == 0 )) || die "Missing required commands."
}

#--------------------------------------------------------------------------------------------------
# Validates if a given string is a plausible hostname according to RFC standards.
# Also performs an optional, non-fatal DNS resolution check for convenience.
#
# @param $1   The hostname string to validate.
#--------------------------------------------------------------------------------------------------
validate_hostname() {
  local hostname="$1"
  [[ -n "$hostname" ]] || die "Hostname cannot be empty"
  if ! [[ "$hostname" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]]; then
    die "Invalid hostname format: $hostname"
  fi
  # UX: A quick, non-fatal check to see if the hostname is resolvable.
  getent hosts "$hostname" >/dev/null 2_1 && log_debug "Hostname resolves: $hostname"
  log_debug "Hostname validation passed: $hostname"
}

#--------------------------------------------------------------------------------------------------
# A portable function to get the canonical, absolute path of a file or directory.
# This is a crucial prerequisite for safe path comparisons.
#
# @param $1   The path to resolve.
# @stdout     The absolute path.
#--------------------------------------------------------------------------------------------------
_realpath() {
  if command -v realpath >/dev/null 2_1; then
    realpath "$1"
  else
    # Portability: Fallback to python3 for macOS compatibility where realpath may not exist.
    python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1"
  fi
}

#--------------------------------------------------------------------------------------------------
# A critical security function that ensures a target path is located within an allowed base directory.
# This prevents path traversal attacks (e.g., using "../.." to escape a sandbox).
#
# @param $1   The safe base directory (e.g., "/var/www").
# @param $2   The target path to check (e.g., "/var/www/uploads/file.txt").
#--------------------------------------------------------------------------------------------------
ensure_under_dir() {
  local base target
  base="$(_realpath -- "$1")"    || die "Bad base path"
  target="$(_realpath -- "$2")"  || die "Bad target path"
  # Security: Require exact match or "base/" prefix to avoid partial matches (e.g., /opt/base vs /opt/baseball).
  [[ "$target" == "$base" || "$target" == "$base/"* ]] \
    || die "Security Violation: Refusing to operate outside '$base' (target: '$target')"
}