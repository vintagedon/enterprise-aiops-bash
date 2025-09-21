<!--
---
title: "Enterprise Template Examples Directory"
description: "Practical examples demonstrating enterprise bash template usage patterns and best practices"
author: "VintageDon - https://github.com/vintagedon"
date: "2025-09-20"
version: "1.0"
status: "Published"
tags:
- type: kb-article
- domain: enterprise-automation
- tech: bash
- audience: devops-engineers
related_documents:
- "[Enterprise Template](../enterprise-template.sh)"
- "[Pattern Library](../../patterns/README.md)"
- "[Framework Core](../framework/)"
---
-->

# **Enterprise Template Examples Directory**

This directory contains practical examples demonstrating how to use the Enterprise AIOps Bash Framework template for common automation scenarios. Each example builds upon the framework foundation while showcasing specific implementation patterns.

---

## **Introduction**

The examples in this directory serve as starting points for developing enterprise automation scripts. They demonstrate proper framework integration, common automation patterns, and best practices for production deployment.

### Purpose

These examples bridge the gap between framework documentation and practical implementation, providing working code that can be adapted for specific enterprise requirements.

### Scope

**What's Covered:**

- Basic template usage patterns
- Common automation scenarios
- Framework integration examples
- Best practice implementations

### Target Audience

**Primary Users:** DevOps engineers, automation developers, SRE professionals  
**Secondary Users:** System administrators, platform engineers  
**Background Assumed:** Basic understanding of bash scripting and enterprise automation concepts

### Overview

Examples progress from simple demonstrations to more complex scenarios, allowing users to understand framework capabilities incrementally.

---

## **Available Examples**

This section provides an overview of each example script and its intended learning objectives.

### Simple Example (`simple-example.sh`)

**Purpose:** Demonstrates basic framework usage for common file operations  
**Learning Objectives:** Framework integration, argument parsing, basic operations  
**Use Cases:** File backup, analysis, system information gathering

#### Key Features Demonstrated

| Feature | Implementation | Learning Value |
|---------|----------------|----------------|
| **Framework Integration** | Sources core framework modules | Foundation pattern for all scripts |
| **Argument Parsing** | Handles required and optional parameters | Standard parameter handling approach |
| **Input Validation** | Validates file existence and permissions | Security and reliability patterns |
| **Structured Operations** | Separate functions for each operation type | Code organization best practices |
| **Error Handling** | Uses framework error trapping | Robust failure management |

#### Usage Examples

```bash
# Basic file backup operation
./simple-example.sh --target-file /etc/hosts --operation backup

# File analysis with verbose output
./simple-example.sh --target-file /var/log/syslog --operation analyze --verbose

# System information gathering (dry run)
./simple-example.sh --target-file /dev/null --operation sysinfo --dry-run

# Custom backup directory
./simple-example.sh --target-file /etc/nginx/nginx.conf --operation backup \
                    --backup-dir /opt/backups
```

#### Code Organization

```bash
# Framework Integration Section
source "../framework/logging.sh"
source "../framework/security.sh" 
source "../framework/validation.sh"

# Operation-Specific Functions
backup_file()         # File backup with timestamp
analyze_file()        # File property analysis
gather_system_info()  # System information collection

# Standard Framework Patterns
usage()              # Help text and examples
parse_args()         # Argument validation
main()               # Primary execution flow
```

---

## **Example Usage Patterns**

### Development Workflow

#### Script Creation Process

1. **Copy Template Base:** Start with `simple-example.sh` as foundation
2. **Customize Variables:** Update script metadata and global variables
3. **Implement Operations:** Replace example functions with domain-specific logic
4. **Test Integration:** Verify framework integration and error handling
5. **Add Validation:** Implement appropriate input validation patterns

#### Adaptation Guidelines

```bash
# Replace example-specific variables
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Customize for your domain
OPERATION=""          # Replace with domain-specific operations
TARGET_FILE=""        # Replace with relevant parameters
BACKUP_DIR=""         # Add domain-specific configuration
```

### Framework Integration Patterns

#### Core Module Integration

```bash
# Standard framework sourcing pattern
for lib in "../framework/logging.sh" "../framework/security.sh" "../framework/validation.sh"; do
  if ! source "${SCRIPT_DIR}/${lib}"; then
    echo "FATAL: Could not source required library: ${lib}" >&2
    exit 1
  fi
done
```

#### Error Handling Integration

```bash
# Framework error trapping
trap 'on_err $LINENO "$BASH_COMMAND" $?' ERR
trap 'on_exit' EXIT

# Function-level error handling
validate_operation_input() {
  [[ -n "$1" ]] || die "Operation input cannot be empty"
  [[ -f "$1" ]] || die "Input file does not exist: $1"
}
```

### Common Operation Patterns

#### File Operations

```bash
# Safe file backup with validation
backup_file_safely() {
  local source="$1"
  local backup_dir="$2"
  
  # Validation
  [[ -f "$source" && -r "$source" ]] || die "Source file not accessible: $source"
  
  # Safe directory creation
  run mkdir -p "$backup_dir"
  
  # Timestamped backup
  local backup_name="$(basename "$source").backup.$(date +%Y%m%d_%H%M%S)"
  run cp "$source" "$backup_dir/$backup_name"
}
```

#### System Information Collection

```bash
# Safe system information gathering
collect_system_metrics() {
  log_info "Collecting system metrics"
  
  # Use safe command execution
  local hostname uptime disk_usage
  hostname=$(run hostname || echo "unknown")
  uptime=$(run uptime -p || echo "unknown")
  disk_usage=$(run df -h / | tail -1 | awk '{print $5}' || echo "unknown")
  
  log_info "Metrics collected: hostname=$hostname, uptime=$uptime, disk=$disk_usage"
}
```

---

## **Best Practices Demonstrated**

### Code Organization

**Function Structure:**

- Single responsibility principle
- Clear parameter validation
- Consistent error handling
- Structured logging integration

**Script Layout:**

- Standard header with metadata
- Framework integration section
- Global variable declarations
- Function definitions
- Main execution flow

### Security Practices

**Input Validation:**

```bash
# Validate all external inputs
validate_user_input() {
  local input="$1"
  local field_name="$2"
  
  [[ -n "$input" ]] || die "$field_name cannot be empty"
  [[ ${#input} -le 255 ]] || die "$field_name too long"
  
  # Additional validation as needed
  case "$field_name" in
    "file_path") [[ -f "$input" ]] || die "File does not exist: $input" ;;
    "operation") [[ "$input" =~ ^[a-zA-Z_]+$ ]] || die "Invalid operation format: $input" ;;
  esac
}
```

**Safe Command Execution:**

```bash
# Use framework run() function for all external commands
safe_operation() {
  local operation="$1"
  local target="$2"
  
  log_info "Executing safe operation: $operation on $target"
  run "$operation" "$target"
}
```

### Observability Integration

**Structured Logging:**

```bash
# Consistent logging patterns
operation_with_logging() {
  local operation_name="$1"
  
  log_info "Starting operation: $operation_name"
  log_debug "Operation details: param1=$param1, param2=$param2"
  
  # Operation execution
  if perform_operation; then
    log_info "Operation completed successfully: $operation_name"
  else
    log_error "Operation failed: $operation_name"
    return 1
  fi
}
```

---

## **Customization Guidelines**

### Adapting Examples for Specific Use Cases

#### Domain-Specific Modifications

1. **Update Script Metadata:**
   - Change script name, purpose, and usage documentation
   - Update version and repository information
   - Modify usage examples for domain context

2. **Customize Operations:**
   - Replace example operations with domain-specific functions
   - Add appropriate input validation for domain requirements
   - Implement business logic while maintaining framework patterns

3. **Extend Validation:**
   - Add domain-specific validation functions
   - Implement business rule validation
   - Integrate with external validation services if needed

#### Framework Extension Points

```bash
# Custom validation functions
validate_business_requirements() {
  local input="$1"
  
  # Add business-specific validation logic
  # Maintain framework error handling patterns
}

# Custom operation functions
perform_domain_operation() {
  local operation_params="$@"
  
  # Implement domain-specific logic
  # Use framework logging and error handling
  # Follow idempotent operation patterns
}
```

### Testing and Validation

#### Example Testing Process

```bash
# Test framework integration
./simple-example.sh --help                    # Verify usage output
./simple-example.sh --invalid-option          # Test error handling
./simple-example.sh --target-file /nonexistent --operation backup  # Test validation

# Test operations
./simple-example.sh --target-file /etc/hosts --operation analyze --dry-run
./simple-example.sh --target-file /etc/hosts --operation backup --verbose
```

---

## **Usage & Maintenance**

### Usage Guidelines

**Development Process:**

- Start with simple example as foundation
- Customize gradually while maintaining framework integration
- Test each modification thoroughly
- Document changes for team knowledge sharing

**Production Deployment:**

- Validate framework integration in non-production environment
- Test error handling and edge cases
- Verify logging output integrates with monitoring systems
- Implement appropriate security validations for production use

**Team Adoption:**

- Use examples as training materials for new team members
- Establish examples as coding standards for automation scripts
- Create domain-specific examples based on organizational needs

### Troubleshooting

| Issue | Symptoms | Resolution |
|-------|----------|------------|
| **Framework Loading Errors** | "FATAL: Could not source required library" | Verify framework files exist; check file permissions and paths |
| **Permission Denied** | Script execution fails with permission errors | Check script execute permissions; verify user access to target files |
| **Validation Failures** | Operations blocked by input validation | Review validation logic; ensure inputs meet framework requirements |
| **Logging Issues** | Missing or malformed log output | Verify LOG_LEVEL setting; check stderr redirection |

### Maintenance & Updates

**Example Evolution:**

- Update examples when framework capabilities are enhanced
- Add new examples for emerging automation patterns
- Maintain compatibility with framework version updates

**Documentation Maintenance:**

- Keep usage examples current with framework changes
- Update best practices based on production feedback
- Enhance examples based on community contributions

---

## **Advanced Example Patterns**

### Integration with Pattern Library

#### Security Pattern Integration

```bash
# Integrate security validation patterns
secure_file_operation() {
  local file_path="$1"
  local operation="$2"
  
  # Security validation
  validate_file_path "$file_path" "r"
  validate_no_shell_metacharacters "$file_path" "file path"
  validate_alphanumeric_safe "$operation" "operation"
  
  # Safe operation execution
  case "$operation" in
    backup) backup_file "$file_path" "$BACKUP_DIR" ;;
    analyze) analyze_file "$file_path" ;;
    *) die "Unknown operation: $operation" ;;
  esac
}
```

#### Observability Pattern Integration

```bash
# Structured logging integration
operation_with_observability() {
  local operation="$1"
  local start_time end_time duration
  
  start_time=$(date +%s)
  log_structured "INFO" "Operation started" \
    "operation_name" "$operation" \
    "start_timestamp" "$(date -u +%FT%TZ)"
  
  # Perform operation
  if perform_operation "$operation"; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    log_structured "INFO" "Operation completed" \
      "operation_name" "$operation" \
      "duration_seconds" "$duration" \
      "success" "true"
  else
    log_structured "ERROR" "Operation failed" \
      "operation_name" "$operation" \
      "success" "false"
    return 1
  fi
}
```

#### Idempotent Pattern Integration

```bash
# Idempotent operation implementation
idempotent_configuration() {
  local config_file="$1"
  local config_setting="$2"
  
  # Check if setting already exists
  if grep -qF "$config_setting" "$config_file"; then
    log_info "Configuration already present: $config_setting"
    return 0
  fi
  
  # Backup before modification
  backup_file "$config_file" "$BACKUP_DIR"
  
  # Add configuration
  echo "$config_setting" >> "$config_file"
  log_info "Configuration added: $config_setting"
}
```

### Error Recovery Patterns

#### Graceful Degradation

```bash
# Handle operation failures gracefully
robust_operation() {
  local primary_operation="$1"
  local fallback_operation="$2"
  
  log_info "Attempting primary operation: $primary_operation"
  
  if ! perform_operation "$primary_operation"; then
    log_warn "Primary operation failed, attempting fallback: $fallback_operation"
    
    if perform_operation "$fallback_operation"; then
      log_info "Fallback operation succeeded"
    else
      log_error "Both primary and fallback operations failed"
      return 1
    fi
  fi
}
```

---

## **Future Example Development**

### Planned Example Additions

**Short-term Roadmap:**

- Database operation examples
- Network service management examples
- Container orchestration examples
- Configuration management examples

**Long-term Vision:**

- AI agent integration examples
- Multi-cloud deployment examples
- Advanced monitoring integration examples
- Complex workflow orchestration examples

### Contributing Examples

**Contribution Guidelines:**

1. Follow existing example structure and naming conventions
2. Ensure comprehensive error handling and logging
3. Include thorough documentation and usage examples
4. Test examples in production-like environments
5. Submit examples with appropriate test cases

**Example Quality Standards:**

- Complete framework integration
- Production-ready error handling
- Comprehensive documentation
- Clear learning objectives
- Practical real-world applicability

---

## **References & Related Resources**

### Internal References

| Document Type | Title | Relationship | Link |
|---------------|-------|--------------|------|
| Framework Core | Enterprise Template | Base template for all examples | [enterprise-template.sh](../enterprise-template.sh) |
| Framework Modules | Core Framework | Foundation functionality | [framework/](../framework/) |
| Pattern Library | Implementation Patterns | Advanced usage patterns | [patterns/README.md](../../patterns/README.md) |

### External Resources

| Resource Type | Title | Description | Link |
|---------------|-------|-------------|------|
| Best Practices | Advanced Bash Scripting | Comprehensive bash techniques | [tldp.org/LDP/abs/html/](https://tldp.org/LDP/abs/html/) |
| Testing | Bash Testing Framework | Automated testing for bash scripts | [bats-core/bats-core](https://github.com/bats-core/bats-core) |
| Standards | Shell Style Guide | Google shell scripting standards | [google.github.io/styleguide/shellguide.html](https://google.github.io/styleguide/shellguide.html) |

---

## **Documentation Metadata**

### Change Log

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2025-09-20 | Initial examples directory documentation | VintageDon |

### Authorship & Collaboration

**Primary Author:** VintageDon ([GitHub Profile](https://github.com/vintagedon))  
**Production Validation:** All examples tested in Proxmox Astronomy Lab environment  
**Educational Review:** Examples validated for learning effectiveness and practical applicability

### Technical Notes

**Example Status:** All examples are production-ready and tested  
**Framework Compatibility:** Compatible with Enterprise AIOps Bash Framework v1.0  
**Update Policy:** Examples updated with framework enhancements and community feedback

*Document Version: 1.0 | Last Updated: 2025-09-20 | Status: Published*
