#!/bin/bash
set -e

echo "=== Встановлюємо пакети для звуку ==="
sudo pacman -Syu --needed --noconfirm \
  pipewire pipewire-pulse pipewire-alsa pipewire-jack \
  wireplumber alsa-utils pavucontrol plasma-pa \
  helvum easyeffects

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
