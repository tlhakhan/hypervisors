#!/usr/bin/env bash
log_info "--- Task: vm-builder-agent ---"

# 1. APT prerequisites for adding HashiCorp repo
install_packages gnupg software-properties-common

# 2. HashiCorp GPG key
_keyring_asc="/usr/share/keyrings/hashicorp-archive-keyring.asc"
_keyring_gpg="/usr/share/keyrings/hashicorp-archive-keyring.gpg"

if ! download_if_changed "https://apt.releases.hashicorp.com/gpg" "$_keyring_asc" 0644; then
    gpg --dearmor --yes --output "$_keyring_gpg" "$_keyring_asc"
    log_changed "Updated HashiCorp GPG keyring (dearmored)"
fi

# 3. HashiCorp APT repository
_codename="$(lsb_release -sc)"
_repo_line="deb [arch=amd64 signed-by=${_keyring_gpg}] https://apt.releases.hashicorp.com ${_codename} main"
_repo_file="/etc/apt/sources.list.d/hashicorp.list"
if ! grep -qF "$_repo_line" "$_repo_file" 2>/dev/null; then
    printf '%s\n' "$_repo_line" > "$_repo_file"
    _apt_updated=false  # Force apt-get update on next install_packages call
    log_changed "Added HashiCorp APT repository"
fi
install_packages terraform

# 4. vm-builder-agent binary
_agent_bin="/usr/local/bin/vm-builder-agent"
_version="${VM_BUILDER_AGENT_VERSION:-latest}"
if [[ "$_version" == "latest" ]]; then
    _agent_url="https://github.com/tlhakhan/vm-builder-agent/releases/latest/download/vm-builder-agent-linux-amd64"
else
    _agent_url="https://github.com/tlhakhan/vm-builder-agent/releases/download/${_version}/vm-builder-agent-linux-amd64"
fi
_agent_changed=false
download_if_changed "$_agent_url" "$_agent_bin" 0755 || _agent_changed=true

# 5. systemd service unit
_svc_file="/etc/systemd/system/vm-builder-agent.service"
_svc_content="[Unit]
Description=vm-builder-agent
Documentation=https://github.com/tlhakhan/vm-builder-agent
After=network-online.target libvirtd.service
Wants=network-online.target
Requires=libvirtd.service

[Service]
ExecStartPre=mkdir -p /var/lib/vm-builder-agent/workspaces
ExecStartPre=mkdir -p /var/lib/vm-builder-agent/cloud-image-cache
ExecStartPre=mkdir -p /etc/vm-builder-agent/private
ExecStart=/usr/local/bin/vm-builder-agent \\
  --listen :8443 \\
  --agent-mtls \\
  --agent-trusted-ca-url ${VM_BUILDER_AGENT_TRUSTED_CA_URL} \\
  --private-dir /etc/vm-builder-agent/private \\
  --agent-authorized-client-cn vm-builder-apiserver \\
  --core-repo https://github.com/tlhakhan/vm-builder-core \\
  --terraform /usr/bin/terraform \\
  --workspaces-dir /var/lib/vm-builder-agent/workspaces \\
  --cloud-image-cache-dir /var/lib/vm-builder-agent/cloud-image-cache
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vm-builder-agent
User=root
Group=root

[Install]
WantedBy=multi-user.target"

_svc_changed=false
write_file "$_svc_file" "$_svc_content" 0644 "root:root" || _svc_changed=true

if [[ "$_svc_changed" == true ]]; then
    reload_systemd
fi

ensure_service_enabled_started vm-builder-agent.service

if [[ "$_agent_changed" == true || "$_svc_changed" == true ]]; then
    systemctl restart vm-builder-agent.service
    log_changed "Restarted vm-builder-agent"
fi
