#!/usr/bin/env bash
# nvidia-1.local — NVIDIA RTX 4080 SUPER hypervisor

HAS_GPU=true
GPU_PCI_IDS=("10de:2702" "10de:22bb")
ROOT_DISKS=("/dev/disk/by-id/nvme-SHPP41-1000GM_AJD1N595713201V0H-part3")

WAKELET_ENABLED=true
VM_BUILDER_AGENT_ENABLED=true
