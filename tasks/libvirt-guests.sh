#!/usr/bin/env bash
log_info "--- Task: libvirt-guests ---"

_libvirt_guests_conf="ON_SHUTDOWN=${LIBVIRT_GUESTS_ON_SHUTDOWN}
SHUTDOWN_TIMEOUT=${LIBVIRT_GUESTS_SHUTDOWN_TIMEOUT}
PARALLEL_SHUTDOWN=${LIBVIRT_GUESTS_PARALLEL_SHUTDOWN}
ON_BOOT=${LIBVIRT_GUESTS_ON_BOOT}
START_DELAY=${LIBVIRT_GUESTS_START_DELAY}"

write_file /etc/default/libvirt-guests "$_libvirt_guests_conf" 0644 || true
ensure_service_enabled_started libvirt-guests.service
