#!/bin/bash
none="\e[m"
red="\e[1;31m"
cyan="\e[0;36m"

check()
{
  if [ $? -ne 0 ]; then
    echo -e "${red}failed!${none}"
    exit 1
  else
    echo -e "${cyan}success!${none}"
  fi
}

# 1. Setup the build environment
# -------------------------------------------------------------------------------------------------
ISO=iso       # Build location for staging iso/boot files
TEMP=temp     # Temp location for installing packages for extraction
GRUB=grub     # Location to pull persisted Grub configuration files from
BOOT_CFG="${ISO}/boot/grub/boot.cfg"
echo -en ":: Configuring build environment..."
rm -rf $ISO
#rm -rf $TEMP
mkdir -p $TEMP
mkdir -p $ISO/boot/grub
check

# 2. Create the GRUB menu items
# Pass through options as kernel paramaters
# -------------------------------------------------------------------------------------------------
#echo -e ":: Creating ${cyan}${ISO}/boot/grub/boot.cfg${none} ..."
#echo -e "menuentry --class=deployment 'Start cyberlinux recovery' {" >> ${BOOT_CFG}
#echo -e "  load_video" >> ${BOOT_CFG}
#echo -e "  set gfxpayload=keep" >> ${BOOT_CFG}
#echo -e "  linux	/boot/vmlinuz-linux efi=0 layers=shell,lite autologin=1" >> ${BOOT_CFG}
#echo -e "  initrd	/boot/intel-ucode.img /boot/initramfs-linux.img" >> ${BOOT_CFG}
#echo -e "}" >> ${BOOT_CFG}

# 3. Install GRUB config and theme
# -------------------------------------------------------------------------------------------------
if [ ! -d $TEMP ]; then
    echo -en ":: Installing GRUB and supporting utilities to ${TEMP} ..."
    sudo pacstrap -c -G -M $TEMP coreutils pacman grub
    check
fi
mkdir -p $ISO/boot/grub/themes
echo -en ":: Copying GRUB config and theme to ${ISO}/boot/grub ..."
cp $GRUB/grub.cfg $ISO/boot/grub
cp $GRUB/loopback.cfg $ISO/boot/grub
cp -r $GRUB/themes $ISO/boot/grub
cp $TEMP/usr/share/grub/unicode.pf2 $ISO/boot/grub
# Create early boot config for grub
cat > $ISO/boot/grub/load_cfg <<EOF
insmod part_acorn
insmod part_amiga
insmod part_apple
insmod part_bsd
insmod part_dvh
insmod part_gpt
insmod part_msdos
insmod part_plan
insmod part_sun
insmod part_sunpc
EOF
check

# 4. Install kernel, intel ucode patch and memtest
# -------------------------------------------------------------------------------------------------
if [ ! -d $TEMP ]; then
    echo -en ":: Installing kernel, intel ucode patch and memtest to ${TEMP}..."
    sudo pacstrap -c -G -M $TEMP sed linux intel-ucode memtest86+
    check
fi
echo -en ":: Copying kernel, intel ucode patch and memtest to ${ISO}/boot..."
#cp $TEMP/boot/intel-ucode.img $ISO/boot
#cp $TEMP/boot/vmlinuz-linux.img $ISO/boot
cp $TEMP/boot/memtest86+/memtest.bin $ISO/boot/memtest
check

# 5. Install BIOS boot files
# -------------------------------------------------------------------------------------------------
echo -en ":: Creating core BIOS $TEMP/bios.img..."
cp -r $TEMP/usr/lib/grub/i386-pc $ISO/boot/grub
rm -f $ISO/boot/grub/i386-pc/*.img
# We need to create our bios.img that contains just enough code to find the grub configuration and
# grub modules in /boot/grub/i386-pc directory we'll stage in the next step
# -O i386-pc                        Format of the image to generate
# -p /boot/grub                     Directory to find grub once booted
# -d $TEMP/usr/lib/grub/i386-pc     Use resources from this location when building the boot image
# -o $TEMP/bios.img                 Output destination
# iso9660                           Grub module to support reading your ISO9660 boot media
# biosdisk                          Grub module to support booting off live media
grub-mkimage -O i386-pc -p /boot/grub -d $TEMP/usr/lib/grub/i386-pc -o $TEMP/bios.img iso9660 biosdisk
check
echo -en ":: Concatenate cdboot.img to bios.img to create the CD-ROM bootable Eltorito $TEMP/eltorito.img..."
cat $TEMP/usr/lib/grub/i386-pc/cdboot.img $TEMP/bios.img > $ISO/boot/grub/i386-pc/eltorito.img
check
echo -en ":: Concatenate boot.img to bios.img to create isohybrid $TEMP/isohybrid.img..."
cat $TEMP/usr/lib/grub/i386-pc/boot.img $TEMP/bios.img > $ISO/boot/grub/i386-pc/isohybrid.img
check

# 6. Make bootable ISO
#grub-mkrescue \
#  # Use resources from this location when building the boot image
#  -d $TEMP/usr/lib/grub/x86_64-efi \
#  # Specify the output iso file path and location to turn into an ISO
#  -o boot.iso $ISO
#exit

# 6. Install UEFI boot files
# /efi/boot/bootx64.efi is a well known boot file location for compatibility
# -------------------------------------------------------------------------------------------------
#echo -en ":: Creating UEFI boot files..."
#mkdir -p $ISO/efi/boot
#cp -r $TEMP/usr/lib/grub/x86_64-efi $ISO/boot/grub
#rm -f $ISO/grub/x86_64-efi/*.img
## -O x86_64-efi                     Format of the image to generate
## -p /boot/grub                     Directory to find grub once booted
## -d $TEMP/usr/lib/grub/x86_64-efi  Use resources from this location when building the boot image
## -o $ISO/efi/boot/bootx64.efi      Output destination, using wellknown compatibility location
#grub-mkimage -O x86_64-efi -p /boot/grub -d $TEMP/usr/lib/grub/x86_64-efi -o $ISO/efi/boot/bootx64.efi \
#  disk part_msdos part_gpt linux linux16 loopback normal configfile test search search_fs_uuid \
#  search_fs_file true iso9660 search_label efi_uga efi_gop gfxterm gfxmenu gfxterm_menu ext2 \
#  ntfs cat echo ls memdisk tar
#check

# 7. Build the ISO
# -------------------------------------------------------------------------------------------------
echo -e ":: Building an ISOHYBRID bootable image..."

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
#   -b $TEMP/eltorito.img
# Patch an EL TORITO BOOT INFO TABLE into eltorito.img
#   -boot-info-table
# Bootable isohybrid image to make this iso USB stick bootable by BIOS
#   --embedded-boot $TEMP/isohybrid.img
# EFI boot image to use to make this iso USB stick bootable by UEFI
#   --efi-boot /efi/boot/bootx84.efi
# Specify the output iso file path and location to turn into an ISO
#   -o boot.iso $ISO
xorriso -as mkisofs \
    -r -iso-level 3 \
    -volid CYBERLINUX \
    --modification-date=$(date -u +%Y%m%d%H%M%S00) \
    -graft-points \
    -no-emul-boot \
    -boot-info-table \
    --protective-msdos-label \
    -b boot/grub/i386-pc/eltorito.img \
    --embedded-boot $ISO/boot/grub/i386-pc/isohybrid.img \
    -o boot.iso $ISO

# vim: ft=sh:ts=4:sw=4:sts=4
