#!/usr/bin/env bash
# nvidia-1.local — NVIDIA RTX 4080 SUPER hypervisor

HAS_GPU=true
GPU_PCI_IDS=("10de:2702" "10de:22bb")
GRUB_CMDLINE_LINUX_DEFAULT="amd_iommu=on iommu=pt iommu.strict=0 pcie_acs_override=downstream,multifunction mitigations=off apparmor=0 video=efifb:off"
ROOT_DISKS=("/dev/disk/by-id/nvme-SHPP41-1000GM_AJD1N595713201V0H-part3")

WAKELET_ENABLED=true
VM_BUILDER_AGENT_ENABLED=true

ZPOOL_ENABLED=true
ZPOOL_DISKS=("sda" "sdb")               # short names or full /dev/disk/by-id/... paths
ZPOOL_SPECIAL_VDEVS=("nvme1n1")         # one or more SSD/NVMe devices (striped special vdev)
ZFS_ARC_MAX_GB=16
