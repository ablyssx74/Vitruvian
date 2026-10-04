#!/bin/sh

# VOS_KERNEL_DEBS=<dir>: install the kernel from .debs built by
# build/scripts/kernel/build-cachyos-rt.sh instead of Debian's
# linux-image-rt-amd64 (amd64 only). Strips Debian's kernel packages from a
# package list; the custom ones are installed by vos_install_kernel_debs.
vos_use_custom_kernel() {
    [ -n "${VOS_KERNEL_DEBS:-}" ] && [ "$1" = "amd64" ]
}

vos_filter_kernel_pkgs() {
    _arch="$1"; shift
    if vos_use_custom_kernel "$_arch"; then
        # initramfs-tools normally arrives as a dependency of linux-image-*.
        printf '%s' "$*" | sed -e 's/linux-image-rt-amd64//g' \
            -e 's/linux-headers-rt-amd64//g' -e 's/$/ initramfs-tools/'
    else
        printf '%s' "$*"
    fi
}

# Install the custom kernel .debs into a chroot/rootfs mounted at $2.
vos_install_kernel_debs() {
    _arch="$1"; _root="$2"
    vos_use_custom_kernel "$_arch" || return 0
    ls "$VOS_KERNEL_DEBS"/linux-image-*.deb "$VOS_KERNEL_DEBS"/linux-headers-*.deb >/dev/null 2>&1 \
        || die "VOS_KERNEL_DEBS=$VOS_KERNEL_DEBS has no linux-image/linux-headers .debs (run build-cachyos-rt.sh)"
    log_step "Installing custom kernel from $VOS_KERNEL_DEBS..."
    sudo mkdir -p "$_root/kerneldebs"
    sudo cp "$VOS_KERNEL_DEBS"/linux-image-*.deb "$VOS_KERNEL_DEBS"/linux-headers-*.deb \
        "$VOS_KERNEL_DEBS"/linux-libc-dev_*.deb "$_root/kerneldebs/" 2>/dev/null || true
    chroot_isolated "$_root" /usr/bin/env DEBIAN_FRONTEND=noninteractive /bin/bash -c "\
dpkg -i /kerneldebs/*.deb && rm -rf /kerneldebs" \
        || die "custom kernel install failed"
}

get_base_packages() {
    _arch="$1"
    case "$_arch" in
        amd64)
            printf '%s' \
                "apt-utils dialog linux-image-rt-amd64 systemd-sysv" \
                " polkitd pkexec sudo dbus-user-session" \
                " network-manager modemmanager bluez bluez-obexd net-tools wireless-tools wireless-regdb wpasupplicant rfkill curl openssh-client" \
                " procps vim-tiny libbinutils openssh-server locales libnss-myhostname xdg-user-dirs ca-certificates iputils-ping linux-sysctl-defaults xfsprogs" \
                " fdisk e2fsprogs btrfs-progs cryptsetup dosfstools" \
                " fortune-mod ncurses-bin rsync" \
                " pipewire-audio pipewire-bin wireplumber libsdl2-2.0-0 libglu1-mesa libcurl4t64 gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav" \
                " cups cups-filters printer-driver-gutenprint printer-driver-cups-pdf" \
                " firmware-iwlwifi firmware-atheros firmware-realtek firmware-libertas firmware-brcm80211 firmware-misc-nonfree" \
                " firmware-intel-graphics firmware-amd-graphics firmware-nvidia-graphics firmware-mediatek bluez-firmware" \
                " firmware-sof-signed firmware-intel-sound firmware-cirrus intel-microcode amd64-microcode" \
                " firmware-ti-connectivity firmware-intel-misc firmware-samsung firmware-siano firmware-zd1211 firmware-ath9k-htc firmware-carl9170" \
                " grub-common grub2-common grub-efi-amd64-bin grub-efi-ia32-bin grub-pc-bin"
            ;;
        arm64)
            printf '%s' \
                "apt-utils dialog linux-image-arm64 systemd-sysv" \
                " polkitd pkexec sudo dbus-user-session" \
                " network-manager modemmanager bluez bluez-obexd net-tools wireless-tools wireless-regdb wpasupplicant rfkill curl openssh-client" \
                " procps vim-tiny libbinutils openssh-server locales libnss-myhostname xdg-user-dirs ca-certificates iputils-ping linux-sysctl-defaults xfsprogs" \
                " fdisk e2fsprogs btrfs-progs cryptsetup dosfstools" \
                " fortune-mod ncurses-bin rsync" \
                " pipewire-audio pipewire-bin wireplumber libsdl2-2.0-0 libglu1-mesa libcurl4t64 gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav" \
                " cups cups-filters printer-driver-gutenprint printer-driver-cups-pdf" \
                " grub-common grub2-common grub-efi-arm64-bin"
            ;;
        arm32)
            printf '%s' \
                "apt-utils dialog linux-image-armmp systemd-sysv" \
                " polkitd pkexec sudo dbus-user-session" \
                " network-manager modemmanager bluez bluez-obexd net-tools wireless-tools wireless-regdb wpasupplicant rfkill curl openssh-client" \
                " procps vim-tiny libbinutils openssh-server locales libnss-myhostname xdg-user-dirs ca-certificates iputils-ping linux-sysctl-defaults" \
                " fdisk e2fsprogs" \
                " fortune-mod ncurses-bin rsync" \
                " pipewire-audio pipewire-bin wireplumber libsdl2-2.0-0 libglu1-mesa libcurl4t64 gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav" \
                " cups cups-filters printer-driver-gutenprint printer-driver-cups-pdf" \
                " grub-common"
            ;;
        riscv64)
            printf '%s' \
                "apt-utils dialog linux-image-riscv64 systemd-sysv" \
                " polkitd pkexec sudo dbus-user-session" \
                " network-manager modemmanager bluez bluez-obexd net-tools wireless-tools wireless-regdb wpasupplicant rfkill curl openssh-client" \
                " procps vim-tiny libbinutils openssh-server locales libnss-myhostname xdg-user-dirs ca-certificates iputils-ping linux-sysctl-defaults xfsprogs" \
                " fdisk e2fsprogs btrfs-progs cryptsetup dosfstools" \
                " fortune-mod ncurses-bin rsync" \
                " pipewire-audio pipewire-bin wireplumber libsdl2-2.0-0 libglu1-mesa libcurl4t64 gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav" \
                " cups cups-filters printer-driver-gutenprint printer-driver-cups-pdf" \
                " grub-common grub2-common grub-efi-riscv64-bin"
            ;;
        *)
            die "No package list for architecture: $_arch"
            ;;
    esac
}

get_dev_packages() {
    _arch="$1"
    case "$_arch" in
        amd64)
            printf '%s' \
                "linux-headers-rt-amd64 pkg-config libc6-dev libcrypt-dev libstdc++-14-dev" \
                " libfreetype6-dev libicu-dev libcairo2-dev libcups2-dev libdrm-dev libinput-dev" \
                " libevdev-dev libseat-dev libudev-dev zlib1g-dev libgif-dev" \
                " libblkid-dev libbacktrace-dev libfl-dev libncurses-dev" \
                " libgl-dev libegl-dev libgbm-dev" \
                " libxkbcommon-dev libsystemd-dev libpam0g-dev libpwquality-dev" \
                " libgcrypt20-dev libapt-pkg-dev" \
                " libjpeg-dev libpng-dev libtiff-dev libwebp-dev libicns-dev" \
                " libpipewire-0.3-dev libspa-0.2-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev" \
                " libglu1-mesa-dev libsdl2-dev libcurl4-openssl-dev libnm-dev libbluetooth-dev"
            ;;
        arm64)
            printf '%s' \
                "linux-headers-arm64 pkg-config libc6-dev libcrypt-dev libstdc++-14-dev" \
                " libfreetype6-dev libicu-dev libcairo2-dev libcups2-dev libdrm-dev libinput-dev" \
                " libevdev-dev libseat-dev libudev-dev zlib1g-dev libgif-dev" \
                " libblkid-dev libbacktrace-dev libfl-dev libncurses-dev" \
                " libgl-dev libegl-dev libgbm-dev" \
                " libxkbcommon-dev libsystemd-dev libpam0g-dev libpwquality-dev" \
                " libgcrypt20-dev libapt-pkg-dev" \
                " libjpeg-dev libpng-dev libtiff-dev libwebp-dev libicns-dev" \
                " libpipewire-0.3-dev libspa-0.2-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev" \
                " libglu1-mesa-dev libsdl2-dev libcurl4-openssl-dev libnm-dev libbluetooth-dev"
            ;;
        arm32)
            printf '%s' \
                "linux-headers-armmp pkg-config libc6-dev libcrypt-dev libstdc++-14-dev" \
                " libfreetype6-dev libicu-dev libcairo2-dev libcups2-dev libdrm-dev libinput-dev" \
                " libevdev-dev libseat-dev libudev-dev zlib1g-dev libgif-dev" \
                " libblkid-dev libbacktrace-dev libfl-dev libncurses-dev" \
                " libgl-dev libegl-dev libgbm-dev" \
                " libxkbcommon-dev libsystemd-dev libpam0g-dev libpwquality-dev" \
                " libgcrypt20-dev libapt-pkg-dev" \
                " libjpeg-dev libpng-dev libtiff-dev libwebp-dev libicns-dev" \
                " libpipewire-0.3-dev libspa-0.2-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libglu1-mesa-dev libsdl2-dev libcurl4-openssl-dev libnm-dev libbluetooth-dev"
            ;;
        riscv64)
            printf '%s' \
                "linux-headers-riscv64 pkg-config libc6-dev libcrypt-dev libstdc++-14-dev" \
                " libfreetype6-dev libicu-dev libcairo2-dev libcups2-dev libdrm-dev libinput-dev" \
                " libevdev-dev libseat-dev libudev-dev zlib1g-dev libgif-dev" \
                " libblkid-dev libbacktrace-dev libfl-dev libncurses-dev" \
                " libgl-dev libegl-dev libgbm-dev" \
                " libxkbcommon-dev libsystemd-dev libpam0g-dev libpwquality-dev" \
                " libgcrypt20-dev libapt-pkg-dev" \
                " libjpeg-dev libpng-dev libtiff-dev libwebp-dev libicns-dev" \
                " libpipewire-0.3-dev libspa-0.2-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libglu1-mesa-dev libsdl2-dev libcurl4-openssl-dev libnm-dev libbluetooth-dev"
            ;;
        *)
            die "No dev package list for architecture: $_arch"
            ;;
    esac
}

get_iso_image_packages() {
    _arch="$1"
    case "$_arch" in
        amd64|arm64|arm32|riscv64)
            printf '%s' "live-boot"
            ;;
        *)
            die "No iso image package list for architecture: $_arch"
            ;;
    esac
}

get_raw_image_packages() {
    _arch="$1"
    case "$_arch" in
        amd64)
            printf '%s' \
                "systemd systemd-sysv dbus-user-session polkitd pkexec sudo accountsservice libpam-pwquality libpwquality-tools libpwquality-dev systemd-timesyncd locales console-setup keyboard-configuration xdg-user-dirs ca-certificates iputils-ping vim net-tools iproute2 openssh-server" \
                " linux-image-rt-amd64 grub-common grub2-common" \
                " grub-efi-amd64-bin grub-efi-ia32-bin grub-pc-bin xfsprogs"
            ;;
        arm64)
            printf '%s' \
                "systemd systemd-sysv dbus-user-session polkitd pkexec sudo accountsservice libpam-pwquality libpwquality-tools libpwquality-dev systemd-timesyncd locales console-setup keyboard-configuration xdg-user-dirs ca-certificates iputils-ping vim net-tools iproute2 openssh-server" \
                " linux-image-arm64 grub-common grub2-common grub-efi-arm64 grub-efi-arm64-bin xfsprogs"
            ;;
        arm32)
            printf '%s' \
                "systemd systemd-sysv dbus-user-session polkitd pkexec sudo accountsservice libpam-pwquality libpwquality-tools libpwquality-dev systemd-timesyncd locales console-setup keyboard-configuration xdg-user-dirs ca-certificates iputils-ping vim net-tools iproute2 openssh-server" \
                " linux-image-armmp xfsprogs"
            ;;
        riscv64)
            printf '%s' \
                "systemd systemd-sysv dbus-user-session polkitd pkexec sudo accountsservice libpam-pwquality libpwquality-tools libpwquality-dev systemd-timesyncd locales console-setup keyboard-configuration xdg-user-dirs ca-certificates iputils-ping vim net-tools iproute2 openssh-server" \
                " linux-image-riscv64 grub-common grub2-common grub-efi-riscv64 grub-efi-riscv64-bin xfsprogs"
            ;;
        *)
            die "No raw image package list for architecture: $_arch"
            ;;
    esac
}

# Board images get the same system as raw/ISO images minus GRUB, plus the board's own boot
# and firmware packages from _board_extra_packages.
get_board_packages() {
    _board="$1"
    case "$_board" in
        raspberry|rockchip|allwinner|beagle|nxp|amlogic) _bp_arch=arm64 ;;
        rpi-arm32|allwinner-h3|beaglebone) _bp_arch=arm32 ;;
        visionfive2|licheerv) _bp_arch=riscv64 ;;
        *) die "No board package list for: $_board" ;;
    esac
    get_base_packages "$_bp_arch" | tr ' ' '\n' | grep -v '^grub' | tr '\n' ' '
    _board_extra_packages "$_board"
}

_board_extra_packages() {
    _board="$1"
    case "$_board" in
        raspberry)
            printf '%s' \
                "systemd systemd-sysv dbus-user-session polkitd pkexec sudo accountsservice libpam-pwquality libpwquality-tools libpwquality-dev systemd-timesyncd locales console-setup keyboard-configuration xdg-user-dirs ca-certificates iputils-ping vim net-tools iproute2 openssh-server" \
                " linux-image-arm64 raspi-firmware dosfstools rsync firmware-brcm80211 bluez-firmware"
            ;;
        rpi-arm32)
            printf '%s' \
                "systemd systemd-sysv dbus-user-session polkitd pkexec sudo accountsservice libpam-pwquality libpwquality-tools libpwquality-dev systemd-timesyncd locales console-setup keyboard-configuration xdg-user-dirs ca-certificates iputils-ping vim net-tools iproute2 openssh-server" \
                " linux-image-armmp raspi-firmware dosfstools rsync firmware-brcm80211 bluez-firmware"
            ;;
        rockchip)
            printf '%s' \
                "systemd systemd-sysv dbus-user-session polkitd pkexec sudo accountsservice libpam-pwquality libpwquality-tools libpwquality-dev systemd-timesyncd locales console-setup keyboard-configuration xdg-user-dirs ca-certificates iputils-ping vim net-tools iproute2 openssh-server" \
                " linux-image-arm64 linux-headers-arm64 u-boot-rockchip dosfstools rsync"
            ;;
        allwinner)
            printf '%s' \
                "systemd systemd-sysv dbus-user-session polkitd pkexec sudo accountsservice libpam-pwquality libpwquality-tools libpwquality-dev systemd-timesyncd locales console-setup keyboard-configuration xdg-user-dirs ca-certificates iputils-ping vim net-tools iproute2 openssh-server" \
                " linux-image-arm64 linux-headers-arm64 u-boot-sunxi dosfstools rsync"
            ;;
        allwinner-h3)
            printf '%s' \
                "systemd systemd-sysv dbus-user-session polkitd pkexec sudo accountsservice libpam-pwquality libpwquality-tools libpwquality-dev systemd-timesyncd locales console-setup keyboard-configuration xdg-user-dirs ca-certificates iputils-ping vim net-tools iproute2 openssh-server" \
                " linux-image-armmp u-boot-sunxi dosfstools rsync"
            ;;
        beagle)
            printf '%s' \
                "systemd systemd-sysv dbus-user-session polkitd pkexec sudo accountsservice libpam-pwquality libpwquality-tools libpwquality-dev systemd-timesyncd locales console-setup keyboard-configuration xdg-user-dirs ca-certificates iputils-ping vim net-tools iproute2 openssh-server" \
                " linux-image-arm64 u-boot-sitara-binaries dosfstools rsync"
            ;;
        beaglebone)
            printf '%s' \
                "systemd systemd-sysv dbus-user-session polkitd pkexec sudo accountsservice libpam-pwquality libpwquality-tools libpwquality-dev systemd-timesyncd locales console-setup keyboard-configuration xdg-user-dirs ca-certificates iputils-ping vim net-tools iproute2 openssh-server" \
                " linux-image-armmp u-boot-beaglebone dosfstools rsync"
            ;;
        nxp)
            printf '%s' \
                "systemd systemd-sysv dbus-user-session polkitd pkexec sudo accountsservice libpam-pwquality libpwquality-tools libpwquality-dev systemd-timesyncd locales console-setup keyboard-configuration xdg-user-dirs ca-certificates iputils-ping vim net-tools iproute2 openssh-server" \
                " linux-image-arm64 dosfstools rsync"  # u-boot-imx is armhf-only
            ;;
        amlogic)
            printf '%s' \
                "systemd systemd-sysv dbus-user-session polkitd pkexec sudo accountsservice libpam-pwquality libpwquality-tools libpwquality-dev systemd-timesyncd locales console-setup keyboard-configuration xdg-user-dirs ca-certificates iputils-ping vim net-tools iproute2 openssh-server" \
                " linux-image-arm64 dosfstools rsync"
            # No Debian Amlogic U-Boot since bookworm; fip.sh builds the blob.
            ;;
        visionfive2)
            printf '%s' \
                "systemd systemd-sysv dbus-user-session polkitd pkexec sudo accountsservice libpam-pwquality libpwquality-tools libpwquality-dev systemd-timesyncd locales console-setup keyboard-configuration xdg-user-dirs ca-certificates iputils-ping vim net-tools iproute2 openssh-server" \
                " linux-image-riscv64 u-boot-starfive dosfstools rsync"
            ;;
        licheerv)
            printf '%s' \
                "systemd systemd-sysv dbus-user-session polkitd pkexec sudo accountsservice libpam-pwquality libpwquality-tools libpwquality-dev systemd-timesyncd locales console-setup keyboard-configuration xdg-user-dirs ca-certificates iputils-ping vim net-tools iproute2 openssh-server" \
                " linux-image-riscv64 dosfstools rsync"
            ;;
        *)
            die "No board package list for: $_board"
            ;;
    esac
}
