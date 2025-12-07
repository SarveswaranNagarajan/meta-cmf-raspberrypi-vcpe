#!/bin/bash


check_lxd_running() {
    if ! command -v lxd &> /dev/null; then
        echo "Error: LXD is not installed."
        exit 1
    fi
    
    # Check if LXD is running via systemd or snap
    if ! (systemctl is-active --quiet lxd || systemctl is-active --quiet snap.lxd.daemon); then
        # Test LXD connectivity as fallback
        if ! lxc list &> /dev/null; then
            echo "Error: LXD service is not running or not accessible."
            exit 1
        fi
    fi
    
    # Final connectivity test
    if ! lxc list &> /dev/null; then
        echo "Error: Cannot connect to LXD. Please check LXD configuration."
        exit 1
    fi
}

wait_for_container() {
    local container_name="$1"
    local max_attempts=30
    local attempt=1
    
    echo "Waiting for container ${container_name} to be ready..."
    
    while [[ $attempt -le $max_attempts ]]; do
        if lxc exec "${container_name}" -- test -f /etc/hostname 2>/dev/null; then
            echo "Container ${container_name} is ready"
            return 0
        fi
        
        echo "Waiting for container to be ready... (attempt $attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done
    
    echo "Error: Container ${container_name} failed to become ready within expected time"
    return 1
}

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_warning() {
    echo "[WARNING] $*" >&2
}

cleanup_failed_deployment() {
    local container_name="${1:-}"
    if [[ -n "$container_name" ]] && lxc list -c n --format csv | grep -q "^${container_name}$"; then
        echo "Cleaning up failed deployment: ${container_name}"
        lxc stop "${container_name}" --force 2>/dev/null || true
        lxc delete "${container_name}" 2>/dev/null || true
    fi
}

check_lxd_version() {
    if command -v lxd &> /dev/null; then
        lxd_version=$(lxd --version)
        major_version=$(echo "$lxd_version" | cut -d. -f1)
        if [[ $major_version -eq 4 ]] || [[ $major_version -eq 5 ]]; then
            #echo "LXD is installed with version $lxd_version."
            :
        else
            #echo "LXD is installed, but the version is not 4 or 5. Current version: $lxd_version."
            :
        fi
    else
        echo "LXD is not installed."
        exit 1
    fi
}


check_network() {
    echo "Waiting for network..."
    attempt=0
    max_attempts=10
    while ! lxc exec $1 -- ping -c 4 8.8.8.8 > /dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [ $attempt -ge $max_attempts ]; then
            echo "Network check failed after $max_attempts attempts."
            exit 1
        fi
        #echo "Ping failed, retrying in 1 second..."
        sleep 1
    done
    echo "Network is up."
}


check_devuan_chimaera() {
    # non ubuntu images are no longer (early '24) publically served
    #
    # posted the image on dropbox
    #
    # https://www.dropbox.com/scl/fi/i1amx0tvbd4lygg29o4st/devuan-chimaera.tar.gz?rlkey=9q0mrda1eaohfr85xj2l8zryh&dl=0
    # wget 'https://dl.dropboxusercontent.com/scl/fi/i1amx0tvbd4lygg29o4st/devuan-chimaera.tar.gz?rlkey=9q0mrda1eaohfr85xj2l8zryh&dl=0' -O devuan-chimaera.tar.gz
    # Check if the LXD image with a specific alias exists
    if lxc image list | grep -q "devuan-chimaera-base"; then
        :
        #echo "Image with alias 'devuan-chimaera-base' exists."
    else
        echo "Creating devuan-chimaera-base image"
        url="https://dl.dropboxusercontent.com/scl/fi/i1amx0tvbd4lygg29o4st/devuan-chimaera.tar.gz?rlkey=9q0mrda1eaohfr85xj2l8zryh&dl=0"
        file="$M_ROOT/tmp/devuan-chimaera.tar.gz"
        [ -e "$encfile" ] || curl -L -o "$file" "$url"
        tar xzf $file -C $M_ROOT/tmp
        lxc image import $M_ROOT/tmp/devuan-chimaera $M_ROOT/tmp/devuan-chimaera.root --alias devuan-chimaera-base
    fi
}


# Validates version string format: name-release-customerid[-index]
# where name=mv1|mv2plus|mv3, release=r21|r22, customerid=7|9|20, index=001-099
# Returns unique hash 1001-3129 or -1 if invalid
# Hash format: name(1-3)release(0-1)custid(0-2)index(00-99)

validate_and_hash() {

    local input="$1"
    local regex="^(mv1|mv2plus|mv3)-r2[12]-(7|9|20)(-0(0[1-9]|[1-9][0-9]))?$"
    # Initial validation
    if [[ ! "$input" =~ $regex ]]; then
        echo "-1"
        return 1
    fi
    # Extract components
    local name=$(echo "$input" | cut -d'-' -f1)
    local release=$(echo "$input" | cut -d'-' -f2)
    local customer_id=$(echo "$input" | cut -d'-' -f3)
    local index=$(echo "$input" | cut -d'-' -f4)
    # Generate name value (1-3)
    local name_val
    case "$name" in
        "mv1") name_val=1 ;;
        "mv2plus") name_val=2 ;;
        "mv3") name_val=3 ;;
    esac
    # Map release to 0-1 position
    local release_num=${release#r}
    local release_position
    case $release_num in
        21) release_position=0 ;;
        22) release_position=1 ;;
        *) echo "-1"
           return 1 ;;
    esac
    # Map customer_id to 0-2 position
    local cust_num=$((10#$customer_id))
    local cust_position
    case $cust_num in
        7) cust_position=0 ;;
        9) cust_position=1 ;;
        20) cust_position=2 ;;
        *) echo "-1"
           return 1 ;;
    esac
    # Validate index if present
    local index_num=0
    if [ ! -z "$index" ]; then
        index_num=$((10#$index))
        if [ $index_num -lt 1 ] || [ $index_num -gt 99 ]; then
            echo "-1"
            return 1
        fi
    fi
    # Generate and return only the hash
    local hash=$((
        (name_val * 1000 +
        release_position * 100 +
        cust_position * 10 +
        index_num) + 1
    ))
    echo "$hash"
    return 0
}


# Generate first MAC address with fixed OUI
generate_mac1() {
    local container_name=$1
    local fixed_oui="00:60:2F"

    # Use md5sum and take first 6 characters
    local hash=$(echo -n "$container_name" | md5sum | cut -c1-6)

    # Convert hash to MAC address format (last 3 bytes)
    local nic_part=$(echo $hash | sed 's/\(..\)/:\1/g' | sed 's/^://')

    # Combine OUI and NIC parts
    echo "${fixed_oui}:${nic_part}"
}


# Generate second MAC address with same OUI but different hash approach
generate_mac2() {
    local container_name=$1
    local fixed_oui="00:60:2F"

    # Use sha256sum and take characters 7-12 for different hash result
    local hash=$(echo -n "$container_name:secondary" | md5sum | cut -c7-12)

    # Convert hash to MAC address format (last 3 bytes)
    local nic_part=$(echo $hash | sed 's/\(..\)/:\1/g' | sed 's/^://')

    # Combine OUI and NIC parts
    echo "${fixed_oui}:${nic_part}"
}


check_and_create_lxdbr1() {

    bridge_name="lxdbr1"
    # Check if the network bridge exists
    if ! lxc network list | grep -q "^| ${bridge_name} "; then
        echo "Bridge ${bridge_name} does not exist. Creating it..."
        # Create the network bridge
        lxc network create ${bridge_name}
    else
        echo "Bridge ${bridge_name} exists. Reapplying settings..."
    fi
    # Set the IPv4 address and disable DHCP
    lxc network set ${bridge_name} ipv4.address "10.10.10.1/24"
    lxc network set ${bridge_name} ipv4.dhcp "false"
    #lxc network set ${bridge_name} ipv4.dhcp.ranges "10.10.10.100-10.10.10.150"
    # Set the IPv6 address and disable DHCP
    lxc network set ${bridge_name} ipv6.address "2001:dbf:0:1::1/64"
    lxc network set ${bridge_name} ipv6.dhcp "false"
    #lxc network set ${bridge_name} ipv6.dhcp.ranges "2001:dbf:0:1::100-2001:dbf:0:1::254"
    lxc network set ${bridge_name} ipv6.dhcp.stateful "true"
    if true; then
        # We need NAT, as this provides the ability to connect to internet from ACS
        # and BNG containers.
        # However we do not want NAT for wan interface on BNG as this prevents ACS
        # connecting to MVx, the 107. address would be replaced by the ip address of
        # the gateway interface.
        # setting nat to true using lxd, would enable NAT for any outgoing interface
        # Create a custom NAT rule that disables NAT for wan interface
        lxc network set ${bridge_name} ipv4.nat "false"
        lxc network set ${bridge_name} ipv6.nat "false"
        ## # Define the rule components
        ## SOURCE_IP="10.10.10.0/24"
        ## OUT_INTERFACE="wan"
        ## TARGET="MASQUERADE"
        ## # Check if the rule exists
        ## if sudo iptables -t nat -C POSTROUTING -s $SOURCE_IP ! -o $OUT_INTERFACE -j $TARGET 2>/dev/null; then
        ##     echo "Bridge ${bridge_name}: NAT rule exists."
        ## else
        ##     echo "Bridge ${bridge_name}: NAT rule does not exist. adding it."
        ##     sudo iptables -t nat -A POSTROUTING -s $SOURCE_IP ! -o $OUT_INTERFACE -j $TARGET
        ## fi
        # Define the rule components
        SOURCE_IP="10.10.10.0/24"
        OUT_INTERFACE="wan"
        TARGET="MASQUERADE"
        DEST_IP="10.10.10.0/24"
        # Check if the rule exists
        if sudo iptables -t nat -C POSTROUTING -s $SOURCE_IP ! -o $OUT_INTERFACE ! -d $DEST_IP -j $TARGET 2>/dev/null; then
            echo "Bridge ${bridge_name}: NAT rule exists."
        else
            echo "Bridge ${bridge_name}: NAT rule does not exist. Adding it."
            sudo iptables -t nat -A POSTROUTING -s $SOURCE_IP ! -o $OUT_INTERFACE ! -d $DEST_IP -j $TARGET
        fi
        #ipv6..
    else
        lxc network set ${bridge_name} ipv4.nat "true"
        lxc network set ${bridge_name} ipv6.nat "true"
    fi
}


check_lxdbr0() {

    # Check for the specific LXD comment
    if sudo iptables -t nat -L -v | grep -q "generated for LXD network lxdbr0"; then
        echo "LXD network rule for lxdbr0 found"
    else
        echo "LXD network rule for lxdbr0 not found"
    fi
}


check_and_create_wan_bridge() {

    bridge_name=$1

    if ! ip link show type bridge | grep -q "^.* ${bridge_name}:"; then
        echo "Creating bridge: ${bridge_name}"

        if ! sudo ip link add name ${bridge_name} type bridge; then
            echo "Failed to create bridge ${bridge_name}"
            ret=1
        fi
        # Disable IPv6 router advertisements
        if ! sudo sysctl -w net.ipv6.conf.${bridge_name}.accept_ra=0 > /dev/null 2>&1; then
            echo "Warning: Failed to disable IPv6 RA on ${bridge_name}"
        fi
        # Bring bridge up
        if ! sudo ip link set ${bridge_name} up; then
            echo "Failed to bring up bridge ${bridge_name}"
            ret=1
        fi
        # Optional: Enable promiscuous mode and STP
        #sudo ip link set dev "${bridge_name}" promisc on
        #sudo bridge stp "${bridge_name}" on

    else
        echo "Bridge ${bridge_name} exists, flushing IP addresses"
        # Flush existing IP addresses
        if ! sudo ip addr flush dev ${bridge_name}; then
            echo "Warning: Failed to flush IP addresses from ${bridge_name}"
        fi
    fi
}


check_and_create_lan_bridge() {

    bridge_name=$1

    if ! ip link show type bridge | grep -q "^.* ${bridge_name}:"; then
        echo "Creating bridge: ${bridge_name}"

        # Create VLAN-aware bridge
        if ! sudo ip link add name ${bridge_name} type bridge \
            vlan_filtering 1 \
            vlan_default_pvid 1; then
            echo "Failed to create VLAN-aware bridge ${bridge_name}"
            ret=1
        fi
        # Bring bridge up
        if ! sudo ip link set ${bridge_name} up; then
            echo "Failed to bring up bridge ${bridge_name}"
            ret=1
        fi
        # Verify VLAN filtering is enabled
        if ! grep -q "1" /sys/class/net/${bridge_name}/bridge/vlan_filtering 2>/dev/null; then
            echo "Warning: VLAN filtering might not be enabled on ${bridge_name}"
        fi

    else
        echo "Bridge ${bridge_name} exists, flushing IP addresses"
        # Flush existing IP addresses
        if ! sudo ip addr flush dev ${bridge_name}; then
            echo "Warning: Failed to flush IP addresses from ${bridge_name}"
        fi
        # For existing LAN bridges, ensure VLAN filtering is enabled
        if ! grep -q "1" /sys/class/net/${bridge_name}/bridge/vlan_filtering 2>/dev/null; then
            echo "Enabling VLAN filtering on existing bridge ${bridge_name}"
            sudo ip link set ${bridge_name} down
            sudo ip link set ${bridge_name} type bridge vlan_filtering 1
            sudo ip link set ${bridge_name} up
        else
            echo "VLAN filtering is enabled on existing bridge ${bridge_name}"
        fi
    fi
}


check_bridges() {
    local ret=0

    for bridge_name in $bridges; do
        # Check if bridge exists using ip link - silent if exists
        if ! ip link show dev "$bridge_name" &>/dev/null; then
            echo "Bridge $bridge_name does not exist"
            ret=1
        fi
    done

    # Check lxdbr0 - silent if exists
    if ! ip link show dev "lxdbr0" &>/dev/null; then
        echo "Bridge lxdbr0 does not exist"
        ret=1
    fi

    return $ret
}


check_and_create_bridges() {

    for bridge_name in $bridges; do
        case "$bridge_name" in

            # lxdbr1
            lxdbr1)
                echo '------------------------------------------------------'
                check_and_create_lxdbr1
                ;;

            # WAN bridges
            wan|cm)
                echo '------------------------------------------------------'
                check_and_create_wan_bridge $bridge_name
                ;;

            # LAN bridges with VLAN support
            lan-p[1-4]|br-wlan[0-1]|wanoe)
                echo '------------------------------------------------------'
                check_and_create_lan_bridge $bridge_name
                # sudo bridge vlan show dev $bridge_name
                ;;

            *)
                echo '------------------------------------------------------'
                echo "Error: Unsupported bridge name: ${bridge_name}"
                ret=1
                continue
                ;;
        esac
    done

    echo '------------------------------------------------------'

    #check_lxdbr0
    #echo '------------------------------------------------------'

    return $ret
}


# Function to verify bridge configuration
verify_bridge_config() {
    local bridge_name="$1"
    # Check if bridge exists
    if ! ip link show type bridge | grep -q "^.* ${bridge_name}:"; then
        return 1
    fi
    # For LAN bridges, verify VLAN filtering
    if [[ "$bridge_name" =~ ^(lan-p[1-4]|wlan[0-1])$ ]]; then
        if ! grep -q "1" /sys/class/net/${bridge_name}/bridge/vlan_filtering 2>/dev/null; then
            return 1
        fi
    fi
    return 0
}


remove_bridge() {

    bridge_name=$1
    if [[ "$bridge_name" == "lxdbr1" ]]; then
        if lxc network delete "${bridge_name}"; then
            echo "Bridge ${bridge_name} deleted successfully."
        else
            echo "Error: Failed to delete bridge ${bridge_name}."
            lxc network show ${bridge_name}
        fi
    elif ip link show type bridge | grep -q "^.* ${bridge_name}:"; then
        sudo ip link set ${bridge_name} down
        sudo ip link delete ${bridge_name} type bridge
        echo "Bridge ${bridge_name} deleted successfully."
    fi
    if [[ "$bridge_name" == "lxdbr1" ]]; then
        # Define the rule components
        SOURCE_IP="10.10.10.0/24"
        OUT_INTERFACE="wan"
        TARGET="MASQUERADE"
        DEST_IP="10.0.0.0/24"
        # Check if the rule exists
        if sudo iptables -t nat -C POSTROUTING -s $SOURCE_IP ! -o $OUT_INTERFACE ! -d $DEST_IP -j $TARGET 2>/dev/null; then
            echo "Bridge ${bridge_name}: NAT rule exists. Deleting the rule."
            sudo iptables -t nat -D POSTROUTING -s $SOURCE_IP ! -o $OUT_INTERFACE ! -d $DEST_IP -j $TARGET
        else
            echo "Bridge ${bridge_name}: NAT rule does not exist."
        fi
    fi
}


# Function to get parent bridge for a network device in a profile
get_parent_bridge() {
    local profile_name="$1"
    local eth_device="$2"

    # Check if profile exists
    if ! lxc profile show "$profile_name" >/dev/null 2>&1; then
        echo "Error: Profile '$profile_name' not found" >&2
        return 1
    fi

    # Get the parent bridge using yaml path
    local parent
    parent=$(lxc profile show "$profile_name" | awk -v dev="$eth_device" '
        BEGIN { found=0; in_device=0 }
        $1 == "devices:" { in_devices=1 }
        in_devices && $1 == dev":" { found=1; next }
        found && $1 == "parent:" { print $2; exit }
    ')

    if [ -z "$parent" ]; then
        echo "Error: Device '$eth_device' not found in profile '$profile_name' or parent not defined" >&2
        return 1
    fi

    echo "$parent"
    return 0
}

check_and_create_virt_wlan() {
    # Define the expected interfaces

    local interfaces_vcpe=("virt-wlan0" "virt-wlan1" "virt-wlan2" "virt-wlan3")
    local missing=0

    if [ "$(lxc list vcpe --format csv -c ns | awk -F',' '{print $2}')" = "RUNNING" ]; then
        : # vcpe is running, the wlan interfaces have been mapped into vpce container
    else
        : # vcpe is not running
        # Check each interface
        for iface in "${interfaces_vcpe[@]}"; do
            if ! ip link show "$iface" &>/dev/null; then
                missing=$((missing + 1))
            fi
        done
    fi


    # If any interfaces are missing, create them
    if [ $missing -gt 0 ]; then
        echo "Virtual wlan interfaces are missing. Creating virtual wlan interfaces now..."

        # Check if mac80211_hwsim is already loaded
        if lsmod | grep -q "mac80211_hwsim"; then
            echo "Unloading mac80211_hwsim module..."
            sudo modprobe -r mac80211_hwsim
        fi

        # Load the module with 5 radios
        echo "Loading mac80211_hwsim with 5 radios..."
        sudo modprobe mac80211_hwsim radios=5

        # Wait a moment for interfaces to be created
        sleep 1

        # Rename the interfaces
        for i in {0..4}; do
            if ip link show "wlan$i" &>/dev/null; then
                echo "Renaming wlan$i to virt-wlan$i"
                sudo ip link set "wlan$i" down
                sudo ip link set "wlan$i" name "virt-wlan$i"
                sudo ip link set "virt-wlan$i" up
            else
                echo "Warning: wlan$i was not created by mac80211_hwsim"
            fi
        done

    fi
}


banner() {
    local text="$1"
    local color="${2:-white}"  # Default to white if no color specified

    case "$color" in
        "grey")   color_code="\e[30m" ;;
        "red")    color_code="\e[31m" ;;
        "white")  color_code="\e[37m" ;;
        "blue")   color_code="\e[34m" ;;
        "green")  color_code="\e[32m" ;;
        "yellow") color_code="\e[33m" ;;
        *)        color_code="\e[37m" ;; # Default to white
    esac

    echo -e "${color_code}${text}\e[0m"
}

validate_lan_port() {
    local port_num=$1
    local lan_var="lan_p${port_num}"
    local vlan_var="lan_p${port_num}_vlan"

    [[ -n "${!lan_var}" && "${!lan_var}" != "wanoe" && "${!lan_var}" != "wan" ]] && {
        declare -g ${vlan_var}="$(validate_and_hash "${!lan_var}")" &&
        [[ "${!vlan_var}" == "-1" ]] && {
            echo "cannot determine unique vlan for ${lan_var} ${!lan_var}"
            exit 1
        }
    }
}


setup_lxd_certificates() {
    #local lxd_endpoint="${1:-192.168.2.150:8443}"
    local lxd_endpoint="${1:-10.0.0.194:8443}"
    local cert_dir="$HOME/.config/lxc"
    local cert_validity_days=3650
    
    # Create certificate directory silently
    mkdir -p "${cert_dir}" 2>/dev/null
    
    # Generate client certificate and key if they don't exist
    if [[ ! -f "${cert_dir}/client.crt" ]] || [[ ! -f "${cert_dir}/client.key" ]]; then
        # Generate certificate silently
        if ! openssl req -x509 -newkey rsa:4096 \
            -keyout "${cert_dir}/client.key" \
            -out "${cert_dir}/client.crt" \
            -days ${cert_validity_days} \
            -nodes \
            -subj "/CN=lxd-client/O=LXD/OU=REST-API" >/dev/null 2>&1; then
            echo "Error: Failed to generate LXD client certificates"
            return 1
        fi
        
        # Set permissions
        chmod 600 "${cert_dir}/client.key" 2>/dev/null
        chmod 644 "${cert_dir}/client.crt" 2>/dev/null
    fi
    
    # Add certificate to LXD trusted certificates (silent unless error)
    lxc config trust add "${cert_dir}/client.crt" >/dev/null 2>&1 || true
    
    # Test API connectivity
    local test_response
    test_response=$(curl -s -k \
        --cert "${cert_dir}/client.crt" \
        --key "${cert_dir}/client.key" \
        -w "\nHTTP_CODE:%{http_code}" \
        --connect-timeout 5 \
        "https://${lxd_endpoint}/1.0" 2>/dev/null || echo "CURL_FAILED")
    
    if [[ "$test_response" == "CURL_FAILED" ]]; then
        echo "Error: Failed to connect to LXD API at ${lxd_endpoint}"
        return 1
    fi
    
    local http_code
    http_code=$(echo "$test_response" | grep "HTTP_CODE:" | cut -d: -f2)
    
    if [[ "$http_code" != "200" ]]; then
        echo "Error: LXD API test failed with HTTP status ${http_code}"
        return 1
    fi
    
    # Test instance listing (using instances endpoint for newer LXD versions)
    local instances_response
    instances_response=$(curl -s -k \
        --cert "${cert_dir}/client.crt" \
        --key "${cert_dir}/client.key" \
        --connect-timeout 5 \
        "https://${lxd_endpoint}/1.0/instances" 2>/dev/null)
    
    # Fallback to containers endpoint if instances fails
    if ! echo "$instances_response" | grep -q '"type":"sync"'; then
        instances_response=$(curl -s -k \
            --cert "${cert_dir}/client.crt" \
            --key "${cert_dir}/client.key" \
            --connect-timeout 5 \
            "https://${lxd_endpoint}/1.0/containers" 2>/dev/null)
    fi
    
    if ! echo "$instances_response" | grep -q '"type":"sync"'; then
        echo "Error: Failed to retrieve LXD instance list"
        return 1
    fi
    
    # All tests passed silently
    return 0
}


main() {
    M_ROOT="$( dirname "$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )" )"

    if [[ ! "$PWD" == "$M_ROOT"* ]]; then
        SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
        echo "Error: Script(s) are being run from outside the current directory !" >&2
        echo "Current directory: $PWD" >&2
        echo "PATH             : $SCRIPT_PATH" >&2
        echo "Please change the current directory or update PATH." >&2
        exit 1
    fi

    export M_ROOT

    mkdir -p $M_ROOT/tmp

    check_lxd_version

    bridges="
            lxdbr1 \
            wan \
            cm \
            lan-p1 lan-p2 lan-p3 lan-p4 \
        "

    check_bridges
    if [ $? -eq 1 ]; then
        echo -e "Required bridges are missing. Creating bridges now...\n"
        check_and_create_bridges
    fi

    #check_and_create_virt_wlan //No need to setup wlan for managed bridge device

    setup_lxd_certificates

}

main
