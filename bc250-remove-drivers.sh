#!/usr/bin/env bash
set -euo pipefail

echo "======================================================="
echo " AMD BC-250 — FULL MESA / VULKAN GRAPHICS PURGE (v2)"
echo "======================================================="
echo
echo "This will REMOVE all Mesa / Vulkan userspace drivers."
echo "Kernel (amdgpu) and firmware will NOT be touched."
echo
read -rp "Type YES to continue: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || { echo "Aborted."; exit 1; }

echo
echo "[1/6] Stopping display manager (if any)..."
systemctl stop display-manager 2>/dev/null || true

echo
echo "[2/6] Currently installed graphics-related packages:"
pacman -Q | grep -E 'mesa|vulkan|radeon|lib32' || true

echo
echo "[3/6] Removing Mesa / Vulkan userspace packages (repo + git + lib32)..."

# NOTE:
# - linux-firmware-radeon is intentionally NOT removed
# - kernel drivers are NOT touched
# pacman -Rdd --noconfirm \
#   mesa mesa-utils mesa-git \
#   lib32-mesa-git \
#   vulkan-radeon vulkan-radeon-git \
#   vulkan-mesa-layers vulkan-mesa-layers-git vulkan-mesa-implicit-layers \
#   vulkan-icd-loader lib32-vulkan-icd-loader \
#   vulkan-tools \
#   lib32-vulkan-radeon \
#   xf86-video-amdgpu \
#   2>/dev/null || true

echo "[*] Removing Mesa / Vulkan userspace packages (safe loop)..."

REMOVE_PKGS=(
  mesa
  mesa-utils
  mesa-git
  lib32-mesa-git

  vulkan-radeon
  vulkan-radeon-git

  vulkan-mesa-layers
  vulkan-mesa-layers-git
  vulkan-mesa-implicit-layers

  vulkan-icd-loader
  lib32-vulkan-icd-loader

  vulkan-tools
  lib32-vulkan-radeon

  xf86-video-amdgpu
)

INSTALLED="$(pacman -Qq)"

for pkg in "${REMOVE_PKGS[@]}"; do
  if echo "$INSTALLED" | grep -qx "$pkg"; then
    echo "  → Removing $pkg"
    pacman -Rdd --noconfirm "$pkg" || true
  else
    echo "  → $pkg not installed (skipping)"
  fi
done

echo
echo "[4/6] Verifying Mesa/Vulkan removal (dynamic)..."

# Collect remaining Mesa/Vulkan packages (real package names only)
LEFTOVER_PKGS=$(pacman -Qq | grep -E '^(mesa|lib32-mesa|vulkan|lib32-vulkan|mesa-utils)' || true)

if [[ -n "$LEFTOVER_PKGS" ]]; then
  echo "Detected remaining Mesa/Vulkan packages:"
  echo "$LEFTOVER_PKGS"
  echo

  echo "Removing remaining Mesa/Vulkan userspace packages (dynamic)..."
  pacman -Rdd --noconfirm $LEFTOVER_PKGS || {
    echo "ERROR: Failed to remove one or more remaining packages:"
    echo "$LEFTOVER_PKGS"
    exit 1
  }
else
  echo "No Mesa/Vulkan userspace packages detected."
fi

echo
echo "[5/6] Final verification..."
FINAL_LEFTOVERS=$(pacman -Qq | grep -E '^(mesa|lib32-mesa|vulkan|lib32-vulkan|mesa-utils)' || true)

if [[ -n "$FINAL_LEFTOVERS" ]]; then
  echo "ERROR: Mesa/Vulkan packages still detected after cleanup:"
  echo "$FINAL_LEFTOVERS"
  exit 1
else
  echo "All Mesa/Vulkan userspace packages successfully removed."
fi


echo
echo "[6/6] Cleaning leftover configuration files..."
rm -f /etc/environment.d/99-radv*.conf
rm -f /etc/modprobe.d/amdgpu*.conf
rm -f /etc/X11/xorg.conf.d/*amdgpu*.conf

echo
echo "======================================================="
echo " GRAPHICS PURGE COMPLETE"
echo "======================================================="
echo
echo "System state now:"
echo "  ✔ linux-lts kernel untouched"
echo "  ✔ amdgpu kernel module intact"
echo "  ✔ firmware intact"
echo "  ✘ Mesa removed"
echo "  ✘ Vulkan removed"
echo
echo "System is expected to boot into TTY only."
echo "Next step: clean graphics reinstall."
echo "======================================================="
