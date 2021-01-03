#!/bin/bash

# DNS Config #######################################
# - ref: https://docs.openshift.com/container-platform/4.6/installing/installing_bare_metal/installing-bare-metal.html#installation-dns-user-infra_installing-bare-metal

## DNS ZONE
OCP_ZONE=$(openstack zone create --email adetalhouet89@gmail.com $DNS_DOMAIN |  awk '$2=="id" {print $4}')
openstack recordset create --type A --records $EXT_IP --ttl 3600 $OCP_ZONE *.apps.$DNS_DOMAIN
openstack recordset create --type A --records $EXT_IP --ttl 3600 $OCP_ZONE api.$DNS_DOMAIN
openstack recordset create --type A --records 192.168.1.100 --ttl 3600 $OCP_ZONE etcd-0.$DNS_DOMAIN
openstack recordset create --type A --records 192.168.1.101 --ttl 3600 $OCP_ZONE etcd-1.$DNS_DOMAIN
openstack recordset create --type A --records 192.168.1.102 --ttl 3600 $OCP_ZONE etcd-2.$DNS_DOMAIN
openstack recordset create --type SRV --records "10 0 2380 etcd-0.$DNS_DOMAIN" "10 0 2380 etcd-1.$DNS_DOMAIN" "10 0 2380 etcd-2.$DNS_DOMAIN" --ttl 3600 $OCP_ZONE _etcd-server-ssl._tcp.ocp.adetalhouet.io.
openstack recordset create --type A --records 192.168.1.10 --ttl 3600 $OCP_ZONE boostrap.$DNS_DOMAIN
openstack recordset create --type A --records 192.168.1.100 --ttl 3600 $OCP_ZONE master-0.$DNS_DOMAIN
openstack recordset create --type A --records 192.168.1.101 --ttl 3600 $OCP_ZONE master-1.$DNS_DOMAIN
openstack recordset create --type A --records 192.168.1.102 --ttl 3600 $OCP_ZONE master-2.$DNS_DOMAIN
openstack recordset create --type A --records 192.168.1.200 --ttl 3600 $OCP_ZONE worker-0.$DNS_DOMAIN
openstack recordset create --type A --records 192.168.1.201 --ttl 3600 $OCP_ZONE worker-1.$DNS_DOMAIN
openstack recordset create --type A --records 192.168.1.202 --ttl 3600 $OCP_ZONE worker-2.$DNS_DOMAIN

## DNS Reverse zone for Red Hat Enterprise Linux CoreOS (RHCOS) that uses the reverse records to set the host name for all the nodes
OCP_REVERSE_ZONE=$(openstack zone create --email adetalhouet89@gmail.com 1.168.192.in-addr.arpa. |  awk '$2=="id" {print $4}')
openstack recordset create --type PTR --records boostrap.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 10.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records master-0.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 100.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records master-1.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 101.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records master-2.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 102.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records worker-0.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 200.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records worker-1.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 201.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records worker-2.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 202.1.168.192.in-addr.arpa.

# Network config #######################################
openstack network create --disable-port-security pxe_net
openstack subnet create --network pxe_net --dns-nameserver 10.195.194.16 --subnet-range 192.168.1.0/24 pxe_subnet

BOOTSTRAP_MAC=(openstack port create openshift.bootstrap  --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.10 | awk '$2=="mac_address" {print $4}')
MASTER0_MAC=(openstack port create openshift.master-0   --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.100 | awk '$2=="mac_address" {print $4}')
MASTER1_MAC=(openstack port create openshift.master-1   --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.101 | awk '$2=="mac_address" {print $4}')
MASTER2_MAC=(openstack port create openshift.master-2   --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.102 | awk '$2=="mac_address" {print $4}')
WORKER0_MAC=(openstack port create openshift.worker-0   --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.200 | awk '$2=="mac_address" {print $4}')
WORKER1_MAC=(openstack port create openshift.worker-1   --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.201 | awk '$2=="mac_address" {print $4}')
WORKER2_MAC=(openstack port create openshift.worker-2   --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.202 | awk '$2=="mac_address" {print $4}')

# Setup dnsmasq config
sed -i -e "s/DNS_SERVER/$DNS_SERVER/g" dnsmasq-pxe.conf
sed -i -e "s/BOOTSTRAP_MAC/$BOOTSTRAP_MAC/g" dnsmasq-pxe.conf
sed -i -e "s/MASTER0_MAC/$MASTER0_MAC/g" dnsmasq-pxe.conf
sed -i -e "s/MASTER1_MAC/$MASTER1_MAC/g" dnsmasq-pxe.conf
sed -i -e "s/MASTER2_MAC/$MASTER2_MAC/g" dnsmasq-pxe.conf
sed -i -e "s/WORKER0_MAC/$WORKER0_MAC/g" dnsmasq-pxe.conf
sed -i -e "s/WORKER1_MAC/$WORKER1_MAC/g" dnsmasq-pxe.conf
sed -i -e "s/WORKER2_MAC/$WORKER2_MAC/g" dnsmasq-pxe.conf

for i in {0..2}; do
    openstack server create --image pxeboot --flavor m1.openshift --key-name adetalhouet --port openshift.master-${i} master-${i}
done
#
# for i in {0..2}; do
#     openstack server create --image pxeboot --flavor m1.openshift --key-name adetalhouet --port openshift.worker-${i} worker-${i}.$DNS_DOMAIN
# done