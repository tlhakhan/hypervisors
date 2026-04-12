# hypervisors

Ansible playbook to configure homelab servers as KVM hypervisors on Ubuntu 24.04 (Noble).

## What it does

- Installs KVM/QEMU, libvirt, and bridge-utils
- Configures a bridged network interface (`br0`) over any `en*`/`et*` NIC for VM connectivity
- Sets up GPU passthrough via VFIO — blacklists host GPU drivers, writes kernel cmdline args, and updates initramfs
- Resizes the LVM volume group (`ubuntu-vg`) across all root disks and expands the logical volume to 95%
- Creates `/data` for VM disk image storage (owned by `libvirt-qemu:kvm`)
- Configures avahi/mDNS restricted to `br0` for `.local` resolution
- Sets CPU governor to `performance` via a systemd oneshot service
- Disables unattended upgrades to prevent unexpected reboots
- Creates a restricted `wakelet` SSH user whose only capability is triggering a clean shutdown (used by the [wakelet](https://github.com/tlhakhan/wakelet) HomeKit bridge for Siri/Home app power control)

## Hosts

| Host | GPU | Root disks |
|---|---|---|
| `nvidia-1.local` | NVIDIA RTX 4080 SUPER | 2× NVMe |
| `sparkle-1.local` | Intel Arc | 1× NVMe |

## Usage

```bash
ansible-playbook main.yaml
```

Privilege escalation is required (`become: true`). You will be prompted for the sudo password.

## Host variables

| Variable | Default | Description |
|---|---|---|
| `has_gpu` | `false` | Enable GPU passthrough tasks |
| `gpu_pci_ids` | `[]` | PCI IDs to bind to vfio-pci (VGA + audio device) |
| `root_disks` | `[]` | Disk paths to add to `ubuntu-vg` for LVM resize |
| `wakelet_pubkey` | *(set in vars)* | SSH public key for the wakelet shutdown user |
