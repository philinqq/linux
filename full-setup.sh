#!/usr/bin/env bash
# -E — робить так, щоб trap ... ERR спрацьовував і всередині функцій/сабшелів
# -e — зупиняє скрипт, якщо будь-яка команда повернула помилку (exit≠0)
# -u — помилка, якщо звернувся до НЕвизначеної змінної (ловить друкарські помилки)
# -o pipefail — якщо в конвеєрі a | b | c впала a чи b, то вважаємо весь пайп фейлом (і не «маскуємо» помилки)

# trap ... ERR — це хук, що виконається при будь-якій помилці. У твоєму прикладі 
# він надрукує рядок, де впало ($LINENO), і завершить скрипт.
# Практична порада: коли очікуєш, що команда може падати (і це не критично), додавай || true, щоб не рвати скрипт.

set -Eeuo pipefail
trap 'echo "❌ Помилка на рядку $LINENO"; exit 1' ERR

PAC="sudo pacman -S --needed --noconfirm"
REFRESH() { sudo pacman -Syyu --noconfirm; }

echo "==> Оновлюємо ключі та вмикаємо multilib (якщо закоментовано)"
sudo pacman -S --needed --noconfirm archlinux-keyring
sudo sed -i -E 's/^\s*#\s*\[multilib\]/[multilib]/' /etc/pacman.conf
sudo sed -i -E '/^\s*\[multilib\]/ {n; s/^\s*#\s*Include\s*=.*/Include = \/etc\/pacman.d\/mirrorlist/}' /etc/pacman.conf
sudo pacman -Syy --noconfirm

echo "==> Базові інструменти для складання AUR"
$PAC git base-devel dkms

echo "==> Встановлюємо хедери ядра"
if pacman -Q linux &>/dev/null; then $PAC linux-headers; fi
if pacman -Q linux-zen &>/dev/null; then $PAC linux-zen-headers; fi

echo "==> Встановлюємо/оновлюємо yay"
if ! command -v yay >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  git clone https://aur.archlinux.org/yay.git "$tmp/yay"
  pushd "$tmp/yay"
  makepkg -si --noconfirm
  popd
  rm -rf "$tmp"
fi

echo "==> Оновлення системи"
REFRESH

echo "==> GPU (NVIDIA + Vulkan + CUDA)"
$PAC nvidia nvidia-utils lib32-nvidia-utils nvidia-settings \
     vulkan-icd-loader lib32-vulkan-icd-loader vulkan-tools mesa-utils cuda

# KMS для NVIDIA
sudo tee /etc/modprobe.d/nvidia.conf >/dev/null <<'EOF'
options nvidia_drm modeset=1
EOF

# (Опціонально) Ранній KMS: додай модулі у mkinitcpio і перебудуй initramfs:
if ! grep -q 'nvidia_drm' /etc/mkinitcpio.conf; then
  sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
fi
sudo mkinitcpio -P

echo "==> Мікрокод CPU"
if grep -qi 'GenuineIntel' /proc/cpuinfo; then
  $PAC intel-ucode
else
  $PAC amd-ucode
fi

# У мене використовується GRUB тому - оновлюємо конфіг:
if [ -d /boot/grub ] && command -v grub-mkconfig >/dev/null; then
  sudo grub-mkconfig -o /boot/grub/grub.cfg
fi

echo "==> Power management"
$PAC power-profiles-daemon
sudo systemctl enable --now power-profiles-daemon

# Опційно: cpupower (може ігноруватись на amd_pstate_epp)
$PAC cpupower || true
sudo systemctl enable --now cpupower.service || true
sudo bash -c 'echo governor="performance" > /etc/default/cpupower' || true

echo "==> KDE Plasma (мінімальний набір + Wayland)"
$PAC plasma-desktop konsole dolphin systemsettings kscreen \
     plasma-workspace xorg-xwayland xdg-desktop-portal-kde kwalletmanager

echo "==> SDDM"
$PAC sddm
sudo systemctl enable sddm.service

echo "==> Щоб Plasma на Wayland мала менше артефактів у сторонніх Qt-додатках"
$PAC qt6-wayland qt5-wayland

echo "==> Аудіо (PipeWire + інструменти)"
# базовий стек
$PAC pipewire pipewire-pulse pipewire-alsa wireplumber
# тут ключовий момент: ставимо pipewire-jack і одночасно погоджуємось видалити jack2, якщо він раптом підтягнувся
sudo pacman -S --needed --noconfirm pipewire-jack || sudo pacman -R --noconfirm jack2 && sudo pacman -S --needed --noconfirm pipewire-jack
# інструменти
$PAC alsa-utils pavucontrol plasma-pa helvum easyeffects

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

# Якщо треба буде закоментувати рядок default.clock.rate у 99-HiFi.conf
# systemctl --user restart pipewire pipewire-pulse wireplumber
systemctl --user enable --now pipewire pipewire-pulse wireplumber || true

echo "==> Браузер chrome"
yay -S --needed --noconfirm google-chrome

echo "==> Браузер firefox"
$PAC firefox

echo "==> Ігри"
$PAC steam gamescope gamemode lib32-gamemode mangohud lib32-mangohud
systemctl --user enable --now gamemoded

echo "==> OBS / Telegram"
$PAC obs-studio telegram-desktop

echo "==> Фото/Відео програвачі + кодеки"
$PAC gwenview vlc mpv ffmpeg gst-libav gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly
vlc --reset-plugins-cache || true

echo "==> Музика / Spotify / VS Code"
yay -S --needed --noconfirm deadbeef spotify visual-studio-code-bin

echo "==> Zoom + віртуальна камера"
yay -S --needed --noconfirm zoom v4l2loopback-dkms
sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="VirtualCam" exclusive_caps=1 || true
# автозавантаження модуля при старті (для постійної роботи віртуальної камери)
echo v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf
# параметри модуля (ті самі, що у твоєму modprobe)
sudo tee /etc/modprobe.d/v4l2loopback.conf >/dev/null <<'EOF'
options v4l2loopback devices=1 video_nr=10 card_label="VirtualCam" exclusive_caps=1
EOF

echo "==> Discord / Торрент"
$PAC discord qbittorrent

echo "==> Графічний планшет Gaomon (DKMS) + софт"
yay -S --needed --noconfirm digimend-kernel-drivers-dkms
$PAC krita gimp

echo "==> Утиліти, шрифти, каталоги користувача"
$PAC kate spectacle xdg-user-dirs ttf-dejavu ttf-liberation noto-fonts noto-fonts-cjk noto-fonts-emoji
xdg-user-dirs-update

echo "==> Встановлюємо libreoffice та додаткові шрифти"
$PAC libreoffice-fresh libreoffice-fresh-uk hunspell-uk hyphen-uk \
  ttf-dejavu ttf-liberation noto-fonts ttf-carlito ttf-caladea
yay -S --needed ttf-ms-fonts     # core web fonts, включно з Times New Roman
yay -S --needed ttf-calibri      # власне Calibri (або пакети з родиною Vista/Office)


echo "==> Опційна оптимізація NVIDIA (автостарт у сесії Xorg)"
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/nvidia-max-performance.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=NVIDIA Max Performance
Exec=sh -c 'command -v nvidia-settings >/dev/null && nvidia-settings -a "[gpu:0]/GpuPowerMizerMode=1" || true'
X-GNOME-Autostart-enabled=true
EOF

echo "✅ Готово! За потреби перезавантажся, щоб застосувати модулі ядра."
