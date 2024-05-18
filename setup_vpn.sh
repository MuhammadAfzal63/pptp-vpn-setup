#!/bin/bash

if dpkg-query -W needrestart >/dev/null 2>&1; then
    sudo sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf
fi

# Get the interface name for the WAN connection using ip a command
INTERFACE_NAME=$(ip a | awk '/state UP/ {print $2}' | tr -d ':')
if [[ $INTERFACE_NAME == *"w"* ]]
then
    # WLAN connection detected
    wan=$(ip -f inet -o addr show $INTERFACE_NAME|cut -d\  -f 7 | cut -d/ -f 1)
else
    # Ethernet connection detected
    wan=$(ip -f inet -o addr show $INTERFACE_NAME|cut -d\  -f 7 | cut -d/ -f 1)
fi

ppp1=$(/sbin/ip route | awk '/default/ { print $3 }')
ip=$(dig +short myip.opendns.com @resolver1.opendns.com)

# Installing pptpd
echo "Installing PPTPD"
sudo apt-get update
sudo apt-get install pptpd -y

# edit DNS
echo "Setting Google DNS"
sudo bash -c 'echo "ms-dns 8.8.8.8" >> /etc/ppp/pptpd-options'
sudo bash -c 'echo "ms-dns 8.8.4.4" >> /etc/ppp/pptpd-options'

# Edit PPTP Configuration
echo "Editing PPTP Configuration"
remote="$ppp1"
remote+="0-200"
sudo bash -c "echo 'localip $ppp1' >> /etc/pptpd.conf"
sudo bash -c "echo 'remoteip $remote' >> /etc/pptpd.conf"

# Enabling IP forwarding in PPTP server
echo "Enabling IP forwarding in PPTP server"
sudo bash -c 'echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf'
sudo sysctl -p

# Tinkering in Firewall
echo "Configuring Firewall"
if [ -z "$wan" ]
then
    sudo iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
    sudo iptables --table nat --append POSTROUTING --out-interface ppp0 -j MASQUERADE
    sudo iptables -I INPUT -s $ip/8 -i ppp0 -j ACCEPT
    sudo iptables --append FORWARD --in-interface wlan0 -j ACCEPT
else
    sudo iptables -t nat -A POSTROUTING -o $INTERFACE_NAME -j MASQUERADE
    sudo iptables --table nat --append POSTROUTING --out-interface ppp0 -j MASQUERADE
    sudo iptables -I INPUT -s $ip/8 -i ppp0 -j ACCEPT
    sudo iptables --append FORWARD --in-interface $INTERFACE_NAME -j ACCEPT
fi

sudo iptables-save

# Adding VPN Users
echo "Set username:"
read username
echo "Set password:"
read -s password
sudo bash -c "echo '$username * $password *' >> /etc/ppp/chap-secrets"

# Restarting Service 
sudo service pptpd restart

echo "All done!"
