# OpenShift in OpenStack using PXE
Below is the recipe to deploy an OpenShift cluster using PXE boot, for baremetal environment. But in this case, we will simulate baremetal with VM in OpenStack.
For this recipe, we will use the OpenStack CLI for most of the provisioning.

## Prerequisites
You can adjust the below information as required.

The External network is used to assign a Floating IP to the Load Balancer acting as the cluster API gateway.
- Your Public Key
	- name `adetalhouet`
- Networks
	- Management network
		- name `vlan197_net`
		- subnet `vlan192_subnet`
		- CIDR `10.195.197.0/24`
	- External network
		- name  `vlan200_net`
		- subnet `vlan200_subnet`
		- CIDR `10.195.200.0/24`
- OpenStack 
	- CentOS 8 image
		- name `centos`
	- DNS Designate
		- IP `10.195.194.16`
		- If you don't have Designate, you could deploy a DNS solution, such as `dnsmasq` and achieve the same. Make sure to adjust the IP address where necessary.

## Overall architecture
![architecture](https://github.com/adetalhouet/ocp-pxe/raw/master/doc/ocp-pxe-blog.png)

## Setup
### PXE Network
#### Create the network and the subnet
This private network will be use boot the hosts from a PXE server. It will then serve as internal network for the OpenShift cluster networking.
~~~
openstack network create --disable-port-security pxe_net
openstack subnet create --network pxe_net --dns-nameserver 10.195.194.16 --subnet-range 192.168.1.0/24 pxe_subnet
~~~
#### Create a router to enable external traffic
This will allow the hosts in the PXE network to resolve the Internet, and other tools, such as the DNS.
~~~
openstack router create --enable ocp-pxe
openstack router add subnet ocp-pxe pxe_subnet
openstack router set --external-gateway vlan200_net ocp-pxe
~~~
#### Create the ports for the cluster's Master and Worker hosts, as well as the Bastion and API GW hosts
This is where we simulate a baremetal deployment. We should assume these are all baremetal servers, hence their IP is pre-set.
It will be important later to get their MAC address for the PXE boot process.
~~~
openstack port create openshift.bastion  --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.125
openstack port create openshift.api.gw  --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.10
openstack port create openshift.bootstrap  --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.20
openstack port create openshift.master-0   --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.100
openstack port create openshift.master-1   --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.101
openstack port create openshift.master-2   --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.102
openstack port create openshift.worker-0   --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.200
openstack port create openshift.worker-1   --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.201
openstack port create openshift.worker-2   --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.202
~~~

### Bastion host
#### Create the instance
Bastion has an interface in the PXE network, setup with the static port create previously, and an interface in the Management network.
~~~
openstack server create --image centos8 --flavor m1.medium --key-name adetalhouet --port openshift.bastion --network vlan197_net bastion
~~~
#### Provision the Bastion host
Login into the instance `$ ssh centos@10.195.197.102` and install dependencies.
~~~
sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
mkdir $HOME/ocp-pxe
~~~
##### Setup TFTP server
This will be used to provide the default PXE configuration to the hosts when they boot.

The configuration is as follow

<details>
<summary>pxelinux.cfg/default</summary>

```
# /var/lib/tftpboot/pxelinux.cfg/default

DEFAULT menu.c32
PROMPT 0
TIMEOUT 300
ONTIMEOUT BOOTSTRAP

MENU TITLE PXE BOOT MENU

LABEL WORKER
  MENU LABEL ^1 WORKER
  KERNEL http://192.168.1.125:8080/rhcos/rhcos-kernel
  APPEND rd.neednet=1 initrd=http://192.168.1.125:8080/rhcos/rhcos-initramfs.img console=tty0,115200n8 coreos.inst=yes coreos.inst.install_dev=/dev/vda coreos.inst.ignition_url=http://192.168.1.125:8080/ignition/worker.ign coreos.live.rootfs_url=http://192.168.1.125:8080/rhcos/rhcos-live-rootfs ip=dhcp

LABEL MASTER
  MENU LABEL ^2 MASTER
  KERNEL http://192.168.1.125:8080/rhcos/rhcos-kernel
  APPEND rd.neednet=1 initrd=http://192.168.1.125:8080/rhcos/rhcos-initramfs.img console=tty0,115200n8 coreos.inst=yes coreos.inst.install_dev=/dev/vda coreos.inst.ignition_url=http://192.168.1.125:8080/ignition/master.ign coreos.live.rootfs_url=http://192.168.1.125:8080/rhcos/rhcos-live-rootfs ip=dhcp

LABEL BOOTSTRAP
  MENU LABEL ^3 BOOTSTRAP
  KERNEL http://192.168.1.125:8080/rhcos/rhcos-kernel
  APPEND rd.neednet=1 initrd=http://192.168.1.125:8080/rhcos/rhcos-initramfs.img console=tty0,115200n8 coreos.inst=yes coreos.inst.install_dev=/dev/vda coreos.inst.ignition_url=http://192.168.1.125:8080/ignition/bootstrap.ign coreos.live.rootfs_url=http://192.168.1.125:8080/rhcos/rhcos-live-rootfs ip=dhcp
```
</details>

Now, let's install the dependencies, and setup the TFTP server
~~~
sudo yum -y install tftp-server syslinux
sudo cp -r /usr/share/syslinux/* /var/lib/tftpboot
mkdir /var/lib/tftpboot/pxelinux.cfg
# copy the config above
vi $HOME/ocp-pxe/pxelinux.0 
sudo cp $HOME/ocp-pxe/pxelinux.0 /var/lib/tftpboot/pxelinux.cfg/default
sudo systemctl start tftp
sudo systemctl enable tftp
~~~
##### Setup PXE DHCP server
It needs to be configured as below. If you adjust some of the pre-requisite, or the PXE network setup, make sure to accordingly update the config.
Regardless, you need to edits the port MAC address. To do so, retrieve the ports and their MAC, and update below accordingly.

<details>
<summary>openstack port list --network pxe_net</summary>

```
~~~
$ openstack port list --network pxe_net
+--------------------------------------+---------------------+-------------------+------------------------------------------------------------------------------+--------+
| ID                                   | Name                | MAC Address       | Fixed IP Addresses                                                           | Status |
+--------------------------------------+---------------------+-------------------+------------------------------------------------------------------------------+--------+
| 22f93644-3e79-4cc9-8081-d04ce29fdf89 | openshift.bootstrap | fa:16:3e:01:73:40 | ip_address='192.168.1.20', subnet_id='3957eef9-ad9a-407e-bba6-8aa1c3865bb8'  | DOWN   |
| 368ac6b8-5069-4241-9261-b583578f43a3 | openshift.master-0  | fa:16:3e:79:51:c0 | ip_address='192.168.1.100', subnet_id='3957eef9-ad9a-407e-bba6-8aa1c3865bb8' | DOWN   |
| 3aef0d5d-68c9-4c64-92a3-0223f62b06bf | openshift.master-1  | fa:16:3e:02:87:7d | ip_address='192.168.1.101', subnet_id='3957eef9-ad9a-407e-bba6-8aa1c3865bb8' | DOWN   |
| 4341b040-74e5-4046-84b3-e2cdfbf7a07f | openshift.worker-0  | fa:16:3e:aa:fe:80 | ip_address='192.168.1.200', subnet_id='3957eef9-ad9a-407e-bba6-8aa1c3865bb8' | DOWN   |
| 508f93d7-7317-4c38-af42-c66e29999cd5 | openshift.worker-1  | fa:16:3e:5d:ad:2c | ip_address='192.168.1.201', subnet_id='3957eef9-ad9a-407e-bba6-8aa1c3865bb8' | DOWN   |
| 6dc72ffd-953a-413a-85dc-1971a91cc917 |                     | fa:16:3e:a6:12:53 | ip_address='192.168.1.2', subnet_id='3957eef9-ad9a-407e-bba6-8aa1c3865bb8'   | ACTIVE |
| 7ef40217-5273-401c-b218-095742905fa4 | openshift.bastion   | fa:16:3e:8f:4e:84 | ip_address='192.168.1.125', subnet_id='3957eef9-ad9a-407e-bba6-8aa1c3865bb8' | ACTIVE |
| 84ccd0c9-b0ff-49e0-a44d-0d391108909f | openshift.master-2  | fa:16:3e:9c:e3:5c | ip_address='192.168.1.102', subnet_id='3957eef9-ad9a-407e-bba6-8aa1c3865bb8' | DOWN   |
| d5cd3f55-5a61-438c-b83c-bbeb7370f565 |                     | fa:16:3e:42:66:b0 | ip_address='192.168.1.1', subnet_id='3957eef9-ad9a-407e-bba6-8aa1c3865bb8'   | ACTIVE |
| f62f8477-72c7-42be-98d7-69ee67c70019 | openshift.worker-2  | fa:16:3e:1a:cb:64 | ip_address='192.168.1.202', subnet_id='3957eef9-ad9a-407e-bba6-8aa1c3865bb8' | DOWN   |
| fd18ef7a-fe31-4b84-b3b9-463b9736f8ef | openshift.api.gw    | fa:16:3e:d6:6e:59 | ip_address='192.168.1.10', subnet_id='3957eef9-ad9a-407e-bba6-8aa1c3865bb8'  | DOWN   |
+--------------------------------------+---------------------+-------------------+------------------------------------------------------------------------------+--------+
```
</details>

Replace the MAC address below to match your environment.

<details>
<summary>dnsmasq-pxe.conf</summary>

```
# lease at /var/lib/dnsmasq/dnsmasq.leases

no-dhcp-interface=eth0
interface=eth1,lo

domain=ocp.adetalhouet.io

## DHCP
dhcp-range=eth1,192.168.1.10,192.168.1.250,24h
dhcp-option=option:netmask,255.255.255.0
dhcp-option=option:router,192.168.1.1
dhcp-option=option:dns-server,10.195.194.16
dhcp-option=option:ntp-server,204.11.201.10

## PXE
enable-tftp
tftp-root=/var/lib/tftpboot
pxe-service=x86PC, "Install OpenShift CoreOS", pxelinux

## Hosts
# Bootstrap
dhcp-host=fa:16:3e:01:73:40,192.168.1.10
# master-0, master-1, master-2
dhcp-host=fa:16:3e:79:51:c0,192.168.1.100
dhcp-host=fa:16:3e:02:87:7d,192.168.1.101
dhcp-host=fa:16:3e:9c:e3:5c,192.168.1.102
# worker-0, worker-1, worker-2
dhcp-host=fa:16:3e:aa:fe:80,192.168.1.200
dhcp-host=fa:16:3e:5d:ad:2c,192.168.1.201
dhcp-host=fa:16:3e:1a:cb:64,192.168.1.202
```
</details>

Now, let's install `dnsmasq`, apply the above config, and start it
~~~
sudo yum -y install dnsmasq
mkdir $HOME/ocp-pxe
vi $HOME/ocp-pxe/dnsmasq-pxe.conf #copy the config defined above
sudo cp $HOME/ocp-pxe/dnsmasq-pxe.conf /etc/dnsmasq.d/dnsmasq-pxe.conf
sudo systemctl start dnsmasq
sudo systemctl enable dnsmasq
~~~
##### Setup an HTTP server to serve the OS and Ignition files
While booting, the host will download their config from this HTTP server. For that, we use `nginx`
~~~
sudo yum -y install nginx
~~~
Now is the time where we need to decide which version of OpenShift to install. For that, update the below 3 parameters accordingly.
~~~
OCP_RELEASE_PATH=ocp # https://mirror.openshift.com/pub/openshift-v4/clients/
OCP_SUBRELEASE=4.6.9 # https://mirror.openshift.com/pub/openshift-v4/clients/ocp/
RHCOS_RELEASE=4.6 # https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/

sudo mkdir /usr/share/nginx/html/rhcos/
curl -J -L -O https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/${RHCOS_RELEASE}/latest/rhcos-live-initramfs.x86_64.img
curl -J -L -O https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/${RHCOS_RELEASE}/latest/rhcos-live-kernel-x86_64
curl -J -L -O https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/${RHCOS_RELEASE}/latest/rhcos-live-rootfs.x86_64.img
curl -J -L -O https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/${RHCOS_RELEASE}/latest/rhcos-openstack.x86_64.qcow2.gz
gunzip rhcos-openstack.x86_64.qcow2.gz
sudo mv rhcos-* /usr/share/nginx/html/rhcos/

curl -J -L -O https://mirror.openshift.com/pub/openshift-v4/clients/${OCP_RELEASE_PATH}/${OCP_SUBRELEASE}/openshift-client-linux-${OCP_SUBRELEASE}.tar.gz 
curl -J -L -O https://mirror.openshift.com/pub/openshift-v4/clients/${OCP_RELEASE_PATH}/${OCP_SUBRELEASE}/openshift-install-linux-${OCP_SUBRELEASE}.tar.gz
tar -xvf openshift-install-linux-${OCP_SUBRELEASE}.tar.gz
tar -xvf openshift-client-linux-${OCP_SUBRELEASE}.tar.gz
rm openshift-*-linux* README.md
~~~

Now, let's start the web server
~~~
sudo systemctl start nginx
sudo systemctl enable nginx
~~~
