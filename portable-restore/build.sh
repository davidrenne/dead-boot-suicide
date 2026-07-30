#!/usr/bin/env bash
set -Eeuo pipefail

# Build a bootable, automatic FSArchiver restore ISO on macOS.
#
# Usage:
#   ./build.sh \
#       [systemrescue.iso] \
#       [root.fsa] \
#       [boot.fsa] \
#       [restore.sh] \
#       [output.iso]
#
# With default filenames in the same directory:
#   ./build.sh
#
# Example:
  # ./build.sh \
  #     ~/Downloads/systemrescue-12.02-amd64.iso \
  #     /Volumes/ESD-USB/root.fsa \
  #     /Volumes/ESD-USB/boot.fsa \
  #     ./restore.sh \
  #     ./deadboot.iso

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SYSTEMRESCUE_ISO="${1:-$SCRIPT_DIR/systemrescue.iso}"
ROOT_ARCHIVE="${2:-$SCRIPT_DIR/root.fsa}"
BOOT_ARCHIVE="${3:-$SCRIPT_DIR/boot.fsa}"
RESTORE_SCRIPT="${4:-$SCRIPT_DIR/restore.sh}"
OUTPUT_ISO="${5:-$SCRIPT_DIR/deadboot.iso}"

BUILD_DIR="$SCRIPT_DIR/.deadboot-build"

GENERATED_AUTORUN="$BUILD_DIR/autorun0"
GENERATED_RESTORE="$BUILD_DIR/restore.sh"

fatal() {
    echo
    echo "============================================================"
    echo "BUILD FAILED"
    echo "============================================================"
    echo "$*"
    echo
    exit 1
}

cleanup() {
    rm -rf "$BUILD_DIR"
}

trap cleanup EXIT
trap 'fatal "Failure at line $LINENO: $BASH_COMMAND"' ERR

absolute_path() {
    local input_path="$1"
    local parent_dir
    local base_name

    parent_dir="$(dirname "$input_path")"
    base_name="$(basename "$input_path")"

    (
        cd "$parent_dir"
        printf '%s/%s\n' "$PWD" "$base_name"
    )
}

# ============================================================
# Validate build environment
# ============================================================

[[ "$(uname -s)" == "Darwin" ]] ||
    fatal "This build.sh is intended for macOS."

command -v xorriso >/dev/null 2>&1 ||
    fatal "xorriso is not installed.

Install it with:

  brew install xorriso"

[[ -f "$SYSTEMRESCUE_ISO" ]] ||
    fatal "SystemRescue ISO not found:

  $SYSTEMRESCUE_ISO"

[[ -f "$ROOT_ARCHIVE" ]] ||
    fatal "root.fsa not found:

  $ROOT_ARCHIVE"

[[ -f "$BOOT_ARCHIVE" ]] ||
    fatal "boot.fsa not found:

  $BOOT_ARCHIVE"

[[ -f "$RESTORE_SCRIPT" ]] ||
    fatal "restore.sh not found:

  $RESTORE_SCRIPT"

[[ "$OUTPUT_ISO" != "$SYSTEMRESCUE_ISO" ]] ||
    fatal "Output ISO cannot overwrite the source SystemRescue ISO."

SYSTEMRESCUE_ISO="$(absolute_path "$SYSTEMRESCUE_ISO")"
ROOT_ARCHIVE="$(absolute_path "$ROOT_ARCHIVE")"
BOOT_ARCHIVE="$(absolute_path "$BOOT_ARCHIVE")"
RESTORE_SCRIPT="$(absolute_path "$RESTORE_SCRIPT")"

OUTPUT_DIR="$(dirname "$OUTPUT_ISO")"
mkdir -p "$OUTPUT_DIR"

OUTPUT_ISO="$(
    cd "$OUTPUT_DIR"
    printf '%s/%s\n' "$PWD" "$(basename "$OUTPUT_ISO")"
)"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

rm -f "$OUTPUT_ISO"

# ============================================================
# Prepare restore script
# ============================================================

cp "$RESTORE_SCRIPT" "$GENERATED_RESTORE"
chmod 0755 "$GENERATED_RESTORE"

# The restore script should normally use the environment variables
# exported by autorun0. These replacements also make the embedded
# defaults point at the boot media in case the environment variables
# are unavailable.

if grep -Eq '^[[:space:]]*ROOT_IMAGE=' "$GENERATED_RESTORE"; then
    sed -E \
        '0,/^[[:space:]]*ROOT_IMAGE=.*/s||ROOT_IMAGE="${DEADBOOT_ROOT_IMAGE:-${DEADBOOT_IMAGE:-/run/archiso/bootmnt/custom-img/root.fsa}}"|' \
        "$GENERATED_RESTORE" > "$GENERATED_RESTORE.tmp"

    mv "$GENERATED_RESTORE.tmp" "$GENERATED_RESTORE"
else
    echo "WARNING: restore.sh has no ROOT_IMAGE= assignment."
    echo "         Autorun environment variables will still be exported."
fi

if grep -Eq '^[[:space:]]*BOOT_IMAGE=' "$GENERATED_RESTORE"; then
    sed -E \
        '0,/^[[:space:]]*BOOT_IMAGE=.*/s||BOOT_IMAGE="${DEADBOOT_BOOT_IMAGE:-$(dirname "$ROOT_IMAGE")/boot.fsa}"|' \
        "$GENERATED_RESTORE" > "$GENERATED_RESTORE.tmp"

    mv "$GENERATED_RESTORE.tmp" "$GENERATED_RESTORE"
else
    echo "WARNING: restore.sh has no BOOT_IMAGE= assignment."
    echo "         Autorun environment variables will still be exported."
fi

chmod 0755 "$GENERATED_RESTORE"

# ============================================================
# Generate SystemRescue autorun script
# ============================================================

cat > "$GENERATED_AUTORUN" <<'AUTORUN_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="/tmp/deadboot-autorun.log"

exec > >(tee -a "$LOG_FILE") 2>&1

fatal() {
    echo
    echo "============================================================"
    echo "DEAD BOOT AUTORUN FAILED"
    echo "============================================================"
    echo "$*"
    echo
    echo "Log:"
    echo "  $LOG_FILE"
    echo
    exec /bin/bash
}

echo
echo "============================================================"
echo "DEAD BOOT AUTOMATIC RESTORE"
echo "============================================================"
echo

find_boot_media() {
    local candidate

    for candidate in \
        /run/archiso/bootmnt \
        /run/archiso/cowspace \
        /mnt/cdrom \
        /mnt/usb \
        /media/cdrom \
        /run/media/*
    do
        [[ -d "$candidate" ]] || continue

        if [[ -f "$candidate/custom-img/root.fsa" ]] &&
           [[ -f "$candidate/custom-img/boot.fsa" ]] &&
           [[ -f "$candidate/custom-img/restore.sh" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        [[ -d "$candidate" ]] || continue

        if [[ -f "$candidate/custom-img/root.fsa" ]] &&
           [[ -f "$candidate/custom-img/boot.fsa" ]] &&
           [[ -f "$candidate/custom-img/restore.sh" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(
        findmnt -rn -o TARGET 2>/dev/null ||
        mount | awk '{print $3}'
    )

    return 1
}

BOOT_MEDIA="$(find_boot_media)" ||
    fatal "Could not locate root.fsa, boot.fsa, and restore.sh on the boot media."

export DEADBOOT_ROOT_IMAGE="$BOOT_MEDIA/custom-img/root.fsa"
export DEADBOOT_BOOT_IMAGE="$BOOT_MEDIA/custom-img/boot.fsa"

# Retain compatibility with restore scripts that still read DEADBOOT_IMAGE.
export DEADBOOT_IMAGE="$DEADBOOT_ROOT_IMAGE"

RESTORE_SCRIPT="$BOOT_MEDIA/custom-img/restore.sh"

echo "Boot media:"
echo "  $BOOT_MEDIA"
echo
echo "Root archive:"
echo "  $DEADBOOT_ROOT_IMAGE"
echo
echo "Boot archive:"
echo "  $DEADBOOT_BOOT_IMAGE"
echo
echo "Restore script:"
echo "  $RESTORE_SCRIPT"
echo

[[ -f "$DEADBOOT_ROOT_IMAGE" ]] ||
    fatal "Missing root archive: $DEADBOOT_ROOT_IMAGE"

[[ -f "$DEADBOOT_BOOT_IMAGE" ]] ||
    fatal "Missing boot archive: $DEADBOOT_BOOT_IMAGE"

[[ -f "$RESTORE_SCRIPT" ]] ||
    fatal "Missing restore script: $RESTORE_SCRIPT"

exec /usr/bin/env bash "$RESTORE_SCRIPT"
AUTORUN_EOF

chmod 0755 "$GENERATED_AUTORUN"

# ============================================================
# Display input information
# ============================================================

echo
echo "============================================================"
echo "DEAD BOOT ISO BUILDER"
echo "============================================================"
echo

echo "SystemRescue ISO:"
echo "  $SYSTEMRESCUE_ISO"
echo "  $(du -h "$SYSTEMRESCUE_ISO" | awk '{print $1}')"
echo

echo "Root archive:"
echo "  $ROOT_ARCHIVE"
echo "  $(du -h "$ROOT_ARCHIVE" | awk '{print $1}')"
echo

echo "Boot archive:"
echo "  $BOOT_ARCHIVE"
echo "  $(du -h "$BOOT_ARCHIVE" | awk '{print $1}')"
echo

echo "Restore script:"
echo "  $RESTORE_SCRIPT"
echo

echo "Output ISO:"
echo "  $OUTPUT_ISO"
echo

# ============================================================
# Check disk space
# ============================================================

AVAILABLE_KB="$(
    df -Pk "$OUTPUT_DIR" |
        awk 'NR == 2 {print $4}'
)"

INPUT_KB="$(
    du -k "$SYSTEMRESCUE_ISO" "$ROOT_ARCHIVE" "$BOOT_ARCHIVE" |
        awk '{total += $1} END {print total}'
)"

# xorriso may need source data plus output plus temporary overhead.
RECOMMENDED_KB=$((INPUT_KB * 2))

if (( AVAILABLE_KB < RECOMMENDED_KB )); then
    echo "WARNING: Free space may be insufficient."
    echo
    echo "Available:"
    echo "  $((AVAILABLE_KB / 1024 / 1024)) GiB"
    echo
    echo "Recommended:"
    echo "  $((RECOMMENDED_KB / 1024 / 1024)) GiB"
    echo
fi

# ============================================================
# Build ISO
# ============================================================

echo "Building bootable ISO..."
echo

xorriso \
    -indev "$SYSTEMRESCUE_ISO" \
    -outdev "$OUTPUT_ISO" \
    -boot_image any replay \
    -map "$ROOT_ARCHIVE" /custom-img/root.fsa \
    -map "$BOOT_ARCHIVE" /custom-img/boot.fsa \
    -map "$GENERATED_RESTORE" /custom-img/restore.sh \
    -map "$GENERATED_AUTORUN" /autorun/autorun0 \
    -chmod 0755 /custom-img/restore.sh -- \
    -chmod 0755 /autorun/autorun0 -- \
    -commit

[[ -f "$OUTPUT_ISO" ]] ||
    fatal "xorriso finished but the output ISO was not created."

# ============================================================
# Verify ISO contents
# ============================================================

echo
echo "Verifying embedded files..."
echo

VERIFY_OUTPUT="$(
    xorriso \
        -indev "$OUTPUT_ISO" \
        -find /custom-img/root.fsa -exec lsdl -- \
        -find /custom-img/boot.fsa -exec lsdl -- \
        -find /custom-img/restore.sh -exec lsdl -- \
        -find /autorun/autorun0 -exec lsdl -- \
        2>&1
)"

printf '%s\n' "$VERIFY_OUTPUT"

for required_iso_path in \
    "/custom-img/root.fsa" \
    "/custom-img/boot.fsa" \
    "/custom-img/restore.sh" \
    "/autorun/autorun0"
do
    if ! grep -Fq "$required_iso_path" <<< "$VERIFY_OUTPUT"; then
        fatal "ISO verification failed. Missing:

  $required_iso_path"
    fi
done

FINAL_SIZE="$(du -h "$OUTPUT_ISO" | awk '{print $1}')"

echo
echo "============================================================"
echo "BUILD COMPLETE"
echo "============================================================"
echo
echo "Output:"
echo "  $OUTPUT_ISO"
echo
echo "Size:"
echo "  $FINAL_SIZE"
echo
echo "Embedded payload:"
echo "  /custom-img/root.fsa"
echo "  /custom-img/boot.fsa"
echo "  /custom-img/restore.sh"
echo "  /autorun/autorun0"
echo
echo "Write to USB:"
echo
echo "  diskutil list"
echo "  diskutil unmountDisk /dev/diskN"
echo "  sudo dd if=\"$OUTPUT_ISO\" of=/dev/rdiskN bs=4m status=progress"
echo "  sync"
echo "  diskutil eject /dev/diskN"
echo
echo "WARNING: Verify diskN is the USB drive."
