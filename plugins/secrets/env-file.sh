#!/usr/bin/env bash
# shellcheck shell=bash
#--------------------------------------------------------------------------------------------------
# SCRIPT:       env-file.sh
# PURPOSE:      Environment file plugin for secure credential management
# VERSION:      1.0.0
# REPOSITORY:   https://github.com/vintagedon/enterprise-aiops-bash
# LICENSE:      MIT
# USAGE:        source plugins/secrets/env-file.sh
#
# NOTES:
#   This plugin provides secure environment file loading with validation and encryption support.
#   It integrates with the Enterprise AIOps Bash Framework for secure credential management.
#--------------------------------------------------------------------------------------------------

# Plugin identification
readonly ENV_FILE_PLUGIN_VERSION="1.0.0"
readonly ENV_FILE_PLUGIN_NAME="env-file"

# Plugin configuration
ENV_FILE_PATH="${ENV_FILE_PATH:-}"
ENV_FILE_REQUIRED="${ENV_FILE_REQUIRED:-1}"
ENV_FILE_ENCRYPTED="${ENV_FILE_ENCRYPTED:-0}"
ENV_FILE_PREFIX="${ENV_FILE_PREFIX:-}"

#--------------------------------------------------------------------------------------------------
# Validates environment file format and security
# @param $1  Path to environment file
#--------------------------------------------------------------------------------------------------
validate_env_file() {
  local env_file="$1"
  
  [[ -n "$env_file" ]] || die "Environment file path cannot be empty"
  [[ -f "$env_file" ]] || die "Environment file does not exist: $env_file"
  [[ -r "$env_file" ]] || die "Environment file not readable: $env_file"
  
  # Check file permissions - should not be world-readable
  local perms
  perms=$(stat -c%a "$env_file")
  if [[ "${perms: -1}" != "0" ]]; then
    log_warn "Environment file is world-readable: $env_file (permissions: $perms)"
  fi
  
  # Validate file format
  local line_num=0
  local invalid_lines=()
  
  while IFS= read -r line; do
    ((line_num++))
    
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Validate key=value format
    if ! [[ "$line" =~ ^[A-Z_][A-Z0-9_]*=.*$ ]]; then
      invalid_lines+=("Line $line_num: $line")
    fi
  done < "$env_file"
  
  if [[ ${#invalid_lines[@]} -gt 0 ]]; then
    log_error "Invalid environment file format in $env_file:"
    printf '%s\n' "${invalid_lines[@]}" >&2
    die "Environment file validation failed"
  fi
  
  log_debug "Environment file validation passed: $env_file"
}

#--------------------------------------------------------------------------------------------------
# Decrypts environment file if encryption is enabled
# @param $1  Path to encrypted environment file
# @stdout    Decrypted content
#--------------------------------------------------------------------------------------------------
decrypt_env_file() {
  local encrypted_file="$1"
  local encryption_key="${ENV_FILE_ENCRYPTION_KEY:-}"
  
  [[ -n "$encryption_key" ]] || die "Encryption key not provided for encrypted environment file"
  
  # Use openssl for AES-256-CBC decryption
  if ! openssl enc -aes-256-cbc -d -a -in "$encrypted_file" -k "$encryption_key" 2>/dev/null; then
    die "Failed to decrypt environment file: $encrypted_file"
  fi
  
  log_debug "Environment file decrypted successfully"
}

#--------------------------------------------------------------------------------------------------
# Loads environment variables from file with optional prefix filtering
# @param $1  Path to environment file (optional, uses ENV_FILE_PATH if not provided)
#--------------------------------------------------------------------------------------------------
load_env_file() {
  local env_file="${1:-$ENV_FILE_PATH}"
  local temp_file=""
  
  [[ -n "$env_file" ]] || {
    if [[ "$ENV_FILE_REQUIRED" -eq 1 ]]; then
      die "Environment file path not specified and no default provided"
    else
      log_debug "No environment file specified, skipping load"
      return 0
    fi
  }
  
  log_info "Loading environment file: $env_file"
  
  # Validate file
  validate_env_file "$env_file"
  
  # Handle encrypted files
  if [[ "$ENV_FILE_ENCRYPTED" -eq 1 ]]; then
    temp_file=$(mktemp)
    decrypt_env_file "$env_file" > "$temp_file"
    env_file="$temp_file"
  fi
  
  # Load environment variables
  local loaded_count=0
  local line_num=0
  
  while IFS= read -r line; do
    ((line_num++))
    
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Extract key and value
    local key="${line%%=*}"
    local value="${line#*=}"
    
    # Apply prefix filtering if configured
    if [[ -n "$ENV_FILE_PREFIX" ]]; then
      if [[ "$key" == "$ENV_FILE_PREFIX"* ]]; then
        # Remove prefix from key name when exporting
        local export_key="${key#$ENV_FILE_PREFIX}"
        export "$export_key=$value"
        log_debug "Loaded environment variable: $export_key (from $key)"
        ((loaded_count++))
      fi
    else
      export "$key=$value"
      log_debug "Loaded environment variable: $key"
      ((loaded_count++))
    fi
  done < "$env_file"
  
  # Clean up temporary file
  [[ -n "$temp_file" ]] && rm -f "$temp_file"
  
  log_info "Environment file loaded successfully: $loaded_count variables from $env_file"
}

#--------------------------------------------------------------------------------------------------
# Validates that required environment variables are set
# @param $@  List of required environment variable names
#--------------------------------------------------------------------------------------------------
require_env_vars() {
  local missing_vars=()
  local var_name
  
  for var_name in "$@"; do
    if [[ -z "${!var_name:-}" ]]; then
      missing_vars+=("$var_name")
    fi
  done
  
  if [[ ${#missing_vars[@]} -gt 0 ]]; then
    log_error "Required environment variables not set:"
    printf '  %s\n' "${missing_vars[@]}" >&2
    die "Missing required environment variables"
  fi
  
  log_debug "All required environment variables are set"
}

#--------------------------------------------------------------------------------------------------
# Creates a secure environment file template
# @param $1  Output file path
# @param $2  Template type (basic, database, service)
#--------------------------------------------------------------------------------------------------
create_env_template() {
  local output_file="$1"
  local template_type="${2:-basic}"
  
  [[ -n "$output_file" ]] || die "Output file path required for environment template"
  
  # Check if file already exists
  if [[ -f "$output_file" ]]; then
    log_warn "Environment file already exists: $output_file"
    read -p "Overwrite existing file? (y/N): " -r
    [[ $REPLY =~ ^[Yy]$ ]] || return 1
  fi
  
  log_info "Creating environment file template: $output_file ($template_type)"
  
  # Create template content based on type
  case "$template_type" in
    basic)
      cat > "$output_file" << 'EOF'
# Basic Environment Configuration
# Generated by Enterprise AIOps Bash Framework

# Application Configuration
APP_NAME=my-application
APP_VERSION=1.0.0
APP_ENVIRONMENT=development

# Logging Configuration
LOG_LEVEL=INFO
LOG_FORMAT=json

# Security Configuration
ENCRYPTION_ENABLED=false
AUDIT_LOGGING=true
EOF
      ;;
    database)
      cat > "$output_file" << 'EOF'
# Database Environment Configuration
# Generated by Enterprise AIOps Bash Framework

# Database Connection
DB_HOST=localhost
DB_PORT=5432
DB_NAME=myapp_db
DB_USERNAME=app_user
DB_PASSWORD=CHANGE_ME_SECURE_PASSWORD

# Connection Pool Settings
DB_MAX_CONNECTIONS=20
DB_TIMEOUT_SECONDS=30

# Security Settings
DB_SSL_MODE=require
DB_SSL_CERT_PATH=/etc/ssl/certs/db-client.crt
DB_SSL_KEY_PATH=/etc/ssl/private/db-client.key
EOF
      ;;
    service)
      cat > "$output_file" << 'EOF'
# Service Environment Configuration
# Generated by Enterprise AIOps Bash Framework

# Service Configuration
SERVICE_NAME=my-service
SERVICE_PORT=8080
SERVICE_HOST=0.0.0.0
SERVICE_TIMEOUT=60

# External Dependencies
API_ENDPOINT=https://api.example.com
API_KEY=CHANGE_ME_API_KEY
API_TIMEOUT=30

# Monitoring Configuration
METRICS_ENABLED=true
METRICS_PORT=9090
HEALTH_CHECK_PATH=/health
EOF
      ;;
    *)
      die "Unknown template type: $template_type (use basic, database, or service)"
      ;;
  esac
  
  # Set secure permissions
  chmod 600 "$output_file"
  
  log_info "Environment template created: $output_file"
  log_warn "Please update placeholder values before using this file"
}

#--------------------------------------------------------------------------------------------------
# Encrypts an environment file for secure storage
# @param $1  Input environment file path
# @param $2  Output encrypted file path
#--------------------------------------------------------------------------------------------------
encrypt_env_file() {
  local input_file="$1"
  local output_file="$2"
  local encryption_key="${ENV_FILE_ENCRYPTION_KEY:-}"
  
  [[ -n "$input_file" ]] || die "Input file path required for encryption"
  [[ -n "$output_file" ]] || die "Output file path required for encryption"
  [[ -f "$input_file" ]] || die "Input file does not exist: $input_file"
  
  if [[ -z "$encryption_key" ]]; then
    log_warn "No encryption key provided, generating random key"
    encryption_key=$(openssl rand -base64 32)
    log_warn "Generated encryption key: $encryption_key"
    log_warn "Store this key securely - it cannot be recovered"
  fi
  
  log_info "Encrypting environment file: $input_file -> $output_file"
  
  # Validate input file first
  validate_env_file "$input_file"
  
  # Encrypt using AES-256-CBC
  if openssl enc -aes-256-cbc -a -salt -in "$input_file" -out "$output_file" -k "$encryption_key"; then
    chmod 600 "$output_file"
    log_info "Environment file encrypted successfully: $output_file"
  else
    die "Failed to encrypt environment file"
  fi
}

#--------------------------------------------------------------------------------------------------
# Shows current environment configuration (for debugging)
#--------------------------------------------------------------------------------------------------
show_env_config() {
  log_info "Environment file plugin configuration:"
  log_info "  Plugin version: $ENV_FILE_PLUGIN_VERSION"
  log_info "  Environment file path: ${ENV_FILE_PATH:-'not set'}"
  log_info "  Required: $ENV_FILE_REQUIRED"
  log_info "  Encrypted: $ENV_FILE_ENCRYPTED"
  log_info "  Variable prefix: ${ENV_FILE_PREFIX:-'none'}"
  
  if [[ -n "$ENV_FILE_PATH" && -f "$ENV_FILE_PATH" ]]; then
    local perms
    perms=$(stat -c%a "$ENV_FILE_PATH")
    log_info "  File permissions: $perms"
    
    local var_count
    var_count=$(grep -c "^[A-Z_][A-Z0-9_]*=" "$ENV_FILE_PATH" 2>/dev/null || echo "0")
    log_info "  Variables in file: $var_count"
  fi
}

# Plugin initialization
log_debug "Environment file plugin loaded (version $ENV_FILE_PLUGIN_VERSION)"

# Auto-load environment file if path is configured
if [[ -n "$ENV_FILE_PATH" && "$ENV_FILE_PATH" != "SKIP_AUTO_LOAD" ]]; then
  load_env_file
fi
