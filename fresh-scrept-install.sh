#!/usr/bin/env bash
set -euo pipefail

echo "=== AMD BC250 EndeavourOS Setup Script ==="

### 1. Sanity checks ###########################################################

echo "[1/10] Checking kernel..."
uname -r | grep -q lts || {
  echo "ERROR: You are not running an LTS kernel. Install and boot linux-lts first."
  exit 1
}

### 2. Install required base packages #########################################

echo "[2/10] Installing base GPU packages..."
sudo pacman -S --needed --noconfirm \
  linux-lts-headers \
  linux-firmware \
  mesa lib32-mesa \
  vulkan-radeon lib32-vulkan-radeon \
  xf86-video-amdgpu \
  mkinitcpio

### 3. Verify BC250 firmware ###################################################

echo "[3/10] Verifying Aldebaran firmware..."
ls /usr/lib/firmware/amdgpu | grep -q aldebaran || {
  echo "ERROR: Aldebaran firmware missing"
  exit 1
}

### 4. Configure GRUB kernel parameters #######################################

echo "[4/10] Configuring GRUB kernel parameters..."

GRUB_FILE="/etc/default/grub"
REQUIRED_PARAMS="amdgpu.sg_display=0 amdgpu.dc=0 iommu=pt pcie_aspm=off"

if ! grep -q "amdgpu.sg_display=0" "$GRUB_FILE"; then
  sudo sed -i \
    "s|^GRUB_CMDLINE_LINUX_DEFAULT='\(.*\)'|GRUB_CMDLINE_LINUX_DEFAULT='\1 $REQUIRED_PARAMS'|" \
    "$GRUB_FILE"
fi

sudo grub-mkconfig -o /boot/grub/grub.cfg

### 5. Fix mkinitcpio archiso leftovers #######################################

echo "[5/10] Removing archiso mkinitcpio config if present..."
sudo rm -f /etc/mkinitcpio.conf.d/archiso.conf

### 6. Force early amdgpu loading #############################################

echo "[6/10] Enabling early amdgpu loading..."
sudo mkdir -p /etc/mkinitcpio.conf.d
echo "MODULES=(amdgpu)" | sudo tee /etc/mkinitcpio.conf.d/bc250.conf >/dev/null

### 7. Disable non-LTS initramfs ##############################################

echo "[7/10] Disabling non-LTS mkinitcpio preset..."
LINUX_PRESET="/etc/mkinitcpio.d/linux.preset"
if [[ -f "$LINUX_PRESET" ]]; then
  sudo sed -i "s/^PRESETS=.*/PRESETS=()/" "$LINUX_PRESET"
fi

### 8. Rebuild initramfs #######################################################

echo "[8/10] Rebuilding initramfs..."
sudo mkinitcpio -P

### 9. Install minimal ROCm stack #############################################

echo "[9/10] Installing ROCm (BC250-safe subset)..."
sudo pacman -S --needed --noconfirm \
  rocm-core \
  rocminfo \
  rocm-device-libs \
  hsa-rocr

### 10. Configure ROCm environment ############################################

echo "[10/10] Configuring ROCm environment..."
sudo tee /etc/profile.d/rocm.sh >/dev/null <<'EOF'
export PATH=/opt/rocm/bin:$PATH
export LD_LIBRARY_PATH=/opt/rocm/lib:/opt/rocm/lib64:$LD_LIBRARY_PATH
EOF

echo "=== SETUP COMPLETE ==="
echo
echo "NEXT STEPS:"
echo "  1. Reboot: sudo reboot"
echo "  2. After reboot:"
echo "       rocminfo"
echo "       dmesg | grep -i amdgpu"
echo
echo "If rocminfo shows AMD BC-250 (gfx1013), setup is successful."
