#!/bin/bash

# ================================================================================================
# GenieACS Container Creation Script (Refactored)
# ================================================================================================
#
# This script creates a GenieACS TR-069 Auto Configuration Server container using the common
# utility functions from gen-util.sh. GenieACS is an open-source TR-069 remote management
# solution for CPE devices.
#
# Features:
#   - MongoDB database for device management
#   - TR-069 CWMP interface (port 7547)
#   - Web-based management UI (port 3000)  
#   - Northbound Interface API (port 7557)
#   - File Server for firmware/config (port 7567)
#   - Port forwarding for external access
#
# Usage: ./genieacs-refactored.sh
#
# Network Configuration:
#   - Static IP: 10.10.10.201/24
#   - Gateway: 10.10.10.1
#   - DNS: 8.8.8.8, 8.8.4.4
#
# Dependencies:
#   - genieacs-base image (created automatically if missing)
#   - LXD with lxdbr1 bridge configured
#   - Network configuration file: configs/genieacs-50-cloud-init.yaml
#
# Author: RDK-B Development Team  
# Version: 2.0 (Refactored)
# Last Modified: 2025-01-13
#
# ================================================================================================

# Import common utility functions
source gen-util.sh

# Container configuration
container_name="genieacs"

# ================================================================================================
# IMAGE DEPENDENCY MANAGEMENT
# ================================================================================================

# Ensure the GenieACS base image exists before proceeding
# This image contains MongoDB, Node.js, and GenieACS pre-installed
echo "Checking for GenieACS base image..."
ensure_base_image "genieacs-base" "genieacs-base.sh"

# ================================================================================================
# CONTAINER PROFILE CONFIGURATION
# ================================================================================================

# Define the LXD profile configuration for the GenieACS container
# This profile includes port forwarding for all GenieACS services
echo "Defining container profile configuration..."

profile_config='name: genieacs
description: "GenieACS TR-069 Auto Configuration Server"
config:
    # Disable automatic startup - containers are started manually
    boot.autostart: "false"
    
    # Security configuration
    raw.lxc: |
      lxc.apparmor.profile=unconfined
    security.privileged: "false"
    security.nesting: "false"
    
    # Resource limits - no limits for GenieACS server
    limits.cpu: ""      # No CPU limits for optimal performance
    limits.memory: ""   # No memory limits for large device databases
    
devices:
    # Network interface - bridged to main container network
    eth0:
        name: eth0
        nictype: bridged
        parent: lxdbr1
        type: nic
        # Static IP configured via netplan file
        
    # Root filesystem
    root:
        path: /
        pool: default
        type: disk
        size: ""  # Use default pool settings
        
    # Port forwarding for GenieACS services
    # These allow external access to GenieACS from the host
    
    # CWMP port - TR-069 communication with CPE devices
    cwmp-port:
        type: proxy
        listen: tcp:0.0.0.0:7547
        connect: tcp:127.0.0.1:7547
        
    # Web UI port - Management interface
    ui-port:
        type: proxy
        listen: tcp:0.0.0.0:3000
        connect: tcp:127.0.0.1:3000
        
    # Northbound Interface - API for external systems
    nbi-port:
        type: proxy
        listen: tcp:0.0.0.0:7557
        connect: tcp:127.0.0.1:7557
        
    # File Server - Firmware and configuration downloads
    fs-port:
        type: proxy
        listen: tcp:0.0.0.0:7567
        connect: tcp:127.0.0.1:7567'

# ================================================================================================
# CONTAINER CREATION
# ================================================================================================

echo "Creating GenieACS container with network configuration..."

# Create the container using the standard function
# - Uses genieacs-base image with pre-installed components
# - Applies the profile configuration defined above
# - Configures static network from netplan file
# - Skips shell alias setup (setup_alias=false) as this is a service container
create_standard_container "genieacs-base" "$container_name" "$profile_config" \
    "$M_ROOT/gen/configs/genieacs-50-cloud-init.yaml" false

# ================================================================================================
# SYSTEM CONFIGURATION
# ================================================================================================

echo "Configuring system timezone..."
# Set timezone to Pacific Time for consistency with development environment
lxc exec ${container_name} -- timedatectl set-timezone America/Los_Angeles

# ================================================================================================
# SERVICE STARTUP SEQUENCE
# ================================================================================================

echo "Starting GenieACS services in proper sequence..."

# Start MongoDB database first - GenieACS depends on it
echo "Starting MongoDB database..."
start_systemd_service "$container_name" "mongod"

# Wait for MongoDB to fully initialize
echo "Waiting for MongoDB to initialize..."
sleep 10

# Verify MongoDB is running before starting GenieACS services
echo "Verifying MongoDB status..."
lxc exec ${container_name} -- systemctl status mongod --no-pager -l

# Start GenieACS services in sequence with delays
# Each service needs time to initialize before the next starts

echo "Starting GenieACS CWMP service (TR-069 interface)..."
start_systemd_service "$container_name" "genieacs-cwmp"
sleep 5

echo "Starting GenieACS NBI service (Northbound Interface)..."
start_systemd_service "$container_name" "genieacs-nbi"
sleep 5

echo "Starting GenieACS File Server..."
start_systemd_service "$container_name" "genieacs-fs"
sleep 5

echo "Starting GenieACS Web UI..."
start_systemd_service "$container_name" "genieacs-ui"

# ================================================================================================
# SERVICE VERIFICATION AND HEALTH CHECK
# ================================================================================================

echo "Allowing services to fully initialize..."
sleep 15

echo "Performing comprehensive service health check..."

# Check all critical services
services=("mongod" "genieacs-cwmp" "genieacs-nbi" "genieacs-fs" "genieacs-ui")
service_descriptions=(
    "MongoDB Database"
    "GenieACS CWMP (TR-069)"
    "GenieACS Northbound Interface"
    "GenieACS File Server"
    "GenieACS Web UI"
)

for i in "${!services[@]}"; do
    service="${services[$i]}"
    description="${service_descriptions[$i]}"
    echo ""
    echo "=== $description Status ==="
    lxc exec ${container_name} -- systemctl status "$service" --no-pager -l
done

echo ""
echo "=== Network Port Status ==="
echo "Checking that all GenieACS services are listening on expected ports..."
lxc exec ${container_name} -- ss -tlnp | grep -E "(27017|7547|7557|7567|3000)"

# ================================================================================================
# COMPLETION SUMMARY
# ================================================================================================

echo ""
echo "=============================================================================="
echo "GenieACS Container Setup Complete!"
echo "=============================================================================="
echo ""

# Get container IP for user convenience
container_ip=$(lxc list ${container_name} -c 4 --format csv | cut -d' ' -f1)

echo "Container Information:"
echo "  Name: ${container_name}"
echo "  IP Address: ${container_ip}"
echo "  Base Image: genieacs-base"
echo ""
echo "Service Endpoints:"
echo "  Web UI:         http://${container_ip}:3000"
echo "  CWMP (TR-069):  http://${container_ip}:7547"
echo "  NBI API:        http://${container_ip}:7557"
echo "  File Server:    http://${container_ip}:7567"
echo "  MongoDB:        ${container_ip}:27017"
echo ""
echo "Access Methods:"
echo "  Shell Access:   lxc exec ${container_name} -- bash"
echo "  Container Info: lxc info ${container_name}"
echo "  Service Logs:   lxc exec ${container_name} -- journalctl -u <service-name>"
echo ""
echo "Next Steps:"
echo "  1. Access the Web UI to configure GenieACS"
echo "  2. Configure CPE devices to connect to CWMP endpoint"
echo "  3. Use NBI API for programmatic device management"
echo "=============================================================================="