#!/usr/bin/env bash

# Enable safe script execution mode and display a message with the line number in case of an error.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# Creates a short command to install packages via pacman without confirmations.
PAC="sudo pacman -S --needed --noconfirm"
REFRESH() { sudo pacman -Syyu --noconfirm; }

# Updates package signing keys, enables multilib repository (if commented out).
# We do this to enable multilib repository, which is needed to install 32-bit libraries.
# Some games, applications, and emulators (e.g. Steam, Proton, Wine) use 32-bit components, even on 64-bit systems.
echo "==> Оновлюємо ключі та вмикаємо multilib (якщо закоментовано)"
sudo pacman -S --needed --noconfirm archlinux-keyring
sudo sed -i -E 's/^\s*#\s*\[multilib\]/[multilib]/' /etc/pacman.conf
sudo sed -i -E '/^\s*\[multilib\]/ {n; s/^\s*#\s*Include\s*=.*/Include = \/etc\/pacman.d\/mirrorlist/}' /etc/pacman.conf
sudo pacman -Syy --noconfirm

# Installs the necessary packages for building and compiling from AUR (git, base-devel, dkms).
echo "==> Basic tools for building AUR"
$PAC git base-devel dkms

# Checks which kernel is installed (linux or linux-zen) and installs the appropriate headers for it.
# Required for kernel modules that are compiled manually or via DKMS (e.g. NVIDIA drivers, VirtualBox, Wi-Fi modules, etc.) to work correctly.
# Without kernel headers, such modules will not be able to compile under your current version of Linux.
echo "==> Installing kernel headers"
if pacman -Q linux &>/dev/null; then $PAC linux-headers; fi
if pacman -Q linux-zen &>/dev/null; then $PAC linux-zen-headers; fi

# Checks if yay is installed.
# If not, downloads it from the AUR, compiles it, and installs it for further work with AUR packages.
# yay is an AUR helper, a tool for conveniently installing and updating packages from the AUR, just like pacman.
echo "==> Installing/updating yay"
if ! command -v yay >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  git clone https://aur.archlinux.org/yay.git "$tmp/yay"
  pushd "$tmp/yay"
  makepkg -si --noconfirm
  popd
  rm -rf "$tmp"
fi

# A function that updates the package database and all installed system packages.
echo "==> System update"
REFRESH

# Installs NVIDIA drivers, Vulkan libraries (32- and 64-bit), graphics testing utilities, and the CUDA package for working with GPUs.
echo "==> GPU (NVIDIA + Vulkan + CUDA)"
$PAC nvidia nvidia-utils lib32-nvidia-utils nvidia-settings \
     vulkan-icd-loader lib32-vulkan-icd-loader vulkan-tools mesa-utils cuda

# KMS for NVIDIA
# Creates a configuration file for the NVIDIA module and enables modeset to ensure the GUI and Wayland work correctly.
sudo tee /etc/modprobe.d/nvidia.conf >/dev/null <<'EOF'
options nvidia_drm modeset=1
EOF

# (Optional) Early KMS: modules in mkinitcpio and rebuild initramfs.
# Adds NVIDIA modules to mkinitcpio.conf (if not already present) and updates initramfs so drivers are loaded at boot time.
# The initramfs is the “preparatory phase” of Linux booting, allowing the kernel to access disks, drivers, and the file system before the system is fully booted.
if ! grep -q 'nvidia_drm' /etc/mkinitcpio.conf; then
  sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
fi
sudo mkinitcpio -P

# Determines the processor type (Intel or AMD) and installs the appropriate microcode to fix bugs and improve system stability.
echo "==> CPU microcode"
if grep -qi 'GenuineIntel' /proc/cpuinfo; then
  $PAC intel-ucode
else
  $PAC amd-ucode
fi

# If GRUB is used, updates its configuration to apply changes (such as a new kernel or drivers).
# GRUB is the Linux boot loader that starts the kernel and allows you to select a system when the computer starts.
if [ -d /boot/grub ] && command -v grub-mkconfig >/dev/null; then
  sudo grub-mkconfig -o /boot/grub/grub.cfg
fi

# Installs and enables the power-profiles-daemon service, which manages power consumption and allows you to switch performance modes.
echo "==> Power management"
$PAC power-profiles-daemon
sudo systemctl enable --now power-profiles-daemon

# Sets and enables cpupower to control CPU frequency, setting the mode to “performance” for maximum performance.
$PAC cpupower || true
sudo systemctl enable --now cpupower.service || true
sudo bash -c 'echo governor="performance" > /etc/default/cpupower' || true

# Installs the core components of the KDE Plasma environment - desktop, terminal, file manager, system settings, and Wayland support.
echo "==> KDE Plasma (minimal set + Wayland)"
$PAC plasma-desktop konsole dolphin systemsettings kscreen \
     plasma-workspace xorg-xwayland xdg-desktop-portal-kde kwalletmanager

# Installs and enables SDDM - a login manager for graphical user authorization.
echo "==> SDDM"
$PAC sddm
sudo systemctl enable sddm.service

# Installs Wayland support for applications using Qt5 and Qt6 so that they run correctly in the Wayland environment.
echo "==> To make Plasma on Wayland have fewer artifacts in third-party Qt applications"
$PAC qt6-wayland qt5-wayland

# Sound
# Installs PipeWire with PulseAudio and ALSA support, as well as WirePlumber, a session manager for managing audio and video streams.
echo "==> Audio (PipeWire + instruments)"
$PAC pipewire pipewire-pulse pipewire-alsa wireplumber
# Key point: we install pipewire-jack and at the same time agree to remove jack2 if it suddenly comes up
# Replaces jack2 with pipewire-jack to ensure compatibility of programs with JACK via PipeWire.
sudo pacman -S --needed --noconfirm pipewire-jack || sudo pacman -R --noconfirm jack2 && sudo pacman -S --needed --noconfirm pipewire-jack
# Installs sound management utilities: ALSA, PulseAudio, KDE Plasma module, as well as Helvum and EasyEffects for audio and effects customization.
$PAC alsa-utils pavucontrol plasma-pa helvum easyeffects
# Creates a custom PipeWire settings file that sets high-quality audio settings (up to 192 kHz) for better sound and stability.
mkdir -p ~/.config/pipewire/pipewire.conf.d
cat > ~/.config/pipewire/pipewire.conf.d/99-HiFi.conf <<'EOF'
context.properties = {
    default.clock.rate          = 192000 
    default.clock.allowed-rates = [ 44100 48000 88200 96000 176400 192000 352800 384000 ]
    default.clock.quantum       = 1024
    default.clock.min-quantum   = 1024
    default.clock.max-quantum   = 1024
}
EOF
# Enables and starts the PipeWire, PulseAudio services via PipeWire and WirePlumber for full operation of the user's audio system.
systemctl --user enable --now pipewire pipewire-pulse wireplumber || true

echo "==> Installing Chrome"
yay -S --needed --noconfirm google-chrome

echo "==> Installing Firefox"
$PAC firefox

# Installs gaming tools (Steam, Gamescope, Gamemode, MangoHud) and enables Gamemode to automatically optimize performance while gaming.
echo "==> Games"
$PAC steam gamescope gamemode lib32-gamemode mangohud lib32-mangohud
systemctl --user enable --now gamemoded

echo "==> OBS / Telegram"
$PAC obs-studio telegram-desktop
yay -S --needed --noconfirm obs-pipewire-audio-capture pavucontrol

echo "==> Photo/Video players + codecs"
$PAC gwenview vlc mpv ffmpeg gst-libav gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly

echo "==> Music / Spotify / VS Code"
yay -S --needed --noconfirm deadbeef spotify visual-studio-code-bin

# Installs and configures Zoom and v4l2loopback, a kernel module that creates a virtual camera for OBS or other applications, and adds it to the system startup.
echo "==> Zoom + Virtual Camera"
yay -S --needed --noconfirm zoom v4l2loopback-dkms
sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="VirtualCam" exclusive_caps=1 || true
echo v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf
sudo tee /etc/modprobe.d/v4l2loopback.conf >/dev/null <<'EOF'
options v4l2loopback devices=1 video_nr=10 card_label="VirtualCam" exclusive_caps=1
EOF

echo "==> Discord & Torrent"
$PAC discord qbittorrent

# Installs Digimend drivers via DKMS to support graphics tablets that do not have official Linux drivers.
echo "==> Installing Digimend tablet drivers (DKMS)"
yay -S --needed --noconfirm digimend-kernel-drivers-dkms

# Installs Krita and GIMP - tools for digital painting, image editing, and graphics work.
echo "==> Installing Gimp & Krita"
$PAC krita gimp

# Installs basic applications (Kate, Spectacle) and fonts for correct display of text and emoji.
echo "==> Utilities, fonts, user directories"
$PAC kate spectacle xdg-user-dirs ttf-dejavu ttf-liberation noto-fonts noto-fonts-cjk noto-fonts-emoji

# Creates standard user folders (Documents, Downloads, etc.).
xdg-user-dirs-update

# Installs LibreOffice with Ukrainian and English support, dictionaries, word hyphenation, and popular fonts (including Microsoft fonts) for full document compatibility.
echo "==> Installing libreoffice and additional fonts"
$PAC libreoffice-fresh libreoffice-fresh-uk hunspell hunspell-en_US hyphen hyphen-en \
  ttf-dejavu ttf-liberation noto-fonts ttf-carlito ttf-caladea
yay -S --needed --noconfirm ttf-ms-fonts
yay -S --needed --noconfirm ttf-calibri
yay -S --needed --noconfirm hunspell-uk

echo "Done! Reboot if necessary to apply kernel modules."
