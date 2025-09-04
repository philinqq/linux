#!/bin/bash
set -e

# Оновлюємо базу пакетів
sudo pacman -Syu

# Yay + GIT
sudo pacman -S --needed git base-devel
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
cd ..
rm -rf yay

# Драйвера GPU
sudo pacman -S nvidia nvidia-utils lib32-nvidia-utils nvidia-settings \
    vulkan-icd-loader lib32-vulkan-icd-loader vulkan-tools mesa-utils \
    cuda

echo "nvidia nvidia_modeset nvidia_uvm nvidia_drm" | sudo tee /etc/modules-load.d/nvidia.conf
sudo mkdir -p /etc/modprobe.d
echo "options nvidia_drm modeset=1" | sudo tee /etc/modprobe.d/nvidia.conf
sudo mkinitcpio -P

# Драйвера CPU (intel-ucode - якщо інтел)
sudo pacman -S amd-ucode

# Power Profile
sudo pacman -S power-profiles-daemon
sudo systemctl enable --now power-profiles-daemon

# Налаштування NVIDIA для максимальної продуктивності
nvidia-settings --assign [gpu:0]/GpuPowerMizerMode=1

# 2. Керування продуктивністю CPU
echo ">>> Встановлення cpupower..."
sudo pacman -S --noconfirm cpupower
echo ">>> Увімкнення та запуск cpupower.service..."
sudo systemctl enable --now cpupower.service
echo ">>> Встановлення governor = performance..."
sudo cpupower frequency-set -g performance
echo ">>> Запис у конфіг /etc/default/cpupower..."
sudo bash -c 'echo "governor=\"performance\"" > /etc/default/cpupower'
echo "✅ Готово! CPU тепер працює у режимі performance."


# KDE Plasmac
sudo pacman -S plasma-desktop konsole dolphin systemsettings kscreen

#Логін-менеджер SDDM
sudo pacman -S sddm
sudo systemctl enable sddm


# Звук
echo "=== Встановлюємо пакети для звуку ==="
sudo pacman -Syu --needed --noconfirm \
  pipewire pipewire-pulse pipewire-alsa pipewire-jack \
  wireplumber alsa-utils pavucontrol plasma-pa \
  helvum easyeffects pipewire-audio 

echo "=== Створюємо конфіг для Hi-Res (192 кГц) ==="
mkdir -p ~/.config/pipewire/pipewire.conf.d
cat << 'EOF' > ~/.config/pipewire/pipewire.conf.d/99-HiFi.conf
context.properties = {
    default.clock.rate          = 192000
    default.clock.allowed-rates = [ 44100 48000 88200 96000 176400 192000 352800 384000 ]
    default.clock.quantum       = 1024
    default.clock.min-quantum   = 1024
    default.clock.max-quantum   = 1024
}
EOF

echo "=== Вмикаємо сервіси PipeWire та WirePlumber ==="
systemctl --user enable --now pipewire pipewire-pulse wireplumber

echo "=== Перезапускаємо Plasma Shell (щоб з'явились налаштування звуку) ==="
systemctl --user restart plasma-plasmashell || true

echo "=== Перезапускаємо систему звуку ==="
systemctl --user restart pipewire pipewire-pulse wireplumber

echo "=== Готово! ==="
echo "Тепер відкрий 'System Settings → Audio' або 'pavucontrol' для керування звуком."
echo "Для Hi-Fi режиму у pavucontrol вибери профіль 'Pro Audio' для свого ЦАП."

# Google Chrome
yay -S google-chrome-stable

# Steam
sudo pacman -S steam gamescope

# OBS Studio
sudo pacman -S obs-studio

# Telegram
sudo pacman -S telegram-desktop

# Для перегляду фото 
# Gwenview (рідна для KDE, швидка) або nomacs (більш функціональна)
sudo pacman -S gwenview nomacs

# Для перегляду відео
# MPV - максимально якісний і легкий, але без графічного меню
# VLC - більш «важкий» ніж MPV, але має купу вбудованих кодеків 
# і власне меню для керування (еквалайзер, субтитри, потоки, плейлисти тощо)
sudo pacman -S vlc mpv
# Кодеки (обов’язково для відтворення всіх форматів)
sudo pacman -S ffmpeg gst-libav gst-plugins-ugly gst-plugins-good \
  gst-plugins-bad gst-plugins-base lib32-libva lib32-libvdpau lib32-libxv lib32-mesa \
  vlc-plugin-ffmpeg vlc-plugins-all vlc-plugin-upnp
vlc --reset-plugins-cache


# Для музики
yay -S deadbeef

# Spotify
yay -S spotify

# Visual Studio Code - версія з AUR з вбудованими розширеннями Microsoft
yay -S visual-studio-code-bin

# Zoom & v4l2loopback-dkms - для кращої якості відео
yay -S zoom
sudo pacman -S v4l2loopback-dkms

# Discord
sudo pacman -S discord

# Торрент
sudo pacman -S qbittorrent


# Драйвера для Gaomon S620 [малювання]
# Krita - найпопулярніша для художників, підтримує pen pressure, layers, PSD
# Gimp - аналог Photoshop, теж підтримує планшети
yay -S digimend-kernel-drivers-dkms
sudo pacman -S krita gimp


# Текстовий редактор Kate (рекомендований у KDE Plasma)
sudo pacman -S kate

# Програма для скріншотів
sudo pacman -S spectacle


# -----------------



#VLC:
sudo pacman -S vlc-plugins-all

#Архіватор:
sudo pacman -S ark

#Calculator:
sudo pacman -S gnome-calculator

#Bluetooth:
sudo pacman -S bluez bluez-utils bluez-deprecated-tools bluedevil
sudo systemctl enable --now bluetooth
yay -S xpadneo-dkms
sudo modprobe hid_xpadneo

#OBS audio:
yay -S obs-pipewire-audio-capture pavucontrol

#Doplphin:
sudo pacman -S ntfs-3g kio-admin

#GPU usage:
sudo pacman -S nvtop


#VM:

sudo pacman -Syy
sudo pacman -S archlinux-keyring
sudo pacman -S qemu virt-manager virt-viewer dnsmasq vde2 bridge-utils openbsd-netcat dmidecode
sudo pacman -S ebtables iptables
sudo pacman -S libguestfs
sudo systemctl enable libvirtd.service
sudo systemctl start libvirtd.service

nano /etc/libvirt/libvirtdd.conf > unux_sock_group = "libvirt" & unix_sock_rw_perms = "0770"

sudo usermod -a -G libvirt $(whoami)
newgrp libvirt

sudo systemctl restart libvirtd.service




