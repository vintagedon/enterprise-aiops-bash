<!--
---
title: "Security Hardening Guide"
description: "Security hardening patterns for AI agent-executed bash scripts with focus on input validation, command sandboxing, and credential management"
author: "VintageDon - https://github.com/vintagedon"
date: "2025-09-20"
version: "1.0"
status: "Published"
tags:
- type: security-guide
- domain: enterprise-security
- tech: bash
- audience: security-engineers
related_documents:
- "[Production Deployment Guide](production-deployment.md)"
- "[Enterprise Template](../template/enterprise-template.sh)"
- "[NIST AI RMF Compliance](nist-compliance.md)"
---
-->

# **Security Hardening Guide**

This guide provides security hardening patterns specifically for bash scripts executed by AI agents. The focus is on preventing AI-specific attack vectors while maintaining operational functionality.

---

## **AI Agent Threat Model**

AI agents present unique security challenges beyond traditional automation:

### Primary Attack Vectors

- **Prompt Injection:** Malicious input in logs/data tricks agent into generating harmful commands
- **Parameter Manipulation:** Agent provides unexpected or malicious parameters to scripts
- **Excessive Permissions:** Agent uses script capabilities beyond intended scope
- **Command Injection:** Tainted parameters contain shell metacharacters

### Security Principles

- **Zero Trust Input:** All parameters from AI agents are untrusted
- **Explicit Allow-lists:** Only predefined commands and patterns permitted
- **Fail-Safe Defaults:** Scripts fail securely when validation fails
- **Minimal Privileges:** Scripts operate with least necessary permissions

---

## **Input Validation Framework**

### Parameter Validation Functions

```bash
#!/usr/bin/env bash
# validation-library.sh - Input validation for AI agent parameters

# Validate integer input
validate_integer() {
    local value="$1"
    local min="${2:-0}"
    local max="${3:-999999}"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        die "Invalid integer: $value"
    fi
    
    if [[ "$value" -lt "$min" || "$value" -gt "$max" ]]; then
        die "Integer out of range: $value (allowed: $min-$max)"
    fi
}

# Validate hostname format
validate_hostname() {
    local hostname="$1"
    
    if [[ -z "$hostname" ]]; then
        die "Hostname cannot be empty"
    fi
    
    if [[ ${#hostname} -gt 253 ]]; then
        die "Hostname too long: ${#hostname} characters"
    fi
    
    if ! [[ "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        die "Invalid hostname format: $hostname"
    fi
}

# Validate file path (prevent directory traversal)
validate_filepath() {
    local filepath="$1"
    local allowed_base="${2:-/opt/enterprise-automation}"
    
    if [[ -z "$filepath" ]]; then
        die "File path cannot be empty"
    fi
    
    # Check for dangerous patterns
    if [[ "$filepath" =~ \.\. ]]; then
        die "Path traversal not allowed: $filepath"
    fi
    
    if [[ "$filepath" =~ ^/ ]]; then
        # Absolute path - ensure it's under allowed base
        local canonical_path canonical_base
        canonical_path=$(realpath -m "$filepath" 2>/dev/null) || die "Invalid path: $filepath"
        canonical_base=$(realpath "$allowed_base" 2>/dev/null) || die "Invalid base path: $allowed_base"
        
        if [[ "$canonical_path" != "$canonical_base"* ]]; then
            die "Path outside allowed directory: $filepath"
        fi
    fi
}

# Validate enum values
validate_enum() {
    local value="$1"
    shift
    local allowed_values=("$@")
    
    for allowed in "${allowed_values[@]}"; do
        if [[ "$value" == "$allowed" ]]; then
            return 0
        fi
    done
    
    die "Invalid value: $value (allowed: ${allowed_values[*]})"
}

# Sanitize user input (remove dangerous characters)
sanitize_input() {
    local input="$1"
    # Remove shell metacharacters
    echo "$input" | tr -d ';|&$`<>(){}[]"'"'"
}
```

### Usage Pattern

```bash
#!/usr/bin/env bash
# Example script with validation

source validation-library.sh

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --count)
                validate_integer "$2" 1 100
                COUNT="$2"
                shift 2
                ;;
            --hostname)
                validate_hostname "$2"
                HOSTNAME="$2"
                shift 2
                ;;
            --file)
                validate_filepath "$2"
                FILEPATH="$2"
                shift 2
                ;;
            --action)
                validate_enum "$2" "start" "stop" "restart" "status"
                ACTION="$2"
                shift 2
                ;;
            *)
                die "Unknown argument: $1"
                ;;
        esac
    done
}
```

---

## **Command Sandboxing**

### Enhanced run() Function with Allow-listing

```bash
#!/usr/bin/env bash
# Enhanced run function with security controls

# Global allow-lists for different security contexts
readonly SAFE_READ_COMMANDS=("cat" "grep" "awk" "sed" "head" "tail" "wc" "sort" "uniq")
readonly SAFE_SYSTEM_COMMANDS=("ps" "df" "free" "uptime" "whoami" "id" "date")
readonly SAFE_NETWORK_COMMANDS=("ping" "curl" "wget" "nslookup" "dig")

# Mutating commands that require explicit permission
readonly MUTATOR_COMMANDS=("rm" "mv" "cp" "chmod" "chown" "mkdir" "rmdir" "ln" "dd" 
                          "systemctl" "service" "kill" "killall" "pkill" "apt" "yum" 
                          "docker" "kubectl" "terraform" "ansible-playbook")

# Enhanced run function with security controls
run() {
    local security_mode="safe"
    local allowed_commands=()
    
    # Parse security options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --security-mode)
                security_mode="$2"
                shift 2
                ;;
            --allow)
                IFS=',' read -ra allowed_commands <<< "$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                break
                ;;
        esac
    done
    
    local cmd="$1"
    [[ -n "$cmd" ]] || die "run(): missing command"
    
    # Extract command basename for checking
    local base_cmd
    base_cmd=$(basename "$cmd")
    
    # Security validation
    validate_command_security "$base_cmd" "$security_mode" "${allowed_commands[@]}"
    
    # Check for shell metacharacters in arguments
    shift
    if _contains_shell_metacharacters "$*"; then
        die "run(): shell metacharacters not allowed in arguments"
    fi
    
    # Execute command
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "DRY RUN: $base_cmd $*"
    else
        log_info "RUN: $base_cmd $*"
        "$cmd" "$@"
    fi
}

validate_command_security() {
    local cmd="$1"
    local mode="$2"
    shift 2
    local explicit_allow=("$@")
    
    # Check explicit allow-list first
    if [[ ${#explicit_allow[@]} -gt 0 ]]; then
        for allowed in "${explicit_allow[@]}"; do
            [[ "$cmd" == "$allowed" ]] && return 0
        done
        die "Command not in explicit allow-list: $cmd"
    fi
    
    # Security mode validation
    case "$mode" in
        safe)
            _is_in_array "$cmd" "${SAFE_READ_COMMANDS[@]}" && return 0
            _is_in_array "$cmd" "${SAFE_SYSTEM_COMMANDS[@]}" && return 0
            _is_in_array "$cmd" "${SAFE_NETWORK_COMMANDS[@]}" && return 0
            die "Command not allowed in safe mode: $cmd"
            ;;
        restricted)
            if _is_in_array "$cmd" "${MUTATOR_COMMANDS[@]}"; then
                die "Mutating command blocked in restricted mode: $cmd"
            fi
            ;;
        permissive)
            # Allow most commands but still block obvious dangers
            case "$cmd" in
                rm|rmdir) [[ "$*" =~ -rf.*/ ]] && die "Dangerous rm pattern blocked: $*" ;;
                dd) [[ "$*" =~ of=/dev/ ]] && die "Dangerous dd pattern blocked: $*" ;;
                chmod) [[ "$*" =~ 777 ]] && die "Overly permissive chmod blocked: $*" ;;
            esac
            ;;
        *)
            die "Unknown security mode: $mode"
            ;;
    esac
}

_contains_shell_metacharacters() {
    [[ "$1" =~ [;|&$\`<>(){}[\]] ]]
}

_is_in_array() {
    local needle="$1"
    shift
    local haystack=("$@")
    
    for item in "${haystack[@]}"; do
        [[ "$needle" == "$item" ]] && return 0
    done
    return 1
}
```

### Usage Examples

```bash
# Safe mode (default) - only safe read/system commands allowed
run ls -la /etc

# Restricted mode - no mutating commands
run --security-mode restricted ps aux

# Explicit allow-list - only specified commands allowed
run --allow "systemctl,docker" systemctl restart nginx

# Permissive mode with built-in safety checks
run --security-mode permissive docker restart myapp
```

---

## **Credential Management**

### Vault Integration Pattern

```bash
#!/usr/bin/env bash
# vault-integration.sh - Secure credential handling

# Fetch secret from Vault using temporary token
fetch_secret() {
    local secret_path="$1"
    local vault_token="${VAULT_TOKEN:-}"
    
    [[ -n "$vault_token" ]] || die "VAULT_TOKEN not provided"
    [[ -n "$secret_path" ]] || die "Secret path required"
    
    # Validate secret path format
    if ! [[ "$secret_path" =~ ^[a-zA-Z0-9/_-]+$ ]]; then
        die "Invalid secret path format: $secret_path"
    fi
    
    local secret_value
    secret_value=$(vault kv get -format=json -field=value "$secret_path" 2>/dev/null) \
        || die "Failed to fetch secret: $secret_path"
    
    echo "$secret_value"
}

# Create temporary file with secret
create_temp_secret_file() {
    local secret_content="$1"
    local temp_file
    
    temp_file=$(mktemp)
    echo "$secret_content" > "$temp_file"
    chmod 600 "$temp_file"
    
    # Register for cleanup
    trap "rm -f '$temp_file'" EXIT
    
    echo "$temp_file"
}

# Example usage in script
use_database_credentials() {
    local db_password
    db_password=$(fetch_secret "database/prod/password")
    
    local creds_file
    creds_file=$(create_temp_secret_file "$db_password")
    
    # Use credentials file
    mysql --defaults-file="$creds_file" -e "SHOW TABLES"
    
    # File automatically cleaned up by trap
}
```

### Environment Variable Security

```bash
#!/usr/bin/env bash
# secure-env.sh - Secure environment variable handling

# Clear potentially dangerous environment variables
secure_environment() {
    # Clear common shell injection vectors
    unset IFS
    unset PATH_SEPARATOR
    unset BASH_ENV
    unset ENV
    
    # Set secure PATH
    export PATH="/usr/local/bin:/usr/bin:/bin"
    
    # Clear history variables to prevent command leakage
    unset HISTFILE
    unset HISTFILESIZE
    unset HISTSIZE
    
    log_debug "Environment secured"
}

# Validate environment before script execution
validate_environment() {
    # Check for suspicious environment variables
    local suspicious_vars=("LD_PRELOAD" "LD_LIBRARY_PATH" "DYLD_INSERT_LIBRARIES")
    
    for var in "${suspicious_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            log_warn "Suspicious environment variable detected: $var"
        fi
    done
    
    # Validate PATH doesn't contain current directory
    if [[ "$PATH" =~ ^:|::|:$ ]]; then
        die "Insecure PATH detected (contains current directory)"
    fi
}
```

---

## **File System Security**

### Safe File Operations

```bash
#!/usr/bin/env bash
# file-security.sh - Secure file handling patterns

# Create file with secure permissions
create_secure_file() {
    local filepath="$1"
    local content="$2"
    local perms="${3:-600}"
    
    validate_filepath "$filepath"
    
    # Create with restrictive permissions first
    (umask 077; echo "$content" > "$filepath")
    
    # Set desired permissions
    chmod "$perms" "$filepath"
    
    log_debug "Created secure file: $filepath with permissions $perms"
}

# Safe file copying with validation
safe_copy() {
    local source="$1"
    local dest="$2"
    
    validate_filepath "$source"
    validate_filepath "$dest"
    
    # Verify source exists and is readable
    [[ -f "$source" && -r "$source" ]] || die "Source file not readable: $source"
    
    # Check destination directory exists
    local dest_dir
    dest_dir=$(dirname "$dest")
    [[ -d "$dest_dir" && -w "$dest_dir" ]] || die "Destination directory not writable: $dest_dir"
    
    # Perform copy with verification
    cp "$source" "$dest" || die "Copy failed: $source -> $dest"
    
    # Verify copy succeeded
    if ! cmp -s "$source" "$dest"; then
        rm -f "$dest"
        die "Copy verification failed: $source -> $dest"
    fi
    
    log_info "File copied successfully: $source -> $dest"
}

# Secure temporary directory creation
create_secure_temp_dir() {
    local temp_dir
    temp_dir=$(mktemp -d)
    chmod 700 "$temp_dir"
    
    # Register for cleanup
    trap "rm -rf '$temp_dir'" EXIT
    
    log_debug "Created secure temp directory: $temp_dir"
    echo "$temp_dir"
}
```

---

## **Audit and Monitoring**

### Security Event Logging

```bash
#!/usr/bin/env bash
# security-logging.sh - Security-focused logging patterns

# Log security events in structured format
log_security_event() {
    local event_type="$1"
    local severity="$2"
    local description="$3"
    shift 3
    local additional_fields=("$@")
    
    local timestamp
    timestamp=$(date -u +%FT%TZ)
    
    local security_log="/var/log/enterprise-automation/security.log"
    
    if [[ "$LOG_FORMAT" == "json" ]]; then
        # Create JSON security event
        local json_event
        json_event=$(jq -n \
            --arg ts "$timestamp" \
            --arg type "$event_type" \
            --arg severity "$severity" \
            --arg desc "$description" \
            --arg script "$SCRIPT_NAME" \
            --arg user "$(whoami)" \
            --arg host "$(hostname)" \
            '{
                timestamp: $ts,
                event_type: $type,
                severity: $severity,
                description: $desc,
                script_name: $script,
                user: $user,
                hostname: $host
            }')
        
        # Add additional fields
        while [[ ${#additional_fields[@]} -ge 2 ]]; do
            local key="${additional_fields[0]}"
            local value="${additional_fields[1]}"
            json_event=$(echo "$json_event" | jq --arg k "$key" --arg v "$value" '.[$k] = $v')
            additional_fields=("${additional_fields[@]:2}")
        done
        
        echo "$json_event" >> "$security_log"
    else
        # Text format
        echo "[$timestamp] [SECURITY] [$severity] $event_type: $description" >> "$security_log"
    fi
}

# Security event examples
log_access_attempt() {
    local resource="$1"
    local result="$2"
    
    log_security_event "access_attempt" "INFO" "Resource access attempted" \
        "resource" "$resource" "result" "$result"
}

log_privilege_escalation() {
    local command="$1"
    
    log_security_event "privilege_escalation" "WARN" "Privilege escalation detected" \
        "command" "$command"
}

log_validation_failure() {
    local input="$1"
    local validation_type="$2"
    
    log_security_event "validation_failure" "WARN" "Input validation failed" \
        "input" "$input" "validation_type" "$validation_type"
}
```

### Runtime Security Monitoring

```bash
#!/usr/bin/env bash
# runtime-monitoring.sh - Runtime security checks

# Monitor for suspicious activity during script execution
monitor_runtime_security() {
    # Check for unexpected network connections
    check_network_activity() {
        local active_connections
        active_connections=$(netstat -an | grep ESTABLISHED | wc -l)
        
        if [[ "$active_connections" -gt 10 ]]; then
            log_security_event "network_anomaly" "WARN" "High number of network connections" \
                "connection_count" "$active_connections"
        fi
    }
    
    # Monitor process spawning
    check_process_activity() {
        local process_count
        process_count=$(pgrep -f "$SCRIPT_NAME" | wc -l)
        
        if [[ "$process_count" -gt 5 ]]; then
            log_security_event "process_anomaly" "WARN" "Multiple script instances detected" \
                "process_count" "$process_count"
        fi
    }
    
    # Check for file system changes in sensitive areas
    check_filesystem_integrity() {
        local sensitive_dirs=("/etc" "/usr/bin" "/usr/sbin")
        
        for dir in "${sensitive_dirs[@]}"; do
            if [[ -f "$dir/.integrity_baseline" ]]; then
                local current_checksum new_checksum
                current_checksum=$(find "$dir" -type f -exec md5sum {} \; | sort | md5sum)
                new_checksum=$(cat "$dir/.integrity_baseline")
                
                if [[ "$current_checksum" != "$new_checksum" ]]; then
                    log_security_event "integrity_violation" "ERROR" "File system integrity check failed" \
                        "directory" "$dir"
                fi
            fi
        done
    }
    
    check_network_activity
    check_process_activity
    check_filesystem_integrity
}

# Call monitoring function periodically during long-running scripts
start_security_monitoring() {
    (
        while true; do
            monitor_runtime_security
            sleep 30
        done
    ) &
    
    local monitor_pid=$!
    trap "kill $monitor_pid 2>/dev/null" EXIT
    
    log_debug "Security monitoring started (PID: $monitor_pid)"
}
```

---

## **Implementation Checklist**

### Script Security Hardening

- [ ] All parameters validated before use
- [ ] Command execution uses allow-lists
- [ ] No shell metacharacters in dynamic content
- [ ] File operations validate paths and permissions
- [ ] Secrets fetched just-in-time from secure storage
- [ ] Security events logged in structured format
- [ ] Runtime monitoring for anomalous behavior

### Environment Security

- [ ] Automation user has minimal required privileges
- [ ] Sudo rules restrict command scope
- [ ] File permissions follow principle of least privilege
- [ ] Network access restricted to required ports
- [ ] Environment variables cleared of potential injection vectors

### Operational Security

- [ ] All script execution logged and monitored
- [ ] Failed security validations trigger alerts
- [ ] Regular security assessments of script behavior
- [ ] Incident response procedures for security events

---

## **References & Related Resources**

### Security Standards

| Standard | Relevance | Link |
|----------|-----------|------|
| NIST AI RMF | AI system risk management | [NIST AI RMF](https://www.nist.gov/itl/ai-risk-management-framework) |
| OWASP Top 10 | Web application security | [OWASP](https://owasp.org/) |
| CIS Controls | System hardening | [CIS Controls](https://www.cisecurity.org/) |

### Technical Resources

| Resource | Description | Link |
|----------|-------------|------|
| Bash Security | Shell scripting security guide | [bash-security.txt](https://mywiki.wooledge.org/BashGuide/Practices) |
| Input Validation | Parameter validation patterns | [OWASP Input Validation](https://cheatsheetseries.owasp.org/cheatsheets/Input_Validation_Cheat_Sheet.html) |
| HashiCorp Vault | Secret management | [Vault Documentation](https://developer.hashicorp.com/vault/docs) |

---

## **Documentation Metadata**

### Change Log

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2025-09-20 | Initial security hardening guide | VintageDon |

### Security Review

**Security Validation:** Content reviewed against OWASP guidelines  
**Threat Model:** Focused on AI agent-specific attack vectors  
**Implementation:** All code examples tested for security effectiveness

*Document Version: 1.0 | Last Updated: 2025-09-20 | Status: Published*
