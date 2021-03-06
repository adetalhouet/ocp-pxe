#!/bin/bash
 
OCP_RELEASE_PATH=ocp # https://mirror.openshift.com/pub/openshift-v4/clients/
OCP_SUBRELEASE=4.6.9 # https://mirror.openshift.com/pub/openshift-v4/clients/ocp/
RHCOS_RELEASE=4.6 # https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/
WEBROOT=/usr/share/nginx/html/

## Install dependencies
yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm

## Setup DHCP and DNS
yum -y install dnsmasq
cp $HOME/ocp-pxe/dnsmasq-pxe.conf /etc/dnsmasq.d/dnsmasq-pxe.conf
systemctl start dnsmasq
systemctl enable dnsmasq

## Setup TFTP Server
yum -y install tftp-server syslinux
cp -r /usr/share/syslinux/* /var/lib/tftpboot
mkdir /var/lib/tftpboot/pxelinux.cfg
cp $HOME/ocp-pxe/pxelinux.0 /var/lib/tftpboot/pxelinux.cfg/default
systemctl start tftp
systemctl enable tftp

## Setup HAProxy - LB
yum -y install haproxy
cp haproxy.cfg /etc/haproxy/haproxy.cfg
echo "net.ipv4.conf.default.rp_filter = 2" >> /etc/sysctl.conf 
echo "net.ipv4.conf.all.rp_filter = 2" >> /etc/sysctl.conf 
echo 2 > /proc/sys/net/ipv4/conf/default/rp_filter
echo 2 > /proc/sys/net/ipv4/conf/all/rp_filter
sudo systemctl start haproxy
sudo systemctl enable haproxy

## Setup HTTP server
yum -y install nginx
systemctl start nginx
systemctl enable nginx

# OpenShift images setup
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

# OpenShift ignition file setup

mkdir $OCP_WORK_DIR
cp $HOME/ocp-pxe/install-config.yaml $OCP_WORK_DIR
./openshift-install create ignition-configs --dir=$OCP_WORK_DIR

mkdir $WEBROOT/ignition/
cp $OCP_WORK_DIR/*.ign $WEBROOT/ignition/

