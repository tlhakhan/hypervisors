#!/usr/bin/env bash
# Default values for all hypervisor hosts.
# Host-specific files source this first, then override selectively.

HAS_GPU=false
GPU_PCI_IDS=()
ROOT_DISKS=()

WAKELET_ENABLED=false
WAKELET_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDywWj6OTinhgHIlTl8fJqwsjq9dXOKhOgdcMLbQvL+w"

VM_BUILDER_AGENT_ENABLED=false
VM_BUILDER_AGENT_VERSION="v1.7.0"
VM_BUILDER_AGENT_TRUSTED_CA_URL="https://homelab.tenzin.io/api/pki/vm-builder-ca.crt"

TERRAFORM_VERSION="1.15.0"

ZPOOL_ENABLED=false
ZPOOL_NAME="zvols"
ZPOOL_DISKS=()                      # spinning disks — bare list = implicit stripe (RAID0), no redundancy
ZPOOL_SPECIAL_VDEVS=()              # SSD/NVMe devices for special vdev (stripe); empty = no special vdev
ZPOOL_SPECIAL_SMALL_BLOCKS="128K"   # blocks ≤ this go to special vdev (metadata always does)
ZFS_ARC_MAX_GB=8                    # ARC ceiling in GiB; tune per host to leave RAM for VMs
