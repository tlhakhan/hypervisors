#!/usr/bin/env bash
log_info "--- Task: system ---"

# 1. Disable automatic unattended upgrades (prevents surprise reboots during VM workloads)
_apt_conf='APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "0";
'
write_file /etc/apt/apt.conf.d/20auto-upgrades "$_apt_conf" || true

# 2. Stop and disable unattended upgrade services
ensure_service_disabled_stopped unattended-upgrades.service
ensure_service_disabled_stopped apt-daily-upgrade.timer

# 3. CPU performance governor — runs once at boot via systemd oneshot service
_cpu_svc='[Unit]
Description=Set CPU governor to performance

[Service]
Type=oneshot
ExecStart=/usr/bin/cpupower frequency-set -g performance
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target'

_svc_file=/etc/systemd/system/cpu-performance.service
if ! write_file "$_svc_file" "$_cpu_svc" 0644; then
    reload_systemd
fi
ensure_service_enabled_started cpu-performance.service
