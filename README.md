Xen-And-The-Art-Of-VM-Maintenance
=================================

Creates Linux VMs on Citrix XenServer
This simple script currently supports CentOS and Debian VMs, because that is what we use. 
It will run a completely automated install via kickstart or preseed.

Usage 

``` 
./create_vm.sh -n <vm_name> -m <memory_in_MB> -c <number of CPUS> -d <disk_in_GB> -i <ip address> -f flavor [debian|centos]
```

  Example:
  --------
```
 ./create_vm.sh -n dc1-int-test01 -m 2048 -c 2 -d 20 -i 192.168.120.12 -f centos
```
 Asumptions:
 ----------- 
  **network:**
  * You must supply an IP address (-i) to the script. It is assumed that
            you are using /24 subnet mask with the .1 address used for the gateway.
            The network VLAN is also assumed to match the 3rd octet of the IP address.
  *          Example:
    * IP address : 192.168.130.11
    * Gateway    : 192.168.130.1
    * VLAN       : 130
  * If this does not match your network setup, it would be trivial to add a gateway and VLAN parameter
   

  **template:** assumes you have an appropriate template for the OS on your XenServer


  **iso:**      assumes you have the appropriate iso available to your XenServer in your iso storage repository


  **ksserver:** kickstart server for your CentOS/Redhat kickstart script


  **psserver:** preseed server for your Debian/Ubuntu preseed script 

