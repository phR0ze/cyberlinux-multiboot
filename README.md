cyberlinux-multiboot
[![build-badge](https://travis-ci.com/phR0ze/cyberlinux-multiboot.svg?branch=master)](https://travis-ci.com/phR0ze/cyberlinux-multiboot)
[![license-badge](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
====================================================================================================

<img align="left" width="48" height="48" src="https://raw.githubusercontent.com/phR0ze/cyberlinux/master/art/logo_256x256.png">
<b>cyberlinux-multiboot</b> provides a reference implementation for a GRUB2 based installer and
recovery system for the <b>cyberlinux project</b> including documentation to build a fully functional
multiboot ISO that supports booting on both BIOS and UEFI hardware systems as a USB stick or CD-ROM.

### Disclaimer
***cyberlinux-multiboot*** comes with absolutely no guarantees or support of any kind. It is to be
used at your own risk.  Any damages, issues, losses or problems caused by the use of
***cyberlinux-multiboot*** are strictly the responsiblity of the user and not the developer/creator
of ***cyberlinux-multiboot***.

### Quick links
* [Usage](#usage)
  * [Prerequisites](#prerequisites)
    * [Arch Linux](#arch-linux)
    * [Ubuntu](#ubuntu)
  * [Create multiboot USB](#create-multiboot-usb)
    * [Test USB in VirtualBox](#test-usb-in-virtualbox)
* [Configuration](#configuration)
  * [dconf](#dconf)
* [Hardware](#hardware)
  * [ACEPC AK1](#acepc-ak1)
  * [Dell XPS 13 9310](#dell-xps-13-9310)
* [Installer](#installer)
  * [initramfs installer](#initramfs-installer)
    * [create initramfs installer](#create-initramfs-installer)
* [Docker](#docker)
  * [Basics](#basics)
    * [Shell into a running container](#shell-into-a-running-container)
    * [Create image from directory](#create-images-from-directory)
    * [Check if image exists](#check-if-image-exists)
  * [Caching packages](#caching-packages)
* [mkinitcpio](#mkinitcpio)
  * [mkinitcpio-vt-colors](#mkinitcpio-vt-colors)
  * [docker mkinitcpio issues](#docker-mkinitcpio-issues)
    * [autodetect](#autodetect)
    * [arch-chroot](#arch-chroot)
* [GRUB2 bootloader](#grub2-bootloader)
  * [GRUB structure](#grub-structure)
  * [GFXMenu module](#gfxmenu-module)
  * [incompatible license](#incompatible-license)
  * [grub-mkimage](#grub-mkimage)
  * [xorriso](#xorriso)
    * [mkarchiso](#mkarchiso)
    * [EFI only ISO](#efi-only-iso)
* [Bash pro tips](#bash-pro-tips)
  * [heredoc](#heredoc)
* [Contribute](#contribute)
  * [Git-Hook](#git-hook)
* [License](#license)
  * [Contribution](#contribution)
* [Backlog](#backlog)
* [Changelog](#changelog)

---

# Usage <a name="usage"/></a>

## Prerequisites <a name="prerequisites"/></a>
The mutli-boot ISO is build entirely in a docker container with data cached on the local host for
quicker rebuilds. This makes it possible to build on systmes with a minimal amount of dependencies.
All that is required is ***passwordless sudo*** and ***docker***.

### Arch Linux <a name="arch-linux"/></a>
1. Passwordless sudo access is required for automation:
   ```bash
   $ sudo bash -c "echo '$USER ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/10-passwordless"
   ```
2. Install dependencies:
   ```bash
   $ sudo pacman -S jq docker virtualbox virtualbox-host-modules-arch
   $ sudo usermod -aG disk,docker,vboxusers $USER

   $ sudo systemctl enable docker
   $ sudo systemctl start docker
   ```
3. Add your user to the appropriate groups:
   ```bash
   $ sudo apt install jq
   ```

### Ubuntu <a name="ubuntu"/></a>
1. Passwordless sudo access is required for automation:
   ```bash
   $ sudo bash -c "echo 'YOUR_USER ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/10-passwordless"
   ```
2. Install dependencies:
   ```bash
   $ sudo apt update
   $ sudo apt install jq docker
   ```
3. Add your user to the appropriate groups:
   ```bash
   $ sudo usermod -aG disk,docker,vboxusers $USER
   ```

## Create multiboot USB <a name="create-multiboot-usb"/></a>

1. Clone the multiboot repo:
   ```bash
   $ cd ~/Projects
   $ git clone git@github.com:phR0ze/cyberlinux-multiboot
   ```

2. Execute the build:
   ```bash
   $ ./build.sh -a
   ```

3. Copy the ISO to the USB:
   ```bash
   # Determine the correct USB device
   $ lsblk

   # Copy to the dev leaving off the partition
   $ sudo cp temp/output/cyberlinux.iso /dev/sdd
   ```

### Test USB in VirtualBox <a name="test-usb-in-virtualbox"/></a>
1. Determine which device is your USB
   ```bash
   $ lsblk
   ```
2. Create a raw vmdk boot stub from the USB
   ```
   $ sudo vboxmanage internalcommands createrawvmdk -filename usb.vmdk -rawdisk /dev/sdd
   RAW host disk access VMDK file usb.vmdk created successfully.

   # Change ownership of new image to your user
   $ sudo chown $USER: usb.vmdk

   # Add your user to the disk group
   $ sudo usermod -a -G disk $USER

   # Logout and back in and launch virtualbox
   ```
3. Create a new VM in VirtualBox  
   a. On the `Virtual Hard Disk` option choose `Use existing hard disk`  
   b. Browse to and select the `usb.vmdk` you just created  

# Configuration <a name="configuration"/></a>
## dconf <a name="dconf"/></a>
To get setting persisted from dconf configure the target app as desired then dump the settings out
and save them in the dconf load location.

Dump out the target app setttings to the load area
```bash
$ dconf dump /apps/guake/ > /etc/dconf/db/local.d/03-guake
```

# Hardware <a name="hardware"/></a>

## ACEPC AK1 <a name="acepc-ak1"/></a>
1. Boot Into the `BIOS`:  
   a. Press `F7` repeatedly until the boot menu pops up  
   b. Select `Enter Setup`  
   c. Navigate to `Security >Secure Boot`  
   d. Ensure it is `Disabled`

1. Boot the AK1 form the USB:  
   a. Plug in the USB from [Create multiboot USB](#create-multiboot-usb)  
   b. Press `F7` repeatedly until the boot menu pops up  
   c. Select your device e.g. `KingstonDataTravelor 2.01.00`  
   d. 

2. Boot while pressing ``

## Dell XPS 13 9310 <a name="dell-xps-13-9310"/></a>

References:
* 

### Ubuntu install <a name="ubuntu-install"/></a>
* kernel: 5.6.0-1039-oem
* CPU: 11th Gen Intel Core i7-1185G7@3.00GHz
* RAM: 16GB
* SSD: NVMe 256GB

### UEFI Secure Boot <a name="uefi-secure-boot"/></a>
You need to disable UEFI secure boot in order to install cyberlinux as only the Ubuntu factory
firmware that comes with the machine will be cryptographically signed for the machine.

1. Hit `F2` while booting
2. In the left hand navigation select `Boot Configuration`
3. On the right side scroll down to `Secure Boot`
4. Flip the toggle on `Enable Secure Boot` to `OFF`
5. Select `Yes` on the Secure Boot disable confirmation
6. Select `APPLY CHANGES` at the bottom
7. Select `OK` on the Apply Settings Confirmation page
8. Select `EXIT` bottom right of the screen to reboot

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

# Docker <a name="docker"/></a>
While building the various components required for the multiboot ISO and constructing the various
deployment flavors a number of system specific commands are run. The only way I've found to safely
reproduce the desired results regardless to the host systems state is to build components in
containers.

References:
* [Go Formatting](https://docs.docker.com/config/formatting)

## Basics <a name="basics"/></a>

### Shell into a running container <a name="shell-into-a-running-container"/></a>
```bash
$ docker exec -it builder bash
```

### Create image from directory <a name="create-image-from-directory"/></a>
```bash
$ sudo tar -c . | docker import - builder
```

### Check if image exists <a name="check-if-image-exists"/></a>
List out all info available in json then use jq to work with it
```bash
$ docker container ls --format='{{json .}}' | jq
```

## Caching packages <a name="caching-packages"/></a>
Docker has a limitation that it can't mount a volume during build and we'd really like to cache
package downloading so we're not constantly downloading the same packages over and over again. Its
slow and annoying. To avoid this we can use the off the shelf image `archlinux:base-devel` with a
mounted volume to download them and store them for us using the same lates image version that we'll
be using to build with thus avoiding host dependencies.

Arch Linux uses the `/var/cache/pacman/pkg` location as its package cache and provides a nifty
download only option `-w` that will allow us to download the target packages to the cache.

```bash
$ docker run --name builder --rm -it -v "${pwd}/temp/cache":/var/cache/pacman/pkg archlinux:base-devel bash
$ pacman -Syw --noconfirm grub
```

# mkinitcpio <a name="mkinitcpio"/></a>

## mkinitcpio-vt-colors <a name="mkinitcpio-vt-colors"/></a>
The color of the kernel messages that are output during boot time can be controlled with a mkinitcpio
hook for color configuration.

1. Install `mkinitcpio-vt-colors`
2. Update `/etc/mkinitcpio.conf` to include the `vt-colors` hook
3. Rebuild the initramfs early boot image

## docker mkinitcpio issues <a name="docker-mkinitcpio-issues"/></a>
The intent is to be able to build a full multiboot ISO with only the minimal dependencies so its easy
to reproduce the ISO on any arch linux based system or virtual machine. After some initial research
it became obvious the easiest route was going to be using containers.

`arch-chroot` and `mount` etc.. require teh `--privileged=true` option to work correctly with docker.

### autodetect <a name="autodetect"/></a>
`mkinitcpio` when running in a docker container will `autodetect` that the docker overlay system
being used and try to add it as a module. To solve this you need to:

Edit the `/etc/mkinitcpio.conf` and remove the `autodetect` option

### arch-chroot <a name="arch-chroot"/></a>
Originally I tried to use `arch-chroot` only for isolation but ran into odd issues when the kernel
didn't match the host kernel. Obviously the jail was leaking.

Example:
```
[root@main4 /]# ls -la /lib/modules
total 36
drwxr-xr-x  3 root root  4096 Jul 30 03:29 .
drwxr-xr-x 47 root root 24576 Jul 30 03:29 ..
drwxr-xr-x  3 root root  4096 Jul 30 03:29 5.13.6-arch1-1
[root@main4 /]# mkinitcpio -g /root/installer
==> ERROR: '/lib/modules/5.12.15-arch1-1' is not a valid kernel module directory
[root@main4 /]# exit
exit
```

# GRUB2 bootloader <a name="grub2-bootloader"/></a>
[GRUB2](https://www.gnu.org/software/grub) offers the ability to easily create a bootable USB drive
for both BIOS and UEFI systems as well as a customizable menu for arbitrary payloads. This
combination is ideal for a customizable initramfs based installer. Using GRUB2 we can boot on any
system with a custom splash screen and menus and then launch our initramfs installer which will
contain the tooling necessary to install the system. After which the initramfs installer will reboot
the system into the newly installed OS.

**References**:
* [GRUB lower level](http://www.dolda2000.com/~fredrik/doc/grub2)
* [GRUB Documentation](https://www.gnu.org/software/grub/manual/grub/html_node/index.html)
* [GRUB Developers Manual](https://www.gnu.org/software/grub/manual/grub-dev/html_node/index.html)
* [GFXMenu Components](https://www.gnu.org/software/grub/manual/grub-dev/html_node/GUI-Components.html#GUI-Components)

## GRUB structure <a name="grub-structure"/></a>
GRUB is composed of a `kernel` which contains the fundamental features from memory allocation to
basic commands the module loader and a simplistic rescue shell. The `modules` can be loaded by the
kernel to add functionality such as additional commands or support for various filesystems. The `core`
image which is constructed via `grub-mkimage` consists of the `kernel` the `specified modules` the
`prefix string` put together in a platform specific format.

Once GRUB is running the first thing it will do is try to load modules from the `prefix string`
location post fixed with the architecture e.g. `/boot/grub/x86_64-efi`. The modules included in the
core image are just enough to be able to load additional modules from the real filesystem usually
bios and filesystem modules.

## GFXMenu module <a name="gfxmenu-module"/></a>
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

## incompatible license <a name="incompatible-license"/></a>
If you get an ugly GRUB license error as follows upon boot you'll need to re-examine the GRUB modules
you've included on your EFI boot.
```
GRUB loading...
Welcome to GRUB!

incompatible license
Aborted. Press any key to exit.
```
During boot `GRUB` will check for licenses embedded in the EFI boot modules. You can test ahead of
time to see of any are flagged. Acceptable licenses are `GPLv2+`, `GPLv3` and `GPLv3+`.

Following the instructions in [Test USB in VirtualBox](#test-usb-in-virtualbox) I was able to
determine that the problem existed in VirtualBox as well so its not unique to the target machine I
was attempting to test my USB on. This means that either:

* A non-compliant licensed module being included could cause this
  * Looking through all modules wih `for x in *.mod; do strings $x | grep LICENS; done` revealed
  everything is kosher.
* GRUB doesn't have a stable binary ABI so mixing modules versions could cause this
  * Ensuring that all modules were removed before recreating didn't help
* Copying the ISO to the USB incorrectly may cause this
  * Validated the same process with the Arch Linux ISO and it works 
* The construction of the GRUB boot images isn't accurate
* The construction of the ISO isn't accurate
* Actual ISO creation with xorriso might be suspect

## grub-mkimage <a name="grub-mkimage"/></a>
***grub-mkimage*** is the key to building GRUB bootable systems. All of GRUB's higher level utilities
like `grub-[install,mkstandalone,mkresuce]` all use `grub-mkimage` to do their work.

Resources:
* [GRUB on ISO](https://sites.google.com/site/grubefikiss/grub-on-iso-image)

Essential Options:
* `-c, --config=FILE` is only required if your not using the default `/boot/grub/grub.cfg`
* `-O, --format=FORMAT` calls out the platform format e.g. `i386-pc` or `x86_64-efi`
* `-o DESTINATION` output destination for the core image being built e.g. `/efi/boot/bootx64.efi`
* `-d MODULES_PATH` location to modules during construction defaults to `/usr/lib/grub/<platform>`
* `-p /boot/grub` directory to find grub once booted i.e. prefix directory
* `space delimeted modules` list of modules to embedded in the core image
  * `i386-pc` minimal are `biosdisk part_msdos fat`

## grub-mkresuce <a name="grub-mkrescue"/></a>

## xorriso <a name="xorriso"/></a>
`genisoimage` is an outdated buggy fork of `mkisofs`. `xorriso` is a more feature rich and
stable utility that also has a `-as mkisofs` compatible mode.

Options:
* `-as mkisofs` puts it in mkisofs mode to support options like grub-mkrescue does
  * `-V volid` specifies the volume id xorriso's version is `-volid volid`
* `-volid volid` xorriso's direct option rather than the mkisofs compatible optiona `-V`

### mkarchiso <a name="mkarchiso"/></a>
Examining the archiso construction process:
1. Install the bits: `sudo pacman -S archiso`
2. View the source: `sudo vim /usb/bin/mkarchiso`

```bash
$ xorriso -as mkisofs \
   -iso-level 3 \
   -full-iso9660-filenames \
   -volid "${iso_label}" \
   -eltorito-boot isolinux/isolinux.bin \
   -eltorito-catalog isolinux/boot.cat \
   -no-emul-boot -boot-load-size 4 -boot-info-table \
   -isohybrid-mbr ~/customiso/isolinux/isohdpfx.bin \
   -output arch-custom.iso \
   ~/customiso
```

```bash
$ sudo mkdir /mnt/iso
$ sudo mount ~/Downloads/archlinux-2021.08.01-x86_64.iso /mnt/iso
```

### EFI only ISO <a name="efi-only-iso"/></a>
Useful for testing

```bash
$ xorriso -as mkisofs \
    -V 'deb10.5.0 preseed amd64 efi' \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -o $ISO_NEW $DIR_EXTRACT
```

# Bash pro tips <a name="bash-pro-tips"/></a>

## heredoc <a name="heredoc"/></a>

### Save heredoc into variable <a name="save-here-doc-into-variable"/></a>
Changing `EOF` to `'EOF'` ignores variable expansion

```bash
local DOC=$(cat << 'EOF'
[cyberlinux]
SigLevel = Optional TrustAll
Server = https://phr0ze.github.io/cyberlinux-repo/$repo/$arch
EOF
)
```

---

# Contribute <a name="Contribute"/></a>
Pull requests are always welcome. However understand that they will be evaluated purely on whether
or not the change fits with my goals/ideals for the project.

## Git-Hook <a name="git-hook"/></a>
Enable the git hooks to have automatic version increments
```bash
cd ~/Projects/cyberlinux-multiboot
git config core.hooksPath .githooks
```

# License <a name="license"/></a>
This project is licensed under either of:
 * MIT license [LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT
 * Apache License, Version 2.0 [LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0

### Contribution <a name="contribution"/></a>
Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in
this project by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without
any additional terms or conditions.

---

# Backlog <a name="backlog"/></a>
* Migrate to nvim

* Personal packages: Wallpaper
* Add GTK Arc Dark theme
* Add utshushi menu entry
* devede and asunder icons in Paper are both the same?
* Switch to XFWM because openbox doesn't have nice window edge control
* Add gtk2fontsel to menu in lite
* clu - cyberlinux automation
  * replace conky scripts, cal.rb, date.rb and radio.rb
  * build in skel copy for updates
* Add cyberlinux-repo README about packages and warnings and how to configure
  * Automate updates to the readme when updating the packages
* Build a rust replacement for oblogout

# Changelog <a name="changelog"/></a>
* Replaced cinnamon-screensaver with i3lock-color
* Replaced oblogout with arcologout a simple clean overlay logout app
* Powerline font doesn't look right in bash - solved set fontconfig
* Fixed keyboard repeat rate with lxsession config
* Install yay from blackarch into the shell deployment
* Set standard language defaults: `LANG = "en_US.UTF-8"`
* Passwords need to be SHA512 to avoid being flagged by pam policies
