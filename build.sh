#!/bin/bash
#set -x
none="\e[m"
red="\e[1;31m"
cyan="\e[1;36m"
green="\e[1;32m"
yellow="\e[1;33m"

BUILDER="builder"                         # Name of the build image and container

# Determine the script name and absolute root path of the project
SCRIPT=$(basename $0)
PROJECT_DIR=$(readlink -f $(dirname $BASH_SOURCE[0]))

# Temp build locations
TEMP_DIR="${PROJECT_DIR}/temp"            # Temp directory for build artifacts
ISO_DIR="${TEMP_DIR}/iso"                 # Build location for staging iso/boot files
REPO_DIR="${TEMP_DIR}/repo"               # Local repo location to stage packages being built
CACHE_DIR="${TEMP_DIR}/cache"             # Local location to cache packages used in building deployments
LAYERS_DIR="${TEMP_DIR}/layers"           # Layered filesystems to include in the ISO
OUTPUT_DIR="${TEMP_DIR}/output"           # Final built artifacts
IMAGES_DIR="${ISO_DIR}/images"            # Final iso sqfs image locations

# Source material to pull from
WORK_DIR="${LAYERS_DIR}/work"             # Temp work directory for layer mounts
GRUB_DIR="${PROJECT_DIR}/grub"            # Location to pull persisted Grub configuration files from
CONFIG_DIR="${PROJECT_DIR}/config"        # Location for config files and templates files
PROFILES_DIR="${PROJECT_DIR}/profiles"    # Location for profile descriptions, packages and configs
INSTALLER_DIR="${PROJECT_DIR}/installer"  # Location to pull installer hooks from
BOOT_CFG_PATH="${ISO_DIR}/boot/grub/boot.cfg"  # Boot menu entries to read in
PACMAN_BUILDER_CONF="${CONFIG_DIR}/pacman.builder" # Pacman config template to turn into the actual config

# Container directories and mount locations
CONT_BUILD_DIR="/home/build"              # Build location for layer components
CONT_ROOT_DIR="${CONT_BUILD_DIR}/root"    # Root mount point to build layered filesystems
CONT_ISO_DIR="${CONT_BUILD_DIR}/iso"      # Build location for staging iso/boot files
CONT_IMAGES_DIR="${CONT_ISO_DIR}/images"  # Final iso sqfs image locations
CONT_REPO_DIR="${CONT_BUILD_DIR}/repo"    # Local repo location to stage packages being built
CONT_CACHE_DIR="/var/cache/pacman/pkg"    # Location to mount cache at inside container
CONT_OUTPUT_DIR="${CONT_BUILD_DIR}/output" # Final built artifacts
CONT_LAYERS_DIR="${CONT_BUILD_DIR}/layers" # Layered filesystems to include in the ISO
CONT_WORK_DIR="${CONT_LAYERS_DIR}/work"    # Needs to be on the same file system as the upper dir i.e. layers
CONT_PROFILES_DIR="${CONT_BUILD_DIR}/profiles" # Location to mount profiles inside container

# Ensure the current user has passwordless sudo access
if ! sudo -l | grep -q "NOPASSWD: ALL"; then
  echo -e ":: ${red}Failed${none} - Passwordless sudo access is required see README.md..."
  exit
fi

# Create the necessary directories upfront
make_env_directories() {
  mkdir -p "${ISO_DIR}"
  mkdir -p "${REPO_DIR}"
  mkdir -p "${OUTPUT_DIR}"
  mkdir -p "${LAYERS_DIR}"
}

# Failsafe resource release code
[ -z ${RELEASED+x} ] && RELEASED=0
release() {
  if [ $RELEASED -ne 1 ]; then
    RELEASED=1
    docker_kill ${BUILDER}
    sudo rm -rf "${WORK_DIR}"
  fi
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
# `memtest86+`            boot memory tester tool
# `libisoburn`            needed for xorriso support
# `linux-firmware`        needed to reduce issing firmware during mkinitcpio builds
# `arch-install-scripts`  needed for `pacstrap`
# `squashfs-tools`        provides `mksquashfs` for creating squashfs images
# `jq`                    provides `jq` json manipulation
build_env()
{
  echo -e "${yellow}:: Configuring build environment...${none}"

  # Build the builder image
  if ! docker_image_exists ${BUILDER}; then
    docker_kill ${BUILDER}

    # Cache packages ahead of time as mounts are not allowed in builds
    docker_run archlinux:base-devel
    docker_cp "${PACMAN_BUILDER_CONF}" "${BUILDER}:/etc/pacman.conf"
    local packages="vim grub dosfstools mkinitcpio mkinitcpio-vt-colors rsync gptfdisk linux \
      intel-ucode memtest86+ libisoburn squashfs-tools"
    docker_exec ${BUILDER} "pacman -Syw --noconfirm ${packages}"
    docker_kill ${BUILDER}

    # Build the builder image
    docker build --force-rm -t ${BUILDER} "${PROJECT_DIR}"
  fi

  # Build custom packages
  if [ ! -f "$REPO_DIR/builder.db" ]; then
    build_packages
  fi
}

# Build packages if needed
build_packages() 
{
  echo -e "${yellow}:: Building packages for${none} ${cyan}${PROFILE}${none} profile..."

  docker_run ${BUILDER}
  docker_exec ${BUILDER} "sudo -u build bash -c 'cd ~/profiles/standard; BUILDDIR=~/ PKGDEST=/home/build/repo makepkg'"

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
  docker_run ${BUILDER}

  echo -e ":: Copying kernel, intel ucode patch and memtest to ${cyan}${ISO_DIR}/boot${none}"
  mkdir -p "${ISO_DIR}/boot/grub/themes"
  docker_cp "${BUILDER}:/boot/intel-ucode.img" "${ISO_DIR}/boot"
  docker_cp "${BUILDER}:/boot/vmlinuz-linux" "${ISO_DIR}/boot"
  docker_cp "${BUILDER}:/boot/memtest86+/memtest.bin" "${ISO_DIR}/boot/memtest"

  echo -e ":: Copying GRUB config and theme to ${ISO_DIR}/boot/grub"
  cp "${GRUB_DIR}/grub.cfg" "${ISO_DIR}/boot/grub"
  cp "${GRUB_DIR}/loopback.cfg" "${ISO_DIR}/boot/grub"
  cp -r "${GRUB_DIR}/themes" "${ISO_DIR}/boot/grub"
  docker_cp "${BUILDER}:/usr/share/grub/unicode.pf2" "${ISO_DIR}/boot/grub"

  # Create the target profile's boot entries
  rm -f "$BOOT_CFG_PATH"
  for layer in $(echo "$PROFILE_JSON" | jq -r '.[].name'); do
    read_deployment $layer

    # Don't include entries that don't have a kernel called out as they are intended
    # as a non-installable option for building on only
    if [ ${KERNEL} != "null" ]; then
      echo -e ":: Creating ${cyan}${layer}${none} boot entry in ${cyan}${ISO_DIR}/boot/grub/boot.cfg${none}"
      echo -e "menuentry --class=deployment ${LABEL} {" >> "${BOOT_CFG_PATH}"
      echo -e "  cat /boot/grub/themes/cyberlinux/splash" >> "${BOOT_CFG_PATH}"
      #echo -e "  sleep 5" >> "${BOOT_CFG_PATH}"
      echo -e "  linux	/boot/vmlinuz-${KERNEL} kernel=${KERNEL} layers=${LAYERS_STR}" >> "${BOOT_CFG_PATH}"
      echo -e "  initrd	/boot/intel-ucode.img /boot/installer" >> "${BOOT_CFG_PATH}"
      echo -e "}" >> "${BOOT_CFG_PATH}"
    fi
  done

  echo -en ":: Creating core BIOS $TEMP_DIR/bios.img..."
  docker_cp "${BUILDER}:/usr/lib/grub/i386-pc" "${ISO_DIR}/boot/grub"
  rm -f "${ISO_DIR}/boot/grub/i386-pc"/*.img
  # We need to create our bios.img that contains just enough code to find the grub configuration and
  # grub modules in /boot/grub/i386-pc directory we'll stage in the next step
  # -O i386-pc                Format of the image to generate
  # -p /boot/grub             Directory to find grub once booted
  # -d /usr/lib/grub/i386-pc  Use resources from this location when building the boot image
  # -o $TEMP_DIR/bios.img     Output destination
  cat <<EOF | docker exec --privileged -i ${BUILDER} sudo -u build bash
  grub-mkimage -O i386-pc -p /boot/grub -d /usr/lib/grub/i386-pc -o "$CONT_BUILD_DIR/bios.img" \
    biosdisk disk part_msdos part_gpt linux linux16 loopback normal configfile test search search_fs_uuid \
    search_fs_file true iso9660 search_label gfxterm gfxmenu gfxterm_menu ext2 ntfs cat echo ls memdisk tar
  echo -e ":: Concatenate cdboot.img to bios.img to create CD-ROM bootable image $CONT_BUILD_DIR/eltorito.img..."
  cat /usr/lib/grub/i386-pc/cdboot.img "$CONT_BUILD_DIR/bios.img" > "$CONT_ISO_DIR/boot/grub/i386-pc/eltorito.img"
  echo -e ":: Concatenate boot.img to bios.img to create isohybrid $CONT_BUILD_DIR/isohybrid.img..."
  cat /usr/lib/grub/i386-pc/boot.img "$CONT_BUILD_DIR/bios.img" > "$CONT_ISO_DIR/boot/grub/i386-pc/isohybrid.img"
EOF
  check

  echo -en ":: Creating UEFI boot files..."
  mkdir -p "${ISO_DIR}/efi/boot"
  docker_cp "$BUILDER:/usr/lib/grub/x86_64-efi" "$ISO_DIR/boot/grub"
  rm -f "$ISO_DIR/grub/x86_64-efi"/*.img
  # -O x86_64-efi                     Format of the image to generate
  # -p /boot/grub                     Directory to find grub once booted
  # -d "$BUILDER_DIR/usr/lib/grub/x86_64-efi"  Use resources from this location when building the boot image
  # -o "$ISO_DIR/efi/boot/bootx64.efi"      Output destination, using wellknown compatibility location
  cat <<EOF | docker exec --privileged -i ${BUILDER} sudo -u build bash
  grub-mkimage -O x86_64-efi -p /boot/grub -d /usr/lib/grub/x86_64-efi -o \
    "$CONT_ISO_DIR/efi/boot/bootx64.efi" disk part_msdos part_gpt linux linux16 loopback normal \
    configfile test search search_fs_uuid search_fs_file true iso9660 search_label efi_uga \
    efi_gop gfxterm gfxmenu gfxterm_menu ext2 ntfs cat echo ls memdisk tar
EOF
  check
}

# Build the initramfs based installer
build_installer()
{
  echo -en "${yellow}:: Stage files for building initramfs based installer...${none}"
  docker_run ${BUILDER}
  docker_cp "${INSTALLER_DIR}/installer" "$BUILDER:/usr/lib/initcpio/hooks"
  docker_cp "${INSTALLER_DIR}/installer.conf" "$BUILDER:/usr/lib/initcpio/install/installer"
  docker_cp "${INSTALLER_DIR}/mkinitcpio.conf" "$BUILDER:/etc"

  # Build a sorted array of kernels such that the first is the newest
  echo -en "${yellow}:: Build the initramfs based installer...${none}"
  local kernels=($(docker_exec ${BUILDER} "ls /lib/modules | sort -r | tr '\n' ' '"))
  docker_exec ${BUILDER} "mkinitcpio -k ${kernels[0]} -g /root/installer"
  check

  docker_cp "$BUILDER:/root/installer" "$ISO_DIR/boot"
}

# Build deployments
build_deployments() 
{
  echo -e "${yellow}:: Building deployments${none} ${cyan}${1}${none}..."
  docker_run ${BUILDER}
  docker_exec ${BUILDER} "mkdir -p ${CONT_WORK_DIR} ${CONT_ROOT_DIR} ${CONT_IMAGES_DIR}"

  # Iterate over the deployments
  for target in ${1//,/ }; do
    read_deployment $target
    echo -e ":: Building deployment ${cyan}${target}${none} composed of ${cyan}${LAYERS_STR}${none}"

    # Build each of the deployment's layers
    for i in "${!LAYERS[@]}"; do
      local layer="${LAYERS[$i]}"
      echo -e ":: Building layer ${cyan}${layer}${none}..."

      # Ensure the layer destination path exists and is owned by root to avoid warnings
      local layer_dir="${LAYERS_DIR}/${layer}"
      local cont_layer_dir="${CONT_LAYERS_DIR}/${layer}"                  # e.g. /home/build/layers/stanard/core
      local cont_layer_image_dir="${CONT_IMAGES_DIR}/$(dirname ${layer})" # e.g. /home/build/iso/images/standard
      docker_exec ${BUILDER} "mkdir -p ${cont_layer_dir} ${cont_layer_image_dir}"

      # Mount the layer destination path 
      if [ ${i} -eq 0 ]; then
        echo -en ":: Bind mount layer ${cyan}${cont_layer_dir}${none} to ${cyan}${CONT_ROOT_DIR}${none}..."
        docker_exec ${BUILDER} "mount --bind $cont_layer_dir $CONT_ROOT_DIR"
        check
      else
        # `upperdir` is a writable layer at the top
        # `lowerdir` is a colon : separated list of read-only dirs the right most is the lowest
        # `workdir`  is an empty dir used to prepare files and has to be on the same file system as upperdir
        # the last param is the merged or resulting filesystem after layering to work with
        echo -en ":: Mounting layer ${cyan}${cont_layer_dir}${none} over ${cyan}${CONT_ROOT_DIR}${none}..."
        docker_exec ${BUILDER} "mount -t overlay overlay -o lowerdir=${CONT_ROOT_DIR},upperdir=${cont_layer_dir},workdir=${CONT_WORK_DIR} ${CONT_ROOT_DIR}"
        check
      fi

      # Install target package if necessary
      if [ "$(ls "${layer_dir}")" != "" ]; then
        echo -e ":: Skipping install layer ${cyan}${cont_layer_dir}${none} already exists"
      else
        local pkg="cyberlinux-${layer//\//-}" # Derive the package name from 'profile/layer' string given
        echo -e ":: Installing target layer package ${cyan}${pkg}${none} to root ${cyan}${CONT_ROOT_DIR}${none}"
        # -c use the package cache on the host rather than target
        # -G avoid copying the host's pacman keyring to the target
        # -M avoid copying the host's mirrorlist to the target
        docker_exec ${BUILDER} "pacstrap -c -G -M ${CONT_ROOT_DIR} $pkg"
        check
      fi
    done

    # Release the root mount point now that we have fully built the required layers
    echo -en ":: Releasing overlay ${cyan}${CONT_ROOT_DIR}${none}..."
    docker_exec ${BUILDER} "umount -fR $CONT_ROOT_DIR"
    check

    # Compress each built layer into a deliverable image
    for i in "${!LAYERS[@]}"; do
      local layer="${LAYERS[$i]}"
      local cont_layer_dir="${CONT_LAYERS_DIR}/${layer}"
      local cont_layer_image="${CONT_IMAGES_DIR}/${layer}.sqfs" # e.g.  iso/images/standard/core.sqfs
      if [ -f "${IMAGES_DIR}/${layer}.sqfs" ]; then
        echo -e ":: Squashfs image ${cyan}${cont_layer_image}${none} already exists"
      else
        echo -en ":: Compressing layer ${cyan}${cont_layer_dir}${none} into ${cyan}${cont_layer_image}${none}..."
        # Stock settings pulled from ArchISO
        # -noappend           // overwrite destination image rather than adding to it
        # -b 1M               // use a larger block size for higher performance
        # -comp xz -Xbcj x86  // use xz compression with x86 filter for best compression
        docker_exec ${BUILDER} "mksquashfs ${cont_layer_dir} ${cont_layer_image} -noappend -b 1M -comp xz -Xbcj x86"
        check
      fi
    done
  done
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
#   -o cyberlinux.iso "$ISO_DIR"
build_iso()
{
  echo -e "${yellow}:: Building an ISOHYBRID bootable image...${none}"
  docker_run ${BUILDER}
  cat <<EOF | docker exec --privileged -i ${BUILDER} sudo -u build bash
  cd ~/
  xorriso -as mkisofs \
    -r -iso-level 3 \
    -volid CYBERLINUX_INSTALLER \
    --modification-date=$(date -u +%Y%m%d%H%M%S00) \
    -graft-points \
    -no-emul-boot \
    -boot-info-table \
    --protective-msdos-label \
    -b /boot/grub/i386-pc/eltorito.img \
    --embedded-boot "$CONT_ISO_DIR/boot/grub/i386-pc/isohybrid.img" \
    --efi-boot /efi/boot/bootx64.efi \
    -o $CONT_OUTPUT_DIR/cyberlinux.iso "$CONT_ISO_DIR"
EOF
  check
}

# Clean the various build artifacts as called out
clean()
{
  docker_kill ${BUILDER}

  for x in ${1//,/ }; do
    local target="${TEMP_DIR}/${x}"

    # Clean everything not covered in other specific cases
    if [ "${x}" == "all" ]; then
      target="${TEMP_DIR}"
      echo -e "${yellow}:: Cleaning docker image ${cyan}archlinux:base-devel${none}"
      docker_rmi archlinux:base-devel
    fi

    # Clean the builder docker image
    if [ "${x}" == "all" ] || [ "${x}" == "${BUILDER}" ]; then
      echo -e "${yellow}:: Cleaning docker image ${cyan}${BUILDER}${none}"
      docker_rmi ${BUILDER}
    fi

    # Clean the squashfs staged images from temp/iso/images if layer called out
    if [ "${x}" == "all" ] || [ "${x%%/*}" == "layers" ]; then
      local layer_image="${IMAGES_DIR}/${x#*/}.sqfs" # e.g. .../images/standard/core.sqfs
      echo -e "${yellow}:: Cleaning sqfs layer image${none} ${cyan}${layer_image}${none}"
      sudo rm -f "${layer_image}"
    fi

    echo -e "${yellow}:: Cleaning build artifacts${none} ${cyan}${target}${none}"
    sudo rm -rf "${target}"
  done
}

check()
{
  if [ $? -ne 0 ]; then
    echo -e "${red}failed!${none}"
    exit 1
  else
    echo -e "${green}success!${none}"
  fi
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
  LAYERS=($(echo ${LAYERS_STR} | tr ',' ' '))
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
docker_image_exists() {
  docker image inspect -f {{.Metadata.LastTagTime}} $1 &>/dev/null
}

# Check if the given docker container is running
# $1 container to check
docker_container_running() {
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
  if docker_image_exists ${1}; then
    echo -en ":: Removing the given image ${cyan}${1}${none}..."
    docker image rm $1
    check
  fi
}

# Pull the builder container if it doesn't exist then run it in a sleep loop so we can work with
# it in parallel. We'll need to wait until it is ready and manage its lifecycle
# $1 container repository:tag combo to run
# $2 additional params to include e.g. "-v "${REPO_DIR}":/var/cache/builder"
docker_run() {
  docker_container_running ${BUILDER} && return
  echo -en ":: Running docker container in loop: ${cyan}${1}${none}..."
  
  # Docker will need additional privileges to allow mount to work inside a container
  local params="-e TERM=xterm -v /var/run/docker.sock:/var/run/docker.sock --privileged"

  # Run a sleep loop for as long as we need to
  # -d means run in detached mode so we don't block
  # -v is used to mount a directory into the container to cache all the packages.
  #    also using it to mount the custom repo into the container
  docker run -d --name ${BUILDER} --rm ${params} ${2} \
    -v "${ISO_DIR}":"${CONT_ISO_DIR}" \
    -v "${REPO_DIR}":"${CONT_REPO_DIR}" \
    -v "${CACHE_DIR}":"${CONT_CACHE_DIR}" \
    -v "${LAYERS_DIR}":"${CONT_LAYERS_DIR}" \
    -v "${OUTPUT_DIR}":"${CONT_OUTPUT_DIR}" \
    -v "${PROFILES_DIR}":"${CONT_PROFILES_DIR}" \
    $1 bash -c "while :; do sleep 5; done" &>/dev/null
  check

  # Now wait until it responds to commands
  while ! docker_container_running ${BUILDER}; do sleep 2; done
}

# Kill the running container using its wellknown name
# $1 container name to kill
docker_kill() {
  if docker_container_running ${1}; then
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
  echo -e "  -a               Build all components"
  echo -e "  -b               Build the builder filesystem"
  echo -e "  -d DEPLOYMENTS   Build deployments, comma delimited (all|shell|lite)"
  echo -e "  -i               Build the initramfs installer"
  echo -e "  -m               Build the grub multiboot environment"
  echo -e "  -I               Build the acutal ISO image"
  echo -e "  -P               Build packages for deployment/s and/or profile"
  echo -e "  -p               Set the profile to use (default: standard)"
  echo -e "  -c               Clean build artifacts, commad delimited (all|builder|iso|layers/standard/core)"
  echo -e "  -h               Display usage help\n"
  echo -e "Examples:"
  echo -e "  ${green}Build everything:${none} ./${SCRIPT} -a"
  echo -e "  ${green}Build shell deployment:${none} ./${SCRIPT} -d shell"
  echo -e "  ${green}Build just bootable installer:${none} ./${SCRIPT} -imI"
  echo -e "  ${green}Build packages for standard profile:${none} ./${SCRIPT} -p standard -P"
  echo -e "  ${green}Build standard base:${none} ./${SCRIPT} -p standard -d base"
  echo -e "  ${green}Clean standard core,base layers:${none} ./${SCRIPT} -c layers/standard/core,layers/standard/base"
  echo -e "  ${green}Rebuild builder, multiboot and installer:${none} ./${SCRIPT} -c all -p standard -b -m -i"
  echo -e "  ${green}Don't automatically destroy the build container:${none} RELEASED=1 ./${SCRIPT} -p standad -d base"
  echo
  RELEASED=1
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

# Default profile if not set
[ -z ${PROFILE+x} ] && PROFILE=standard
read_profile "$PROFILE"

# Optionally clean artifacts
[ ! -z ${CLEAN+x} ] && clean $CLEAN
make_env_directories

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
  [ -z ${DEPLOYMENTS+x} ] && echo -e "Error: ${red}missing deployment value${none}" && exit
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
