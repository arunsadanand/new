#!/bin/bash

# Parsing arguments

dcs=$1
deviceId=$2
fqdn=$3
if [ $# -eq 7 ]; then
    #top layer with proxy and ACR
    proxySettings=$4
    acrAddress=$5
    acrUsername=$6
    acrPassword=$7
elif [ $# -eq 5 ]; then
    #middle or bottom layer with proxy
    parentFqdn=$4
    proxySettings=$5
else
    #middle or bottom layer
    parentFqdn=$4
fi

# Validating parameters
echo "Executing script with parameters:"
echo "- Device connection string: ${dcs}"
echo "- Device Id: ${deviceId}"
echo "- FQDN: ${fqdn}"
echo "- Parent FQDN: ${parentFqdn}"
echo "- ProxySettings: ${proxySettings}"
echo "- ACR address: ${acrAddress}"
echo "- ACR username: ${acrUsername}"
echo "- ACR password: ${acrPassword}"
echo ""
if [ -z ${dcs} ]; then
    echo "Missing device connection string. Please pass a device connection string as a primary parameter. Exiting."
    exit 1
fi
if [ -z ${deviceId} ]; then
    echo "Missing device Fully Domain Qualified Name (FQDN). Please pass a FQDN as a secondary parameter. Exiting."
    exit 1
fi
if [ -z ${fqdn} ]; then
    echo "Missing device Fully Domain Qualified Name (FQDN). Please pass a FQDN as a secondary parameter. Exiting."
    exit 1
fi

# Waiting for IoT Edge installation to be complete
i=0
iotedgeConfigFile="/etc/iotedge/config.yaml"
while [[ ! -f "$iotedgeConfigFile" ]]; do
    echo "Waiting 10s for IoT Edge to complete its installation"
    sleep 10
    ((i++))
    if [ $i -gt 30 ]; then
        echo "Something went wrong in the installation of IoT Edge. Please install IoT Edge first. Exiting."
        exit 1
   fi
done
echo "Installation of IoT Edge is complete."
echo ""

# Waiting for installation of certificates to be complete
i=0
deviceCaCertFile="/certs/certs/certs/iot-edge-device-$deviceId-full-chain.cert.pem"
while [[ ! -f "$deviceCaCertFile" ]]; do
    echo "Waiting 10s for installation of certificates to complete"
    sleep 10
    ((i++))
    if [ $i -gt 30 ]; then
        echo "Something went wrong in the installation of certificates. Please install certificates first. Exiting."
        exit 1
   fi
done
echo "Installation of certificates is complete. Starting configuration of the IoT Edge device."
echo ""

# Configuring IoT Edge
echo "Updating the device connection string"
sudo sed -i "s#\(device_connection_string: \).*#\1\"$dcs\"#g" /etc/iotedge/config.yaml

echo "Updating the device hostname"
sudo sed -i "224s/.*/hostname: \"$fqdn\"/" /etc/iotedge/config.yaml

if [ ! -z $parentFqdn ]; then
    echo "Updating the parent hostname"
    sudo sed -i "237s/.*/parent_hostname: \"$parentFqdn\"/" /etc/iotedge/config.yaml
fi

echo "Updating the version of the bootstrapping edgeAgent to be the public preview one"
if [ -z $parentFqdn ]; then
    edgeAgentImage="$acrAddress:443/azureiotedge-agent:1.2.0-rc2"
else
    edgeAgentImage="$parentFqdn:443/azureiotedge-agent:1.2.0-rc2"
fi
sudo sed -i "207s|.*|    image: \"${edgeAgentImage}\"|" /etc/iotedge/config.yaml

if [ -z $parentFqdn ]; then
    echo "Adding ACR credentials for IoT Edge daemon to download the bootstrapping edgeAgent"
    sudo sed -i "208s|.*|    auth:|" /etc/iotedge/config.yaml
    sed -i "209i\      serveraddress: \"${acrAddress}\"" /etc/iotedge/config.yaml
    sed -i "210i\      username: \"${acrUsername}\"" /etc/iotedge/config.yaml
    sed -i "211i\      password: \"${acrPassword}\"" /etc/iotedge/config.yaml
fi

#echo "Configuring the bootstrapping edgeAgent to use AMQP/WS"
#sudo sed -i "205s|.*|  env:|" /etc/iotedge/config.yaml
sudo sed -i "206i\#    UpstreamProtocol: \"AmqpWs\"" /etc/iotedge/config.yaml

if [ ! -z $proxySettings ]; then
    echo "Configuring the bootstrapping edgeAgent to use http proxy"
    sudo sed -i "205s|.*|  env:|" /etc/iotedge/config.yaml
    httpProxyAddress=$(echo $proxySettings | cut -d "=" -f2-)
    sudo sed -i "207i\    https_proxy: \"${httpProxyAddress}\"" /etc/iotedge/config.yaml

    echo "Adding proxy configuration to docker"
    sudo mkdir -p /etc/systemd/system/docker.service.d/
    { echo "[Service]";
    echo "Environment=${proxySettings}";
    } | sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf
    sudo systemctl daemon-reload
    sudo systemctl restart docker

    echo "Adding proxy configuration to IoT Edge daemon"
    sudo mkdir -p /etc/systemd/system/iotedge.service.d/
    { echo "[Service]";
    echo "Environment=${proxySettings}";
    } | sudo tee /etc/systemd/system/iotedge.service.d/proxy.conf
    sudo systemctl daemon-reload
fi

echo "Restarting IoT Edge to apply new configuration"
sudo systemctl unmask iotedge
sudo systemctl start iotedge

echo "Done."