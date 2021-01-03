credits to https://github.com/williamcaban/ocp4-lab

# OpenShift in OpenStack using PXE
Below is the recipe to deploy an OpenShift cluster using PXE boot, for baremetal environment. But in this case, we will simulate baremetal with VM in OpenStack.
For this recipe, we will use the OpenStack CLI for most of the provisioning.

1. [Pre-requisites](#prerequisites)
2. [Architecture](#architecture)
3. [Setup](#setup)
	- [PXE Boot image](#pxebootimage)
	- [API GW](#apigw)
	- [DNS Zones](#dnszones)
	- [PXE Network](#pxenetwork)
	- [Bastion](#bastion)
4. [Deploy OpenShift Cluster](#deployocp)
	- [Prepare ignition files](#ignition)
	- [Deploy Boostrap host](#bootstrap)
	- [Deploy Master hosts](#master)
	- [Deploy Worker hosts](#worker)
4. [Validate cluster status](#clusterstatus)

## Pre-requisites <a name="prerequisites"></a>
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

## Overall architecture <a name="architecture"></a>
![architecture](https://github.com/adetalhouet/ocp-pxe/raw/master/images/ocp-pxe-blog.png)

### Hosts
| Hosts | IP |
|---------|:----:|
| api-gw | 192.168.1.10 |
| bootstrap | 192.168.1.20 |
| master-0  | 192.168.1.100 |
| master-1   | 192.168.1.101 |
| master-2 | 192.168.1.102 |
| worker-0  | 192.168.1.200 |
| worker-1   | 192.168.1.201 |
| worker-2 | 192.168.1.202 |
## Setup <a name="setup"></a>
### PXE Boot image <a name="pxebootimage"></a>
Create a small empty disk file, create dos filesystem.
~~~
dd if=/dev/zero of=pxeboot.img bs=1M count=4
mkdosfs pxeboot.img
~~~
Make it bootable by syslinux
~~~
losetup /dev/loop0 pxeboot.img
syslinux --install /dev/loop0
mount /dev/loop0 /mnt
~~~
Install iPXE kernel and make sysliux.cfg to load it at bootup
~~~
wget http://boot.ipxe.org/ipxe.iso
mount -o loop ipxe.iso /media
cp /media/ipxe.krn /mnt
cat > /mnt/syslinux.cfg <<EOF
DEFAULT ipxe
LABEL ipxe
 KERNEL ipxe.krn
EOF
umount /media/
umount /mnt
~~~
Create the image in OpenStack
~~~
openstack image create --disk-format raw --container-format bare --public --file pxeboot.img pxeboot
~~~
### DNS Zones <a name="dnszones"></a>
#### Forward Zone
In order to provide reachibility to the API of OpenShift, let's create a Floating IP from our External network.
~~~
$ openstack floating ip create --description "OCP API VIP" vlan200_net | awk '$2=="floating_ip_address" {print $4}'
10.195.200.143
~~~
Adjust the `DOMAIN`, `CLUSTER_NAME` and `EXT_IP` based on your environment. 
The `EXT_IP` is what you got just above.
Make sure the `DOMAIN` ends with a `.` as it represents a domain.
~~~
DOMAIN=adetalhouet.io.
CLUSTER_NAME=ocp
EXT_IP=10.195.200.143
DNS_DOMAIN=$CLUSTER_NAME.$DOMAIN

## DNS ZONE
OCP_ZONE=$(openstack zone create --email adetalhouet89@gmail.com $DNS_DOMAIN |  awk '$2=="id" {print $4}')
### API
openstack recordset create --type A --records $EXT_IP --ttl 3600 $OCP_ZONE *.apps.$DNS_DOMAIN
openstack recordset create --type A --records $EXT_IP --ttl 3600 $OCP_ZONE api.$DNS_DOMAIN
openstack recordset create --type A --records 192.168.1.10 --ttl 3600 $OCP_ZONE api-int.$DNS_DOMAIN
### ETCD
openstack recordset create --type A --records 192.168.1.100 --ttl 3600 $OCP_ZONE etcd-0.$DNS_DOMAIN
openstack recordset create --type A --records 192.168.1.101 --ttl 3600 $OCP_ZONE etcd-1.$DNS_DOMAIN
openstack recordset create --type A --records 192.168.1.102 --ttl 3600 $OCP_ZONE etcd-2.$DNS_DOMAIN
openstack recordset create --type SRV --records "10 0 2380 etcd-0.$DNS_DOMAIN" "10 0 2380 etcd-1.$DNS_DOMAIN" "10 0 2380 etcd-2.$DNS_DOMAIN" --ttl 3600 $OCP_ZONE _etcd-server-ssl._tcp.$DNS_DOMAIN
### Hosts
openstack recordset create --type A --records 192.168.1.10 --ttl 3600 $OCP_ZONE api-gw.$DNS_DOMAIN
openstack recordset create --type A --records 192.168.1.20 --ttl 3600 $OCP_ZONE boostrap.$DNS_DOMAIN
openstack recordset create --type A --records 192.168.1.100 --ttl 3600 $OCP_ZONE master-0.$DNS_DOMAIN
openstack recordset create --type A --records 192.168.1.101 --ttl 3600 $OCP_ZONE master-1.$DNS_DOMAIN
openstack recordset create --type A --records 192.168.1.102 --ttl 3600 $OCP_ZONE master-2.$DNS_DOMAIN
openstack recordset create --type A --records 192.168.1.200 --ttl 3600 $OCP_ZONE worker-0.$DNS_DOMAIN
openstack recordset create --type A --records 192.168.1.201 --ttl 3600 $OCP_ZONE worker-1.$DNS_DOMAIN
openstack recordset create --type A --records 192.168.1.202 --ttl 3600 $OCP_ZONE worker-2.$DNS_DOMAIN
~~~
#### Reverse Zone
DNS Reverse zone for Red Hat Enterprise Linux CoreOS (RHCOS) that uses the reverse records to set the host name for all the nodes
~~~
OCP_REVERSE_ZONE=$(openstack zone create --email adetalhouet89@gmail.com 1.168.192.in-addr.arpa. |  awk '$2=="id" {print $4}')
openstack recordset create --type PTR --records api-gw.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 10.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records boostrap.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 20.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records master-0.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 100.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records master-1.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 101.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records master-2.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 102.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records worker-0.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 200.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records worker-1.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 201.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records worker-2.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 202.1.168.192.in-addr.arpa.
~~~
### PXE Network <a name="pxenetwork"></a>
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
### API GW <a name="apigw"></a>
This will serve as Load Balancer accross the Master and Worker nodes, and will be configured using `haproxy`
Let's start by creating the instance
~~~
openstack server create --image centos8 --flavor m1.medium --key-name adetalhouet --port openshift.api.gw api-gw
~~~
Then, let's attach the Floating IP, created during the DNS setup, to the `openshift.api.gw` port, to enable external reachibility.
~~~
openstack floating ip set --port openshift.api.gw 10.195.200.143
~~~

The applied `haproxy` configuration is as follow; make sure to update according to your environment
<details>
<summary>haproxy.cfg</summary>

```
# /opt/haproxy/haproxy.cfg

global
    log 127.0.0.1:514 local0

defaults
	mode                	http
	log                 	global
	option              	httplog
	option              	dontlognull
	option forwardfor   	except 127.0.0.0/8
	option              	redispatch
	retries             	3
	timeout http-request	10s
	timeout queue       	1m
	timeout connect     	10s
	timeout client      	300s
	timeout server      	300s
	timeout http-keep-alive 10s
	timeout check       	10s
	maxconn             	20000

frontend openshift-api-server
	bind *:6443
	default_backend openshift-api-server
	mode tcp
	option tcplog

backend openshift-api-server
	balance source
	mode tcp
	server bootstrap 192.168.1.20:6443 check
	server master-0 192.168.1.100:6443 check
	server master-1 192.168.1.101:6443 check
	server master-2 192.168.1.102:6443 check
    
frontend machine-config-server
	bind *:22623
	default_backend machine-config-server
	mode tcp
	option tcplog

backend machine-config-server
	balance source
	mode tcp
	server bootstrap 192.168.1.20:22623 check
	server master-0 192.168.1.100:22623 check
	server master-1 192.168.1.101:22623 check
	server master-2 192.168.1.102:22623 check

frontend ingress-http
	bind *:80
	default_backend ingress-http
	mode tcp
	option tcplog

backend ingress-http
	balance source
	mode tcp
	server worker-0 192.168.1.200:80 check
	server worker-1 192.168.1.201:80 check
	server worker-2 192.168.1.202:80 check
   
frontend ingress-https
	bind *:443
	default_backend ingress-https
	mode tcp
	option tcplog

backend ingress-https
	balance source
	mode tcp
	server worker-0 192.168.1.200:443 check
	server worker-1 192.168.1.201:443 check
	server worker-2 192.168.1.202:443 check
```
</details>

Now, login into the instance, and let's setup the load balancer.
~~~
ssh centos@10.195.200.143
sudo yum -y install haproxy
# copy the config above
sudo vi /etc/haproxy/haproxy.cfg
# Configure SELinux HTTP policy to enable HAProxy to bind to OpenShift API Server and Machine Config Server
sudo semanage port -a -t http_port_t -p tcp 6443
sudo semanage port -a -t http_port_t -p tcp 22623
# To accept asymmetrically routed packets
echo "net.ipv4.conf.default.rp_filter = 2" >> /etc/sysctl.conf 
echo "net.ipv4.conf.all.rp_filter = 2" >> /etc/sysctl.conf 
echo 2 > /proc/sys/net/ipv4/conf/default/rp_filter
echo 2 > /proc/sys/net/ipv4/conf/all/rp_filter
# Let's start the proxy
sudo systemctl start haproxy
sudo systemctl enable haproxy
~~~

### Bastion host <a name="bastion"></a>
#### Create the instance
Bastion has an interface in the PXE network, setup with the static port create previously, and an interface in the Management network.
~~~
openstack server create --image centos8 --flavor m1.medium --key-name adetalhouet --port openshift.bastion --network vlan197_net bastion
~~~
#### Provision the Bastion host
Login into the instance `$ ssh centos@10.195.197.102` and install dependencies.
~~~
sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
sudo yum -y install jq
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
sudo vi /var/lib/tftpboot/pxelinux.cfg/default
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
dhcp-host=fa:16:3e:01:73:40,192.168.1.20
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
sudo vi /etc/dnsmasq.d/dnsmasq-pxe.conf
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
sudo curl https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/${RHCOS_RELEASE}/latest/rhcos-live-initramfs.x86_64.img -o /usr/share/nginx/html/rhcos/rhcos-initramfs.img
sudo curl https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/${RHCOS_RELEASE}/latest/rhcos-live-kernel-x86_64 -o /usr/share/nginx/html/rhcos/rhcos-kernel
sudo curl https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/${RHCOS_RELEASE}/latest/rhcos-live-rootfs.x86_64.img -o /usr/share/nginx/html/rhcos/rhcos-live-rootfs
sudo curl https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/${RHCOS_RELEASE}/latest/rhcos-openstack.x86_64.qcow2.gz -o /usr/share/nginx/html/rhcos/rhcos-openstack.x86_64.qcow2.gz
sudo gunzip /usr/share/nginx/html/rhcos/rhcos-openstack.x86_64.qcow2.gz

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
## Deploy OpenShift Cluster <a name="deployocp"></a>
### Prepare Ignition files <a name="ignition"></a>
In order to do so, we need to build the `install-config.yaml` file.
Make sure the `baseDomain` and the `metadata.name` (cluster name) match the information provided during the DNS setup.
Also, ensure to modify the `pull-secret` with yours.
<details>
<summary>install-config.yaml</summary>

```
apiVersion: v1
baseDomain: adetalhouet.io
compute:
- hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: 3
controlPlane:
  hyperthreading: Enabled
  name: master
  platform: {}
  replicas: 3
metadata:
  name: ocp
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineCIDR: 10.0.0.0/16
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
pullSecret: ''
sshKey: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCwj7uJMyKiP1ogEsZv5kKDFw9mFNhxI+woR3Tuv8vjfNnqdB1GfSnvTFyNbdpyNdR8BlljkiZ1SlwJLEkvPk0HpOoSVVek/QmBeGC7mxyRcpMB2cNQwjXGfsVrforddXOnOkj+zx1aNdVGMc52Js3pex8B/L00H68kOcwP26BI1o77Uh+AxjOkIEGs+wlWNUmXabLDCH8l8IJk9mCTruKEN9KNj4NRZcaNC+XOz42SyHV9RT3N6efp31FqKzo8Ko63QirvKEEBSOAf9VlJ7mFMrGIGH37AP3JJfFYEHDdOA3N64ZpJLa39y25EWwGZNlWpO/GW5bNjTME04dl4eRyd adetalhouet
```
</details>
From the Bastion host, let's create the ignition files based on the above configuration.

~~~
ssh centos@10.195.197.102
# define a working directory for OpenShift and create it
WORKDIR=$HOME/ocp-pxe
mkdir -p $WORKDIR

# copy the configuration
vi $WORKDIR/install-config.yaml

# Generate the ignition files
./openshift-install create ignition-configs --dir=$WORKDIR/

# Copy the ignition file to the directory exposed through the HTTP server and set the file as readable
sudo mkdir /usr/share/nginx/html/ignition/
sudo cp ocp-pxe/*.ign /usr/share/nginx/html/ignition/
sudo chmod 644 /usr/share/nginx/html/ignition/*
~~~
### Deploy the Boostrap node <a name="bootstrap"></a>
From the host that has the OpenStack CLI access,
~~~
openstack server create --image pxeboot --flavor m1.openshift --key-name adetalhouet --port openshift.bootstrap bootstrap
~~~
From the instance console, from the OpenStack UI, select `BOOSTRAP` option.
![pxeboot](https://github.com/adetalhouet/ocp-pxe/raw/master/images/pxeboot-boostrap.png)

Then, from the Bastion host, wait until the API is up. Use the below command to monitor the progress
~~~
./openshift-install wait-for bootstrap-complete --dir=$WORKDIR/ --log-level debug
DEBUG OpenShift Installer 4.6.9
DEBUG Built from commit a48ad4a15b42102d1747d2f5f3b635deffb950b5
INFO Waiting up to 20m0s for the Kubernetes API at https://api.ocp.adetalhouet.io:6443...
INFO API v1.19.0+7070803 up
INFO Waiting up to 30m0s for bootstrapping to complete...
~~~
At this point, you can decomision the boostrap host.
### Deploy the Master nodes <a name="master"></a>
From the host that has the OpenStack CLI access,
~~~
for i in {0..2}; do
    openstack server create --image pxeboot --flavor m1.openshift --key-name adetalhouet --port openshift.master-${i} master-${i}
done
~~~
From the instances console, from the OpenStack UI, select `MASTER` option.
![pxeboot](https://github.com/adetalhouet/ocp-pxe/raw/master/images/pxeboot-master.png)
Back on the Bastion host, you should have the following after couple of minutes
~~~
./openshift-install wait-for bootstrap-complete --dir=$WORKDIR/ --log-level debug
DEBUG OpenShift Installer 4.6.9
DEBUG Built from commit a48ad4a15b42102d1747d2f5f3b635deffb950b5
INFO Waiting up to 20m0s for the Kubernetes API at https://api.ocp.adetalhouet.io:6443...
INFO API v1.19.0+7070803 up
INFO Waiting up to 30m0s for bootstrapping to complete...
DEBUG Bootstrap status: complete
INFO It is now safe to remove the bootstrap resources
DEBUG Time elapsed per stage:
DEBUG Bootstrap Complete: 3m59s
INFO Time elapsed: 3m59s
~~~
We can now deploy the Worker nodes
### Deploy the Worker nodes <a name="worker"></a>
From the host that has the OpenStack CLI access,
~~~
for i in {0..2}; do
    openstack server create --image pxeboot --flavor m1.openshift --key-name adetalhouet --port openshift.worker-${i} worker-${i}
done
~~~
From the instance console, from the OpenStack UI, select `WORKER` option.
![pxeboot](https://github.com/adetalhouet/ocp-pxe/raw/master/images/pxeboot-worker.png)
For the Worker nodes, there is a certificate signing process, which means we have to approve the issued CSR.
To do so, first, export the `KUBECONFIG` to have CLI access to the cluster
~~~
export KUBECONFIG=$WORKDIR/auth/kubeconfig
~~~
Then, you can check the CSR, and their status. Below, you can see the Workers CSR are pending approval
~~~
$ ./oc get csr
NAME        AGE     SIGNERNAME                                    REQUESTOR                                                                   CONDITION
csr-c7wng   36m     kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Approved,Issued
csr-d7d95   94s     kubernetes.io/kubelet-serving                 system:node:worker-1                                                        Pending
csr-hftq8   98s     kubernetes.io/kubelet-serving                 system:node:worker-2                                                        Pending
csr-ljqbr   34m     kubernetes.io/kubelet-serving                 system:node:master-1                                                        Approved,Issued
csr-md6rz   36m     kubernetes.io/kubelet-serving                 system:node:master-0                                                        Approved,Issued
csr-q8lbc   96s     kubernetes.io/kubelet-serving                 system:node:worker-0                                                        Pending
csr-t2qv2   34m     kubernetes.io/kubelet-serving                 system:node:master-2                                                        Approved,Issued
~~~
Approve the Workers CSR
~~~
./oc get csr -ojson | jq -r '.items[] | select(.status == {} ) | .metadata.name' | xargs ./oc adm certificate approve
~~~
You can monitor the installation progress using the following command
~~~
./openshift-install wait-for install-complete --dir=$WORKDIR/ --log-level debug
~~~
### Validate cluster status <a name="clusterstatus"></a>
#### Node status
We can start by looking at the node status, from the Bastion host, they should all be in `Ready` state.
~~~
export KUBECONFIG=$WORKDIR/auth/kubeconfig
./oc get nodes
NAME       STATUS   ROLES    AGE     VERSION
master-0   Ready    master   42m     v1.19.0+7070803
master-1   Ready    master   40m     v1.19.0+7070803
master-2   Ready    master   40m     v1.19.0+7070803
worker-0   Ready    worker   7m45s   v1.19.0+7070803
worker-1   Ready    worker   7m44s   v1.19.0+7070803
worker-2   Ready    worker   7m48s   v1.19.0+7070803
~~~
#### Login into the console
Navigate to `https://console-openshift-console.apps.ocp.adetalhouet.io/`
Adjust the cluster and domain name to your environment, as follow `https://console-openshift-console.apps.CLUSTER_NAME.DOMAIN_NAME/`

Get your `Kubeadmin` password using this command
~~~
 cat $WORKDIR/auth/kubeadmin-password
 ~~~
 ![ui](https://github.com/adetalhouet/ocp-pxe/raw/master/images/ui.png)
