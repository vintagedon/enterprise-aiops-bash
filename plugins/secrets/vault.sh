#!/usr/bin/env bash
# shellcheck shell=bash
#--------------------------------------------------------------------------------------------------
# SCRIPT:       vault.sh
# PURPOSE:      HashiCorp Vault plugin for enterprise secret management
# VERSION:      1.0.0
# REPOSITORY:   https://github.com/vintagedon/enterprise-aiops-bash
# LICENSE:      MIT
# USAGE:        source plugins/secrets/vault.sh
#
# NOTES:
#   This plugin provides HashiCorp Vault integration for secure secret retrieval.
#   It supports multiple authentication methods and secure secret caching.
#--------------------------------------------------------------------------------------------------

# Plugin identification
readonly VAULT_PLUGIN_VERSION="1.0.0"
readonly VAULT_PLUGIN_NAME="vault"

# Plugin configuration
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
VAULT_AUTH_METHOD="${VAULT_AUTH_METHOD:-token}"
VAULT_MOUNT_PATH="${VAULT_MOUNT_PATH:-kv}"
VAULT_SECRET_ENGINE="${VAULT_SECRET_ENGINE:-kv-v2}"
VAULT_TIMEOUT="${VAULT_TIMEOUT:-30}"

# Internal state
VAULT_AUTHENTICATED=0
VAULT_TOKEN_EXPIRES=""

#--------------------------------------------------------------------------------------------------
# Validates vault CLI availability and basic connectivity
#--------------------------------------------------------------------------------------------------
validate_vault_setup() {
  # Check if vault CLI is available
  if ! command -v vault >/dev/null 2>&1; then
    die "HashiCorp Vault CLI not found. Please install vault binary."
  fi
  
  # Validate vault address format
  if ! [[ "$VAULT_ADDR" =~ ^https?://[^[:space:]]+$ ]]; then
    die "Invalid Vault address format: $VAULT_ADDR"
  fi
  
  log_debug "Vault CLI found, testing connectivity to $VAULT_ADDR"
  
  # Test basic connectivity
  if ! vault status >/dev/null 2>&1; then
    log_warn "Cannot connect to Vault at $VAULT_ADDR"
    log_warn "Ensure Vault is running and accessible"
    return 1
  fi
  
  log_debug "Vault connectivity validated"
  return 0
}

#--------------------------------------------------------------------------------------------------
# Authenticates with Vault using the configured method
# @param $1  Authentication method (optional, overrides VAULT_AUTH_METHOD)
#--------------------------------------------------------------------------------------------------
vault_authenticate() {
  local auth_method="${1:-$VAULT_AUTH_METHOD}"
  
  log_info "Authenticating with Vault using method: $auth_method"
  
  # Set vault address
  export VAULT_ADDR
  [[ -n "$VAULT_NAMESPACE" ]] && export VAULT_NAMESPACE
  
  case "$auth_method" in
    token)
      vault_auth_token
      ;;
    userpass)
      vault_auth_userpass
      ;;
    aws)
      vault_auth_aws
      ;;
    kubernetes)
      vault_auth_kubernetes
      ;;
    approle)
      vault_auth_approle
      ;;
    *)
      die "Unsupported authentication method: $auth_method"
      ;;
  esac
  
  if [[ $? -eq 0 ]]; then
    VAULT_AUTHENTICATED=1
    log_info "Vault authentication successful"
  else
    die "Vault authentication failed"
  fi
}

#--------------------------------------------------------------------------------------------------
# Token-based authentication
#--------------------------------------------------------------------------------------------------
vault_auth_token() {
  [[ -n "$VAULT_TOKEN" ]] || die "VAULT_TOKEN not provided for token authentication"
  
  export VAULT_TOKEN
  
  # Validate token
  if vault token lookup >/dev/null 2>&1; then
    log_debug "Vault token validated successfully"
    return 0
  else
    die "Invalid or expired Vault token"
  fi
}

#--------------------------------------------------------------------------------------------------
# Username/password authentication
#--------------------------------------------------------------------------------------------------
vault_auth_userpass() {
  local username="${VAULT_USERNAME:-}"
  local password="${VAULT_PASSWORD:-}"
  
  [[ -n "$username" ]] || die "VAULT_USERNAME not provided for userpass authentication"
  [[ -n "$password" ]] || die "VAULT_PASSWORD not provided for userpass authentication"
  
  local auth_response
  auth_response=$(vault write -format=json "auth/userpass/login/$username" "password=$password" 2>/dev/null)
  
  if [[ $? -eq 0 ]]; then
    VAULT_TOKEN=$(echo "$auth_response" | jq -r '.auth.client_token')
    export VAULT_TOKEN
    log_debug "Userpass authentication successful"
  else
    die "Userpass authentication failed for user: $username"
  fi
}

#--------------------------------------------------------------------------------------------------
# AWS IAM authentication
#--------------------------------------------------------------------------------------------------
vault_auth_aws() {
  local role="${VAULT_AWS_ROLE:-}"
  
  [[ -n "$role" ]] || die "VAULT_AWS_ROLE not provided for AWS authentication"
  
  log_debug "Attempting AWS authentication with role: $role"
  
  local auth_response
  auth_response=$(vault write -format=json "auth/aws/login" "role=$role" 2>/dev/null)
  
  if [[ $? -eq 0 ]]; then
    VAULT_TOKEN=$(echo "$auth_response" | jq -r '.auth.client_token')
    export VAULT_TOKEN
    log_debug "AWS authentication successful"
  else
    die "AWS authentication failed for role: $role"
  fi
}

#--------------------------------------------------------------------------------------------------
# Kubernetes service account authentication
#--------------------------------------------------------------------------------------------------
vault_auth_kubernetes() {
  local role="${VAULT_K8S_ROLE:-}"
  local jwt_path="${VAULT_K8S_JWT_PATH:-/var/run/secrets/kubernetes.io/serviceaccount/token}"
  
  [[ -n "$role" ]] || die "VAULT_K8S_ROLE not provided for Kubernetes authentication"
  [[ -f "$jwt_path" ]] || die "Kubernetes service account token not found: $jwt_path"
  
  local jwt_token
  jwt_token=$(cat "$jwt_path")
  
  local auth_response
  auth_response=$(vault write -format=json "auth/kubernetes/login" "role=$role" "jwt=$jwt_token" 2>/dev/null)
  
  if [[ $? -eq 0 ]]; then
    VAULT_TOKEN=$(echo "$auth_response" | jq -r '.auth.client_token')
    export VAULT_TOKEN
    log_debug "Kubernetes authentication successful"
  else
    die "Kubernetes authentication failed for role: $role"
  fi
}

#--------------------------------------------------------------------------------------------------
# AppRole authentication
#--------------------------------------------------------------------------------------------------
vault_auth_approle() {
  local role_id="${VAULT_ROLE_ID:-}"
  local secret_id="${VAULT_SECRET_ID:-}"
  
  [[ -n "$role_id" ]] || die "VAULT_ROLE_ID not provided for AppRole authentication"
  [[ -n "$secret_id" ]] || die "VAULT_SECRET_ID not provided for AppRole authentication"
  
  local auth_response
  auth_response=$(vault write -format=json "auth/approle/login" "role_id=$role_id" "secret_id=$secret_id" 2>/dev/null)
  
  if [[ $? -eq 0 ]]; then
    VAULT_TOKEN=$(echo "$auth_response" | jq -r '.auth.client_token')
    export VAULT_TOKEN
    log_debug "AppRole authentication successful"
  else
    die "AppRole authentication failed"
  fi
}

#--------------------------------------------------------------------------------------------------
# Retrieves a secret from Vault
# @param $1  Secret path
# @param $2  Secret key (optional, returns entire secret if not specified)
# @stdout    Secret value or JSON object
#--------------------------------------------------------------------------------------------------
vault_get_secret() {
  local secret_path="$1"
  local secret_key="${2:-}"
  
  [[ -n "$secret_path" ]] || die "Secret path required"
  [[ "$VAULT_AUTHENTICATED" -eq 1 ]] || vault_authenticate
  
  log_debug "Retrieving secret: $secret_path${secret_key:+.$secret_key}"
  
  local full_path
  case "$VAULT_SECRET_ENGINE" in
    kv-v2)
      full_path="$VAULT_MOUNT_PATH/data/$secret_path"
      ;;
    kv-v1|generic)
      full_path="$VAULT_MOUNT_PATH/$secret_path"
      ;;
    *)
      full_path="$secret_path"
      ;;
  esac
  
  local secret_response
  secret_response=$(vault read -format=json "$full_path" 2>/dev/null)
  
  if [[ $? -ne 0 ]]; then
    log_error "Failed to retrieve secret: $secret_path"
    return 1
  fi
  
  if [[ -n "$secret_key" ]]; then
    # Extract specific key
    case "$VAULT_SECRET_ENGINE" in
      kv-v2)
        echo "$secret_response" | jq -r ".data.data.$secret_key // empty"
        ;;
      *)
        echo "$secret_response" | jq -r ".data.$secret_key // empty"
        ;;
    esac
  else
    # Return entire secret data
    case "$VAULT_SECRET_ENGINE" in
      kv-v2)
        echo "$secret_response" | jq -r '.data.data'
        ;;
      *)
        echo "$secret_response" | jq -r '.data'
        ;;
    esac
  fi
}

#--------------------------------------------------------------------------------------------------
# Sets environment variables from a Vault secret
# @param $1  Secret path
# @param $2  Variable prefix (optional)
#--------------------------------------------------------------------------------------------------
vault_load_env() {
  local secret_path="$1"
  local var_prefix="${2:-}"
  
  [[ -n "$secret_path" ]] || die "Secret path required for environment loading"
  
  log_info "Loading environment variables from Vault secret: $secret_path"
  
  local secret_data
  secret_data=$(vault_get_secret "$secret_path")
  
  if [[ -z "$secret_data" || "$secret_data" == "null" ]]; then
    log_error "No data found in secret: $secret_path"
    return 1
  fi
  
  local loaded_count=0
  local key value
  
  # Parse JSON and set environment variables
  while IFS="=" read -r key value; do
    if [[ -n "$key" && -n "$value" ]]; then
      local env_var="${var_prefix}${key}"
      export "$env_var=$value"
      log_debug "Loaded environment variable: $env_var"
      ((loaded_count++))
    fi
  done < <(echo "$secret_data" | jq -r 'to_entries[] | "\(.key)=\(.value)"' 2>/dev/null)
  
  log_info "Loaded $loaded_count environment variables from Vault"
}

#--------------------------------------------------------------------------------------------------
# Stores a secret in Vault
# @param $1  Secret path
# @param $2  Secret data (JSON format)
#--------------------------------------------------------------------------------------------------
vault_put_secret() {
  local secret_path="$1"
  local secret_data="$2"
  
  [[ -n "$secret_path" ]] || die "Secret path required"
  [[ -n "$secret_data" ]] || die "Secret data required"
  [[ "$VAULT_AUTHENTICATED" -eq 1 ]] || vault_authenticate
  
  # Validate JSON format
  if ! echo "$secret_data" | jq . >/dev/null 2>&1; then
    die "Secret data must be valid JSON: $secret_data"
  fi
  
  log_info "Storing secret in Vault: $secret_path"
  
  local full_path
  case "$VAULT_SECRET_ENGINE" in
    kv-v2)
      full_path="$VAULT_MOUNT_PATH/data/$secret_path"
      # Wrap data for KV v2
      secret_data=$(echo "$secret_data" | jq '{data: .}')
      ;;
    kv-v1|generic)
      full_path="$VAULT_MOUNT_PATH/$secret_path"
      ;;
    *)
      full_path="$secret_path"
      ;;
  esac
  
  if vault write "$full_path" - <<< "$secret_data" >/dev/null 2>&1; then
    log_info "Secret stored successfully: $secret_path"
  else
    die "Failed to store secret: $secret_path"
  fi
}

#--------------------------------------------------------------------------------------------------
# Checks if current token is valid and not expired
#--------------------------------------------------------------------------------------------------
vault_token_valid() {
  [[ -n "$VAULT_TOKEN" ]] || return 1
  
  local token_info
  token_info=$(vault token lookup -format=json 2>/dev/null)
  
  [[ $? -eq 0 ]] || return 1
  
  # Check if token is renewable or has sufficient TTL
  local ttl
  ttl=$(echo "$token_info" | jq -r '.data.ttl')
  
  if [[ "$ttl" != "null" && "$ttl" -gt 60 ]]; then
    return 0
  else
    log_warn "Vault token expires soon (TTL: ${ttl}s)"
    return 1
  fi
}

#--------------------------------------------------------------------------------------------------
# Renews the current Vault token if possible
#--------------------------------------------------------------------------------------------------
vault_renew_token() {
  [[ "$VAULT_AUTHENTICATED" -eq 1 ]] || die "Not authenticated with Vault"
  
  log_info "Attempting to renew Vault token"
  
  if vault token renew >/dev/null 2>&1; then
    log_info "Vault token renewed successfully"
  else
    log_warn "Failed to renew Vault token, re-authentication may be required"
    return 1
  fi
}

#--------------------------------------------------------------------------------------------------
# Shows current Vault configuration and status
#--------------------------------------------------------------------------------------------------
vault_status() {
  log_info "Vault plugin configuration:"
  log_info "  Plugin version: $VAULT_PLUGIN_VERSION"
  log_info "  Vault address: $VAULT_ADDR"
  log_info "  Namespace: ${VAULT_NAMESPACE:-'none'}"
  log_info "  Authentication method: $VAULT_AUTH_METHOD"
  log_info "  Mount path: $VAULT_MOUNT_PATH"
  log_info "  Secret engine: $VAULT_SECRET_ENGINE"
  log_info "  Authenticated: $VAULT_AUTHENTICATED"
  
  if vault_token_valid; then
    log_info "  Token status: valid"
  else
    log_warn "  Token status: invalid or expired"
  fi
}

#--------------------------------------------------------------------------------------------------
# Cleanup function to revoke token on exit
#--------------------------------------------------------------------------------------------------
vault_cleanup() {
  if [[ "$VAULT_AUTHENTICATED" -eq 1 && -n "$VAULT_TOKEN" ]]; then
    log_debug "Revoking Vault token on cleanup"
    vault token revoke -self >/dev/null 2>&1 || true
  fi
}

# Plugin initialization
log_debug "Vault plugin loaded (version $VAULT_PLUGIN_VERSION)"

# Validate setup if auto-initialization is enabled
if [[ "${VAULT_AUTO_INIT:-1}" -eq 1 ]]; then
  if validate_vault_setup; then
    # Auto-authenticate if token is provided
    if [[ -n "$VAULT_TOKEN" && "$VAULT_AUTH_METHOD" == "token" ]]; then
      vault_authenticate
    fi
  fi
fi

# Register cleanup function
trap vault_cleanup EXIT
