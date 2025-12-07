![vCPE Diagram](doc/e2e.svg)

# VCPE containers overview

## vcpe containers

The vcpe containers run the full rdk-b (rpi) router / gateway stack. These containers are created from a rootfs that was built from a standard rdk-b rpi build with a modified machine/distro config. The (bare metal / no emulation) vcpe container is configured with a couple cpu's, memory, rootfs disk, wan, lan, and wlan interfaces, and an nvram volume which retains all persistent settings between reboots.

## bng containers

The bng containers (devuan chimaera) provide basic configuration and connectivity services to the wan-side of the cpe containers (similar to cmts / head-end / back-office). This includes: router.cfg tftp, dhcpv4/v6, radvd, dns, ntp, internet-gateway, etc. There are multiple pre-configured bng containers providing a specific real world market configuration. For instance bng-9 is configured for multi-vlan with a specific ip-pool. Each bng provides a wan (internet) and a cm (cmts) connection to the cpe containers.

## lan-client containers

lan clients (alpine) connect to a cpe lan port via the lan-p1 (/2/3/4) bridges (vlan). automatically comfigured with dhcp.

## acs (axiros / genie) container (tr069)

The acs container (debian 7) contains an Axiros tr069 cwmp server stack. cpe containers will register and establish the tr069 protocol with the acs. In addition to the acs-ui, auto testing via (soap) is available as well. The Axiros acs image is available to licensees only.

## oktopus container (usp)

The oktopus container (debian 12) contains the open source Oktopus usp controller stack. cpe containers run usp agent and will register and establish the usp over mqtt/stomp/websocket protocol with Oktopus. Oktopus services run in docker containers inside the oktopus container.

## webpa container

The webpa container (centos-stream 9) contains the webpa server xmidt stack. cpe containers run webpa client and will register and establish the web-pa protocol with web-pa server.

## webconfig container

The webconfig container (ubuntu 18.04) contains the webconfig server stack.

## xconf container

The xconf container (ubuntu 18.04) contains the xconf server stack. cpe containers obtain telemetry config files from the xconf server.

## telemetry container

The telemetry container (ubuntu 20.04) contains the telemetry upload server stack. cpe containers upload telemetry data, and the server stores and presents the data (elasticsearch / kibana)

## automatics container

The automatics container (centos-stream 9) comprises the entire suite of automatics services in a single container. It is configured with a rpi provider, and can run rdkb-tests manually or from orchestration UI.

## boardfarm container

The boardfarm container (ubuntu 22.04) comprises the entire suite of boardfarm components in a single container. It is currently under development.

## DevOps containers

### jira container

The jira container (ubuntu 22.04) contains Atlassian JIRA Server for issue tracking and project management. It includes PostgreSQL database and is configured for agile development workflows with the vCPE team.

### jenkins container

The jenkins container (ubuntu 22.04) contains Jenkins LTS for continuous integration and deployment. It comes pre-configured with Docker, Ansible, Terraform, kubectl, and other DevOps tools for automating vCPE container builds, testing, and deployments.

### gitlab container

The gitlab container (ubuntu 22.04) contains GitLab CE for Git repository hosting with integrated CI/CD capabilities. It provides source code management, merge request workflows, issue tracking, and automated pipeline execution for vCPE development.

### tdk container

The tdk container (ubuntu 20.04) runs the Test Development Kit (TDK) Test Manager inside a Docker container. It provides comprehensive test management capabilities for RDK-B devices including test case creation, execution, result analysis, and CI/CD integration. TDK uses MySQL database, Tomcat application server, and supports both Python and Java test frameworks.

# Bridges overview

## lxdbr1

This bridge connects the service containers (acs, usp, webpa, etc.) to the bng containers, and provides host gateway (internet) access to the bng containers.

## wan

cpe containers connect to bng containers using a common wan bridge (supporting single/multi/no - vlan) and a common cm bridge (docsis capable vcpe's).

## lan-p1/2/3/4
lan clients connect to cpe containers lan ports using lan-p1..lan-p4 bridges. The cpe containers lan ports and the lan-p1.lan-p4 bridges are vlan configured allowing a large number of client connections to cpe containers lan ports.


# Installation

## Prerequisites

The Virtual CPE Environment runs on a x86 Linux host using LXD container manager. VCPE runs a large number of linux containers, and creates network interfaces and bridges. While it can run on a shared server, deploying it on a dedicated physical (or vm) server is recommended.

Ubuntu 20/22/24 is recommended as it is known to work correctly for all cpe, bng, client, and service - container configurations. Verified with virtual box ubuntu-20.04.6/22.04.5/24.04.1-live-server-amd64.

```text
sudo apt install -y curl
```


## Install LXD

```text
sudo snap install lxd --channel=6
```

## Initialize LXD

this is required once after a install or re-install. select all except for the below two items:

```text
Size in GiB of the new loop device (1GiB minimum) [default=30GiB]: 40
Would you like the LXD server to be available over the network? (yes/no) [default=no]: yes
```

```text
lxd init
```

## Test LXD

Launch a container and perform an internet connectivity test:

```text
lxc launch images:alpine/edge edge
lxc exec edge -- ping google.com -c 3
lxc delete edge -f
```

# Install meta-cmf-raspberrypi-vcpe (this repo)

meta-cmf-raspberrypi-vcpe contains shell scripts to manage the VCPE environment (located in /gen). Scripts required for running various vcpe tests, and scripts required for obtaining and processing vcpe data, including a large number of debug and visualization tooling scripts known as probes are located in /probes (initial limited version). /doc contains additional documentation. /recipes is part of the vcpe container (yocto) meta-layer for building a vcpe rpi image.

Clone the repo:

```text
mkdir -p $HOME/git
cd $_

git clone ssh://git@bitbucket.upc.biz:7999/~rvogelaar/meta-cmf-raspberrypi-vcpe.git

/

git clone https://github.com/robvogelaar/meta-cmf-raspberrypi-vcpe

```

Add meta-cmf-raspberrypi-vcpe to system PATH:

```text
export PATH="$HOME/git/meta-cmf-raspberrypi-vcpe/gen:$PATH"
export PATH="$HOME/git/meta-cmf-raspberrypi-vcpe/probes/scripts:$PATH"

# it is recommended to run all the vcpe scripts from this directory
cd $HOME/git/meta-cmf-raspberrypi-vcpe

```
# switch to mso_managed_bridge branch
git checkout mso_managed_bridge

## Install VCPE bridges

Modify this lxd end point ip address as per your host machine address
gen/gen-util.sh
    local lxd_endpoint="${1:-192.168.2.150:8443}"
gen/boardfarm.sh
    lxd_endpoint="192.168.2.120:8443"
    
Required once after a host reboot. Run the bridges.sh script:
```text
bridges.sh
```

## Install BNG containers

Run the bng.sh script to install bng-7 (ie. non-vlan bng)

Note: This will first create a bng base container. This is a one-time process that will take several minutes to complete, as it builds a container image from scratch. Please be patient during this initial setup.

```text
bng.sh 7

lxc list
+--------+---------+--------------------------+-------------------------------+
|  NAME  |  STATE  |           IPV4           |             IPV6              |
+--------+---------+--------------------------+-------------------------------+
| bng-7  | RUNNING | 10.107.201.1 (eth2)      | 2001:dbf:0:1::107 (eth0)      |
|        |         | 10.107.200.1 (eth1)      | 2001:daf:7:1::129 (eth2)      |
|        |         | 10.10.10.107 (eth0)      | 2001:dae:7:1::129 (eth1)      |
+--------+---------+--------------------------+-------------------------------+
```

## Install VCPE container

Run the vcpe.sh user@host:/path-to-container-image script to install vcpe container:

Shell into the container to check processes, datamodel etc.

It is recommended to at least once run a factory default inside the vcpe container using the appropriate command syscfg / dmcli etc.

e.g. dmcli eRT setv Device.X_CISCO_COM_DeviceControl.FactoryReset string "Router,Wifi"

a factory default will eventually reboot the container at which time you will be kicked out of the container shell, you can immediately shell back in.

Once the vcpe container is running it should take < 10 seconds for the lan and wan (erouter0) side to be completely configured with ip4/6.

Note: the cpe container command history will be saved in /nvram/, to write the history file, exit and re-enter the container, the history will remain available upon a container reboot.

```text

vcpe.sh rev@rev140:/home/rev/yocto/rdkb-2025q1-kirkstone-nosrc-0601/build-qemux86broadband/tmp/deploy/images/qemux86broadband/rdk-generic-broadband-image-qemux86broadband.lxc.tar.bz2

lxc list
+--------+---------+---------------------------+---------------------------------------------+
| vcpe   | RUNNING | 192.168.245.1 (br403)     | 3001:dae:0:e900:216:3eff:fe16:5f7c (brlan0) |
|        |         | 192.168.106.1 (br106)     | 2001:dae:7:1::254 (erouter0)                |
|        |         | 192.168.101.3 (br0)       |                                             |
|        |         | 10.107.200.100 (erouter0) |                                             |
|        |         | 10.0.0.1 (brlan0)         |                                             |
+--------+---------+---------------------------+---------------------------------------------+

lxc exec vcpe bash
root@RaspberryPi-Gateway:~$ ps / top /etc.
root@RaspberryPi-Gateway:~$ dmcli eRT getv Device.DeviceInfo.
root@RaspberryPi-Gateway:~$ systemd-analyze plot
```

### Multiple VCPE Instances

The vcpe.sh script supports creating multiple independent vCPE container instances using an optional suffix parameter (001-099). Each instance has its own:
- Unique container name, profile, and NVRAM volume
- Unique MAC addresses and VLAN ID


```text
# Create first instance (vcpe-001)
vcpe.sh rev@rev140:/path/to/rdk-generic-broadband-image-qemux86broadband.lxc.tar.bz2 001

# Create second instance (vcpe-002)
vcpe.sh rev@rev140:/path/to/rdk-generic-broadband-image-qemux86broadband.lxc.tar.bz2 002

# Create additional instances for parallel testing
vcpe.sh /path/to/local/image.tar.bz2 010
vcpe.sh /path/to/local/image.tar.bz2 020

# List all containers
lxc list

+----------+---------+---------------------------+---------------------------------------------+
| vcpe     | RUNNING | 10.107.200.100 (erouter0) | 3001:dae:0:e900:216:3eff:fe16:5f7c (brlan0) |
+----------+---------+---------------------------+---------------------------------------------+
| vcpe-001 | RUNNING | 10.107.200.101 (erouter0) | 3001:dae:0:e900:216:3eff:fe16:5f7d (brlan0) |
+----------+---------+---------------------------+---------------------------------------------+
| vcpe-002 | RUNNING | 10.107.200.102 (erouter0) | 3001:dae:0:e900:216:3eff:fe16:5f7e (brlan0) |
+----------+---------+---------------------------+---------------------------------------------+

# Manage specific instances
lxc exec vcpe-001 bash
lxc restart vcpe-002
lxc stop vcpe-010
```

Each instance gets:
- Container name: vcpe-{suffix} (e.g., vcpe-001)
- Profile name: vcpe-{suffix}
- NVRAM volume: vcpe-{suffix}-nvram
- VLAN ID: 100 + offset (e.g., 001 → VLAN 101, 002 → VLAN 102)
- MAC addresses: Base MAC + offset



## Install ACS container

Run the acs.sh / genieacs.sh script:

Note: as part of the acs container creation, an encrypted Axiros container image is obtained from dropbox available to licensees only.

```text
ACS_URL="" ACS_KEY="" acs.sh

genieacs.sh

lxc list
+-----------+---------+------------------------+----------------------------------------------+
| acs       | RUNNING | 10.10.10.200 (eth0)    | 2001:dbf:0:1::200 (eth0)                     |
|           |         |                        | 2001:dbf:0:1:216:3eff:fe38:11ab (eth0)       |
+-----------+---------+------------------------+----------------------------------------------+
| genieacs  | RUNNING | 10.10.10.201 (eth0)    | 2001:dbf:0:1::201 (eth0)                     |
|           |         |                        | 2001:dbf:0:1:216:3eff:fe38:11ac (eth0)       |
+-----------+---------+------------------------+----------------------------------------------+
```

the axiros acs UI will be at 10.10.10.200:80
the genie acs UI will be at 10.10.10.201:3000

## Install Oktopus container

Run the oktopus.sh script:

```text
oktopus.sh

lxc list
+----------+---------+--------------------------------+----------------------------------------+
| oktopus  | RUNNING | 172.17.0.1 (docker0)           | 2001:dbf:0:1::220 (eth0)               |
|          |         | 172.16.235.1 (br-ab31f132a111) | 2001:dbf:0:1:216:3eff:fe25:904c (eth0) |
|          |         | 10.10.10.220 (eth0)            |                                        |
+----------+---------+--------------------------------+----------------------------------------+
```

the Oktopus UI will be at 10.10.10.220:80

the default transport will be mqtt.

If cpe does not show in oktopus UI or cannot be interacted with, then delete the cpe in oktopus UI, and restart the agent on the cpe:

```text
lxc exec vcpe -- systemctl restart usp-pa
```

## Install WebPA (Xmidt) container

Run the webpa.sh script to install webpa container

```text
webpa.sh

lxc list

+-------+---------+----------------------+---------------------------+
| webpa | RUNNING | 10.10.10.210 (eth0)  | 2001:dbf:0:1::210 (eth0)  |
+-------+---------+----------------------+---------------------------+
```

the webpa api will be:

```text

curl -H 'Authorization:Basic dXNlcjEyMzp3ZWJwYUAxMjM0NTY3ODkw' http://10.10.10.210:8080/api/v2/devices

{"devices":[{"id": "mac:00163e08c00f", "pending": 0, "statistics": {"bytesSent": 192, "messagesSent": 1, "bytesReceived": 3622, "messagesReceived": 6, "duplications": 0, "connectedAt": "2024-12-06T23:22:13.83241117Z", "upTime": "14m53.977362322s"}}]}

curl -H 'Authorization:Basic dXNlcjEyMzp3ZWJwYUAxMjM0NTY3ODkw' http://10.10.10.210:9003/api/v2/device/mac:00163e08c00f/config?names=Device.DeviceInfo.ModelName
{"parameters":[{"name":"Device.DeviceInfo.ModelName","value":"F3896LG","dataType":0,"parameterCount":1,"message":"Success"}],"statusCode":200}rev@rev120:~/git/meta-lxd$

```


## Install (lan) client containers

Run the client-lan.

```text
client-lan.sh vcpe-p1


lxc list

+--------------------+---------+---------------------------+---------------------------------------------+
| client-lan-vcpe-p1 | RUNNING | 10.0.0.158 (eth0)         | 3001:dae:0:e900:216:3eff:fee8:4dc (eth0)    |
+--------------------+---------+---------------------------+---------------------------------------------+
```

## Access the webui

lxc config device add client-wlan http-proxy proxy listen=tcp:0.0.0.0:8080 connect=tcp:10.0.0.1:80

webui is now available on host :8080

## Install xconf telemetry automatics

Run the appropriate scripts. All of these scripts will create a base image the very first time (when the base image does not yet exist).

```text
xconf.sh
telemetry.sh
automatics.sh

lxc list

```

## Install DevOps services

Run the DevOps service scripts to add project management, CI/CD, source code management, and test management capabilities.

```text
jira.sh
jenkins.sh
gitlab.sh
tdk.sh

# Or install TDK with specific version
tdk.sh TDK_M129

lxc list

+----------+---------+--------------------------------+----------------------------------------+
| jira     | RUNNING | 10.10.10.27 (eth0)             | 2001:dbf:0:1::27 (eth0)                |
+----------+---------+--------------------------------+----------------------------------------+
| jenkins  | RUNNING | 10.10.10.28 (eth0)             | 2001:dbf:0:1::28 (eth0)                |
+----------+---------+--------------------------------+----------------------------------------+
| gitlab   | RUNNING | 10.10.10.29 (eth0)             | 2001:dbf:0:1::29 (eth0)                |
+----------+---------+--------------------------------+----------------------------------------+
| tdk      | RUNNING | 10.10.10.30 (eth0)             | 2001:dbf:0:1::30 (eth0)                |
+----------+---------+--------------------------------+----------------------------------------+
```

## Connect physical CPE's

Connect the CPE wan to the container host using a usb eth adapter and add the usb eth interface into the wan bridge. Restart the device and it will obtain ip from the bng container.

```text
sudo ip link set enxXXX master wan
```


## Access the service container services ip, and ports

```text

###############################################################################################
# acs:
#       10.10.10.200 | 2001:dbf:0:1::200 (eth0)
#       ssh -L 192.168.2.120:8888:10.10.10.200:80 rev@192.168.2.120
#
# ui:
#       http://192.168.2.120:8888
#
###############################################################################################
# webpa:
#       10.10.10.210 | 2001:dbf:0:1::210 (eth0)
#
###############################################################################################
# oktopus:
#       10.10.10.220 | 2001:dbf:0:1::220 (eth0)
#       ssh -L 192.168.2.120:7777:10.10.10.220:80 rev@192.168.2.120
#
# ui:
#       http://192.168.2.120:7777
#
###############################################################################################
# automatics:
#       10.10.10.240 | 2001:dbf:0:1::240 (eth0)
#       ssh -L 192.168.2.120:5555:10.10.10.240:8080 rev@192.168.2.120
#
# automatics-orchestration:
#
#       http://192.168.2.120:5555/Automatics/login.htm
#       admin
#       ""
#
# automatics-props:
#       http://192.168.2.120:5555/AutomaticsProps/automatics/deviceConfig
#       http://192.168.2.120:5555/AutomaticsProps/automatics/property
#
#       john
#       Winner@123
#
# device manager:
#       http://192.168.2.120:5555/DeviceManagerUI/login.html
#       admin
#       ""
#
#       http://192.168.2.120:5555/DeviceManager/swagger-ui.html
#
###############################################################################################
# jira:
#       10.10.10.27 | 2001:dbf:0:1::27 (eth0)
#       ssh -L 192.168.2.120:8270:10.10.10.27:8080 rev@192.168.2.120
#
# ui:
#       http://192.168.2.120:8270
#       admin / admin123 (change on first login)
#
###############################################################################################
# jenkins:
#       10.10.10.28 | 2001:dbf:0:1::28 (eth0)
#       ssh -L 192.168.2.120:8280:10.10.10.28:8080 rev@192.168.2.120
#
# ui:
#       http://192.168.2.120:8280
#       admin / admin123 (or check initial admin password)
#
###############################################################################################
# gitlab:
#       10.10.10.29 | 2001:dbf:0:1::29 (eth0)
#       ssh -L 192.168.2.120:8290:10.10.10.29:80 rev@192.168.2.120
#
# ui:
#       http://192.168.2.120:8290
#       root / gitlab123 (change on first login)
#
# git clone:
#       http://192.168.2.120:8290/root/vcpe-example.git
#
###############################################################################################
# tdk:
#       10.10.10.30 | 2001:dbf:0:1::30 (eth0)
#       ssh -L 192.168.2.120:8300:10.10.10.30:8080 rev@192.168.2.120
#
# ui:
#       http://192.168.2.120:8300/rdk-test-tool
#       admin / admin (change on first login)
#
# database:
#       Host: 192.168.2.120:3306
#       Database: rdktesttoolproddb
#       Username: rdktesttooluser
#       Password: 6dktoolus3r!
#
###############################################################################################
# xconf:
#       10.10.10.250 | 2001:dbf:0:1::250 (eth0)
#       ssh -L 192.168.2.120:19093:10.10.10.250:19093 rev@192.168.2.120
#
# ui:
#       http://192.168.2.120:19093
#
###############################################################################################
# telemetry:
#       10.10.10.251 | 2001:dbf:0:1::251 (eth0)
#       ssh -L 192.168.2.120:5601:10.10.10.251:5601 rev@192.168.2.120
#
# ui (elastic):
#       http://192.168.2.120:5601
#
###############################################################################################
# tdk:
#       10.10.10.300 | 2001:dbf:0:1::300 (eth0)
#       ssh -L 192.168.2.120:8300:10.10.10.300:8080 rev@192.168.2.120
#
# ui:
#       http://192.168.2.120:8300/rdk-test-tool
#
# database:
#       MySQL on port 3306
#       Database: rdktesttoolproddb
#       Username: rdktesttooluser / 6dktoolus3r!
#
```

## Container management:

list all containers / images / profiles / volumes
```text
lxc list
lxc image list
lxc profile list
lxc storage volume list
```

enter a cpe container's console

ctrl a + q   to quit

```text
lxc console vcpe
```

enter a shell on a cpe container
```text
lxc exec vcpe bash
```

run a command in a container
```text
lxc exec vcpe bash -- dmcli eRT getv Device.DeviceInfo.
```

pull a file from a container
```text
lxc file pull vcpe/rdklogs/logs/WANManager.log.txt.0 .
```

push a file to a container
```text
lxc file push debug.ini vcpe/etc/debug.ini
```

stop start restart (reboot) a container

Note: stopping (restarting) a container is a graceful procedure and can take a few seconds to finish (due to dhcp release). A container can be forced stopped or restarted using the -f option. In this case ctrl-c twice to break the pending action and rerun the action with -f. or we can restart with console, to see the entire console during shutdown and startup


```text
lxc stop vcpe
lxc start vcpe
lxc restart vcpe
lxc restart vcpe -f

lxc restart vcpe --console

```

reboot a container

```text
lxc exec vcpe bash
root@RaspberryPi-Gateway:~$ reboot
#leaves the shell
```


# Probes

## getrdklogs
```text
getrdklogs.sh vcpe
```

## getlogs
```text
getlogs.sh vcpe
```


## acs tests

## usp tests

## webpa tests

# LXD UI

# LXD Metrics


## After a host reboot

All containers will come up in the stopped state, they all require a lxc start. All VCPE bridges (except lxdbr1) have to be re-created by running the bridges.sh script.

## Uninstall LXD from snap

```text
sudo snap remove lxd --purge
```
