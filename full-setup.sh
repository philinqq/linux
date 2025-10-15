#!/usr/bin/env bash

# Вмикаємо безпечний режим виконання скрипта та виведення повідомлення з номером рядка при помилці.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# Створює коротку команду для встановлення пакетів через pacman без підтверджень.
PAC="sudo pacman -S --needed --noconfirm"
REFRESH() { sudo pacman -Syyu --noconfirm; }

# Оновлює ключі підписів пакетів, вмикає репозиторій multilib (якщо він закоментований).
# Ми це робимо, щоб увімкнути репозиторій multilib, який потрібен для встановлення 32-бітних бібліотек.
# Деякі ігри, програми та емулятори (наприклад Steam, Proton, Wine) використовують 32-бітні компоненти, навіть на 64-бітних системах.
echo "==> Оновлюємо ключі та вмикаємо multilib (якщо закоментовано)"
sudo pacman -S --needed --noconfirm archlinux-keyring
sudo sed -i -E 's/^\s*#\s*\[multilib\]/[multilib]/' /etc/pacman.conf
sudo sed -i -E '/^\s*\[multilib\]/ {n; s/^\s*#\s*Include\s*=.*/Include = \/etc\/pacman.d\/mirrorlist/}' /etc/pacman.conf
sudo pacman -Syy --noconfirm

# Встановлює необхідні пакети для збірки й компіляції з AUR (git, base-devel, dkms).
echo "==> Basic tools for building AUR"
$PAC git base-devel dkms

# Перевіряє, який ядро встановлено (linux або linux-zen), і встановлює відповідні заголовки для нього.
# Потрібно для коректної роботи модулів ядра, які компілюються вручну або через DKMS (наприклад, драйвери NVIDIA, VirtualBox, Wi-Fi-модулі тощо).
# Без заголовків ядра такі модулі не зможуть зібратися під твою поточну версію Linux.
echo "==> Installing kernel headers"
if pacman -Q linux &>/dev/null; then $PAC linux-headers; fi
if pacman -Q linux-zen &>/dev/null; then $PAC linux-zen-headers; fi

# Перевіряє, чи встановлено yay. 
# Якщо ні — завантажує його з AUR, збирає та встановлює для подальшої роботи з AUR-пакетами.
# yay — це AUR-хелпер, інструмент для зручного встановлення й оновлення пакетів з AUR так само, як через pacman.
echo "==> Installing/updating yay"
if ! command -v yay >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  git clone https://aur.archlinux.org/yay.git "$tmp/yay"
  pushd "$tmp/yay"
  makepkg -si --noconfirm
  popd
  rm -rf "$tmp"
fi

# Функція, що оновлює базу пакетів і всі встановлені пакети системи.
echo "==> System update"
REFRESH

# Встановлює драйвери NVIDIA, бібліотеки Vulkan (32- та 64-бітні), утиліти для тестування графіки та пакет CUDA для роботи з GPU.
echo "==> GPU (NVIDIA + Vulkan + CUDA)"
$PAC nvidia nvidia-utils lib32-nvidia-utils nvidia-settings \
     vulkan-icd-loader lib32-vulkan-icd-loader vulkan-tools mesa-utils cuda

# KMS для NVIDIA
# Створює файл конфігурації для модуля NVIDIA та вмикає modeset, щоб забезпечити коректну роботу графічного інтерфейсу й Wayland.
sudo tee /etc/modprobe.d/nvidia.conf >/dev/null <<'EOF'
options nvidia_drm modeset=1
EOF

# (Опціонально) Ранній KMS: модулі у mkinitcpio і перебудуй initramfs.
# Додає модулі NVIDIA до mkinitcpio.conf (якщо їх ще немає) і оновлює initramfs, щоб драйвери завантажувались під час старту системи.
# initramfs — це “підготовчий етап” завантаження Linux, який дозволяє ядру отримати доступ до дисків, драйверів і файлової системи перед повним запуском системи.
if ! grep -q 'nvidia_drm' /etc/mkinitcpio.conf; then
  sudo sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
fi
sudo mkinitcpio -P

# Визначає тип процесора (Intel або AMD) та встановлює відповідний мікрокод для виправлення помилок і підвищення стабільності системи.
echo "==> CPU microcode"
if grep -qi 'GenuineIntel' /proc/cpuinfo; then
  $PAC intel-ucode
else
  $PAC amd-ucode
fi

# Якщо використовується GRUB, оновлює його конфігурацію, щоб застосувати зміни (наприклад, нове ядро чи драйвери).
# GRUB — це завантажувач Linux, який запускає ядро та дозволяє вибирати систему під час старту комп’ютера.
if [ -d /boot/grub ] && command -v grub-mkconfig >/dev/null; then
  sudo grub-mkconfig -o /boot/grub/grub.cfg
fi

# Встановлює та вмикає сервіс power-profiles-daemon, який керує енергоспоживанням і дозволяє перемикати режими продуктивності.
echo "==> Power management"
$PAC power-profiles-daemon
sudo systemctl enable --now power-profiles-daemon

# Встановлює та вмикає cpupower для керування частотою CPU, задаючи режим “performance” для максимальної продуктивності.
$PAC cpupower || true
sudo systemctl enable --now cpupower.service || true
sudo bash -c 'echo governor="performance" > /etc/default/cpupower' || true

# Встановлює основні компоненти середовища KDE Plasma - робочий стіл, термінал, файловий менеджер, налаштування системи та підтримку Wayland.
echo "==> KDE Plasma (minimal set + Wayland)"
$PAC plasma-desktop konsole dolphin systemsettings kscreen \
     plasma-workspace xorg-xwayland xdg-desktop-portal-kde kwalletmanager

# Встановлює та вмикає SDDM - менеджер входу в систему для графічної авторизації користувача.
echo "==> SDDM"
$PAC sddm
sudo systemctl enable sddm.service

# Встановлює підтримку Wayland для застосунків, що використовують Qt5 та Qt6, щоб вони коректно працювали у середовищі Wayland.
echo "==> To make Plasma on Wayland have fewer artifacts in third-party Qt applications"
$PAC qt6-wayland qt5-wayland

# Звук
# Встановлює PipeWire з підтримкою PulseAudio та ALSA, а також WirePlumber — менеджер сесій для керування аудіо- та відеопотоками.
echo "==> Audio (PipeWire + instruments)"
$PAC pipewire pipewire-pulse pipewire-alsa wireplumber
# Ключовий момент: ставимо pipewire-jack і одночасно погоджуємось видалити jack2, якщо він раптом підтягнувся
# Замінює jack2 на pipewire-jack, щоб забезпечити сумісність програм із JACK через PipeWire.
sudo pacman -S --needed --noconfirm pipewire-jack || sudo pacman -R --noconfirm jack2 && sudo pacman -S --needed --noconfirm pipewire-jack
# Встановлює утиліти для керування звуком: ALSA, PulseAudio, модуль KDE Plasma, а також Helvum і EasyEffects для налаштування аудіо та ефектів.
$PAC alsa-utils pavucontrol plasma-pa helvum easyeffects
# Створює користувацький файл налаштувань PipeWire, який задає високоякісні параметри аудіо (до 192 кГц) для кращого звучання та стабільності.
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
# Вмикає та запускає сервіси PipeWire, PulseAudio через PipeWire і WirePlumber для повноцінної роботи аудіосистеми користувача.
systemctl --user enable --now pipewire pipewire-pulse wireplumber || true

echo "==> Installing Chrome"
yay -S --needed --noconfirm google-chrome

echo "==> Installing Firefox"
$PAC firefox

# Встановлює інструменти для ігор (Steam, Gamescope, Gamemode, MangoHud) і вмикає Gamemode для автоматичної оптимізації продуктивності під час гри.
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

# Встановлює та налаштовує Zoom та v4l2loopback — модуль ядра, який створює віртуальну камеру для OBS чи інших програм, і додає його в автозавантаження системи.
echo "==> Zoom + Virtual Camera"
yay -S --needed --noconfirm zoom v4l2loopback-dkms
sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="VirtualCam" exclusive_caps=1 || true
echo v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf
sudo tee /etc/modprobe.d/v4l2loopback.conf >/dev/null <<'EOF'
options v4l2loopback devices=1 video_nr=10 card_label="VirtualCam" exclusive_caps=1
EOF

echo "==> Discord & Torrent"
$PAC discord qbittorrent

# Встановлює драйвери Digimend через DKMS для підтримки графічних планшетів, які не мають офіційних Linux-драйверів.
echo "==> Installing Digimend tablet drivers (DKMS)"
yay -S --needed --noconfirm digimend-kernel-drivers-dkms

# Встановлює програми Krita та GIMP - інструменти для цифрового малювання, редагування зображень і роботи з графікою.
echo "==> Installing Gimp & Krita"
$PAC krita gimp

# Встановлює базові програми (Kate, Spectacle) і шрифти для коректного відображення тексту та емодзі.
echo "==> Utilities, fonts, user directories"
$PAC kate spectacle xdg-user-dirs ttf-dejavu ttf-liberation noto-fonts noto-fonts-cjk noto-fonts-emoji

# Створює стандартні користувацькі теки (Documents, Downloads тощо).
xdg-user-dirs-update

# Встановлює LibreOffice з українською та англійською підтримкою, словники, перенос слів і популярні шрифти (включно з Microsoft-шрифтами) для повної сумісності документів.
echo "==> Installing libreoffice and additional fonts"
$PAC libreoffice-fresh libreoffice-fresh-uk hunspell hunspell-en_US hyphen hyphen-en \
  ttf-dejavu ttf-liberation noto-fonts ttf-carlito ttf-caladea
yay -S --needed --noconfirm ttf-ms-fonts
yay -S --needed --noconfirm ttf-calibri
yay -S --needed --noconfirm hunspell-uk

echo "==> Archiver"
$PAC ark

echo "==> Calculator"
$PAC gnome-calculator

# Встановлює підтримку файлової системи NTFS (через ntfs-3g) і пакет kio-admin, що дозволяє відкривати системні каталоги з правами адміністратора у KDE.
$PAC ntfs-3g kio-admin

# Встановлює nvtop і htop — інструменти моніторингу ресурсів системи та навантаження на GPU і CPU.
$PAC nvtop htop

# Встановлює й запускає Bluetooth-служби, а також драйвер xpadneo для коректної роботи бездротових геймпадів Xbox через Bluetooth.
$PAC bluez bluez-utils bluez-deprecated-tools bluedevil
sudo systemctl enable --now bluetooth
yay -S --needed --noconfirm xpadneo-dkms
sudo modprobe hid_xpadneo

# Оновлює прошивки пристроїв, перевіряє мережевий адаптер, вмикає NetworkManager для керування з’єднаннями Wi-Fi, показує доступні мережі та встановлює мережевий аплет Plasma-NM для KDE.
echo "==> Updating firmware and enabling NetworkManager"
sudo pacman -Syu --noconfirm linux-firmware
sudo systemctl enable --now NetworkManager
sudo pacman -S --needed --noconfirm plasma-nm
# Інформаційні команди (не обов’язкові)
echo "==> Detecting network adapter:"
lspci -k | grep -A3 -i network || true
echo "==> Listing available Wi-Fi networks:"
nmcli device wifi list || true

# Встановлює інструменти для підключення iPhone до системи через USB та перезапускає служби, щоб пристрій коректно визначався й відображався у файловому менеджері.
echo "==> Setting up iPhone USB connection support"
$PAC ifuse libimobiledevice usbmuxd gvfs-afc
systemctl --user restart gvfs-afc-volume-monitor.service || true
sudo systemctl restart usbmuxd || true

# Встановлює всі доступні плагіни для VLC, щоб забезпечити підтримку більшості аудіо- та відеоформатів.
$PAC vlc-plugins-all

echo "Done! Reboot if necessary to apply kernel modules."
