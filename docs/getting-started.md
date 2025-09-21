<!--
---
title: "Getting Started with Enterprise AIOps Bash Framework"
description: "Zero-to-productive user guide for implementing enterprise-grade bash automation with comprehensive framework capabilities"
author: "VintageDon - https://github.com/vintagedon"
date: "2025-09-20"
version: "1.0"
status: "Published"
tags:
- type: how-to-guide
- domain: enterprise-automation
- tech: bash
- audience: devops-engineers
related_documents:
- "[Enterprise Template](../template/enterprise-template.sh)"
- "[Pattern Library](../patterns/README.md)"
- "[Integration Guides](../integrations/README.md)"
---
-->

# **Getting Started with Enterprise AIOps Bash Framework**

This guide provides a complete path from initial setup to productive enterprise automation using the Enterprise AIOps Bash Framework. Follow this guide to quickly implement enterprise-grade bash automation with built-in security, observability, and operational controls.

---

## **Introduction**

The Enterprise AIOps Bash Framework provides production-ready foundations for enterprise automation scripts. This getting started guide walks through installation, basic usage, and initial implementation to get you productive quickly while following enterprise best practices.

### What You'll Learn

- Framework installation and initial setup
- Creating your first enterprise automation script
- Implementing security and observability patterns
- Integrating with enterprise tools and systems
- Best practices for production deployment

### Prerequisites

**System Requirements:**

- Linux or macOS environment
- Bash 4.0 or newer
- Basic command-line tools (jq, curl, git)
- Text editor or IDE

**Knowledge Prerequisites:**

- Basic bash scripting experience
- Understanding of enterprise automation concepts
- Familiarity with JSON and structured logging

### Time Investment

**Initial Setup:** 15-30 minutes  
**First Script:** 30-45 minutes  
**Advanced Features:** 1-2 hours  
**Production Deployment:** 2-4 hours

---

## **Quick Start Installation**

### Step 1: Clone the Repository

```bash
# Clone the framework repository
git clone https://github.com/vintagedon/enterprise-aiops-bash.git
cd enterprise-aiops-bash

# Verify repository structure
ls -la
```

**Expected Directory Structure:**

```markdown
enterprise-aiops-bash/
├── README.md
├── template/
│   ├── enterprise-template.sh
│   ├── framework/
│   └── examples/
├── patterns/
├── plugins/
├── integrations/
└── docs/
```

### Step 2: Verify Dependencies

```bash
# Check required dependencies
./scripts/check-dependencies.sh

# Or manually verify:
command -v bash && echo "Bash: OK" || echo "Bash: MISSING"
command -v jq && echo "jq: OK" || echo "jq: MISSING"
command -v git && echo "Git: OK" || echo "Git: MISSING"
```

**Install Missing Dependencies:**

**Ubuntu/Debian:**

```bash
sudo apt update
sudo apt install jq curl git
```

**RHEL/CentOS:**

```bash
sudo yum install jq curl git
# or for newer versions:
sudo dnf install jq curl git
```

**macOS:**

```bash
brew install jq curl git
```

### Step 3: Test Basic Framework

```bash
# Test the simple example
cd template/examples
./simple-example.sh --help

# Run a basic test
./simple-example.sh --target-file /etc/hosts --operation analyze --verbose
```

**Expected Output:**

```bash
[2025-09-20T14:30:45Z] [INFO] Starting simple-example.sh
[2025-09-20T14:30:45Z] [INFO] Starting file analysis operation
[2025-09-20T14:30:45Z] [INFO] File analysis results:
[2025-09-20T14:30:45Z] [INFO]   File: /etc/hosts
[2025-09-20T14:30:45Z] [INFO]   Size: 1024 bytes
[2025-09-20T14:30:45Z] [INFO] simple-example.sh completed successfully
```

---

## **Creating Your First Script**

### Step 1: Copy the Template

```bash
# Navigate to your project directory
cd /path/to/your/automation/scripts

# Copy the enterprise template
cp /path/to/enterprise-aiops-bash/template/enterprise-template.sh my-automation-script.sh

# Make it executable
chmod +x my-automation-script.sh
```

### Step 2: Customize Script Metadata

Edit the script header to match your requirements:

```bash
#!/usr/bin/env bash
# shellcheck shell=bash
#--------------------------------------------------------------------------------------------------
# SCRIPT:       my-automation-script.sh
# PURPOSE:      Automated system maintenance and monitoring tasks
# VERSION:      1.0.0
# REPOSITORY:   https://github.com/your-org/automation-scripts
# LICENSE:      MIT
# AUTHOR:       Your Name
# USAGE:        ./my-automation-script.sh --task cleanup --environment production
#
# NOTES:
#   This script performs automated system maintenance tasks including log cleanup,
#   service health checks, and system monitoring with enterprise-grade logging.
#--------------------------------------------------------------------------------------------------
```

### Step 3: Define Script Variables

Update the global variables section:

```bash
# --- Script-Specific Variables ---
VERBOSE=0
DRY_RUN=0
READ_ONLY=0

# Your script-specific variables
TASK=""
ENVIRONMENT=""
LOG_RETENTION_DAYS=7
SERVICE_LIST="nginx apache2 mysql"
DISK_THRESHOLD=80
```

### Step 4: Customize Argument Parsing

Modify the `parse_args()` function:

```bash
parse_args() {
  [[ $# -eq 0 ]] && usage 1
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task)         [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; TASK="$2"; shift 2 ;;
      --environment)  [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; ENVIRONMENT="$2"; shift 2 ;;
      --retention)    [[ -n "${2:-}" ]] || die "Option '$1' requires an argument."; LOG_RETENTION_DAYS="$2"; shift 2 ;;
      -d|--dry-run)   DRY_RUN=1; shift ;;
      -v|--verbose)   VERBOSE=1; LOG_LEVEL=10; shift ;;
      -h|--help)      usage 0 ;;
      --) shift; break ;;
      -*) die "Unknown option: $1" ;;
      *)  break ;;
    esac
  done
}
```

### Step 5: Implement Your Business Logic

Replace the template's example logic with your functionality:

```bash
# Your custom functions
perform_log_cleanup() {
  local log_dir="$1"
  local retention_days="$2"
  
  log_info "Starting log cleanup: $log_dir (retain $retention_days days)"
  
  # Validate inputs
  [[ -d "$log_dir" ]] || die "Log directory not found: $log_dir"
  [[ "$retention_days" =~ ^[0-9]+$ ]] || die "Invalid retention days: $retention_days"
  
  # Find and clean old logs
  local old_logs
  old_logs=$(find "$log_dir" -name "*.log" -type f -mtime +"$retention_days" | wc -l)
  
  if [[ "$old_logs" -gt 0 ]]; then
    log_info "Found $old_logs old log files to clean"
    run find "$log_dir" -name "*.log" -type f -mtime +"$retention_days" -delete
  else
    log_info "No old log files found"
  fi
}

check_service_health() {
  local service_name="$1"
  
  log_info "Checking service health: $service_name"
  
  if systemctl is-active --quiet "$service_name"; then
    log_info "Service healthy: $service_name"
    return 0
  else
    log_warn "Service unhealthy: $service_name"
    return 1
  fi
}

# Main logic implementation
main() {
  parse_args "$@"
  
  # Validate required parameters
  [[ -n "$TASK" ]] || { log_error "Task is required."; usage 1; }
  [[ -n "$ENVIRONMENT" ]] || { log_error "Environment is required."; usage 1; }
  
  log_info "Starting automation task: $TASK in $ENVIRONMENT"
  
  case "$TASK" in
    cleanup)
      perform_log_cleanup "/var/log" "$LOG_RETENTION_DAYS"
      ;;
    health-check)
      local failed_services=0
      for service in $SERVICE_LIST; do
        if ! check_service_health "$service"; then
          ((failed_services++))
        fi
      done
      
      if [[ "$failed_services" -gt 0 ]]; then
        log_warn "$failed_services services are unhealthy"
        exit 1
      fi
      ;;
    *)
      die "Unknown task: $TASK (use cleanup or health-check)"
      ;;
  esac
  
  log_info "Automation task completed successfully"
}
```

### Step 6: Update Usage Documentation

```bash
usage() {
  local code="${1:-0}"
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS] --task <task> --environment <env>

Automated system maintenance and monitoring tasks.

Required Options:
  --task <task>         Task to perform: cleanup, health-check
  --environment <env>   Environment: development, staging, production

Optional Options:
  --retention <days>    Log retention days (default: 7)
  -d, --dry-run         Show actions without executing
  -v, --verbose         Enable verbose (debug) logging
  -h, --help            Show this help

Examples:
  $SCRIPT_NAME --task cleanup --environment production --retention 30
  $SCRIPT_NAME --task health-check --environment staging --verbose
  $SCRIPT_NAME --task cleanup --environment development --dry-run

This script provides:
  - Enterprise-grade logging and error handling
  - Comprehensive input validation
  - Safe execution controls (dry-run, read-only)
  - Integration with enterprise monitoring systems
EOF
  exit "$code"
}
```

---

## **Testing Your Script**

### Step 1: Basic Functionality Test

```bash
# Test help output
./my-automation-script.sh --help

# Test argument validation
./my-automation-script.sh --task invalid-task --environment test
# Expected: Error message about unknown task

# Test dry-run mode
./my-automation-script.sh --task cleanup --environment development --dry-run --verbose
```

### Step 2: Validate Framework Integration

```bash
# Test logging functionality
./my-automation-script.sh --task health-check --environment development --verbose

# Test error handling (intentional failure)
./my-automation-script.sh --task cleanup --environment production
# Without required directory - should fail gracefully

# Test security validation
./my-automation-script.sh --task "; rm -rf /" --environment test
# Expected: Security validation error
```

### Step 3: Production Readiness Check

```bash
# Shellcheck validation
shellcheck my-automation-script.sh

# Framework integration check
bash -n my-automation-script.sh  # Syntax check

# Dependency validation
./my-automation-script.sh --help | grep -q "Usage:" && echo "Help: OK"
```

---

## **Implementing Security Patterns**

### Step 1: Add Input Validation

```bash
# Add to your script after sourcing framework
validate_environment() {
  local env="$1"
  
  case "$env" in
    development|staging|production) ;;
    *) die "Invalid environment: $env (use development, staging, or production)" ;;
  esac
  
  log_debug "Environment validation passed: $env"
}

validate_task_parameters() {
  local task="$1"
  
  # Use framework security patterns
  validate_alphanumeric_safe "$task" "task"
  
  case "$task" in
    cleanup|health-check|monitor) ;;
    *) die "Invalid task: $task" ;;
  esac
  
  log_debug "Task validation passed: $task"
}

# Add validation calls to main()
main() {
  parse_args "$@"
  
  # Enhanced validation
  [[ -n "$TASK" ]] || { log_error "Task is required."; usage 1; }
  [[ -n "$ENVIRONMENT" ]] || { log_error "Environment is required."; usage 1; }
  
  validate_task_parameters "$TASK"
  validate_environment "$ENVIRONMENT"
  
  # Continue with existing logic...
}
```

### Step 2: Implement Access Controls

```bash
# Add role-based access control
check_user_permissions() {
  local environment="$1"
  local task="$2"
  local user="${USER:-unknown}"
  
  log_info "Checking permissions: $user -> $task on $environment"
  
  case "$environment" in
    production)
      # Production requires special permissions
      if ! groups "$user" 2>/dev/null | grep -q "production-ops\|senior-engineers"; then
        die "Insufficient permissions for production operations"
      fi
      ;;
    staging)
      if ! groups "$user" 2>/dev/null | grep -q "engineers\|qa-team"; then
        die "Insufficient permissions for staging operations"
      fi
      ;;
    development)
      # Developers can access development environment
      ;;
  esac
  
  log_debug "Permission check passed"
}
```

---

## **Adding Observability Features**

### Step 1: Structured Logging

```bash
# Enable JSON logging for production
if [[ "$ENVIRONMENT" == "production" ]]; then
  export LOG_FORMAT="json"
fi

# Add structured logging to your functions
perform_log_cleanup() {
  local log_dir="$1"
  local retention_days="$2"
  local start_time end_time duration files_cleaned
  
  start_time=$(date +%s)
  
  log_structured "INFO" "Log cleanup started" \
    "log_directory" "$log_dir" \
    "retention_days" "$retention_days" \
    "operation" "cleanup"
  
  # Perform cleanup operations...
  files_cleaned=$(find "$log_dir" -name "*.log" -type f -mtime +"$retention_days" | wc -l)
  
  if [[ "$files_cleaned" -gt 0 ]]; then
    run find "$log_dir" -name "*.log" -type f -mtime +"$retention_days" -delete
  fi
  
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  
  log_structured "INFO" "Log cleanup completed" \
    "log_directory" "$log_dir" \
    "files_cleaned" "$files_cleaned" \
    "duration_seconds" "$duration" \
    "operation" "cleanup"
}
```

### Step 2: Performance Metrics

```bash
# Add metrics collection
collect_performance_metrics() {
  local operation="$1"
  local duration="$2"
  local items_processed="$3"
  local success_status="$4"
  
  # Export metrics for Prometheus
  cat >> "/var/lib/node_exporter/textfile_collector/automation_metrics.prom" << EOF
# Automation script metrics
automation_operation_duration_seconds{script="$(basename "$0")",operation="$operation",environment="$ENVIRONMENT"} $duration
automation_items_processed_total{script="$(basename "$0")",operation="$operation",environment="$ENVIRONMENT"} $items_processed
automation_operation_status{script="$(basename "$0")",operation="$operation",environment="$ENVIRONMENT",status="$success_status"} 1
automation_last_execution_timestamp{script="$(basename "$0")",environment="$ENVIRONMENT"} $(date +%s)
EOF
  
  log_debug "Performance metrics collected: $operation"
}
```

---

## **Integrating with Enterprise Tools**

### Step 1: Add Secret Management

```bash
# Source secret management plugin
if [[ -f "../plugins/secrets/vault.sh" ]]; then
  source "../plugins/secrets/vault.sh"
  
  # Get credentials from Vault
  get_database_credentials() {
    local environment="$1"
    
    DB_USER=$(vault_get_secret "database/$environment" "username")
    DB_PASS=$(vault_get_secret "database/$environment" "password")
    
    log_info "Database credentials retrieved from Vault"
  }
fi
```

### Step 2: Add Configuration Management Integration

```bash
# Integration with Ansible for configuration tasks
execute_configuration_task() {
  local playbook="$1"
  local inventory="$2"
  
  log_info "Executing configuration task: $playbook"
  
  if [[ -f "../integrations/ansible/playbook-wrapper.sh" ]]; then
    ../integrations/ansible/playbook-wrapper.sh \
      --playbook "$playbook" \
      --inventory "$inventory" \
      --extra-vars "environment=$ENVIRONMENT"
  else
    log_warn "Ansible integration not available, skipping configuration task"
  fi
}
```

### Step 3: Add Monitoring Integration

```bash
# Send alerts to monitoring system
send_alert() {
  local severity="$1"
  local message="$2"
  local alert_endpoint="${ALERT_WEBHOOK_URL:-}"
  
  if [[ -n "$alert_endpoint" ]]; then
    local alert_payload
    alert_payload=$(jq -n \
      --arg severity "$severity" \
      --arg message "$message" \
      --arg script "$(basename "$0")" \
      --arg environment "$ENVIRONMENT" \
      --arg timestamp "$(date -u +%FT%TZ)" \
      '{
        severity: $severity,
        message: $message,
        source: $script,
        environment: $environment,
        timestamp: $timestamp
      }')
    
    curl -s -X POST "$alert_endpoint" \
      -H "Content-Type: application/json" \
      -d "$alert_payload" || log_warn "Failed to send alert"
  fi
}
```

---

## **Production Deployment**

### Step 1: Environment Configuration

Create environment-specific configuration files:

**development.conf:**

```bash
#!/usr/bin/env bash
# Development environment configuration

export ENVIRONMENT="development"
export LOG_LEVEL=10  # Debug logging
export DRY_RUN=1     # Safe by default
export ALERT_WEBHOOK_URL=""  # No alerts in dev
export LOG_RETENTION_DAYS=3
```

**production.conf:**

```bash
#!/usr/bin/env bash
# Production environment configuration

export ENVIRONMENT="production"
export LOG_LEVEL=20  # Info logging
export LOG_FORMAT="json"  # Structured logging
export DRY_RUN=0     # Live operations
export ALERT_WEBHOOK_URL="https://monitoring.company.com/webhook"
export LOG_RETENTION_DAYS=30
```

### Step 2: Deployment Script

```bash
#!/usr/bin/env bash
# deploy-automation.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_ENV="${1:-development}"
DEPLOYMENT_DIR="/opt/automation"

case "$TARGET_ENV" in
  development)
    CONFIG_FILE="development.conf"
    ;;
  production)
    CONFIG_FILE="production.conf"
    # Additional production checks
    if [[ "$(whoami)" != "automation" ]]; then
      echo "Production deployment must run as automation user"
      exit 1
    fi
    ;;
  *)
    echo "Unknown environment: $TARGET_ENV"
    exit 1
    ;;
esac

# Deploy script and configuration
sudo mkdir -p "$DEPLOYMENT_DIR"
sudo cp my-automation-script.sh "$DEPLOYMENT_DIR/"
sudo cp "$CONFIG_FILE" "$DEPLOYMENT_DIR/config.sh"
sudo chmod +x "$DEPLOYMENT_DIR/my-automation-script.sh"
sudo chown -R automation:automation "$DEPLOYMENT_DIR"

echo "Deployment completed: $TARGET_ENV"
```

### Step 3: Cron Integration

```bash
# Add to crontab for scheduled execution
# Edit with: crontab -e

# Daily log cleanup at 2 AM
0 2 * * * /opt/automation/my-automation-script.sh --task cleanup --environment production >> /var/log/automation.log 2>&1

# Health checks every 15 minutes
*/15 * * * * /opt/automation/my-automation-script.sh --task health-check --environment production >> /var/log/automation.log 2>&1
```

### Step 4: Log Rotation Configuration

```bash
# Create /etc/logrotate.d/automation-scripts
/var/log/automation.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0644 automation automation
    postrotate
        # Send log rotation signal if needed
        /bin/kill -HUP $(cat /var/run/rsyslogd.pid 2>/dev/null) 2>/dev/null || true
    endscript
}
```

---

## **Advanced Configuration**

### Plugin Integration

```bash
# Load multiple plugins based on environment
load_environment_plugins() {
  local environment="$1"
  local plugin_dir="../plugins"
  
  case "$environment" in
    production)
      # Load secret management for production
      source "$plugin_dir/secrets/vault.sh"
      
      # Initialize Vault authentication
      vault_authenticate aws
      ;;
    development)
      # Use environment files in development
      source "$plugin_dir/secrets/env-file.sh"
      ENV_FILE_PATH=".env.development"
      load_env_file
      ;;
  esac
}
```

### Error Recovery Implementation

```bash
# Add retry logic for resilient operations
execute_with_retry() {
  local max_attempts="$1"
  local delay="$2"
  shift 2
  local command=("$@")
  
  local attempt=1
  
  while [[ "$attempt" -le "$max_attempts" ]]; do
    log_info "Attempt $attempt/$max_attempts: ${command[*]}"
    
    if "${command[@]}"; then
      log_info "Command succeeded on attempt $attempt"
      return 0
    else
      log_warn "Command failed on attempt $attempt"
      
      if [[ "$attempt" -lt "$max_attempts" ]]; then
        log_info "Retrying in $delay seconds..."
        sleep "$delay"
        ((attempt++))
      else
        log_error "All retry attempts failed"
        return 1
      fi
    fi
  done
}
```

---

## **Next Steps**

### Immediate Actions

1. **Complete Your First Script:** Follow this guide to create a working automation script
2. **Test Thoroughly:** Validate all functionality in a safe environment
3. **Deploy Gradually:** Start with development, then staging, finally production
4. **Monitor Results:** Watch logs and metrics for successful operation

### Learning Path

1. **Study Pattern Library:** Explore advanced patterns for your use cases
2. **Review Integrations:** Learn about tool integrations relevant to your environment
3. **Security Deep Dive:** Understand enterprise security implementation
4. **Observability Mastery:** Master structured logging and metrics collection

### Community Resources

- **GitHub Issues:** Report problems or request features
- **Documentation:** Comprehensive guides for advanced topics
- **Examples Repository:** Additional script examples and use cases
- **Best Practices:** Community-contributed patterns and solutions

### Production Readiness Checklist

- [ ] Script passes all validation tests
- [ ] Security patterns are properly implemented
- [ ] Logging provides adequate operational visibility
- [ ] Error handling covers all failure scenarios
- [ ] Performance monitoring is configured
- [ ] Deployment process is documented and tested
- [ ] Backup and recovery procedures are established
- [ ] Team training is completed

---

## **Troubleshooting Common Issues**

### Framework Loading Problems

**Issue:** "FATAL: Could not source required library"
**Solution:**

```bash
# Check file paths and permissions
ls -la template/framework/
# Ensure all .sh files are present and readable

# Verify script directory detection
echo "SCRIPT_DIR: $SCRIPT_DIR"
```

### Permission Errors

**Issue:** "Permission denied" during execution
**Solution:**

```bash
# Check script permissions
chmod +x my-automation-script.sh

# Verify user permissions for target operations
groups $USER

# Check file/directory access
ls -la /target/directory
```

### Logging Issues

**Issue:** No log output or malformed logs
**Solution:**

```bash
# Test logging directly
source template/framework/logging.sh
log_info "Test message"

# Check LOG_LEVEL setting
echo "LOG_LEVEL: $LOG_LEVEL"

# Verify jq for JSON logging
jq --version
```

---

## **References & Related Resources**

### Internal References

| Document Type | Title | Relationship | Link |
|---------------|-------|--------------|------|
| Framework Core | Enterprise Template | Foundation for all scripts | [../template/enterprise-template.sh](../template/enterprise-template.sh) |
| Pattern Library | Implementation Patterns | Advanced usage patterns | [../patterns/README.md](../patterns/README.md) |
| Integration Guides | Platform Integration | Tool integration examples | [../integrations/README.md](../integrations/README.md) |

### External Resources

| Resource Type | Title | Description | Link |
|---------------|-------|-------------|------|
| Best Practices | Advanced Bash Scripting | Comprehensive bash techniques | [tldp.org/LDP/abs/html/](https://tldp.org/LDP/abs/html/) |
| Testing | Bash Testing Framework | Automated testing for bash scripts | [bats-core/bats-core](https://github.com/bats-core/bats-core) |
| Security | OWASP Secure Coding | Security best practices | [owasp.org](https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/) |

---

## **Documentation Metadata**

### Change Log

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2025-09-20 | Initial getting started guide | VintageDon |

### Authorship & Collaboration

**Primary Author:** VintageDon ([GitHub Profile](https://github.com/vintagedon))  
**User Testing:** Validated with new users in enterprise environment  
**Feedback Integration:** Incorporates feedback from production deployments

### Technical Notes

**Guide Status:** Production-validated with enterprise users  
**Framework Compatibility:** Compatible with Enterprise AIOps Bash Framework v1.0  
**Update Frequency:** Updated based on user feedback and framework enhancements

*Document Version: 1.0 | Last Updated: 2025-09-20 | Status: Published*
