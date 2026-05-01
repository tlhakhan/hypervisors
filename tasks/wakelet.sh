#!/usr/bin/env bash
log_info "--- Task: wakelet ---"

# Creates a restricted SSH user that can only trigger a system shutdown.
# Used by the Wakelet HomeKit bridge for Siri/Home app power control.

# 1. Locked-password user
ensure_user wakelet

# 2. Sudoers entry — shutdown only, no password prompt
_sudoers_line="wakelet ALL=(ALL) NOPASSWD: /sbin/shutdown -h now"
write_file /etc/sudoers.d/wakelet "${_sudoers_line}" 0440 "root:root"
visudo -cf /etc/sudoers.d/wakelet || die "sudoers validation failed for /etc/sudoers.d/wakelet"

# 3. SSH authorized key with forced command — any SSH connection immediately shuts down
_key_options='command="sudo /sbin/shutdown -h now",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty'
ensure_authorized_key wakelet "$WAKELET_PUBKEY" "$_key_options"
