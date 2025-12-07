#!/bin/bash

source gen-util.sh

if [ -z "${1}" ]; then
    echo "Please provide a mv to connect to, including the lan port number"
    echo "e.g. vcpe-p1/2/3/4"
    exit 1
fi

if [[ "${1}" =~ -p([1-4])$ ]]; then
    port="${BASH_REMATCH[1]}"
    trimmed="${1%-p[1-4]}"
else
    echo "Error, Must end with -p1 through -p4"
    exit 1
fi


container_name="client-lan-${1}"
profile_name="$container_name"

# Fix me : determine vlan id based of vcpe instance
vlan=100

# create client-base image if not exist
if ! lxc image list | grep -q "client-base"; then
    echo "Creating client-base image"
    client-base.sh
fi


# Delete existing container, and profile
lxc delete -f "${container_name}" > /dev/null 2>&1
lxc profile delete "${profile_name}" > /dev/null 2>&1


# Create new profile and configure
lxc profile create "${profile_name}" >/dev/null 2>&1 || true

lxc profile set "${profile_name}" boot.autostart false
lxc profile set "${profile_name}" limits.memory=128MB
lxc profile set "${profile_name}" limits.cpu=1

lxc profile device remove "${profile_name}" eth0 >/dev/null 2>&1 || true
lxc profile device remove "${profile_name}" root >/dev/null 2>&1 || true

lxc profile device add "${profile_name}" eth0 nic nictype=bridged "parent=lan-p${port}" "vlan=${vlan}" 1> /dev/null
lxc profile device add "${profile_name}" root disk path=/ pool=default 1> /dev/null

# Launch container using client-base image
lxc launch "client-base" "${container_name}" "--profile=${profile_name}"
