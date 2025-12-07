#!/bin/bash

# TDK Base Container Creation Script
# Creates a base Ubuntu 20.04 container with Docker and TDK prerequisites

set -e

source "$(dirname "$0")/gen-util.sh"

CONTAINER_NAME="tdk-base"
IMAGE_ALIAS="ubuntu/24.04"
DOCKER_VERSION="24.0.7"

create_tdk_base_container() {
    echo "Creating TDK base container..."
    
    # Check if container already exists
    if lxc list --format csv | grep -q "^${CONTAINER_NAME},"; then
        echo "Container ${CONTAINER_NAME} already exists. Stopping and deleting..."
        lxc stop "${CONTAINER_NAME}" --force || true
        lxc delete "${CONTAINER_NAME}" || true
    fi
    
    # Launch base container
    echo "Launching Ubuntu 20.04 container..."
    lxc launch "${IMAGE_ALIAS}" "${CONTAINER_NAME}" -c security.nesting=true
    
    # Wait for container to be ready
    wait_for_container "${CONTAINER_NAME}"
    
    # Set non-interactive environment
    echo "Setting non-interactive environment..."
    lxc exec "${CONTAINER_NAME}" -- bash -c "echo 'export DEBIAN_FRONTEND=noninteractive' >> /etc/environment"
    lxc exec "${CONTAINER_NAME}" -- bash -c "ln -fs /usr/share/zoneinfo/UTC /etc/localtime"
    lxc exec "${CONTAINER_NAME}" -- bash -c "echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections"
    
    # Update system
    echo "Updating system packages..."
    lxc exec "${CONTAINER_NAME}" -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get update"
    lxc exec "${CONTAINER_NAME}" -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y"
    
    # Install Docker prerequisites
    echo "Installing Docker prerequisites..."
    lxc exec "${CONTAINER_NAME}" -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common"
    
    # Install Docker
    install_docker
    
    # Install additional tools
    install_additional_tools
    
    # Configure Docker
    configure_docker
    
    # Create TDK directory structure
    setup_tdk_directories
    
    echo "TDK base container created successfully"
}

install_docker() {
    echo "Installing Docker..."
    
    # Add Docker's official GPG key
    lxc exec "${CONTAINER_NAME}" -- mkdir -m 0755 -p /etc/apt/keyrings
    lxc exec "${CONTAINER_NAME}" -- curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        lxc exec "${CONTAINER_NAME}" -- gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    lxc exec "${CONTAINER_NAME}" -- sh -c 'echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null'
    
    # Update package index and install Docker
    lxc exec "${CONTAINER_NAME}" -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get update"
    lxc exec "${CONTAINER_NAME}" -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin"
    
    # Enable and start Docker
    lxc exec "${CONTAINER_NAME}" -- systemctl enable docker
    lxc exec "${CONTAINER_NAME}" -- systemctl start docker
}

install_additional_tools() {
    echo "Installing additional tools for TDK..."
    
    lxc exec "${CONTAINER_NAME}" -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y \
        git \
        wget \
        curl \
        vim \
        nano \
        htop \
        net-tools \
        iputils-ping \
        python3 \
        python3-pip \
        build-essential \
        supervisor"
}

configure_docker() {
    echo "Configuring Docker..."
    
    # Configure Docker daemon
    cat << 'EOF' | lxc exec "${CONTAINER_NAME}" -- tee /etc/docker/daemon.json
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "dns": ["8.8.8.8", "8.8.4.4"]
}
EOF
    
    # Restart Docker to apply configuration
    lxc exec "${CONTAINER_NAME}" -- systemctl restart docker
}

setup_tdk_directories() {
    echo "Setting up TDK directories..."
    
    # Create TDK directories
    lxc exec "${CONTAINER_NAME}" -- mkdir -p /opt/tdk
    lxc exec "${CONTAINER_NAME}" -- mkdir -p /opt/tdk/docker
    lxc exec "${CONTAINER_NAME}" -- mkdir -p /opt/tdk/config
    lxc exec "${CONTAINER_NAME}" -- mkdir -p /opt/tdk/logs
    lxc exec "${CONTAINER_NAME}" -- mkdir -p /opt/tdk/data
}

main() {
    echo "Starting TDK base container creation..."
    echo "Note: This container requires nesting support for Docker"
    
    check_lxd_running
    
    create_tdk_base_container
    
    # Stop the base container
    echo "Stopping base container..."
    lxc stop "${CONTAINER_NAME}"
    
    # Export base container to image
    echo "Exporting base container to image..."
    # Remove existing image if it exists
    if lxc image list --format csv | grep -q "${CONTAINER_NAME}"; then
        echo "Removing existing ${CONTAINER_NAME} image..."
        lxc image delete "${CONTAINER_NAME}"
    fi
    lxc publish "${CONTAINER_NAME}" --alias "${CONTAINER_NAME}"
    
    # Delete base container
    echo "Removing base container..."
    lxc delete "${CONTAINER_NAME}"
    
    echo "TDK base container setup complete!"
    echo "You can now create TDK instances using tdk.sh"
}

main "$@"
