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
  * [GRUB2 configuration](#grub2-configuration)
  * [GFXMenu module](#gfxmenu-module)
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

## Install prerequisites <a name="install-prerequisites"/></a>
1. Install dependencies for building boot images:
   ```bash
   $ sudo pacman -S arch-install-scripts grub mtools libisoburn pacman-contrib mkinitcpio sudo \
     util-linux pacutils jq sed docker tar
   ```
2. Install dependencies for testing boot images:
   ```bash
   $ sudo pacman -S virtualbox virtualbox-host-modules-arch
   $ sudo usermod -aG vboxusers USER
   $ sudo reboot
   ```
3. Ensure user has passwordless sudo access  
   a. Edit `/etc/sudoers`  
   b. Append for your user: `YOUR_USER ALL=(ALL) NOPASSWD: ALL`  

4. Clone the profiles repo at the same level as the multiboot repo:
   ```bash
   $ cd ~/Projects
   $ git clone git@github.com:phR0ze/cyberlinux-multiboot
   $ git clone git@github.com:phR0ze/cyberlinux-profiles
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
* lxterminal sessions to be full screen if small display
* Audacious is missing its icon in the menu
* Keyboard repeat rate, .xprofile and lxsession don't work
* Configure openbox menu
* Powerline font doesn't look right in bash
* Build a rust replacement for oblogout
* Switch over to neovim
* Build out custom LXDM greeter theme for cyberlinux

# Changelog <a name="changelog"/></a>
* XDG home directories need adjusting
* Install yay from blackarch into the shell deployment
* Configure lxdm splash image
* Setup repo versioning
* Build out the lite deployment
* Set standard language defaults: `LANG = "en_US.UTF-8"`
* Build out the shell deployment
* Sort blackarch mirrors according to speed
* Add pacman support to base
* Enable sshd out of the box
* Add skel configs to root user
* Get basic networking working
* Don't require new users to immediately change their passwords
* Test UEFI install with custom steps
* Test UEFI automated install
* mkinitcpio-vt-colors is not taking affect on boot
* Test BIOS install with custom steps
* Containerize the builder
* Compress layers into squashfs images 
* Build bootable USB with custom menus
