#!/bin/bash

# ================================================================================================
# LAN Client Container Creation Script (Refactored)
# ================================================================================================
#
# This script creates lightweight client containers for LAN testing scenarios. These containers
# simulate end-user devices connected to specific LAN ports with VLAN configuration.
#
# Features:
#   - Alpine Linux based for minimal resource usage
#   - VLAN tagging support for network isolation
#   - Configurable LAN port assignment (p1-p4)
#   - Optimized resource limits for client simulation
#   - Automatic bridge connection to appropriate LAN port
#
# Usage: ./client-lan-refactored.sh <device-identifier>
#
# Device Identifier Format:
#   - vcpe-p1, vcpe-p2, vcpe-p3, vcpe-p4
#   - mv1-r21-7-p1, mv2plus-r22-9-p2, etc.
#   - Any string ending with -p[1-4]
#
# Network Configuration:
#   - Connects to lan-p{port} bridge
#   - VLAN ID: 100 (configurable)
#   - DHCP client by default
#   - Resource limits: 128MB RAM, 1 CPU
#
# Dependencies:
#   - client-base image (Alpine Linux with network tools)
#   - LAN port bridges (lan-p1 through lan-p4)
#   - VLAN-aware bridge configuration
#
# Author: RDK-B Development Team
# Version: 2.0 (Refactored)
# Last Modified: 2025-01-13
#
# ================================================================================================

# Import common utility functions
source gen-util.sh

# ================================================================================================
# INPUT VALIDATION AND PARAMETER EXTRACTION
# ================================================================================================

# Validate command line arguments
if [ -z "${1}" ]; then
    echo ""
    echo "ERROR: Missing device identifier parameter"
    echo ""
    echo "Usage: $0 <device-identifier>"
    echo ""
    echo "Device identifier must end with -p[1-4] to specify LAN port:"
    echo "  Examples:"
    echo "    $0 vcpe-p1              # Virtual CPE on port 1"
    echo "    $0 vcpe-p2              # Virtual CPE on port 2"  
    echo "    $0 mv1-r21-7-p3         # MV1 device on port 3"
    echo "    $0 mv2plus-r22-20-p4    # MV2+ device on port 4"
    echo ""
    exit 1
fi

# Extract LAN port number from device identifier using regex
# The device identifier must end with -p[1-4] format
if [[ "${1}" =~ -p([1-4])$ ]]; then
    port="${BASH_REMATCH[1]}"
    device_base="${1%-p[1-4]}"
    echo "Parsed device identifier: ${1}"
    echo "  Device base: ${device_base}"
    echo "  LAN port: ${port}"
else
    echo ""
    echo "ERROR: Invalid device identifier format"
    echo ""
    echo "Device identifier must end with -p1, -p2, -p3, or -p4"
    echo "Examples: vcpe-p1, mv1-r21-7-p2, custom-device-p3"
    echo ""
    exit 1
fi

# ================================================================================================
# CONTAINER CONFIGURATION
# ================================================================================================

# Network configuration
vlan=100  # Default VLAN ID for client devices
memory_limit="128MB"  # Optimized for lightweight client simulation
cpu_limit="1"         # Single CPU core sufficient for client workload

# Generate container name based on full device identifier
container_name="client-lan-${1}"

echo ""
echo "Client Container Configuration:"
echo "  Container Name: ${container_name}"
echo "  LAN Port: ${port} (connects to lan-p${port} bridge)"
echo "  VLAN ID: ${vlan}"
echo "  Memory Limit: ${memory_limit}"
echo "  CPU Limit: ${cpu_limit}"
echo ""

# ================================================================================================
# CONTAINER CREATION
# ================================================================================================

echo "Creating client container using optimized configuration..."

# Use the specialized client container creation function
# This function handles:
# - Base image dependency (client-base)
# - Container deletion if exists
# - Profile creation with VLAN configuration
# - Bridge connection to appropriate LAN port
# - Resource limit optimization
create_client_container "$container_name" "$port" "$vlan" "$memory_limit" "$cpu_limit"

# ================================================================================================
# COMPLETION SUMMARY
# ================================================================================================

echo ""
echo "=============================================================================="
echo "LAN Client Container Created Successfully!"
echo "=============================================================================="
echo ""
echo "Container Details:"
echo "  Name: ${container_name}"
echo "  Base Image: client-base (Alpine Linux)"
echo "  Network:"
echo "    - Bridge: lan-p${port}"
echo "    - VLAN: ${vlan}"
echo "    - IP: DHCP (automatically assigned)"
echo "  Resources:"
echo "    - Memory: ${memory_limit}"
echo "    - CPU: ${cpu_limit} core"
echo ""
echo "Management Commands:"
echo "  Access Shell:     lxc exec ${container_name} -- ash"
echo "  View Network:     lxc exec ${container_name} -- ip addr"
echo "  Check Routing:    lxc exec ${container_name} -- ip route"
echo "  Test Connectivity: lxc exec ${container_name} -- ping 8.8.8.8"
echo ""
echo "Container Operations:"
echo "  Start Container:  lxc start ${container_name}"
echo "  Stop Container:   lxc stop ${container_name}"
echo "  Delete Container: lxc delete ${container_name} --force"
echo ""
echo "Network Testing:"
echo "  # Test LAN connectivity from inside container"
echo "  lxc exec ${container_name} -- ping <target-ip>"
echo ""
echo "  # Monitor network traffic"
echo "  lxc exec ${container_name} -- tcpdump -i eth0"
echo ""
echo "  # Check DHCP lease"
echo "  lxc exec ${container_name} -- cat /var/lib/dhcp/dhclient.leases"
echo ""
echo "=============================================================================="