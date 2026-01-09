#!/bin/bash

source gen-util.sh


container_name="oktopus"
image_name="debian12"

########################################################################################
# Obtain the image if it does not exist

if ! lxc image list | grep -q $image_name; then
    echo "Obtaining image: debian/12"
    lxc image copy images:debian/12 local: --alias $image_name
fi

########################################################################################
# Delete container if exists

if lxc list --format csv | grep -q "^${container_name}"; then
    echo "Deleting ${container_name} container"
    lxc delete ${container_name} -f 1>/dev/null
fi

########################################################################################
# Create the profile

if lxc profile list --format csv | grep -q "^${container_name}"; then
    lxc profile delete ${container_name} 1> /dev/null
fi
lxc profile copy default ${container_name}


cat << EOF | lxc profile edit ${container_name}
name: oktopus
description: "oktopus"
config:
    boot.autostart: "false"
    raw.lxc: |
      lxc.apparmor.profile=unconfined
    security.privileged: "true"
    security.nesting: "true"
    limits.cpu: "0"               # "0" effectively means no CPU limits, allowing access to all available CPUs
    limits.memory: 4GB            # Restrict memory usage to 4GB
devices:
    eth0:
        name: eth0
        nictype: bridged
        parent: lxdbr1
        type: nic
        ## ip addressing is static and configured in /etc/network/interfaces
    root:
        path: /
        pool: default
        type: disk
        size: 4GB
EOF


echo "Configuring ${container_name}"

########################################################################################
## set timezone

#lxc profile set ${container_name} environment.TZ $(date +%z | awk '{printf("PST8PDT,M3.2.0,M11.1.0")}')

########################################################################################
## set timezone

lxc init ${image_name} ${container_name} -p ${container_name}


##################################################################################
#

lxc file push $M_ROOT/gen/configs/oktopus.eth0.network oktopus/etc/systemd/network/eth0.network

##################################################################################
#

lxc start ${container_name}

##################################################################################
# install docker

lxc exec ${container_name} -- bash -c '
apt update
apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
'

##################################################################################
# install oktopus

lxc exec ${container_name} -- bash -c '
apt install wget unzip
wget https://github.com/OktopUSP/oktopus/archive/refs/heads/main.zip
unzip main.zip
cd /$HOME/oktopus-main/deploy/compose
sed -i "s/image: mongo/image: mongo:4.4/" docker-compose.yaml
sed -i "/image: mongo:4.4/a\\    security_opt:\\n      - apparmor:unconfined" docker-compose.yaml
sed -i "/image:.*nginx/a\\    security_opt:\\n      - apparmor=unconfined" docker-compose.yaml
COMPOSE_PROFILES=nats,controller,cwmp,mqtt,stomp,ws,adapter,frontend docker compose up -d
'

##################################################################################
# run oktopus

lxc exec ${container_name} -- bash -c '
cd /$HOME/oktopus-main/deploy/compose
COMPOSE_PROFILES=nats,controller,cwmp,mqtt,stomp,ws,adapter,frontend docker compose up -d
'

