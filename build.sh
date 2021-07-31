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

BUILDER="builder"                         # Name of the builder directory, image and container
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
WORK_DIR="${TEMP_DIR}/work"               # Temp directory for package building cruft and mounting empty dir
PACMAN_CONF="${TEMP_DIR}/pacman.conf"     # Pacman config to use for building deployments
MIRRORLIST="${TEMP_DIR}/mirrorlist"       # Pacman mirrorlist to use for builder and deployments
MIRRORLIST_SRC="${CONFIG_DIR}/mirrorlist" # Pacman source mirrorlist to use for builder and deployments
MOUNTPOINTS=("$BUILDER_DIR" "$ROOT_DIR")  # Array of mount points to ensure get unmounted when done
PACMAN_CONF_SRC="${CONFIG_DIR}/pacman.conf" # Pacman config template to turn into the actual config
PACMAN_BUILDER_CONF="${CONFIG_DIR}/pacman.builder" # Pacman config template to turn into the actual config
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

# Configure build environment using Docker
# -------------------------------------------------------------------------------------------------
# We need to use a docker container in order to get the isolation needed. arch-chroot alone seems
# to allow leakage. Building off the `archlinux:base-devel` image provides a quick start.
# docker run --name builder --rm -it archlinux:base-devel bash
#
# archlinux:base-devel contains needed 
# `coreutils`             provides basic linux tooling
# `pacman`                provides the ability to add additional packages via a chroot to our build env
# `sed`                   is used by the installer to update configuration files as needed
#
# Need to install in container
# `grub`                  is needed by the installer for creating the EFI and BIOS boot partitions
# `dosfstools`            provides `mkfs.fat` needed by the installer for creating the EFI boot partition
# `mkinitcpio`            provides the tooling to build the initramfs early userspace installer
# `mkinitcpio-vt-colors`  provides terminal coloring at boot time for output messages
# `rsync`                 used by the installer to copy install data to the install target
# `gptfdisk`              used by the installer to prepare target media for install
# `linux`                 need to load the kernel to satisfy GRUB
# `intel-ucode`           standard practice to load the intel-ucode
# `expect`                provides the mkpasswd command
build_env()
{
  echo -e "${yellow}:: Configuring build environment...${none}"
  mkdir -p "${REPO_DIR}"

  # Build the builder image
  if ! docker_exists ${BUILDER}; then
    docker_kill ${BUILDER}

    # Cache packages ahead of time as mounts are not allowed in builds
    sudo mkdir -p "${CACHE_DIR}"
    docker_run archlinux:base-devel
    docker_cp "${PACMAN_BUILDER_CONF}" "${BUILDER}:/etc/pacman.conf"
    local packages="vim grub dosfstools mkinitcpio mkinitcpio-vt-colors rsync gptfdisk linux intel-ucode expect"
    docker_exec ${BUILDER} "pacman -Syw --noconfirm ${packages}"

    docker build -t ${BUILDER} "${PROJECT_DIR}"
  fi

  # Build custom packages
  if [ ! -f "$REPO_DIR/builder.db" ]; then
    build_packages
  fi

#  # Build the builder image if it doesn't exist yet
#  if [ ! -d "$BUILDER_DIR" ]; then
#    docker image ls --format="{{json .}}" | jq -r 'select(.Repository == "archlinux" and .Tag == "base-devel") | .ID'
#  fi
#
#  # Build the builder
#  if [ ! -d "$BUILDER_DIR" ]; then
#    [ ! -f "$PACMAN_CONF" ] && update_pacman_conf
#    [ ! -d "$REPO_DIR" ] && build_packages
#
#    echo -e "${yellow}:: Configuring build environment...${none}"
#
#    # Needs to be owned by root to avoid warnings
#    sudo mkdir -p "$BUILDER_DIR"
#
#    # -C use an alternate config file for pacman
#    # -c use the package cache on the host rather than target
#    # -G avoid copying the host's pacman keyring to the target
#    # -M avoid copying the host's mirrorlist to the target
#    sudo pacstrap -C "${PACMAN_CONF}" -c -G -M "${BUILDER_DIR}" coreutils pacman grub sed linux \
#      intel-ucode memtest86+ mkinitcpio mkinitcpio-vt-colors dosfstools rsync gptfdisk
#    check
#  fi
    docker_kill ${BUILDER}
}

# Build packages if needed
build_packages() 
{
  echo -e "${yellow}:: Building packages for${none} ${cyan}${PROFILE}${none} profile..."
  mkdir -p "$REPO_DIR" "$WORK_DIR"
  return

  docker_run ${BUILDER}

  pushd "${PROFILE_DIR}"
  BUILDDIR="${WORK_DIR}" PKGDEST="${REPO_DIR}" makepkg
  rm -rf "${WORK_DIR}"
  popd

  # Ensure the builder repo exists locally
  pushd "${REPO_DIR}"
  repo-add builder.db.tar.gz *.pkg.tar.*
  popd
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

    # Don't include entries that don't have a kernel called out as they are intended
    # as a non-installable option for building on only
    if [ ${KERNEL} != "null" ]; then
      echo -e ":: Creating ${cyan}${layer}${none} boot entry in ${cyan}${ISO_DIR}/boot/grub/boot.cfg${none}"
      echo -e "menuentry --class=deployment '${LABEL}' {" >> "${BOOT_CFG_PATH}"
      echo -e "  cat /boot/grub/themes/cyberlinux/splash" >> "${BOOT_CFG_PATH}"
      echo -e "  sleep 5" >> "${BOOT_CFG_PATH}"
      echo -e "  linux	/boot/vmlinuz-${KERNEL} kernel=${KERNEL} layers=${LAYERS_STR}" >> "${BOOT_CFG_PATH}"
      echo -e "  initrd	/boot/intel-ucode.img /boot/installer" >> "${BOOT_CFG_PATH}"
      echo -e "}" >> "${BOOT_CFG_PATH}"
    fi
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
  sudo rm -rf "$WORK_DIR"
  mkdir -p "$LAYERS_DIR" "$WORK_DIR"
  sudo mkdir -p "$ROOT_DIR" # needs to be owned by root for layering to be happy

  for target in ${1//,/ }; do
    read_deployment $target
    echo -e ":: Building deployment ${cyan}${target}${none} composed of ${cyan}${LAYERS_STR}${none}"

    for i in "${!LAYERS[@]}"; do
      local layer="${LAYERS[$i]}"
      echo -e ":: Building layer ${cyan}${layer}${none}..."

      # Ensure the layer destination path exists and is owned by root to avoid warnings
      local layer_path="${LAYERS_DIR}/${layer}"
      sudo mkdir -p "$layer_path"

      # Mount the layer destination path 
      if [ ${i} -gt 0 ]; then
        # `upperdir` is a writable layer at the top
        # `lowerdir` is a colon : separated list of read-only dirs the right most is the lowest
        # `workdir` is an empty dir used to prepare files as they are switched between layers
        # the last param is the merged or resulting filesystem after layering to work with
        echo -e ":: Mounting layer ${cyan}${layer}${none} over ${cyan}${ROOT_DIR}${none}..."
        sudo mount -t overlay overlay -o lowerdir="${ROOT_DIR}",upperdir="${layer_path}",workdir="${WORK_DIR}" "${ROOT_DIR}"
        check
      else
        echo -en ":: Bind mount layer ${cyan}${layer}${none} to root ${cyan}${ROOT_DIR}${none}..."
        sudo mount --bind "$layer_path" "$ROOT_DIR"
        check
      fi

      # Derive the package name from 'profile/layer' string given
      local pkg="cyberlinux-${layer//\//-}"

      echo -e ":: Installing target layer package ${cyan}${pkg}${none} to root ${cyan}${ROOT_DIR}${none}"
      # -C use an alternate config file for pacman
      # -c use the package cache on the host rather than target
      # -G avoid copying the host's pacman keyring to the target
      # -M avoid copying the host's mirrorlist to the target
      sudo pacstrap -C "${PACMAN_CONF}" -c -G -M "$ROOT_DIR" "$pkg"
    done

    # Release the root mount point now that we have fully built the required layers
    echo -en ":: Releasing overlay ${cyan}${ROOT_DIR}${none}..."
    sudo umount -fR "$ROOT_DIR"
    check
  done
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
    elif [ "${x}" == "${BUILDER}" ]; then
      sudo rm -rf "${target}"
      docker_rmi ${BUILDER}
    else
      sudo rm -rf "${target}"
    fi
  done
}

# Profile utility functions
# -------------------------------------------------------------------------------------------------

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

# Docker utility functions
# -------------------------------------------------------------------------------------------------

# Execute the given bash script against the wellknown builder container
# $1 container to execute on
# $2 bash to execute
docker_exec() {
  docker exec --privileged ${1} bash -c "${2}"
}

# Check if the given image exists
# $1 docker repository
docker_exists() {
  docker image inspect -f {{.Metadata.LastTagTime}} $1 &>/dev/null
}

# Check if the given docker container is running
# $1 container to check
docker_running() {
  [ "$(docker container inspect -f {{.State.Running}} $1 2>/dev/null)" == "true" ]
}

# Copy the given source file to the given destination file
# example to container: docker_cp "/etc/pacman.conf" "builder:/etc/pacman.conf"
# example from container: docker_cp "builder:/etc/pacman.conf" "/tmp"
# $1 source file
# $2 destination file
docker_cp() {
  echo -en ":: Copying ${cyan}${1}${none} to ${cyan}$2${none}..."
  docker cp "$1" "$2"
  check
}

# Docker remove image
# $1 repository name
docker_rmi() {
  if docker_exists ${1}; then
    echo -en ":: Removing the given image ${cyan}${1}${none}..."
    docker image rm $1
    check
  fi
}

# Pull the builder container if it doesn't exist then run it in a sleep loop so we can work with
# it in parallel. We'll need to wait until it is ready and manage its lifecycle
# $1 container repository:tag combo to run
docker_run() {
  docker_running ${BUILDER} && return
  echo -en ":: Running docker container in loop: ${cyan}${1}${none}..."
  
  # Docker will need additional privileges to allow mount to work inside a container
  local params="-e TERM=xterm -v /var/run/docker.sock:/var/run/docker.sock --privileged=true"

  # Run a sleep loop for as long as we need to
  # -d means run in detached mode so we don't block
  # -v is used to mount a directory into the container to cache all the packages.
  #    also using it to mount the custom repo into the container
  docker run --name ${BUILDER} -d --rm ${params} \
    -v "${REPO_DIR}":/var/cache/builder -v "${CACHE_DIR}":/var/cache/pacman/pkg \
    $1 bash -c "while :; do sleep 5; done" &>/dev/null
  check

  # Now wait until it responds to commands
  while ! docker_running ${BUILDER}; do sleep 2; done
}

# Kill the running container using its wellknown name
# $1 container name to kill
docker_kill() {
  if docker_running ${1}; then
    echo -en ":: Killing docker ${cyan}${1}${none} container..."
    docker kill ${1} &>/dev/null
    check
  fi
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
  echo -e "Usage: ${cyan}./$(basename $0)${none} [options]\n"
  echo -e "Options:"
  echo -e "-a               Build all components"
  echo -e "-b               Build the builder filesystem"
  echo -e "-d DEPLOYMENTS   Build deployments, comma delimited (all|shell|lite)"
  echo -e "-i               Build the initramfs installer"
  echo -e "-m               Build the grub multiboot environment"
  echo -e "-I               Build the acutal ISO image"
  echo -e "-P               Build packages for deployment/s and/or profile"
  echo -e "-p               Set the profile to use, default: personal"
  echo -e "-c               Clean build artifacts, commad delimited (all|builder|iso|layers/standard/core)"
  echo -e "-h               Display usage help\n"
  echo -e "Examples:"
  echo -e "${green}Build everything:${none} ./${SCRIPT} -a"
  echo -e "${green}Build shell deployment:${none} ./${SCRIPT} -d shell"
  echo -e "${green}Build just bootable installer:${none} ./${SCRIPT} -imI"
  echo -e "${green}Build packages for standard profile:${none} ./${SCRIPT} -p standard -P"
  echo -e "${green}Build standard base:${none} ./${SCRIPT} -p standard -d base"
  echo -e "${green}Clean standard core layer:${none} ./${SCRIPT} -c layers/standard/core"
  echo -e "${green}Rebuild builder image:${none} ./${SCRIPT} -c builder -b"
  echo
  exit 1
}
while getopts ":abd:imIPp:c:th" opt; do
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
    t) TEST=1;;
    h) usage;;
    \?) echo -e "Invalid option: ${red}-${OPTARG}${none}\n"; usage;;
    :) echo -e "Option ${red}-${OPTARG}${none} requires an argument\n"; usage;;
  esac
done
[ $(($OPTIND -1)) -eq 0 ] && usage
header

# Invoke the testing function if given
[ ! -z ${TEST+x} ] && testing

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
