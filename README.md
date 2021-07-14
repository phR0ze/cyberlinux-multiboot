cyberlinux-multiboot
[![build-badge](https://travis-ci.com/phR0ze/cyberlinux-multiboot.svg?branch=master)](https://travis-ci.com/phR0ze/cyberlinux-multiboot)
[![license-badge](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
====================================================================================================

<img align="left" width="48" height="48" src="https://raw.githubusercontent.com/phR0ze/cyberlinux/master/art/logo_256x256.png">
<b>cyberlinux-multiboot</b> provides a reference implementation for a GRUB2 based installer and
recovery system for the <b>cyberlinux project</b> including documentation to build a fully functional
multiboot ISO that supports booting on both BIOS and UEFI hardware systems as a USB stick or CD-ROM.

### Disclaimer
***cyberlinux-boot*** comes with absolutely no guarantees or support of any kind. It is to be used at
your own risk.  Any damages, issues, losses or problems caused by the use of ***cyberlinux-boot*** are
strictly the responsiblity of the user and not the developer/creator of ***cyberlinux-boot***.

### Quick links
* [Usage](#usage)
  * [Install prerequisites](#install-prerequisites)
  * [Create multiboot USB](#create-multiboot-usb)
* [Installer](#installer)
  * [initramfs installer](#initramfs-installer)
    * [create initramfs installer](#create-initramfs-installer)
* [GRUB2 bootloader](#grub2-bootloader)
  * [GRUB2 configuration](#grub2-configuration)
  * [GFXMenu module](#gfxmenu-module)
* [Contribute](#contribute)
  * [Git-Hook](#git-hook)
* [License](#license)
  * [Contribution](#contribution)
* [Backlog](#backlog)
* [Changelog](#changelog)

---

# Usage <a name="grub2-bootloader"/></a>

## Install prerequisites <a name="install-prerequisites"/></a>
**For building grub boot images:**
```bash
$ sudo pacman -S arch-install-scripts grub mtools libisoburn 
```

**For testing grub boot images:**
```bash
$ sudo pacman -S virtualbox virtualbox-host-modules-arch
$ sudo usermod -aG vboxusers <user>
$ sudo reboot
```

## Create multiboot USB <a name="create-multiboot-usb"/></a>
We need to create a bootable USB that will work on older BIOS systems as well as the newer UEFI
systems to make this as universal as possible.

```bash
$ ./build.sh
```

# Installer <a name="installer"/></a>
**Goals:** *boot speed*, *simplicity*, and *automation*

Installing Linux on a target system typically consists of booting into a full live system and then
launch a full GUI with wizard to walk you through the installtion process. The downsides of this are
it takes a long time to boot into the live system and it isn't well suited for automating an install
process from boot. The other method which I'll use for `cyberlinux` is a minimal graphical
environment that launches from a pre-boot environment. Fedora's Anaconda or Ubuntu's minimal ncurses
based installers are examples of this. The concept is to build an early user space image typically
known as an `initramfs` that will contain enough tooling to setup and install your system.

We'll use GRUB to handle booting and presenting the same boot menu regardless of the under lying BIOS
or UEFI hardware systems. The GRUB menu will then launch our installer.

## initramfs installer <a name="initramfs-installer"/></a>
The initial ramdisk is in essence a very small environment (a.k.a early userspace) which contains
customizable tooling and instructions to load kernel modules as needed to set up necessary things
before handing over control to `init`. We can leverage this early userspace to build a custom install
environment containing all the tooling required to setup our system before than rebooting into it.

The installer is composed of three files:
1. `installer` is an initcpio hook and the heart of the installer
2. `installer.conf` initcpio hook configuration for what to include in the installer hook
3. `mkinitcpio.conf` configuration file to construct the initramfs early userspace environment

### Create initramfs installer <a name="create-initramfs-installer"/></a>
An initramfs is made by creating a `cpio` archive, which is an old simple archive format comparable
to tar. This archive is then compressed using `gzip`.


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
* Build bootable USB with custom menus

# Changelog <a name="changelog"/></a>
