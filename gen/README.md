# LXD Container Generation Scripts

## Overview

This directory contains scripts for creating and managing LXD containers for various RDK-B testing and development services. The scripts create isolated containers for different components of the RDK-B ecosystem including ACS servers, BNG routers, client devices, and various testing frameworks.

## Architecture

```
gen/
├── gen-util.sh              # Common utility functions and LXD management library
├── *-base.sh                # Base image creation scripts
├── *.sh                     # Service container creation scripts
├── configs/                 # Configuration files and templates
├── patches/                 # Source code patches
└── profiles/               # LXD profile templates
```

## Quick Start

### Prerequisites

- LXD installed and configured (version 4.x or 5.x)
- Ubuntu 22.04+ or compatible host system
- Network bridges configured (automatically handled by scripts)
- Sudo access for bridge and iptables management

### Basic Usage

```bash
# Navigate to the gen directory
cd gen/

# Create a basic ACS server
./acs.sh

# Create a BNG router for customer 7
./bng.sh 7

# Create an automatics testing container
./automatics.sh

# Create a client device on LAN port 1
./client-lan.sh vcpe-p1
```

## Container Types

### Service Containers

| Script | Purpose | Default IP | Ports |
|--------|---------|------------|-------|
| `acs.sh` | ACS TR-069 Server | 10.10.10.200 | 80, 443 |
| `genieacs.sh` | GenieACS Server | 10.10.10.201 | 3000, 7547, 7557, 7567 |
| `webpa.sh` | WebPA Service | 10.10.10.210 | 6200, 6201 |
| `oktopus.sh` | Oktopus Service | 10.10.10.220 | 6400 |
| `telemetry.sh` | Telemetry Service | 10.10.10.251 | 8080 |
| `xconf.sh` | XConf Service | 10.10.10.250 | 8080 |
| `webconfig.sh` | WebConfig Service | 10.10.10.252 | 8080 |

### Infrastructure Containers

| Script | Purpose | Network Configuration |
|--------|---------|----------------------|
| `bng.sh` | BNG Router | Multiple interfaces, customer-specific VLANs |
| `automatics.sh` | Test Framework | Static IP with extensive routing |
| `boardfarm.sh` | Board Farm Testing | Docker-enabled container |

### Client Containers

| Script | Purpose | Network Type |
|--------|---------|--------------|
| `client-lan.sh` | LAN Client Device | Bridged to LAN ports with VLAN |
| `client-wlan.sh` | WLAN Client Device | Wireless interface simulation |

### Base Images

| Script | Purpose | Based On |
|--------|---------|----------|
| `automatics-base.sh` | Automatics Framework Base | Ubuntu 22.04 |
| `bng-base.sh` | BNG Router Base | Devuan Chimaera |
| `client-base.sh` | Client Device Base | Alpine Linux |
| `genieacs-base.sh` | GenieACS Server Base | Ubuntu 22.04 |
| `telemetry-base.sh` | Telemetry Service Base | Ubuntu 22.04 |
| `webconfig-base.sh` | WebConfig Service Base | Ubuntu 22.04 |
| `webpa-base.sh` | WebPA Service Base | Ubuntu 22.04 |
| `xconf-base.sh` | XConf Service Base | Ubuntu 22.04 |

## Network Architecture

### Bridge Configuration

The scripts automatically create and configure several network bridges:

- **lxdbr1** (10.10.10.0/24): Main service network for containers
- **wan**: WAN interface for BNG containers
- **cm**: Cable modem interface
- **lan-p1** to **lan-p4**: LAN port bridges with VLAN support
- **br-wlan0**, **br-wlan1**: Wireless interface bridges

### IP Address Allocation

| Range | Purpose |
|-------|---------|
| 10.10.10.1 | Bridge gateway |
| 10.10.10.100-199 | Reserved for future use |
| 10.10.10.200-299 | Service containers |
| 10.107.200.0/24 | Device management network |
| 10.100.200.0/24 | Customer network (varies by BNG config) |

## Common Functions Library (gen-util.sh)

The `gen-util.sh` script provides a comprehensive library of common functions for LXD container management:

### Container Lifecycle Functions
- `create_container_profile()` - Create and configure LXD profiles
- `delete_container()` - Safely delete containers
- `launch_container()` - Launch containers with profiles
- `create_standard_container()` - Complete container setup workflow

### Image Management
- `ensure_base_image()` - Ensure base images exist, create if needed
- `check_devuan_chimaera()` - Handle Devuan base image

### Network Configuration
- `setup_static_network()` - Configure static IP addresses
- `add_common_routes()` - Add standard routing rules
- `check_and_create_lxdbr1()` - Manage main bridge

### Service Management
- `create_systemd_service()` - Create systemd service files
- `start_systemd_service()` - Start services
- `install_common_packages()` - Install packages

### Utility Functions
- `copy_config_file()` - Copy files with proper permissions
- `setup_container_alias()` - Configure shell aliases
- `wait_for_container_ready()` - Wait for container initialization
- `validate_container_name()` - Validate naming conventions

## Usage Examples

### Creating a Complete Test Environment

```bash
# Create infrastructure
./bridges.sh

# Create ACS server
./acs.sh

# Create BNG for customer 7
./bng.sh 7

# Create test clients
./client-lan.sh mv1-r21-7-p1
./client-lan.sh mv1-r21-7-p2

# Create testing framework
./automatics.sh
./boardfarm.sh
```

### Container Management

```bash
# List all containers
lxc list

# Access a container
lxc exec acs -- bash

# Stop a container
lxc stop genieacs

# Start a container
lxc start genieacs

# Delete a container
lxc delete bng-7 --force
```

### Network Inspection

```bash
# Check container IPs
lxc list -c n4

# Test connectivity
lxc exec acs -- ping 10.10.10.201

# Check routes in container
lxc exec automatics -- ip route

# Monitor traffic
lxc exec bng-7 -- tcpdump -i eth0
```

## Configuration Files

### Profile Templates
- Located in `profiles/vcpe.yaml`
- Define container resource limits and device mappings
- Automatically applied by container scripts

### Network Configurations
- `configs/*-50-cloud-init.yaml`: Netplan configurations for static IPs
- `configs/*-interfaces`: Legacy network interface files
- `configs/*.nmconnection`: NetworkManager connection files

### Service Configurations
- `configs/*.conf`: Service-specific configuration files
- `configs/*.yaml`: Service configuration templates
- `configs/dhcpd*.conf`: DHCP server configurations

## Advanced Usage

### Custom Container Creation

Using the common functions library:

```bash
#!/bin/bash
source gen-util.sh

container_name="my-service"

# Define profile configuration
profile_config='name: my-service
description: "Custom Service Container"
config:
    boot.autostart: "false"
    limits.memory: "512MB"
devices:
    eth0:
        name: eth0
        nictype: bridged
        parent: lxdbr1
        type: nic'

# Create container
ensure_base_image "ubuntu-22.04" ""
create_standard_container "ubuntu-22.04" "$container_name" "$profile_config"

# Install packages
install_common_packages "$container_name" "nginx" "curl" "vim"

# Configure service
copy_config_file "my-service.conf" "$container_name" "/etc/nginx/sites-available/default"
```

### BNG Customer Configuration

The BNG script supports multiple customer configurations:

```bash
# Standard customers (7, 9, 20)
./bng.sh 7    # Creates bng-7 with customer 7 config
./bng.sh 9    # Creates bng-9 with customer 9 config
./bng.sh 20   # Creates bng-20 with customer 20 config

# Extended customers (8, 51, 68, 69)
./bng.sh 8    # Special configuration for customer 8
./bng.sh 68   # Multi-VLAN configuration
./bng.sh 69   # Alternative VLAN setup
```

### Client Device Variants

```bash
# LAN clients with port specification
./client-lan.sh vcpe-p1     # Port 1, VLAN 100
./client-lan.sh mv1-r21-7-p2  # MV1 device on port 2
./client-lan.sh mv3-r22-20-p4 # MV3 device on port 4

# WLAN clients
./client-wlan.sh vcpe-p1    # Wireless client simulation
```

## Troubleshooting

### Common Issues

#### Container Creation Fails
```bash
# Check LXD status
systemctl status lxd

# Verify bridge existence
ip link show lxdbr1

# Check image availability
lxc image list
```

#### Network Connectivity Issues
```bash
# Verify bridge configuration
lxc network show lxdbr1

# Check iptables rules
sudo iptables -t nat -L | grep lxdbr1

# Test DNS resolution
lxc exec container-name -- nslookup google.com
```

#### Service Startup Failures
```bash
# Check service status
lxc exec container-name -- systemctl status service-name

# View service logs
lxc exec container-name -- journalctl -u service-name

# Check listening ports
lxc exec container-name -- netstat -tlnp
```

### Performance Optimization

#### Resource Limits
- Default memory limits vary by container type
- CPU limits can be adjusted in profile configurations
- Disk space is allocated per container

#### Network Performance
- Bridge MTU settings affect throughput
- VLAN configuration impacts switching performance
- Multiple bridges distribute network load

## Development Guidelines

### Adding New Container Types

1. Create base image script if needed
2. Define profile configuration
3. Use common functions from `gen-util.sh`
4. Add network configuration
5. Document in this README

### Best Practices

- Always source `gen-util.sh` for common functions
- Use descriptive container and profile names
- Include proper error handling
- Document any special requirements
- Test with clean environment

### Code Standards

- Use consistent variable naming
- Add comments for complex operations
- Follow existing script structure
- Validate input parameters
- Handle cleanup on errors

## Security Considerations

### Container Isolation
- Containers run unprivileged by default
- AppArmor profiles provide additional security
- Network isolation through bridge configuration

### Access Control
- No default SSH access to containers
- Console access through `lxc exec`
- Service ports exposed only as needed

### Data Protection
- Containers are ephemeral by design
- Important data should be externally mounted
- Regular cleanup prevents data accumulation

## Integration

### CI/CD Pipeline Integration
```bash
# Automated testing setup
./bridges.sh
./acs.sh
./automatics.sh

# Run tests
lxc exec automatics -- /opt/run-tests.sh

# Cleanup
./cleanup-all.sh
```

### External Tool Integration
- Compatible with standard LXD tools
- Integrates with existing network infrastructure
- Supports external monitoring systems

## Support

### Log Locations
- Container logs: `lxc info --show-log container-name`
- Service logs: `/var/log/` within containers
- System logs: `journalctl -u lxd`

### Debugging
- Enable verbose output: `set -x` in scripts
- Container inspection: `lxc config show container-name`
- Network debugging: `lxc network list-leases lxdbr1`

## References

- [LXD Documentation](https://linuxcontainers.org/lxd/docs/master/)
- [RDK-B Documentation](https://wiki.rdkcentral.com/display/RDK/RDK-B)
- [TR-069 Specification](https://www.broadband-forum.org/technical/download/TR-069.pdf)