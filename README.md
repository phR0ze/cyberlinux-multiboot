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
    * [Install cyberlinux](#acepc-ak1-install-cyberlinux)
    * [Configure cyberlinux](#acepc-ak1-configure-cyberlinux)
  * [Dell XPS 13 9310](#dell-xps-13-9310)
    * [Install cyberlinux](#dell-xps-13-install-cyberlinux)
    * [Configure cyberlinux](#dell-xps-13-configure-cyberlinux)
  * [Samsung Chromebook 3 (a.k.a CELES)](#chromebook-3)
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
* [Boot Loaders](#boot-loaders)
  * [BIOS Firmware](#bios-firmware)
  * [UEFI Firmware](#uefi-firmware)
  * [Clover](#clover)
    * [Install Clover (USB)](#install-clover-usb)
    * [Install Clover (SSD)](#install-clover-ssd)
  * [rEFInd](#rEFInd)
    * [rEFInd vs GRUB2](#rEFInd-vs-grub2)
  * [GRUB2](#grub2)
    * [GRUB structure](#grub-structure)
    * [grub-mkimage](#grub-mkimage)
    * [GFXMenu module](#gfxmenu-module)
    * [Trouble-shooting](#trouble-shooting)
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
   $ sudo dd bs=32M if=temp/output/cyberlinux.iso of=/dev/sdd status=progress oflag=sync
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
Note because of the `xHCI` USB driver being used by the newer firmware on the ACEPC AK1 you must
choose an `UEFI` boot option in order to get keyboard support during the install.

### Install cyberlinux <a name="acepc-ak1-install-cyberlinux"/></a>
1. Boot Into the `Setup firmware`:  
   a. Press `F7` repeatedly until the boot menu pops up  
   b. Select `Enter Setup`  
   c. Navigate to `Security >Secure Boot`  
   d. Ensure it is `Disabled`

2. Now boot the AK1 from the USB:  
   a. Plug in the USB from [Create multiboot USB](#create-multiboot-usb)  
   b. Press `F7` repeatedly until the boot menu pops up  
   c. Select your `UEFI` device entry e.g. `UEFI: USB Flash Disk 1.00`  

3. Install `cyberlinux`:  
   a. Select the desired deployment type e.g. `Desktop`  
   b. Walk through the wizard enabling WiFi on the way  
   c. Complete out the process and login to your new system  
   d. Unplug the USB, reboot and log back in  

### Configure cyberlinux <a name="acepc-ak1-configure-cyberlinux"/></a>
1. Configure WiFi:  
   a. WPA GUI will be launched automatically  
   b. Select `Scan >Scan` then doblue click the chosen `SSID`  
   c. Enter the pre-shared secret `PSK` and click `Add`  
   d. You should have an ip now you can verify with `ip a` in a shell  
   e. Set a static ip if desired, edit `sudo /etc/systemd/network/30-wireless.network`  
      ```
      [Match]
      Name=wl*

      [Network]
      Address=192.168.1.7/24
      Gateway=192.168.1.1
      DNS=1.1.1.1
      DNS=1.0.0.1
      IPForward=kernel
      ```
   f. Restart networking:  
      ```bash
      $ sudo systemctl restart systemd-networkd
      ```

2. Configure Teamviewer if installed:  
   a. Launch Teamviewer from the tray icon  
   b. Navigate to `Extras >Options`  
   c. Set `Choose a theme` to `Dark` and hit `Apply`  
   d. Navigate to `Advanced` and set `Personal password` and hit `OK`  

3. Configure Kodi if desired:  
   a. Hover over selecting `Remove this main menu item` for those not used `Muic Videos, TV, Radio,
   Games, Favourites`  
   b. Add NFS shares as desired  
   c. Navigate to `Movies > Enter files selection > Files >Add videos...`  
   d. Select `Browse >Add network location...`  
   e. Select `Protocol` as `Network File System (NFS)`  
   f. Set `Server address` to your target e.g. `192.168.1.3`  
   g. Set `Remote path` to your server path e.g. `srv/nfs/Movies`  
   h. Select your new NFS location in the list and select `OK`  
   i. Select `OK` then set `This directory contains` to `Movies`  
   j. Set `Choose information provider` and set `Local information only`  
   k. Set `Movies are in separate folders that match the movie title` and select `OK`  
   l. Repeat for any other NFS share paths your server has  

4. Copy over ssh keys to `~/.ssh`  

5. Copy over any wallpaper to `/usr/share/backgrounds`  

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

## Samsung Chromebook 3 (a.k.a. CELES) <a name="samsung-chromebook-3"/></a>
With earlier kernel versions and drivers there were some quirks to work out but the latest `5.13.13`
and associated Arch Linux packages seem to work pretty smooth.

### Prerequisites <a name="chromebook-3-prerequisites"/></a>
Chromebooks are not setup for Linux out of the box however there has been some excellent work done
in the community to make Chromebooks behave like normal Linux netbooks.

see [Prepare you system for install](https://wiki.galliumos.org/Installing/Preparing)

### Install cyberlinux <a name="chromebook-3-install-cyberlinux"/></a>
1. Boot Into the `Setup firmware`:  
   a. Press `F7` repeatedly until the boot menu pops up  
   b. Select `Enter Setup`  
   c. Navigate to `Security >Secure Boot`  
   d. Ensure it is `Disabled`

2. Now boot the AK1 from the USB:  
   a. Plug in the USB from [Create multiboot USB](#create-multiboot-usb)  
   b. Press `F7` repeatedly until the boot menu pops up  
   c. Select your `UEFI` device entry e.g. `UEFI: USB Flash Disk 1.00`  

3. Install `cyberlinux`:  
   a. Select the desired deployment type e.g. `Desktop`  
   b. Walk through the wizard enabling WiFi on the way  
   c. Complete out the process and login to your new system  
   d. Unplug the USB, reboot and log back in  

### Configure cyberlinux <a name="chromebook-3-configure-cyberlinux"/></a>
1. Configure WiFi:  
   a. WPA GUI will be launched automatically  
   b. Select `Scan >Scan` then doblue click the chosen `SSID`  
   c. Enter the pre-shared secret `PSK` and click `Add`  
   d. You should have an ip now you can verify with `ip a` in a shell  
   e. Set a static ip if desired, edit `sudo /etc/systemd/network/30-wireless.network`  
      ```
      [Match]
      Name=wl*

      [Network]
      Address=192.168.1.7/24
      Gateway=192.168.1.1
      DNS=1.1.1.1
      DNS=1.0.0.1
      IPForward=kernel
      ```
   f. Restart networking:  
      ```bash
      $ sudo systemctl restart systemd-networkd
      ```

2. Configure Teamviewer if installed:  
   a. Launch Teamviewer from the tray icon  
   b. Navigate to `Extras >Options`  
   c. Set `Choose a theme` to `Dark` and hit `Apply`  
   d. Navigate to `Advanced` and set `Personal password` and hit `OK`  

3. Configure Kodi if desired:  
   a. Hover over selecting `Remove this main menu item` for those not used `Muic Videos, TV, Radio,
   Games, Favourites`  
   b. Add NFS shares as desired  
   c. Navigate to `Movies > Enter files selection > Files >Add videos...`  
   d. Select `Browse >Add network location...`  
   e. Select `Protocol` as `Network File System (NFS)`  
   f. Set `Server address` to your target e.g. `192.168.1.3`  
   g. Set `Remote path` to your server path e.g. `srv/nfs/Movies`  
   h. Select your new NFS location in the list and select `OK`  
   i. Select `OK` then set `This directory contains` to `Movies`  
   j. Set `Choose information provider` and set `Local information only`  
   k. Set `Movies are in separate folders that match the movie title` and select `OK`  
   l. Repeat for any other NFS share paths your server has  

4. Copy over ssh keys to `~/.ssh`  

5. Copy over any wallpaper to `/usr/share/backgrounds`  

### MicroSD Storage <a name="chromebook-3-micro-sd-storage"/></a>
The MicroSD card is recognized as ***/dev/mmcblk1*** and not as removable device. This would be a
problem if I intended to be inserting/removing it a lot, however I intend to simply use it as
personal data storage for things such as Documents and media separate from the main disk. This will
allow the main disk to be wiped and reinstalled as often as needed while keeping all non-system
i.e. personal data separate and protected during system re-installs/formats.

Prepare SD card for use and persistently mount:

1. List out devices
   ```bash
   $ lsblk
   ```
2. Format using `-m 0` to use all space as this is a storage disk
   ```bash
   $ sudo mkfs.ext4 -m 0 /dev/mmcblk1
   ```

3. Mount using `noatime` to improve performance
   ```bash
   sudo mkdir /mnt/storage
   sudo tee -a /etc/fstab <<< "/dev/mmcblk1 /mnt/storage ext4 defaults,noatime 0 0"
   sudo mount -a
   sudo chown -R $USER: /mnt/storage
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

# Boot Loaders <a name="boot-loaders"/></a>
UEFI devices now have alternative options for boot loaders that provide options for image display,
custom fonts, and menus either on par or more advanced than the venerable GRUB2's GFXMenu in
functionality. It might be time to find a new boot loader.

**References**:
* [Arch Linux Early User space](http://archlinux.me/brain0/2010/02/13/early-userspace-in-arch-linux/)

## BIOS Firmware <a name="bios-firmware"/></a>
BIOS was developed in the 1970s and was prevelant till the late 2000s when it began to be gradually
replaced by EFI. BIOS provides a basic text-based interface.

### BIOS boot process <a name="bios-boot-process"/></a>
BIOS looks at the first segment of the drive to find the bootloader. Traditionally this was a `MBR`
partitioning sceme; however `GPT` partitioning part of the `EFI` spec can be used instead if done
correctly. In order to accomplish this you need to create a `GPT protective MBR`. The only caveat is
the boot loader needs to be GPT aware which pretty much all Linux compatible bootloaders are. Instead
of injecting the boot loader into the MBR space in the first partition you need to create a new `BIOS
Boot Partition` code `EF02`.

By leveraging the `GPT BIOS Boot Partition EF02` on a BIOS system and instead a normal `ESP EF02`
boot partition on UEFI systems we create a configuration that is bootable by modern EFI bootloaders
like Clover in either case. This means we can create a single Clover custom UI that will boot and be
used on either BIOS or UEFI.

## UEFI Firmware <a name="uefi-firmware"/></a>
From about 2010 on all computers have been using UEFI as their firmware to interface with the mother
board rather than thd old BIOS firmware. 

Note: `UEFI` is essentially `EFI 2.0`

Most EFI boot loaders and boot managers reside in their own subdirectories inside the `EFI` directory
on the `EFI System Partition (ESP)` e.g. `/dev/sda1` mounted at `/boot` thus
`/boot/efi/<bootloader>`.

### EFI boot process <a name="efi-boot-process"/></a>
UEFI firmware identifies the `ESP` (i.e. partition with code `ef00` formatted as `FAT32`) and loads
the binary target at `/efi/boot/bootx86.efi` which can be either a boot manager or bootloader. Either
way the binary target then loads the target kernel or target bootloader which loads the target
kernel.

## Clover <a name="clover"/></a>
Clover EFI is a boot loader developed to boot OSX, Windows and Linux in legacy or UEFI mode.

**References**:
* [Arch Linux - Clover](https://wiki.archlinux.org/title/Clover)

**Features**:
* Emulate UEFI on legacy BIOS systems which allows you to boot into EFI mode from legacy mode so you
can share the same `efi` files and UI
* Support native resolution GUI with icons, fonts and other UI elements with mouse support
* Easy to use and customize

### Install Clover (USB) <a name="install-clover-usb"/></a>
1. Install the clover pacakge
   ```bash
   $ sudo pacman -S clover
   ```
2. Copy the install files to the boot location
   ```bash
   $ cp -r /usr/lib/clover/EFI/BOOT iso/EFI
   $ cp -r /usr/lib/clover/EFI/CLOVER iso/EFI
   ```
3. Building the ISO
   ```bash
   xorriso \
    \
    `# Configure general settings` \
    -as mkisofs                                     `# Use -as mkisofs to support options like grub-mkrescue does` \
    -volid CYBERLINUX_INSTALLER                     `# Identifier installer uses to find the install drive` \
    --modification-date=$(date -u +%Y%m%d%H%M%S00)  `# Date created YYYYMMDDHHmmsscc e.g. 2021071223322500` \
    -r -iso-level 3 -full-iso9660-filenames         `# Use Rock Ridge and level 3 for standard ISO features` \
    \
    `# Configure BIOS bootable settings` \
    -b boot/grub/i386-pc/eltorito.img               `# El Torito boot image enables BIOS boot` \
    -no-emul-boot                                   `# Image is not emulating floppy mode` \
    -boot-load-size 4                               `# Specifies (4) 512byte blocks: 2048 total` \
    -boot-info-table                                `# Updates boot image with boot info table` \
    \
    `# Configure UEFI bootable settings` \
    -eltorito-alt-boot                              `# Separates BIOS settings from UEFI settings` \
    -e boot/grub/efi.img                            `# EFI boot image on the iso post creation` \
    -no-emul-boot                                   `# Image is not emulating floppy mode` \
    -isohybrid-gpt-basdat                           `# Announces efi.img is FAT GPT i.e. ESP` \
    \
    `# Specify the output iso file path and location to turn into an ISO` \
    -o "${CONT_OUTPUT_DIR}/cyberlinux.iso" "$CONT_ISO_DIR"
   ```

### Install Clover (SSD) <a name="install-clover-ssd"/></a>

## rEFInd <a name="rEFInd"/></a>
`rEFInd themes` are quite intriguing providing custom icons, images, fonts and menus that surpass
what GRUB2 offers.

References:
* [The rEFInd Boot Manager](https://www.rodsbooks.com/refind/)
* [Theming rEFInd](https://www.rodsbooks.com/refind/themes.html)
* [rEFInd vs GRUB](https://askubuntu.com/questions/760875/any-downside-to-using-refind-instead-of-grub)

### rEFInd vs GRUB2 <a name="refind-vs-grub2"/></a>
* rEFInd features
  * scans for kernels on every boot making it more adaptive and less reliant on config files.
  * configuration files are simpler and is easier to tweak
  * has `more eye candy`
  * can boot from CD or USB stick
  * has an arch linux package
* rEFInd downsides
  * has a single developer
  * doesn't support as many platforms as GRUB
  * getting `Shim` to work with rEFInd is harder

## GRUB2 <a name="grub2"/></a>
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

### GRUB structure <a name="grub-structure"/></a>
GRUB is composed of a `kernel` which contains the fundamental features from memory allocation to
basic commands the module loader and a simplistic rescue shell. The `modules` can be loaded by the
kernel to add functionality such as additional commands or support for various filesystems. The `core`
image which is constructed via `grub-mkimage` consists of the `kernel` the `specified modules` the
`prefix string` put together in a platform specific format.

Once GRUB is running the first thing it will do is try to load modules from the `prefix string`
location post fixed with the architecture e.g. `/boot/grub/x86_64-efi`. The modules included in the
core image are just enough to be able to load additional modules from the real filesystem usually
bios and filesystem modules.

### grub-mkimage <a name="grub-mkimage"/></a>
***grub-mkimage*** is the key to building GRUB bootable systems. All of GRUB's higher level utilities
like `grub-[install,mkstandalone,mkresuce]` all use `grub-mkimage` to do their work.

Resources:
* [GRUB on ISO](https://sites.google.com/site/grubefikiss/grub-on-iso-image)
* [GRUB image descriptions](https://www.gnu.org/software/grub/manual/grub/html_node/Images.html)
* [grub-mkstandalone](https://willhaley.com/blog/custom-debian-live-environment-grub-only/#create-bootable-isocd)
* [GRUB2 bootable ISO with xorriso](http://lukeluo.blogspot.com/2013/06/grub-how-to-2-make-boot-able-iso-with.html)

Essential Options:
* `-c, --config=FILE` is only required if your not using the default `/boot/grub/grub.cfg`
* `-O, --format=FORMAT` calls out the platform format e.g. `i386-pc` or `x86_64-efi`
* `-o DESTINATION` output destination for the core image being built e.g. `/efi/boot/bootx64.efi`
* `-d MODULES_PATH` location to modules during construction defaults to `/usr/lib/grub/<platform>`
* `-p /boot/grub` directory to find grub once booted i.e. prefix directory
* `space delimeted modules` list of modules to embedded in the core image
  * `i386-pc` minimal are `biosdisk part_msdos fat`

#### BIOS grub-mkimage <a name="bios-grub-mkimage"/></a>
```bash
local shared_modules="iso9660 part_gpt ext2"

# Stage the grub modules
# GRUB doesn't have a stable binary ABI so modules from one version can't be used with another one
# and will cause failures so we need to remove then all in advance
cp -r /usr/lib/grub/i386-pc iso/boot/grub
rm -f iso/boot/grub/i386-pc/*.img

# We need to create our core image i.e bios.img that contains just enough code to find the grub
# configuration and grub modules in /boot/grub/i386-pc directory
# -p /boot/grub                 Directory to find grub once booted, default is /boot/grub
# -c /boot/grub/grub.cfg        Location of the config to use, default is /boot/grub/grub.cfg
# -d /usr/lib/grub/i386-pc      Use resources from this location when building the boot image
# -o temp/bios.img              Output destination
grub-mkimage --format i386-pc -d /usr/lib/grub/i386-pc -p /boot/grub \
  -o temp/bios.img biosdisk ${shared_modules}

echo -e ":: Concatenate cdboot.img to bios.img to create CD-ROM bootable eltorito.img..."
cat /usr/lib/grub/i386-pc/cdboot.img temp/bios.img" > iso/boot/grub/i386-pc/eltorito.img
```

#### UEFI grub-mkimage <a name="uefi-grub-mkimage"/></a>
The key to making a bootable UEFI USB is to embedded the grub `BOOTX64.EFI` boot image inside an
official `ESP`, i.e. FAT32 formatted file, at `/EFI/BOOT/BOOTX64.EFI` then pass the resulting
`efi.img` to xorriso using the `-isohybrid-gpt-basdat` flag.

Resources:
* [UEFI only bootable USB](https://askubuntu.com/questions/1110651/how-to-produce-an-iso-image-that-boots-only-on-uefi)

**xorriso UEFI bootable settings**
```bash
-eltorito-alt-boot               `# Separates BIOS settings from UEFI settings` \
-e boot/grub/efi.img             `# EFI boot image on the iso filesystem` \
-no-emul-boot                    `# Image is not emulating floppy mode` \
-isohybrid-gpt-basdat            `# Announces efi.img is FAT GPT i.e. ESP` \
```

**ESP creation including grub-mkimage bootable image**
```bash
mkdir -p iso/EFI/BOOT

# Stage the grub modules
# GRUB doesn't have a stble binary ABI so modules from one version can't be used with another one
# and will cause failures so we need to remove then all in advance
cp -r /usr/lib/grub/x86_64-efi iso/boot/grub
rm -f iso/grub/x86_64-efi/*.img

# We need to create our core image i.e. BOOTx64.EFI that contains just enough code to find the grub
# configuration and grub modules in /boot/grub/x86_64-efi directory.
# -p /boot/grub                   Directory to find grub once booted, default is /boot/grub
# -c /boot/grub/grub.cfg          Location of the config to use, default is /boot/grub/grub.cfg
# -d /usr/lib/grub/x86_64-efi     Use resources from this location when building the boot image
# -o iso/EFI/BOOT/BOOTX64.EFI     Using wellknown EFI location for fallback compatibility
grub-mkimage --format x86_64-efi -d /usr/lib/grub/x86_64-efi -p /boot/grub \
  -o iso/EFI/BOOT/BOOTX64.EFI fat efi_gop efi_uga ${shared_modules}

echo -e ":: Creating ESP with the BOOTX64.EFI binary"
truncate -s 8M iso/boot/grub/efi.img
mkfs.vfat iso/boot/grub/efi.img
mkdir -p temp/esp
sudo mount iso/boot/grub/efi.img temp/esp
sudo mkdir -p temp/esp/EFI/BOOT
sudo cp iso/EFI/BOOT/BOOTX64.EFI temp/esp/EFI/BOOT
sudo umount temp/esp
```

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

### Trouble-shooting <a name="trouble-shooting"/></a>

#### Keyboard not working <a name="keyboard-not-working"/></a>
Booting into the ACEPC AK1 I found that GRUB had no keyboard support. After some research I found
that newer systems use `XHCI` mode for USB which is a combination of USB 1.0, USB 2.0 and USB 3.0 and
is newer. On newer Intel motherboards XHCI is the only option meaning that there is no way to fall
back on EHCI.

**Research:**
* XHCI GRUB module?
  * I see a `uhci.mod ehci.mod usb_keyboard.mod` in `/usr/lib/grub/i386-pc`
  * `uhci.mod` supports USB 1 devices
  * `ehci.mod` supports USB 2 devices
  * `xhci.mod` supports all USB devices including USB 3
* Use Auto rather than Smart Auto or Legacy USB in BIOS
  * Doesn't seem to help

Turns out that GRUB2 doesn't have any plans to support xHCI. After digging into this futher it
appears that the community in the UEFI age is pulling away from GRUB2 as the boot manager of choice.
There are other options out there for newer systems like [rEFInd](#rEFInd)

#### incompatible license <a name="incompatible-license"/></a>
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
  * I dropped it down to the minimal modules, possible this helped but unlikely
* The construction of the ISO isn't accurate
  * I believe the issue was the xorriso properties I had used. After switching back to the original
  xorriso settings from cyberlinux 1.0 I fixed it.

## mkarchiso <a name="mkarchiso"/></a>
The Arch Linux ISO has a primitive 

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

### BlueTooth <a name="bluetooth"/></a>
https://wiki.archlinux.org/index.php/bluetooth

```bash
# Install Bluetooth management tool and pulse audio plugin
sudo pacman -S blueman pulseaudio-bluetooth
# Enable/Start the Bluetooth daemon
sudo systemctl enable bluetooth
sudo systemctl start bluetooth
# Start Blueman
```

* ACEPC
  * Need overscan, white line on right of monitor
  * Vulkan support
    * `sudo pacman -S vulkan-intel vulkan-tools`
    * `vulkaninfo` if you get info about your graphics card its working
* Support profiles depending on each other
* Desktop:
  * Validate: Added wine packages for gaming
  * Conky's settings didn't take for Desktop
  * GTK folder sort settings didn't take
  * Filezilla initial configs not set
* Add conflicts to PKGBUILD

* Migrate to nvim
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

<!-- 
vim: ts=2:sw=2:sts=2
-->
