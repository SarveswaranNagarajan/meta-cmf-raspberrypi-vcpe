# LXD Container Management - Troubleshooting & Best Practices Guide

## Table of Contents

1. [Common Issues](#common-issues)
2. [Diagnostic Commands](#diagnostic-commands)
3. [Network Troubleshooting](#network-troubleshooting)
4. [Performance Optimization](#performance-optimization)
5. [Best Practices](#best-practices)
6. [Development Guidelines](#development-guidelines)
7. [Maintenance Procedures](#maintenance-procedures)
8. [Error Recovery](#error-recovery)

## Common Issues

### 1. Container Creation Failures

#### Issue: "lxd is not running"
```
Error: Get "http://unix.socket/1.0": dial unix /var/lib/lxd/unix.socket: connect: connection refused
```

**Diagnosis:**
```bash
# Check LXD service status
systemctl status lxd

# Check if LXD daemon is running
ps aux | grep lxd
```

**Solutions:**
```bash
# Start LXD service
sudo systemctl start lxd
sudo systemctl enable lxd

# Initialize LXD if first time
sudo lxd init --minimal

# Add user to lxd group
sudo usermod -a -G lxd $USER
newgrp lxd
```

#### Issue: "Image not found"
```
Error: The requested image couldn't be found
```

**Diagnosis:**
```bash
# List available images
lxc image list

# Check if base image script exists
ls -la *-base.sh
```

**Solutions:**
```bash
# Run base image creation script manually
./genieacs-base.sh

# Or use ensure_base_image function
ensure_base_image "missing-image" "create-script.sh"
```

#### Issue: "Profile already exists"
```
Error: The profile already exists
```

**Diagnosis:**
```bash
# List existing profiles
lxc profile list

# Show profile details
lxc profile show profile-name
```

**Solutions:**
```bash
# Delete existing profile
lxc profile delete profile-name

# Or use the common function which handles this
delete_container "container-name"
create_container_profile "container-name" "$config"
```

### 2. Network Issues

#### Issue: Container has no network connectivity
```
# Ping fails from inside container
lxc exec container-name -- ping 8.8.8.8
ping: bad address '8.8.8.8'
```

**Diagnosis:**
```bash
# Check container network interfaces
lxc exec container-name -- ip addr

# Check routing table
lxc exec container-name -- ip route

# Check DNS resolution
lxc exec container-name -- nslookup google.com

# Check bridge configuration
lxc network show lxdbr1
ip link show lxdbr1
```

**Solutions:**
```bash
# Restart network in container
lxc exec container-name -- systemctl restart networking

# Apply netplan configuration
lxc exec container-name -- netplan apply

# Restart NetworkManager if used
lxc exec container-name -- systemctl restart NetworkManager

# Recreate bridges if needed
./bridges.sh
```

#### Issue: Static IP not assigned
```
# Container gets DHCP IP instead of static
```

**Diagnosis:**
```bash
# Check netplan configuration
lxc exec container-name -- cat /etc/netplan/50-cloud-init.yaml

# Check network interface status
lxc exec container-name -- networkctl status

# Check for NetworkManager conflicts
lxc exec container-name -- systemctl status NetworkManager
```

**Solutions:**
```bash
# Ensure netplan file is correct
copy_config_file "config.yaml" "container-name" "/etc/netplan/50-cloud-init.yaml"

# Apply netplan configuration
lxc exec container-name -- netplan apply

# Disable NetworkManager if conflicting
lxc exec container-name -- systemctl disable NetworkManager
```

### 3. Service Startup Issues

#### Issue: Service fails to start
```
Job for service.service failed because the control process exited with error code.
```

**Diagnosis:**
```bash
# Check service status
lxc exec container-name -- systemctl status service-name

# View service logs
lxc exec container-name -- journalctl -u service-name -f

# Check service file
lxc exec container-name -- cat /etc/systemd/system/service-name.service
```

**Solutions:**
```bash
# Reload systemd daemon
lxc exec container-name -- systemctl daemon-reload

# Check service dependencies
lxc exec container-name -- systemctl list-dependencies service-name

# Manually start dependencies
lxc exec container-name -- systemctl start dependency-service

# Use utility functions for proper service creation
create_systemd_service "$container" "$service" "$service_content"
start_systemd_service "$container" "$service"
```

### 4. Resource Limit Issues

#### Issue: Container out of memory
```
# Container becomes unresponsive or services crash
```

**Diagnosis:**
```bash
# Check container resource usage
lxc info container-name

# Check memory usage inside container
lxc exec container-name -- free -h

# Check system resources
free -h
lxc list
```

**Solutions:**
```bash
# Increase memory limit in profile
lxc config set container-name limits.memory 1GB

# Or recreate with higher limits
profile_config='config:
  limits.memory: "2GB"
  limits.cpu: "2"'
create_container_profile "container-name" "$profile_config"
```

## Diagnostic Commands

### System Health Check
```bash
#!/bin/bash
# Comprehensive system health check

echo "=== LXD System Health Check ==="

# Check LXD status
echo "LXD Service Status:"
systemctl status lxd --no-pager

# Check LXD version
echo -e "\nLXD Version:"
lxd --version

# List containers and their status
echo -e "\nContainer Status:"
lxc list

# Check network bridges
echo -e "\nNetwork Bridges:"
lxc network list

# Check available images
echo -e "\nAvailable Images:"
lxc image list

# Check storage pools
echo -e "\nStorage Pools:"
lxc storage list

# Check system resources
echo -e "\nSystem Resources:"
free -h
df -h
```

### Container Diagnostics
```bash
#!/bin/bash
# Diagnose specific container issues

container_name="$1"
if [ -z "$container_name" ]; then
    echo "Usage: $0 <container-name>"
    exit 1
fi

echo "=== Container Diagnostics: $container_name ==="

# Container information
echo "Container Info:"
lxc info "$container_name"

# Container configuration
echo -e "\nContainer Config:"
lxc config show "$container_name"

# Network interfaces
echo -e "\nNetwork Interfaces:"
lxc exec "$container_name" -- ip addr

# Routing table
echo -e "\nRouting Table:"
lxc exec "$container_name" -- ip route

# Process list
echo -e "\nRunning Processes:"
lxc exec "$container_name" -- ps aux

# Service status
echo -e "\nSystemd Services:"
lxc exec "$container_name" -- systemctl list-units --state=failed

# Disk usage
echo -e "\nDisk Usage:"
lxc exec "$container_name" -- df -h

# Memory usage
echo -e "\nMemory Usage:"
lxc exec "$container_name" -- free -h
```

### Network Diagnostics
```bash
#!/bin/bash
# Network connectivity diagnostics

container_name="$1"
if [ -z "$container_name" ]; then
    echo "Usage: $0 <container-name>"
    exit 1
fi

echo "=== Network Diagnostics: $container_name ==="

# Basic connectivity
echo "Testing external connectivity:"
lxc exec "$container_name" -- ping -c 3 8.8.8.8

echo -e "\nTesting DNS resolution:"
lxc exec "$container_name" -- nslookup google.com

echo -e "\nTesting container-to-container connectivity:"
# Get other container IPs
other_containers=$(lxc list -c n4 --format csv | grep -v "^$container_name" | head -3)
for container_info in $other_containers; do
    other_name=$(echo "$container_info" | cut -d, -f1)
    other_ip=$(echo "$container_info" | cut -d, -f2 | cut -d' ' -f1)
    if [ -n "$other_ip" ]; then
        echo "Testing connectivity to $other_name ($other_ip):"
        lxc exec "$container_name" -- ping -c 2 "$other_ip"
    fi
done

# Port connectivity
echo -e "\nChecking listening ports:"
lxc exec "$container_name" -- netstat -tlnp

# Network interface details
echo -e "\nNetwork Interface Details:"
lxc exec "$container_name" -- ip link
```

## Network Troubleshooting

### Bridge Configuration Issues

#### Problem: Bridge doesn't exist
```bash
# Check if bridge exists
ip link show lxdbr1
# Error: Device "lxdbr1" does not exist.
```

**Solution:**
```bash
# Recreate bridges using utility script
./bridges.sh

# Or manually create bridge
check_and_create_lxdbr1
```

#### Problem: Bridge has wrong IP range
```bash
# Check bridge configuration
lxc network show lxdbr1
```

**Solution:**
```bash
# Reconfigure bridge
lxc network set lxdbr1 ipv4.address "10.10.10.1/24"
lxc network set lxdbr1 ipv4.dhcp "false"
```

### VLAN Configuration Issues

#### Problem: VLAN traffic not working
```bash
# Check VLAN configuration on bridge
sudo bridge vlan show
```

**Solution:**
```bash
# Ensure bridge has VLAN filtering enabled
sudo ip link set bridge-name type bridge vlan_filtering 1

# Add VLAN to bridge port
sudo bridge vlan add vid 100 dev eth0 master
```

### Container Network Isolation

#### Problem: Containers can't communicate
```bash
# Test container-to-container connectivity
lxc exec container1 -- ping container2-ip
```

**Solution:**
```bash
# Check firewall rules
sudo iptables -L

# Check LXD network configuration
lxc network show lxdbr1

# Ensure containers are on same network
lxc config device show container1 eth0
lxc config device show container2 eth0
```

## Performance Optimization

### Resource Allocation

#### CPU Optimization
```bash
# Set CPU limits based on workload
lxc config set container-name limits.cpu "2"           # 2 cores
lxc config set container-name limits.cpu.allowance "50%" # 50% of 1 core
lxc config set container-name limits.cpu.priority "5"  # Lower priority
```

#### Memory Optimization
```bash
# Set memory limits
lxc config set container-name limits.memory "512MB"
lxc config set container-name limits.memory.swap "false"
```

#### Disk I/O Optimization
```bash
# Set disk limits
lxc config device set container-name root limits.read "20MB"
lxc config device set container-name root limits.write "10MB"
```

### Network Performance

#### Network Throughput
```bash
# Optimize network buffer sizes
lxc exec container-name -- sysctl -w net.core.rmem_max=134217728
lxc exec container-name -- sysctl -w net.core.wmem_max=134217728
```

#### Bridge Performance
```bash
# Enable bridge features for performance
sudo ip link set lxdbr1 type bridge ageing_time 30000
sudo ip link set lxdbr1 type bridge forward_delay 0
```

### Storage Performance

#### ZFS Optimization (if using ZFS)
```bash
# Optimize ZFS pool
sudo zfs set compression=lz4 default/containers
sudo zfs set atime=off default/containers
```

#### Directory-based Storage
```bash
# Use fast SSD for container storage
lxc storage create fast-pool dir source=/fast-ssd/lxd
lxc profile device set default root pool=fast-pool
```

## Best Practices

### Container Design

#### 1. Use Minimal Base Images
```bash
# Prefer Alpine for lightweight containers
create_client_container() {
    # Uses Alpine-based client-base image
    ensure_base_image "client-base" "client-base.sh"
}

# Use Ubuntu only when necessary
ensure_base_image "ubuntu-22.04" ""
```

#### 2. Implement Proper Resource Limits
```bash
# Always set appropriate limits
profile_config='config:
  limits.memory: "512MB"
  limits.cpu: "1"
  boot.autostart: "false"'
```

#### 3. Use Static IPs for Services
```bash
# Service containers should have predictable IPs
# Define in netplan configuration files
setup_static_network "$container" "$netplan_file"
```

### Security Best Practices

#### 1. Container Isolation
```bash
# Use unprivileged containers
profile_config='config:
  security.privileged: "false"
  security.nesting: "false"'
```

#### 2. Network Segmentation
```bash
# Use different bridges for different purposes
# - lxdbr1: Service containers
# - lan-p1-p4: Client device simulation
# - wan: External facing services
```

#### 3. Service Hardening
```bash
# Run services as non-root when possible
create_systemd_service "$container" "$service" "
[Unit]
Description=My Service

[Service]
User=nobody
Group=nogroup
ExecStart=/usr/bin/my-service
"
```

### Operational Best Practices

#### 1. Use Common Functions
```bash
# Always use utility functions for consistency
source gen-util.sh
create_standard_container "$image" "$container" "$profile"

# Instead of manual commands
# lxc launch ...
# lxc profile ...
```

#### 2. Implement Error Handling
```bash
# Check return codes
if ! create_standard_container "$image" "$container" "$profile"; then
    echo "Failed to create container"
    exit 1
fi

# Use validation functions
if ! validate_container_name "$name"; then
    echo "Invalid container name"
    exit 1
fi
```

#### 3. Document Configuration
```bash
# Always comment complex configurations
profile_config='name: web-server
description: "Production web server container"
config:
    # Disable autostart for manual control
    boot.autostart: "false"
    
    # Resource limits for web workload
    limits.memory: "2GB"
    limits.cpu: "2"'
```

## Development Guidelines

### Script Structure

#### 1. Standard Script Template
```bash
#!/bin/bash

# ===================================================================
# Script Description and Documentation
# ===================================================================

# Import utilities
source gen-util.sh

# Validate prerequisites
check_lxd_version

# Define configuration
container_name="my-service"
profile_config='...'

# Create container
ensure_base_image "$base_image" "$base_script"
create_standard_container "$base_image" "$container_name" "$profile_config"

# Configure services
install_common_packages "$container_name" "package1" "package2"
create_systemd_service "$container_name" "$service" "$service_config"
start_systemd_service "$container_name" "$service"

# Provide user feedback
echo "Container $container_name ready!"
```

#### 2. Function Development
```bash
# Always include comprehensive documentation
#
# Function description
#
# Arguments:
#   $1 - Parameter description
#   $2 - Optional parameter (default: value)
#
# Returns: Description of return values
# Side Effects: What the function modifies
#
# Example:
#   my_function "arg1" "arg2"
#
my_function() {
    local param1="$1"
    local param2="${2:-default}"
    
    # Implementation with error checking
    if [ -z "$param1" ]; then
        echo "Error: param1 required"
        return 1
    fi
    
    # Function logic
    ...
    
    return 0
}
```

### Testing Practices

#### 1. Test Script Syntax
```bash
# Always test syntax before committing
bash -n script.sh

# Test with different parameters
./script.sh test-container
./script.sh production-container
```

#### 2. Automated Testing
```bash
#!/bin/bash
# test-container-creation.sh

# Test basic container creation
./genieacs-refactored.sh
if lxc list | grep -q "genieacs"; then
    echo "✓ GenieACS container created"
else
    echo "✗ GenieACS container creation failed"
    exit 1
fi

# Test service startup
sleep 30
if lxc exec genieacs -- systemctl is-active genieacs-ui; then
    echo "✓ GenieACS UI service running"
else
    echo "✗ GenieACS UI service failed"
    exit 1
fi

# Cleanup
lxc delete genieacs --force
echo "✓ Test completed successfully"
```

## Maintenance Procedures

### Regular Maintenance

#### 1. Clean Up Unused Resources
```bash
#!/bin/bash
# cleanup-lxd.sh

# Remove stopped containers older than 7 days
lxc list -c ns --format csv | while IFS=, read name status; do
    if [ "$status" = "STOPPED" ]; then
        echo "Checking $name..."
        # Add logic to check age and remove if old
    fi
done

# Clean up unused images
lxc image list --format csv | grep "^cached" | cut -d, -f1 | xargs -r lxc image delete

# Clean up unused profiles
lxc profile list --format csv | while IFS=, read profile; do
    if [ "$profile" != "default" ]; then
        # Check if profile is in use
        if ! lxc list --format csv | grep -q ",$profile$"; then
            echo "Removing unused profile: $profile"
            lxc profile delete "$profile"
        fi
    fi
done
```

#### 2. Update Base Images
```bash
#!/bin/bash
# update-base-images.sh

base_images=("ubuntu-22.04" "alpine-3.18" "devuan-chimaera")

for image in "${base_images[@]}"; do
    echo "Updating $image..."
    if lxc image list | grep -q "$image"; then
        # Create backup
        lxc image copy "$image" local: --alias "${image}-backup-$(date +%Y%m%d)"
        
        # Update image
        lxc image delete "$image"
        # Re-import latest version
        # Implementation depends on image source
    fi
done
```

#### 3. Monitor Resource Usage
```bash
#!/bin/bash
# monitor-resources.sh

echo "=== LXD Resource Usage Report ==="
echo "Generated: $(date)"
echo ""

echo "Container Resource Usage:"
lxc list -c n4m --format table

echo ""
echo "Storage Usage:"
lxc storage info default

echo ""
echo "Network Statistics:"
for container in $(lxc list -c n --format csv); do
    echo "Container: $container"
    lxc exec "$container" -- cat /proc/net/dev | grep eth0
done
```

## Error Recovery

### Container Recovery

#### 1. Corrupted Container
```bash
# Symptoms: Container won't start, filesystem errors

# Stop container
lxc stop container-name --force

# Check container filesystem
lxc config set container-name security.privileged true
lxc start container-name
lxc exec container-name -- fsck /dev/root

# If recovery fails, recreate from backup or script
lxc delete container-name --force
./recreate-container.sh container-name
```

#### 2. Network Configuration Reset
```bash
# Reset all network configuration
lxc stop container-name
lxc config device remove container-name eth0
lxc config device add container-name eth0 nic nictype=bridged parent=lxdbr1
lxc start container-name

# Reconfigure network
setup_static_network "$container_name" "$netplan_file"
```

### System Recovery

#### 1. Bridge Recovery
```bash
# If bridges are misconfigured or missing
sudo systemctl stop lxd
sudo ip link delete lxdbr1 2>/dev/null
sudo systemctl start lxd

# Recreate bridges
./bridges.sh
```

#### 2. LXD Database Recovery
```bash
# If LXD database is corrupted
sudo systemctl stop lxd
sudo cp -r /var/lib/lxd/database /var/lib/lxd/database.backup.$(date +%Y%m%d)

# Try to repair
sudo sqlite3 /var/lib/lxd/database/global/db.bin ".recover" > /tmp/recovered.sql
sudo mv /var/lib/lxd/database/global/db.bin /var/lib/lxd/database/global/db.bin.corrupt
sudo sqlite3 /var/lib/lxd/database/global/db.bin < /tmp/recovered.sql

sudo systemctl start lxd
```

### Emergency Procedures

#### 1. Complete Environment Reset
```bash
#!/bin/bash
# emergency-reset.sh - USE WITH CAUTION

echo "WARNING: This will destroy ALL containers and configuration!"
read -p "Type 'DESTROY' to continue: " confirm
if [ "$confirm" != "DESTROY" ]; then
    echo "Aborted"
    exit 1
fi

# Stop all containers
lxc list -c n --format csv | xargs -I {} lxc stop {} --force

# Delete all containers
lxc list -c n --format csv | xargs -I {} lxc delete {} --force

# Delete all custom profiles
lxc profile list --format csv | grep -v "^default$" | xargs -I {} lxc profile delete {}

# Delete all custom images
lxc image list --format csv | cut -d, -f2 | xargs -I {} lxc image delete {}

# Reset network configuration
sudo systemctl stop lxd
sudo rm -rf /var/lib/lxd/networks/*
sudo systemctl start lxd

# Reinitialize
sudo lxd init --minimal
./bridges.sh

echo "Environment reset complete. Recreate containers as needed."
```

#### 2. Backup and Restore
```bash
#!/bin/bash
# backup-lxd.sh

backup_dir="/backup/lxd/$(date +%Y%m%d)"
mkdir -p "$backup_dir"

# Export all containers
lxc list -c n --format csv | while read container; do
    echo "Backing up $container..."
    lxc export "$container" "$backup_dir/${container}.tar.gz"
done

# Backup profiles
lxc profile list --format csv | while read profile; do
    lxc profile show "$profile" > "$backup_dir/${profile}.yaml"
done

# Backup images
lxc image list --format csv | while read fingerprint alias; do
    if [ -n "$alias" ]; then
        lxc image export "$alias" "$backup_dir/"
    fi
done

echo "Backup completed in $backup_dir"
```

This comprehensive troubleshooting guide covers the most common issues and provides practical solutions for maintaining a healthy LXD container environment. Always test procedures in a development environment before applying to production systems.