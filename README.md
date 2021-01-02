# OpenShift setup on OpenStack using PXE

This repo simulate a bare metal UPI setup of OpenShift, in OpenStack.

# Overall setup
![architecture](https://github.com/adetalhouet/ocp-pxe/raw/master/docs/ocp-pxe.png)

## Hosts IP

| Hosts | IP |
|---------|:----:|
| bootstrap | 192.168.1.10 |
| master-0  | 192.168.1.100 |
| master-1   | 192.168.1.101 |
| master-2 | 192.168.1.102 |
| worker-0  | 192.168.1.200 |
| worker-1   | 192.168.1.201 |
| worker-2 | 192.168.1.202 |

# Requirement

- OpenStack
  - DNS Designate