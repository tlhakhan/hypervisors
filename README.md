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
- Optionally installs and enables [`vm-builder-agent`](https://github.com/tlhakhan/vm-builder-agent) from GitHub release assets, including its systemd service and mTLS settings

## Hosts

| Host | GPU | Root disks |
|---|---|---|
| `nvidia-1.local` | NVIDIA RTX 4080 SUPER | 2× NVMe |
| `sparkle-1.local` | Intel Arc B570 | 1× NVMe |

## Usage

```bash
ansible-playbook main.yaml
```

Privilege escalation is required (`become: true`). You will be prompted for the sudo password.

## Layout

- `main.yaml` keeps the play-level assertions, task ordering, and handlers.
- `tasks/packages.yaml` installs shared packages and optional vm-builder-agent runtime dependencies.
- `tasks/gpu.yaml` contains VFIO, GRUB, and GPU driver blacklist configuration.
- `tasks/network.yaml` configures Avahi and the `br0` netplan bridge.
- `tasks/storage.yaml` handles LVM growth and `/data` creation.
- `tasks/system.yaml` applies unattended-upgrades and CPU governor settings.
- `tasks/wakelet.yaml` manages the restricted shutdown user.
- `tasks/vm-builder-agent.yaml` installs Terraform plus the vm-builder-agent service and runtime it depends on.

## Host variables

| Variable | Default | Description |
|---|---|---|
| `has_gpu` | `false` | Enable GPU passthrough tasks |
| `gpu_pci_ids` | `[]` | PCI IDs to bind to vfio-pci (VGA + audio device) — find them with `lspci -nn`, look for the VGA compatible controller and Audio device lines |
| `root_disks` | `[]` | Disk paths to add to `ubuntu-vg` for LVM resize |
| `wakelet_enabled` | `false` | Enable `wakelet` user and shutdown access setup |
| `wakelet_pubkey` | *(set in vars)* | SSH public key for the wakelet shutdown user |
| `vm_builder_agent_enabled` | `false` | Enable `vm-builder-agent` installation and service management |
| `vm_builder_agent_trusted_ca_url` | `""` | URL the agent fetches to get the CA used to verify client certificates |

## vm-builder-agent notes

- The playbook installs the published `vm-builder-agent` `linux-amd64` release binary instead of building from source, so the hypervisors do not need a Go toolchain.
- The service uses the upstream `vm-builder-core` repository and the default authorized client CN `vm-builder-apiserver`.
- The service also installs `git` and `xsltproc`, which `vm-builder-agent` and `vm-builder-core` need at runtime. Terraform is installed by the playbook and the service uses `/usr/bin/terraform`.
- The service always starts with agent mTLS enabled on `:8443`, uses `/etc/vm-builder-agent/private` for generated TLS material, and stores workspaces in `/var/lib/vm-builder-agent/workspaces`, matching the upstream example service.
- You must provide `vm_builder_agent_trusted_ca_url`. The agent fetches that CA at startup and generates its own server cert/key inside `/etc/vm-builder-agent/private`.
