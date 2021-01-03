#!/bin/bash

## EDIT THE BELLOW PROPS TO MATCH YOUR ENV AND DESIRED SETUP

OCP_RELEASE_PATH=ocp # https://mirror.openshift.com/pub/openshift-v4/clients/
OCP_SUBRELEASE=4.6.9 # https://mirror.openshift.com/pub/openshift-v4/clients/ocp/
RHCOS_RELEASE=4.6 # https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/

OCP_WORK_DIR=ocp-pxe

EXT_IP=10.195.197.105
DNS_SERVER=10.195.194.16

DOMAIN=pxe.test.io.
CLUSTER_NAME=ocp

#######################################

WEBROOT=/usr/share/nginx/html/
DNS_DOMAIN=$CLUSTER_NAME.$DOMAIN

## Clone repo with config
git clone https://github.com/adetalhouet/ocp-pxe.git

## Set pxeboot image
./ocp-pxe/pxeboot-image.sh

## Setup OpenStack - DNS and Network
./ocp-pxe/openstack-setup.sh

## Create Bastion
openstack port create openshift.bastion  --network pxe_net --fixed-ip subnet=pxe_subnet,ip-address=192.168.1.126
openstack server create --image centos8 --flavor m1.medium --key-name adetalhouet --port openshift.bastion bastion

#export KUBECONFIG=${POCDIR}/auth/kubeconfig
#./oc get csr
#./oc get csr -ojson | jq -r '.items[] | select(.status == {} ) | .metadata.name' | xargs ./oc adm certificate approve