FROM archlinux:base-devel

# Copy of configuration
ADD profiles/standard/core /
ADD temp/cache /var/cache/pacman/pkg
COPY profiles/standard/core/etc/skel /root
COPY config/pacman.builder /etc/pacman.conf
COPY config/mkinitcpio.conf /etc/mkinitcpio.conf

# New user is created with:
# -r            to not create a mail directory
# -m            to create a home directory from /etc/skel
# -u            to use a specific user id
# -g            calls out the user's primary group created with a specific group id
# --no-log-init to avoid an unresolved Go archive/tar bug with docker
RUN echo ">> Install builder packages" && \
  mkdir -p /root/repo /root/profiles && \
  pacman -Sy --noconfirm vim grub dosfstools mkinitcpio mkinitcpio-vt-colors rsync gptfdisk \
    linux intel-ucode memtest86+ libisoburn linux-firmware && \
  echo ">> Add the build user" && \
  groupadd -g 1000 build && \
  useradd --no-log-init -r -m -u 1000 -g build build && \
  echo "build ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Update the pacman config after we installed the target packages so that future runs
# will use the custom repo were going to build at /home/build/repo
COPY config/pacman.conf /etc/pacman.conf
