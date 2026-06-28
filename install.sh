#!/bin/bash
# ============================================================================
# NVIDIA Optimus Wayland Fix — Global Installation Script
# ============================================================================
# Achieves true D3cold (0W) dGPU sleep on Intel + NVIDIA Optimus laptops
# running Ubuntu with GNOME Wayland. Installs:
#   1. EnvyControl with RTD3 hybrid mode
#   2. Kernel module loading, udev rules, and legacy tool cleanup
#   3. GPU Mode Switcher — GNOME Quick Settings tile extension
#
# Designed to run fully offline (no browser dependencies).
# Only network call: downloading the EnvyControl .deb from GitHub.
#
# Usage:  sudo bash install.sh
# Undo:   sudo bash uninstall.sh
# ============================================================================

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root. Use: sudo bash install.sh" >&2
  exit 1
fi

trap 'echo "Deployment halted due to an unexpected error at line $LINENO." >&2' ERR

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     NVIDIA Optimus Wayland Fix — Installation Script        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ---------------------------------------------------------------------------
# 1. Install minimal system dependencies (no browser packages)
# ---------------------------------------------------------------------------
echo "[1/7] Installing minimal dependencies..."
apt-get update -y || { echo "Error: Package repository sync failed." >&2; exit 1; }
apt-get install -y wget curl zenity || { echo "Error: Critical dependencies failed to install." >&2; exit 1; }

# ---------------------------------------------------------------------------
# 2. Download and install EnvyControl
# ---------------------------------------------------------------------------
echo "[2/7] Downloading EnvyControl..."

ENVYCONTROL_URL="https://github.com/bayasdev/envycontrol/releases/download/v3.5.1/python3-envycontrol_3.5.1-1_all.deb"

wget "$ENVYCONTROL_URL" -O /tmp/envycontrol.deb || { echo "Error: EnvyControl download failed." >&2; exit 1; }
apt-get install -y /tmp/envycontrol.deb || { echo "Error: EnvyControl package installation failed." >&2; exit 1; }

# ---------------------------------------------------------------------------
# 3. Purge legacy tools and orphaned blacklists
# ---------------------------------------------------------------------------
echo "[3/7] Purging legacy NVIDIA tools and orphaned blacklists..."

systemctl mask gpu-manager.service 2>/dev/null || true

rm -f /lib/modprobe.d/blacklist-nvidia.conf /etc/modprobe.d/blacklist-nvidia.conf
rm -f /lib/udev/rules.d/50-remove-nvidia.rules /etc/udev/rules.d/50-remove-nvidia.rules

# ---------------------------------------------------------------------------
# 4. Force NVIDIA DRM modules to load at boot
# ---------------------------------------------------------------------------
echo "[4/7] Configuring kernel module loading..."

if ! grep -q "nvidia" /etc/modules 2>/dev/null; then
  echo "nvidia" >> /etc/modules
  echo "nvidia_modeset" >> /etc/modules
  echo "nvidia_drm" >> /etc/modules
fi

# ---------------------------------------------------------------------------
# 5. Block Mutter from waking the dGPU (GNOME Wayland only)
# ---------------------------------------------------------------------------
echo "[5/7] Installing Mutter compositor isolation rule..."

echo 'SUBSYSTEM=="drm", DRIVERS=="nvidia", TAG+="mutter-device-ignore"' > /etc/udev/rules.d/61-mutter-ignore-nvidia.rules

# ---------------------------------------------------------------------------
# 6. Deploy the GPU Quick Switch backend script + GNOME extension
# ---------------------------------------------------------------------------
echo "[6/7] Deploying GPU mode switching backend and GNOME extension..."

cat << 'SWITCH_EOF' > /usr/local/bin/gpu-quick-switch.sh
#!/bin/bash
TARGET_MODE=$1
if [ -z "$TARGET_MODE" ]; then
    echo "Error: Target execution parameter omitted." >&2
    exit 1
fi
pkexec envycontrol -s "$TARGET_MODE" --rtd3
if [ $? -eq 0 ]; then
    UPPER_MODE=$(echo "$TARGET_MODE" | tr 'a-z' 'A-Z')
    zenity --question --title="GPU Mode Setup" --text="System configured to <b>${UPPER_MODE}</b> mode.\n\nA hardware reboot is required to map the fresh topology." --ok-label="Reboot Now" --cancel-label="Reboot Later" --width=380
    if [ $? -eq 0 ]; then
        systemctl reboot
    fi
else
    zenity --error --title="Execution Failure" --text="The hardware daemon failed to safely toggle the graphics configuration matrix." --width=320
fi
SWITCH_EOF

chmod +x /usr/local/bin/gpu-quick-switch.sh

EXT_UUID="gpu-control@global.profile"
EXT_DIR="/usr/share/gnome-shell/extensions/${EXT_UUID}"
mkdir -p "$EXT_DIR"

touch "$EXT_DIR/stylesheet.css"

cat << METADATA_EOF > "$EXT_DIR/metadata.json"
{
  "uuid": "${EXT_UUID}",
  "name": "GPU Mode Switcher",
  "description": "System-level EnvyControl integration.",
  "shell-version": [ "45", "46", "47", "48", "49", "50" ],
  "url": "https://github.com/kinsukairav/nvidia-gpu-switcher-linux"
}
METADATA_EOF

cat << 'EXTJS_EOF' > "$EXT_DIR/extension.js"
import GObject from 'gi://GObject';
import GLib from 'gi://GLib';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
import * as QuickSettings from 'resource:///org/gnome/shell/ui/quickSettings.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

const GPUModeToggle = GObject.registerClass(
    class GPUModeToggle extends QuickSettings.QuickMenuToggle {
        _init() {
            super._init({
                title: 'GPU Profile',
                iconName: 'video-display-symbolic',
                toggleMode: true
            });
            this.checked = true;
            this.menu.setHeader('video-display-symbolic', 'Select GPU Architecture');
            this._items = {};
            this._items['integrated'] = this._addMenuItem('Integrated GPU (iGPU)', 'power-profile-power-saver-symbolic', 'integrated');
            this._items['hybrid'] = this._addMenuItem('Hybrid Auto Mode', 'power-profile-balanced-symbolic', 'hybrid');
            this._items['nvidia'] = this._addMenuItem('NVIDIA Dedicated Mode', 'power-profile-performance-symbolic', 'nvidia');
            this.menu.connect('open-state-changed', (menu, isOpen) => {
                if (isOpen) {
                    this._syncState();
                }
            });
        }
        _addMenuItem(label, iconName, mode) {
            let item = new PopupMenu.PopupImageMenuItem(label, iconName);
            item.connect('activate', () => {
                this.menu.close();
                GLib.spawn_command_line_async(`/usr/local/bin/gpu-quick-switch.sh ${mode}`);
            });
            this.menu.addMenuItem(item);
            return item;
        }
        _syncState() {
            try {
                let [success, stdout, stderr] = GLib.spawn_command_line_sync('/usr/bin/envycontrol -q');
                if (success) {
                    let currentMode = new TextDecoder().decode(stdout).trim();
                    for (let key in this._items) {
                        if (key === currentMode) {
                            this._items[key].setOrnament(PopupMenu.Ornament.CHECK);
                        } else {
                            this._items[key].setOrnament(PopupMenu.Ornament.NONE);
                        }
                    }
                } else {
                    let errStr = new TextDecoder().decode(stderr).trim();
                    console.error('GPU Switcher Synchronization Error: ' + errStr);
                }
            } catch (e) {
                console.error('GPU Switcher Core Exception: ' + e.toString());
            }
        }
    }
);

const GPUIndicator = GObject.registerClass(
    class GPUIndicator extends QuickSettings.SystemIndicator {
        _init() {
            super._init();
            this._toggle = new GPUModeToggle();
            this.quickSettingsItems.push(this._toggle);
        }
        destroy() {
            this._toggle.destroy();
            super.destroy();
        }
    }
);

export default class GPUSwitcherExtension extends Extension {
    enable() {
        this._indicator = new GPUIndicator();
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
    }
    disable() {
        if (this._indicator) {
            this._indicator.destroy();
            this._indicator = null;
        }
    }
}
EXTJS_EOF

# ---------------------------------------------------------------------------
# 7. Set default mode to hybrid with RTD3
# ---------------------------------------------------------------------------
echo "[7/7] Configuring hybrid mode with RTD3 power management..."
envycontrol -s hybrid --rtd3 || { echo "Warning: Hardware topology configuration returned an initialization anomaly." >&2; }

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              Installation Complete!                         ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                            ║"
echo "║  ✅ EnvyControl installed (hybrid + RTD3)                  ║"
echo "║  ✅ Legacy nvidia-prime artifacts purged                   ║"
echo "║  ✅ NVIDIA DRM modules configured for boot                 ║"
echo "║  ✅ Mutter compositor isolation rule installed              ║"
echo "║  ✅ GPU Mode Switcher extension deployed                   ║"
echo "║                                                            ║"
echo "║  Next steps:                                               ║"
echo "║  1. Reboot your system                                     ║"
echo "║  2. Enable the extension:                                  ║"
echo "║     gnome-extensions enable gpu-control@global.profile     ║"
echo "║  3. Verify GPU is suspended:                               ║"
echo "║     cat /sys/bus/pci/devices/0000:01:00.0/power/           ║"
echo "║     runtime_status                                         ║"
echo "║                                                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "A system reboot is required. Reboot now? (y/N)"
read -r REPLY
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    systemctl reboot
fi
