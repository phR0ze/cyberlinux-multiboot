FROM archlinux:base-devel

# Copy of configuration
ADD profiles/standard/core /
ADD temp/cache /var/cache/pacman/pkg
COPY profiles/standard/core/etc/skel /root
COPY config/pacman.builder /etc/pacman.conf
COPY config/mkinitcpio.conf /etc/mkinitcpio.conf

RUN echo ">> Install builder packages" && \
  mkdir -p /root/repo /root/profiles && \
  pacman -Sy --noconfirm vim grub dosfstools mkinitcpio mkinitcpio-vt-colors rsync gptfdisk \
    linux intel-ucode \
  echo ">> Add the build user" && \
  groupadd build && \
  useradd -m -g build -G build -s /bin/bash build && \
  usermod -p build build && \
  echo "build ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

