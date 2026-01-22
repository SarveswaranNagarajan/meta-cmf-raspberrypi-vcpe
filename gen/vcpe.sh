#!/bin/bash

source gen-util.sh

# Defaults
wan_bridge="wan"
lan_bridge="lan-p1"

# Need at least image
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <image> [suffix] [-b|--wan-bridge <bridge>] [-l|--lan-bridge <bridge>]"
    echo "Example: $0 image.tar.bz2 001"
    echo "Example: $0 image.tar.bz2 001 -b br-wan106 -l br-lan206"
    echo "  Creates container: vcpe-001, profile: vcpe-001, volume: vcpe-001-nvram"
    echo "Options:"
    echo "  -b, --wan-bridge <bridge>  Bridge for WAN interface (default: wan)"
    echo "  -l, --lan-bridge <bridge>  Bridge for LAN interface (default: lan-p1)"
    exit 1
fi

# First arg is always image
imagefile="$1"
shift

# Second arg is suffix if it doesn't start with '-'
suffix=""
if [ $# -gt 0 ] && [[ ! "$1" == -* ]]; then
    suffix="$1"
    shift
fi

# Parse remaining named options
while [ $# -gt 0 ]; do
    case "$1" in
        -b|--wan-bridge)
            wan_bridge="$2"
            shift 2
            ;;
        -l|--lan-bridge)
            lan_bridge="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate suffix format if provided (must be 001-099)
if [ -n "$suffix" ]; then
    if ! [[ "$suffix" =~ ^0[0-9]{2}$ ]]; then
        echo "Error: Suffix must be in the format 001-099 (three digits starting with 0)"
        echo "Examples: 001, 002, 010, 099"
        exit 1
    fi

    # Convert to numeric value for offset calculation
    offset=$((10#$suffix))

    # Validate range
    if [ $offset -lt 1 ] || [ $offset -gt 99 ]; then
        echo "Error: Suffix must be between 001 and 099"
        exit 1
    fi
fi

# Check if imagefile matches SCP URL pattern (user@host:path or host:path)
# Skip if it's clearly a local path (starts with /, ./, or ../)
if [[ ! $imagefile =~ ^\.?\.?/ ]] && [[ $imagefile =~ ^([^@/:]+@)?[a-zA-Z0-9][-a-zA-Z0-9.]*:.+ ]]; then
    mkdir -p ./tmp
    # Extract filename from path
    filename="${imagefile##*/}"
    if ! scp "$imagefile" "./tmp/$filename"; then
        echo "SCP download failed"
        exit 1
    fi
    imagefile="./tmp/$filename"
fi

# Verify file exists
if [ ! -f "$imagefile" ]; then
    echo "Error: File not found: $imagefile"
    exit 1
fi

#
imagename="${imagefile##*/}"; imagename="${imagename%.tar.bz2}"

# Build names with optional suffix
if [ -n "$suffix" ]; then
    containername="vcpe-${suffix}"
    profilename="vcpe-${suffix}"
else
    containername="vcpe"
    profilename="vcpe"
fi
volumename="${containername}-nvram"

# Generate unique MAC addresses and VLAN based on suffix
if [ -n "$suffix" ]; then
    # Offset was already calculated and validated above

    # Generate unique MAC addresses by adding offset to last octet
    eth0_last_octet=$((0x68 + offset))
    eth1_last_octet=$((0x7c + offset))

    # Format MAC addresses
    eth0_mac=$(printf "00:16:3e:20:79:%02x" $eth0_last_octet)
    eth1_mac=$(printf "00:16:3e:16:5f:%02x" $eth1_last_octet)

    # VLAN ID: 100 + offset (101-199)
    vlan_id=$((100 + offset))
else
    # Default MAC addresses and VLAN for base vcpe container
    eth0_mac="00:16:3e:20:79:68"
    eth1_mac="00:16:3e:16:5f:7c"
    vlan_id=100
fi

#
lxc delete ${containername} -f 2>/dev/null


# Add VLAN to bridge (only for default lan-p* bridges)
if [[ $lan_bridge == lan-p* ]]; then
    sudo bridge vlan add vid $vlan_id dev $lan_bridge self
fi

# Create virtual wlan interfaces
check_and_create_virt_wlan "$suffix"

# Nvram
if ! lxc storage volume show default $volumename > /dev/null 2>&1; then
    lxc storage volume create default $volumename size=4MiB
fi

# Import image - always overwrite
lxc image delete ${imagename} 2>/dev/null
lxc image import $imagefile --alias ${imagename} 2>/dev/null || {
    # Same fingerprint exists - delete rdkb images and retry
    lxc image list --format=csv | grep rdkb | cut -d, -f2 | xargs -r -n1 lxc image delete 2>/dev/null || true
    lxc image import $imagefile --alias ${imagename}
}

# Profile - always use base vcpe.yaml as template
lxc profile create "$profilename" 2>/dev/null || true
lxc profile edit "$profilename" < "$M_ROOT/gen/profiles/vcpe.yaml"

# Remove wlan devices from profile (we'll add them back with correct parent names)
for i in {0..3}; do
    lxc profile device remove "$profilename" "wlan${i}" > /dev/null 2>&1 || true
done

# eth0 interface
lxc profile device add "$profilename" eth0 nic \
    nictype=bridged \
    parent=$wan_bridge \
    hwaddr=$eth0_mac \
    name=eth0 \
    > /dev/null

# eth1 interface
if [[ $lan_bridge == lan-p* ]]; then
    lxc profile device add "$profilename" eth1 nic \
        nictype=bridged \
        parent=$lan_bridge \
        hwaddr=$eth1_mac \
        name=eth1 \
        vlan=$vlan_id \
        > /dev/null
else
    lxc profile device add "$profilename" eth1 nic \
        nictype=bridged \
        parent=$lan_bridge \
        hwaddr=$eth1_mac \
        name=eth1 \
        > /dev/null
fi


# Attach nvram volume to profile
lxc profile device add "$profilename" nvram disk \
    source=$volumename \
    path=/nvram \
    > /dev/null 2>&1 || true

# Add wlan interfaces with appropriate parent names
if [ -n "$suffix" ]; then
    # Add wlan interfaces with suffix
    for i in {0..3}; do
        lxc profile device add "$profilename" "wlan${i}" nic \
            nictype=physical \
            parent="virt-wlan${i}-${suffix}" \
            name="wlan${i}" \
            type=nic \
            > /dev/null 2>&1 || true
    done
else
    # Add standard wlan interfaces for base vcpe (virt-wlan1-4, since virt-wlan0 is for client)
    for i in {0..3}; do
        lxc profile device add "$profilename" "wlan${i}" nic \
            nictype=physical \
            parent="virt-wlan$((i + 1))" \
            name="wlan${i}" \
            type=nic \
            > /dev/null 2>&1 || true
    done
fi

# Initialize the container without starting it
lxc init ${imagename} ${containername} -p ${profilename}

# Set container environment variables (persist across stop/start/reboot)
lxc config set ${containername} environment.CREATION_DATE="$(date +"%Y-%m-%d_%H:%M:%S")"
lxc config set ${containername} environment.SERIAL_NUMBER="$(echo ${eth0_mac//:/} | tr '[:lower:]' '[:upper:]')"
lxc config set ${containername} environment.HARDWARE_VERSION="1.0"

# Start the container
lxc start ${containername}
