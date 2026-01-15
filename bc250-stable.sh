#!/usr/bin/env bash
set -euo pipefail

echo "======================================================="
echo " AMD BC-250 — Arch Linux CLEAN & STABLE SETUP SCRIPT   "
echo "======================================================="

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Run as root (sudo)."
  exit 1
fi

echo "[0/11] Syncing package databases..."
rm -f /var/lib/pacman/db.lck || true
pacman -Sy --noconfirm

# -------------------------------------------------------
# 1. Remove unsupported / custom kernels
# -------------------------------------------------------
echo "[1/11] Removing unsupported / custom kernels (if present)..."
pacman -Rns --noconfirm \
  linux-lts-amd-bc250 \
  linux-lts-amd-bc250-headers \
  linux linux-headers \
  2>/dev/null || true

# -------------------------------------------------------
# 2. Remove BC-250 custom Mesa forks (CRITICAL)
# -------------------------------------------------------
echo "[2/11] Removing BC-250 custom Mesa forks (if present)..."
pacman -Rdd --noconfirm \
  mesa-amd-bc250 \
  lib32-mesa-amd-bc250 \
  2>/dev/null || true

# -------------------------------------------------------
# 3. Remove Mesa git / experimental stacks
# -------------------------------------------------------
echo "[3/11] Removing existing Mesa / Vulkan stacks..."
pacman -Rdd --noconfirm \
  mesa mesa-utils mesa-git \
  vulkan-radeon vulkan-radeon-git \
  vulkan-mesa-layers vulkan-mesa-layers-git \
  lib32-vulkan-radeon lib32-mesa-git \
  2>/dev/null || true

# -------------------------------------------------------
# 4. Install Mesa-GIT graphics stack (FINAL provider-safe)
# -------------------------------------------------------
echo "[4/11] Installing Mesa-GIT graphics stack (provider-safe)..."

# Stop display manager to avoid races
systemctl stop display-manager 2>/dev/null || true

# HARD BLOCK mesa-amber from coming back during this run
sed -i '/^IgnorePkg/ s/$/ mesa-amber/' /etc/pacman.conf || \
  echo "IgnorePkg = mesa-amber" >> /etc/pacman.conf

# Force-remove ALL Mesa providers (repo + amber)
echo "Removing existing Mesa providers (real package names only)..."

INSTALLED_PKGS="$(pacman -Qq)"

for pkg in mesa-git mesa-amber mesa; do
  if echo "$INSTALLED_PKGS" | grep -qx "$pkg"; then
    echo "Removing installed package: $pkg"
    pacman -Rdd --noconfirm "$pkg"
  else
    echo "Package not installed: $pkg (skipping)"
  fi
done



# Ensure yay exists
if ! command -v yay &>/dev/null; then
  echo "Installing yay (AUR helper)..."
  pacman -S --needed --noconfirm base-devel git
  sudo -u "$SUDO_USER" git clone https://aur.archlinux.org/yay.git /tmp/yay
  (cd /tmp/yay && sudo -u "$SUDO_USER" makepkg -si --noconfirm)
  rm -rf /tmp/yay
fi

# Repo Vulkan + helpers
pacman -S --needed --noconfirm \
  mesa-utils \
  xf86-video-amdgpu \
  vulkan-radeon \
  vulkan-mesa-layers \
  lib32-vulkan-radeon

# AUR Mesa (64-bit first)
run_yay -S --noconfirm --rebuild mesa-git

# AUR Mesa (32-bit)
run_yay -S --noconfirm --rebuild lib32-mesa-git

# Clean any previous failed builds
sudo -u "$SUDO_USER" rm -rf /home/"$SUDO_USER"/.cache/yay/mesa-git

# Install Mesa-GIT stack as user (atomic provider replacement)
sudo -u "$SUDO_USER" pacman -S --noconfirm --rebuild \
  mesa-git \
  vulkan-radeon-git \
  vulkan-mesa-layers-git \
  lib32-mesa-git

# -------------------------------------------------------
# 5. Install base system (known-good)
# -------------------------------------------------------
echo "[5/11] Installing base system + mesa-git prerequisites..."
pacman -S --needed --noconfirm \
  linux-lts linux-lts-headers linux-firmware \
  base-devel git networkmanager lm_sensors \
  python meson \
  python-yaml python-mako python-markupsafe \
  spirv-tools glslang

# -------------------------------------------------------
# 6. Install Mesa-GIT graphics stack (AUR-correct)
# -------------------------------------------------------
echo "[6/11] Installing Mesa-GIT graphics stack..."

# Ensure yay exists
if ! command -v yay &>/dev/null; then
  echo "Installing yay (AUR helper)..."
  pacman -S --needed --noconfirm base-devel git
  sudo -u "$SUDO_USER" git clone https://aur.archlinux.org/yay.git /tmp/yay
  (cd /tmp/yay && sudo -u "$SUDO_USER" makepkg -si --noconfirm)
  rm -rf /tmp/yay
fi

# Install repo packages ONLY
pacman -S --needed --noconfirm \
  mesa-utils \
  xf86-video-amdgpu

# Install AUR packages as user (NOT root)
yay -S --noconfirm --rebuild \
  mesa-git \
  vulkan-radeon-git \
  vulkan-mesa-layers-git

yay -S --noconfirm --rebuild \
  lib32-mesa-git


# -------------------------------------------------------
# 7. Rebuild initramfs
# -------------------------------------------------------
echo "[7/11] Rebuilding initramfs..."

pacman -S --needed --noconfirm mkinitcpio

if ! mkinitcpio -P; then
  echo "WARNING: mkinitcpio reported firmware warnings. Continuing anyway."
fi

# -------------------------------------------------------
# 8. Sanitize GRUB kernel parameters
# -------------------------------------------------------
echo "[8/11] Cleaning GRUB kernel parameters..."

sed -i 's/nomodeset//g' /etc/default/grub
sed -i 's/amdgpu\.dc=0//g' /etc/default/grub
sed -i 's/RADV_DEBUG=[^ ]*//g' /etc/default/grub
sed -i 's/  */ /g' /etc/default/grub

if ! grep -q '^GRUB_CMDLINE_LINUX_DEFAULT' /etc/default/grub; then
  echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' >> /etc/default/grub
fi


# -------------------------------------------------------
# 9. Regenerate GRUB
# -------------------------------------------------------
echo "[9/11] Regenerating GRUB configuration..."
grub-mkconfig -o /boot/grub/grub.cfg

# -------------------------------------------------------
# 10. Sensors
# -------------------------------------------------------
echo "[10/11] Running sensors auto-detection..."
sensors-detect --auto || true

# -------------------------------------------------------
# 11. Enable networking
# -------------------------------------------------------
echo "[11/11] Enabling NetworkManager..."
systemctl enable NetworkManager

echo "======================================================="
echo " BC-250 CLEAN MESA-GIT BASELINE COMPLETE               "
echo "======================================================="
echo
echo "Reboot now:"
echo "  sudo reboot"
echo
echo "Post-reboot verification:"
echo "  uname -r"
echo "  lsmod | grep amdgpu"
echo "  glxinfo | grep renderer"
echo "  vulkaninfo | grep RADV"
echo "  sensors"
echo
echo "You are on linux-lts + mesa-git (experimental)."
echo "Use sanity-check.v3.sh after updates."
echo "======================================================="
