#!/bin/bash

source gen-util.sh

container_name="automatics"

# Ensure base image exists
ensure_base_image "automatics-base" "automatics-base.sh"

# Profile configuration
profile_config='name: automatics
description: "automatics"
config:
    boot.autostart: "false"
    limits.cpu: ""      # "" effectively means no CPU limits, allowing access to all available CPUs
    limits.memory: ""   #
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
        size: 2GiB'

# Create container using standard function
create_standard_container "automatics-base" "$container_name" "$profile_config"

########################################################################################
# Network configuration

sleep 5

# Copy network configuration
copy_config_file "$M_ROOT/gen/configs/automatics.eth0.nmconnection" \
    "$container_name" "/etc/NetworkManager/system-connections/eth0.nmconnection" 600

# Restart NetworkManager and configure routes
lxc exec ${container_name} -- systemctl restart NetworkManager

# Configure automatics-specific routes
lxc exec ${container_name} -- nmcli connection modify eth0 +ipv4.routes "10.100.200.0/24 10.10.10.100"
lxc exec ${container_name} -- nmcli connection modify eth0 +ipv4.routes "10.107.200.0/24 10.10.10.107"
lxc exec ${container_name} -- nmcli connection modify eth0 +ipv4.routes "10.108.200.0/24 10.10.10.108"
lxc exec ${container_name} -- nmcli connection modify eth0 +ipv4.routes "10.120.200.0/24 10.10.10.120"
lxc exec ${container_name} -- nmcli connection modify eth0 +ipv4.routes "10.177.200.0/24 10.10.10.109"
lxc exec ${container_name} -- nmcli connection modify eth0 +ipv4.routes "10.178.200.0/24 10.10.10.109"
lxc exec ${container_name} -- nmcli connection modify eth0 +ipv6.routes "2001:dae:0:1::/64 2001:dbf:0:1::100"
lxc exec ${container_name} -- nmcli connection modify eth0 +ipv6.routes "2001:dae:7:1::/64 2001:dbf:0:1::107"
lxc exec ${container_name} -- nmcli connection modify eth0 +ipv6.routes "2001:dae:8:1::/64 2001:dbf:0:1::108" 
lxc exec ${container_name} -- nmcli connection modify eth0 +ipv6.routes "2001:dae:20:1::/64 2001:dbf:0:1::120"
lxc exec ${container_name} -- nmcli connection modify eth0 +ipv6.routes "2001:dbd:0:1::/64 2001:dbf:0:1::109"
lxc exec ${container_name} -- nmcli connection modify eth0 +ipv6.routes "2001:dbe:0:1::/64 2001:dbf:0:1::109"
lxc exec ${container_name} -- nmcli connection up eth0

###################################################################################################################################
#

lxc exec ${container_name} -- systemctl stop tomcat

###################################################################################################################################
# Install build configure deploy automatics-props

lxc exec ${container_name} -- bash -c 'cd /root && git clone https://code.rdkcentral.com/r/rdk/tools/automatics/automatics-props'
lxc exec ${container_name} -- bash -c "cd /root/automatics-props && /opt/apache-maven-3.9.10/bin/mvn install"

# create server-config.xml

lxc exec ${container_name} -- sh -c 'cat > /root/server-config.xml << '\''EOF'\''
<?xml version="1.0" encoding="utf-8"?>
<config>
  <system>
  <!--Logical Grouping of system -->
    <group name="Group_Name">
      <!-- For destination that requires login with private key, details can be configured in below format -->
      <machine name="10.107.200.110">
      <authorisation auth-type="private-key" username="root" password=""
      private-key=""/>
      </machine>
        <!-- For destination that requires login with password, details can be configured in below format -->
        <machine name="10.107.200.110">
        <authorisation auth-type="password" username="root" password=""/>
      </machine>
    </group>
  </system>
</config>
EOF'


# update automatics.properties

lxc exec ${container_name} -- sh -c '
sed -i \
  -e "s|^device\.props=$|device.props=http://localhost:8080/automatics/device_config.json|" \
  -e "s|^automatics\.url=$|automatics.url=http://localhost:8080/Automatics/|" \
  -e "s|^DEVICE_MANAGER_BASE_URL=$|DEVICE_MANAGER_BASE_URL=http://localhost:8080/DeviceManager/|" \
  /root/automatics-props/src/automatics.properties

cat >> /root/automatics-props/src/automatics.properties << EOF

serverConfig.path=/root/server-config.xml
SSH_CONNECTION_MAX_ATTEMPT=1
rdk.resp.wait.time.millisecs=1000
ssh_custom_port=22
service.base.url=http://localhost:8084/api/rack/service/
EOF
'



lxc exec ${container_name} -- mkdir -p /opt/automatics/apache-tomcat-9.0.102/backup_file/automatics/device
lxc exec ${container_name} -- cp /root/automatics-props/src/automatics.properties /opt/automatics/apache-tomcat-9.0.102/backup_file/automatics
lxc exec ${container_name} -- cp /root/automatics-props/src/device_config.json /opt/automatics/apache-tomcat-9.0.102/backup_file/automatics/device
lxc exec ${container_name} -- mkdir /opt/automatics/apache-tomcat-9.0.102/webapps/automatics
lxc exec ${container_name} -- cp /root/automatics-props/src/automatics.properties /opt/automatics/apache-tomcat-9.0.102/webapps/automatics
lxc exec ${container_name} -- cp /root/automatics-props/src/device_config.json /opt/automatics/apache-tomcat-9.0.102/webapps/automatics
lxc exec ${container_name} -- cp /root/automatics-props/src/config.properties /opt/automatics/apache-tomcat-9.0.102/webapps/automatics
lxc exec ${container_name} -- cp /root/automatics-props/src/user_management.properties /opt/automatics/apache-tomcat-9.0.102/webapps/automatics

lxc exec ${container_name} -- bash -c 'echo "john=b931cd522a614e767bcc48200819c520" > /opt/automatics/apache-tomcat-9.0.102/webapps/automatics/user_management.properties'
lxc exec ${container_name} -- sed -i 's/automatics\.properties\.passcode=/automatics.properties.passcode=YWRtaW46YXV0b21hdGljcw==/' /opt/automatics/apache-tomcat-9.0.102/webapps/automatics/config.properties

lxc exec ${container_name} -- cp /root/automatics-props/target/AutomaticsProps.war /opt/automatics/apache-tomcat-9.0.102/webapps/


###################################################################################################################################
# Install build configure deploy automatics-orchestration

lxc exec ${container_name} -- bash -c 'cd /root && git clone https://code.rdkcentral.com/r/rdk/tools/automatics'
lxc exec ${container_name} -- bash -c "cd /root/automatics && /opt/apache-maven-3.9.10/bin/mvn install"

# Create automatics database
lxc exec ${container_name} -- mysql -u root -e "CREATE DATABASE \`automatics\`;"
lxc exec ${container_name} -- mysql -u root automatics -e "SET foreign_key_checks=0; SOURCE /root/automatics/resources/Automatics_RDKB.sql;"
lxc exec ${container_name} -- mysql -u root automatics -e "SET foreign_key_checks=0; SOURCE /root/automatics/resources/Automatics_DB.sql;"
lxc exec ${container_name} -- mysql -u root automatics -e "SET foreign_key_checks=0; SOURCE /root/automatics/resources/Automatics_MySqlProcedures.sql;"

lxc exec ${container_name} -- cp /root/automatics/config/restartTMR.sh /opt/automatics/apache-tomcat-9.0.102/bin
lxc exec ${container_name} -- sed -i 's|JAVA_OPTS="$JAVA_OPTS $JSSE_OPTS"|JAVA_OPTS="$JAVA_OPTS $JSSE_OPTS -DAutomatics -DhibernateUI.config.file=/root/automatics/config/hibernate.cfg.xml -Dlog4j.configurationFile=/root/automatics/target/classes/log4j2-test.xml"|' /opt/automatics/apache-tomcat-9.0.102/bin/catalina.sh
lxc exec ${container_name} -- touch /opt/automatics/apache-tomcat-9.0.102/bin/childUI.jmd
lxc exec ${container_name} -- touch /opt/automatics/apache-tomcat-9.0.102/bin/mainUI.jmd

lxc exec automatics -- sh -c 'cp /root/automatics/releases/Automatics-v*/Automatics.war /opt/automatics/apache-tomcat-9.0.102/webapps/'

lxc exec ${container_name} -- sed -i 's|<property name="hibernate.connection.driver_class">com.mysql.jdbc.Driver</property>|<property name="hibernate.connection.driver_class">com.mysql.cj.jdbc.Driver</property>|g' /root/automatics/config/hibernate.cfg.xml
lxc exec ${container_name} -- sed -i 's|<property name="hibernate.connection.username"></property>|<property name="hibernate.connection.username">root</property>|g' /root/automatics/config/hibernate.cfg.xml
lxc exec ${container_name} -- sed -i 's|<property name="hibernate.connection.password"></property>|<property name="hibernate.connection.password">cm9vdA==</property>|g' /root/automatics/config/hibernate.cfg.xml


###################################################################################################################################
# Install configure build device-manager

lxc exec ${container_name} -- bash -c 'cd /root && git clone https://code.rdkcentral.com/r/rdk/tools/device-manager'

# Create device_manager database
lxc exec ${container_name} -- mysql -u root -e "CREATE DATABASE \`device_manager\`;"
lxc exec ${container_name} -- mysql -u root device_manager -e "SET foreign_key_checks=0; SOURCE /root/device-manager/src/main/resources/Device_Manager_DB.sql;"
lxc exec ${container_name} -- mysql -u root device_manager -e "ALTER TABLE user_details MODIFY \`PASSWORD\` VARCHAR(75);"
lxc exec ${container_name} -- mysql -u root device_manager -e "UPDATE user_details SET PASSWORD = \"\" WHERE USER_ID = \"admin\";"
lxc exec ${container_name} -- mysql -u root device_manager -e "UPDATE user_details SET EMAIL_ID = \"\" WHERE USER_ID = \"admin\";"
lxc exec ${container_name} -- mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'root'; FLUSH PRIVILEGES;"

# Set the database username (root) and password (root (in base64)) in application.properties
lxc exec ${container_name} -- sed -i 's/spring.datasource.username=/spring.datasource.username=root/' /root/device-manager/src/main/resources/application.properties
lxc exec ${container_name} -- sed -i 's/spring.datasource.password=/spring.datasource.password=cm9vdA==/' /root/device-manager/src/main/resources/application.properties

lxc exec ${container_name} -- bash -c "cd /root/device-manager && /opt/apache-maven-3.9.10/bin/mvn install"

###################################################################################################################################
# Install configure build device-manager-ui

lxc exec ${container_name} -- bash -c 'cd /root && git clone https://code.rdkcentral.com/r/rdk/tools/device-manager-ui'
lxc exec ${container_name} -- sed -i 's#DEVICE_MANAGER_BASE_URL=#DEVICE_MANAGER_BASE_URL=http://localhost:8080/DeviceManager/#' /root/device-manager-ui/src/main/resources/application.properties
lxc exec ${container_name} -- bash -c "cd /root/device-manager-ui && /opt/apache-maven-3.9.10/bin/mvn install"

###################################################################################################################################
# Deploy device-manager

lxc exec ${container_name} -- cp /root/device-manager/target/device-manager-1.0.5.war /opt/automatics/apache-tomcat-9.0.102/webapps/DeviceManager.war

###################################################################################################################################
# Deploy device-manager-ui

lxc exec ${container_name} -- cp /root/device-manager-ui/target/DeviceManagerUI.war /opt/automatics/apache-tomcat-9.0.102/webapps/

###################################################################################################################################
# Install build automatics-core

lxc exec ${container_name} -- bash -c 'cd /root/ && git clone https://code.rdkcentral.com/r/rdk/tools/automatics/automatics-core'
lxc exec ${container_name} -- bash -c 'cd /root/automatics-core/ && /opt/apache-maven-3.9.10/bin/mvn install'

###################################################################################################################################
# Install build rpi-provider

lxc exec ${container_name} -- bash -c 'cd /root/ && git clone https://code.rdkcentral.com/r/rdk/tools/automatics/rpi-provider/java-handler'

# apply patch
lxc file push gen/patches/automatics/java-handler/0001-fixups.patch automatics/root/java-handler/
lxc exec ${container_name} -- bash -c 'cd /root/java-handler/ && git am 0001-fixups.patch'

lxc exec ${container_name} -- bash -c 'cd /root/java-handler/ && /opt/apache-maven-3.9.10/bin/mvn install -DskipTests'

###################################################################################################################################
# Install RDKB tests

lxc exec ${container_name} -- bash -c 'cd /root/ && git clone https://code.rdkcentral.com/r/rdk/tools/automatics/rdkb-test-utils'
lxc exec ${container_name} -- bash -c 'cd /root/rdkb-test-utils/ && /opt/apache-maven-3.9.10/bin/mvn clean install'

lxc exec ${container_name} -- bash -c 'cd /root/ && git clone https://code.rdkcentral.com/r/rdk/tools/automatics/rdkb-tests'

# add rpi provider dependency

lxc exec ${container_name} -- sed -i '/<\/dependencies>/i\
               <dependency>\
                       <groupId>com.automatics.providers</groupId>\
                       <artifactId>rpi-provider-impl</artifactId>\
                       <version>0.0.1-SNAPSHOT</version>\
               </dependency>' /root/rdkb-tests/pom.xml


lxc exec ${container_name} -- bash -c 'cd /root/rdkb-tests/ && /opt/apache-maven-3.9.10/bin/mvn clean install -DskipTests'

lxc exec ${container_name} -- bash -c 'cd /root/ && git clone https://code.rdkcentral.com/r/rdk/tools/automatics/generic-automation-tests'
lxc exec ${container_name} -- bash -c 'cd /root/generic-automation-tests/ && /opt/apache-maven-3.9.10/bin/mvn clean install -DskipTests'


###################################################################################################################################
# Install scriptless service

lxc exec ${container_name} -- bash -c 'cd /root/ && git clone https://code.rdkcentral.com/r/rdk/tools/automatics/scriptless-service'
lxc exec ${container_name} -- sed -i 's/spring.datasource.username=/spring.datasource.username=root/' /root/scriptless-service/RackDataService/src/main/resources/application.properties
lxc exec ${container_name} -- sed -i 's/spring.datasource.password=/spring.datasource.password=cm9vdA==/' /root/scriptless-service/RackDataService/src/main/resources/application.properties
lxc exec ${container_name} -- bash -c 'cd /root/scriptless-service/RackDataService && /opt/apache-maven-3.9.10/bin/mvn clean install'

# Install systemd service

rackdata_service='[Unit]
Description=Rack Data Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/scriptless-service/RackDataService/target
ExecStart=/usr/bin/java -XX:+UseSerialGC -Dlog4j2.formatMsgNoLookups=true -jar rackdataservice-1.0.9.jar
Restart=always
RestartSec=10
StandardOutput=file:/root/scriptless-service/RackDataService/target/logfile.log
StandardError=file:/root/scriptless-service/RackDataService/target/logfile.log

[Install]
WantedBy=multi-user.target'

create_systemd_service "$container_name" "rackdata" "$rackdata_service"
start_systemd_service "$container_name" "rackdata"

###################################################################################################################################
###################################################################################################################################

###################################################################################################################################
# start tomcat

lxc exec ${container_name} -- systemctl start tomcat

# wait for tomcat
lxc exec ${container_name} -- sh -c 'timeout 120 sh -c "while ! nc -z localhost 8080; do sleep 2; done"'

# add devices
lxc exec ${container_name} -- curl -X POST "http://localhost:8080/DeviceManager/device/add" -H "accept: application/json" -H "Content-Type: application/json" -d '{
 "accountId": 123456,
 "createdBy": "admin",
 "createdDate": "2025-06-09T20:24:20.884Z",
 "deletedDate": "2025-06-09T20:24:20.884Z",
 "deviceCategoryName": "RDKB",
 "deviceGroupName": "RDKB_EXEC",
 "deviceId": 123456,
 "deviceModelName": "Rpi-RDKB",
 "deviceRackDtls": "Rpi_device",
 "deviceStatus": "GOOD",
 "ecmIpAddress": "1:1:1:1",
 "ecmMacAddress": "DC:A6:32:CA:11:B6",
 "extraProperties": {
   "username": "",
   "password": "",
   "connectionType": "",
   "wifiCapability": "",
   "wifiMacAddress": "",
   "ethernetMacAddress": "",
   "devicePort": "",
   "deviceIp": "",
   "osType": "",
   "nodePort": ""
 },
 "featureNames": [
   "rdkb"
 ],
 "firmwareVersion": "Rpi-RDKB",
 "gatewayMacAddress": "DC:A6:32:CA:11:B6",
 "hardwareVersion": "SLN567",
 "headEndName": "HE",
 "ipAddress": "10.107.200.110",
 "ipType": "IPV4",
 "isExcludedFromPool": "N",
 "macAddress": "DC:A6:32:CA:11:B6",
 "mtaIpAddress": "10.107.200.110",
 "mtaMacAddress": "DC:A6:32:CA:11:B6",
 "phoneNumber": 90932413284,
 "serialNumber": "HYU890",
 "serviceAccId": 12431234,
 "slotNumber": "SL1",
 "statusRemarks": "Device is Good",
 "updatedDate": "2025-06-09T20:24:20.884Z",
 "updatedUser": "admin"
}'

lxc exec ${container_name} -- curl -X POST "http://localhost:8080/DeviceManager/device/add" -H "accept: application/json" -H "Content-Type: application/json" -d '{
 "accountId": 123456,
 "createdBy": "admin",
 "createdDate": "2025-06-09T20:24:20.884Z",
 "deletedDate": "2025-06-09T20:24:20.884Z",
 "deviceCategoryName": "RDKB",
 "deviceGroupName": "RDKB_EXEC",
 "deviceId": 123456,
 "deviceModelName": "Rpi-RDKB",
 "deviceRackDtls": "Rpi_device",
 "deviceStatus": "GOOD",
 "ecmIpAddress": "1:1:1:1",
 "ecmMacAddress": "00:16:3E:20:79:68",
 "extraProperties": {
   "username": "",
   "password": "",
   "connectionType": "",
   "wifiCapability": "",
   "wifiMacAddress": "",
   "ethernetMacAddress": "",
   "devicePort": "",
   "deviceIp": "",
   "osType": "",
   "nodePort": ""
 },
 "featureNames": [
   "rdkb"
 ],
 "firmwareVersion": "Rpi-RDKB",
 "gatewayMacAddress": "00:16:3E:20:79:68",
 "hardwareVersion": "SLN567",
 "headEndName": "HE",
 "ipAddress": "10.107.200.127",
 "ipType": "IPV4",
 "isExcludedFromPool": "N",
 "macAddress": "00:16:3E:20:79:68",
 "mtaIpAddress": "10.107.200.127",
 "mtaMacAddress": "00:16:3E:20:79:68",
 "phoneNumber": 90932413284,
 "serialNumber": "HYU890",
 "serviceAccId": 12431234,
 "slotNumber": "SL1",
 "statusRemarks": "Device is Good",
 "updatedDate": "2025-06-09T20:24:20.884Z",
 "updatedUser": "admin"
}'
