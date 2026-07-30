#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Dead Boot automatic Ubuntu 24.04 restore
#
# Required payload:
#   root.fsa
#   boot.fsa
#
# Target layout:
#   p1 = 512 MiB FAT32 EFI
#   p2 = 2 GiB ext4 /boot
#   p3 = remaining disk ext4 /
#
# The target disk is completely erased.
# ============================================================

ROOT_IMAGE="${DEADBOOT_ROOT_IMAGE:-${DEADBOOT_IMAGE:-/run/archiso/bootmnt/custom-img/root.fsa}}"
BOOT_IMAGE="${DEADBOOT_BOOT_IMAGE:-$(dirname "$ROOT_IMAGE")/boot.fsa}"

TARGET_MOUNT="/mnt/target"
LOG_FILE="/tmp/deadboot-restore.log"

exec > >(tee -a "$LOG_FILE") 2>&1

fatal() {
    echo
    echo "============================================================"
    echo "RESTORE FAILED"
    echo "============================================================"
    echo "$*"
    echo
    echo "Log:"
    echo "  $LOG_FILE"
    echo
    echo "A rescue shell will now open."
    exec /bin/bash
}

cleanup_mounts() {
    set +e

    mountpoint -q "$TARGET_MOUNT/run" &&
        umount -R -l "$TARGET_MOUNT/run"

    mountpoint -q "$TARGET_MOUNT/sys" &&
        umount -R -l "$TARGET_MOUNT/sys"

    mountpoint -q "$TARGET_MOUNT/proc" &&
        umount -R -l "$TARGET_MOUNT/proc"

    mountpoint -q "$TARGET_MOUNT/dev" &&
        umount -R -l "$TARGET_MOUNT/dev"

    mountpoint -q "$TARGET_MOUNT/boot/efi" &&
        umount -l "$TARGET_MOUNT/boot/efi"

    mountpoint -q "$TARGET_MOUNT/boot" &&
        umount -l "$TARGET_MOUNT/boot"

    mountpoint -q "$TARGET_MOUNT" &&
        umount -l "$TARGET_MOUNT"

    set -e
}

trap 'fatal "Failure at line $LINENO: $BASH_COMMAND"' ERR

[[ "$EUID" -eq 0 ]] ||
    fatal "restore.sh must run as root."

REQUIRED_COMMANDS=(
    awk
    blkid
    blockdev
    chroot
    dd
    find
    fsarchiver
    lsblk
    mkfs.fat
    mount
    mountpoint
    partprobe
    sgdisk
    sort
    udevadm
    umount
    wipefs
)

for command_name in "${REQUIRED_COMMANDS[@]}"; do
    command -v "$command_name" >/dev/null 2>&1 ||
        fatal "Missing SystemRescue command: $command_name"
done

[[ -f "$ROOT_IMAGE" ]] ||
    fatal "Missing root archive: $ROOT_IMAGE"

[[ -f "$BOOT_IMAGE" ]] ||
    fatal "Missing boot archive: $BOOT_IMAGE"

echo
echo "============================================================"
echo "DEAD BOOT — UBUNTU 24.04 AUTOMATIC RESTORE"
echo "============================================================"
echo
echo "Root archive:"
echo "  $ROOT_IMAGE"
echo
echo "Boot archive:"
echo "  $BOOT_IMAGE"
echo

# ============================================================
# Select destination disk
# ============================================================

TARGET_DISK="$(
    lsblk -b -d -n -p -o NAME,SIZE,TYPE,RM,TRAN |
        awk '
            $3 == "disk" &&
            $4 == 0 &&
            $5 != "usb" {
                print $1, $2
            }
        ' |
        sort -k2,2nr |
        awk 'NR == 1 { print $1 }'
)"

[[ -n "$TARGET_DISK" ]] ||
    fatal "No internal destination disk was found."

case "$TARGET_DISK" in
    /dev/nvme*|/dev/mmcblk*)
        EFI_PARTITION="${TARGET_DISK}p1"
        BOOT_PARTITION="${TARGET_DISK}p2"
        ROOT_PARTITION="${TARGET_DISK}p3"
        ;;
    *)
        EFI_PARTITION="${TARGET_DISK}1"
        BOOT_PARTITION="${TARGET_DISK}2"
        ROOT_PARTITION="${TARGET_DISK}3"
        ;;
esac

echo "Selected destination disk:"
echo "  $TARGET_DISK"
echo

lsblk \
    -o NAME,PATH,SIZE,TYPE,FSTYPE,TRAN,RM,MOUNTPOINTS \
    "$TARGET_DISK" || true

echo
echo "EVERYTHING ON $TARGET_DISK WILL BE DESTROYED."
echo

for seconds in $(seq 15 -1 1); do
    printf '\rStarting destructive restore in %2d seconds...' "$seconds"
    sleep 1
done

echo
echo

# ============================================================
# Stop anything using the disk
# ============================================================

echo "Disabling swap..."

swapoff -a 2>/dev/null || true

echo "Deactivating existing LVM volumes..."

if command -v vgchange >/dev/null 2>&1; then
    vgchange -an 2>/dev/null || true
fi

echo "Unmounting filesystems from $TARGET_DISK..."

while IFS= read -r device_path; do
    [[ -n "$device_path" ]] || continue
    umount -R -l "$device_path" 2>/dev/null || true
done < <(
    lsblk -n -p -r -o PATH "$TARGET_DISK" |
        tail -n +2 |
        tac
)

# ============================================================
# Erase and partition
# ============================================================

echo "Erasing old partition and filesystem metadata..."

wipefs -a -f "$TARGET_DISK"
sgdisk --zap-all "$TARGET_DISK"

dd \
    if=/dev/zero \
    of="$TARGET_DISK" \
    bs=1M \
    count=16 \
    conv=fsync \
    status=none

DISK_SECTORS="$(blockdev --getsz "$TARGET_DISK")"

if (( DISK_SECTORS > 32768 )); then
    dd \
        if=/dev/zero \
        of="$TARGET_DISK" \
        bs=512 \
        seek=$((DISK_SECTORS - 32768)) \
        count=32768 \
        conv=fsync \
        status=none
fi

echo "Creating GPT partition layout..."

sgdisk --clear "$TARGET_DISK"

sgdisk \
    --new=1:1MiB:+512MiB \
    --typecode=1:ef00 \
    --change-name=1:"EFI System" \
    "$TARGET_DISK"

sgdisk \
    --new=2:0:+2GiB \
    --typecode=2:8300 \
    --change-name=2:"Ubuntu Boot" \
    "$TARGET_DISK"

sgdisk \
    --new=3:0:0 \
    --typecode=3:8300 \
    --change-name=3:"Ubuntu Root" \
    "$TARGET_DISK"

partprobe "$TARGET_DISK"
udevadm settle

for attempt in $(seq 1 30); do
    if [[ -b "$EFI_PARTITION" &&
          -b "$BOOT_PARTITION" &&
          -b "$ROOT_PARTITION" ]]; then
        break
    fi

    sleep 1
    partprobe "$TARGET_DISK" 2>/dev/null || true
    udevadm settle 2>/dev/null || true
done

[[ -b "$EFI_PARTITION" ]] ||
    fatal "EFI partition did not appear: $EFI_PARTITION"

[[ -b "$BOOT_PARTITION" ]] ||
    fatal "/boot partition did not appear: $BOOT_PARTITION"

[[ -b "$ROOT_PARTITION" ]] ||
    fatal "Root partition did not appear: $ROOT_PARTITION"

echo
echo "New partition layout:"
echo

lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE "$TARGET_DISK"

# ============================================================
# Restore filesystems
# ============================================================

echo
echo "Formatting EFI partition..."

mkfs.fat -F 32 -n EFI "$EFI_PARTITION"

echo
echo "Restoring Ubuntu root filesystem..."
echo

fsarchiver restfs \
    "$ROOT_IMAGE" \
    id=0,dest="$ROOT_PARTITION"

echo
echo "Restoring Ubuntu /boot filesystem..."
echo

fsarchiver restfs \
    "$BOOT_IMAGE" \
    id=0,dest="$BOOT_PARTITION"

echo
echo "Filesystem restore completed."
echo

mkdir -p "$TARGET_MOUNT"

mount "$ROOT_PARTITION" "$TARGET_MOUNT"

mkdir -p "$TARGET_MOUNT/boot"
mount "$BOOT_PARTITION" "$TARGET_MOUNT/boot"

mkdir -p "$TARGET_MOUNT/boot/efi"
mount "$EFI_PARTITION" "$TARGET_MOUNT/boot/efi"

sync

# ============================================================
# Validate restore
# ============================================================

[[ -x "$TARGET_MOUNT/bin/bash" ]] ||
    fatal "root.fsa does not contain a usable Ubuntu installation."

[[ -f "$TARGET_MOUNT/etc/os-release" ]] ||
    fatal "The restored root filesystem has no /etc/os-release."

echo "Restored operating system:"

grep -E '^(PRETTY_NAME|VERSION_ID)=' \
    "$TARGET_MOUNT/etc/os-release" || true

echo

KERNEL_COUNT="$(
    find "$TARGET_MOUNT/boot" \
        -maxdepth 1 \
        -type f \
        -name 'vmlinuz-*' |
        wc -l |
        tr -d ' '
)"

INITRD_COUNT="$(
    find "$TARGET_MOUNT/boot" \
        -maxdepth 1 \
        -type f \
        -name 'initrd.img-*' |
        wc -l |
        tr -d ' '
)"

[[ "$KERNEL_COUNT" -gt 0 ]] ||
    fatal "boot.fsa did not contain any vmlinuz kernel files."

[[ "$INITRD_COUNT" -gt 0 ]] ||
    fatal "boot.fsa did not contain any initrd.img files."

echo "Kernel files found:    $KERNEL_COUNT"
echo "Initramfs files found: $INITRD_COUNT"
echo

# ============================================================
# Write new fstab
# ============================================================

ROOT_UUID="$(blkid -s UUID -o value "$ROOT_PARTITION")"
BOOT_UUID="$(blkid -s UUID -o value "$BOOT_PARTITION")"
EFI_UUID="$(blkid -s UUID -o value "$EFI_PARTITION")"

[[ -n "$ROOT_UUID" ]] ||
    fatal "Could not determine root UUID."

[[ -n "$BOOT_UUID" ]] ||
    fatal "Could not determine /boot UUID."

[[ -n "$EFI_UUID" ]] ||
    fatal "Could not determine EFI UUID."

echo "New filesystem UUIDs:"
echo
echo "  Root: $ROOT_UUID"
echo "  Boot: $BOOT_UUID"
echo "  EFI:  $EFI_UUID"
echo

if [[ -f "$TARGET_MOUNT/etc/fstab" ]]; then
    cp \
        "$TARGET_MOUNT/etc/fstab" \
        "$TARGET_MOUNT/etc/fstab.before-deadboot"
fi

cat > "$TARGET_MOUNT/etc/fstab" <<EOF
# Generated by Dead Boot
UUID=$ROOT_UUID /         ext4 defaults    0 1
UUID=$BOOT_UUID /boot     ext4 defaults    0 2
UUID=$EFI_UUID  /boot/efi vfat umask=0077  0 1
EOF

rm -f "$TARGET_MOUNT/etc/initramfs-tools/conf.d/resume"

# ============================================================
# Prepare chroot
# ============================================================

echo "Preparing Ubuntu chroot..."

mount --rbind /dev "$TARGET_MOUNT/dev"
mount --make-rslave "$TARGET_MOUNT/dev"

mount -t proc proc "$TARGET_MOUNT/proc"

mount --rbind /sys "$TARGET_MOUNT/sys"
mount --make-rslave "$TARGET_MOUNT/sys"

mount --rbind /run "$TARGET_MOUNT/run"
mount --make-rslave "$TARGET_MOUNT/run"

[[ -x "$TARGET_MOUNT/usr/sbin/grub-install" ]] ||
    fatal "The restored Ubuntu system does not contain grub-install."

[[ -x "$TARGET_MOUNT/usr/sbin/update-grub" ]] ||
    fatal "The restored Ubuntu system does not contain update-grub."

if [[ ! -x "$TARGET_MOUNT/usr/bin/grub-mkstandalone" &&
      ! -x "$TARGET_MOUNT/usr/sbin/grub-mkstandalone" ]]; then
    fatal "The restored Ubuntu system does not contain grub-mkstandalone."
fi

# ============================================================
# Rebuild initramfs and GRUB
# ============================================================

echo
echo "Rebuilding Ubuntu boot configuration..."
echo

chroot "$TARGET_MOUNT" \
    /usr/bin/env \
    DEADBOOT_ROOT_UUID="$ROOT_UUID" \
    DEADBOOT_BOOT_UUID="$BOOT_UUID" \
    /bin/bash <<'CHROOT_EOF'
set -Eeuo pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo "Removing stale LVM boot configuration..."

rm -f /etc/initramfs-tools/conf.d/resume

if [[ -f /etc/default/grub ]]; then
    cp /etc/default/grub /etc/default/grub.before-deadboot
else
    touch /etc/default/grub
fi

if grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub; then
    sed -i \
        's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=""|' \
        /etc/default/grub
else
    echo 'GRUB_CMDLINE_LINUX=""' >> /etc/default/grub
fi

if grep -q '^GRUB_DISABLE_LINUX_UUID=' /etc/default/grub; then
    sed -i \
        's/^GRUB_DISABLE_LINUX_UUID=.*/GRUB_DISABLE_LINUX_UUID=false/' \
        /etc/default/grub
else
    echo 'GRUB_DISABLE_LINUX_UUID=false' >> /etc/default/grub
fi

if grep -q '^GRUB_DISABLE_OS_PROBER=' /etc/default/grub; then
    sed -i \
        's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=true/' \
        /etc/default/grub
else
    echo 'GRUB_DISABLE_OS_PROBER=true' >> /etc/default/grub
fi

echo "Rebuilding initramfs..."

if command -v update-initramfs >/dev/null 2>&1; then
    if [[ -f /etc/initramfs-tools/initramfs.conf ]]; then
        if grep -q '^MODULES=' /etc/initramfs-tools/initramfs.conf; then
            sed -i \
                's/^MODULES=.*/MODULES=most/' \
                /etc/initramfs-tools/initramfs.conf
        else
            echo 'MODULES=most' >> /etc/initramfs-tools/initramfs.conf
        fi
    fi

    update-initramfs -u -k all

elif command -v dracut >/dev/null 2>&1; then
    dracut --regenerate-all --force

else
    echo "WARNING: No initramfs generator found."
    echo "Existing initramfs files from boot.fsa will be retained."
fi

echo "Generating GRUB menu..."

update-grub

echo "Installing normal Ubuntu UEFI GRUB..."

grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --boot-directory=/boot \
    --bootloader-id=ubuntu \
    --recheck \
    --no-nvram

echo "Building portable fallback BOOTX64.EFI..."

mkdir -p /boot/efi/EFI/BOOT

cat > /tmp/deadboot-bootstrap.cfg <<EOF
insmod part_gpt
insmod ext2

search --no-floppy --fs-uuid --set=boot $DEADBOOT_BOOT_UUID

set root=\$boot
set prefix=(\$boot)/grub

configfile (\$boot)/grub/grub.cfg
EOF

grub-mkstandalone \
    --format=x86_64-efi \
    --output=/boot/efi/EFI/BOOT/BOOTX64.EFI \
    "boot/grub/grub.cfg=/tmp/deadboot-bootstrap.cfg"

cat > /boot/efi/EFI/BOOT/grub.cfg <<EOF
insmod part_gpt
insmod ext2

search --no-floppy --fs-uuid --set=boot $DEADBOOT_BOOT_UUID

set root=\$boot
set prefix=(\$boot)/grub

configfile (\$boot)/grub/grub.cfg
EOF

rm -f /tmp/deadboot-bootstrap.cfg

echo "Resetting cloned machine identity..."

rm -f /etc/machine-id
touch /etc/machine-id
rm -f /var/lib/dbus/machine-id

sync
CHROOT_EOF

# ============================================================
# Verify final boot configuration
# ============================================================

echo
echo "Verifying restored boot configuration..."

[[ -f "$TARGET_MOUNT/boot/grub/grub.cfg" ]] ||
    fatal "GRUB configuration was not generated."

[[ -f "$TARGET_MOUNT/boot/efi/EFI/BOOT/BOOTX64.EFI" ]] ||
    fatal "Fallback BOOTX64.EFI was not generated."

[[ -f "$TARGET_MOUNT/boot/efi/EFI/BOOT/grub.cfg" ]] ||
    fatal "Fallback EFI grub.cfg was not generated."

if grep -q '/dev/mapper/ubuntu--vg-ubuntu--lv' \
    "$TARGET_MOUNT/boot/grub/grub.cfg"; then
    grep -E '^[[:space:]]*linux' \
        "$TARGET_MOUNT/boot/grub/grub.cfg" || true

    fatal "Generated grub.cfg still references the old LVM root."
fi

if grep -q 'lvmid/' \
    "$TARGET_MOUNT/boot/grub/grub.cfg"; then
    fatal "Generated grub.cfg still contains an old LVM identifier."
fi

echo
echo "Generated Linux boot entries:"
echo

grep -E '^[[:space:]]*(menuentry|linux|initrd)' \
    "$TARGET_MOUNT/boot/grub/grub.cfg" |
    head -60 || true

echo
echo "Fallback EFI configuration:"
echo

cat "$TARGET_MOUNT/boot/efi/EFI/BOOT/grub.cfg"

sync

# ============================================================
# Finish
# ============================================================

echo
echo "Unmounting restored operating system..."

cleanup_mounts

sync

echo
echo "============================================================"
echo "RESTORE COMPLETE"
echo "============================================================"
echo
echo "Destination disk:"
echo "  $TARGET_DISK"
echo
echo "Remove the USB after shutdown."
echo

sleep 5
poweroff
