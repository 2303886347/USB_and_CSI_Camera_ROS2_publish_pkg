#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s nullglob

SCRIPT_NAME="$(basename "$0")"
BOOT_DIR="${BOOT_DIR:-/boot}"
DTB_DIR="${DTB_DIR:-$BOOT_DIR/dtb}"
DT_BASE="${DT_BASE:-/sys/firmware/devicetree/base}"
ACTIVE_FDT="${ACTIVE_FDT:-/sys/firmware/fdt}"
JETSON_IO_DIR="${JETSON_IO_DIR:-/opt/nvidia/jetson-io}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/jetson-io-dtb}"
STATE_DIR="${STATE_DIR:-/var/lib/jetson-io-dtb-fix}"

log() {
    printf '[INFO] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage:
  sudo bash $SCRIPT_NAME status
  sudo bash $SCRIPT_NAME fix-jetson-io [candidate.dtb]
  sudo bash $SCRIPT_NAME verify-jetson-io
  sudo bash $SCRIPT_NAME restore-jetson-io [backup-id]
  sudo bash $SCRIPT_NAME expand-rootfs [partition]

Commands:
  status             Show the active model/compatible values, package versions,
                     DTB files, and exact Jetson-IO matches.
  fix-jetson-io      Install a DTB in /boot/dtb whose embedded model and
                     compatible values exactly match the active device tree.
                     Without an argument, a matching DTB is selected from /boot.
  verify-jetson-io   Verify the exact DTB match and run Jetson-IO list mode.
  restore-jetson-io  Undo the most recent fix-jetson-io file installation.
  expand-rootfs      Grow an ext filesystem partition. Unrelated to Jetson-IO.
EOF
}

rerun_as_root() {
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        return 0
    fi

    command -v sudo >/dev/null 2>&1 || die "sudo is required"
    local script_path
    script_path="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
    exec sudo -- "$script_path" "$@"
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

read_dt_value() {
    local path="$1"
    if [[ -r "$path" ]]; then
        tr '\000' '\n' < "$path" | sed '/^[[:space:]]*$/d' | paste -sd ' ' -
    fi
}

active_model() {
    read_dt_value "$DT_BASE/model"
}

active_compatible() {
    read_dt_value "$DT_BASE/compatible"
}

active_sku() {
    active_compatible | grep -Eo 'p3767-[0-9]{4}' | head -n 1 || true
}

dtb_prop() {
    local dtb="$1"
    local prop="$2"
    fdtget "$dtb" / "$prop" 2>/dev/null || true
}

validate_dtb() {
    local path="$1"
    [[ -s "$path" ]] || die "DTB is missing or empty: $path"

    local magic
    magic="$(od -An -tx1 -N4 "$path" | tr -d '[:space:]')"
    [[ "$magic" == "d00dfeed" ]] || die "Invalid DTB magic: $path"
}

dtb_matches_active() {
    local dtb="$1"
    [[ "$(dtb_prop "$dtb" model)" == "$(active_model)" ]] \
        && [[ "$(dtb_prop "$dtb" compatible)" == "$(active_compatible)" ]]
}

find_matching_dtbs() {
    local directory="$1"
    local dtb

    for dtb in "$directory"/*.dtb; do
        [[ -f "$dtb" ]] || continue
        if dtb_matches_active "$dtb"; then
            printf '%s\n' "$dtb"
        fi
    done
}

show_identity() {
    printf '%s\n' '=== Active device tree identity ==='
    printf 'model:      %s\n' "$(active_model)"
    printf 'compatible: %s\n' "$(active_compatible)"
    printf 'module SKU: %s\n' "$(active_sku)"
}

show_packages() {
    printf '%s\n' '=== NVIDIA packages ==='
    if command -v dpkg-query >/dev/null 2>&1; then
        dpkg-query -W nvidia-l4t-jetson-io nvidia-l4t-kernel-dtbs 2>/dev/null || true
    else
        printf '%s\n' 'dpkg-query is not installed.'
    fi
}

verify_exact_match() {
    need_cmd fdtget

    local matches=()
    mapfile -t matches < <(find_matching_dtbs "$DTB_DIR")

    printf '%s\n' '=== Jetson-IO DTB exact match ==='
    if [[ ${#matches[@]} -eq 0 ]]; then
        printf '%s\n' "No matching DTB found in $DTB_DIR"
        return 1
    fi

    printf '%s\n' "${matches[@]}"
    if [[ ${#matches[@]} -gt 1 ]]; then
        warn "Multiple exact DTB matches found; Jetson-IO will reject this state."
        return 2
    fi

    log "Exactly one Jetson-IO DTB match was found."
}

show_status() {
    show_identity
    show_packages

    printf '%s\n' '=== Super DTBs in /boot ==='
    local files=("$BOOT_DIR"/*super*.dtb "$DTB_DIR"/*super*.dtb)
    if [[ ${#files[@]} -gt 0 ]]; then
        ls -l "${files[@]}"
    else
        printf '%s\n' 'No Super DTB files found.'
    fi

    verify_exact_match || true
}

select_candidate() {
    local explicit="${1:-}"
    if [[ -n "$explicit" ]]; then
        explicit="$(readlink -f "$explicit")"
        [[ -f "$explicit" ]] || die "Candidate DTB not found: $explicit"
        validate_dtb "$explicit"
        dtb_matches_active "$explicit" \
            || die "Candidate model/compatible values do not match the active device tree: $explicit"
        printf '%s\n' "$explicit"
        return 0
    fi

    local candidates=()
    mapfile -t candidates < <(find_matching_dtbs "$BOOT_DIR")

    if [[ ${#candidates[@]} -eq 1 ]]; then
        printf '%s\n' "${candidates[0]}"
        return 0
    fi

    if [[ ${#candidates[@]} -gt 1 ]]; then
        local preferred=()
        local candidate base
        for candidate in "${candidates[@]}"; do
            base="$(basename "$candidate")"
            if [[ "$base" == *-nv-super.dtb && "$base" != kernel_* ]]; then
                preferred+=("$candidate")
            fi
        done

        if [[ ${#preferred[@]} -eq 1 ]]; then
            printf '%s\n' "${preferred[0]}"
            return 0
        fi

        printf '%s\n' "Matching candidates:" >&2
        printf '  %s\n' "${candidates[@]}" >&2
        die "Multiple matching DTBs found in $BOOT_DIR; provide the intended candidate path explicitly."
    fi

    if [[ -r "$ACTIVE_FDT" ]]; then
        validate_dtb "$ACTIVE_FDT"
        dtb_matches_active "$ACTIVE_FDT" \
            || die "The active FDT could not be validated against the active device tree."
        printf '%s\n' "$ACTIVE_FDT"
        return 0
    fi

    die "No matching DTB was found in /boot and /sys/firmware/fdt is unavailable."
}

destination_for_candidate() {
    local candidate="$1"
    local base

    if [[ "$candidate" == "$ACTIVE_FDT" ]]; then
        base="kernel-active-$(active_sku)-super.dtb"
    else
        base="$(basename "$candidate")"
        [[ "$base" == kernel_* ]] || base="kernel_$base"
    fi

    printf '%s/%s\n' "$DTB_DIR" "$base"
}

run_jetson_io_check() {
    local command="$JETSON_IO_DIR/config-by-function.py"
    [[ -f "$command" ]] || die "Jetson-IO command not found: $command"
    need_cmd python3

    printf '%s\n' '=== Jetson-IO function list ==='
    python3 "$command" -l all
}

fix_jetson_io() {
    need_cmd fdtget
    need_cmd install
    need_cmd od
    need_cmd sha256sum

    local existing=()
    mapfile -t existing < <(find_matching_dtbs "$DTB_DIR")
    if [[ ${#existing[@]} -eq 1 ]]; then
        log "Jetson-IO already has an exact DTB match: ${existing[0]}"
        run_jetson_io_check
        return 0
    elif [[ ${#existing[@]} -gt 1 ]]; then
        printf '  %s\n' "${existing[@]}" >&2
        die "Multiple exact DTB matches already exist in $DTB_DIR"
    fi

    local candidate destination backup_id backup_dir had_existing=0
    candidate="$(select_candidate "${1:-}")"
    destination="$(destination_for_candidate "$candidate")"
    backup_id="$(date +%Y%m%d-%H%M%S)"
    backup_dir="$BACKUP_ROOT/$backup_id"

    mkdir -p "$DTB_DIR" "$backup_dir" "$STATE_DIR"
    if [[ -f "$destination" ]]; then
        cp -a "$destination" "$backup_dir/destination.before.dtb"
        had_existing=1
    fi

    {
        printf 'backup_id=%s\n' "$backup_id"
        printf 'source=%s\n' "$candidate"
        printf 'destination=%s\n' "$destination"
        printf 'had_existing=%s\n' "$had_existing"
        printf 'model=%s\n' "$(active_model)"
        printf 'compatible=%s\n' "$(active_compatible)"
        printf 'installed_at=%s\n' "$(date -Is)"
    } > "$backup_dir/fix-info.txt"

    install -m 0644 "$candidate" "$destination"
    sha256sum "$candidate" "$destination" | tee "$backup_dir/sha256.txt"
    printf '%s\n' "$backup_id" > "$STATE_DIR/last-backup-id"
    sync

    log "Installed matching Jetson-IO DTB: $destination"
    verify_exact_match
    run_jetson_io_check
    log "Jetson-IO DTB discovery is working. No reboot was required for this repair."
}

restore_jetson_io() {
    local backup_id="${1:-}"
    if [[ -z "$backup_id" ]]; then
        [[ -r "$STATE_DIR/last-backup-id" ]] || die "No previous fix state was found"
        backup_id="$(cat "$STATE_DIR/last-backup-id")"
    fi

    [[ "$backup_id" =~ ^[0-9]{8}-[0-9]{6}$ ]] || die "Invalid backup ID: $backup_id"
    local backup_dir="$BACKUP_ROOT/$backup_id"
    local info="$backup_dir/fix-info.txt"
    [[ -f "$info" ]] || die "Backup not found: $backup_dir"

    local destination had_existing
    destination="$(sed -n 's/^destination=//p' "$info")"
    had_existing="$(sed -n 's/^had_existing=//p' "$info")"

    case "$destination" in
        "$DTB_DIR"/*.dtb) ;;
        *) die "Unsafe destination recorded in backup: $destination" ;;
    esac

    if [[ "$had_existing" == "1" ]]; then
        [[ -f "$backup_dir/destination.before.dtb" ]] \
            || die "Original destination backup is missing"
        install -m 0644 "$backup_dir/destination.before.dtb" "$destination"
        log "Restored the previous DTB: $destination"
    else
        rm -f -- "$destination"
        log "Removed the DTB installed by fix-jetson-io: $destination"
    fi
    sync
}

expand_rootfs() {
    local partition="${1:-}"
    need_cmd findmnt
    need_cmd lsblk
    need_cmd resize2fs

    if [[ -z "$partition" ]]; then
        partition="$(findmnt -n -o SOURCE /)"
    fi
    [[ -b "$partition" ]] || die "Root source is not a block partition: $partition"

    local disk_name partition_number disk
    disk_name="$(lsblk -ndo PKNAME "$partition" | head -n 1)"
    partition_number="$(lsblk -ndo PARTN "$partition" | head -n 1)"
    [[ -n "$disk_name" && -n "$partition_number" ]] \
        || die "Unable to resolve disk and partition number for $partition"
    disk="/dev/$disk_name"

    log "Growing partition $partition on $disk"
    if command -v growpart >/dev/null 2>&1; then
        growpart "$disk" "$partition_number"
    else
        need_cmd parted
        parted -s "$disk" "resizepart $partition_number 100%"
    fi

    command -v partprobe >/dev/null 2>&1 && partprobe "$disk" || true
    resize2fs "$partition"
    log "Filesystem expansion completed."
}

main() {
    local command="${1:-help}"
    if [[ $# -gt 0 ]]; then
        shift
    fi

    case "$command" in
        status)
            show_status
            ;;
        fix-jetson-io)
            rerun_as_root fix-jetson-io "$@"
            fix_jetson_io "$@"
            ;;
        verify-jetson-io)
            rerun_as_root verify-jetson-io "$@"
            show_identity
            verify_exact_match
            run_jetson_io_check
            ;;
        restore-jetson-io)
            rerun_as_root restore-jetson-io "$@"
            restore_jetson_io "$@"
            ;;
        expand-rootfs)
            rerun_as_root expand-rootfs "$@"
            expand_rootfs "$@"
            ;;
        help|-h|--help)
            usage
            ;;
        *)
            usage >&2
            die "Unknown command: $command"
            ;;
    esac
}

if [[ "${JETSON_DTB_LIB_ONLY:-0}" != "1" ]]; then
    main "$@"
fi
