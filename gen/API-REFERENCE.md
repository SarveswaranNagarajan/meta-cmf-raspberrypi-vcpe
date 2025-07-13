# LXD Container Management API Reference

## Overview

This document provides a comprehensive reference for all functions available in the `gen-util.sh` library. These functions provide a high-level API for managing LXD containers in the RDK-B testing environment.

## Function Categories

- [System Validation Functions](#system-validation-functions)
- [Container Lifecycle Management](#container-lifecycle-management)
- [Network Configuration Functions](#network-configuration-functions)
- [Service Management Functions](#service-management-functions)
- [File and Utility Functions](#file-and-utility-functions)
- [High-Level Container Creation](#high-level-container-creation)
- [Legacy Functions](#legacy-functions)

## System Validation Functions

### `check_lxd_version()`

Verifies LXD installation and version compatibility.

**Syntax:**
```bash
check_lxd_version
```

**Parameters:** None

**Returns:** 
- `0` if LXD is compatible (version 4.x or 5.x)
- Exits with `1` if LXD is not found or incompatible

**Example:**
```bash
check_lxd_version
```

---

### `check_network(container_name)`

Tests network connectivity for a container by pinging 8.8.8.8.

**Syntax:**
```bash
check_network "container_name"
```

**Parameters:**
- `container_name` (string): Name of container to test

**Returns:** 
- `0` if network is working
- Exits with `1` if max attempts (10) reached

**Example:**
```bash
check_network "web-server"
```

---

### `check_devuan_chimaera()`

Ensures the Devuan Chimaera base image is available, downloading if necessary.

**Syntax:**
```bash
check_devuan_chimaera
```

**Parameters:** None

**Returns:** `0` on success, non-zero on failure

**Side Effects:** Downloads and imports image if not present

**Example:**
```bash
check_devuan_chimaera
```

## Container Lifecycle Management

### `create_container_profile(profile_name, [profile_config])`

Creates or updates an LXD container profile.

**Syntax:**
```bash
create_container_profile "profile_name" ["profile_config"]
```

**Parameters:**
- `profile_name` (string): Name for the profile
- `profile_config` (string, optional): YAML configuration content

**Returns:** `0` on success, non-zero on failure

**Example:**
```bash
profile_config='name: test
config:
  limits.memory: "512MB"
devices:
  eth0:
    type: nic
    nictype: bridged
    parent: lxdbr1'
create_container_profile "test-profile" "$profile_config"
```

---

### `delete_container(container_name)`

Safely deletes an LXD container, stopping it if necessary.

**Syntax:**
```bash
delete_container "container_name"
```

**Parameters:**
- `container_name` (string): Name of container to delete

**Returns:** `0` (always succeeds, even if container doesn't exist)

**Example:**
```bash
delete_container "old-container"
```

---

### `ensure_base_image(image_name, [script_path])`

Checks if a base image exists, optionally creating it with a script.

**Syntax:**
```bash
ensure_base_image "image_name" ["script_path"]
```

**Parameters:**
- `image_name` (string): Name of image to check
- `script_path` (string, optional): Script to run if image doesn't exist

**Returns:** `0` on success, non-zero if script fails

**Example:**
```bash
ensure_base_image "ubuntu-base" "create-ubuntu-base.sh"
ensure_base_image "my-app-base"  # Just check, don't create
```

---

### `launch_container(image_name, container_name, [profile_name])`

Launches a new container from an image with optional profile.

**Syntax:**
```bash
launch_container "image_name" "container_name" ["profile_name"]
```

**Parameters:**
- `image_name` (string): Base image to use
- `container_name` (string): Name for new container
- `profile_name` (string, optional): Profile to apply (defaults to container_name)

**Returns:** `0` on success, non-zero on failure

**Example:**
```bash
launch_container "ubuntu-22.04" "web-server" "web-profile"
```

---

### `restart_container(container_name)`

Restarts a container.

**Syntax:**
```bash
restart_container "container_name"
```

**Parameters:**
- `container_name` (string): Name of container to restart

**Returns:** `0` on success, non-zero on failure

**Example:**
```bash
restart_container "web-server"
```

## Network Configuration Functions

### `setup_static_network(container_name, netplan_file)`

Applies a netplan configuration file to a container.

**Syntax:**
```bash
setup_static_network "container_name" "netplan_file"
```

**Parameters:**
- `container_name` (string): Target container name
- `netplan_file` (string): Path to netplan YAML file

**Returns:** `0` on success, non-zero on failure

**Example:**
```bash
setup_static_network "web-server" "/configs/static-ip.yaml"
```

---

### `add_common_routes(container_name)`

Adds standard RDK-B routing rules to a container.

**Syntax:**
```bash
add_common_routes "container_name"
```

**Parameters:**
- `container_name` (string): Container to configure

**Returns:** `0` on success, non-zero on failure

**Routes Added:**
- IPv4: `10.107.200.0/24` via `10.10.10.107`
- IPv6: `2001:dae:7:1::/64` via `2001:dbf:0:1::107`

**Example:**
```bash
add_common_routes "test-container"
```

---

### `setup_container_alias(container_name)`

Sets up a convenient shell alias in the container.

**Syntax:**
```bash
setup_container_alias "container_name"
```

**Parameters:**
- `container_name` (string): Container to configure

**Returns:** `0` on success, non-zero on failure

**Alias Created:** `c` = `clear && printf "\033[3J\033[0m"`

**Example:**
```bash
setup_container_alias "web-server"
```

## Service Management Functions

### `install_common_packages(container_name, packages...)`

Installs packages in a container using apt-get.

**Syntax:**
```bash
install_common_packages "container_name" "package1" "package2" ...
```

**Parameters:**
- `container_name` (string): Target container
- `packages` (strings): One or more package names

**Returns:** `0` on success, non-zero on failure

**Example:**
```bash
install_common_packages "web-server" "nginx" "curl" "vim"
```

---

### `create_systemd_service(container_name, service_name, service_content)`

Creates and enables a systemd service in a container.

**Syntax:**
```bash
create_systemd_service "container_name" "service_name" "service_content"
```

**Parameters:**
- `container_name` (string): Target container
- `service_name` (string): Service name (without .service extension)
- `service_content` (string): Complete systemd unit file content

**Returns:** `0` on success, non-zero on failure

**Example:**
```bash
service_content='[Unit]
Description=My Web Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /app/server.py
Restart=always

[Install]
WantedBy=multi-user.target'

create_systemd_service "web-server" "my-web-service" "$service_content"
```

---

### `start_systemd_service(container_name, service_name)`

Starts a systemd service in a container.

**Syntax:**
```bash
start_systemd_service "container_name" "service_name"
```

**Parameters:**
- `container_name` (string): Target container
- `service_name` (string): Service name (without .service extension)

**Returns:** `0` on success, non-zero on failure

**Example:**
```bash
start_systemd_service "web-server" "nginx"
```

## File and Utility Functions

### `copy_config_file(source_file, container_name, dest_path, [mode], [uid], [gid])`

Copies a file to a container with specified permissions.

**Syntax:**
```bash
copy_config_file "source_file" "container_name" "dest_path" ["mode"] ["uid"] ["gid"]
```

**Parameters:**
- `source_file` (string): Path to source file on host
- `container_name` (string): Target container name
- `dest_path` (string): Absolute destination path in container
- `mode` (string, optional): File permissions (default: "644")
- `uid` (string, optional): Owner UID (default: "0")
- `gid` (string, optional): Owner GID (default: "0")

**Returns:** `0` on success, non-zero on failure

**Example:**
```bash
copy_config_file "/host/nginx.conf" "web-server" "/etc/nginx/nginx.conf" "644"
copy_config_file "/host/script.sh" "web-server" "/usr/local/bin/script.sh" "755"
```

---

### `wait_for_container_ready(container_name, [max_attempts])`

Waits for a container to complete its initialization.

**Syntax:**
```bash
wait_for_container_ready "container_name" [max_attempts]
```

**Parameters:**
- `container_name` (string): Container to wait for
- `max_attempts` (integer, optional): Maximum seconds to wait (default: 30)

**Returns:** `0` when ready, warns if timeout reached

**Example:**
```bash
wait_for_container_ready "web-server" 60  # Wait up to 60 seconds
wait_for_container_ready "quick-container"  # Use default 30 second timeout
```

## High-Level Container Creation

### `create_standard_container(image_name, container_name, profile_config, [netplan_file], [setup_alias])`

Creates a complete container with standard configuration.

**Syntax:**
```bash
create_standard_container "image_name" "container_name" "profile_config" ["netplan_file"] ["setup_alias"]
```

**Parameters:**
- `image_name` (string): Base image to use
- `container_name` (string): Name for new container
- `profile_config` (string): LXD profile configuration in YAML
- `netplan_file` (string, optional): Path to network configuration
- `setup_alias` (boolean, optional): Whether to setup shell aliases (default: true)

**Returns:** `0` on success, non-zero on failure

**Workflow:**
1. Deletes existing container
2. Creates profile with configuration
3. Launches container
4. Sets up aliases (if enabled)
5. Applies network configuration (if provided)
6. Waits for container to be ready

**Example:**
```bash
profile_config='name: web-server
description: "Web server container"
config:
  boot.autostart: "false"
  limits.memory: "1GB"
  limits.cpu: "2"
devices:
  eth0:
    name: eth0
    nictype: bridged
    parent: lxdbr1
    type: nic
  root:
    path: /
    pool: default
    type: disk'

create_standard_container "ubuntu-22.04" "web-server" "$profile_config" "/configs/web-static.yaml"
```

---

### `create_client_container(container_name, port, [vlan], [memory_limit], [cpu_limit])`

Creates a specialized lightweight client container for testing.

**Syntax:**
```bash
create_client_container "container_name" "port" ["vlan"] ["memory_limit"] ["cpu_limit"]
```

**Parameters:**
- `container_name` (string): Name for new container
- `port` (string): LAN port number (1-4)
- `vlan` (string, optional): VLAN ID (default: "100")
- `memory_limit` (string, optional): Memory limit (default: "128MB")
- `cpu_limit` (string, optional): CPU limit (default: "1")

**Returns:** `0` on success, non-zero on failure

**Features:**
- Uses Alpine-based client-base image
- Connects to `lan-p{port}` bridge
- Configured with VLAN tagging
- Optimized resource limits for client devices

**Example:**
```bash
create_client_container "client-test-p1" "1" "200" "256MB" "2"
create_client_container "simple-client" "2"  # Use defaults
```

## Legacy Functions

These functions provide compatibility with existing scripts and specialized functionality:

### `validate_and_hash(input_string)`

Validates and generates hash for RDK-B device naming conventions.

**Syntax:**
```bash
hash=$(validate_and_hash "mv1-r21-7-001")
```

**Returns:** Hash value (1001-3129) or -1 if invalid

---

### `hash_to_string(hash_value)`

Converts a hash back to RDK-B device string format.

**Syntax:**
```bash
device_string=$(hash_to_string "1234")
```

---

### `validate_container_name(name)`

Validates container name against RDK-B naming conventions.

**Syntax:**
```bash
if validate_container_name "mv1-r21-7"; then
    echo "Valid name"
fi
```

---

### `generate_mac1(container_name)` / `generate_mac2(container_name)`

Generate deterministic MAC addresses for containers.

**Syntax:**
```bash
mac1=$(generate_mac1 "container-name")
mac2=$(generate_mac2 "container-name")
```

---

### Network Bridge Management Functions

- `check_and_create_lxdbr1()` - Main bridge setup
- `check_and_create_wan_bridge(bridge_name)` - WAN bridge creation
- `check_and_create_lan_bridge(bridge_name)` - LAN bridge with VLAN support
- `check_and_create_virt_wlan()` - Virtual WLAN interface setup

## Error Handling

All functions return standard exit codes:
- `0`: Success
- `1`: General failure
- `>1`: Specific error codes (function-dependent)

Some functions may exit the script entirely on critical failures (e.g., LXD not available).

## Best Practices

### Function Usage Patterns

1. **Always check dependencies first:**
```bash
source gen-util.sh
check_lxd_version
```

2. **Use high-level functions when possible:**
```bash
# Preferred
create_standard_container "ubuntu-22.04" "my-app" "$profile_config"

# Instead of manual steps
delete_container "my-app"
create_container_profile "my-app" "$profile_config"
launch_container "ubuntu-22.04" "my-app"
# ... etc
```

3. **Handle base image dependencies:**
```bash
ensure_base_image "my-app-base" "create-my-app-base.sh"
create_standard_container "my-app-base" "my-app" "$profile_config"
```

4. **Use proper error handling:**
```bash
if ! create_standard_container "$image" "$container" "$config"; then
    echo "Failed to create container"
    exit 1
fi
```

### Profile Configuration Guidelines

Profile configurations should follow this structure:

```yaml
name: container-name
description: "Brief description"
config:
  boot.autostart: "false"
  limits.memory: "512MB"
  limits.cpu: "1"
devices:
  eth0:
    name: eth0
    nictype: bridged
    parent: lxdbr1
    type: nic
  root:
    path: /
    pool: default
    type: disk
    size: "2GiB"  # Optional size limit
```

### Network Configuration Best Practices

1. **Use static IPs for services:**
```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 10.10.10.200/24
      gateway4: 10.10.10.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
```

2. **Apply routes after network configuration:**
```bash
setup_static_network "$container" "$netplan_file"
add_common_routes "$container"
```

## Migration Guide

### Converting Existing Scripts

Replace common patterns with utility functions:

**Before:**
```bash
lxc delete my-container -f 2>/dev/null
if lxc profile list --format csv | grep -q "^my-container"; then
    lxc profile delete my-container 1> /dev/null
fi
lxc profile copy default my-container
cat << EOF | lxc profile edit my-container
# profile config
EOF
lxc launch my-image my-container -p my-container
```

**After:**
```bash
source gen-util.sh
profile_config='# profile config'
create_standard_container "my-image" "my-container" "$profile_config"
```

### Gradual Migration Strategy

1. Start by sourcing `gen-util.sh` in existing scripts
2. Replace container deletion with `delete_container()`
3. Replace profile creation with `create_container_profile()`
4. Replace file copying with `copy_config_file()`
5. Finally, use `create_standard_container()` for new containers

This incremental approach ensures existing functionality remains intact while improving maintainability.