#!/usr/bin/env bash
# Default values for all hypervisor hosts.
# Host-specific files source this first, then override selectively.

HAS_GPU=false
GPU_PCI_IDS=()
ROOT_DISKS=()

WAKELET_ENABLED=false
WAKELET_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDywWj6OTinhgHIlTl8fJqwsjq9dXOKhOgdcMLbQvL+w"

VM_BUILDER_AGENT_ENABLED=false
VM_BUILDER_AGENT_VERSION="v1.6.0"
VM_BUILDER_AGENT_TRUSTED_CA_URL="https://homelab.tenzin.io/api/pki/vm-builder-ca.crt"

TERRAFORM_VERSION="1.15.0"
