# meta-cmf-raspberrypi-vcpe

![vCPE Diagram](doc/e2e.svg)

## Overview

**meta-cmf-raspberrypi-vcpe** is a comprehensive **Yocto/OpenEmbedded meta-layer** and **LXD container orchestration system** designed for **RDK-B (Reference Design Kit - Broadband) virtual Customer Premises Equipment (vCPE)** development, testing, and validation. This project creates a complete virtualized broadband gateway environment that simulates real-world network deployments without requiring physical hardware infrastructure.

## Table of Contents

- [Project Architecture](#project-architecture)
- [Key Components](#key-components)
- [Container Types](#container-types)
- [Network Architecture](#network-architecture)
- [Installation and Setup](#installation-and-setup)
- [Usage Workflows](#usage-workflows)
- [Development Guide](#development-guide)
- [Testing and Validation](#testing-and-validation)
- [Troubleshooting](#troubleshooting)
- [Documentation](#documentation)

## Project Architecture

### Technology Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Build System** | Yocto/OpenEmbedded (Kirkstone) | RDK-B image compilation and customization |
| **Container Runtime** | LXD 6.1+ | System container management |
| **Gateway Software** | RDK-B (CCSP Framework) | Broadband gateway functionality |
| **Management Protocols** | TR-069, USP (TR-369), WebPA | Device management and configuration |
| **Network Simulation** | Linux Bridges, VLAN, iptables | Realistic network topology |
| **Testing Framework** | Automatics, Boardfarm | Automated test execution |

### Repository Structure

```
meta-cmf-raspberrypi-vcpe/
├── classes/                    # BitBake class extensions
│   └── image_types_lxc.bbclass  # LXC container image generation
├── conf/                       # Layer and machine configuration
│   ├── layer.conf              # Yocto meta-layer definition
│   └── machine/                # Target machine configurations
├── doc/                        # Comprehensive documentation
│   ├── automatics/             # Test automation setup
│   ├── dac/                    # Container management docs
│   ├── genieacs/               # Open-source ACS documentation
│   └── vcpe/                   # vCPE container build guides
├── gen/                        # LXD container orchestration scripts
│   ├── *-base.sh               # Base container image creation
│   ├── *.sh                    # Service container deployment
│   ├── configs/                # Container configuration files
│   └── profiles/               # LXD profile templates
├── probes/                     # Debugging and analysis tools
│   └── scripts/                # Log collection and parsing utilities
├── recipes-ccsp/              # CCSP component customizations
├── recipes-containers/         # Container runtime integration
├── recipes-connectivity/       # Network component modifications
├── recipes-core/               # Core system customizations
├── recipes-rdkb/               # RDK-B specific enhancements
└── recipes-vcpe/               # vCPE container initialization
```

## Key Components

### 1. Yocto Meta-Layer (`conf/`, `classes/`, `recipes-*`)

**Purpose**: Extends RDK-B builds to generate containerized gateway images

**Key Features**:
- **Custom Image Types**: Creates LXC-compatible container images from RDK-B builds
- **CCSP Modifications**: Patches and configurations for TR-069, device profiles, and HAL components
- **Container Integration**: Dobby and DSM container runtime support
- **vCPE Initialization**: Container-specific startup services and configuration

**Target Platforms**:
- **Primary**: x86 emulated broadband gateway (`qemux86broadband`)
- **Architecture**: Supports ARM64 and x86_64 container deployment
- **Compatibility**: Yocto Kirkstone (4.0) and RDK-B 2024+ releases

### 2. Container Orchestration System (`gen/`)

**Purpose**: Creates and manages complete virtual broadband network environments

**Features**:
- **15+ Common Functions**: Standardized container lifecycle management
- **Network Simulation**: Realistic ISP and customer network topology
- **Service Integration**: TR-069, USP, WebPA, and cloud service simulators
- **Automated Deployment**: One-command environment setup
- **Resource Management**: Optimized container profiles and resource allocation

**Enhanced Documentation**: The `gen/` directory includes comprehensive documentation:
- **[gen/README.md](gen/README.md)**: Complete container management guide
- **[gen/API-REFERENCE.md](gen/API-REFERENCE.md)**: Function library documentation
- **[gen/TROUBLESHOOTING.md](gen/TROUBLESHOOTING.md)**: Common issues and solutions

### 3. Testing and Debugging Infrastructure (`probes/`, `doc/`)

**Purpose**: Comprehensive testing, monitoring, and debugging capabilities

**Components**:
- **Automatics Framework**: RDK-B automated test execution
- **Boardfarm Integration**: Hardware-in-the-loop testing
- **Log Analysis Tools**: RDK log parsing and correlation
- **Performance Monitoring**: Memory, CPU, and network analysis

## Container Types

### Service Containers

| Container | Purpose | Default IP | Key Ports | Base OS |
|-----------|---------|------------|-----------|---------|
| **acs** | Axiros TR-069 ACS Server | 10.10.10.200 | 80, 443 | Debian 7 |
| **genieacs** | Open-source TR-069 ACS | 10.10.10.201 | 3000, 7547, 7557, 7567 | Ubuntu 22.04 |
| **oktopus** | USP Controller (TR-369) | 10.10.10.220 | 80, 1883, 8080 | Debian 12 |
| **webpa** | WebPA/Xmidt Server | 10.10.10.210 | 6200, 6201, 8080, 9003 | CentOS Stream 9 |
| **xconf** | Configuration Server | 10.10.10.250 | 19093 | Ubuntu 18.04 |
| **telemetry** | Data Collection Server | 10.10.10.251 | 5601, 9200 | Ubuntu 20.04 |
| **webconfig** | WebConfig Server | 10.10.10.252 | 8080 | Ubuntu 18.04 |

### Infrastructure Containers

| Container | Purpose | Network Configuration | Key Features |
|-----------|---------|----------------------|--------------|
| **vcpe** | RDK-B Gateway | WAN + 4 LAN ports + WiFi | Full CCSP stack, TR-069/USP agents |
| **bng-{customer}** | ISP Network Gateway | Multi-interface, VLAN support | DHCP, DNS, routing, TFTP |
| **automatics** | Test Framework | Static IP with extensive routing | Maven, MySQL, test orchestration |
| **boardfarm** | Hardware Testing | Docker-enabled | Physical device integration |

### Client Simulation Containers

| Container Type | Purpose | Network Connection | Base Image |
|----------------|---------|-------------------|------------|
| **client-lan-{device}-p{1-4}** | LAN client devices | Bridged to LAN ports with VLAN | Alpine Linux |
| **client-wlan** | WiFi client devices | 802.11 simulation via mac80211_hwsim | Alpine Linux |

## Network Architecture

### Bridge Configuration

The system automatically creates and manages multiple network bridges:

```
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  Service        │  │  Infrastructure │  │  Client         │
│  Containers     │  │  Containers     │  │  Containers     │
├─────────────────┤  ├─────────────────┤  ├─────────────────┤
│ acs             │  │ bng-{customer}  │  │ client-lan-*    │
│ genieacs        │  │ vcpe            │  │ client-wlan     │
│ oktopus         │  │ automatics      │  │                 │
│ webpa           │  │ boardfarm       │  │                 │
│ xconf           │  │                 │  │                 │
│ telemetry       │  │                 │  │                 │
│ webconfig       │  │                 │  │                 │
└─────────────────┘  └─────────────────┘  └─────────────────┘
         │                      │                      │
    ┌────▼────┐            ┌────▼────┐            ┌────▼────┐
    │ lxdbr1  │            │   wan   │            │ lan-p1  │
    │         │            │   cm    │            │ lan-p2  │
    │10.10.10 │            │         │            │ lan-p3  │
    │  .0/24  │            │         │            │ lan-p4  │
    └─────────┘            └─────────┘            │br-wlan0 │
                                                  │br-wlan1 │
                                                  └─────────┘
```

### IP Address Allocation

| Network Segment | IP Range | Purpose |
|-----------------|----------|---------|
| **lxdbr1** | 10.10.10.0/24 | Service container communication |
| **WAN Networks** | 10.107.200.0/24, 10.100.200.0/24 | vCPE WAN interfaces |
| **LAN Networks** | 10.0.0.0/24, 192.168.x.0/24 | Client device networks |
| **Management** | Variable per customer config | BNG management interfaces |

### VLAN Configuration

- **LAN Ports**: VLAN-aware bridges supporting 802.1Q tagging
- **Client Isolation**: VLAN ID 100 (default) for client containers
- **Multi-tenant Support**: Customer-specific VLAN configurations
- **WAN Flexibility**: Single-VLAN, multi-VLAN, or untagged configurations

## Installation and Setup

### Prerequisites

#### System Requirements
- **Operating System**: Ubuntu 20.04/22.04/24.04 LTS (recommended)
- **Architecture**: x86_64 (primary), ARM64 (experimental)
- **Memory**: 8GB RAM minimum, 16GB+ recommended
- **Storage**: 50GB+ available disk space
- **Network**: Internet connectivity for image downloads

#### Software Dependencies
- **LXD**: Version 6.1+ (installed via snap)
- **Git**: For repository cloning
- **Build Tools**: GCC, make, python3 (if building from source)

### LXD Installation and Configuration

```bash
# Install LXD via snap
sudo snap install lxd --channel=6.1

# Initialize LXD (select all defaults)
sudo lxd init

# Add user to lxd group
sudo usermod -a -G lxd $USER
newgrp lxd

# Test LXD installation
lxc launch images:alpine/edge test
lxc exec test -- ping -c 3 google.com
lxc delete test --force
```

### Repository Setup

```bash
# Create workspace directory
mkdir -p $HOME/git
cd $HOME/git

# Clone repository
git clone https://github.com/robvogelaar/meta-cmf-raspberrypi-vcpe.git
cd meta-cmf-raspberrypi-vcpe

# Add to system PATH (optional but recommended)
echo 'export PATH="$HOME/git/meta-cmf-raspberrypi-vcpe/gen:$PATH"' >> ~/.bashrc
echo 'export PATH="$HOME/git/meta-cmf-raspberrypi-vcpe/probes/scripts:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Network Infrastructure Setup

```bash
# Initialize network bridges (required after each host reboot)
cd gen
./bridges.sh

# Verify bridge creation
lxc network list
ip link show type bridge
```

### Quick Environment Validation

```bash
# Test basic functionality
cd gen
source gen-util.sh
check_lxd_version

# Create a simple test environment
./genieacs.sh        # TR-069 ACS server
./bng.sh 7          # BNG for customer 7
./client-lan.sh vcpe-p1  # Test client on port 1

# Verify containers are running
lxc list
```

## Usage Workflows

### 1. Development Workflow

#### Building vCPE Images (Yocto)

```bash
# Set up Yocto build environment
source oe-init-build-env

# Add meta-cmf-raspberrypi-vcpe to bblayers.conf
bitbake-layers add-layer /path/to/meta-cmf-raspberrypi-vcpe

# Configure for vCPE target
echo 'MACHINE = "qemux86broadband"' >> conf/local.conf
echo 'IMAGE_FSTYPES += "lxc"' >> conf/local.conf

# Build vCPE container image
bitbake rdk-generic-broadband-image
```

#### Deploying Built Images

```bash
# Deploy built image to container
cd gen
./vcpe.sh user@build-host:/path/to/rdk-generic-broadband-image-qemux86broadband.lxc.tar.bz2

# Verify deployment
lxc list
lxc exec vcpe -- dmcli eRT getv Device.DeviceInfo.
```

### 2. Testing Workflow

#### Complete Test Environment Setup

```bash
cd gen

# Create infrastructure services
./genieacs.sh                    # TR-069 ACS
./oktopus.sh                     # USP controller
./webpa.sh                       # WebPA server

# Create network infrastructure
./bng.sh 7                       # ISP network simulation

# Deploy vCPE container
./vcpe.sh user@host:/path/to/image.lxc.tar.bz2

# Create test clients
./client-lan.sh vcpe-p1          # LAN client on port 1
./client-wlan.sh                 # WiFi client

# Set up testing framework
./automatics.sh                  # Automated testing
./boardfarm.sh                   # Hardware integration testing
```

#### Running Automated Tests

```bash
# Access Automatics web interface
echo "Automatics UI: http://$(lxc list automatics -c 4 --format csv | cut -d' ' -f1):8080/Automatics/"

# Run specific test cases
lxc exec automatics -- /opt/run-specific-test.sh TC-RDKB-WEBUI-1001

# Monitor test execution
lxc exec automatics -- tail -f /var/log/automatics/test-execution.log
```

### 3. Protocol Testing Workflows

#### TR-069 Testing

```bash
# Set up TR-069 environment
./genieacs.sh
./bng.sh 7
./vcpe.sh user@host:/path/to/image.lxc.tar.bz2

# Access GenieACS UI
echo "GenieACS UI: http://$(lxc list genieacs -c 4 --format csv | cut -d' ' -f1):3000"

# Verify TR-069 connection
lxc exec vcpe -- tail -f /rdklogs/logs/TR69Agent.log.txt.0
```

#### USP (TR-369) Testing

```bash
# Set up USP environment
./oktopus.sh
./bng.sh 9    # Customer 9 supports USP
./vcpe.sh user@host:/path/to/image.lxc.tar.bz2

# Access Oktopus UI
echo "Oktopus UI: http://$(lxc list oktopus -c 4 --format csv | cut -d' ' -f1):80"

# Monitor USP agent
lxc exec vcpe -- systemctl status usp-pa
lxc exec vcpe -- tail -f /rdklogs/logs/usp-pa.log.txt.0
```

#### WebPA Testing

```bash
# Set up WebPA environment
./webpa.sh
./vcpe.sh user@host:/path/to/image.lxc.tar.bz2

# Test WebPA API
webpa_ip=$(lxc list webpa -c 4 --format csv | cut -d' ' -f1)
curl -H 'Authorization:Basic dXNlcjEyMzp3ZWJwYUAxMjM0NTY3ODkw' \
     http://$webpa_ip:8080/api/v2/devices

# Get device parameters
device_id="mac:00163e08c00f"  # Replace with actual device MAC
curl -H 'Authorization:Basic dXNlcjEyMzp3ZWJwYUAxMjM0NTY3ODkw' \
     "http://$webpa_ip:9003/api/v2/device/$device_id/config?names=Device.DeviceInfo.ModelName"
```

## Development Guide

### Adding New Container Types

1. **Create Base Image Script** (if needed):
```bash
# Example: new-service-base.sh
#!/bin/bash
source gen-util.sh

container_name="new-service-base"
# Implementation using common functions
create_standard_container "ubuntu-22.04" "$container_name" "$profile_config"
# Install and configure service
install_common_packages "$container_name" "service-package"
# Publish as image
lxc publish "$container_name" --alias new-service-base
```

2. **Create Service Container Script**:
```bash
# Example: new-service.sh
#!/bin/bash
source gen-util.sh

ensure_base_image "new-service-base" "new-service-base.sh"
create_standard_container "new-service-base" "new-service" "$profile_config"
```

3. **Add Configuration Files** to `gen/configs/`:
```bash
# Add network configuration
new-service-50-cloud-init.yaml    # Netplan configuration
new-service.conf                  # Service configuration
```

4. **Document the Service** in README.md and API reference

### Extending Yocto Recipes

#### Adding New CCSP Components

```bash
# Create new recipe directory
mkdir -p recipes-ccsp/my-component

# Create recipe file
cat > recipes-ccsp/my-component/my-component.bbappend << 'EOF'
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Add custom patches
SRC_URI += "file://0001-my-custom-changes.patch"

# Custom configuration
do_install:append() {
    install -d ${D}${sysconfdir}/my-component
    install -m 644 ${WORKDIR}/my-config.conf ${D}${sysconfdir}/my-component/
}
EOF
```

#### Modifying Container Initialization

```bash
# Extend recipes-vcpe/vcpe/
SRC_URI += "file://my-custom-init.sh"

do_install:append() {
    install -m 755 ${WORKDIR}/my-custom-init.sh ${D}${systemd_unitdir}/scripts/
}
```

### Best Practices

1. **Use Common Functions**: Always source `gen-util.sh` and use standardized functions
2. **Follow Naming Conventions**: Use consistent container and profile naming
3. **Document Changes**: Update relevant documentation files
4. **Test Thoroughly**: Validate in clean environment before committing
5. **Resource Management**: Set appropriate limits for container resources

## Testing and Validation

### Container Health Monitoring

```bash
# System health check
cd gen
source gen-util.sh
./health-check.sh  # Custom script for comprehensive system check

# Individual container diagnostics
./diagnose-container.sh container-name

# Network connectivity testing
./test-network.sh
```

### Automated Test Execution

#### Automatics Framework

```bash
# Access test orchestration UI
automatics_ip=$(lxc list automatics -c 4 --format csv | cut -d' ' -f1)
echo "Open: http://$automatics_ip:8080/Automatics/login.htm"
echo "Credentials: admin / (blank)"

# Direct test execution
lxc exec automatics -- /opt/run-test-suite.sh RDKB_BASIC_TESTS

# View test results
lxc exec automatics -- cat /opt/automatics/test-results/latest-results.xml
```

#### Boardfarm Integration

```bash
# Hardware-in-the-loop testing
./boardfarm.sh
boardfarm_ip=$(lxc list boardfarm -c 4 --format csv | cut -d' ' -f1)

# Connect physical device for testing
sudo ip link set enx<usb-eth-adapter> master wan

# Run boardfarm tests
lxc exec boardfarm -- boardfarm -m test_suite.json
```

### Performance Testing

#### Resource Usage Monitoring

```bash
# Monitor container resource usage
lxc info --show-log container-name
lxc exec container-name -- top
lxc exec container-name -- free -h

# Network performance testing
lxc exec client-lan-vcpe-p1 -- iperf3 -c 10.0.0.1 -t 60
lxc exec vcpe -- iperf3 -s
```

#### Stress Testing

```bash
# Create multiple client containers
for i in {1..20}; do
    ./client-lan.sh test-client-$i-p$((i % 4 + 1))
done

# Monitor system performance
htop
iotop
netstat -i
```

## Troubleshooting

### Common Issues and Solutions

For comprehensive troubleshooting information, see **[gen/TROUBLESHOOTING.md](gen/TROUBLESHOOTING.md)**.

#### Quick Diagnostics

```bash
# Check LXD status
systemctl status lxd
lxc version

# Verify network bridges
ip link show type bridge
lxc network list

# Container connectivity test
lxc exec container-name -- ping -c 3 8.8.8.8

# Check container logs
lxc info --show-log container-name
lxc exec container-name -- journalctl -u service-name
```

#### Emergency Recovery

```bash
# Reset network configuration
sudo systemctl restart lxd
./bridges.sh

# Container recovery
lxc stop container-name --force
lxc start container-name

# Complete environment reset (USE WITH CAUTION)
./emergency-reset.sh  # See troubleshooting guide
```

### Log Analysis

```bash
# Collect RDK logs from vCPE
cd probes/scripts
./getrdklogs.sh vcpe

# Analyze collected logs
./parse-rssfree-log.py vcpe-logs/rssfree.log
./combine-logs.py vcpe-logs/
```

## Documentation

### Available Documentation

| Document | Purpose | Location |
|----------|---------|----------|
| **Project Overview** | This README | README.md |
| **Container Management** | Complete container orchestration guide | [gen/README.md](gen/README.md) |
| **API Reference** | Function library documentation | [gen/API-REFERENCE.md](gen/API-REFERENCE.md) |
| **Troubleshooting** | Common issues and solutions | [gen/TROUBLESHOOTING.md](gen/TROUBLESHOOTING.md) |
| **Documentation Index** | Navigation guide | [gen/DOCUMENTATION-INDEX.md](gen/DOCUMENTATION-INDEX.md) |

### Component-Specific Documentation

| Component | Documentation Location |
|-----------|----------------------|
| **Automatics** | [doc/automatics/README.md](doc/automatics/README.md) |
| **GenieACS** | [doc/genieacs/README.md](doc/genieacs/README.md) |
| **vCPE Containers** | [doc/vcpe/README.md](doc/vcpe/README.md) |
| **DAC (Deployment)** | [doc/dac/README.md](doc/dac/README.md) |

### Getting Help

1. **Check Documentation**: Start with relevant README files
2. **Review Troubleshooting**: Common solutions in troubleshooting guides
3. **Examine Examples**: Study existing container scripts for patterns
4. **Community Support**: Engage with RDK-B community forums
5. **Issue Reporting**: Submit issues via project repository

## Advanced Topics

### Multi-Customer Environments

```bash
# Deploy multiple customer configurations
./bng.sh 7    # Customer 7 - single VLAN
./bng.sh 9    # Customer 9 - multi-VLAN
./bng.sh 68   # Customer 68 - special configuration

# Deploy corresponding vCPE containers
./vcpe.sh user@host:/path/to/cust7-image.lxc.tar.bz2
mv vcpe vcpe-cust7
./vcpe.sh user@host:/path/to/cust9-image.lxc.tar.bz2
mv vcpe vcpe-cust9
```

### Physical Device Integration

```bash
# Connect physical CPE to container environment
sudo ip link set enx<adapter> master wan

# Monitor physical device connectivity
lxc exec bng-7 -- tcpdump -i eth1 host <cpe-mac-address>

# Configure physical device for container ACS
# Set TR-069 ACS URL to container IP:
# http://10.10.10.201:7547  (for GenieACS)
```

### CI/CD Integration

```bash
# Automated environment setup for CI
#!/bin/bash
set -e

# Environment setup
cd gen
./bridges.sh
./genieacs.sh
./bng.sh 7
./vcpe.sh "$BUILD_ARTIFACT_URL"

# Wait for services to be ready
sleep 60

# Run automated tests
lxc exec automatics -- /opt/run-ci-tests.sh

# Collect results
./getrdklogs.sh vcpe
./collect-test-results.sh

# Cleanup
./cleanup-environment.sh
```

## Contributing

### Development Workflow

1. **Fork Repository**: Create personal fork for development
2. **Create Feature Branch**: Use descriptive branch names
3. **Follow Standards**: Adhere to existing code and documentation patterns
4. **Test Changes**: Validate in clean environment
5. **Update Documentation**: Keep documentation current with changes
6. **Submit Pull Request**: Include comprehensive description of changes

### Code Standards

- **Shell Scripts**: Follow existing patterns in `gen/` directory
- **Yocto Recipes**: Use standard BitBake conventions
- **Documentation**: Use Markdown with clear structure
- **Container Profiles**: Follow resource allocation guidelines
- **Network Configuration**: Maintain IP allocation standards

## License

This project is licensed under the MIT License. See [COPYING.MIT](COPYING.MIT) for details.

## Support and Community

- **RDK Central**: [https://wiki.rdkcentral.com/](https://wiki.rdkcentral.com/)
- **RDK-B Documentation**: [https://wiki.rdkcentral.com/display/RDK/RDK-B](https://wiki.rdkcentral.com/display/RDK/RDK-B)
- **LXD Documentation**: [https://linuxcontainers.org/lxd/docs/master/](https://linuxcontainers.org/lxd/docs/master/)
- **Yocto Project**: [https://www.yoctoproject.org/](https://www.yoctoproject.org/)

---

**meta-cmf-raspberrypi-vcpe** provides a complete solution for RDK-B development, testing, and validation through sophisticated containerization and network simulation capabilities. Whether you're developing gateway software, validating protocol implementations, or testing interoperability scenarios, this project offers the tools and infrastructure needed for efficient and comprehensive broadband gateway development.