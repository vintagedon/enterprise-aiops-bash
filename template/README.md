<!--
---
title: "Enterprise Template System Documentation"
description: "Complete template system for enterprise bash automation with framework integration and production-ready patterns"
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
- "[Pattern Library](../patterns/README.md)"
- "[Plugin Architecture](../plugins/README.md)"
- "[Integration Guides](../integrations/README.md)"
---
-->

# **Enterprise Template System Documentation**

The template system provides the foundation for all enterprise bash automation scripts. It consists of a core framework, comprehensive template, and supporting examples that enable rapid development of production-ready automation scripts.

---

## **Introduction**

The template system represents the core of the Enterprise AIOps Bash Framework, providing a standardized foundation that ensures security, reliability, and observability across all automation scripts. It eliminates the need to build common functionality from scratch while maintaining enterprise-grade standards.

### Purpose

This template system enables rapid development of enterprise automation scripts by providing a battle-tested foundation with built-in security, error handling, logging, and operational controls.

### Scope

**What's Covered:**

- Core framework modules (logging, security, validation)
- Complete enterprise template for new scripts
- Example implementations and usage patterns
- Framework integration guidelines

### Target Audience

**Primary Users:** DevOps engineers, automation developers, SRE professionals  
**Secondary Users:** System administrators, platform engineers  
**Background Assumed:** Basic bash scripting knowledge, enterprise automation concepts

### Overview

The template system follows a layered architecture where core framework modules provide foundational capabilities, the enterprise template integrates these modules, and examples demonstrate practical usage patterns.

---

## **Template System Architecture**

This section describes the structure and organization of the template system.

### Directory Structure

```markdown
template/
├── README.md                    # This document - template system overview
├── enterprise-template.sh       # Complete template for new scripts
├── framework/                   # Core framework modules
│   ├── logging.sh              # Structured logging with JSON support
│   ├── security.sh             # Error handling and diagnostics
│   └── validation.sh           # Input validation and path safety
└── examples/                    # Implementation examples
    ├── simple-example.sh        # Basic usage demonstration
    └── README.md               # Examples documentation
```

### Component Relationships

```markdown
┌─────────────────────────────────────────────────────────┐
│                Enterprise Template                      │
│  ┌─────────────────────────────────────────────────────┤
│  │                Examples Layer                       │
│  │  ┌─────────────────────────────────────────────────┤
│  │  │             Framework Core                      │
│  │  │  ┌─────────────┬─────────────┬─────────────────┤
│  │  │  │ logging.sh  │ security.sh │  validation.sh  │
│  │  │  └─────────────┴─────────────┴─────────────────┤
│  │  └─────────────────────────────────────────────────┤
│  └─────────────────────────────────────────────────────┤
└─────────────────────────────────────────────────────────┘
```

---

## **Core Framework Modules**

This section provides an overview of each framework module and its capabilities.

### Logging Framework (`framework/logging.sh`)

**Purpose:** Structured logging with configurable output formats and log levels  
**Key Features:** JSON output support, log level filtering, printf-safe formatting  
**Enterprise Benefits:** Machine-readable logs, observability platform integration

#### Core Functions

| Function | Purpose | Usage Pattern |
|----------|---------|---------------|
| `log_debug()` | Debug-level logging | Development and troubleshooting |
| `log_info()` | Informational logging | Standard operational events |
| `log_warn()` | Warning-level logging | Non-fatal issues and advisories |
| `log_error()` | Error-level logging | Serious issues requiring attention |
| `die()` | Fatal error with exit | Unrecoverable error conditions |

#### Configuration Options

```bash
# Environment variables for logging configuration
LOG_FORMAT="text"     # or "json" for structured output
LOG_LEVEL=20         # 10=DEBUG, 20=INFO, 30=WARN, 40=ERROR
VERBOSE=0            # Enable debug logging
```

#### Usage Examples

```bash
# Basic logging
log_info "Operation completed successfully"
log_warn "Resource usage is high"
log_error "Connection failed"

# Conditional debug logging
log_debug "Processing item: $item_name"  # Only shown if VERBOSE=1

# Fatal error handling
[[ -f "$config_file" ]] || die "Configuration file not found: $config_file"
```

### Security Framework (`framework/security.sh`)

**Purpose:** Error handling, exit traps, and diagnostic output for debugging  
**Key Features:** Context-rich error reporting, stack traces, machine-readable error events  
**Enterprise Benefits:** Rapid incident resolution, comprehensive failure diagnostics

#### Core Functions

| Function | Purpose | Integration Point |
|----------|---------|-------------------|
| `on_err()` | ERR trap handler | Automatic error context capture |
| `on_exit()` | EXIT trap handler | Cleanup and final status logging |

#### Error Context Capture

```bash
# Automatic error context includes:
# - Line number where error occurred
# - Command that failed
# - Exit code of failed command
# - Function call stack trace
# - Timestamp and script identification

# Example error output:
# [2025-09-20T14:30:45Z] [ERROR] Failed at line 42: cp /nonexistent /tmp (exit 1)
```

#### Machine-Readable Error Events

```bash
# JSON error output (when LOG_FORMAT=json):
{
  "timestamp": "2025-09-20T14:30:45Z",
  "level": "ERROR",
  "event": "script_error",
  "line": 42,
  "command": "cp /nonexistent /tmp",
  "exit_code": 1
}
```

### Validation Framework (`framework/validation.sh`)

**Purpose:** Input validation, dependency checking, and security validation  
**Key Features:** Command validation, hostname checking, path traversal prevention  
**Enterprise Benefits:** Security hardening, safe automation, dependency management

#### Core Functions

| Function | Purpose | Security Benefit |
|----------|---------|------------------|
| `require_cmd()` | Verify command availability | Dependency validation |
| `validate_hostname()` | RFC-compliant hostname validation | Network security |
| `ensure_under_dir()` | Path traversal prevention | File system security |

#### Usage Examples

```bash
# Dependency validation
require_cmd jq awk curl

# Hostname validation
validate_hostname "$target_server"

# Path security validation
ensure_under_dir "/var/app" "$user_provided_path"
```

---

## **Enterprise Template (`enterprise-template.sh`)**

The enterprise template provides a complete, production-ready foundation for new automation scripts.

### Template Structure

#### Header Section

```bash
#!/usr/bin/env bash
# shellcheck shell=bash
#--------------------------------------------------------------------------------------------------
# SCRIPT:       (Your Script Name)
# PURPOSE:      (Purpose of your script)
# VERSION:      1.0.0
# REPOSITORY:   https://github.com/vintagedon/enterprise-aiops-bash
# LICENSE:      MIT
# AUTHOR:       (Your Name)
# USAGE:        (Usage examples)
#--------------------------------------------------------------------------------------------------
```

#### Strict Mode and Security

```bash
# Strict mode enforcement
set -Eeuo pipefail    # Error propagation and strict execution
IFS=$'\n\t'          # Secure word splitting
umask 027            # Restrictive file permissions
```

#### Framework Integration

```bash
# Defensive framework loading
for lib in "framework/logging.sh" "framework/security.sh" "framework/validation.sh"; do
  if ! source "${SCRIPT_DIR}/${lib}"; then
    echo "FATAL: Could not source required library: ${lib}" >&2
    exit 1
  fi
done

# Error handling setup
trap 'on_err $LINENO "$BASH_COMMAND" $?' ERR
trap 'on_exit' EXIT
```

#### Operational Controls

```bash
# Built-in operational safety
VERBOSE=0            # Debug logging control
DRY_RUN=0           # Preview mode
READ_ONLY=0         # Read-only mode for diagnostics

# Safe command execution wrapper
run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log_info "DRY RUN: $*"
  else
    log_info "RUN: $*"
    "$@"
  fi
}
```

### Template Customization Points

#### Script Metadata

1. **Update Header:** Script name, purpose, author, usage examples
2. **Version Information:** Version number and repository details
3. **License:** Appropriate license for your organization

#### Global Variables

```bash
# Replace template variables with script-specific ones
INPUT_FILE=""        # Example: replace with domain-specific parameters
OPERATION=""         # Example: define operations for your use case
CONFIG_FILE=""       # Example: configuration file paths
```

#### Argument Parsing

```bash
# Customize parse_args() function for script-specific options
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --your-option)   YOUR_VARIABLE="$2"; shift 2 ;;
      --another-opt)   ANOTHER_VAR="$2"; shift 2 ;;
      # Add script-specific options here
    esac
  done
}
```

#### Main Logic

```bash
# Replace example logic with script-specific implementation
main() {
  parse_args "$@"
  
  # Pre-flight checks
  require_cmd your_required_commands
  
  # Your script logic here
  perform_your_operations
  
  log_info "Script completed successfully"
}
```

---

## **Implementation Examples**

### Simple Example (`examples/simple-example.sh`)

**Purpose:** Demonstrates basic framework usage for common operations  
**Learning Objectives:** Framework integration, argument parsing, operational patterns  
**Use Cases:** File operations, system information gathering, basic automation

#### Key Demonstrations

- **Framework Integration:** Proper sourcing and initialization
- **Argument Parsing:** Standard parameter handling patterns
- **Input Validation:** File existence and permission checking
- **Operational Safety:** Dry-run and verbose modes
- **Error Handling:** Framework error management integration

#### Usage Scenarios

```bash
# File backup operation
./simple-example.sh --target-file /etc/hosts --operation backup

# File analysis with verbose output
./simple-example.sh --target-file /var/log/syslog --operation analyze --verbose

# System information gathering
./simple-example.sh --target-file /dev/null --operation sysinfo --dry-run
```

[**Detailed Examples Documentation →**](examples/README.md)

---

## **Development Workflow**

### Script Creation Process

#### 1. Template Initialization

```bash
# Copy template to new script
cp template/enterprise-template.sh new-automation-script.sh
chmod +x new-automation-script.sh
```

#### 2. Customization Steps

1. **Update Header:** Script metadata and documentation
2. **Define Variables:** Script-specific global variables
3. **Customize Arguments:** Modify parse_args() for required parameters
4. **Implement Logic:** Replace example logic with domain-specific operations
5. **Add Validation:** Implement appropriate input validation
6. **Test Integration:** Verify framework integration and error handling

#### 3. Validation Checklist

- [ ] Header documentation is complete and accurate
- [ ] Framework modules are properly sourced
- [ ] Error traps are configured
- [ ] Argument parsing handles all required parameters
- [ ] Input validation uses appropriate security patterns
- [ ] Main logic integrates with framework logging
- [ ] Usage function provides clear examples
- [ ] Script passes shellcheck validation

### Testing Methodology

#### Unit Testing Approach

```bash
# Test framework integration
test_framework_integration() {
  # Test logging functions
  log_info "Testing log output"
  log_debug "Debug message (should only show with VERBOSE=1)"
  
  # Test error handling
  false || log_error "Expected error handled correctly"
  
  # Test validation functions
  require_cmd bash
  
  echo "Framework integration test completed"
}

# Test argument parsing
test_argument_parsing() {
  # Test with valid arguments
  parse_args --target-file "/etc/hosts" --operation "backup"
  
  # Verify variables are set correctly
  [[ "$TARGET_FILE" == "/etc/hosts" ]] || die "Argument parsing failed"
  [[ "$OPERATION" == "backup" ]] || die "Operation parsing failed"
  
  echo "Argument parsing test completed"
}
```

#### Integration Testing

```bash
# End-to-end functionality test
test_end_to_end() {
  local test_file="/tmp/test-file-$$"
  echo "test content" > "$test_file"
  
  # Test actual script functionality
  ./your-script.sh --target-file "$test_file" --operation "backup" --dry-run
  
  # Verify expected behavior
  # Add specific validation for your script's functionality
  
  # Cleanup
  rm -f "$test_file"
  
  echo "End-to-end test completed"
}
```

---

## **Integration Patterns**

### Pattern Library Integration

#### Security Pattern Integration

```bash
# Integrate security validation patterns
secure_operation() {
  local input_file="$1"
  local operation="$2"
  
  # Use security patterns from pattern library
  validate_file_path "$input_file" "r"
  validate_no_shell_metacharacters "$input_file" "input file"
  validate_alphanumeric_safe "$operation" "operation"
  
  # Perform operation with security context
  log_info "Performing secure operation: $operation on $input_file"
  run "$operation" "$input_file"
}
```

#### Observability Pattern Integration

```bash
# Integrate structured logging patterns
operation_with_observability() {
  local operation_name="$1"
  local start_time end_time duration
  
  start_time=$(date +%s)
  log_structured "INFO" "Operation started" \
    "operation_name" "$operation_name" \
    "script_name" "$SCRIPT_NAME"
  
  # Perform operation
  if perform_operation "$operation_name"; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    log_structured "INFO" "Operation completed" \
      "operation_name" "$operation_name" \
      "duration_seconds" "$duration" \
      "success" "true"
  else
    log_structured "ERROR" "Operation failed" \
      "operation_name" "$operation_name" \
      "success" "false"
    return 1
  fi
}
```

### Plugin System Integration

```bash
# Plugin integration example
integrate_plugins() {
  local required_plugins=("secrets/vault" "monitoring/prometheus")
  
  for plugin in "${required_plugins[@]}"; do
    if [[ -f "plugins/${plugin}.sh" ]]; then
      source "plugins/${plugin}.sh"
      log_info "Plugin loaded: $plugin"
    else
      log_warn "Plugin not found: $plugin"
    fi
  done
}
```

---

## **Production Deployment Guidelines**

### Environment-Specific Configuration

#### Development Environment

```bash
# Development-specific template configuration
ENVIRONMENT="development"
LOG_LEVEL=10          # Debug logging enabled
DRY_RUN=1            # Safe preview mode by default
VERBOSE=1            # Detailed output for debugging
```

#### Production Environment

```bash
# Production-specific template configuration
ENVIRONMENT="production"
LOG_LEVEL=20         # Info level logging
LOG_FORMAT="json"    # Structured logging for aggregation
READ_ONLY=0          # Full operational capability
AUDIT_LOGGING=1      # Enhanced audit trail
```

### Security Hardening

#### Production Security Configuration

```bash
# Enhanced security for production deployment
STRICT_VALIDATION=1   # Enable additional input validation
SECURITY_LOGGING=1    # Log all security events
COMMAND_ALLOWLIST=1   # Enable command allow-listing
FILE_INTEGRITY=1      # Verify file integrity before operations
```

### Monitoring Integration

#### Observability Configuration

```bash
# Production monitoring integration
METRICS_ENABLED=1     # Enable performance metrics
TRACE_ENABLED=1       # Enable distributed tracing
ALERT_THRESHOLD=30    # Alert on operations taking >30 seconds
LOG_AGGREGATION=1     # Send logs to central aggregation
```

---

## **Troubleshooting & Support**

### Common Template Issues

| Issue | Symptoms | Resolution |
|-------|----------|------------|
| **Framework Loading Failed** | "FATAL: Could not source required library" | Verify framework files exist and are readable |
| **Shellcheck Errors** | Script validation warnings | Review and fix shell scripting best practices |
| **Permission Denied** | Cannot execute operations | Check file permissions and user access rights |
| **Argument Parsing Errors** | Unexpected parameter behavior | Validate parse_args() function logic |

### Debug Commands

```bash
# Template debugging utilities
debug_template() {
  log_info "Template debugging information:"
  log_info "  Script: $SCRIPT_NAME"
  log_info "  Directory: $SCRIPT_DIR"
  log_info "  Start time: $START_TS"
  log_info "  Log level: $LOG_LEVEL"
  log_info "  Dry run: $DRY_RUN"
  log_info "  Verbose: $VERBOSE"
}

# Framework module verification
verify_framework() {
  local modules=("logging.sh" "security.sh" "validation.sh")
  
  for module in "${modules[@]}"; do
    local module_path="${SCRIPT_DIR}/framework/${module}"
    if [[ -f "$module_path" && -r "$module_path" ]]; then
      log_info "Framework module OK: $module"
    else
      log_error "Framework module FAILED: $module"
    fi
  done
}
```

---

## **References & Related Resources**

### Internal References

| Document Type | Title | Relationship | Link |
|---------------|-------|--------------|------|
| Pattern Library | Implementation Patterns | Advanced template usage | [../patterns/README.md](../patterns/README.md) |
| Plugin System | Plugin Architecture | Template extension | [../plugins/README.md](../plugins/README.md) |
| Integration Guides | Platform Integration | Template deployment | [../integrations/README.md](../integrations/README.md) |

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
| 1.0 | 2025-09-20 | Initial template system documentation | VintageDon |

### Authorship & Collaboration

**Primary Author:** VintageDon ([GitHub Profile](https://github.com/vintagedon))  
**Production Validation:** All components tested in Proxmox Astronomy Lab environment  
**Framework Review:** Templates validated for enterprise automation workflows

### Technical Notes

**Template Status:** Production-ready and battle-tested  
**Framework Version:** Enterprise AIOps Bash Framework v1.0  
**Compatibility:** Tested across multiple enterprise environments

*Document Version: 1.0 | Last Updated: 2025-09-20 | Status: Published*
