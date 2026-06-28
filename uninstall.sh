#!/bin/bash
# ============================================================================
# NVIDIA Optimus Wayland Fix — Uninstallation Script
# ============================================================================
# Completely reverses all changes made by install.sh, restoring the system
# to its default Ubuntu NVIDIA configuration.
#
# Usage:  sudo bash uninstall.sh
# ============================================================================

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root. Use: sudo bash uninstall.sh" >&2
  exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     NVIDIA Optimus Wayland Fix — Uninstallation Script      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ---------------------------------------------------------------------------
# 1. Disable and remove the GNOME Shell extension
# ---------------------------------------------------------------------------
echo "[1/5] Removing GNOME Shell extension..."
gnome-extensions disable gpu-control@global.profile 2>/dev/null || true
rm -rf /usr/share/gnome-shell/extensions/gpu-control@global.profile

# ---------------------------------------------------------------------------
# 2. Remove backend script and udev rules
# ---------------------------------------------------------------------------
echo "[2/5] Removing GPU switch script and udev rules..."
rm -f /usr/local/bin/gpu-quick-switch.sh
rm -f /etc/udev/rules.d/61-mutter-ignore-nvidia.rules

# ---------------------------------------------------------------------------
# 3. Clean forced NVIDIA modules from /etc/modules
# ---------------------------------------------------------------------------
echo "[3/5] Removing NVIDIA module entries from /etc/modules..."
if [ -f /etc/modules ]; then
  sed -i '/^nvidia$/d' /etc/modules
  sed -i '/^nvidia_modeset$/d' /etc/modules
  sed -i '/^nvidia_drm$/d' /etc/modules
fi

# ---------------------------------------------------------------------------
# 4. Unmask gpu-manager service
# ---------------------------------------------------------------------------
echo "[4/5] Restoring default system service states..."
systemctl unmask gpu-manager.service 2>/dev/null || true

# ---------------------------------------------------------------------------
# 5. Purge EnvyControl
# ---------------------------------------------------------------------------
echo "[5/5] Purging EnvyControl package..."
apt-get purge -y envycontrol 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
rm -f /tmp/envycontrol.deb

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              Uninstallation Complete!                       ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                            ║"
echo "║  All modifications have been reversed:                     ║"
echo "║  ✅ GNOME extension removed                                ║"
echo "║  ✅ GPU switch script deleted                              ║"
echo "║  ✅ Mutter udev rule removed                               ║"
echo "║  ✅ NVIDIA module entries cleaned from /etc/modules         ║"
echo "║  ✅ gpu-manager.service unmasked                           ║"
echo "║  ✅ EnvyControl purged                                     ║"
echo "║                                                            ║"
echo "║  A system reboot is required to complete the reversal.     ║"
echo "║                                                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Reboot now? (y/N)"
read -r REPLY
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    systemctl reboot
fi
