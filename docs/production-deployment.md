<!--
---
title: "Production Deployment Guide"
description: "Focused production deployment guide for enterprise bash automation with essential security, monitoring, and operational controls"
author: "VintageDon - https://github.com/vintagedon"
date: "2025-09-20"
version: "1.0"
status: "Published"
tags:
- type: runbook
- domain: enterprise-operations
- tech: bash
- audience: sre-engineers
related_documents:
- "[Getting Started Guide](getting-started.md)"
- "[Security Hardening Guide](security-hardening.md)"
- "[Enterprise Template](../template/enterprise-template.sh)"
---
-->

# **Production Deployment Guide**

This guide covers the essential steps for deploying the Enterprise AIOps Bash Framework in production environments. Focus is on core requirements, not comprehensive coverage of every possible scenario.

---

## **Prerequisites**

### System Requirements

- Linux system (Ubuntu 20.04+, RHEL 8+, or Amazon Linux 2)
- 2+ CPU cores, 4GB RAM, 20GB disk space
- Network access to package repositories and monitoring systems

### Required Packages

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y bash jq curl git

# RHEL/CentOS/Amazon Linux
sudo yum install -y bash jq curl git
```

---

## **Core Installation**

### 1. System Setup

```bash
#!/usr/bin/env bash
# Basic production setup

# Create automation user
sudo useradd -r -s /bin/bash -d /opt/enterprise-automation -c "Enterprise Automation" automation

# Create directory structure
sudo mkdir -p /opt/enterprise-automation/{framework,scripts,config,logs}
sudo mkdir -p /var/log/enterprise-automation
sudo mkdir -p /backup/enterprise-automation

# Set ownership
sudo chown -R automation:automation /opt/enterprise-automation
sudo chown -R automation:automation /var/log/enterprise-automation
sudo chown -R automation:automation /backup/enterprise-automation

# Set permissions
sudo chmod 755 /opt/enterprise-automation
sudo chmod 750 /opt/enterprise-automation/config
sudo chmod 755 /var/log/enterprise-automation
```

### 2. Framework Installation

```bash
#!/usr/bin/env bash
# Install framework from repository

cd /tmp
git clone https://github.com/vintagedon/enterprise-aiops-bash.git
cd enterprise-aiops-bash
git checkout v1.0.0  # Use specific version for production

# Copy framework files
sudo cp -r template patterns plugins integrations /opt/enterprise-automation/framework/

# Set permissions
sudo chown -R automation:automation /opt/enterprise-automation/framework
sudo find /opt/enterprise-automation/framework -name "*.sh" -exec chmod +x {} \;

# Verify installation
test -f /opt/enterprise-automation/framework/template/enterprise-template.sh || exit 1
```

### 3. Environment Configuration

```bash
#!/usr/bin/env bash
# Production environment configuration

cat > /opt/enterprise-automation/config/production.conf << 'EOF'
# Production Environment Configuration
export ENVIRONMENT="production"
export LOG_LEVEL=20                    # INFO level
export LOG_FORMAT="json"               # Structured logging
export DRY_RUN_DEFAULT=0              # Live operations
export VAULT_ADDR="${VAULT_ADDR:-}"    # Set via environment
export PROMETHEUS_GATEWAY="${PROMETHEUS_GATEWAY:-}"
EOF

sudo chown automation:automation /opt/enterprise-automation/config/production.conf
sudo chmod 640 /opt/enterprise-automation/config/production.conf
```

---

## **Security Configuration**

### Access Control

```bash
#!/usr/bin/env bash
# Configure sudo access for automation user

cat << 'EOF' | sudo tee /etc/sudoers.d/enterprise-automation
# Enterprise Automation sudo rules
automation ALL=(ALL) NOPASSWD: /bin/systemctl restart nginx
automation ALL=(ALL) NOPASSWD: /bin/systemctl reload apache2
automation ALL=(ALL) NOPASSWD: /usr/bin/docker restart
EOF

sudo chmod 440 /etc/sudoers.d/enterprise-automation
```

### SSH Configuration

```bash
#!/usr/bin/env bash
# Generate SSH key for automation user

sudo -u automation ssh-keygen -t ed25519 -f /opt/enterprise-automation/.ssh/id_ed25519 -N ""

cat << 'EOF' | sudo -u automation tee /opt/enterprise-automation/.ssh/config
Host *
    StrictHostKeyChecking yes
    UserKnownHostsFile ~/.ssh/known_hosts
    IdentityFile ~/.ssh/id_ed25519
    ConnectTimeout 30
EOF

sudo chmod 600 /opt/enterprise-automation/.ssh/config
```

### Firewall Setup

```bash
#!/usr/bin/env bash
# Basic firewall configuration

if command -v ufw >/dev/null; then
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow 22/tcp
    sudo ufw allow from 10.0.0.0/8 to any port 9100  # Node exporter
    sudo ufw --force enable
elif command -v firewall-cmd >/dev/null; then
    sudo firewall-cmd --permanent --add-service=ssh
    sudo firewall-cmd --permanent --add-port=9100/tcp
    sudo firewall-cmd --reload
fi
```

---

## **Monitoring Setup**

### Node Exporter Installation

```bash
#!/usr/bin/env bash
# Install Prometheus Node Exporter

NODE_EXPORTER_VERSION="1.7.0"
cd /tmp

wget "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
tar xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"

sudo useradd -r -s /bin/false node_exporter
sudo mkdir -p /opt/node_exporter
sudo cp "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /opt/node_exporter/
sudo chown node_exporter:node_exporter /opt/node_exporter/node_exporter

# Create systemd service
cat << 'EOF' | sudo tee /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/opt/node_exporter/node_exporter --web.listen-address=:9100
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

# Create textfile collector directory
sudo mkdir -p /var/lib/node_exporter/textfile_collector
sudo chown automation:automation /var/lib/node_exporter/textfile_collector

rm -rf /tmp/node_exporter-*
```

### Log Management

```bash
#!/usr/bin/env bash
# Configure log rotation

cat << 'EOF' | sudo tee /etc/logrotate.d/enterprise-automation
/var/log/enterprise-automation/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0644 automation automation
}
EOF
```

---

## **Operational Procedures**

### Health Check Script

```bash
#!/usr/bin/env bash
# Essential health monitoring

source /opt/enterprise-automation/framework/template/framework/logging.sh

check_system_health() {
    log_info "Running system health check"
    
    # Check disk space
    local disk_usage=$(df /opt | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ "$disk_usage" -gt 85 ]]; then
        log_error "High disk usage: ${disk_usage}%"
        return 1
    fi
    
    # Check automation service
    if ! systemctl is-active --quiet enterprise-automation 2>/dev/null; then
        log_warn "Enterprise automation service not running"
    fi
    
    # Check node exporter
    if ! curl -sf http://localhost:9100/metrics >/dev/null; then
        log_error "Node exporter not responding"
        return 1
    fi
    
    log_info "System health check passed"
}

check_system_health "$@"
```

### Backup Script

```bash
#!/usr/bin/env bash
# Simple backup solution

source /opt/enterprise-automation/framework/template/framework/logging.sh

BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backup/enterprise-automation/$BACKUP_DATE"

create_backup() {
    log_info "Creating backup: $BACKUP_DIR"
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup critical components
    tar czf "$BACKUP_DIR/scripts.tar.gz" -C /opt/enterprise-automation scripts
    tar czf "$BACKUP_DIR/config.tar.gz" -C /opt/enterprise-automation config
    tar czf "$BACKUP_DIR/logs.tar.gz" -C /var/log enterprise-automation
    
    # Create manifest
    cat > "$BACKUP_DIR/manifest.txt" << EOF
Backup Date: $(date)
Hostname: $(hostname)
Components: scripts, config, logs
EOF
    
    # Cleanup old backups (keep 7 days)
    find /backup/enterprise-automation -name "*.tar.gz" -mtime +7 -delete
    
    log_info "Backup completed: $BACKUP_DIR"
}

create_backup "$@"
```

### Deployment Script

```bash
#!/usr/bin/env bash
# Automated deployment with rollback capability

source /opt/enterprise-automation/framework/template/framework/logging.sh

ENVIRONMENT="${1:-production}"
ROLLBACK_DIR="/backup/enterprise-automation/rollback-$(date +%s)"

deploy() {
    log_info "Starting deployment to $ENVIRONMENT"
    
    # Create rollback backup
    mkdir -p "$ROLLBACK_DIR"
    cp -r /opt/enterprise-automation/scripts "$ROLLBACK_DIR/"
    cp -r /opt/enterprise-automation/config "$ROLLBACK_DIR/"
    
    # Deploy new version (assuming files are staged in /tmp/deployment)
    if [[ -d "/tmp/deployment" ]]; then
        cp -r /tmp/deployment/* /opt/enterprise-automation/
        chown -R automation:automation /opt/enterprise-automation
        find /opt/enterprise-automation/scripts -name "*.sh" -exec chmod +x {} \;
    fi
    
    # Restart services
    systemctl restart enterprise-automation 2>/dev/null || true
    
    # Validate deployment
    if /opt/enterprise-automation/scripts/health-check.sh; then
        log_info "Deployment successful"
        rm -rf "$ROLLBACK_DIR"
    else
        log_error "Deployment validation failed, rolling back"
        rollback
        exit 1
    fi
}

rollback() {
    log_info "Rolling back deployment"
    
    if [[ -d "$ROLLBACK_DIR" ]]; then
        cp -r "$ROLLBACK_DIR"/* /opt/enterprise-automation/
        chown -R automation:automation /opt/enterprise-automation
        systemctl restart enterprise-automation 2>/dev/null || true
        log_info "Rollback completed"
    else
        log_error "No rollback version available"
        exit 1
    fi
}

deploy "$@"
```

---

## **Validation Checklist**

After deployment, verify these essential components:

### Framework Validation

```bash
# Test framework functionality
sudo -u automation /opt/enterprise-automation/framework/template/enterprise-template.sh --help

# Test dry run capability
sudo -u automation /opt/enterprise-automation/framework/template/enterprise-template.sh \
    --file /etc/hosts --dry-run

# Verify error handling
! sudo -u automation /opt/enterprise-automation/framework/template/enterprise-template.sh \
    --file /nonexistent 2>/dev/null
```

### Security Validation

```bash
# Check user configuration
id automation

# Verify permissions
ls -la /opt/enterprise-automation/config/
stat -c "%a %n" /opt/enterprise-automation/scripts/*.sh

# Test sudo configuration
sudo -u automation sudo -l
```

### Monitoring Validation

```bash
# Check node exporter
curl -sf http://localhost:9100/metrics | head -5

# Verify log directory
ls -la /var/log/enterprise-automation/

# Test log rotation configuration
sudo logrotate -d /etc/logrotate.d/enterprise-automation
```

---

## **Troubleshooting**

### Common Issues

| Issue | Symptoms | Resolution |
|-------|----------|------------|
| **Permission Denied** | Scripts fail with permission errors | Check ownership: `chown -R automation:automation /opt/enterprise-automation` |
| **jq Command Not Found** | JSON logging fails | Install jq: `sudo apt install jq` or `sudo yum install jq` |
| **Node Exporter Not Responding** | Metrics endpoint unreachable | Check service: `systemctl status node_exporter` |
| **Backup Directory Full** | Disk space warnings | Clean old backups: `find /backup -mtime +30 -delete` |

### Log Analysis

```bash
# Check recent automation logs
journalctl -u enterprise-automation --since "1 hour ago"

# Monitor system logs for automation activity
sudo tail -f /var/log/enterprise-automation/*.log

# Check for permission issues
sudo ausearch -k automation_access --start today 2>/dev/null || echo "auditd not configured"
```

---

## **References & Related Resources**

### Internal References

| Document | Purpose | Link |
|----------|---------|------|
| Enterprise Template | Core framework template | [template/enterprise-template.sh](../template/enterprise-template.sh) |
| Security Guide | Detailed security hardening | [security-hardening.md](security-hardening.md) |
| Getting Started | Initial setup guide | [getting-started.md](getting-started.md) |

### External Resources

| Resource | Description | Link |
|----------|-------------|------|
| Prometheus Node Exporter | Metrics collection | [GitHub](https://github.com/prometheus/node_exporter) |
| jq Documentation | JSON processing | [jqlang.org](https://jqlang.org/) |
| systemd Documentation | Service management | [systemd.io](https://systemd.io/) |

---

## **Documentation Metadata**

### Change Log

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2025-09-20 | Initial focused production guide | VintageDon |

### Authorship & Collaboration

**Primary Author:** VintageDon ([GitHub Profile](https://github.com/vintagedon))  
**Methodology:** RAVGVR - focused on essential production requirements  
**Quality Assurance:** Content validated for practical production deployment

### Implementation Notes

- **Target:** Production-ready deployment in 2-4 hours
- **Focus:** Core security, monitoring, and operational requirements
- **Scope:** Essential components only, not comprehensive coverage

*Document Version: 1.0 | Last Updated: 2025-09-20 | Status: Published*
