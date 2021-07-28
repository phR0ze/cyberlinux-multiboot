#!/bin/bash
none="\e[m"
red="\e[1;31m"
cyan="\e[1;36m"
green="\e[1;32m"
yellow="\e[1;33m"

TEMP_PATH=temp                            # Temp directory for build artifacts
GRUB_PATH=grub                            # Location to pull persisted Grub configuration files from
PROFILES_PATH=profiles                    # Location for profile descriptions, packages and configs
INSTALLER_PATH=installer                  # Location to pull installer hooks from
ROOT_PATH=${TEMP_PATH}/root               # Root mount point to build layered filesystems
REPO_PATH=${TEMP_PATH}/x86_64             # Local repo location to stage packages being built
ISO_PATH=${TEMP_PATH}/iso                 # Build location for staging iso/boot files
BUILD_PATH=${TEMP_PATH}/build             # Build location for packages extraction and builds
LAYERS_PATH=${TEMP_PATH}/layers           # Layered filesystems to include in the ISO
MOUNTPOINTS=("$BUILD_PATH" "$ROOT_PATH")  # Array of mount points to ensure get unmounted when done
BOOT_CFG="${ISO_PATH}/boot/grub/boot.cfg" # Boot menu entries to read in
PROJECT_ROOT=$(dirname $BASH_SOURCE[0])   # Determine the root path of the project

# Ensure the current user has passwordless sudo access
if ! sudo -l | grep -q "NOPASSWD: ALL"; then
  echo -e ":: ${red}Failed${none} - Passwordless sudo access is required see README.md..."
  exit
fi

check()
{
  if [ $? -ne 0 ]; then
    echo -e "${red}failed!${none}"
    exit 1
  else
    echo -e "${green}success!${none}"
  fi
}

# Provide a failsafe for umounting mount points on exit
RELEASED=0
release()
{
  if [ $RELEASED -ne 1 ]; then
    RELEASED=1
    for x in ${MOUNTPOINTS[@]}; do
      if mountpoint -q $x; then
        echo -en ":: Releasing mount point ${cyan}${x}${none}..."
        sudo umount -R $x
        check
      fi
    done
  fi
  exit
}
trap release EXIT
trap release SIGINT

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
  if [ ! -d $BUILD_PATH ]; then
    echo -en "${yellow}:: Configuring build environment...${none}"
    sudo mkdir -p $BUILD_PATH
    sudo pacstrap -c -G -M $BUILD_PATH coreutils pacman grub sed linux intel-ucode memtest86+ mkinitcpio \
      mkinitcpio-vt-colors dosfstools rsync gptfdisk
  fi
}

# Configure grub theme and build supporting BIOS and EFI boot images required to make
# the ISO bootable as a CD or USB stick on BIOS and UEFI systems with the same presentation.
build_multiboot()
{
  echo -e "${yellow}:: Building multiboot components...${none}"
  mkdir -p $ISO_PATH/boot/grub/themes

  echo -en ":: Copying kernel, intel ucode patch and memtest to ${ISO_PATH}/boot..."
  cp $BUILD_PATH/boot/intel-ucode.img $ISO_PATH/boot
  cp $BUILD_PATH/boot/vmlinuz-linux $ISO_PATH/boot
  cp $BUILD_PATH/boot/memtest86+/memtest.bin $ISO_PATH/boot/memtest
  check

  echo -en ":: Copying GRUB config and theme to ${ISO_PATH}/boot/grub ..."
  cp ${GRUB_PATH}/grub.cfg $ISO_PATH/boot/grub
  cp ${GRUB_PATH}/loopback.cfg $ISO_PATH/boot/grub
  cp -r ${GRUB_PATH}/themes $ISO_PATH/boot/grub
  cp $BUILD_PATH/usr/share/grub/unicode.pf2 $ISO_PATH/boot/grub
  check

  # Create the target profile's boot entries
  rm -f $BOOT_CFG
  for layer in $(echo "$PROFILE_JSON" | jq -r '.[].name'); do
    deployment $layer
    echo -e ":: Creating ${cyan}${layer}${none} boot entry in ${cyan}${ISO_PATH}/boot/grub/boot.cfg${none}"
    echo -e "menuentry --class=deployment '${LABEL}' {" >> ${BOOT_CFG}
    echo -e "  cat /boot/grub/themes/cyberlinux/splash" >> ${BOOT_CFG}
    echo -e "  sleep 5" >> ${BOOT_CFG}
    echo -e "  linux	/boot/vmlinuz-${KERNEL} kernel=${KERNEL} layers=${LAYERS_STR}" >> ${BOOT_CFG}
    echo -e "  initrd	/boot/intel-ucode.img /boot/installer" >> ${BOOT_CFG}
    echo -e "}" >> ${BOOT_CFG}
  done

  echo -en ":: Creating core BIOS $BUILD_PATH/bios.img..."
  cp -r $BUILD_PATH/usr/lib/grub/i386-pc $ISO_PATH/boot/grub
  rm -f $ISO_PATH/boot/grub/i386-pc/*.img
  # We need to create our bios.img that contains just enough code to find the grub configuration and
  # grub modules in /boot/grub/i386-pc directory we'll stage in the next step
  # -O i386-pc                        Format of the image to generate
  # -p /boot/grub                     Directory to find grub once booted
  # -d $BUILD_PATH/usr/lib/grub/i386-pc    Use resources from this location when building the boot image
  # -o $BUILD_PATH/bios.img                Output destination
  grub-mkimage -O i386-pc -p /boot/grub -d $BUILD_PATH/usr/lib/grub/i386-pc -o $TEMP_PATH/bios.img  \
    biosdisk disk part_msdos part_gpt linux linux16 loopback normal configfile test search search_fs_uuid \
    search_fs_file true iso9660 search_label gfxterm gfxmenu gfxterm_menu ext2 ntfs cat echo ls memdisk tar
  check
  echo -en ":: Concatenate cdboot.img to bios.img to create the CD-ROM bootable Eltorito $TEMP_PATH/eltorito.img..."
  cat $BUILD_PATH/usr/lib/grub/i386-pc/cdboot.img $TEMP_PATH/bios.img > $ISO_PATH/boot/grub/i386-pc/eltorito.img
  check
  echo -en ":: Concatenate boot.img to bios.img to create isohybrid $TEMP_PATH/isohybrid.img..."
  cat $BUILD_PATH/usr/lib/grub/i386-pc/boot.img $TEMP_PATH/bios.img > $ISO_PATH/boot/grub/i386-pc/isohybrid.img
  check

  echo -en ":: Creating UEFI boot files..."
  mkdir -p $ISO_PATH/efi/boot
  cp -r $BUILD_PATH/usr/lib/grub/x86_64-efi $ISO_PATH/boot/grub
  rm -f $ISO_PATH/grub/x86_64-efi/*.img
  # -O x86_64-efi                     Format of the image to generate
  # -p /boot/grub                     Directory to find grub once booted
  # -d $BUILD_PATH/usr/lib/grub/x86_64-efi  Use resources from this location when building the boot image
  # -o $ISO_PATH/efi/boot/bootx64.efi      Output destination, using wellknown compatibility location
  grub-mkimage -O x86_64-efi -p /boot/grub -d $BUILD_PATH/usr/lib/grub/x86_64-efi -o $ISO_PATH/efi/boot/bootx64.efi \
    disk part_msdos part_gpt linux linux16 loopback normal configfile test search search_fs_uuid \
    search_fs_file true iso9660 search_label efi_uga efi_gop gfxterm gfxmenu gfxterm_menu ext2 \
    ntfs cat echo ls memdisk tar
  check
}

# Build the initramfs based installer
build_installer()
{
  echo -en "${yellow}:: Build the initramfs based installer...${none}"
  mkdir -p $ISO_PATH/boot
  sudo cp ${INSTALLER_PATH}/installer $BUILD_PATH/usr/lib/initcpio/hooks
  sudo cp ${INSTALLER_PATH}/installer.conf $BUILD_PATH/usr/lib/initcpio/install/installer
  sudo cp ${INSTALLER_PATH}/mkinitcpio.conf $BUILD_PATH/etc

  # Mount as bind mount to satisfy arch-chroot requirement
  # umount is handled by the release function on exit
  sudo mount --bind $BUILD_PATH $BUILD_PATH
  sudo arch-chroot $BUILD_PATH mkinitcpio -g /root/installer
  sudo cp $BUILD_PATH/root/installer $ISO_PATH/boot
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
#   --embedded-boot $TEMP_PATH/isohybrid.img
# EFI boot image location on the iso post creation to use to make this iso USB stick bootable by UEFI
# Note the use of the well known compatibility path /efi/boot/bootx64.efi
#   --efi-boot /efi/boot/bootx64.efi 
# Specify the output iso file path and location to turn into an ISO
#   -o boot.iso $ISO_PATH
build_iso()
{
  echo -e "${yellow}:: Building an ISOHYBRID bootable image...${none}"
  xorriso -as mkisofs \
    -r -iso-level 3 \
    -volid CYBERLINUX \
    --modification-date=$(date -u +%Y%m%d%H%M%S00) \
    -graft-points \
    -no-emul-boot \
    -boot-info-table \
    --protective-msdos-label \
    -b /boot/grub/i386-pc/eltorito.img \
    --embedded-boot $ISO_PATH/boot/grub/i386-pc/isohybrid.img \
    --efi-boot /efi/boot/bootx64.efi \
    -o boot.iso $ISO_PATH
}

# Build deployments
build_deployments() 
{
  echo -e "${yellow}:: Building deployments${none} ${cyan}${1}${none}..."
  mkdir -p $ROOT_PATH
  mkdir -p $LAYERS_PATH

  for target in ${1//,/ }; do
    deployment $target
    echo -e ":: Building deployment ${cyan}${target}${none} composed of ${cyan}${LAYERS_STR}${none}"

    for layer in ${LAYERS[@]}; do
      echo -e ":: Building layer ${cyan}${layer}${none}..."

      # Ensure the layer destination path exists
      local layer_path="${LAYERS_PATH}/${layer}"
      mkdir -p $layer_path

      # Mount the layer destination path 
      if [ ${#LAYERS[@]} -gt 1 ]; then
        echo -e ":: Mounting layer ${cyan}${layer}${none} to root ${cyan}${ROOT_PATH}${none}..."
        check
      else
        echo -en ":: Bind mount layer ${cyan}${layer}${none} to root ${cyan}${ROOT_PATH}${none}..."
        sudo mount --bind $layer_path $ROOT_PATH
        check
      fi

      # Install the target layer packages onto the layer
      local pkg="cyberlinux-${PROFILE}-${layer}"
      echo -e ":: Installing target layer package ${cyan}${pkg}${none} to root ${cyan}${ROOT_PATH}${none}"
      sudo pacstrap -c -G -M $ROOT_PATH $pkg
    done
  done
}

# Retrieve the deployment's properties
deployment()
{
  local layer=$(echo "$PROFILE_JSON" | jq '.[] | select(.name=="'$1'")')
  LABEL=$(echo "$layer" | jq '.label')
  KERNEL=$(echo "$layer" | jq -r '.kernel')
  LAYERS_STR=$(echo "$layer" | jq -r '.layers')
  
  # Create an array out of the layers as well
  ifs=$IFS; IFS=",";
  read -ra LAYERS <<< "${LAYERS_STR}"
  IFS=$ifs
}

# Main entry point
# -------------------------------------------------------------------------------------------------
header()
{
  echo -e "${cyan}CYBERLINUX${none} builder automation for a multiboot installer ISO"
  echo -e "${cyan}------------------------------------------------------------------${none}"
}
usage()
{
  header
  echo -e "Usage: ${cyan}./$(basename $0)${none} [options]"
  echo -e "Options:"
  echo -e "-a               Build all components"
  echo -e "-d DEPLOYMENTS   Build deployments, comma delimited (all|shell|lite)"
  echo -e "-i               Build the initramfs installer"
  echo -e "-m               Build the grub multiboot environment"
  echo -e "-I               Build the acutal ISO image"
  echo -e "-p               Set the profile to use, default: personal"
  echo -e "-c               Clean the build artifacts before building"
  echo -e "-h               Display usage help\n"
  echo -e "Examples:"
  echo -e "Build everything: ./$(basename $0) -a"
  echo -e "Build shell deployment: ./$(basename $0) -d shell"
  exit 1
}
while getopts ":ad:imIp:ch" opt; do
  case $opt in
    c) CLEAN=1;;
    a) ALL=1;;
    i) INSTALLER=1;;
    d) DEPLOYMENTS=$OPTARG;;
    m) MULTIBOOT=1;;
    I) ISO=1;;
    p) PROFILE=$OPTARG;;
    h) usage;;
    \?) echo -e "Invalid option: ${red}-${OPTARG}${none}\n"; usage;;
    :) echo -e "Option ${red}-${OPTARG}${none} requires an argument\n"; usage;;
  esac
done
[ $(($OPTIND -1)) -eq 0 ] && usage
header

# Set varible defaults
[ -z ${PROFILE+x} ] && PROFILE="personal"
PROFILE_PATH="${PROFILES_PATH}/${PROFILE}/profile.json"
echo -e ":: Using profile ${cyan}${PROFILE_PATH}${none}"
PROFILE_JSON=$(jq -r '.' ${PROFILE_PATH})

# Optionally clean artifacts
if [ ! -z ${CLEAN+x} ]; then
  echo -e ":: Cleaning build artifacts before building"
  sudo rm -rf $TEMP_PATH
fi
mkdir -p $TEMP_PATH

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

# Build the actual ISO
if [ ! -z ${ALL+x} ] || [ ! -z ${ISO+x} ]; then
  build_iso
fi

# vim: ft=sh:ts=2:sw=2:sts=2
