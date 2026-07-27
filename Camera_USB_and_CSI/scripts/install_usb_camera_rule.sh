#!/usr/bin/env bash
# Create and install a stable /dev alias for one USB V4L2 capture device.
set -Eeuo pipefail

DEVICE=""
ALIAS_NAME="usb_cam"
RULE_NAME="99-usb-camera.rules"
DRY_RUN=false
LIST_ONLY=false

usage() {
    cat <<'EOF'
Usage: bash install_usb_camera_rule.sh [options]

List the available /dev/videoN devices, then generate a serial-number-specific
udev rule for the USB capture device explicitly selected by the user.

Required workflow:
  1. Run with --list and identify the intended USB capture device manually.
  2. Test that device and confirm its /dev/videoN number.
  3. Run again with --device /dev/videoN, first with --dry-run if desired.

Options:
  --list          List video devices and exit without changing the system.
  --device PATH   Confirmed USB capture device, for example /dev/video1. Required.
  --alias NAME    Alias below /dev; default: usb_cam.
  --dry-run       Print the generated rule without installing it.
  -h, --help      Show this help.
EOF
}

while (($#)); do
    case "$1" in
        --device)
            (($# >= 2)) || { echo "--device requires a value" >&2; exit 2; }
            DEVICE="$2"
            shift 2
            ;;
        --list)
            LIST_ONLY=true
            shift
            ;;
        --alias)
            (($# >= 2)) || { echo "--alias requires a value" >&2; exit 2; }
            ALIAS_NAME="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

run_as_root() {
    if ((EUID == 0)); then
        "$@"
    else
        sudo "$@"
    fi
}

is_usb_capture_device() {
    local candidate="$1"
    local properties
    [[ -c "$candidate" ]] || return 1
    properties="$(udevadm info --query=property --name="$candidate" 2>/dev/null)" || return 1
    grep -qx 'ID_BUS=usb' <<<"$properties" || return 1
    grep -q '^ID_V4L_CAPABILITIES=.*:capture:' <<<"$properties" || return 1
}

property_value() {
    local properties="$1"
    local key="$2"
    awk -F= -v key="$key" '$1 == key {print $2; exit}' <<<"$properties"
}

list_devices() {
    local candidate
    local properties
    local bus
    local capture
    local product
    local vendor_id
    local product_id
    local serial
    local index
    local candidates=()

    shopt -s nullglob
    candidates=(/dev/video*)
    if ((${#candidates[@]} == 0)); then
        echo "No /dev/videoN devices were found."
        return
    fi

    printf '%-12s %-6s %-8s %-5s %-11s %-16s %-20s\n' \
        "DEVICE" "BUS" "CAPTURE" "INDEX" "VID:PID" "SERIAL" "PRODUCT"
    for candidate in "${candidates[@]}"; do
        properties="$(udevadm info --query=property --name="$candidate" 2>/dev/null || true)"
        bus="$(property_value "$properties" ID_BUS)"
        product="$(property_value "$properties" ID_V4L_PRODUCT)"
        vendor_id="$(property_value "$properties" ID_VENDOR_ID)"
        product_id="$(property_value "$properties" ID_MODEL_ID)"
        serial="$(property_value "$properties" ID_SERIAL_SHORT)"
        index="?"
        if [[ -r "/sys/class/video4linux/$(basename -- "$candidate")/index" ]]; then
            read -r index < "/sys/class/video4linux/$(basename -- "$candidate")/index"
        fi
        if grep -q '^ID_V4L_CAPABILITIES=.*:capture:' <<<"$properties"; then
            capture="yes"
        else
            capture="no"
        fi
        [[ -n "$bus" ]] || bus="platform"
        [[ -n "$vendor_id" && -n "$product_id" ]] \
            && vendor_id="${vendor_id,,}:${product_id,,}" \
            || vendor_id="-"
        [[ -n "$serial" ]] || serial="-"
        [[ -n "$product" ]] || product="-"
        printf '%-12s %-6s %-8s %-5s %-11s %-16s %-20s\n' \
            "$candidate" "$bus" "$capture" "$index" "$vendor_id" "$serial" "$product"
    done
}

[[ "$ALIAS_NAME" =~ ^[A-Za-z0-9._-]+$ ]] \
    || fail "Alias may contain only letters, numbers, dot, underscore, and hyphen."

if [[ "$LIST_ONLY" == true ]]; then
    list_devices
    exit 0
fi

if [[ -z "$DEVICE" ]]; then
    echo "Manual device confirmation is required before installing a udev rule."
    echo
    list_devices
    echo
    fail "Identify and test the intended USB capture device, then rerun with --device /dev/videoN."
fi

DEVICE="$(readlink -f -- "$DEVICE")"
is_usb_capture_device "$DEVICE" \
    || fail "Not a USB V4L2 capture device: $DEVICE"

PROPERTIES="$(udevadm info --query=property --name="$DEVICE")"
VENDOR_ID="$(awk -F= '$1 == "ID_VENDOR_ID" {print $2; exit}' <<<"$PROPERTIES")"
PRODUCT_ID="$(awk -F= '$1 == "ID_MODEL_ID" {print $2; exit}' <<<"$PROPERTIES")"
SERIAL_SHORT="$(awk -F= '$1 == "ID_SERIAL_SHORT" {print $2; exit}' <<<"$PROPERTIES")"
DEVICE_BASENAME="$(basename -- "$DEVICE")"
INDEX_FILE="/sys/class/video4linux/$DEVICE_BASENAME/index"
[[ -r "$INDEX_FILE" ]] || fail "Missing V4L2 interface index: $INDEX_FILE"
read -r VIDEO_INDEX < "$INDEX_FILE"

[[ "$VENDOR_ID" =~ ^[0-9A-Fa-f]{4}$ ]] || fail "Invalid USB vendor ID."
[[ "$PRODUCT_ID" =~ ^[0-9A-Fa-f]{4}$ ]] || fail "Invalid USB product ID."
[[ -n "$SERIAL_SHORT" ]] \
    || fail "The USB camera has no serial number; refusing an ambiguous binding."
[[ "$VIDEO_INDEX" =~ ^[0-9]+$ ]] || fail "Invalid V4L2 interface index."

RULE_LINE="SUBSYSTEM==\"video4linux\", KERNEL==\"video*\", ATTR{index}==\"$VIDEO_INDEX\", ATTRS{idVendor}==\"${VENDOR_ID,,}\", ATTRS{idProduct}==\"${PRODUCT_ID,,}\", ATTRS{serial}==\"$SERIAL_SHORT\", SYMLINK+=\"$ALIAS_NAME\", GROUP=\"video\", MODE=\"0660\", TAG+=\"uaccess\""

echo "USB capture device: $DEVICE"
echo "VID:PID: ${VENDOR_ID,,}:${PRODUCT_ID,,}"
echo "Serial: $SERIAL_SHORT"
echo "V4L2 interface index: $VIDEO_INDEX"
echo "Generated rule:"
echo "$RULE_LINE"

if [[ "$DRY_RUN" == true ]]; then
    exit 0
fi

TEMP_RULE="$(mktemp)"
trap 'rm -f -- "$TEMP_RULE"' EXIT
printf '# Generated by camera_usb_and_csi/scripts/install_usb_camera_rule.sh\n%s\n' \
    "$RULE_LINE" > "$TEMP_RULE"

TARGET_RULE="/etc/udev/rules.d/$RULE_NAME"
run_as_root install -m 0644 "$TEMP_RULE" "$TARGET_RULE"
run_as_root udevadm control --reload-rules

DEVICE_PATH="$(udevadm info --query=path --name="$DEVICE")"
run_as_root udevadm trigger --action=add "/sys$DEVICE_PATH"
run_as_root udevadm settle

ALIAS_PATH="/dev/$ALIAS_NAME"
if [[ -L "$ALIAS_PATH" ]]; then
    echo "SUCCESS: $ALIAS_PATH -> $(readlink -f -- "$ALIAS_PATH")"
else
    echo "Rule installed at $TARGET_RULE."
    echo "Unplug and reconnect the USB camera, then check: ls -l $ALIAS_PATH"
fi

if ! id -nG "${SUDO_USER:-$USER}" | tr ' ' '\n' | grep -qx video; then
    echo "WARNING: ${SUDO_USER:-$USER} is not in the video group."
    echo "Run: sudo usermod -aG video ${SUDO_USER:-$USER}, then log out and back in."
fi
