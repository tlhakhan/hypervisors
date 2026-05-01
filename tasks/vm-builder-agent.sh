#!/usr/bin/env bash
log_info "--- Task: vm-builder-agent ---"

# 1. Runtime dependencies
# Remove stale HashiCorp APT repo if present (replaced by direct binary download)
if [[ -f /etc/apt/sources.list.d/hashicorp.list ]]; then
    rm -f /etc/apt/sources.list.d/hashicorp.list
    _apt_updated=false
    log_changed "Removed stale HashiCorp APT repository"
fi
install_packages unzip

# 2. Terraform binary — downloaded directly from releases.hashicorp.com
_tf_version="${TERRAFORM_VERSION}"
_tf_bin="/usr/local/bin/terraform"
_tf_zip="/tmp/terraform_${_tf_version}_linux_amd64.zip"
_tf_url="https://releases.hashicorp.com/terraform/${_tf_version}/terraform_${_tf_version}_linux_amd64.zip"

if "${_tf_bin}" version 2>/dev/null | grep -qF "Terraform v${_tf_version}"; then
    log_skip "Terraform ${_tf_version} already installed"
else
    log_info "Installing Terraform ${_tf_version}..."
    curl -fsSL -o "$_tf_zip" "$_tf_url"
    unzip -q -o "$_tf_zip" -d /usr/local/bin/ terraform
    chmod 0755 "$_tf_bin"
    rm -f "$_tf_zip"
    log_changed "Installed Terraform ${_tf_version}"
fi

# 3. vm-builder-agent binary
_agent_bin="/usr/local/bin/vm-builder-agent"
_agent_version="${VM_BUILDER_AGENT_VERSION:-latest}"
if [[ "$_agent_version" == "latest" ]]; then
    _agent_url="https://github.com/tlhakhan/vm-builder-agent/releases/latest/download/vm-builder-agent-linux-amd64"
else
    _agent_url="https://github.com/tlhakhan/vm-builder-agent/releases/download/${_agent_version}/vm-builder-agent-linux-amd64"
fi
_agent_changed=false
download_if_changed "$_agent_url" "$_agent_bin" 0755 || _agent_changed=true

# 4. systemd service unit
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
  --terraform /usr/local/bin/terraform \\
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
