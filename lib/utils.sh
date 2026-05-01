#!/usr/bin/env bash
# Idempotent helper library — sourced by setup.sh and all task scripts.
# Every helper follows: check current state → act only if different → log what changed.

set -euo pipefail

# ---------------------------------------------------------------------------
# Shared state (must be set before sourcing tasks)
# ---------------------------------------------------------------------------
REBOOT_REQUIRED=false
REBOOT_REASON=""
_apt_updated=false

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log_info()    { echo "[INFO]    $*"; }
log_changed() { echo "[CHANGED] $*"; }
log_skip()    { echo "[SKIP]    $*"; }
die()         { echo "[ERROR]   $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
require_root() {
    [[ $EUID -eq 0 ]] || die "Must be run as root. Re-run with: sudo $0"
}

check_ubuntu_version() {
    local distro version
    distro=$(lsb_release -si 2>/dev/null) || die "lsb_release not found — is this Ubuntu?"
    version=$(lsb_release -sr)
    [[ "$distro" == "Ubuntu" ]] || die "Unsupported OS: $distro. Only Ubuntu is supported."
    awk -v v="$version" 'BEGIN { if (v+0 < 24.04) exit 1 }' \
        || die "Ubuntu ${version} not supported. Requires 24.04 or later."
    log_info "OS check passed: Ubuntu ${version}"
}

# ---------------------------------------------------------------------------
# Reboot tracking
# ---------------------------------------------------------------------------
flag_reboot() {
    REBOOT_REQUIRED=true
    REBOOT_REASON="${REBOOT_REASON}  - $1\n"
}

# ---------------------------------------------------------------------------
# Package management
# ---------------------------------------------------------------------------
_ensure_apt_updated() {
    if [[ "$_apt_updated" == false ]]; then
        log_info "Running apt-get update..."
        apt-get update -qq
        _apt_updated=true
    fi
}

pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

install_packages() {
    local pkgs=("$@")
    local to_install=()
    for pkg in "${pkgs[@]}"; do
        pkg_installed "$pkg" || to_install+=("$pkg")
    done
    if [[ ${#to_install[@]} -gt 0 ]]; then
        _ensure_apt_updated
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${to_install[@]}"
        log_changed "Installed packages: ${to_install[*]}"
    else
        log_skip "All packages already installed: ${pkgs[*]}"
    fi
}

# ---------------------------------------------------------------------------
# File management
# ---------------------------------------------------------------------------

# Write file only if content differs. Returns 1 if file was changed.
write_file() {
    local path="$1" content="$2" mode="${3:-0644}" ownership="${4:-}"
    local tmpfile
    tmpfile=$(mktemp)
    printf '%s' "$content" > "$tmpfile"

    if [[ -f "$path" ]] && cmp -s "$tmpfile" "$path"; then
        log_skip "File unchanged: $path"
        rm -f "$tmpfile"
        return 0
    fi

    install -D -m "$mode" "$tmpfile" "$path"
    rm -f "$tmpfile"
    [[ -n "$ownership" ]] && chown "$ownership" "$path"
    log_changed "Wrote file: $path"
    return 1
}

# Append a line to a file if it is not already present (exact match).
# Returns 1 if line was added.
ensure_line() {
    local path="$1" line="$2"
    if grep -qxF "$line" "$path" 2>/dev/null; then
        log_skip "Line already present in $path: $line"
        return 0
    fi
    printf '%s\n' "$line" >> "$path"
    log_changed "Added line to $path: $line"
    return 1
}

# Replace the first line matching an ERE pattern. Returns 1 if changed.
# Uses a temp file + mv for atomicity.
replace_line() {
    local path="$1" pattern="$2" replacement="$3"
    local current
    current=$(grep -E "$pattern" "$path" 2>/dev/null || true)
    if [[ "$current" == "$replacement" ]]; then
        log_skip "Line already correct in $path"
        return 0
    fi
    local tmpfile
    tmpfile=$(mktemp)
    sed -E "s|${pattern}|${replacement}|" "$path" > "$tmpfile"
    mv "$tmpfile" "$path"
    log_changed "Updated line in $path (pattern: '$pattern')"
    return 1
}

# ---------------------------------------------------------------------------
# Directory management
# ---------------------------------------------------------------------------
ensure_dir() {
    local path="$1" mode="${2:-0755}" ownership="${3:-}"
    if [[ -d "$path" ]]; then
        log_skip "Directory exists: $path"
        return 0
    fi
    install -d -m "$mode" "$path"
    if [[ -n "$ownership" ]]; then chown "$ownership" "$path"; fi
    log_changed "Created directory: $path"
}

# ---------------------------------------------------------------------------
# User management
# ---------------------------------------------------------------------------
ensure_user() {
    local username="$1"
    if id "$username" &>/dev/null; then
        log_skip "User exists: $username"
        return 0
    fi
    useradd -m -s /bin/bash "$username"
    passwd -l "$username"
    log_changed "Created user: $username"
}

ensure_authorized_key() {
    local username="$1" key="$2" key_options="${3:-}"
    local home_dir
    home_dir=$(getent passwd "$username" | cut -d: -f6)
    local ssh_dir="${home_dir}/.ssh"
    local auth_file="${ssh_dir}/authorized_keys"
    local full_entry="${key_options:+${key_options} }${key}"

    if [[ ! -d "$ssh_dir" ]]; then
        install -d -m 0700 -o "$username" -g "$username" "$ssh_dir"
        log_changed "Created $ssh_dir"
    fi

    if grep -qF "$key" "$auth_file" 2>/dev/null; then
        log_skip "SSH key already present for $username"
        return 0
    fi

    printf '%s\n' "$full_entry" >> "$auth_file"
    chown "${username}:${username}" "$auth_file"
    chmod 0600 "$auth_file"
    log_changed "Added SSH authorized key for $username"
}

# ---------------------------------------------------------------------------
# Service management
# ---------------------------------------------------------------------------
service_enabled() { systemctl is-enabled "$1" &>/dev/null; }
service_active()  { systemctl is-active  "$1" &>/dev/null; }

ensure_service_enabled_started() {
    local name="$1"
    local changed=false
    if ! service_enabled "$name"; then
        systemctl enable "$name" --quiet
        log_changed "Enabled service: $name"
        changed=true
    fi
    if ! service_active "$name"; then
        systemctl start "$name"
        log_changed "Started service: $name"
        changed=true
    fi
    if [[ "$changed" == false ]]; then
        log_skip "Service already enabled and running: $name"
    fi
}

ensure_service_disabled_stopped() {
    local name="$1"
    local changed=false
    if service_enabled "$name" 2>/dev/null; then
        systemctl disable "$name" --quiet 2>/dev/null || true
        log_changed "Disabled service: $name"
        changed=true
    fi
    if service_active "$name" 2>/dev/null; then
        systemctl stop "$name" 2>/dev/null || true
        log_changed "Stopped service: $name"
        changed=true
    fi
    if [[ "$changed" == false ]]; then
        log_skip "Service already disabled/stopped: $name"
    fi
}

reload_systemd() {
    systemctl daemon-reload
    log_changed "Reloaded systemd daemon"
}

# ---------------------------------------------------------------------------
# Downloads
# ---------------------------------------------------------------------------

# Download a file only if it has changed (uses If-Modified-Since).
# Returns 1 if file was updated, 0 if already up to date.
download_if_changed() {
    local url="$1" dest="$2" mode="${3:-0644}"
    local tmpfile
    tmpfile=$(mktemp)

    if [[ -f "$dest" ]]; then
        local http_code
        http_code=$(curl -sSL -o "$tmpfile" -w "%{http_code}" -z "$dest" "$url")
        if [[ "$http_code" == "304" || ! -s "$tmpfile" ]]; then
            log_skip "Already up to date: $dest"
            rm -f "$tmpfile"
            return 0
        fi
    else
        curl -sSL -o "$tmpfile" "$url"
    fi

    install -D -m "$mode" "$tmpfile" "$dest"
    rm -f "$tmpfile"
    log_changed "Downloaded: $dest"
    return 1
}

# ---------------------------------------------------------------------------
# Host config resolution (modular mode — overridden in bundled mode)
# ---------------------------------------------------------------------------
resolve_config() {
    local config_arg="${1:-}"
    local hostname

    if [[ -n "$config_arg" ]]; then
        hostname="$config_arg"
    else
        hostname="$(hostname -f)"
        # Append .local if not already a FQDN with a dot
        [[ "$hostname" == *.* ]] || hostname="${hostname}.local"
    fi

    local host_file="${SCRIPT_DIR}/hosts/${hostname}.sh"
    if [[ ! -f "$host_file" ]]; then
        local available
        available=$(ls "${SCRIPT_DIR}/hosts/"*.sh 2>/dev/null \
            | xargs -n1 basename 2>/dev/null \
            | grep -v '^defaults' \
            | sed 's/\.sh$//' \
            | tr '\n' ' ' || echo "(none)")
        die "No config found for host '${hostname}'. Available: ${available}"
    fi

    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/hosts/defaults.sh"
    # shellcheck source=/dev/null
    source "$host_file"
    log_info "Loaded config for: ${hostname}"
}
