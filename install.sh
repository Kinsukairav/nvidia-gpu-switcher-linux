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
# Usage:  sudo bash install.sh
# Undo:   sudo bash uninstall.sh
# ============================================================================

set -e

# ---------------------------------------------------------------------------
# 1. Root privilege check
# ---------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root. Use: sudo bash install.sh" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. ERR trap — print failing line number on unexpected errors
# ---------------------------------------------------------------------------
trap 'echo "Deployment halted due to an unexpected error at line $LINENO." >&2' ERR

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     NVIDIA Optimus Wayland Fix — Installation Script        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ---------------------------------------------------------------------------
# 3. Install required system dependencies
# ---------------------------------------------------------------------------
echo "[1/7] Syncing package repositories and installing dependencies..."
apt-get update -y || { echo "Error: Package repository sync failed." >&2; exit 1; }
apt-get install -y wget curl zenity gnome-shell-extension-prefs || { echo "Error: Critical dependencies failed to install." >&2; exit 1; }

# ---------------------------------------------------------------------------
# 4. Download and install EnvyControl (latest release from GitHub)
# ---------------------------------------------------------------------------
echo "[2/7] Downloading EnvyControl from GitHub..."
LATEST_DEB=$(curl -s https://api.github.com/repos/bayasdev/envycontrol/releases/latest | grep "browser_download_url.*deb" | cut -d : -f 2,3 | tr -d \")

if [ -z "$LATEST_DEB" ]; then
  echo "Error: Unable to retrieve the EnvyControl download URL from GitHub API." >&2
  exit 1
fi

wget "$LATEST_DEB" -O /tmp/envycontrol.deb || { echo "Error: EnvyControl download failed." >&2; exit 1; }
apt-get install -y /tmp/envycontrol.deb || { echo "Error: EnvyControl package installation failed." >&2; exit 1; }

# ---------------------------------------------------------------------------
# 5. Purge legacy tools and orphaned blacklists
# ---------------------------------------------------------------------------
echo "[3/7] Purging legacy NVIDIA tools and orphaned blacklists..."

# Mask Ubuntu's gpu-manager which overrides manual GPU config on every boot
systemctl mask gpu-manager.service 2>/dev/null || true

# Remove orphaned blacklist files left by old prime-select runs
rm -f /lib/modprobe.d/blacklist-nvidia.conf /etc/modprobe.d/blacklist-nvidia.conf
rm -f /lib/udev/rules.d/50-remove-nvidia.rules /etc/udev/rules.d/50-remove-nvidia.rules

# ---------------------------------------------------------------------------
# 6. Force NVIDIA DRM modules to load at boot
# ---------------------------------------------------------------------------
echo "[4/7] Configuring kernel module loading..."

if ! grep -q "nvidia" /etc/modules 2>/dev/null; then
  echo "nvidia" >> /etc/modules
  echo "nvidia_modeset" >> /etc/modules
  echo "nvidia_drm" >> /etc/modules
fi

# ---------------------------------------------------------------------------
# 7. Block Mutter from waking the dGPU (GNOME Wayland only)
# ---------------------------------------------------------------------------
echo "[5/7] Installing Mutter compositor isolation rule..."

echo 'SUBSYSTEM=="drm", DRIVERS=="nvidia", TAG+="mutter-device-ignore"' > /etc/udev/rules.d/61-mutter-ignore-nvidia.rules

# ---------------------------------------------------------------------------
# 8. Deploy the GPU Quick Switch backend script
# ---------------------------------------------------------------------------
echo "[6/7] Deploying GPU mode switching backend and GNOME extension..."

cat << 'SWITCH_EOF' > /usr/local/bin/gpu-quick-switch.sh
#!/bin/bash
# Backend script for the GPU Mode Switcher GNOME extension.
# Invoked by the extension's JavaScript frontend via GLib.spawn.
# Uses pkexec for secure privilege escalation (native GNOME auth dialog).

TARGET_MODE=$1

if [ -z "$TARGET_MODE" ]; then
    echo "Error: No GPU mode specified. Usage: gpu-quick-switch.sh [integrated|hybrid|nvidia]" >&2
    exit 1
fi

# Execute EnvyControl with pkexec (triggers native GNOME password dialog)
pkexec envycontrol -s "$TARGET_MODE" --rtd3

if [ $? -eq 0 ]; then
    UPPER_MODE=$(echo "$TARGET_MODE" | tr 'a-z' 'A-Z')
    # Show a native GTK dialog asking to reboot now or later
    zenity --question \
           --title="GPU Mode Changed" \
           --text="System configured to <b>${UPPER_MODE}</b> mode.\n\nA reboot is required to apply the new GPU topology." \
           --ok-label="Reboot Now" \
           --cancel-label="Reboot Later" \
           --width=380
    if [ $? -eq 0 ]; then
        systemctl reboot
    fi
else
    zenity --error \
           --title="GPU Mode Switch Failed" \
           --text="EnvyControl failed to switch the GPU mode.\n\nCheck 'journalctl -xe' for details." \
           --width=320
fi
SWITCH_EOF

chmod +x /usr/local/bin/gpu-quick-switch.sh

# ---------------------------------------------------------------------------
# 9. Deploy the GNOME Shell Quick Settings extension (system-wide)
# ---------------------------------------------------------------------------
EXT_UUID="gpu-control@global.profile"
EXT_DIR="/usr/share/gnome-shell/extensions/${EXT_UUID}"
mkdir -p "$EXT_DIR"

# Empty stylesheet (required by GNOME extension loader)
touch "$EXT_DIR/stylesheet.css"

# metadata.json — Extension identity and GNOME Shell version compatibility
cat << METADATA_EOF > "$EXT_DIR/metadata.json"
{
  "uuid": "${EXT_UUID}",
  "name": "GPU Mode Switcher",
  "description": "Quick Settings tile for switching between Integrated, Hybrid (RTD3), and Dedicated NVIDIA GPU modes via EnvyControl.",
  "shell-version": [ "45", "46", "47", "48", "49", "50" ],
  "url": "https://github.com/kinsukairav/nvidia-optimus-wayland-fix"
}
METADATA_EOF

# extension.js — The GNOME Shell JavaScript extension
cat << 'EXTJS_EOF' > "$EXT_DIR/extension.js"
import GObject from 'gi://GObject';
import GLib from 'gi://GLib';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
import * as QuickSettings from 'resource:///org/gnome/shell/ui/quickSettings.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

// ---------------------------------------------------------------------------
// GPUModeToggle — The Quick Settings menu tile with 3 GPU mode options
// ---------------------------------------------------------------------------
const GPUModeToggle = GObject.registerClass(
    class GPUModeToggle extends QuickSettings.QuickMenuToggle {
        _init() {
            super._init({
                title: 'GPU Profile',
                iconName: 'video-display-symbolic',
                toggleMode: true
            });

            // Start with toggle visually "checked" (accent-colored background)
            this.checked = true;

            // Menu header
            this.menu.setHeader('video-display-symbolic', 'Select GPU Mode');

            // Build the 3 GPU mode menu items
            this._items = {};
            this._items['integrated'] = this._addMenuItem(
                'Integrated GPU (iGPU)',
                'power-profile-power-saver-symbolic',
                'integrated'
            );
            this._items['hybrid'] = this._addMenuItem(
                'Hybrid Auto Mode',
                'power-profile-balanced-symbolic',
                'hybrid'
            );
            this._items['nvidia'] = this._addMenuItem(
                'NVIDIA Dedicated Mode',
                'power-profile-performance-symbolic',
                'nvidia'
            );

            // Sync checkmark state every time the dropdown opens
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
                // Invoke the backend switch script asynchronously
                GLib.spawn_command_line_async(
                    `/usr/local/bin/gpu-quick-switch.sh ${mode}`
                );
            });
            this.menu.addMenuItem(item);
            return item;
        }

        // Query envycontrol for the current mode and update checkmarks
        _syncState() {
            try {
                let [success, stdout, stderr] =
                    GLib.spawn_command_line_sync('/usr/bin/envycontrol -q');
                if (success) {
                    let currentMode = new TextDecoder().decode(stdout).trim();
                    for (let key in this._items) {
                        this._items[key].setOrnament(
                            key === currentMode
                                ? PopupMenu.Ornament.CHECK
                                : PopupMenu.Ornament.NONE
                        );
                    }
                } else {
                    let errStr = new TextDecoder().decode(stderr).trim();
                    console.error('GPU Switcher sync error: ' + errStr);
                }
            } catch (e) {
                console.error('GPU Switcher exception: ' + e.toString());
            }
        }
    }
);

// ---------------------------------------------------------------------------
// GPUIndicator — SystemIndicator wrapper (required for GNOME 45+ injection)
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Extension entry point — enable/disable lifecycle
// ---------------------------------------------------------------------------
export default class GPUSwitcherExtension extends Extension {
    enable() {
        this._indicator = new GPUIndicator();
        Main.panel.statusArea.quickSettings.addExternalIndicator(
            this._indicator
        );
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
# 10. Set default mode to hybrid with RTD3
# ---------------------------------------------------------------------------
echo "[7/7] Configuring hybrid mode with RTD3 power management..."
envycontrol -s hybrid --rtd3 || { echo "Warning: EnvyControl returned a non-zero exit. Check 'envycontrol -q' after reboot." >&2; }

# ---------------------------------------------------------------------------
# Done!
# ---------------------------------------------------------------------------
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
echo "║     cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_   ║"
echo "║     status                                                 ║"
echo "║                                                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "A system reboot is required. Reboot now? (y/N)"
read -r REPLY
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    systemctl reboot
fi
