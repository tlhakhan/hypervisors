#!/usr/bin/env bash
log_info "--- Task: gpu ---"

if [[ "$HAS_GPU" != true ]] || [[ ${#GPU_PCI_IDS[@]} -eq 0 ]]; then
    log_skip "GPU passthrough disabled or no PCI IDs configured"
    return 0
fi

_pci_ids_joined="$(IFS=','; echo "${GPU_PCI_IDS[*]}")"
_initramfs_changed=false

# 1. VFIO kernel modules in /etc/initramfs-tools/modules
for _mod in vfio vfio_iommu_type1 vfio_pci; do
    ensure_line /etc/initramfs-tools/modules "$_mod" || _initramfs_changed=true
done

# 2. /etc/modprobe.d/vfio.conf — bind GPU PCI IDs to vfio-pci
_vfio_conf="softdep snd_hda_intel pre: vfio-pci
softdep xe pre: vfio-pci
options vfio-pci ids=${_pci_ids_joined}
options vfio-pci disable_vga=1
options vfio-pci disable_idle_d3=1"
write_file /etc/modprobe.d/vfio.conf "$_vfio_conf" 0644 || _initramfs_changed=true

# 3. GRUB kernel command line
if [[ -n "${GRUB_CMDLINE_LINUX_DEFAULT:-}" ]]; then
    # Migrate: clear GRUB_CMDLINE_LINUX if it still has vfio-pci params from the old approach
    _old_linux=$(grep -E '^GRUB_CMDLINE_LINUX=' /etc/default/grub 2>/dev/null || true)
    if echo "$_old_linux" | grep -q "vfio-pci"; then
        replace_line /etc/default/grub '^GRUB_CMDLINE_LINUX=.*' 'GRUB_CMDLINE_LINUX=""' || true
        log_changed "Cleared stale GRUB_CMDLINE_LINUX (migrated to GRUB_CMDLINE_LINUX_DEFAULT)"
    fi

    _target="GRUB_CMDLINE_LINUX_DEFAULT=\"${GRUB_CMDLINE_LINUX_DEFAULT} vfio-pci.ids=${_pci_ids_joined} vfio-pci.disable_vga=1\""
    _current=$(grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=.*' /etc/default/grub 2>/dev/null || true)
    if [[ "$_current" != "$_target" ]]; then
        cp /etc/default/grub /etc/default/grub.bak
        log_info "Backed up /etc/default/grub → /etc/default/grub.bak"
    fi

    if ! replace_line /etc/default/grub '^GRUB_CMDLINE_LINUX_DEFAULT=.*' "$_target"; then
        update-grub
        flag_reboot "Updated GRUB_CMDLINE_LINUX_DEFAULT"
    fi

    _grub_cfg=/boot/grub/grub.cfg
    grep -q "iommu=pt" "$_grub_cfg" 2>/dev/null || die "grub.cfg missing iommu=pt"
    grep -q "amd_iommu=pt" "$_grub_cfg" 2>/dev/null && die "grub.cfg still contains amd_iommu=pt" || true

    if echo "$GRUB_CMDLINE_LINUX_DEFAULT" | grep -q "pcie_acs_override"; then
        grep -q "pcie_acs_override" "$_grub_cfg" 2>/dev/null \
            || die "grub.cfg missing pcie_acs_override"
    else
        grep -q "pcie_acs_override" "$_grub_cfg" 2>/dev/null \
            && die "grub.cfg contains pcie_acs_override (should be absent)" || true
    fi

    log_info "grub.cfg assertions passed"
else
    # Legacy path: no per-host GRUB_CMDLINE_LINUX_DEFAULT configured
    _grub_cmdline="GRUB_CMDLINE_LINUX=\"amd_iommu=on iommu=pt mitigations=off apparmor=0 video=efifb:off pcie_acs_override=downstream,multifunction vfio-pci.ids=${_pci_ids_joined}\""
    if ! replace_line /etc/default/grub '^GRUB_CMDLINE_LINUX=.*' "$_grub_cmdline"; then
        update-grub
        flag_reboot "Updated GRUB cmdline for GPU passthrough (PCI IDs: ${_pci_ids_joined})"
    fi
fi

# 4. Blacklist host GPU drivers so they are available for VM passthrough
_no_gpu_conf='# Blacklist NVIDIA GPU modules
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_uvm
blacklist nvidia_modeset
blacklist nvidiafb
blacklist nouveau
blacklist nova_core
blacklist nova

# Blacklist Intel Arc / Xe GPU modules
blacklist xe
blacklist i915'
write_file /etc/modprobe.d/no-gpu.conf "$_no_gpu_conf" 0644 || _initramfs_changed=true

# Rebuild initramfs once if any of the above files changed
if [[ "$_initramfs_changed" == true ]]; then
    update-initramfs -u
    flag_reboot "Updated initramfs for VFIO/GPU passthrough"
fi
