#!/bin/bash
none="\e[m"
red="\e[1;31m"
cyan="\e[0;36m"

TEMP=temp                             # Temp directory for build artifacts
ISO=${TEMP}/iso                       # Build location for staging iso/boot files
ROOT=${TEMP}/root                     # Root for installing packages for extraction
GRUB=grub                             # Location to pull persisted Grub configuration files from
BOOT_CFG="${ISO}/boot/grub/boot.cfg"  # Boot menu entries to read in

check() {
  if [ $? -ne 0 ]; then
    echo -e "${red}failed!${none}"
    exit 1
  else
    echo -e "${cyan}success!${none}"
  fi
}

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
config_build_env() {
  echo -en ":: Configuring build environment..."
  mkdir -p $ISO/boot/grub
  check
  if [ ! -d $ROOT ]; then
    echo -e ":: Installing build environment dependencies..."
    sudo mkdir -p $ROOT
    sudo pacstrap -c -G -M $ROOT coreutils pacman grub sed linux intel-ucode memtest86+ mkinitcpio \
      mkinitcpio-vt-colors dosfstools rsync gptfdisk
  fi

  # Install kernel, intel ucode patch and memtest
  echo -en ":: Copying kernel, intel ucode patch and memtest to ${ISO}/boot..."
  cp $ROOT/boot/intel-ucode.img $ISO/boot
  cp $ROOT/boot/vmlinuz-linux $ISO/boot
  cp $ROOT/boot/memtest86+/memtest.bin $ISO/boot/memtest
  check

  # Install GRUB config and theme
  mkdir -p $ISO/boot/grub/themes
  echo -en ":: Copying GRUB config and theme to ${ISO}/boot/grub ..."
  cp $GRUB/grub.cfg $ISO/boot/grub
  cp $GRUB/boot.cfg $ISO/boot/grub
  cp $GRUB/loopback.cfg $ISO/boot/grub
  cp -r $GRUB/themes $ISO/boot/grub
  cp $ROOT/usr/share/grub/unicode.pf2 $ISO/boot/grub
  check

  # Create the GRUB menu items
  # Pass through options as kernel paramaters
  echo -e ":: Creating ${cyan}${ISO}/boot/grub/boot.cfg${none} ..."
  echo -e "menuentry --class=deployment 'Start cyberlinux recovery' {" >> ${BOOT_CFG}
  echo -e "  cat /boot/grub/themes/cyberlinux/splash" >> ${BOOT_CFG}
  echo -e '  echo -e "\n\n    Transfering control to\n"' >> ${BOOT_CFG}
  echo -e '  echo -e "        CYBERLINUX early boot environment..."' >> ${BOOT_CFG}
  echo -e "  sleep 5" >> ${BOOT_CFG}
  echo -e "  linux	/boot/vmlinuz-linux kernel=linux layers=live,shell,lite" >> ${BOOT_CFG}
  echo -e "  initrd	/boot/intel-ucode.img /boot/installer" >> ${BOOT_CFG}
  echo -e "}" >> ${BOOT_CFG}
}

# Install BIOS boot files
create_bios_boot_images() {
  echo -en ":: Creating core BIOS $ROOT/bios.img..."
  cp -r $ROOT/usr/lib/grub/i386-pc $ISO/boot/grub
  rm -f $ISO/boot/grub/i386-pc/*.img
  # We need to create our bios.img that contains just enough code to find the grub configuration and
  # grub modules in /boot/grub/i386-pc directory we'll stage in the next step
  # -O i386-pc                        Format of the image to generate
  # -p /boot/grub                     Directory to find grub once booted
  # -d $ROOT/usr/lib/grub/i386-pc     Use resources from this location when building the boot image
  # -o $ROOT/bios.img                 Output destination
  grub-mkimage -O i386-pc -p /boot/grub -d $ROOT/usr/lib/grub/i386-pc -o $TEMP/bios.img  \
    biosdisk disk part_msdos part_gpt linux linux16 loopback normal configfile test search search_fs_uuid \
    search_fs_file true iso9660 search_label gfxterm gfxmenu gfxterm_menu ext2 ntfs cat echo ls memdisk tar
  check
  echo -en ":: Concatenate cdboot.img to bios.img to create the CD-ROM bootable Eltorito $TEMP/eltorito.img..."
  cat $ROOT/usr/lib/grub/i386-pc/cdboot.img $TEMP/bios.img > $ISO/boot/grub/i386-pc/eltorito.img
  check
  echo -en ":: Concatenate boot.img to bios.img to create isohybrid $TEMP/isohybrid.img..."
  cat $ROOT/usr/lib/grub/i386-pc/boot.img $TEMP/bios.img > $ISO/boot/grub/i386-pc/isohybrid.img
  check
}

# Install UEFI boot files
# /efi/boot/bootx64.efi is a well known boot file location for compatibility
create_efi_boot_images() {
  echo -en ":: Creating UEFI boot files..."
  mkdir -p $ISO/efi/boot
  cp -r $ROOT/usr/lib/grub/x86_64-efi $ISO/boot/grub
  rm -f $ISO/grub/x86_64-efi/*.img
  # -O x86_64-efi                     Format of the image to generate
  # -p /boot/grub                     Directory to find grub once booted
  # -d $ROOT/usr/lib/grub/x86_64-efi  Use resources from this location when building the boot image
  # -o $ISO/efi/boot/bootx64.efi      Output destination, using wellknown compatibility location
  grub-mkimage -O x86_64-efi -p /boot/grub -d $ROOT/usr/lib/grub/x86_64-efi -o $ISO/efi/boot/bootx64.efi \
    disk part_msdos part_gpt linux linux16 loopback normal configfile test search search_fs_uuid \
    search_fs_file true iso9660 search_label efi_uga efi_gop gfxterm gfxmenu gfxterm_menu ext2 \
    ntfs cat echo ls memdisk tar
  check
}

# Build the initramfs based installer
build_installer() {
  echo -en ":: Build the initramfs based installer..."
  sudo cp installer/installer $ROOT/usr/lib/initcpio/hooks
  sudo cp installer/installer.conf $ROOT/usr/lib/initcpio/install/installer
  sudo cp installer/mkinitcpio.conf $ROOT/etc
  sudo mount --bind $ROOT $ROOT
  sudo arch-chroot $ROOT mkinitcpio -g /root/installer
  sudo cp $ROOT/root/installer $ISO/boot
  sudo umount $ROOT
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

# Main entry point
# -------------------------------------------------------------------------------------------------
build() {
  config_build_env
  create_bios_boot_images
  create_efi_boot_images
}
usage() {
  echo -e "${cyan}CYBERLINUX${none} initramfs based installer automation"
  echo -e "Usage: ${cyan}./`basename $0`${none} [options]"
  echo -e "Options:"
  echo -e "-c  Clean the build artifacts before building"
  echo -e "-f  Force boot images to be rebuilt"
  echo -e "-i  Build the initramfs"
  echo -e "-h  Display usage help"
  exit 1
}
while getopts ":cfih" opt; do
  case $opt in
    c)
      echo "Cleaning build artifacts before building"
      sudo rm -rf $TEMP 
      ;;
    f)
      build
      ;;
    i)
      [ ! -d $TEMP ] && build
      build_installer
      ;;
    h)
      usage
      ;;
    \?)
      echo -e "Invalid option: ${red}-$OPTARG${none}\n"
      usage
      ;;
  esac
done

[ ! -d $TEMP ] && build
build_iso

# vim: ft=sh:ts=2:sw=2:sts=2
