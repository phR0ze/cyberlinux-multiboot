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
ISO=iso       # Build location for staging iso files
TEMP=temp     # Temp location for installing packages for extraction
GRUB=grub     # Location for persisted Grub configuration files
BOOT_CFG="iso/boog/grub/boot.cfg"
echo -e ":: Configuring build environment..."
rm -rf $ISO
#rm -rf $TEMP
mkdir -p $TEMP
mkdir -p $ISO/boot/grub

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

# 3. Install GRUB theme
# -------------------------------------------------------------------------------------------------
echo -en ":: Installing GRUB theme ..."
mkdir -p $ISO/boot/grub/themes
sudo pacstrap -c -G -M $TEMP coreutils pacman grub
check
cp $GRUB/grub.cfg $ISO/boot/grub
cp $GRUB/loopback.cfg $ISO/boot/grub
cp -r $GRUB/themes $ISO/boot/grub
cp $TEMP/usr/share/grub/unicode.pf2 $ISO/boot/grub

# 4. Install kernel, intel ucode patch and memtest
# -------------------------------------------------------------------------------------------------
echo -en ":: Installing kernel, intel ucode patch and memtest..."
sudo pacstrap -c -G -M $TEMP sed linux intel-ucode memtest86+
check
#cp $TEMP/boot/intel-ucode.img $ISO/boot
#cp $TEMP/boot/vmlinuz-linux.img $ISO/boot
cp $TEMP/boot/memtest86+/memtest.bin $ISO/boot/memtest

# 5. Install BIOS boot files
# -------------------------------------------------------------------------------------------------
#echo -en ":: Installing BIOS boot files..."
#cp -r $TEMP/usr/lib/grub/i386-pc $ISO/boot/grub
#rm -f $ISO/boot/grub/i386-pc/*.img
#grub-mkimage -O i386-pc -d $ISO/boot/grub/i386-pc -o bios.img -p /boot/grub iso9660 part_gpt ext2
#cat $TEMP/usr/lib/grub/i398-pc/cdboot.img 
#check

# 6. Install UEFI boot files
# /EFI/BOOT/BOOTX64.EFI is a well known boot file location for compatibility
# -------------------------------------------------------------------------------------------------
echo -en ":: Installing UEFI boot files..."
mkdir -p $ISO/EFI/BOOT
GRUB_MODULES="fat efi_gop efi_uga iso9960 part_gpt ext2"
#cp -r $TEMP/usr/lib/grub/x86_64-efi $ISO/grub
#rm -f $ISO/grub/x86_64-efi/*.img
grub-mkimage -O x86_64-efi -d $TEMP/usr/lib/grub/x86_64-efi -o $ISO/EFI/BOOT/BOOTX64.EFI -p /boot/grub ${GRUB_MODULES}
check

# 7. Build the ISO
# -------------------------------------------------------------------------------------------------
echo -en ":: Building ISO..."

# Use -a mkisofs to support options like grub-mkrescue does
xorriso -as mkisofs \
  # YYYYMMDDhhmmsscc format
  --modification-date=$(date +%Y%m%d%k%M%S) \
  # Identifier installer will use to find the install medium
  -volid CYBERLINUX \
  # GRUB2 requires this
  -no-emul-boot \
  # GRUB2 write boot info table into boot image
  -boot-info-table \
  # Boot from USB
  #--embedded-boot 
  #--protecteive-msdos-label
  --efi-boot /EFI/BOOT/BOOTX64.EFI \
  # Use Rock Ridge and best iso level for standard USB/CDROM compatibility
  -r -iso-level 3 \
  # Specify the output iso file path and location to turn into an ISO
  -o boot.iso $ISO
check
