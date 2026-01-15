#!/usr/bin/env bash
set -euo pipefail

echo "===================================================="
echo " AMD BC-250 — SYSTEM SANITY CHECK (v3)"
echo "===================================================="

FAIL=0

ok()   { echo -e "[ OK ] $1"; }
warn() { echo -e "[WARN] $1"; }
fail() { echo -e "[FAIL] $1"; FAIL=1; }

hint() { echo -e "       -> Fix: $1"; }

# ----------------------------------------------------
# 1. Kernel sanity
# ----------------------------------------------------
echo
echo "== Kernel =="

RUNNING_KERNEL=$(uname -r)

if [[ "$RUNNING_KERNEL" =~ lts ]]; then
  ok "Running LTS kernel: $RUNNING_KERNEL"
else
  fail "Not running LTS kernel: $RUNNING_KERNEL"
  hint "sudo pacman -Rns linux linux-headers && sudo reboot"
fi

INSTALLED_KERNELS=$(pacman -Qq | grep -E '^linux(-lts)?$' | wc -l)

if [[ "$INSTALLED_KERNELS" -eq 1 ]]; then
  ok "Exactly one kernel package installed"
else
  warn "Multiple kernel packages installed"
  pacman -Qq | grep -E '^linux(-lts)?$'
  hint "sudo pacman -Rns linux linux-headers && sudo grub-mkconfig -o /boot/grub/grub.cfg"
fi

# ----------------------------------------------------
# 2. AMDGPU driver binding
# ----------------------------------------------------
echo
echo "== AMDGPU =="

if lsmod | grep -q '^amdgpu'; then
  ok "amdgpu kernel module loaded"
else
  fail "amdgpu module NOT loaded"
  hint "Check GRUB kernel selection and remove nomodeset"
fi

if lspci -k | grep -A3 VGA | grep -q 'Kernel driver in use: amdgpu'; then
  ok "GPU bound to amdgpu driver"
else
  fail "GPU NOT bound to amdgpu"
  hint "Ensure linux-lts + amdgpu driver are installed"
fi

# ----------------------------------------------------
# 3. Mesa stack (repo vs git)
# ----------------------------------------------------
echo
echo "== Mesa stack =="

MESA_REPO=0
MESA_GIT=0

pacman -Q mesa &>/dev/null && MESA_REPO=1
pacman -Q mesa-git &>/dev/null && MESA_GIT=1

if [[ $MESA_REPO -eq 1 && $MESA_GIT -eq 1 ]]; then
  fail "Both mesa and mesa-git installed (INVALID)"
  hint "sudo pacman -R mesa && reinstall one stack only"
elif [[ $MESA_GIT -eq 1 ]]; then
  ok "Using mesa-git"
elif [[ $MESA_REPO -eq 1 ]]; then
  ok "Using repo mesa"
else
  fail "No Mesa package installed"
  hint "sudo pacman -S mesa  OR  yay -S mesa-git"
fi

# ----------------------------------------------------
# 4. Vulkan consistency
# ----------------------------------------------------
echo
echo "== Vulkan =="

VULKAN_REPO=0
VULKAN_GIT=0

pacman -Q vulkan-radeon &>/dev/null && VULKAN_REPO=1
pacman -Q vulkan-radeon-git &>/dev/null && VULKAN_GIT=1

if [[ $VULKAN_REPO -eq 1 && $VULKAN_GIT -eq 1 ]]; then
  fail "Both vulkan-radeon and vulkan-radeon-git installed (INVALID)"
  hint "Remove one Vulkan stack so it matches Mesa"
elif [[ $MESA_GIT -eq 1 && $VULKAN_GIT -eq 0 ]]; then
  fail "mesa-git installed but vulkan-radeon-git missing"
  hint "yay -S vulkan-radeon-git vulkan-mesa-layers-git"
elif [[ $MESA_REPO -eq 1 && $VULKAN_REPO -eq 0 ]]; then
  fail "repo mesa installed but vulkan-radeon missing"
  hint "sudo pacman -S vulkan-radeon"
else
  ok "Vulkan stack matches Mesa"
fi

# ----------------------------------------------------
# 5. Runtime acceleration
# ----------------------------------------------------
echo
echo "== Runtime acceleration =="

if glxinfo 2>/dev/null | grep -q 'radeonsi'; then
  ok "OpenGL using radeonsi"
else
  fail "OpenGL NOT using radeonsi"
  hint "Reinstall Mesa stack and reboot"
fi

if vulkaninfo 2>/dev/null | grep -q 'RADV'; then
  ok "Vulkan using RADV"
else
  fail "Vulkan NOT using RADV"
  hint "Reinstall Vulkan stack matching Mesa"
fi

# ----------------------------------------------------
# 6. Vulkan 32-bit (Steam)
# ----------------------------------------------------
echo
echo "== Vulkan 32-bit (Steam) =="

if [[ $MESA_GIT -eq 1 ]]; then
  pacman -Q lib32-mesa-git &>/dev/null \
    && ok "lib32-mesa-git installed" \
    || { fail "lib32-mesa-git missing"; hint "yay -S lib32-mesa-git"; }
else
  pacman -Q lib32-vulkan-radeon &>/dev/null \
    && ok "lib32-vulkan-radeon installed" \
    || { fail "lib32-vulkan-radeon missing"; hint "sudo pacman -S lib32-vulkan-radeon"; }
fi

# ----------------------------------------------------
# 7. Mesa-git build dependencies (PRE-FLIGHT)
# ----------------------------------------------------
echo
echo "== Mesa-git build dependencies =="

check_py() {
  python - <<EOF &>/dev/null
import $1
EOF
}

if command -v meson &>/dev/null && python -c "import mesonbuild" &>/dev/null; then
  ok "mesonbuild (Meson) OK"
else
  fail "Meson / mesonbuild missing or broken"
  hint "sudo pacman -S meson python"
fi

check_py yaml      && ok "PyYAML OK"        || { fail "PyYAML missing"; hint "sudo pacman -S python-yaml"; }
check_py mako      && ok "Mako OK"          || { fail "Mako missing"; hint "sudo pacman -S python-mako"; }
check_py markupsafe && ok "MarkupSafe OK"   || { fail "MarkupSafe missing"; hint "sudo pacman -S python-markupsafe"; }

command -v spirv-as &>/dev/null \
  && ok "spirv-tools OK" \
  || { fail "spirv-tools missing"; hint "sudo pacman -S spirv-tools"; }

command -v glslangValidator &>/dev/null \
  && ok "glslang OK" \
  || { fail "glslang missing"; hint "sudo pacman -S glslang"; }

# ----------------------------------------------------
# 8. BC-250 custom forks
# ----------------------------------------------------
echo
echo "== BC-250 custom forks =="

BC250_PKGS=$(pacman -Qq | grep -E 'amd-bc250' || true)

if [[ -z "$BC250_PKGS" ]]; then
  ok "No BC-250 custom packages installed"
else
  fail "BC-250 custom packages detected"
  echo "$BC250_PKGS"
  hint "sudo pacman -Rns $(echo $BC250_PKGS)"
fi

# ----------------------------------------------------
# 9. Sensors
# ----------------------------------------------------
echo
echo "== Sensors =="

sensors | grep -q amdgpu && ok "AMDGPU sensors visible" || warn "AMDGPU sensors not visible"
sensors | grep -qi nct   && ok "Board sensors detected" || warn "Board sensors not detected"

# ----------------------------------------------------
# 10. /boot hygiene
# ----------------------------------------------------
echo
echo "== /boot =="

VMLINUX_COUNT=$(ls /boot | grep -c '^vmlinuz')

if [[ "$VMLINUX_COUNT" -eq 1 ]]; then
  ok "Single kernel image in /boot"
else
  warn "Multiple kernel images in /boot"
  ls /boot | grep vmlinuz
  hint "Remove extra kernels and regenerate GRUB"
fi

# ----------------------------------------------------
# 11. Network
# ----------------------------------------------------
echo
echo "== Network =="

systemctl is-enabled NetworkManager &>/dev/null \
  && ok "NetworkManager enabled" \
  || { fail "NetworkManager disabled"; hint "sudo systemctl enable --now NetworkManager"; }

# ----------------------------------------------------
# Final result
# ----------------------------------------------------
echo
echo "===================================================="
if [[ "$FAIL" -eq 0 ]]; then
  echo " RESULT: SYSTEM IS READY ✔"
else
  echo " RESULT: FIXES REQUIRED ✖"
fi
echo "===================================================="

exit "$FAIL"
