# 💀 dead-boot-suicide-largest-disk-emmc-sd-nvme 🪦

A bootable ISO generator that doesn’t ask questions—it just finds the largest internal disk and overwrites it.

No prompts. No disk arguments. No second chances.

If it boots, it wipes your pristine image you captured. ☠️🔥

---

## **🍺 Requirements (macOS)**

Install these four packages before running the generator:

```
brew install p7zip
brew install cdrtools
brew install xorriso
brew install gnu-sed
```

## 🧠 What This Version Actually Does

This is not the original targeted-disk version. This one:

- **Auto-detects the largest internal disk**
- **Ignores USB devices**
- Supports:
  - eMMC (`mmcblk*`)
  - NVMe (`nvme*`)
  - SATA (`sda`, etc.)
- Uses **two completely different restore strategies** depending on hardware:

| Disk Type   | Restore Method                          |
| ----------- | --------------------------------------- |
| eMMC        | **Full raw disk restore (dd)**          |
| NVMe / SATA | **Partition-aware restore (partclone)** |

Because ro.

---

## 🔥 Why This Exists (The Hard Truth)

After way too many failures:

- NVMe images restored fine → NVMe
- Same images → eMMC → **boot failure**
- GRUB dropped to shell
- LVM missing
- initramfs screaming

Root cause:

> **partclone images do NOT reliably reconstruct full disk + LVM + boot layout across different hardware types**

Especially on:

- eMMC
- cheap embedded boards
- different disk geometries

---

## 💣 The Fix

For eMMC we stopped being clever: **one contiguous raw image, streamed to the whole block device.** No reconstruction. No interpretation. Just overwrite reality.

On the **running restore** (inside SystemRescue), that’s the same idea as:

```bash
zstd -dc disk.img.zst | dd of=/dev/mmcblk0 bs=16M status=progress
```

…but **`/dev/mmcblk0` is whatever eMMC the box actually has**, and you are **not** expected to type this on your laptop when you build the ISO.

### 📁 Where `disk.img.zst` actually lives (so one ISO can cover NVMe/SATA _and_ eMMC)

Point **`dead-boot-suicide-largest-disk-emmc-sd-nvme`** at your Clonezilla **`savedisk` folder** (the image repo folder Clonezilla created, e.g. `HW-…-img`). That tree is what gets baked into the ISO.

- **NVMe / SATA:** keep the normal Clonezilla layout at the **top level** of that folder (partition stubs, partition table files, etc.)—the script restores from there.
- **eMMC:** the autorun switches to a subfolder named **`mmc`**. Put your **full-disk** zstd image here:

  ```
  <your-clonezilla-folder>/
    mmc/
      disk.img.zst
  ```

If the target disk is eMMC and `mmc/disk.img.zst` is missing, restore fails early with a clear error.

So: **you prepare the folder** (Clonezilla export + optional `mmc/disk.img.zst`). The ISO carries both stories; at boot the script picks the path that matches the hardware.

### 📸 Export the image with Clonezilla first on a non eMMC disk

Before **Build the ISO** (below), capture the main computer disk hardware with **Clonezilla** ande resulting **`savedisk`** image folder to the machine where you run this generator. Follow the **[Export Image using Clonezilla](https://github.com/davidrenne/dead-boot-suicide/blob/main/README.md#2-export-image-using-clonezilla-)** walkthrough in the main repo.

For the **main** image used by this ISO (NVMe/SATA restore), run Clonezilla against the **internal system disk** on the source unit—typically **NVMe** (e.g. `nvme0n1`) or **SATA** (e.g. `sda` / `sda1` is a partition on that disk; you still select the **whole disk** in `savedisk` as Clonezilla documents). That export is what you pass as the second argument to the script. The optional **`mmc/disk.img.zst`** path above is separate and is what you add for **eMMC** targets.

---

##📸 Creating the eMMC Raw Image 

On your pristine eMMC machine:

```bash
dd if=/dev/mmcblk0 bs=16M status=progress | zstd -T0 -o disk.img.zst
```

That’s it.

No Clonezilla.
No partition guessing.
No LVM reconstruction.

You now have a perfect clone of reality.  Place this in the mmc directory in your clonezilla export folder.

---

## 🛠️ Build the ISO

Example:

```bash
dead-boot-suicide-largest-disk-emmc-sd-nvme \
  ~/Downloads/systemrescue-12.02-amd64.iso \
  /Volumes/ESD-USB/2026-04-02-img \
  ~/Downloads/2026-04-02-img.iso
```

Needs: `bash`, `xorriso`, `7z` (p7zip). Argument 2 is the folder cinto the ISO as `custom-img/<basename>/`.

---

## ⚙️ Behavior at Boot

1. SystemRescue boots
2. Script runs automatically
3. It:

### 🔍 Detects target disk

- prefers NVMe
- otherwise largest non-USB internal disk

### 💀 If eMMC (`mmcblk*`):

- expects **`mmc/disk.img.zst`** inside the embedded image folder
- wipes target, streams that image to the whole disk (`zstd` → `dd`), re-reads partition table, optional expand, then shutdown prompt

### 🧠 If NVMe/SATA:

- restores partition table / stubs from the **top-level** Clonezilla files
- restores partitions via partclone (and friends)
- expands largest partition / filesystem when possible
- shutdown prompt

---

## 💾 Writing the ISO to a bootable USB

After you produce an `.iso` with this bash script, you need to copy it to a USB stick in **raw** form so the machine can boot SystemRescue and run the autorun restore—not just copy the file onto a FAT32 volume like a normal document.

Common **open-source** options:

| Tool                          | Notes                                                                                                                                                                                  |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **[balenaEtcher](https://etcher.balena.io/)** | Cross‑platform (Windows, macOS, Linux). Pick your ISO, pick the USB drive, flash. Hard to misuse.                                                                                      |
| **[Rufus](https://rufus.ie/)**                | Very popular on **Windows**. GPLv3. Good for ISO → USB, including hybrid images.                                                                                                       |
| **`dd` (terminal)**                           | Built in on macOS/Linux: low-level copy of the ISO to the **wholeice** (e.g. `/dev/rdiskN` on Mac, `/dev/sdX` on Linux). Easy to wipe the wrong disk—triple-check the device name. |

Pick a are USB drive (contents will be erased), flash the ISO, eject safely, then boot that USB on the target gateway.

---

## ☠️ Security

The embedded restore is intentionally destructive. Meant for customers to easily flash your software linux build in a downloadable iso cloner. Only boot this ISO on hardware youn to image.

