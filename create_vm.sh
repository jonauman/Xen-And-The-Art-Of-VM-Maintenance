#!/bin/bash
############################
# Usage
############################
# 
#  This simple script currently supports CentOS and Debian VMs, because that is what we use. 
#  It will run a completely automated install via kickstart or preseed.
# 
# ./create_vm.sh -n <vm_name> -m <memory_in_MB> -c <number of CPUS> -d <disk_in_GB> -i <ip address> -f flavor [debian|centos]
#
# Example:
# --------
# ./create_vm.sh -n dc1-int-test01 -m 2048 -c 2 -d 20 -i 192.168.120.12 -f centos
#
# Asumptions:
# ===========
# network:  You must supply an IP address (-i) to the script. It is assumed that
#           you are using /24 subnet mask with the .1 address used for the gateway.
#           The network VLAN is also assumed to match the 3rd octet of the IP address.
#           Example: IP address : 192.168.130.11
#                    Gateway    : 192.168.130.1
#                    VLAN       : 130
#           If this does not match your network setup, it would be trivial to add a gateway
#           and VLAN parameter
#   
# template: assumes you have an appropriate template for the OS on your XenServer
#
# iso:      assumes you have the appropriate iso available to your XenServer in your iso storage repository
#
# ksserver: kickstart server for your CentOS/Redhat kickstart script
# psserver: preseed server for your Debian/Ubuntu preseed script 
#
############################
# vars
############################
debian_template='Debian Wheezy 7.0 (64-bit)'
centos_template='CentOS 6 (64-bit)'
debian_iso='debian-7.1.0-amd64-CD-1.iso'
centos_iso='CentOS-6.4-x86_64-minimal.iso'
domain='medic'
netmask='255.255.255.0'
nameserver='8.8.8.8'
ksserver='192.168.130.10'
psserver='192.168.130.10'

############################
if ( ! getopts "n:m:c:d:i:f:" opt); then
    echo ""
    echo "Usage: "
    echo "$0 -n <vm_name> -m <memory_in_MB> -c <number of CPUS> -d <disk_in_GB> -i <ip address> -f flavor [debian|centos]"
    echo ""
    echo "Example:"
    echo "--------"
    echo "$0 -n dc1-int-test01 -m 2048 -c 2 -d 20 -i 192.168.120.12 -f centos"
    echo ""
    exit 1
fi

while getopts "n:m:c:d:i:f:" opt; do
  case $opt in
    n)
      vm_name=$OPTARG
      ;;
    m)
      memory=$(($OPTARG*1024*1024))
      ;;

    c)
      cpu=$OPTARG
      ;;
    d)
      disk_size=$OPTARG
      ;;
    i)
      ip=$OPTARG
      ;;
    f)
      flavor=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

############################
# Set variables:

# GATEWAY
gateway=$(echo $ip|awk -F"." '{print $1"."$2"."$3".1"}')

# VLAN
vlan=$(echo $ip|awk -F"." '{print "vlan"$3 }')

# OS
if [ $flavor == 'centos' ]; then
  iso=$centos_iso
  template=$centos_template
else
  iso=$debian_iso
  template=$debian_template
fi

#### VM ####
# create VM and capture uuid
vm_uuid=$(xe vm-install new-name-label=$vm_name template="$template")
echo "VM uuid is $vm_uuid"

#### virtual disk ####
# get disk uuid
disk_uuid=$(xe vbd-list vm-uuid=$vm_uuid userdevice=0 params=uuid --minimal)
echo "disk uuid is $disk_uuid"

# set disk size #
vdi_uuid=$(xe vbd-param-get uuid=${disk_uuid} param-name=vdi-uuid)
echo "vdi_uuid is $vdi_uuid"
xe vdi-resize disk-size=${disk_size}GiB uuid=${vdi_uuid}

# name disk
xe vdi-param-set uuid=$vdi_uuid name-label=${vm_name}-root

# set disk unbootable
xe vbd-param-set uuid=$disk_uuid bootable=false
echo "setting $disk_uuid unbootable"

#### set memory ####
xe vm-memory-limits-set vm=${vm_name} dynamic-max=$memory dynamic-min=$memory static-max=$memory static-min=$memory

#### set VCPU ####
xe vm-param-set uuid=$vm_uuid VCPUs-max=$cpu VCPUs-at-startup=$cpu

####CD Boot ####
# boot to iso file
xe vm-cd-add vm=$vm_name cd-name="$iso" device=3
echo "inserting $iso ..."

# Get the UUID of the VBD corresponding to the new virtual CD drive
cd_uuid=$(xe vbd-list vm-uuid=$vm_uuid type=CD params=uuid --minimal)
echo "CD uuid is $cd_uuid"

# Make the VBD of the virtual CD bootable:
xe vbd-param-set uuid=$cd_uuid bootable=true
echo "making cd bootable..."

# Set the install repository of the VM to be the CD drive:
xe vm-param-set uuid=$vm_uuid other-config:install-repository=cdrom

#### network ####
# Find the UUID of the network that you want to connect to

network_uuid=$(xe network-list name-label=${vlan} params=uuid --minimal)
echo "network_uuid id $network_uuid"
#Create a VIF to connect the new VM to this network

xe vif-create vm-uuid=$vm_uuid network-uuid=$network_uuid mac=random device=0

echo "creating VIF for $vlan with net uuid of $network_uuid"
echo "IP is $ip"
echo "Gateway is $gateway"

#### other config ####
if [ $flavor == 'centos' ];then
  xe vm-param-set uuid=$vm_uuid \
  PV-args="console=hvc0 \
  utf8 \
  nogpt \
  ip=$ip:1:$gateway:255.255.255.0:$vm_name:eth0:off \
  nameserver=$nameserver \
  noipv6 \
  ks=http://${ks-server}/config/ks.php?vm_name=${vm_name}&ip=${ip}&nm=255.255.255.0&gw=${gateway}&ns=$nameserver"

else
  # assume debian
  xe vm-param-set uuid=$vm_uuid \
  PV-args="auto=true \
  locale=en_GB.UTF-8 \
  console-keymaps-at/keymap=gb \
  interface=eth0 \
  hostname=$vm_name \
  netcfg/get_domain=$domain \
  netcfg/get_ipaddress=$ip \
  netcfg/get_netmask=255.255.255.0 \
  netcfg/get_gateway=$gateway \
  netcfg/get_nameservers=$nameserver \
  netcfg/disable_dhcp=true \
  url=http://${ps-server}/config/preseed.cfg"
fi

#### Start VM ####
# start the VM
xe vm-start uuid=$vm_uuid
