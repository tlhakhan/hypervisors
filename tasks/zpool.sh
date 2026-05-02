#!/usr/bin/env bash
log_info "--- Task: zpool ---"
log_info "##################################################################"
log_info "# WARNING: NO REDUNDANCY                                        #"
log_info "# This zpool uses a stripe (RAID0) across all data disks with   #"
log_info "# no parity or mirroring. A single disk failure will result in  #"
log_info "# TOTAL DATA LOSS of all zvols and their contents.              #"
log_info "#                                                                #"
log_info "# If the data on this pool is important, back it up regularly.  #"
log_info "##################################################################"

if [[ "$ZPOOL_ENABLED" != true ]]; then
    log_skip "ZPOOL_ENABLED is not true; skipping zpool setup"
    return 0
fi

if [[ ${#ZPOOL_DISKS[@]} -eq 0 ]]; then
    die "ZPOOL_ENABLED=true but ZPOOL_DISKS is empty — set disk paths in host config"
fi

# 1. Resolve short names (sda, nvme0n1) to persistent /dev/disk/by-id/ paths.
#    Full paths starting with / are used as-is.
_resolve_disk_by_id() {
    local input="$1"
    if [[ "$input" == /* ]]; then
        echo "$input"
        return 0
    fi
    local target="/dev/${input}"
    local by_id
    by_id=$(find /dev/disk/by-id/ -maxdepth 1 -type l ! -name '*-part*' | while read -r _link; do
        [[ "$(readlink -f "$_link")" == "$target" ]] && echo "$_link"
    done | sort | head -1)
    if [[ -n "$by_id" ]]; then
        log_info "Resolved ${input} -> ${by_id}" >&2
        echo "$by_id"
    else
        log_info "No by-id entry found for ${input}; using ${target} directly" >&2
        echo "$target"
    fi
}

_derive_partition_path() {
    local base_path="$1" part_num="$2"
    if [[ "$base_path" == /dev/disk/by-id/* ]]; then
        local part_link="${base_path}-part${part_num}"
        [[ -L "$part_link" ]] && echo "$part_link" && return 0
    fi
    local real_dev
    real_dev=$(readlink -f "$base_path")
    local dev_name
    dev_name=$(basename "$real_dev")
    if [[ "$dev_name" == nvme* ]]; then
        echo "/dev/${dev_name}p${part_num}"
    else
        echo "/dev/${dev_name}${part_num}"
    fi
}

_resolved_disks=()
for _disk in "${ZPOOL_DISKS[@]}"; do
    _resolved_disks+=("$(_resolve_disk_by_id "$_disk")")
done

_resolved_specials=()
for _disk in "${ZPOOL_SPECIAL_DISKS[@]}"; do
    _resolved_specials+=("$(_resolve_disk_by_id "$_disk")")
done

_resolved_logs=()
for _disk in "${ZPOOL_LOG_DISKS[@]}"; do
    _resolved_logs+=("$(_resolve_disk_by_id "$_disk")")
done

# 2. Verify all block devices exist before doing anything destructive
for _disk in "${_resolved_disks[@]}"; do
    [[ -b "$_disk" ]] || die "Block device not found: $_disk — fix ZPOOL_DISKS in host config"
done
for _disk in "${_resolved_specials[@]}"; do
    [[ -b "$_disk" ]] || die "Block device not found: $_disk — fix ZPOOL_SPECIAL_DISKS in host config"
done
for _disk in "${_resolved_logs[@]}"; do
    [[ -b "$_disk" ]] || die "Block device not found: $_disk — fix ZPOOL_LOG_DISKS in host config"
done

# 3. Create pool if it does not already exist
if zpool list "$ZPOOL_NAME" &>/dev/null; then
    log_skip "zpool '${ZPOOL_NAME}' already exists; skipping creation"
else
    # Detect shared-disk scenario: 1 log disk + 1 special disk pointing to the same device
    _shared_disk_partition=false
    if [[ ${#ZPOOL_LOG_DISKS[@]} -eq 1 && ${#ZPOOL_SPECIAL_DISKS[@]} -eq 1 ]]; then
        _log_real=$(readlink -f "${_resolved_logs[0]}")
        _special_real=$(readlink -f "${_resolved_specials[0]}")
        if [[ "$_log_real" == "$_special_real" ]]; then
            _shared_disk_partition=true
            log_info "Log and special vdev are the same device (${_log_real}); auto-partitioning"
            sgdisk --zap-all "$_log_real"
            sgdisk \
                --new=1:0:+4G   --typecode=1:bf01 --change-name=1:"zil" \
                --new=2:0:0     --typecode=2:bf01 --change-name=2:"special" \
                "$_log_real"
            udevadm settle
            log_changed "Partitioned ${_log_real}: ZIL (part1=4GiB), special (part2=remainder)"
            _zil_part=$(_derive_partition_path "${_resolved_logs[0]}" 1)
            _special_part=$(_derive_partition_path "${_resolved_logs[0]}" 2)
            [[ -b "$_zil_part" ]]     || die "ZIL partition not found after partitioning: $_zil_part"
            [[ -b "$_special_part" ]] || die "Special partition not found after partitioning: $_special_part"
            _resolved_logs=("$_zil_part")
            _resolved_specials=("$_special_part")
        fi
    fi

    log_info "Wiping existing signatures from disks..."
    _disks_to_wipe=("${_resolved_disks[@]}")
    if [[ "$_shared_disk_partition" == false ]]; then
        _disks_to_wipe+=("${_resolved_logs[@]}" "${_resolved_specials[@]}")
    fi
    for _disk in "${_disks_to_wipe[@]}"; do
        wipefs -a "$_disk"
        log_changed "Wiped signatures: ${_disk}"
    done

    _zpool_args=(
        create -f
        -o ashift=12
        -o autotrim=on
        -O atime=off
        -O compression=lz4
        -O dnodesize=auto
        -O "special_small_blocks=${ZPOOL_SPECIAL_SMALL_BLOCKS}"
        -O "sync=${ZPOOL_SYNC}"
        -O "logbias=${ZPOOL_LOGBIAS}"
        -O "primarycache=${ZPOOL_PRIMARYCACHE}"
        -m none
        "$ZPOOL_NAME"
    )
    _zpool_args+=("${_resolved_disks[@]}")
    if [[ ${#_resolved_logs[@]} -gt 0 ]]; then
        _zpool_args+=(log "${_resolved_logs[@]}")
    fi
    if [[ ${#_resolved_specials[@]} -gt 0 ]]; then
        _zpool_args+=(special "${_resolved_specials[@]}")
    fi
    zpool "${_zpool_args[@]}"
    log_changed "Created zpool '${ZPOOL_NAME}' with ${#_resolved_disks[@]} data disk(s), ${#_resolved_logs[@]} log disk(s), and ${#_resolved_specials[@]} special vdev disk(s)"
fi

# 4. Idempotent dataset property enforcement (corrects drift on re-runs)
_zfs_set_if_needed() {
    local prop="$1" desired="$2" dataset="$3"
    local current
    current=$(zfs get -H -o value "$prop" "$dataset" 2>/dev/null) || return 0
    if [[ "$current" == "$desired" ]]; then
        log_skip "zfs property already set: ${dataset} ${prop}=${desired}"
    else
        zfs set "${prop}=${desired}" "$dataset"
        log_changed "Set zfs property: ${dataset} ${prop}=${desired} (was: ${current})"
    fi
}
_zpool_set_if_needed() {
    local prop="$1" desired="$2" pool="$3"
    local current
    current=$(zpool get -H -o value "$prop" "$pool" 2>/dev/null) || return 0
    if [[ "$current" == "$desired" ]]; then
        log_skip "zpool property already set: ${pool} ${prop}=${desired}"
    else
        zpool set "${prop}=${desired}" "$pool"
        log_changed "Set zpool property: ${pool} ${prop}=${desired} (was: ${current})"
    fi
}
_zpool_set_if_needed autotrim           on                             "$ZPOOL_NAME"
_zfs_set_if_needed atime                off                            "$ZPOOL_NAME"
_zfs_set_if_needed compression          lz4                            "$ZPOOL_NAME"
_zfs_set_if_needed dnodesize            auto                           "$ZPOOL_NAME"
_zfs_set_if_needed special_small_blocks "$ZPOOL_SPECIAL_SMALL_BLOCKS" "$ZPOOL_NAME"
_zfs_set_if_needed sync                 "$ZPOOL_SYNC"                  "$ZPOOL_NAME"
_zfs_set_if_needed logbias              "$ZPOOL_LOGBIAS"               "$ZPOOL_NAME"
_zfs_set_if_needed primarycache         "$ZPOOL_PRIMARYCACHE"          "$ZPOOL_NAME"

# 5. ZFS module parameters — persisted to modprobe config + applied live if module is loaded
_apply_zfs_param() {
    local param="$1" value="$2" label="$3"
    local sysfs="/sys/module/zfs/parameters/${param}"
    if [[ -f "$sysfs" ]]; then
        if [[ "$(< "$sysfs")" == "$value" ]]; then
            log_skip "ZFS param already live: ${param}=${value}"
        else
            printf '%s' "$value" > "$sysfs"
            log_changed "Applied ZFS param live: ${param}=${value} (${label})"
        fi
    else
        log_skip "ZFS module not loaded yet; ${param} will apply on next boot"
    fi
}

_arc_bytes=$(( ZFS_ARC_MAX_GB * 1024 * 1024 * 1024 ))
_zfs_modprobe="options zfs zfs_arc_max=${_arc_bytes} zfs_txg_timeout=${ZFS_TXG_TIMEOUT}"
if [[ "$ZFS_DIRTY_DATA_MAX_MB" -gt 0 ]]; then
    _dirty_bytes=$(( ZFS_DIRTY_DATA_MAX_MB * 1024 * 1024 ))
    _zfs_modprobe+=" zfs_dirty_data_max=${_dirty_bytes}"
fi
write_file /etc/modprobe.d/zfs.conf "$_zfs_modprobe" 0644 || true

_apply_zfs_param zfs_arc_max        "$_arc_bytes"           "${ZFS_ARC_MAX_GB} GiB ARC"
_apply_zfs_param zfs_txg_timeout    "$ZFS_TXG_TIMEOUT"      "${ZFS_TXG_TIMEOUT}s txg timeout"
if [[ "$ZFS_DIRTY_DATA_MAX_MB" -gt 0 ]]; then
    _apply_zfs_param zfs_dirty_data_max "$_dirty_bytes"     "${ZFS_DIRTY_DATA_MAX_MB} MiB dirty data max"
fi
