#!/bin/bash

# TDK Container Creation Script
# Creates a TDK instance from the base container and runs Docker image

set -e

source "$(dirname "$0")/gen-util.sh"

CONTAINER_NAME="tdk"
BASE_CONTAINER="tdk-base"
PROFILE="tdk"
IP_ADDRESS="10.10.10.30"
TDK_TAG="${1:-rdk-next}"

# Create TDK profile if it doesn't exist
create_tdk_profile() {
    if ! lxc profile list --format csv | grep -q "^${PROFILE},"; then
        echo "Creating TDK profile..."
        
        lxc profile create "${PROFILE}"
        
        cat << EOF | lxc profile edit "${PROFILE}"
config:
  limits.cpu: "4"
  limits.memory: 8GB
  security.nesting: "true"
  security.privileged: "true"
  user.user-data: |
    #cloud-config
    package_upgrade: false
    network:
      version: 2
      ethernets:
        eth0:
          addresses:
            - ${IP_ADDRESS}/24
          gateway4: 10.10.10.1
          nameservers:
            addresses:
              - 8.8.8.8
              - 8.8.4.4
    runcmd:
      - systemctl start docker
      - systemctl start supervisor
      - sleep 10
      - cd /opt/tdk/docker && docker build --build-arg tag_name=${TDK_TAG} . -t tdk-image --no-cache
      - docker run -d --name tdk-tm -p 8080:8080 -p 3306:3306 tdk-image
description: TDK Test Manager Profile
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
name: ${PROFILE}
used_by: []
EOF
    else
        echo "TDK profile already exists"
    fi
}

create_tdk_container() {
    echo "Creating TDK container from base..."
    
    # Check if container already exists
    if lxc list --format csv | grep -q "^${CONTAINER_NAME},"; then
        echo "Container ${CONTAINER_NAME} already exists. Stopping and deleting..."
        lxc stop "${CONTAINER_NAME}" --force || true
        lxc delete "${CONTAINER_NAME}" || true
    fi
    
    # Check if base image exists
    if ! lxc image list --format csv | grep -q "^${BASE_CONTAINER},"; then
        echo "Base image ${BASE_CONTAINER} not found. Creating..."
        
        # Create base container
        "$(dirname "$0")/tdk-base.sh"
        
        # Stop base container if running
        if lxc list --format csv | grep "^${BASE_CONTAINER}," | grep -q "RUNNING"; then
            echo "Stopping base container..."
            lxc stop "${BASE_CONTAINER}"
        fi
        
        # Export base container to image
        echo "Exporting base container to image..."
        lxc publish "${BASE_CONTAINER}" --alias "${BASE_CONTAINER}"
        
        # Delete base container
        echo "Removing base container..."
        lxc delete "${BASE_CONTAINER}"
    fi
    
    # Launch container from base image
    echo "Launching TDK container from base image..."
    lxc launch "${BASE_CONTAINER}" "${CONTAINER_NAME}"
    
    # Apply profile
    lxc profile add "${CONTAINER_NAME}" "${PROFILE}"
    
    # Copy Docker files to container
    copy_docker_files

    lxc file push "$M_ROOT/gen/configs/tdk-50-cloud-init.yaml" "${CONTAINER_NAME}/etc/netplan/50-cloud-init.yaml" --uid 0 --gid 0 --mode 600
    # Applying static ip configuration
    lxc exec "${CONTAINER_NAME}" -- netplan apply

    # Wait for container to be ready
    wait_for_container "${CONTAINER_NAME}"
    
    # Build and run Docker image
    build_and_run_docker
    
    # Wait for TDK to be ready
    wait_for_tdk_ready
}

copy_docker_files() {
    echo "Copying Docker files to container..."
    
    # Create Docker directory in container
    lxc exec "${CONTAINER_NAME}" -- mkdir -p /opt/tdk/docker
    
    # Copy all TDK Docker files
    local tdk_config_dir="$(dirname "$0")/configs/tdk"
    
    lxc file push "${tdk_config_dir}/Dockerfile" "${CONTAINER_NAME}/opt/tdk/docker/"
    lxc file push "${tdk_config_dir}/mysqld.cnf" "${CONTAINER_NAME}/opt/tdk/docker/"
    lxc file push "${tdk_config_dir}/tomcat7" "${CONTAINER_NAME}/opt/tdk/docker/"
    lxc file push "${tdk_config_dir}/run_tomcat_mysql.sh" "${CONTAINER_NAME}/opt/tdk/docker/"
    lxc file push "${tdk_config_dir}/war_creation_generic.py" "${CONTAINER_NAME}/opt/tdk/docker/"
    
    # Make scripts executable
    lxc exec "${CONTAINER_NAME}" -- chmod +x /opt/tdk/docker/tomcat7
    lxc exec "${CONTAINER_NAME}" -- chmod +x /opt/tdk/docker/run_tomcat_mysql.sh
    lxc exec "${CONTAINER_NAME}" -- chmod +x /opt/tdk/docker/war_creation_generic.py
}

build_and_run_docker() {
    echo "Building TDK Docker image (this may take 20-30 minutes)..."

    lxc exec "${CONTAINER_NAME}" -- systemctl start docker
    lxc exec "${CONTAINER_NAME}" -- systemctl start supervisor
    lxc exec "${CONTAINER_NAME}" -- sleep 10

    
    # Build Docker image
    lxc exec "${CONTAINER_NAME}" -- bash -c "cd /opt/tdk/docker && docker build --build-arg tag_name=${TDK_TAG} . -t tdk-image --no-cache" || {
        echo "Docker build failed. Checking logs..."
        lxc exec "${CONTAINER_NAME}" -- docker logs
        exit 1
    }
    
    echo "Starting TDK Docker container..."
    
    # Run Docker container
    lxc exec "${CONTAINER_NAME}" -- docker run -d \
        --name tdk-tm \
        -p 8080:8080 \
        -p 3306:3306 \
        --restart unless-stopped \
        tdk-image
    
    # Wait for Docker container to start
    sleep 30
    
    # Check if Docker container is running
    if ! lxc exec "${CONTAINER_NAME}" -- docker ps | grep -q "tdk-tm"; then
        echo "TDK Docker container failed to start"
        lxc exec "${CONTAINER_NAME}" -- docker logs tdk-tm
        exit 1
    fi
}

wait_for_tdk_ready() {
    echo "Waiting for TDK Test Manager to be ready..."
    
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        echo "Checking TDK availability... (attempt $attempt/$max_attempts)"
        
        if curl -s -o /dev/null -w "%{http_code}" "http://${IP_ADDRESS}:8080/rdk-test-tool" | grep -q "200\|302"; then
            echo "TDK Test Manager is accessible!"
            break
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            echo "TDK Test Manager failed to start within expected time"
            echo "Check Docker logs with: lxc exec ${CONTAINER_NAME} -- docker logs tdk-tm"
            exit 1
        fi
        
        sleep 10
        ((attempt++))
    done
}

configure_firewall() {
    echo "Configuring firewall rules for TDK..."
    
    # Allow HTTP access to TDK
    lxc exec "${CONTAINER_NAME}" -- ufw allow 8080/tcp || true
    
    # Allow MySQL access (internal)
    lxc exec "${CONTAINER_NAME}" -- ufw allow 3306/tcp || true
}

display_access_info() {
    echo ""
    echo "============================================"
    echo "TDK Container Created Successfully!"
    echo "============================================"
    echo ""
    echo "Access Information:"
    echo "  URL: http://${IP_ADDRESS}:8080/rdk-test-tool"
    echo "  Container: ${CONTAINER_NAME}"
    echo "  TDK Version: ${TDK_TAG}"
    echo ""
    echo "Database Information:"
    echo "  Type: MySQL"
    echo "  Host: ${IP_ADDRESS}"
    echo "  Port: 3306"
    echo "  Database: rdktesttoolproddb"
    echo "  Username: rdktesttooluser"
    echo "  Password: 6dktoolus3r!"
    echo ""
    echo "Default TDK Credentials:"
    echo "  Username: admin"
    echo "  Password: admin"
    echo ""
    echo "Container Management:"
    echo "  Start:   lxc start ${CONTAINER_NAME}"
    echo "  Stop:    lxc stop ${CONTAINER_NAME}"
    echo "  Shell:   lxc exec ${CONTAINER_NAME} bash"
    echo ""
    echo "Docker Container Management (inside LXC):"
    echo "  View logs:    lxc exec ${CONTAINER_NAME} -- docker logs tdk-tm"
    echo "  Stop Docker:  lxc exec ${CONTAINER_NAME} -- docker stop tdk-tm"
    echo "  Start Docker: lxc exec ${CONTAINER_NAME} -- docker start tdk-tm"
    echo "  Rebuild:      lxc exec ${CONTAINER_NAME} -- docker build --build-arg tag_name=<TAG> /opt/tdk/docker -t tdk-image"
    echo ""
    echo "For SSH tunnel access:"
    echo "  ssh -L 8080:${IP_ADDRESS}:8080 user@host"
    echo "  Then access: http://localhost:8080/rdk-test-tool"
    echo ""
    echo "Integration with vCPE:"
    echo "  - Execute test cases on vCPE devices"
    echo "  - Manage test suites and results"
    echo "  - Generate test reports"
    echo "  - Integrate with CI/CD pipelines"
    echo ""
}

main() {
    echo "Starting TDK container creation..."
    echo "TDK Version: ${TDK_TAG}"
    echo "Note: This process will take 20-30 minutes due to Docker image building"
    
    check_lxd_running
    
    create_tdk_profile
    create_tdk_container
    configure_firewall
    
    display_access_info
}

main "$@"
