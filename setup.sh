#!/usr/bin/env bash
# ============================================================
#  Arch Linux "Pro Setup" for Ryzen 7 7700X + RTX 4070 Ti
#  Автор: для Illia | Фокус: продуктивність, чистота пакетів
#  Особливості:
#   - Увімкнена CUDA (Toolkit) для розробки
#   - NVIDIA + nvidia-powerd + ранній KMS
#   - KDE Plasma (Wayland) + SDDM (мінімально)
#   - PipeWire з автодетектом максимальної частоти твоєї USB-звуковухи
#   - power-profiles-daemon (Performance), без cpupower
#   - АУР пакети ставляться батчем; optional позначені як --asdeps
# ============================================================
set -Eeuo pipefail

# --------- Налаштовувані прапорці --------------------------------------------
# CUDA потрібна для розробки -> залишаємо 1 за замовчанням
ENABLE_CUDA=${ENABLE_CUDA:-1}

# Якщо ставиш Arch з ядром LTS, постав LTS_HEADERS=1 (або авто-виявлення нижче спрацює)
LTS_HEADERS=${LTS_HEADERS:-auto}   # auto|0|1

# -----------------------------------------------------------------------------
log() { echo -e "\e[1;32m[OK]\e[0m $*"; }
warn() { echo -e "\e[1;33m[WARN]\e[0m $*"; }
err() { echo -e "\e[1;31m[ERR]\e[0m $*"; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || { err "Потрібна команда '$1' не знайдена"; exit 1; }; }

# --------- 0) Підготовка та базові оновлення ---------------------------------
need_cmd sudo
if [[ $EUID -eq 0 ]]; then
  err "Не запускай скрипт від root. Запусти звичайним користувачем із sudo."
  exit 1
fi

log "Оновлюю ключі та базу пакетів…"
sudo pacman -Sy --noconfirm archlinux-keyring
sudo pacman -Su --noconfirm || true
sudo pacman -S --needed --noconfirm git base-devel

# --------- 1) Вмикаємо multilib (для Steam, lib32-* і т.д.) ------------------
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
  warn "У pacman.conf не знайдено секцію [multilib] — додаю."
  sudo sed -i '/^\[core\]/i [multilib]\nInclude = /etc/pacman.d/mirrorlist\n' /etc/pacman.conf
else
  sudo sed -i '/^\[multilib\]/,/^$/{s/^#Include/Include/}' /etc/pacman.conf
fi
sudo pacman -Sy --noconfirm

# --------- 2) Визначаємо заголовки ядра --------------------------------------
install_kernel_headers() {
  if [[ "$LTS_HEADERS" == "1" ]] || pacman -Q linux-lts >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm linux-lts-headers
  else
    sudo pacman -S --needed --noconfirm linux-headers
  fi
}
install_kernel_headers

# --------- 3) CORE пакети -----------------------------------------------------
log "Встановлюю ядро графіки/аудіо/десктопа (CORE)…"
CORE_PKGS=(
  dkms               # на майбутнє для сторонніх модулів (опційно)
  # NVIDIA драйвер + рантайм
  nvidia nvidia-utils lib32-nvidia-utils
  # Vulkan
  vulkan-icd-loader lib32-vulkan-icd-loader
  # Аудіо стек (PipeWire)
  pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber
  # Десктоп + логін-менеджер (мінімально)
  plasma-desktop plasma-wayland-session
  sddm sddm-kcm
  # Браузер
  firefox
  # Ігровий стек
  steam gamescope gamemode mangohud lib32-mangohud lib32-gamemode
  # Стрімінг / продакшн
  obs-studio
  # Месенджери
  telegram-desktop discord
  # Утиліти
  xdg-user-dirs
)

sudo pacman -S --needed --noconfirm "${CORE_PKGS[@]}"

# --------- 4) OPTIONAL пакети (як залежності для чистоти бази) ---------------
log "Встановлюю OPTIONAL (як залежності, --asdeps)…"
OPTIONAL_PKGS=(
  # Qt Wayland покращує інтеграцію Qt-додатків у Wayland
  qt5-wayland qt6-wayland
  # Кодеки/плагіни
  gst-plugin-pipewire gst-libav gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly
  # Шрифти
  noto-fonts noto-fonts-cjk noto-fonts-emoji
)
sudo pacman -S --needed --noconfirm --asdeps "${OPTIONAL_PKGS[@]}"

# --------- 5) CUDA Toolkit (за потреби: у нас УВІМКНЕНО) ---------------------
if [[ "${ENABLE_CUDA}" -eq 1 ]]; then
  log "CUDA Toolkit увімкнено прапорцем — встановлюю…"
  sudo pacman -S --needed --noconfirm cuda
else
  warn "ENABLE_CUDA=0 — пропускаю встановлення CUDA Toolkit."
fi

# --------- 6) AUR: встановлення yay і батч АУР-пакетів -----------------------
if ! command -v yay >/dev/null 2>&1; then
  log "Встановлюю yay (AUR helper)…"
  tmpdir="$(mktemp -d)"
  pushd "$tmpdir" >/dev/null
  git clone --depth=1 https://aur.archlinux.org/yay-bin.git
  cd yay-bin
  makepkg -si --noconfirm
  popd >/dev/null
  rm -rf "$tmpdir"
fi

log "Ставлю AUR-пакети одним викликом…"
AUR_PKGS=(
  google-chrome
  visual-studio-code-bin
  ttf-ms-fonts
  obs-pipewire-audio-capture
)
yay -S --needed --noconfirm "${AUR_PKGS[@]}"

# --------- 7) NVIDIA: ранній KMS + nvidia-powerd ------------------------------
log "Налаштовую NVIDIA ранній KMS та вмикаю powerd…"
# 7.1 Модульні опції (KMS)
sudo install -Dm644 /dev/stdin /etc/modprobe.d/nvidia-kms.conf <<'EOF'
options nvidia_drm modeset=1
EOF

# 7.2 mkinitcpio: додаємо модулі NVIDIA (не завадить для плавного KMS)
if ! grep -q 'MODULES=.*nvidia' /etc/mkinitcpio.conf; then
  sudo sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
fi
sudo mkinitcpio -P

# 7.3 Увімкнути сервіс керування живленням NVIDIA
sudo systemctl enable --now nvidia-powerd.service

# --------- 8) Живлення CPU: тільки power-profiles-daemon (варіант А) ----------
log "Вмикаю power-profiles-daemon (варіант А) і ставлю профіль Performance…"
sudo pacman -S --needed --noconfirm power-profiles-daemon
sudo systemctl enable --now power-profiles-daemon
# виставляємо performance (якщо інструмент уже доступний)
if command -v powerprofilesctl >/dev/null 2>&1; then
  powerprofilesctl set performance || true
fi

# --------- 9) PipeWire: автодетект максимальної частоти USB-ЦАП ----------------
# Ідея: зчитати /proc/asound/card*/stream0 для USB-карт (у т.ч. iBasso DC-Elite),
# витягти всі можливі частоти, взяти максимальну і налаштувати PipeWire під неї.
log "Автовизначення максимальної підтримуваної частоти USB-звуковухи…"

detect_max_rate() {
  local rates=() r max=0
  # переглядаємо всі stream*-файли (USB-карти їх мають)
  while IFS= read -r -d '' f; do
    # Витягнути усі числа 22050..768000 Гц
    while read -r r; do
      # фільтр на реалістичні частоти
      if [[ "$r" -ge 22050 && "$r" -le 768000 ]]; then
        rates+=("$r")
      fi
    done < <(grep -Eo '[0-9]{4,6}' "$f" || true)
  done < <(find /proc/asound -maxdepth 2 -type f -name 'stream*' -print0 2>/dev/null || true)

  # Якщо знайшли конкретні частоти — беремо максимум
  for r in "${rates[@]:-}"; do
    (( r > max )) && max=$r
  done

  # Якщо нічого не знайшли — дефолт 48000
  if [[ "$max" -eq 0 ]]; then
    max=48000
  fi
  echo "$max"
}

MAX_RATE="$(detect_max_rate)"
log "Максимальна частота, знайдена в системі: ${MAX_RATE} Гц"

# Підбираємо quantum: для дуже високих частот беремо трішки більше для стабільності
# 48/96 кГц -> 256; >=192 кГц -> 512
if [[ "$MAX_RATE" -ge 192000 ]]; then
  QUANTUM=512
else
  QUANTUM=256
fi

# Формуємо список дозволених частот (щоб уникати зайвого ресемплу)
ALLOWED=(48000 96000)
# додамо 192000 лише якщо max >= 192000
if [[ "$MAX_RATE" -ge 192000 ]]; then
  ALLOWED+=(192000)
fi
# і сам MAX_RATE, якщо його ще нема
if [[ ! " ${ALLOWED[*]} " =~ " ${MAX_RATE} " ]]; then
  ALLOWED+=("$MAX_RATE")
fi

mkdir -p ~/.config/pipewire/pipewire.conf.d
cat > ~/.config/pipewire/pipewire.conf.d/10-audio-maxrate.conf <<EOF
# Налаштування PipeWire під «золотий стандарт» твоєї USB-звуковухи.
# Автовизначена максимальна частота: ${MAX_RATE} Гц
context.properties = {
  default.clock.rate = ${MAX_RATE}
  default.clock.allowed-rates = [ ${ALLOWED[*]} ]
  default.clock.quantum = ${QUANTUM}
}
EOF

# Вмикаємо користувацькі сервіси аудіо
systemctl --user enable --now pipewire pipewire-pulse wireplumber || true

# --------- 10) Gamemode: не вмикаємо сервіс (стартує через D-Bus) ------------
log "Gamemode встановлено, сервіс не вмикаю (D-Bus автозапуск на вимогу ігор)."

# --------- 11) KDE / SDDM -----------------------------------------------------
log "Вмикаю SDDM (Wayland сесії Plasma доступні)…"
sudo systemctl enable --now sddm

# --------- 12) Корисні дрібниці -----------------------------------------------
log "Оновлюю XDG-теки користувача…"
xdg-user-dirs-update || true

# --------- 13) Підсумок -------------------------------------------------------
cat <<'EOM'

============================================================
✅ Готово!

Що зроблено:
 - NVIDIA драйвери + ранній KMS + nvidia-powerd
 - CUDA Toolkit (увімкнено для розробки)
 - KDE Plasma (Wayland) + SDDM
 - PipeWire налаштовано під максимальну частоту твоєї USB-звуковухи
 - power-profiles-daemon → Performance
 - Steam / Gamescope / Gamemode (без сервісу) / MangoHud
 - AUR пакети встановлені одним викликом (yay)

Нотатки:
 - Якщо захочеш вимкнути CUDA у майбутньому, запусти зі змінною:
     ENABLE_CUDA=0 ./arch-pro-setup.sh
 - Частоту аудіо можна перевірити/підкорегувати в
     ~/.config/pipewire/pipewire.conf.d/10-audio-maxrate.conf
 - Для найкращих результатів у іграх запускай Steam-ігри у Wayland-сесії.

Приємної роботи! 🚀
============================================================
EOM
