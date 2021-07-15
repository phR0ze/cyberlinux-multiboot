#!/bin/bash
none="\e[m"
red="\e[1;31m"
cyan="\e[0;36m"

TEMP=temp                             # Temp directory for build artifacts
ISO=${TEMP}/iso                       # Build location for staging iso/boot files
ROOT=${TEMP}/root                     # Root mount point for layered filesystems
BUILD=${TEMP}/build                   # Build location for packages extraction and builds
LAYERS=${TEMP}/layers                 # Layered filesystems to include in the ISO
GRUB=grub                             # Location to pull persisted Grub configuration files from
BOOT_CFG="${ISO}/boot/grub/boot.cfg"  # Boot menu entries to read in

check()
{
  if [ $? -ne 0 ]; then
    echo -e "${red}failed!${none}"
    exit 1
  else
    echo -e "${cyan}success!${none}"
  fi
}

# Provide a failsafe for umounting mount points on exit
RELEASED=0
release()
{
  if [ $RELEASED -ne 1 ]; then
    RELEASED=1
    if mountpoint -q $BUILD; then
      echo -en ":: Releasing mount point ${cyan}${BUILD}${none}..."
      sudo umount -R $BUILD
      check
    fi
  fi
  exit
}
trap release EXIT
trap release SIGINT

# Ensure the current user has passwordless sudo access
if ! sudo -l | grep -q "NOPASSWD: ALL"; then
  echo -e ":: Passwordless sudo access is required see README.md..."
  exit
fi

# Configure build environment
# `coreutils`             provides basic linux tooling
# `pacman`                provides the ability to add additional packages via a chroot to our build env
# `grub`                  is needed by the installer for creating the EFI and BIOS boot partitions
# `sed`                   is used by the installer to update configuration files as needed
# `dosfstoosl`            provides `mkfs.fat` needed by the installer for creating the EFI boot partition
# `mkinitcpio`            provides the tooling to build the initramfs early userspace installer
# `mkinitcpio-vt-colors`  provides terminal coloring at boot time for output messages
# `rsync`                 used by the installer to copy install data to the install target
# `gptfdisk`              used by the installer to prepare target media for install
# `linux`                 need to load the kernel to satisfy GRUB
# `intel-ucode`           standard practice to load the intel-ucode
build_env()
{
  if [ ! -d $BUILD ]; then
    echo -en ":: Configuring build environment..."
    sudo mkdir -p $BUILD
    sudo pacstrap -c -G -M $BUILD coreutils pacman grub sed linux intel-ucode memtest86+ mkinitcpio \
      mkinitcpio-vt-colors dosfstools rsync gptfdisk
  fi
}

# Configure grub theme and build supporting BIOS and EFI boot images required to make
# the ISO bootable as a CD or USB stick on BIOS and UEFI systems with the same presentation.
build_multiboot()
{
  echo -e ":: Building multiboot components..."
  mkdir -p $ISO/boot/grub/themes

  echo -en ":: Copying kernel, intel ucode patch and memtest to ${ISO}/boot..."
  cp $BUILD/boot/intel-ucode.img $ISO/boot
  cp $BUILD/boot/vmlinuz-linux $ISO/boot
  cp $BUILD/boot/memtest86+/memtest.bin $ISO/boot/memtest
  check

  echo -en ":: Copying GRUB config and theme to ${ISO}/boot/grub ..."
  cp $GRUB/grub.cfg $ISO/boot/grub
  cp $GRUB/boot.cfg $ISO/boot/grub
  cp $GRUB/loopback.cfg $ISO/boot/grub
  cp -r $GRUB/themes $ISO/boot/grub
  cp $BUILD/usr/share/grub/unicode.pf2 $ISO/boot/grub
  check

  echo -e ":: Creating ${cyan}${ISO}/boot/grub/boot.cfg${none} ..."
  echo -e "menuentry --class=deployment 'Start cyberlinux live' {" >> ${BOOT_CFG}
  echo -e "  cat /boot/grub/themes/cyberlinux/splash" >> ${BOOT_CFG}
  echo -e "  sleep 5" >> ${BOOT_CFG}
  echo -e "  linux	/boot/vmlinuz-linux kernel=linux layers=shell,lite" >> ${BOOT_CFG}
  echo -e "  initrd	/boot/intel-ucode.img /boot/installer" >> ${BOOT_CFG}
  echo -e "}" >> ${BOOT_CFG}

  echo -en ":: Creating core BIOS $BUILD/bios.img..."
  cp -r $BUILD/usr/lib/grub/i386-pc $ISO/boot/grub
  rm -f $ISO/boot/grub/i386-pc/*.img
  # We need to create our bios.img that contains just enough code to find the grub configuration and
  # grub modules in /boot/grub/i386-pc directory we'll stage in the next step
  # -O i386-pc                        Format of the image to generate
  # -p /boot/grub                     Directory to find grub once booted
  # -d $BUILD/usr/lib/grub/i386-pc    Use resources from this location when building the boot image
  # -o $BUILD/bios.img                Output destination
  grub-mkimage -O i386-pc -p /boot/grub -d $BUILD/usr/lib/grub/i386-pc -o $TEMP/bios.img  \
    biosdisk disk part_msdos part_gpt linux linux16 loopback normal configfile test search search_fs_uuid \
    search_fs_file true iso9660 search_label gfxterm gfxmenu gfxterm_menu ext2 ntfs cat echo ls memdisk tar
  check
  echo -en ":: Concatenate cdboot.img to bios.img to create the CD-ROM bootable Eltorito $TEMP/eltorito.img..."
  cat $BUILD/usr/lib/grub/i386-pc/cdboot.img $TEMP/bios.img > $ISO/boot/grub/i386-pc/eltorito.img
  check
  echo -en ":: Concatenate boot.img to bios.img to create isohybrid $TEMP/isohybrid.img..."
  cat $BUILD/usr/lib/grub/i386-pc/boot.img $TEMP/bios.img > $ISO/boot/grub/i386-pc/isohybrid.img
  check

  echo -en ":: Creating UEFI boot files..."
  mkdir -p $ISO/efi/boot
  cp -r $BUILD/usr/lib/grub/x86_64-efi $ISO/boot/grub
  rm -f $ISO/grub/x86_64-efi/*.img
  # -O x86_64-efi                     Format of the image to generate
  # -p /boot/grub                     Directory to find grub once booted
  # -d $BUILD/usr/lib/grub/x86_64-efi  Use resources from this location when building the boot image
  # -o $ISO/efi/boot/bootx64.efi      Output destination, using wellknown compatibility location
  grub-mkimage -O x86_64-efi -p /boot/grub -d $BUILD/usr/lib/grub/x86_64-efi -o $ISO/efi/boot/bootx64.efi \
    disk part_msdos part_gpt linux linux16 loopback normal configfile test search search_fs_uuid \
    search_fs_file true iso9660 search_label efi_uga efi_gop gfxterm gfxmenu gfxterm_menu ext2 \
    ntfs cat echo ls memdisk tar
  check
}

# Build the initramfs based installer
build_installer() {
  echo -en ":: Build the initramfs based installer..."
  mkdir -p $ISO/boot
  sudo cp installer/installer $BUILD/usr/lib/initcpio/hooks
  sudo cp installer/installer.conf $BUILD/usr/lib/initcpio/install/installer
  sudo cp installer/mkinitcpio.conf $BUILD/etc

  # Mount as bind mount to satisfy arch-chroot requirement
  # umount is handled by the release function on exit
  sudo mount --bind $BUILD $BUILD
  sudo arch-chroot $BUILD mkinitcpio -g /root/installer
  sudo cp $BUILD/root/installer $ISO/boot
  check
}

# Build the ISO
# ISOHYBRID is the format used to create an ISO that is going to be bootable as both a burned CD-ROM
# or as a USB stick or as a raw ISO. Effectively we store a boot loader in the 32K system area that
# will get loaded at boot time. The boot loader i.e. GRUB then presents the user with a configurable
# list of menu options and has the capability to understand ISO9660 file formats to load your target.
#
# Reference: https://lukeluo.blogspot.com/2013/06/grub-how-to-2-make-boot-able-iso-with.html
#
# Use -a mkisofs to support options like grub-mkrescue does
#   -as mkisofs
# Use Rock Ridge and best iso level for standard USB/CDROM compatibility
#   -r -iso-level 3
# Volume identifier used by the installer to find the install drive
#   -volid CYBERLINUX
# Track when the ISO was created in YYYYMMDDHHmmsscc format e.g. 2021071223322500
#   --modification-date=$(date -u +%Y%m%d%H%M%S00)
# Check that all filenames separators are handled correctly
#   -graft-points
# No emulation boot mode
#   -no-emul-boot
# Setup a partition table to block other disk partition tools from manipulating this disk
#   --protective-msdos-label
# El Torito boot image to use to make this iso CD-ROM bootable by BIOS
#   -b /boot/grub/i386-pc/eltorito.img
# Patch an EL TORITO BOOT INFO TABLE into eltorito.img
#   -boot-info-table
# Bootable isohybrid image to make this iso USB stick bootable by BIOS
#   --embedded-boot $TEMP/isohybrid.img
# EFI boot image location on the iso post creation to use to make this iso USB stick bootable by UEFI
# Note the use of the well known compatibility path /efi/boot/bootx64.efi
#   --efi-boot /efi/boot/bootx64.efi 
# Specify the output iso file path and location to turn into an ISO
#   -o boot.iso $ISO
build_iso() {
  echo -e ":: Building an ISOHYBRID bootable image..."
  xorriso -as mkisofs \
    -r -iso-level 3 \
    -volid CYBERLINUX \
    --modification-date=$(date -u +%Y%m%d%H%M%S00) \
    -graft-points \
    -no-emul-boot \
    -boot-info-table \
    --protective-msdos-label \
    -b /boot/grub/i386-pc/eltorito.img \
    --embedded-boot $ISO/boot/grub/i386-pc/isohybrid.img \
    --efi-boot /efi/boot/bootx64.efi \
    -o boot.iso $ISO
}

# Build deployments
build_deployments() 
{
  echo -e ":: Building deployments ${cyan}${1}${none}..."
}

# Main entry point
# -------------------------------------------------------------------------------------------------
header() {
  echo -e "${cyan}CYBERLINUX${none} builder automation for a multiboot installer ISO"
}
usage() {
  header
  echo -e "Usage: ${cyan}./$(basename $0)${none} [options]"
  echo -e "Options:"
  echo -e "-a               Build all buildable options"
  echo -e "-d DEPLOYMENTS   Build deployments, comma delimited (all|shell|lite)"
  echo -e "-i               Build the initramfs installer"
  echo -e "-m               Build the grub multiboot environment"
  echo -e "-c               Clean the build artifacts before building"
  echo -e "-h               Display usage help\n"
  echo -e "Examples:"
  echo -e "Build everything: ./$(basename $0) -a"
  exit 1
}
while getopts ":ad:imch" opt; do
  case $opt in
    c) CLEAN=1;;
    a) ALL=1;;
    i) INSTALLER=1;;
    d) DEPLOYMENTS=$OPTARG;;
    m) MULTIBOOT=1;;
    h) usage;;
    \?) echo -e "Invalid option: ${red}-${OPTARG}${none}\n"; usage;;
    :) echo -e "Option ${red}-${OPTARG}${none} requires an argument\n"; usage;;
  esac
done
[ $(($OPTIND -1)) -eq 0 ] && usage

# Execute build
header
if [ ! -z ${CLEAN+x} ]; then
  echo -e ":: Cleaning build artifacts before building"
  sudo rm -rf $TEMP
fi
mkdir -p $TEMP

# Always build the build environment if any build option is chosen
if [ ! -z ${ALL+x} ] || [ ! -z ${MULTIBOOT+x} ] || [ ! -z ${INSTALLER+x} ] || [ ! -z ${DEPLOYMENTS+x} ]; then
  build_env
fi

# Needs to happen before the multiboot as deployments will be boot entries
if [ ! -z ${ALL+x} ] || [ ! -z ${DEPLOYMENTS+x} ]; then
  build_deployments $DEPLOYMENTS
fi
if [ ! -z ${ALL+x} ] || [ ! -z ${MULTIBOOT+x} ]; then
  build_multiboot
fi
if [ ! -z ${ALL+x} ] || [ ! -z ${INSTALLER+x} ]; then
  build_installer
fi

# vim: ft=sh:ts=2:sw=2:sts=2
