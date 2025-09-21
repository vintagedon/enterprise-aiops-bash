<!--
---
title: "Secret Management Plugins"
description: "Enterprise-grade secret management integrations for secure credential handling in bash automation"
author: "VintageDon - https://github.com/vintagedon"
date: "2025-09-20"
version: "1.0"
status: "Published"
tags:
- type: kb-article
- domain: enterprise-security
- tech: bash
- audience: security-engineers
related_documents:
- "[Plugin Architecture](../README.md)"
- "[Security Patterns](../../patterns/security/README.md)"
- "[Enterprise Template](../../template/enterprise-template.sh)"
---
-->

# **Secret Management Plugins**

This directory contains enterprise-grade secret management plugins that provide secure credential handling for bash automation scripts. These plugins integrate with popular secret management systems and provide consistent APIs for credential access.

---

## **Introduction**

Secret management is critical for enterprise automation security. These plugins provide standardized interfaces to various secret storage systems while maintaining security best practices and framework integration.

### Purpose

These plugins eliminate hardcoded credentials from automation scripts by providing secure, auditable access to enterprise secret management systems.

### Scope

**What's Covered:**

- Environment file management with encryption
- HashiCorp Vault integration
- Secure credential loading patterns
- Authentication method abstractions

### Target Audience

**Primary Users:** Security engineers, DevOps engineers, platform engineers  
**Secondary Users:** System administrators, automation developers  
**Background Assumed:** Understanding of secret management concepts, enterprise security requirements

### Overview

Plugins provide consistent APIs while supporting multiple backend systems, allowing scripts to be portable across different enterprise environments.

---

## **Available Secret Management Plugins**

This section provides an overview of each secret management plugin and its capabilities.

### Environment File Plugin (`env-file.sh`)

**Purpose:** Secure loading and management of environment files with optional encryption  
**Use Cases:** Development environments, containerized applications, simple secret storage  
**Security Features:** File permission validation, encryption support, format validation

#### Key Capabilities

| Feature | Description | Security Benefit |
|---------|-------------|------------------|
| **Format Validation** | Validates environment file syntax | Prevents configuration errors |
| **Permission Checking** | Verifies secure file permissions | Protects against unauthorized access |
| **Encryption Support** | AES-256-CBC encryption for files | Secure storage of sensitive data |
| **Prefix Filtering** | Loads only specified variable prefixes | Namespace isolation |
| **Template Generation** | Creates secure templates | Standardized configuration format |

#### Usage Examples

```bash
# Source the plugin
source "plugins/secrets/env-file.sh"

# Basic environment file loading
ENV_FILE_PATH="/opt/app/.env"
load_env_file

# Encrypted environment file
ENV_FILE_PATH="/opt/app/.env.encrypted"
ENV_FILE_ENCRYPTED=1
ENV_FILE_ENCRYPTION_KEY="your-encryption-key"
load_env_file

# Prefix-filtered loading
ENV_FILE_PREFIX="MYAPP_"
load_env_file "/opt/app/.env"

# Validate required variables
require_env_vars "DB_HOST" "DB_PASSWORD" "API_KEY"
```

### HashiCorp Vault Plugin (`vault.sh`)

**Purpose:** Enterprise-grade secret management with HashiCorp Vault integration  
**Use Cases:** Production environments, enterprise secret management, dynamic credentials  
**Security Features:** Multiple authentication methods, token management, audit logging

#### Key Capabilities

| Feature | Description | Security Benefit |
|---------|-------------|------------------|
| **Multi-Auth Support** | Token, AWS, K8s, AppRole, UserPass | Flexible enterprise integration |
| **Secret Engine Support** | KV v1/v2, generic engines | Compatibility with existing setups |
| **Token Management** | Automatic renewal and cleanup | Secure credential lifecycle |
| **Environment Loading** | Bulk environment variable loading | Simplified secret consumption |
| **Dynamic Secrets** | Support for short-lived credentials | Reduced credential exposure |

#### Authentication Methods

```bash
# Token authentication
VAULT_TOKEN="hvs.CAESIF..."
vault_authenticate token

# AWS IAM authentication
VAULT_AWS_ROLE="automation-role"
vault_authenticate aws

# Kubernetes service account
VAULT_K8S_ROLE="automation-sa"
vault_authenticate kubernetes

# AppRole authentication
VAULT_ROLE_ID="role-id-here"
VAULT_SECRET_ID="secret-id-here"
vault_authenticate approle

# Username/password
VAULT_USERNAME="automation-user"
VAULT_PASSWORD="secure-password"
vault_authenticate userpass
```

#### Usage Examples

```bash
# Source the plugin
source "plugins/secrets/vault.sh"

# Retrieve individual secrets
DB_PASSWORD=$(vault_get_secret "database/prod" "password")
API_KEY=$(vault_get_secret "external/api" "key")

# Load entire secret as environment variables
vault_load_env "application/config" "APP_"

# Store secrets (requires write permissions)
vault_put_secret "database/staging" '{"username":"app","password":"newpass"}'

# Check authentication status
vault_status
```

---

## **Plugin Integration Patterns**

### Framework Integration

#### Error Handling Integration

```bash
# Secure secret retrieval with framework error handling
get_database_credentials() {
  local db_secret_path="$1"
  
  log_info "Retrieving database credentials from Vault"
  
  # Use vault plugin with framework error handling
  DB_HOST=$(vault_get_secret "$db_secret_path" "host") || die "Failed to retrieve DB host"
  DB_USER=$(vault_get_secret "$db_secret_path" "username") || die "Failed to retrieve DB user"
  DB_PASS=$(vault_get_secret "$db_secret_path" "password") || die "Failed to retrieve DB password"
  
  log_info "Database credentials retrieved successfully"
}
```

#### Observability Integration

```bash
# Secret access with structured logging
secure_operation_with_monitoring() {
  local operation="$1"
  local secret_path="$2"
  
  log_structured "INFO" "Secret access initiated" \
    "operation" "$operation" \
    "secret_path" "$secret_path" \
    "auth_method" "$VAULT_AUTH_METHOD"
  
  if vault_get_secret "$secret_path" >/dev/null; then
    log_structured "INFO" "Secret access successful" \
      "operation" "$operation" \
      "secret_path" "$secret_path"
  else
    log_structured "ERROR" "Secret access failed" \
      "operation" "$operation" \
      "secret_path" "$secret_path"
    return 1
  fi
}
```

### Multi-Plugin Architecture

#### Fallback Secret Resolution

```bash
# Try multiple secret sources with fallback
get_secret_with_fallback() {
  local secret_name="$1"
  local secret_value=""
  
  # Try Vault first
  if [[ "$VAULT_AUTHENTICATED" -eq 1 ]]; then
    secret_value=$(vault_get_secret "application/secrets" "$secret_name" 2>/dev/null)
  fi
  
  # Fallback to environment file
  if [[ -z "$secret_value" && -n "$ENV_FILE_PATH" ]]; then
    secret_value="${!secret_name:-}"
  fi
  
  # Final fallback to environment variable
  if [[ -z "$secret_value" ]]; then
    secret_value="${!secret_name:-}"
  fi
  
  [[ -n "$secret_value" ]] || die "Secret not found: $secret_name"
  echo "$secret_value"
}
```

---

## **Security Best Practices**

### Credential Lifecycle Management

#### Token Rotation

```bash
# Automatic token renewal for long-running processes
ensure_vault_token_valid() {
  if ! vault_token_valid; then
    log_warn "Vault token expired, attempting renewal"
    if ! vault_renew_token; then
      log_info "Token renewal failed, re-authenticating"
      vault_authenticate
    fi
  fi
}

# Use in long-running operations
long_running_operation() {
  while true; do
    ensure_vault_token_valid
    
    # Perform operation requiring secrets
    secret_value=$(vault_get_secret "path/to/secret" "key")
    perform_work_with_secret "$secret_value"
    
    sleep 300  # 5 minutes
  done
}
```

#### Secure Environment Handling

```bash
# Clear sensitive environment variables after use
secure_environment_cleanup() {
  local sensitive_vars=(
    "DB_PASSWORD"
    "API_KEY" 
    "JWT_SECRET"
    "ENCRYPTION_KEY"
  )
  
  for var in "${sensitive_vars[@]}"; do
    unset "$var"
  done
  
  log_debug "Sensitive environment variables cleared"
}

# Register cleanup on script exit
trap secure_environment_cleanup EXIT
```

### Audit and Compliance

#### Secret Access Logging

```bash
# Comprehensive secret access logging
log_secret_access() {
  local action="$1"
  local secret_path="$2"
  local result="$3"
  
  log_structured "INFO" "Secret access audit" \
    "audit_event" "secret_access" \
    "action" "$action" \
    "secret_path" "$secret_path" \
    "result" "$result" \
    "user" "${USER:-unknown}" \
    "script" "$SCRIPT_NAME" \
    "timestamp" "$(date -u +%FT%TZ)"
}
```

#### Compliance Validation

```bash
# Validate secret management compliance
validate_secret_compliance() {
  local compliance_issues=()
  
  # Check for hardcoded secrets
  if grep -r "password\|secret\|key" . --include="*.sh" | grep -v "vault_get_secret\|load_env_file"; then
    compliance_issues+=("Potential hardcoded secrets detected")
  fi
  
  # Validate secure file permissions
  if [[ -n "$ENV_FILE_PATH" && -f "$ENV_FILE_PATH" ]]; then
    local perms
    perms=$(stat -c%a "$ENV_FILE_PATH")
    if [[ "${perms: -1}" != "0" ]]; then
      compliance_issues+=("Environment file has insecure permissions: $perms")
    fi
  fi
  
  # Report compliance status
  if [[ ${#compliance_issues[@]} -eq 0 ]]; then
    log_info "Secret management compliance validation passed"
  else
    log_error "Secret management compliance issues detected:"
    printf '  %s\n' "${compliance_issues[@]}" >&2
    return 1
  fi
}
```

---

## **Usage Guidelines**

### Plugin Selection

| Use Case | Recommended Plugin | Rationale |
|----------|-------------------|-----------|
| **Development Environment** | env-file.sh | Simple, portable, version-controlled |
| **Production Enterprise** | vault.sh | Enterprise features, audit, compliance |
| **Container Deployment** | env-file.sh + encryption | Portable, secure for orchestration |
| **CI/CD Pipeline** | vault.sh with AppRole | Automated authentication, audit trail |
| **Multi-Cloud Deployment** | vault.sh | Consistent interface across environments |

### Integration Patterns

#### Plugin Loading Strategy

```bash
# Conditional plugin loading based on environment
load_secret_plugin() {
  local environment="${ENVIRONMENT:-development}"
  
  case "$environment" in
    development|dev)
      source "plugins/secrets/env-file.sh"
      ENV_FILE_PATH=".env.dev"
      ;;
    staging|stage)
      source "plugins/secrets/vault.sh"
      VAULT_AUTH_METHOD="userpass"
      ;;
    production|prod)
      source "plugins/secrets/vault.sh"
      VAULT_AUTH_METHOD="aws"
      ;;
    *)
      die "Unknown environment: $environment"
      ;;
  esac
}
```

#### Configuration Management

```bash
# Environment-specific configuration
configure_secret_management() {
  local config_file="${SECRET_CONFIG_FILE:-/etc/automation/secrets.conf}"
  
  if [[ -f "$config_file" ]]; then
    source "$config_file"
    log_info "Secret management configuration loaded: $config_file"
  else
    log_warn "Secret configuration file not found: $config_file"
    log_warn "Using default configuration"
  fi
}
```

---

## **Troubleshooting**

### Common Issues

| Issue | Symptoms | Resolution |
|-------|----------|------------|
| **Vault Connection Failed** | Cannot connect to Vault server | Verify VAULT_ADDR, network connectivity, Vault status |
| **Authentication Failed** | Invalid credentials or expired token | Check authentication method, refresh credentials |
| **Permission Denied** | Cannot read secrets or environment files | Verify file permissions, Vault policies, user access |
| **Environment File Errors** | Malformed variables or syntax errors | Validate file format, check for special characters |
| **Token Expiration** | Intermittent authentication failures | Implement token renewal, reduce token TTL dependencies |

### Debugging Commands

```bash
# Debug Vault connectivity
vault_debug() {
  log_info "Vault debugging information:"
  log_info "  Address: $VAULT_ADDR"
  log_info "  Status: $(vault status 2>&1 || echo "unreachable")"
  log_info "  Token: ${VAULT_TOKEN:+set}" 
  log_info "  Auth method: $VAULT_AUTH_METHOD"
  
  if vault_token_valid; then
    vault token lookup
  fi
}

# Debug environment file loading
env_debug() {
  log_info "Environment file debugging:"
  log_info "  Path: ${ENV_FILE_PATH:-not set}"
  log_info "  Exists: $([[ -f "$ENV_FILE_PATH" ]] && echo "yes" || echo "no")"
  log_info "  Readable: $([[ -r "$ENV_FILE_PATH" ]] && echo "yes" || echo "no")"
  log_info "  Permissions: $(stat -c%a "$ENV_FILE_PATH" 2>/dev/null || echo "unknown")"
}
```

---

## **References & Related Resources**

### Internal References

| Document Type | Title | Relationship | Link |
|---------------|-------|--------------|------|
| Plugin Architecture | Plugin System Overview | Framework integration | [../README.md](../README.md) |
| Security Patterns | Input Validation | Security integration | [../../patterns/security/README.md](../../patterns/security/README.md) |
| Framework Core | Enterprise Template | Foundation integration | [../../template/enterprise-template.sh](../../template/enterprise-template.sh) |

### External Resources

| Resource Type | Title | Description | Link |
|---------------|-------|-------------|------|
| Documentation | HashiCorp Vault | Official Vault documentation | [vaultproject.io](https://www.vaultproject.io/) |
| Security Guide | OWASP Secret Management | Secret management best practices | [owasp.org](https://owasp.org/www-community/vulnerabilities/Password_Plaintext_Storage) |
| Standards | NIST Cryptographic Standards | Encryption and key management | [csrc.nist.gov](https://csrc.nist.gov/) |

---

## **Documentation Metadata**

### Change Log

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2025-09-20 | Initial secret management plugins documentation | VintageDon |

### Authorship & Collaboration

**Primary Author:** VintageDon ([GitHub Profile](https://github.com/vintagedon))  
**Security Review:** Production validation in enterprise environment  
**Testing Environment:** Validated with HashiCorp Vault and encrypted environment files

### Technical Notes

**Plugin Compatibility:** Compatible with Enterprise AIOps Bash Framework v1.0  
**Security Validation:** All plugins tested against enterprise security requirements  
**Production Status:** Deployed in Proxmox Astronomy Lab secure environment

*Document Version: 1.0 | Last Updated: 2025-09-20 | Status: Published*
