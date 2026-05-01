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
options vfio-pci ids=${_pci_ids_joined}
options vfio-pci disable_vga=1"
write_file /etc/modprobe.d/vfio.conf "$_vfio_conf" 0644 || _initramfs_changed=true

# 3. GRUB kernel command line
_grub_cmdline="GRUB_CMDLINE_LINUX=\"amd_iommu=on amd_iommu=pt mitigations=off apparmor=0 video=efifb:off pcie_acs_override=downstream,multifunction vfio-pci.ids=${_pci_ids_joined} vfio-pci.disable_vga=1\""
if ! replace_line /etc/default/grub '^GRUB_CMDLINE_LINUX=.*' "$_grub_cmdline"; then
    update-grub
    flag_reboot "Updated GRUB cmdline for GPU passthrough (PCI IDs: ${_pci_ids_joined})"
fi

# 4. Blacklist host GPU drivers so they are available for VM passthrough
_no_gpu_conf='# Blacklist NVIDIA GPU modules
blacklist nvidia
blacklist nvidia_drm
blacklist nvidia_uvm
blacklist nvidia_modeset
blacklist nvidiafb
blacklist nouveau

# Blacklist Intel Arc / Xe GPU modules
blacklist xe
blacklist i915'
write_file /etc/modprobe.d/no-gpu.conf "$_no_gpu_conf" 0644 || _initramfs_changed=true

# Rebuild initramfs once if any of the above files changed
if [[ "$_initramfs_changed" == true ]]; then
    update-initramfs -u
    flag_reboot "Updated initramfs for VFIO/GPU passthrough"
fi
