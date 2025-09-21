<!--
---
title: "Security Patterns for Enterprise Bash Automation"
description: "Production-grade security validation patterns for bash scripts handling untrusted input from AI agents and external systems"
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
- "[Enterprise Template](../../template/enterprise-template.sh)"
- "[Idempotent Patterns](../idempotent/README.md)"
- "[Observability Patterns](../observability/README.md)"
---
-->

# **Security Patterns for Enterprise Bash Automation**

This document provides production-tested security patterns for bash scripts that handle input from AI agents, external APIs, and untrusted sources. These patterns are essential for preventing command injection, path traversal, and other security vulnerabilities in enterprise automation environments.

---

## **Introduction**

Security validation is critical when bash scripts are invoked by AI agents or integrated with external systems. Unlike human operators who can identify suspicious inputs, automated systems require explicit validation logic to prevent security vulnerabilities.

### Purpose

This guide demonstrates practical security validation patterns using the Enterprise AIOps Bash Framework, providing defensive programming techniques that ensure scripts can safely handle untrusted input from any source.

### Scope

**What's Covered:**

- Input validation patterns for common data types
- Shell metacharacter detection and prevention
- Path traversal attack mitigation
- File access security verification
- Safe parameter handling techniques

### Target Audience

**Primary Users:** Security engineers, DevOps engineers, SRE professionals  
**Secondary Users:** System administrators, automation developers  
**Background Assumed:** Understanding of common security vulnerabilities, bash scripting experience

### Overview

Security patterns follow a "validate first, use second" approach where all external input undergoes comprehensive validation before being used in any operations.

---

## **Dependencies & Relationships**

This security framework integrates with other framework components to provide comprehensive protection.

### Related Components

| Component | Relationship | Integration Points | Documentation |
|-----------|--------------|-------------------|---------------|
| Enterprise Template | Foundation | Uses framework error handling and logging for security events | [enterprise-template.sh](../../template/enterprise-template.sh) |
| Validation Framework | Core Security | Leverages validation.sh for hostname and path checking | [validation.sh](../../template/framework/validation.sh) |
| Idempotent Patterns | Safe Operations | Ensures security checks don't interfere with repeatability | [Idempotent README](../idempotent/README.md) |

### External Dependencies

- **bash 4.0+** - Modern bash features for robust pattern matching
- **coreutils** - File system operations and path resolution
- **realpath** - Canonical path resolution for security checks

---

## **Core Security Patterns**

This section demonstrates fundamental security validation patterns for protecting against common attack vectors.

### Input Type Validation

#### Alphanumeric Safe Validation

```bash
validate_alphanumeric_safe() {
  local input="$1"
  local field_name="${2:-field}"
  
  [[ -n "$input" ]] || die "Empty input not allowed for $field_name"
  
  # Allow only alphanumeric, hyphens, and underscores
  if [[ ! "$input" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    die "Invalid characters in $field_name: '$input'"
  fi
}
```

#### Hostname Format Validation

```bash
validate_hostname_format() {
  local hostname="$1"
  
  [[ -n "$hostname" ]] || die "Hostname cannot be empty"
  [[ ${#hostname} -le 253 ]] || die "Hostname too long: ${#hostname} characters"
  
  # RFC-compliant hostname pattern
  if ! [[ "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    die "Invalid hostname format: '$hostname'"
  fi
}
```

#### Port Number Validation

```bash
validate_port_number() {
  local port="$1"
  
  [[ "$port" =~ ^[0-9]+$ ]] || die "Port must be a positive integer: '$port'"
  [[ "$port" -ge 1 && "$port" -le 65535 ]] || die "Port out of range: $port"
}
```

### Path Security Validation

#### Path Traversal Prevention

```bash
validate_file_path() {
  local file_path="$1"
  local access_mode="${2:-r}"
  
  # Prevent path traversal attacks
  [[ "$file_path" =~ \.\./|\.\.\\ ]] && die "Path traversal detected: '$file_path'"
  
  # Normalize to absolute path
  local abs_path
  abs_path="$(realpath -m "$file_path")" || die "Invalid file path: '$file_path'"
  
  # Verify access permissions
  case "$access_mode" in
    r) [[ -f "$abs_path" && -r "$abs_path" ]] || die "File not readable: '$abs_path'" ;;
    w) [[ -w "$abs_path" || -w "$(dirname "$abs_path")" ]] || die "File not writable: '$abs_path'" ;;
    x) [[ -f "$abs_path" && -x "$abs_path" ]] || die "File not executable: '$abs_path'" ;;
  esac
}
```

### Command Injection Prevention

#### Shell Metacharacter Detection

```bash
validate_no_shell_metacharacters() {
  local input="$1"
  local field_name="${2:-input}"
  
  # Check for dangerous shell metacharacters
  local dangerous_chars=';&|<>$`(){}\[]'
  local char
  
  for (( i=0; i<${#dangerous_chars}; i++ )); do
    char="${dangerous_chars:$i:1}"
    [[ "$input" == *"$char"* ]] && die "Dangerous character '$char' in $field_name: '$input'"
  done
  
  # Check for command substitution patterns
  [[ "$input" =~ \$\(.*\) ]] && die "Command substitution detected in $field_name"
  [[ "$input" =~ `.*` ]] && die "Backtick substitution detected in $field_name"
}
```

---

## **Advanced Security Patterns**

### Multi-Layer Validation

#### Comprehensive Parameter Validation

```bash
validate_server_parameter() {
  local server="$1"
  
  # Layer 1: Basic format validation
  validate_hostname_format "$server"
  
  # Layer 2: Security character check
  validate_no_shell_metacharacters "$server" "server"
  
  # Layer 3: Length bounds
  validate_string_length "$server" 1 253 "server"
  
  # Layer 4: Business logic validation
  [[ "$server" != "localhost" ]] || die "Localhost not allowed in automation"
}
```

### Safe Command Construction

#### Parameterized Command Building

```bash
# UNSAFE: Direct string interpolation
# run "ssh $hostname 'systemctl restart $service'"

# SAFE: Validated parameters with explicit quoting
safe_service_restart() {
  local hostname="$1"
  local service="$2"
  
  # Validate all inputs first
  validate_hostname_format "$hostname"
  validate_alphanumeric_safe "$service" "service name"
  validate_no_shell_metacharacters "$hostname" "hostname"
  validate_no_shell_metacharacters "$service" "service"
  
  # Construct command safely
  run ssh "$hostname" systemctl restart "$service"
}
```

### Email and Contact Validation

#### Email Format Security

```bash
validate_email_format() {
  local email="$1"
  
  [[ -n "$email" ]] || die "Email address cannot be empty"
  [[ ${#email} -le 254 ]] || die "Email address too long"
  
  # Basic RFC-compatible pattern
  local email_pattern='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
  [[ "$email" =~ $email_pattern ]] || die "Invalid email format: '$email'"
  
  # Security checks
  [[ "$email" != *".."* ]] || die "Email contains consecutive dots"
}
```

---

## **Security Implementation Examples**

### Working Example: Input Validation Script

The `input-validation.sh` script demonstrates comprehensive security patterns:

| Validation Type | Security Feature | Protection Against |
|-----------------|------------------|-------------------|
| Hostname Format | RFC compliance checking | Domain spoofing, injection |
| Port Range | Numeric bounds validation | Buffer overflow, invalid config |
| File Path | Path traversal detection | Directory traversal attacks |
| Shell Metacharacters | Dangerous character blocking | Command injection |
| Email Format | Pattern matching | Email injection, spoofing |
| String Length | Bounds checking | Buffer overflow, DoS |

### Usage Examples

```bash
# Basic validation - all required parameters
./input-validation.sh --hostname web01.company.com --port 8080 --config-file /etc/app.conf

# Full validation with optional parameters
./input-validation.sh --hostname api-server --port 443 --config-file /opt/app/config.yml \
                      --email admin@company.com --timeout 300

# Dry run mode - preview validation without execution
./input-validation.sh --hostname test-server --port 8080 --config-file /tmp/test.conf --dry-run
```

---

## **Security Best Practices**

### Defense in Depth Strategy

**Layered Validation Approach:**

1. **Format Validation** - Verify input matches expected patterns
2. **Security Validation** - Check for malicious characters and patterns
3. **Business Logic Validation** - Ensure input meets operational requirements
4. **Runtime Validation** - Verify resources exist and are accessible

**Implementation Pattern:**

```bash
validate_user_input() {
  local user_input="$1"
  local field_name="$2"
  
  # Layer 1: Format check
  validate_required_field "$user_input" "$field_name"
  
  # Layer 2: Security check
  validate_no_shell_metacharacters "$user_input" "$field_name"
  
  # Layer 3: Business rules
  validate_business_constraints "$user_input" "$field_name"
  
  # Layer 4: Runtime verification
  verify_runtime_requirements "$user_input" "$field_name"
}
```

### Secure Error Handling

**Information Disclosure Prevention:**

```bash
# UNSAFE: Reveals system information
# die "Failed to connect to database server db01.internal.company.com:5432"

# SAFE: Generic error message with logged details
validate_database_connection() {
  local db_host="$1"
  local db_port="$2"
  
  if ! test_connection "$db_host" "$db_port"; then
    log_error "Database connection failed" "host=$db_host" "port=$db_port"
    die "Database connection validation failed"
  fi
}
```

### Input Sanitization Patterns

| Input Type | Validation Pattern | Security Benefit |
|------------|-------------------|------------------|
| **Filenames** | `^[a-zA-Z0-9._-]+$` | Prevents path traversal |
| **Service Names** | `^[a-zA-Z0-9-]+$` | Blocks injection in systemctl commands |
| **IP Addresses** | IPv4/IPv6 regex patterns | Ensures valid network targets |
| **URLs** | Protocol and domain validation | Prevents SSRF attacks |
| **JSON Payloads** | jq validation | Ensures well-formed data |

---

## **Integration with Framework Components**

### Error Handling Integration

```bash
# Security validation with framework error handling
secure_file_operation() {
  local source_file="$1"
  local target_file="$2"
  
  # Use framework validation with security enhancements
  validate_file_path "$source_file" "r"
  validate_file_path "$target_file" "w"
  
  # Additional security checks
  validate_no_shell_metacharacters "$source_file" "source file"
  validate_no_shell_metacharacters "$target_file" "target file"
  
  # Safe operation with framework run() function
  run cp "$source_file" "$target_file"
}
```

### Logging Security Events

```bash
# Security-aware logging
log_security_event() {
  local event_type="$1"
  local details="$2"
  
  # Log security events with high priority
  log_warn "SECURITY: $event_type" "$details"
  
  # Optional: Send to security monitoring system
  [[ -n "${SECURITY_LOG_ENDPOINT:-}" ]] && \
    curl -s -X POST "$SECURITY_LOG_ENDPOINT" -d "event=$event_type&details=$details" || true
}
```

---

## **Usage & Maintenance**

### Usage Guidelines

**Script Development:**

- Validate all external input before use
- Use framework logging for security events
- Implement multi-layer validation for critical parameters

**Operations Integration:**

- Security validation failures provide clear error messages
- All validation events are logged for audit trails
- Framework error handling ensures proper security event reporting

**AI Agent Integration:**

- Validation functions provide deterministic success/failure results
- Clear error messages help agents understand validation failures
- Security checks prevent agents from executing unsafe operations

### Troubleshooting

| Issue | Symptoms | Resolution |
|-------|----------|------------|
| **Validation False Positives** | Legitimate input rejected | Review validation patterns; adjust regex if too restrictive |
| **Performance Impact** | Slow script execution | Profile validation functions; optimize regex patterns |
| **Path Resolution Errors** | realpath failures | Ensure sufficient permissions; check filesystem access |
| **Character Encoding Issues** | Unicode input problems | Implement UTF-8 validation; sanitize character sets |

### Maintenance & Updates

**Security Pattern Evolution:**

- Regularly review and update validation patterns
- Monitor security advisories for new attack vectors
- Test validation logic against known attack payloads

**Framework Integration:**

- Maintain compatibility with core framework updates
- Ensure security patterns integrate with observability features
- Update documentation when patterns evolve

---

## **References & Related Resources**

### Internal References

| Document Type | Title | Relationship | Link |
|---------------|-------|--------------|------|
| Framework Core | Enterprise Template | Foundation security implementation | [enterprise-template.sh](../../template/enterprise-template.sh) |
| Framework Module | Validation Functions | Core security validation utilities | [validation.sh](../../template/framework/validation.sh) |
| Pattern Guide | Idempotent Patterns | Security-aware operation patterns | [Idempotent README](../idempotent/README.md) |

### External Resources

| Resource Type | Title | Description | Link |
|---------------|-------|-------------|------|
| Security Guide | OWASP Command Injection | Prevention techniques and patterns | [owasp.org/command-injection](https://owasp.org/www-community/attacks/Command_Injection) |
| Standards | NIST Secure Coding | Enterprise security standards | [csrc.nist.gov](https://csrc.nist.gov/Projects/ssdf) |
| Best Practices | CIS Controls | Security implementation guidance | [cisecurity.org](https://www.cisecurity.org/controls/) |

---

## **Documentation Metadata**

### Change Log

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2025-09-20 | Initial security patterns documentation | VintageDon |

### Authorship & Collaboration

**Primary Author:** VintageDon ([GitHub Profile](https://github.com/vintagedon))  
**Security Review:** Production validation in enterprise environment  
**Testing Method:** Penetration testing against common attack vectors

### Technical Notes

**Security Validation:** All patterns tested against OWASP Top 10 vulnerabilities  
**Framework Version:** Compatible with Enterprise AIOps Bash Framework v1.0  
**Production Status:** Deployed in Proxmox Astronomy Lab security-hardened environment

*Document Version: 1.0 | Last Updated: 2025-09-20 | Status: Published*
