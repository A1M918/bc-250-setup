#!/usr/bin/env bash
set -euo pipefail

echo "======================================================="
echo " AMD BC-250 — Arch Linux CLEAN & STABLE (mesa-git)     "
echo "======================================================="

# -------------------------------------------------------
# Safety checks
# -------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Run this script with sudo."
  exit 1
fi

if [[ -z "${SUDO_USER:-}" || "$SUDO_USER" == "root" ]]; then
  echo "ERROR: Do not run as root directly. Use sudo."
  exit 1
fi

USER_HOME="/home/$SUDO_USER"

run_yay() {
  sudo -u "$SUDO_USER" env HOME="$USER_HOME" yay "$@"
}

# -------------------------------------------------------
# 0. Sync pacman
# -------------------------------------------------------
echo "[0/9] Syncing package databases..."
rm -f /var/lib/pacman/db.lck || true
pacman -Sy --noconfirm

# -------------------------------------------------------
# 1. Remove unsupported kernels
# -------------------------------------------------------
echo "[1/9] Removing unsupported kernels (if present)..."
pacman -Rns --noconfirm \
  linux \
  linux-headers \
  linux-lts-amd-bc250 \
  linux-lts-amd-bc250-headers \
  2>/dev/null || true

# -------------------------------------------------------
# 2. Remove BC-250 custom Mesa forks
# -------------------------------------------------------
echo "[2/9] Removing BC-250 custom Mesa forks (if present)..."
pacman -Rdd --noconfirm \
  mesa-amd-bc250 \
  lib32-mesa-amd-bc250 \
  2>/dev/null || true

# -------------------------------------------------------
# 3. Remove existing Mesa providers (REAL packages only)
# -------------------------------------------------------
echo "[3/9] Removing existing Mesa providers..."
INSTALLED_PKGS="$(pacman -Qq)"

for pkg in mesa mesa-amber mesa-git; do
  if echo "$INSTALLED_PKGS" | grep -qx "$pkg"; then
    echo "  → Removing $pkg"
    pacman -Rdd --noconfirm "$pkg"
  else
    echo "  → $pkg not installed (skipping)"
  fi
done

# -------------------------------------------------------
# 4. Ensure yay exists
# -------------------------------------------------------
echo "[4/9] Ensuring yay (AUR helper) is installed..."
if ! command -v yay &>/dev/null; then
  pacman -S --needed --noconfirm base-devel git
  sudo -u "$SUDO_USER" git clone https://aur.archlinux.org/yay.git /tmp/yay
  (cd /tmp/yay && sudo -u "$SUDO_USER" makepkg -si --noconfirm)
  rm -rf /tmp/yay
fi

# -------------------------------------------------------
# 5. Install base system + mesa-git build deps
# -------------------------------------------------------
echo "[5/9] Installing base system + mesa-git build deps..."
pacman -S --needed --noconfirm \
  linux-lts linux-lts-headers linux-firmware \
  networkmanager lm_sensors \
  base-devel git \
  mesa-utils-git xf86-video-amdgpu \
  python meson \
  python-yaml python-mako python-markupsafe \
  spirv-tools glslang



# -------------------------------------------------------
# 6. Install mesa-git (AUR, provider-safe, ordered)
# -------------------------------------------------------
echo "[5.5/9] Ensure no repo Vulkan layers remain"

# Ensure no repo Vulkan layers remain
pacman -Rdd --noconfirm \
  vulkan-mesa-layers \
  vulkan-mesa-implicit-layers \
  vulkan-radeon \
  lib32-vulkan-radeon \
  2>/dev/null || true

# -------------------------------------------------------
# 6. Install mesa-git (AUR, provider-safe, ordered)
# -------------------------------------------------------
echo "[6/9] Installing mesa-git (AUR)..."

# Clean any broken builds
sudo -u "$SUDO_USER" rm -rf "$USER_HOME/.cache/yay/mesa-git"

# 64-bit Mesa
run_yay -S --noconfirm --rebuild mesa-git

# 32-bit Mesa (Steam)
run_yay -S --noconfirm --rebuild lib32-mesa-git

# -------------------------------------------------------
# 7. Rebuild initramfs
# -------------------------------------------------------
echo "[7/9] Rebuilding initramfs..."
pacman -S --needed --noconfirm mkinitcpio
mkinitcpio -P || echo "WARNING: initramfs warnings (safe to ignore)"

# -------------------------------------------------------
# 8. Clean GRUB parameters
# -------------------------------------------------------
echo "[8/9] Cleaning GRUB kernel parameters..."
sed -i 's/nomodeset//g; s/amdgpu\.dc=0//g; s/RADV_DEBUG=[^ ]*//g; s/  */ /g' /etc/default/grub
grep -q '^GRUB_CMDLINE_LINUX_DEFAULT' /etc/default/grub || \
  echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' >> /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg

# -------------------------------------------------------
# 9. Enable networking + sensors
# -------------------------------------------------------
echo "[9/9] Enabling services..."
systemctl enable NetworkManager
sensors-detect --auto || true

echo
echo "======================================================="
echo " BC-250 MESA-GIT BASELINE COMPLETE                     "
echo "======================================================="
echo
echo "Reboot now:"
echo "  sudo reboot"
echo
echo "After reboot verify:"
echo "  uname -r"
echo "  lsmod | grep amdgpu"
echo "  glxinfo | grep radeonsi"
echo "  vulkaninfo | grep RADV"
echo "======================================================="
