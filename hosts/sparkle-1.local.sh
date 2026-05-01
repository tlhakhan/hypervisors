#!/usr/bin/env bash
# sparkle-1.local — Intel Arc B570 hypervisor

HAS_GPU=true
GPU_PCI_IDS=("8086:e20c" "8086:e2f7")
GRUB_CMDLINE_LINUX_DEFAULT="amd_iommu=on iommu=pt mitigations=off apparmor=0 video=efifb:off"
ROOT_DISKS=("/dev/disk/by-id/nvme-SHPP41-2000GM_SND4N423512104I6G-part3")

WAKELET_ENABLED=true
VM_BUILDER_AGENT_ENABLED=true

ZPOOL_ENABLED=true
ZPOOL_DISKS=("sda")                     # short names or full /dev/disk/by-id/... paths
ZPOOL_SPECIAL_VDEVS=("sdb")             # one or more SSD/NVMe devices (striped special vdev)
ZFS_ARC_MAX_GB=16
