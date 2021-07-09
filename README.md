cyberlinux-multiboot
[![build-badge](https://travis-ci.com/phR0ze/cyberlinux-multiboot.svg?branch=master)](https://travis-ci.com/phR0ze/cyberlinux-multiboot)
[![license-badge](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
====================================================================================================

<img align="left" width="48" height="48" src="https://raw.githubusercontent.com/phR0ze/cyberlinux/master/art/logo_256x256.png">
<b>cyberlinux-multiboot</b> provides a GRUB2 based installer and recovery system for the
<b>cyberlinux project</b>.

### Disclaimer
***cyberlinux-boot*** comes with absolutely no guarantees or support of any kind. It is to be used at
your own risk.  Any damages, issues, losses or problems caused by the use of ***cyberlinux-boot*** are
strictly the responsiblity of the user and not the developer/creator of ***cyberlinux-boot***.

### Quick links
* [GRUB2 bootloader](#grub2-bootloader)
  * [GRUB2 configuration](#grub2-configuration)
  * [GFXMenu module](#gfxmenu-module)
  * [Create GRUB2 USB](#create-grub2-usb)
* [Contribute](#contribute)
  * [Git-Hook](#git-hook)
* [License](#license)
  * [Contribution](#contribution)
* [Backlog](#backlog)
* [Changelog](#changelog)

---

# GRUB2 bootloader <a name="grub2-bootloader"/></a>
[GRUB2](https://www.gnu.org/software/grub) offers the ability to easily create a bootable USB drive
for both BIOS and UEFI systems as well as a customizable menu for arbitrary payloads. This
combination is ideal for a customizable initramfs based installer. Using GRUB2 we can boot on any
system with a custom splash screen and menus and then launch our initramfs installer which will
contain the tooling necessary to install the system. After which the initramfs installer will reboot
the system into the newly installed OS.

**References**:
* [GRUB Documentation](https://www.gnu.org/software/grub/manual/grub/html_node/index.html)
* [GRUB Developers Manual](https://www.gnu.org/software/grub/manual/grub-dev/html_node/index.html)
* [GFXMenu Components](https://www.gnu.org/software/grub/manual/grub-dev/html_node/GUI-Components.html#GUI-Components)

### GRUB2 configuration <a name="grub2-configuration"/></a>
GRUB2 is configured via its 

### GFXMenu module <a name="gfxmenu-module"/></a>
The [gfxmenu](https://www.gnu.org/software/grub/manual/grub-dev/html_node/Introduction_005f2.html#Introduction_005f2)
module provides a graphical menu interface for GRUB 2. It functions as an alternative to the menu
interface provided by the `normal` module. The graphical menu uses the GRUB video API supporting
VESA BIOS extensions (VBE) 2.0+ and supports a number of GUI components.

`gfxmenu` supports a container-based layout system. Components can be added to containers, and
containers (which are a type of component) can then be added to other containers, to form a tree of
components. The root component of the tree is a `canvas` component, which allows manual layout of its
child components.

**Non-container components**:
* `label`
* `image`
* `progress_bar`
* `circular_progress`
* `list`

**Container components**:
* `canvas`
* `hbox`
* `vbox`

The GUI component instances are created by the theme loader in `gfxmenu/theme_loader.c` when a them
is loaded.

### Create GRUB2 USB <a name="create-grub2-usb"/></a>
We need to create a bootable USB that will work on older BIOS systems as well as the newer UEFI
systems so make this as universal as possible.

1. Create a directory from which to work
   ```bash
   $ mkdir grub_usb; cd grub_usb
   ```
2. Create deployment entries in `boot.cfg`
   ```bash
   $ 
   ```


# Installer <a name="installer"/></a>
**Goals:** *boot speed*, *simplicity*, and *automation*

Installing Linux on a target system typically consists of booting into a full live system and then
launch a full GUI with wizard to walk you through the installtion process. The downsides of this are
it takes a long time to boot into the live system and it isn't well suited for automating an install
process. The other method which I'll use for `cyberlinux` is a minimal graphical environment that
launches from a pre-boot environment. Fedora's Anaconda or Ubuntu's minimal ncurses based installers
are examples of this. The concept is to build an early user space image typically known as an
`initramfs` that will contain enough tooling to setup and install your system.


## initramfs installer <a name="initramfs-installer"/></a>
The initial ramdisk is in essence a very small environment (a.k.a early userspace) which contains
customizable tooling and instructions to load kernel modules as needed to set up necessary things
before handing over control to `init`. We can leverage this early userspace to build a custom install
environment containing all the tooling required to setup our system.

### Create initramfs installer <a name="create-initramfs-installer"/></a>
An initramfs is made by creating a `cpio` archive, which is an old simple archive format comparable
to tar. This archive is then compressed using `gzip`.





# Boot process <a name="boot-process"/></a>
In order for an Arch Linux system to boot, a Linux-capable boot loader must be set up. The boot
loader is responsible for loading the kernel and initial ramdisk before initiating the boot process.

**References**:
* [IBM Linux boot process](https://developer.ibm.com/articles/l-linuxboot/)
* [Arch boot process](https://wiki.archlinux.org/title/Arch_boot_process)

1. System switched on and power on self test (POST) is executed
2. Stage 1 bootloader e.g. Master Boot Record or EFI application
3. Stage 2 bootloader e.g. GRUB or Systemd
4. Linux kernel
5. init e.g. systemd

## Stage 1 bootloader <a name="stage-1-bootloader"/></a>

### BIOS boot process <a name="bios-boot-process"/></a>
1. After POST, BIOS initializes the hardware required for booting (disk, keyboard controllers etc...)
2. BIOS launches the first 440 bytes (i.e. the Master Boot Record bootstrap code MBR) of the target disk
3. The MBR boot code launches the actual boot loader e.g. GRUB on BIOS boot partition
4. The boot loader then loads the operating system either by chain-loading or directly loading the
   kernel

### UEFI boot process <a name="bios-boot-process"/></a>
1. After POST, UEFI initializes the hardware required for booting (disk, keyboard controllers etc...)

## Stage 2 bootloader <a name="stage-2-bootloader"/></a>

### GRUB2 <a name="grub2"/></a>

### Systemd boot <a name="systemd-boot"/></a>
Previously called `gummiboot` is GRUB's new competitor. It only supports EFI systems. It is a much
more minimal way of booting an environment. Text only and much simpler.

---

# Contribute <a name="Contribute"/></a>
Pull requests are always welcome. However understand that they will be evaluated purely on whether
or not the change fits with my goals/ideals for the project.

## Git-Hook <a name="git-hook"/></a>
Enable the git hooks to have automatic version increments
```bash
cd ~/Projects/clu
git config core.hooksPath .githooks
```

# License <a name="license"/></a>
This project is licensed under either of:
 * MIT license [LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT
 * Apache License, Version 2.0 [LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0

## Contribution <a name="contribution"/></a>
Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in
this project by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without
any additional terms or conditions.

---

# Backlog <a name="backlog"/></a>
* Build bootable installer

# Changelog <a name="changelog"/></a>
