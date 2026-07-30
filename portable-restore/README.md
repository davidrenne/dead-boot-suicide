# Dead Boot Suicide - Portable Restore

Portable Restore is a filesystem-based deployment mode for Dead Boot Suicide.

Instead of cloning an entire disk sector-for-sector, Portable Restore rebuilds
a fresh Linux installation using filesystem archives.

Unlike Clonezilla, this mode:

- restores only Linux filesystems
- creates new GPT partitions
- creates a fresh EFI System Partition
- restores /boot
- restores /
- rebuilds initramfs
- regenerates grub.cfg
- installs GRUB
- creates a portable EFI fallback loader

The resulting installation is not a bit-for-bit clone.

Instead, it is a rebuilt installation using the original operating system files.

---

## Advantages

Compared to Clonezilla:

✔ Much smaller backups

✔ Restores onto larger disks

✔ Automatically generates new filesystem UUIDs

✔ No dependence on original partition UUIDs

✔ Rebuilds EFI

✔ Rebuilds GRUB

✔ Removes stale LVM references

✔ Produces a portable installation

---

## Current Status

Supported

- NVMe SSD
- SATA SSD
- SATA HDD

Known issues

- eMMC currently not working reliably.
- eMMC still requires the Clonezilla/raw-image mode.

---

## Required Backup Files

```
root.fsa
boot.fsa
```

These are generated from the golden machine.

Example:

```bash
sudo fsarchiver savefs -A -Z 7 root.fsa /dev/mapper/ubuntu--vg-ubuntu--lv

sudo fsarchiver savefs -A -Z 7 boot.fsa /dev/nvme0n1p2
```

---

## ISO Contents

```
custom-img/

    root.fsa
    boot.fsa
    restore.sh
```

---

## Restore Process

The restore script automatically:

1. Detects the largest internal disk

2. Erases the disk

3. Creates GPT

```
EFI
BOOT
ROOT
```

4. Restores boot.fsa

5. Restores root.fsa

6. Creates new `/etc/fstab`

7. Removes stale LVM configuration

8. Rebuilds initramfs

9. Generates grub.cfg

10. Installs GRUB

11. Creates EFI fallback bootloader

12. Powers off

No operator interaction is required.

---

## Intended Target

Portable Restore is intended for deploying the same Linux image onto many
different PCs where the storage hardware may differ.

Examples:

- NVMe -> NVMe
- NVMe -> SATA
- SATA -> NVMe

without caring about original partition UUIDs or GPT layout.

---

## Supported Layout

Current target layout:

```
EFI     512 MB FAT32

BOOT      2 GB EXT4

ROOT     Remaining EXT4
```

---

## Current Tested OS

Successfully tested:

Ubuntu 24.04 LTS

- Separate EFI partition
- Separate /boot partition
- Root captured with FSArchiver

---

## Future Support

Expected to support without modification:

Ubuntu

- 22.04 LTS
- 24.04 LTS
- 24.10
- 25.04
- 26.04 LTS

Likely compatible:

- Debian 12
- Debian 13
- Linux Mint
- Pop!_OS
- Kubuntu
- Xubuntu
- Lubuntu
- Ubuntu Server

May require changes:

- Fedora
- Rocky
- AlmaLinux
- RHEL

These distributions often use dracut and have different bootloader defaults.

Not currently supported:

- Btrfs
- ZFS
- LUKS encryption
- Secure Boot custom keys
- RAID
- Multi-boot systems

---

## Comparison

| Feature | Clonezilla Mode | Portable Restore |
|----------|----------------|-----------------|
| Sector clone | ✓ | |
| Raw disk clone | ✓ | |
| eMMC | ✓ | |
| Different size drives | Limited | ✓ |
| Rebuild EFI | | ✓ |
| Rebuild GRUB | | ✓ |
| Portable UUIDs | | ✓ |
| Small backups | | ✓ |
| Easy upgrades | | ✓ |

---

## Why this exists

Clonezilla is excellent when every byte must match the source.

Portable Restore is designed for deploying Linux appliances where rebuilding
the operating system is preferable to cloning an entire disk.
