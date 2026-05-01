#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
CONFIG_HOST=""

usage() {
    cat <<EOF
Usage: sudo $0 [--config <hostname>]

Options:
  --config <hostname>   Use config for this hostname (default: auto-detect via hostname -f)
  --help                Show this help message

Examples:
  sudo ./setup.sh
  sudo ./setup.sh --config nvidia-1.local
  sudo ./setup.sh --config sparkle-1.local
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) CONFIG_HOST="$2"; shift 2 ;;
        --help|-h) usage ;;
        *) die "Unknown argument: $1. Run with --help for usage." ;;
    esac
done

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
require_root
check_ubuntu_version
resolve_config "$CONFIG_HOST"

if [[ "$VM_BUILDER_AGENT_ENABLED" == true && -z "${VM_BUILDER_AGENT_TRUSTED_CA_URL:-}" ]]; then
    die "VM_BUILDER_AGENT_TRUSTED_CA_URL must be set when VM_BUILDER_AGENT_ENABLED=true"
fi

log_info "=== Starting hypervisor setup for $(hostname) ==="

# ---------------------------------------------------------------------------
# Tasks — sourced (not subshells) to share REBOOT_REQUIRED and _apt_updated
# ---------------------------------------------------------------------------

# shellcheck source=tasks/packages.sh
source "${SCRIPT_DIR}/tasks/packages.sh"

# shellcheck source=tasks/gpu.sh
source "${SCRIPT_DIR}/tasks/gpu.sh"

# shellcheck source=tasks/network.sh
source "${SCRIPT_DIR}/tasks/network.sh"

# shellcheck source=tasks/storage.sh
source "${SCRIPT_DIR}/tasks/storage.sh"

# shellcheck source=tasks/system.sh
source "${SCRIPT_DIR}/tasks/system.sh"

if [[ "$WAKELET_ENABLED" == true ]]; then
    # shellcheck source=tasks/wakelet.sh
    source "${SCRIPT_DIR}/tasks/wakelet.sh"
fi

if [[ "$VM_BUILDER_AGENT_ENABLED" == true ]]; then
    # shellcheck source=tasks/vm-builder-agent.sh
    source "${SCRIPT_DIR}/tasks/vm-builder-agent.sh"
fi

# ---------------------------------------------------------------------------
# Reboot check
# ---------------------------------------------------------------------------
if [[ "$REBOOT_REQUIRED" == true ]]; then
    echo ""
    log_info "=== REBOOT REQUIRED ==="
    log_info "The following changes require a reboot to take effect:"
    printf '%b' "$REBOOT_REASON"
    echo ""
    log_info "Please reboot and re-run setup.sh to verify all settings."
    log_info "  sudo reboot"
    exit 1
fi

echo ""
log_info "=== Setup complete. No reboot required. ==="
