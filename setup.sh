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
log()  { echo -e "\e[1;34m[INFO]\e[0m $*"; }
warn() { echo -e "\e[1;33m[WARN]\e[0m $*"; }
err()  { echo -e "\e[1;31m[ERROR]\e[0m $*"; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || { err "Required command '$1' not found"; exit 1; }; }

# --------- 0) Підготовка та базові оновлення ---------------------------------
need_cmd sudo
if [[ $EUID -eq 0 ]]; then
  err "Do not run this script as root. Use an unprivileged user with sudo."
  exit 1
fi

log "Refreshing keyring and upgrading system..."
sudo pacman -Sy --noconfirm archlinux-keyring
sudo pacman -Su --noconfirm || true
sudo pacman -S --needed --noconfirm git base-devel

# --------- 1) Вмикаємо multilib (для Steam, lib32-* і т.д.) ------------------
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
  warn "Section [multilib] not found in pacman.conf — adding it."
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
log "Installing core graphics/audio/desktop packages..."
CORE_PKGS=(
  dkms
  # NVIDIA driver + runtime
  nvidia nvidia-utils lib32-nvidia-utils
  # Vulkan
  vulkan-icd-loader lib32-vulkan-icd-loader
  # Audio (PipeWire stack)
  pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber
  # Desktop + login manager (minimal)
  plasma-desktop plasma-wayland-session
  sddm sddm-kcm
  # Browser
  firefox
  # Gaming stack
  steam gamescope gamemode mangohud lib32-mangohud lib32-gamemode
  # Streaming / production
  obs-studio
  # Messengers
  telegram-desktop discord
  # Utils
  xdg-user-dirs
)

sudo pacman -S --needed --noconfirm "${CORE_PKGS[@]}"

# --------- 4) OPTIONAL пакети (як залежності для чистоти бази) ---------------
log "Installing optional packages as dependencies (--asdeps)..."
OPTIONAL_PKGS=(
  qt5-wayland qt6-wayland
  gst-plugin-pipewire gst-libav gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly
  noto-fonts noto-fonts-cjk noto-fonts-emoji
)
sudo pacman -S --needed --noconfirm --asdeps "${OPTIONAL_PKGS[@]}"

# --------- 5) CUDA Toolkit (за потреби: у нас УВІМКНЕНО) ---------------------
if [[ "${ENABLE_CUDA}" -eq 1 ]]; then
  log "ENABLE_CUDA=1 — installing CUDA Toolkit..."
  sudo pacman -S --needed --noconfirm cuda
else
  warn "ENABLE_CUDA=0 — skipping CUDA Toolkit."
fi

# --------- 6) AUR: встановлення yay і батч АУР-пакетів -----------------------
if ! command -v yay >/dev/null 2>&1; then
  log "Installing yay (AUR helper)..."
  tmpdir="$(mktemp -d)"
  pushd "$tmpdir" >/dev/null
  git clone --depth=1 https://aur.archlinux.org/yay-bin.git
  cd yay-bin
  makepkg -si --noconfirm
  popd >/dev/null
  rm -rf "$tmpdir"
fi

log "Installing AUR packages in a single batch..."
AUR_PKGS=(
  google-chrome
  visual-studio-code-bin
  ttf-ms-fonts
  obs-pipewire-audio-capture
)
yay -S --needed --noconfirm "${AUR_PKGS[@]}"

# --------- 7) NVIDIA: ранній KMS + nvidia-powerd ------------------------------
log "Configuring NVIDIA early KMS and enabling nvidia-powerd..."
# 7.1 Модульні опції (KMS)
sudo install -Dm644 /dev/stdin /etc/modprobe.d/nvidia-kms.conf <<'EOF'
options nvidia_drm modeset=1
EOF

# 7.2 mkinitcpio: додаємо модулі NVIDIA для плавного KMS
if ! grep -q 'MODULES=.*nvidia' /etc/mkinitcpio.conf; then
  sudo sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
fi
sudo mkinitcpio -P

# 7.3 Увімкнути сервіс керування живленням NVIDIA
sudo systemctl enable --now nvidia-powerd.service

# --------- 8) Живлення CPU: тільки power-profiles-daemon (варіант А) ----------
log "Enabling power-profiles-daemon and setting Performance profile..."
sudo pacman -S --needed --noconfirm power-profiles-daemon
sudo systemctl enable --now power-profiles-daemon
if command -v powerprofilesctl >/dev/null 2>&1; then
  powerprofilesctl set performance || true
fi

# --------- 9) PipeWire: автодетект максимальної частоти USB-ЦАП ----------------
# Ідея: зчитати /proc/asound/card*/stream0 для USB-карт (у т.ч. iBasso DC-Elite),
# витягти частоти, знайти максимальну і налаштувати PipeWire під неї.
log "Detecting maximum supported sample rate of the USB audio device..."

detect_max_rate() {
  local rates=() r max=0
  while IFS= read -r -d '' f; do
    while read -r r; do
      if [[ "$r" -ge 22050 && "$r" -le 768000 ]]; then
        rates+=("$r")
      fi
    done < <(grep -Eo '[0-9]{4,6}' "$f" || true)
  done < <(find /proc/asound -maxdepth 2 -type f -name 'stream*' -print0 2>/dev/null || true)

  for r in "${rates[@]:-}"; do
    (( r > max )) && max=$r
  done

  if [[ "$max" -eq 0 ]]; then
    max=48000
  fi
  echo "$max"
}

MAX_RATE="$(detect_max_rate)"
log "Max sample rate detected: ${MAX_RATE} Hz"

# Підібрати quantum: на високих частотах трохи збільшуємо для стабільності
if [[ "$MAX_RATE" -ge 192000 ]]; then
  QUANTUM=512
else
  QUANTUM=256
fi

# Cписок дозволених частот для уникнення зайвого ресемплу
ALLOWED=(48000 96000)
if [[ "$MAX_RATE" -ge 192000 ]]; then
  ALLOWED+=(192000)
fi
if [[ ! " ${ALLOWED[*]} " =~ " ${MAX_RATE} " ]]; then
  ALLOWED+=("$MAX_RATE")
fi

mkdir -p ~/.config/pipewire/pipewire.conf.d
cat > ~/.config/pipewire/pipewire.conf.d/10-audio-maxrate.conf <<EOF
# Налаштування PipeWire під «золотий стандарт» USB-звуковухи.
# Автовизначена максимальна частота: ${MAX_RATE} Гц
context.properties = {
  default.clock.rate = ${MAX_RATE}
  default.clock.allowed-rates = [ ${ALLOWED[*]} ]
  default.clock.quantum = ${QUANTUM}
}
EOF

systemctl --user enable --now pipewire pipewire-pulse wireplumber || true

# --------- 10) Gamemode: не вмикаємо сервіс (D-Bus автозапуск) ----------------
log "Gamemode installed. Skipping user service (D-Bus on-demand will be used)."

# --------- 11) KDE / SDDM -----------------------------------------------------
log "Enabling SDDM (Plasma Wayland sessions will be available)..."
sudo systemctl enable --now sddm

# --------- 12) Корисні дрібниці -----------------------------------------------
log "Updating XDG user directories..."
xdg-user-dirs-update || true

# --------- 13) Підсумок -------------------------------------------------------
cat <<'EOM'

============================================================
DONE

What was configured:
 - NVIDIA drivers + early KMS + nvidia-powerd
 - CUDA Toolkit (enabled for development)
 - KDE Plasma (Wayland) + SDDM
 - PipeWire tuned to the maximum supported rate of your USB DAC
 - power-profiles-daemon set to Performance
 - Steam / Gamescope / Gamemode (no user service) / MangoHud
 - AUR packages installed in a single batch (yay)

Notes:
 - To disable CUDA in future runs:
     ENABLE_CUDA=0 ./arch-pro-setup.sh
 - You can review/adjust audio settings here:
     ~/.config/pipewire/pipewire.conf.d/10-audio-maxrate.conf
 - For best gaming results, use a Plasma Wayland session.

EOM
