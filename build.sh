#!/bin/bash
#set -x
none="\e[m"
red="\e[1;31m"
cyan="\e[1;36m"
green="\e[1;32m"
yellow="\e[1;33m"

# Determine the script name and absolute root path of the project
SCRIPT=$(basename $0)
PROJECT_DIR=$(readlink -f $(dirname $BASH_SOURCE[0]))

TEMP_DIR="${PROJECT_DIR}/temp"            # Temp directory for build artifacts
GRUB_DIR="${PROJECT_DIR}/grub"            # Location to pull persisted Grub configuration files from
CONFIG_DIR="${PROJECT_DIR}/config"        # Location for config files and templates files
PROFILES_DIR="${PROJECT_DIR}/profiles"    # Location for profile descriptions, packages and configs
INSTALLER_DIR="${PROJECT_DIR}/installer"  # Location to pull installer hooks from
ISO_DIR="${TEMP_DIR}/iso"                 # Build location for staging iso/boot files
ROOT_DIR="${TEMP_DIR}/root"               # Root mount point to build layered filesystems
REPO_DIR="${TEMP_DIR}/x86_64"             # Local repo location to stage packages being built
CACHE_DIR="${TEMP_DIR}/cache"             # Local location to cache packages used in building deployments
BUILDER_DIR="${TEMP_DIR}/builder"         # Build location for packages extraction and builds
LAYERS_DIR="${TEMP_DIR}/layers"           # Layered filesystems to include in the ISO
PACMAN_CONF="${TEMP_DIR}/pacman.conf"     # Pacman config to use for building deployments
MIRRORLIST="${TEMP_DIR}/mirrorlist"       # Pacman mirrorlist to use for builder and deployments
MIRRORLIST_SRC="${CONFIG_DIR}/mirrorlist" # Pacman source mirrorlist to use for builder and deployments
MOUNTPOINTS=("$BUILDER_DIR" "$ROOT_DIR")  # Array of mount points to ensure get unmounted when done
PACMAN_CONF_SRC="${CONFIG_DIR}/pacman.tpl" # Pacman config template to turn into the actual config
BOOT_CFG_PATH="${ISO_DIR}/boot/grub/boot.cfg"  # Boot menu entries to read in

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
    for x in "${MOUNTPOINTS[@]}"; do
      if mountpoint -q "$x"; then
        echo -en ":: Releasing mount point ${cyan}${x}${none}..."
        sudo umount -fR "$x"
        check
      fi
    done
  fi
  exit
}
trap release EXIT
trap release SIGINT

# Stage the pacman config files for use
stage_pacman_config()
{
  echo -e "${yellow}:: Staging pacman configuration${none}"

  # Stage the mirrorlist and pacman.conf
  cp "${MIRRORLIST_SRC}" "${MIRRORLIST}"
  cp "${PACMAN_CONF_SRC}" "${PACMAN_CONF}"

  # Ensure template variables are replaced properly
  sed -i "s|<%CACHE_DIR%>|${CACHE_DIR}|" "${PACMAN_CONF}"
  sed -i "s|<%BUILD_REPO_PATH%>|${TEMP_DIR}|" "${PACMAN_CONF}"
  sed -i "s|<%ARCH_MIRROR_LIST_PATH%>|${MIRRORLIST}|" "${PACMAN_CONF}"
}

# Build packages
build_packages() 
{
  echo -e "${yellow}:: Building packages for${none} ${cyan}${PROFILE}${none} profile..."
  rm -rf "${REPO_DIR}"
  mkdir -p "$REPO_DIR"
  pushd "${PROFILE_DIR}"
  BUILDDIR="${TEMP_DIR}" PKGDEST="${REPO_DIR}" makepkg
  popd

  # Ensure the builder repo exists locally
  pushd "${REPO_DIR}"
  repo-add builder.db.tar.gz *.pkg.tar.*
  popd
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
build_env()
{
  if [ ! -d "$BUILDER_DIR" ]; then
    stage_pacman_config
    build_packages

    echo -e "${yellow}:: Configuring build environment...${none}"
    mkdir -p "$CACHE_DIR"
    mkdir -p "$BUILDER_DIR"

    # -C use an alternate config file for pacman
    # -c use the package cache on the host rather than target
    # -G avoid copying the host's pacman keyring to the target
    # -M avoid copying the host's mirrorlist to the target
    sudo pacstrap -C "${PACMAN_CONF}" -c -G -M "${BUILDER_DIR}" coreutils pacman grub sed linux \
      intel-ucode memtest86+ mkinitcpio mkinitcpio-vt-colors dosfstools rsync gptfdisk
    check
  fi
}

# Configure grub theme and build supporting BIOS and EFI boot images required to make
# the ISO bootable as a CD or USB stick on BIOS and UEFI systems with the same presentation.
build_multiboot()
{
  echo -e "${yellow}:: Building multiboot components...${none}"
  mkdir -p "${ISO_DIR}/boot/grub/themes"

  echo -en ":: Copying kernel, intel ucode patch and memtest to ${ISO_DIR}/boot..."
  cp "${BUILDER_DIR}/boot/intel-ucode.img" "${ISO_DIR}/boot"
  cp "${BUILDER_DIR}/boot/vmlinuz-linux" "${ISO_DIR}/boot"
  cp "${BUILDER_DIR}/boot/memtest86+/memtest.bin" "${ISO_DIR}/boot/memtest"
  check

  echo -en ":: Copying GRUB config and theme to ${ISO_DIR}/boot/grub ..."
  cp "${GRUB_DIR}/grub.cfg" "${ISO_DIR}/boot/grub"
  cp "${GRUB_DIR}/loopback.cfg" "${ISO_DIR}/boot/grub"
  cp -r "${GRUB_DIR}/themes" "${ISO_DIR}/boot/grub"
  cp "${BUILDER_DIR}/usr/share/grub/unicode.pf2" "${ISO_DIR}/boot/grub"
  check

  # Create the target profile's boot entries
  rm -f "$BOOT_CFG_PATH"
  for layer in $(echo "$PROFILE_JSON" | jq -r '.[].name'); do
    read_deployment $layer
    echo -e ":: Creating ${cyan}${layer}${none} boot entry in ${cyan}${ISO_DIR}/boot/grub/boot.cfg${none}"
    echo -e "menuentry --class=deployment '${LABEL}' {" >> "${BOOT_CFG_PATH}"
    echo -e "  cat /boot/grub/themes/cyberlinux/splash" >> "${BOOT_CFG_PATH}"
    echo -e "  sleep 5" >> "${BOOT_CFG_PATH}"
    echo -e "  linux	/boot/vmlinuz-${KERNEL} kernel=${KERNEL} layers=${LAYERS_STR}" >> "${BOOT_CFG_PATH}"
    echo -e "  initrd	/boot/intel-ucode.img /boot/installer" >> "${BOOT_CFG_PATH}"
    echo -e "}" >> "${BOOT_CFG_PATH}"
  done

  echo -en ":: Creating core BIOS $BUILDER_DIR/bios.img..."
  cp -r "${BUILDER_DIR}/usr/lib/grub/i386-pc" "${ISO_DIR}/boot/grub"
  rm -f "${ISO_DIR}/boot/grub/i386-pc/*.img"
  # We need to create our bios.img that contains just enough code to find the grub configuration and
  # grub modules in /boot/grub/i386-pc directory we'll stage in the next step
  # -O i386-pc                        Format of the image to generate
  # -p /boot/grub                     Directory to find grub once booted
  # -d $BUILDER_DIR/usr/lib/grub/i386-pc    Use resources from this location when building the boot image
  # -o $BUILDER_DIR/bios.img                Output destination
  grub-mkimage -O i386-pc -p /boot/grub -d "$BUILDER_DIR/usr/lib/grub/i386-pc" -o "$TEMP_DIR/bios.img"  \
    biosdisk disk part_msdos part_gpt linux linux16 loopback normal configfile test search search_fs_uuid \
    search_fs_file true iso9660 search_label gfxterm gfxmenu gfxterm_menu ext2 ntfs cat echo ls memdisk tar
  check
  echo -en ":: Concatenate cdboot.img to bios.img to create the CD-ROM bootable Eltorito $TEMP_DIR/eltorito.img..."
  cat "$BUILDER_DIR/usr/lib/grub/i386-pc/cdboot.img" "$TEMP_DIR/bios.img" > "$ISO_DIR/boot/grub/i386-pc/eltorito.img"
  check
  echo -en ":: Concatenate boot.img to bios.img to create isohybrid $TEMP_DIR/isohybrid.img..."
  cat "$BUILDER_DIR/usr/lib/grub/i386-pc/boot.img" "$TEMP_DIR/bios.img" > "$ISO_DIR/boot/grub/i386-pc/isohybrid.img"
  check

  echo -en ":: Creating UEFI boot files..."
  mkdir -p "$ISO_DIR/efi/boot"
  cp -r "$BUILDER_DIR/usr/lib/grub/x86_64-efi" "$ISO_DIR/boot/grub"
  rm -f "$ISO_DIR/grub/x86_64-efi/*.img"
  # -O x86_64-efi                     Format of the image to generate
  # -p /boot/grub                     Directory to find grub once booted
  # -d "$BUILDER_DIR/usr/lib/grub/x86_64-efi"  Use resources from this location when building the boot image
  # -o "$ISO_DIR/efi/boot/bootx64.efi"      Output destination, using wellknown compatibility location
  grub-mkimage -O x86_64-efi -p /boot/grub -d "$BUILDER_DIR/usr/lib/grub/x86_64-efi" -o \
    "$ISO_DIR/efi/boot/bootx64.efi" disk part_msdos part_gpt linux linux16 loopback normal \
    configfile test search search_fs_uuid search_fs_file true iso9660 search_label efi_uga \
    efi_gop gfxterm gfxmenu gfxterm_menu ext2 ntfs cat echo ls memdisk tar
  check
}

# Build the initramfs based installer
build_installer()
{
  echo -en "${yellow}:: Build the initramfs based installer...${none}"
  mkdir -p "$ISO_DIR/boot"
  sudo cp "${INSTALLER_DIR}/installer" "$BUILDER_DIR/usr/lib/initcpio/hooks"
  sudo cp "${INSTALLER_DIR}/installer.conf" "$BUILDER_DIR/usr/lib/initcpio/install/installer"
  sudo cp "${INSTALLER_DIR}/mkinitcpio.conf" "$BUILDER_DIR/etc"

  # Mount as bind mount to satisfy arch-chroot requirement
  # umount is handled by the release function on exit
  sudo mount --bind "$BUILDER_DIR" "$BUILDER_DIR"
  sudo arch-chroot "$BUILDER_DIR" mkinitcpio -g /root/installer
  sudo cp "$BUILDER_DIR/root/installer" "$ISO_DIR/boot"
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
#   --embedded-boot "$TEMP_DIR/isohybrid.img"
# EFI boot image location on the iso post creation to use to make this iso USB stick bootable by UEFI
# Note the use of the well known compatibility path /efi/boot/bootx64.efi
#   --efi-boot /efi/boot/bootx64.efi 
# Specify the output iso file path and location to turn into an ISO
#   -o boot.iso "$ISO_DIR"
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
    --embedded-boot "$ISO_DIR/boot/grub/i386-pc/isohybrid.img" \
    --efi-boot /efi/boot/bootx64.efi \
    -o boot.iso "$ISO_DIR"
}

# Build deployments
build_deployments() 
{
  echo -e "${yellow}:: Building deployments${none} ${cyan}${1}${none}..."
  mkdir -p "$ROOT_DIR"
  mkdir -p "$LAYERS_DIR"

  for target in ${1//,/ }; do
    read_deployment $target
    echo -e ":: Building deployment ${cyan}${target}${none} composed of ${cyan}${LAYERS_STR}${none}"

    for layer in ${LAYERS[@]}; do
      echo -e ":: Building layer ${cyan}${layer}${none}..."

      # Ensure the layer destination path exists
      local layer_path="${LAYERS_DIR}/${layer}"
      mkdir -p "$layer_path"

      # Mount the layer destination path 
      if [ ${#LAYERS[@]} -gt 1 ]; then
        echo -e ":: Mounting layer ${cyan}${layer}${none} to root ${cyan}${ROOT_DIR}${none}..."
        check
      else
        echo -en ":: Bind mount layer ${cyan}${layer}${none} to root ${cyan}${ROOT_DIR}${none}..."
        sudo mount --bind "$layer_path" "$ROOT_DIR"
        check
      fi

      # Install the target layer packages onto the layer
      local pkg="cyberlinux-${PROFILE}-${layer}"
      echo -e ":: Installing target layer package ${cyan}${pkg}${none} to root ${cyan}${ROOT_DIR}${none}"
      sudo pacstrap -c -G -M "$ROOT_DIR" "$pkg"
    done
  done
}

# Retrieve the deployment's properties
read_deployment()
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

# Read the given profile from disk
# $1 is expected to be the name of the profile
read_profile()
{
  PROFILE_DIR="${PROFILES_DIR}/${1}"
  PROFILE_PATH="${PROFILE_DIR}/profile.json"
  echo -en "${yellow}:: Using profile${none} ${cyan}${PROFILE_PATH}${none}..."
  PROFILE_JSON=$(jq -r '.' "$PROFILE_PATH")
  check
}

# Clean the various build artifacts as called out
clean()
{
  for x in ${1//,/ }; do
    local target="${TEMP_DIR}/${x}"
    echo -e "${yellow}:: Cleaning build artifacts${none} ${cyan}${target}${none}"
    if [ "${x}" == "all" ]; then
      sudo rm -rf "${TEMP_DIR}"
      return
    else
      sudo rm -rf "${target}"
    fi
  done
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
  echo -e "-b               Build the builder filesystem"
  echo -e "-d DEPLOYMENTS   Build deployments, comma delimited (all|shell|lite)"
  echo -e "-i               Build the initramfs installer"
  echo -e "-m               Build the grub multiboot environment"
  echo -e "-I               Build the acutal ISO image"
  echo -e "-P               Build packages for deployment/s and/or profile"
  echo -e "-p               Set the profile to use, default: personal"
  echo -e "-c               Clean build artifacts, commad delimited (all|builder|iso|layers/shell|layers/lite)"
  echo -e "-h               Display usage help\n"
  echo -e "Examples:"
  echo -e "${green}Build everything:${none} ./${SCRIPT} -a"
  echo -e "${green}Build shell deployment:${none} ./${SCRIPT} -d shell"
  echo -e "${green}Build just bootable installer:${none} ./${SCRIPT} -imI"
  echo
  exit 1
}
while getopts ":abd:imIPp:c:h" opt; do
  case $opt in
    c) CLEAN=$OPTARG;;
    a) BUILD_ALL=1;;
    b) BUILD_BUILDER=1;;
    i) BUILD_INSTALLER=1;;
    d) DEPLOYMENTS=$OPTARG;;
    m) BUILD_MULTIBOOT=1;;
    I) BUILD_ISO=1;;
    P) BUILD_PACKAGES=1;;
    p) PROFILE=$OPTARG;;
    h) usage;;
    \?) echo -e "Invalid option: ${red}-${OPTARG}${none}\n"; usage;;
    :) echo -e "Option ${red}-${OPTARG}${none} requires an argument\n"; usage;;
  esac
done
[ $(($OPTIND -1)) -eq 0 ] && usage
header

# Read profile
[ -z ${PROFILE+x} ] && PROFILE="personal"
read_profile "$PROFILE"

# Optionally clean artifacts
if [ ! -z ${CLEAN+x} ]; then
  clean $CLEAN
fi
mkdir -p "$TEMP_DIR"

# 1. Always build the build environment if any build option is chosen
if [ ! -z ${BUILD_ALL+x} ] || [ ! -z ${BUILD_MULTIBOOT+x} ] || \
  [ ! -z ${BUILD_INSTALLER+x} ] || [ ! -z ${DEPLOYMENTS+x} ] || \
  [ ! -z ${BUILD_PACKAGES+x} ] || [ ! -z ${BUILD_BUILDER+x} ]; then
  build_env
fi

# Build packages
if [ ! -z ${BUILD_ALL+x} ] || [ ! -z ${BUILD_PACKAGES+x} ]; then
  build_packages
fi

# Needs to happen before the multiboot as deployments will be boot entries
if [ ! -z ${BUILD_ALL+x} ] || [ ! -z ${DEPLOYMENTS+x} ]; then
  build_deployments $DEPLOYMENTS
fi
if [ ! -z ${BUILD_ALL+x} ] || [ ! -z ${BUILD_MULTIBOOT+x} ]; then
  build_multiboot
fi
if [ ! -z ${BUILD_ALL+x} ] || [ ! -z ${BUILD_INSTALLER+x} ]; then
  build_installer
fi

# Build the actual ISO
if [ ! -z ${BUILD_ALL+x} ] || [ ! -z ${BUILD_ISO+x} ]; then
  build_iso
fi

# vim: ft=sh:ts=2:sw=2:sts=2
