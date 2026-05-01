#!/usr/bin/env bash
# sparkle-1.local — Intel Arc B570 hypervisor

HAS_GPU=true
GPU_PCI_IDS=("8086:e20c" "8086:e2f7")
ROOT_DISKS=("/dev/disk/by-id/nvme-SHPP41-2000GM_SND4N423512104I6G-part3")

WAKELET_ENABLED=true
VM_BUILDER_AGENT_ENABLED=true
