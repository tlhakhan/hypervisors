#!/usr/bin/env bash
log_info "--- Task: network ---"

# 1. Restrict avahi-daemon to the VM bridge interface
_avahi_changed=false
replace_line /etc/avahi/avahi-daemon.conf \
    '^#?allow-interfaces=.*' \
    'allow-interfaces=br0' || _avahi_changed=true

if [[ "$_avahi_changed" == true ]]; then
    systemctl restart avahi-daemon
    systemctl enable avahi-daemon --quiet
    log_changed "Restarted and enabled avahi-daemon"
fi

# 2. Netplan br0 bridge over physical ethernet interfaces
# Replaces the existing netplan config — br0 gets DHCP, physical NIC becomes an uplink.
# Detect the existing netplan config file: 00-installer-config.yaml (Ubuntu 26.04+)
# or 50-cloud-init.yaml (Ubuntu 24.04) or fall back to a new file we own.
_netplan_file=$(find /etc/netplan -maxdepth 1 -name '*.yaml' 2>/dev/null | sort | head -1)
_netplan_file="${_netplan_file:-/etc/netplan/10-hypervisor.yaml}"
log_info "Using netplan config: ${_netplan_file}"

_netplan_content='network:
  version: 2
  ethernets:
    uplink:
      match:
        name: "e[nt]*"
      dhcp4: false
      wakeonlan: true
  bridges:
    br0:
      interfaces:
        - uplink
      dhcp4: true
      parameters:
        stp: false
        forward-delay: 0'
write_file "$_netplan_file" "$_netplan_content" 0600 "root:root" \
    || flag_reboot "Updated netplan configuration (br0 bridge over physical NIC)"
