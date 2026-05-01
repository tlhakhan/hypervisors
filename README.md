# hypervisors

Bash scripts to configure homelab servers as KVM hypervisors on Ubuntu 24.04 (Noble).

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

All tasks are idempotent — safe to run multiple times; only changes what differs from the desired state.

## Hosts

| Host | GPU | Root disks |
|---|---|---|
| `nvidia-1.local` | NVIDIA RTX 4080 SUPER | 2× NVMe |
| `sparkle-1.local` | Intel Arc B570 | 1× NVMe |

## Usage

**Git clone (recommended for development):**

```bash
git clone https://github.com/tlhakhan/hypervisors.git
cd hypervisors
sudo ./setup.sh
```

The script auto-detects the host by `hostname -f`. Override with `--config` if needed:

```bash
sudo ./setup.sh --config nvidia-1.local
```

**Single-file curl (from GitHub Releases):**

```bash
curl -fsSL https://github.com/tlhakhan/hypervisors/releases/latest/download/setup-bundled.sh | sudo bash
```

With explicit host config:

```bash
curl -fsSL https://github.com/tlhakhan/hypervisors/releases/latest/download/setup-bundled.sh | sudo bash -s -- --config nvidia-1.local
```

### Reboot behavior

Some changes (GPU passthrough, network bridge) require a reboot. When they occur, the script exits with a summary and code 1:

```
=== REBOOT REQUIRED ===
The following changes require a reboot to take effect:
  - Updated GRUB cmdline for GPU passthrough
  - Updated netplan configuration (br0 bridge)

Please reboot and re-run setup.sh to verify all settings.
  sudo reboot
```

After rebooting, re-run `setup.sh` — on a converged system every task will report `[SKIP]`.

## Layout

```
setup.sh                          # Entry point
build.sh                          # Builds dist/setup-bundled.sh for curl delivery
lib/utils.sh                      # Idempotent helpers (write_file, install_packages, etc.)
hosts/
  defaults.sh                     # Default values for all variables
  nvidia-1.local.sh               # Host-specific overrides
  sparkle-1.local.sh
tasks/
  packages.sh                     # Package installation
  gpu.sh                          # VFIO / GPU passthrough
  network.sh                      # br0 bridge and avahi
  storage.sh                      # LVM resize and /data
  system.sh                       # Unattended upgrades and CPU governor
  wakelet.sh                      # Restricted shutdown SSH user
  vm-builder-agent.sh             # Terraform + vm-builder-agent service
.github/workflows/release.yml     # Auto-builds and publishes bundle on v* tag push
```

## Host configuration

Host configs live in `hosts/<hostname>.sh`. Each file sources `hosts/defaults.sh` first, then overrides only what differs.

| Variable | Default | Description |
|---|---|---|
| `HAS_GPU` | `false` | Enable GPU passthrough tasks |
| `GPU_PCI_IDS` | `()` | PCI IDs to bind to vfio-pci (VGA + audio device) — find them with `lspci -nn` |
| `ROOT_DISKS` | `()` | Disk paths to add to `ubuntu-vg` for LVM resize |
| `WAKELET_ENABLED` | `false` | Enable `wakelet` user and shutdown access setup |
| `WAKELET_PUBKEY` | *(set in defaults)* | SSH public key for the wakelet shutdown user |
| `VM_BUILDER_AGENT_ENABLED` | `false` | Enable `vm-builder-agent` installation and service |
| `VM_BUILDER_AGENT_VERSION` | `v1.5.0` | GitHub release tag for the binary; use `latest` or a specific tag |
| `VM_BUILDER_AGENT_TRUSTED_CA_URL` | *(set in defaults)* | URL the agent fetches to get the CA used to verify client certificates |

### Adding a new host

Create `hosts/new-host.local.sh` with only the variables that differ from the defaults:

```bash
#!/usr/bin/env bash
HAS_GPU=true
GPU_PCI_IDS=("10de:1234" "10de:5678")
ROOT_DISKS=("/dev/disk/by-id/nvme-...")
WAKELET_ENABLED=true
VM_BUILDER_AGENT_ENABLED=true
```

Then run `bash build.sh` to regenerate the bundled script.

## Releases

Pushing a `v*` tag triggers the GitHub Actions workflow in `.github/workflows/release.yml`, which builds `dist/setup-bundled.sh`, runs a syntax check, and uploads it as a release asset automatically.

```bash
git tag v1.0.0
git push --tags
```

## vm-builder-agent notes

- The script installs the published `vm-builder-agent` `linux-amd64` release binary — no Go toolchain needed on the hypervisor.
- Pin to a specific version by setting `VM_BUILDER_AGENT_VERSION="v0.1.2"` in the host config; set to `latest` to always pull the newest release.
- The service uses mTLS on `:8443`, stores generated TLS material in `/etc/vm-builder-agent/private`, and workspaces in `/var/lib/vm-builder-agent/workspaces`.
- `VM_BUILDER_AGENT_TRUSTED_CA_URL` must be set when `VM_BUILDER_AGENT_ENABLED=true`. The agent fetches this CA at startup to verify client certificates.
- Terraform is installed from the HashiCorp APT repo and the service uses `/usr/bin/terraform`.
