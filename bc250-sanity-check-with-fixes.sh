#!/usr/bin/env bash
set -euo pipefail

ok()   { echo -e "[ OK ] $1"; }
warn() { echo -e "[WARN] $1"; }
fail() {
  echo -e "[FAIL] $1"
  echo -e "       FIX: $2"
  exit 1
}

echo "=== AMD BC250 Sanity Check (with Fix Hints) ==="
echo

### 1. Kernel ##################################################################

KERNEL="$(uname -r)"
[[ "$KERNEL" == *lts* ]] \
  && ok "Running LTS kernel: $KERNEL" \
  || fail \
    "Not running LTS kernel ($KERNEL)" \
    "Install and boot linux-lts: sudo pacman -S linux-lts linux-lts-headers && reboot"

### 2. Kernel parameters #######################################################

CMDLINE="$(cat /proc/cmdline)"
for p in amdgpu.sg_display=0 amdgpu.dc=0 iommu=pt pcie_aspm=off; do
  echo "$CMDLINE" | grep -q "$p" \
    && ok "Kernel param present: $p" \
    || fail \
      "Missing kernel param: $p" \
      "Edit /etc/default/grub, add '$p' to GRUB_CMDLINE_LINUX_DEFAULT, then run: sudo grub-mkconfig -o /boot/grub/grub.cfg && reboot"
done

### 3. Firmware ###############################################################

ls /usr/lib/firmware/amdgpu | grep -q aldebaran \
  && ok "Aldebaran firmware present" \
  || fail \
    "Aldebaran firmware missing" \
    "Install linux-firmware: sudo pacman -S linux-firmware && reboot"

### 4. amdgpu + KFD ###########################################################

lsmod | grep -q amdgpu \
  && ok "amdgpu kernel module loaded" \
  || fail \
    "amdgpu module not loaded" \
    "Ensure early loading via mkinitcpio (MODULES=(amdgpu)), rebuild initramfs, and reboot"

[[ -e /dev/kfd ]] \
  && ok "/dev/kfd exists (KFD active)" \
  || fail \
    "/dev/kfd missing" \
    "Ensure amdgpu initialized correctly and hsa-rocr is installed; check dmesg | grep amdgpu"

### 5. mkinitcpio #############################################################

[[ -f /etc/mkinitcpio.conf.d/bc250.conf ]] \
  && grep -q "MODULES=(amdgpu)" /etc/mkinitcpio.conf.d/bc250.conf \
  && ok "Early amdgpu initramfs config present" \
  || fail \
    "Early amdgpu initramfs config missing" \
    "Create /etc/mkinitcpio.conf.d/bc250.conf with 'MODULES=(amdgpu)' and run sudo mkinitcpio -P"

[[ ! -f /etc/mkinitcpio.conf.d/archiso.conf ]] \
  && ok "No archiso mkinitcpio contamination" \
  || fail \
    "archiso mkinitcpio config present" \
    "Remove it: sudo rm /etc/mkinitcpio.conf.d/archiso.conf && sudo mkinitcpio -P"

### 6. Mesa ###################################################################

MESA_VER="$(pacman -Qi mesa | awk '/Version/{print $3}')"
ok "Mesa version installed: $MESA_VER"
echo "       FIX (if too old): Upgrade system Mesa: sudo pacman -Syu mesa"

### 7. LLVM ###################################################################

LLVM_VER="$(pacman -Qi llvm-libs | awk '/Version/{print $3}')"
ok "LLVM version installed: $LLVM_VER"
echo "       FIX (if mismatched): Keep mesa and llvm-libs from the same repo snapshot (sudo pacman -Syu)"

### 8. Vulkan ICD #############################################################

ICDS="$(ls /usr/share/vulkan/icd.d)"

echo "$ICDS" | grep -q radeon_icd \
  && ok "RADV ICD present" \
  || fail \
    "RADV ICD missing" \
    "Install Mesa Vulkan drivers: sudo pacman -S vulkan-radeon lib32-vulkan-radeon"

echo "$ICDS" | grep -qi amdvlk \
  && fail \
    "AMDVLK detected (conflicts with RADV)" \
    "Remove it: sudo pacman -Rns amdvlk and optionally block it via IgnorePkg in /etc/pacman.conf" \
  || ok "No AMDVLK detected"

### 9. Vulkan device ##########################################################

vulkaninfo --summary 2>/dev/null | grep -q "RADV GFX1013" \
  && ok "Vulkan RADV sees AMD BC-250 (gfx1013)" \
  || fail \
    "Vulkan does not see BC250 via RADV" \
    "Verify mesa, vulkan-radeon, and kernel amdgpu initialization (check dmesg | grep amdgpu)"

### 10. ROCm ##################################################################

[[ -x /opt/rocm/bin/rocminfo ]] \
  && ok "rocminfo binary present" \
  || fail \
    "rocminfo binary missing" \
    "Install ROCm userspace: sudo pacman -S rocm-core rocminfo hsa-rocr rocm-device-libs"

 /opt/rocm/bin/rocminfo | grep -q "AMD BC-250" \
  && ok "ROCm detects AMD BC-250" \
  || fail \
    "ROCm does not detect BC250" \
    "Check KFD (/dev/kfd), amdgpu logs, and ensure ROCm version supports CDNA2"

### 11. Environment ###########################################################

echo "$PATH" | grep -q /opt/rocm/bin \
  && ok "ROCm in PATH" \
  || warn \
    "ROCm not in PATH — use /opt/rocm/bin/rocminfo or add /etc/profile.d/rocm.sh"

echo
echo "=== SANITY CHECK COMPLETE ==="
echo "If all checks passed, the BC250 system is healthy and compliant."
