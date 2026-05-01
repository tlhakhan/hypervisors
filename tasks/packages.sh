#!/usr/bin/env bash
log_info "--- Task: packages ---"

_base_pkgs=(
    qemu-system-x86
    libvirt-daemon-system
    libvirt-clients
    bridge-utils
    genisoimage
    libnss-mdns
    avahi-daemon
    avahi-utils
    nvme-cli
    linux-tools-common
    linux-tools-generic
)
install_packages "${_base_pkgs[@]}"

if [[ "$VM_BUILDER_AGENT_ENABLED" == true ]]; then
    install_packages git xsltproc
fi

if [[ "$ZPOOL_ENABLED" == true ]]; then
    install_packages zfsutils-linux
fi
