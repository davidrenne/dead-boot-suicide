# **💀 dead-boot-suicide 🪦**

A reckless little ISO generator for people who want a machine to boot and immediately wipe itself with a pre-captured disk image.
No menus. No confirmations. No brakes.
If it boots, it dies. ☠️🔥

This tool takes:

1. A **SystemRescue ISO** 🛟
2. A **Clonezilla image folder** you exported 📁
3. A **target disk name** (e.g., `nvme0n1`, `sda`, etc.) 💽
4. An **output ISO path** 🧨

…and builds a bootable “suicide ISO” that **automatically restores** the disk image onto the target drive and shuts the machine down.

Use it carefully. Or don’t. It’s your funeral pyre. 🪦🔥

---

# **⚙️ Features**

* Boots into SystemRescue 🚀
* Immediately runs an autorun script 🤖
* Locates your injected Clonezilla image folder 🗂️
* Restores:

  * partition table 🧩
  * each `*-ptcl-img.*` segment 📦
* No password, menu, or interaction required 🙅‍♂️
* Optional CPU-based disk auto-detection 🧠
* Shuts down when finished (unless debug mode enabled) 📴
* Runs on macOS + Linux 🍎🐧
* Built for automation, manufacturing workflows, and absolute chaos 🧨

---

# **🍺 Requirements (macOS)**

Install these four packages before running the generator:

```
brew install p7zip
brew install cdrtools
brew install xorriso
brew install gnu-sed
```

---

# **🧬 How It Works**

The script:

1. Extracts a SystemRescue ISO 📦
2. Injects your Clonezilla image folder 💉
3. Generates a `/autorun/restore` script that executes at boot 🔥
4. Rebuilds the ISO with proper EFI + BIOS boot entries 🧱
5. Outputs a final “dead-boot” disc image ⚰️

At runtime SystemRescue mounts itself at:

```
/run/archiso/bootmnt
```

Your image folder becomes:

```
/run/archiso/bootmnt/custom-img/<your-folder>
```

The autorun script then:

* detects target disk 🎯
* rewrites partition table with `sfdisk`
* restores partitions via `partclone.restore`
* shuts down 🔌

---

# **📸 How to Obtain the Clonezilla Image Folder (Required)**

This clean workflow exports the folder you feed into dead-boot-suicide.

---

## **1. Prepare Two USB Drives** 💽💽

* One boots Clonezilla Live
* One stores the exported image folder (must be **ExFAT**)

USB example:
[https://a.co/d/3k1ogaX](https://a.co/d/3k1ogaX)

Download Clonezilla Live:
[https://clonezilla.org/downloads/download.php?branch=stable](https://clonezilla.org/downloads/download.php?branch=stable)
Older version shown in screenshots:
[https://sourceforge.net/projects/clonezilla/files/clonezilla_live_stable/3.1.0-22/](https://sourceforge.net/projects/clonezilla/files/clonezilla_live_stable/3.1.0-22/)

Create bootable USB:
[https://clonezilla.org/liveusb.php](https://clonezilla.org/liveusb.php)

Format storage USB as **ExFAT**.

---

## **2. Export Image Using Clonezilla** 🧬📦

### **Step 1 — Boot Clonezilla**

<img src="https://clonezilla.org/clonezilla-live/doc/01_Save_disk_image/images/ocs-01-bootmenu.png">

---

### **Step 2 — Select Language**

<img src="https://clonezilla.org/clonezilla-live/doc/01_Save_disk_image/images/ocs-03-lang.png">

---

### **Step 3 — Keyboard Layout**

<img src="https://clonezilla.org/clonezilla-live/doc/01_Save_disk_image/images/ocs-04-keymap.png">

---

### **Step 4 — Start Clonezilla**

<img src="https://clonezilla.org/clonezilla-live/doc/01_Save_disk_image/images/ocs-05-start-clonezilla.png">

---

### **Step 5 — device-image Mode**

<img src="https://clonezilla.org/clonezilla-live/doc/01_Save_disk_image/images/ocs-06-dev-img.png">

---

### **Step 6 — local_dev**

<img src="https://clonezilla.org/clonezilla-live/doc/01_Save_disk_image/images/ocs-07-1-img-repo.png">

Press **Ctrl-C** at the mount screen to continue.

---

### **Step 7 — Select Storage USB**

Choose the **ExFAT** drive. 🧂

---

### **Step 8 — Select Folder + savedisk**

* Choose **Done**
* Choose **Beginner mode**
* Choose **savedisk**
* Enter folder name like:

```
machine-2025-12-11-img
```

Clonezilla will:

* repair filesystem
* image the drive
* verify image
* skip encryption
* shut down when complete

---

### **Step 9 — Done** 🎉

Your exported image folder will look like:

```
d1.partitions
nvme0n1p1.vfat-ptcl-img.zst.aa
nvme0n1p2.ext4-ptcl-img.zst.ab
Info-img-size.txt
Info-lspci.txt
...
```

This folder is the **payload** for dead-boot-suicide.

---

# **💿 Generating a Suicide ISO**

```
dead-boot-suicide \
    ~/Downloads/systemrescue-12.02-amd64.iso \
    /Volumes/ESD-USB/machine-2025-12-11-img \
    nvme0n1 \
    ~/Downloads/machine-2025-12-11-img-suicide.iso
```

Arguments:

1. SystemRescue ISO path
2. Clonezilla image folder
3. Target disk (no `/dev/` prefix)
4. Output ISO

Valid disks:

```
sda
mmcblk0
nvme0n1
```

---

# **🤖 Autorun Behavior**

On boot:

* no menu
* no timeout
* restores all `*-ptcl-img.*` segments
* rewrites partition table
* shuts down

If anything fails, it drops to shell for debugging. 🛠️

---

# **🔥 Danger Zone**

This project exists to automate destruction.
If you boot the ISO on the wrong machine, whatever happens next is between you, your motherboard, and your local spiritual advisor. 🧘‍♂️📉

dead-boot-suicide was born because the **old workflow was a carnival of misery** 🎪💀:

* Clonezilla’s *“magic number errors”*
* Secure Boot tantrums
* ISOLINUX screaming about kernels you definitely loaded
* geniso scripts written by someone who clearly hates you
* xorriso failing because the moon was in retrograde 🌕
* USB writes powered by a dying hamster 🐹
* images that restored perfectly only in *alternate dimensions* 🌌

Everything felt like a haunted house built from bash, duct tape, and spite. 👻🩹

So this exists for one reason:

**Never again should a human suffer while trying to burn an ISO that just… boots.**

You give it a folder → it gives you a murder-ISO → it boots → it wipes → the end. ⚰️💥

Use it wrong and congratulations:
you’ve become part of natural selection in software form. 🧬🔥

---

# **📜 License**

MIT, because nothing matters. 🪦
