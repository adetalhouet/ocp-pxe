#!/bin/bash

# Create a small empty disk file, create dos filesystem.
dd if=/dev/zero of=pxeboot.img bs=1M count=4
mkdosfs pxeboot.img

# Make it bootable by syslinux
losetup /dev/loop0 pxeboot.img
syslinux --install /dev/loop0
mount /dev/loop0 /mnt

# Install iPXE kernel and make sysliux.cfg to load it at bootup
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

openstack image create --disk-format raw --container-format bare   --public --file pxeboot.img pxeboot1