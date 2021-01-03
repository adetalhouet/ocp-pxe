#!/bin/bash
 
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

## DNS Reverse zone for Red Hat Enterprise Linux CoreOS (RHCOS) that uses the reverse records to set the host name for all the nodes
OCP_REVERSE_ZONE=$(openstack zone create --email adetalhouet89@gmail.com 1.168.192.in-addr.arpa. |  awk '$2=="id" {print $4}')
openstack recordset create --type PTR --records api-gw.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 10.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records boostrap.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 20.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records master-0.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 100.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records master-1.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 101.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records master-2.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 102.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records worker-0.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 200.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records worker-1.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 201.1.168.192.in-addr.arpa.
openstack recordset create --type PTR --records worker-2.$DNS_DOMAIN --ttl 3600 $OCP_REVERSE_ZONE 202.1.168.192.in-addr.arpa.


# Network config #######################################

## PXE net
openstack network create --disable-port-security pxe_net
openstack subnet create --network pxe_net --dns-nameserver 10.195.194.16 --subnet-range 192.168.1.0/24 pxe_subnet

## Create router
openstack router create --enable ocp-pxe
openstack router add subnet ocp-pxe pxe_subnet
openstack router set --external-gateway vlan200_net ocp-pxe

## Assign ports
openstack port create openshift.bastion  --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.125
openstack port create openshift.api.gw  --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.10
openstack port create openshift.bootstrap  --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.20
openstack port create openshift.master-0   --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.100
openstack port create openshift.master-1   --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.101
openstack port create openshift.master-2   --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.102
openstack port create openshift.worker-0   --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.200
openstack port create openshift.worker-1   --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.201
openstack port create openshift.worker-2   --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.202