#!/usr/bin/env bash
log_info "--- Task: storage ---"

# 1. Resize LVM physical volumes to use full device capacity
if [[ ${#ROOT_DISKS[@]} -gt 0 ]]; then
    for _disk in "${ROOT_DISKS[@]}"; do
        if [[ -b "$_disk" ]]; then
            pvresize "$_disk"
            log_info "pvresize: ${_disk}"
        else
            log_skip "Block device not found, skipping pvresize: ${_disk}"
        fi
    done
else
    log_skip "No root_disks configured, skipping pvresize"
fi

# 2. Expand root logical volume to 95% of physical volume space
_lv_path="/dev/ubuntu-vg/ubuntu-lv"
if [[ -e "$_lv_path" ]]; then
    # lvextend exits 0 when already at the target size (prints a warning)
    if lvextend -l '95%PVS' --resizefs "$_lv_path" 2>&1 | grep -qE "already|matches|New size"; then
        log_skip "ubuntu-lv already at target size"
    else
        log_changed "Expanded ubuntu-lv to 95%PVS with filesystem resize"
    fi
else
    log_skip "LV not found: ${_lv_path}"
fi

# 3. VM disk image storage directory
ensure_dir /data 0755 "libvirt-qemu:kvm"
