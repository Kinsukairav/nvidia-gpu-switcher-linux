<h1 align="center">⚡ NVIDIA Optimus Wayland Fix</h1>
<h3 align="center">One-Stop Automated Fix for Intel + NVIDIA Hybrid GPU or Optimus on Linux Wayland</h3>

<p align="center">
  <a href="#-compatibility"><img src="https://img.shields.io/badge/OS-Ubuntu_26.04+-E95420?style=for-the-badge&logo=ubuntu&logoColor=white" alt="Ubuntu"/></a>
  <a href="#-compatibility"><img src="https://img.shields.io/badge/GPU-NVIDIA_Optimus-76B900?style=for-the-badge&logo=nvidia&logoColor=white" alt="NVIDIA"/></a>
  <a href="#-compatibility"><img src="https://img.shields.io/badge/Desktop-GNOME_Wayland-4A86CF?style=for-the-badge&logo=gnome&logoColor=white" alt="GNOME"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue?style=for-the-badge" alt="License: MIT"/></a>
</p>

<p align="center">
  A single script that forces your NVIDIA dGPU into <b>true D3cold (0W) sleep</b>, installs a <b>GNOME Quick Settings GPU mode switcher</b>, and keeps on-demand GPU offloading fully functional — on any Intel + NVIDIA Optimus laptop.
</p>

---

## 📋 Table of Contents

- [Why This Exists](#-why-this-exists)
- [What You Get](#-what-you-get)
- [Quick Start](#-quick-start)
- [What the Script Does (Detailed)](#-what-the-script-does-detailed)
- [The GNOME Quick Settings Extension](#-the-gnome-quick-settings-extension)
- [Verification](#-verification)
- [Compatibility](#-compatibility)
- [The Problem & Solution (Technical Deep-Dive)](#-the-problem--solution-technical-deep-dive)
- [Uninstallation](#-uninstallation)
- [FAQ](#-faq)
- [Contributing](#-contributing)
- [Credits](#-credits)

---

## ❓ Why This Exists

If you own a laptop with **Intel + NVIDIA hybrid graphics** and run Linux with Wayland, your NVIDIA dGPU is almost certainly **not sleeping properly**. Out of the box, Ubuntu's default Optimus stack fails at multiple levels:

| Symptom | Root Cause |
|---|---|
| 🔋 Battery drains fast even on iGPU | dGPU stuck in `D0/P8`, burning 3–15W |
| 🖥️ "Launch with Dedicated GPU" is missing | Legacy `prime-select` broke the D-Bus path |
| 👻 GPU draws power despite `prime-select intel` | Mutter holds a 1 MiB memory-map on the DRM node |
| ⚙️ `gpu-manager` fights your config | Ubuntu's GPU manager overwrites settings on every boot |
| 📛 Orphaned blacklist files block the GPU | Old `prime-select` left stale modprobe rules |

### Before vs. After

```
BEFORE:  nvidia-smi → GPU in P8 state, 3–15W constant drain
         prime-select intel → Reports "intel" but GPU never sleeps
         Right-click → No "Launch with Dedicated GPU" option
         Quick Settings → No GPU mode control

AFTER:   cat runtime_status → "suspended" (true D3cold, 0W)
         Right-click → "Launch using Discrete Graphics Card" ✅
         Quick Settings → GPU Mode tile with Integrated/Hybrid/NVIDIA ✅
         GPU wakes ONLY on demand, sleeps automatically after
```

---

## 🎁 What You Get

This repository provides a **single automated install script** that configures everything:

| Component | Description |
|---|---|
| **EnvyControl + RTD3** | Hybrid GPU mode with PCI-Express Runtime D3 power management |
| **Legacy Cleanup** | Purges `nvidia-prime`, `gpu-manager`, and orphaned blacklists |
| **Kernel Module Loading** | Forces `nvidia`, `nvidia_modeset`, `nvidia_drm` at boot |
| **Mutter Isolation** | udev rule preventing GNOME Wayland from waking the GPU |
| **GPU Mode Switcher** | GNOME Quick Settings tile for switching between Integrated / Hybrid / NVIDIA modes |
| **Reboot Dialog** | Native GTK prompt after mode switch — "Reboot Now" or "Reboot Later" |
| **Clean Uninstaller** | One script to completely reverse all changes |

---

## 🚀 Quick Start (Installtion)

### Install

```bash
git clone https://github.com/kinsukairav/nvidia-gpu-switcher-linux.git
cd nvidia-gpu-switcher-linux
sudo bash install.sh
```

**That's it!** Reboot your laptop. The GNOME extension will automatically enable itself on your first login.

### Uninstall

```bash
sudo bash uninstall.sh
```

That's it. One script to fix, one script to undo.

Please Note: To check and verify if Nvidia is truly OFF (D3cold) use this command:
``` cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status
```
- If the output is "suspended", then it's OFF.
- Possibly application using NVIDIA GPU or "Launch using Discrete Graphics Card" option, or System applications like Resources for monitiring purposes or even nvidia-smi command itself. In such cases, it will show "active" state.

- To check if the GPU is OFF. You need to close any application running on NVIDIA GPU. Any small process which triggers Nvidia GPU will instantly wake up and show status as "active".

Hence, it is highly recommended after a reboot OR after closing Nvidia GPU appliation, wait for 5-10 seconds to flush any Nvidia related process or service before checking the status.

For Additional Verification: See ( #Verification )

---

## 🔧 What the Script Does (Detailed)

The install script performs 7 steps, all modifying **standard Linux system files** (nothing vendor-specific):

### Step 1 — Install Dependencies
Installs `wget`, `curl`, and `zenity` via apt. No browser connectors or extension-manager packages — the GNOME extension is deployed directly to the system path.

### Step 2 — Install EnvyControl
Downloads the latest `.deb` release from the [EnvyControl GitHub](https://github.com/bayasdev/envycontrol) and installs it. EnvyControl manages the `NVreg_DynamicPowerManagement=0x02` modprobe parameter and PCI runtime PM rules.

### Step 3 — Purge Legacy Tools
- **Masks** `gpu-manager.service` — Ubuntu's built-in GPU manager that silently overrides manual configurations on every boot
- **Removes** orphaned blacklist files left by old `prime-select intel` runs:
  - `/lib/modprobe.d/blacklist-nvidia.conf`
  - `/etc/modprobe.d/blacklist-nvidia.conf`
  - `/lib/udev/rules.d/50-remove-nvidia.rules`
  - `/etc/udev/rules.d/50-remove-nvidia.rules`

### Step 4 — Force NVIDIA DRM Module Loading
Appends `nvidia`, `nvidia_modeset`, and `nvidia_drm` to `/etc/modules` so the Direct Rendering Manager detects the GPU at boot. This restores `switcheroo-control` functionality and the "Launch with Dedicated GPU" context menu.

### Step 5 — Mutter Compositor Isolation
Creates `/etc/udev/rules.d/61-mutter-ignore-nvidia.rules` with:
```
SUBSYSTEM=="drm", DRIVERS=="nvidia", TAG+="mutter-device-ignore"
```
This prevents GNOME's Mutter compositor from opening `/dev/dri/card1`, which otherwise keeps the PCIe lane active and blocks D3cold.

### Step 6 — GPU Mode Switcher Extension
Deploys a **system-wide** GNOME Shell extension to `/usr/share/gnome-shell/extensions/` with:
- A **Quick Settings tile** (like Wi-Fi/Bluetooth toggles) for GPU mode control
- A **backend shell script** at `/usr/local/bin/gpu-quick-switch.sh` that handles EnvyControl switching via `pkexec` (native GNOME auth dialog)
- A **Zenity reboot dialog** after each mode switch

### Step 7 — Set Default Mode
Configures `hybrid` mode with `--rtd3` as the default GPU power policy.

---

## 🖥️ The GNOME Quick Settings Extension

After installation, you get a native **GPU Profile** tile in your GNOME Quick Settings panel (the dropdown with Wi-Fi, Bluetooth, Power, etc.):

### How It Works

1. **Pull down** the Quick Settings panel from the top-right
2. **Click** the "GPU Profile" tile to expand the dropdown menu
3. **Select** your desired mode:
   - ⚡ **Integrated GPU (iGPU)** — Maximum battery, NVIDIA fully off
   - ⚖️ **Hybrid Auto Mode** — GPU sleeps at 0W, wakes on demand (recommended)
   - 🎮 **NVIDIA Dedicated Mode** — GPU always on, maximum performance
4. **Authenticate** via the native GNOME password dialog (pkexec)
5. **Choose** "Reboot Now" or "Reboot Later" from the native GTK dialog

The extension is installed **system-wide** at `/usr/share/gnome-shell/extensions/`, meaning it works for all user accounts on the machine — not just your profile.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  GNOME Quick Settings Panel                                 │
│  ┌───────────────────────────────┐                          │
│  │ 🖥️ GPU Profile  ▼            │ ← QuickMenuToggle tile    │
│  ├───────────────────────────────┤                          │
│  │ ✓ Hybrid Auto Mode           │ ← Current mode (check)    │
│  │   Integrated GPU (iGPU)      │                           │
│  │   NVIDIA Dedicated Mode      │                           │
│  └───────────────────────────────┘                          │
│         │                                                   │
│         ▼ on click                                          │
│  /usr/local/bin/gpu-quick-switch.sh <mode>                  │
│         │                                                   │
│         ▼ pkexec (password prompt)                          │
│  envycontrol -s <mode> --rtd3                               │
│         │                                                   │
│         ▼ on success                                        │
│  Zenity dialog: [Reboot Now] [Reboot Later]                 │
└─────────────────────────────────────────────────────────────┘
```

---

## ✅ Verification

After rebooting, run these commands to confirm everything is working:

```bash
# 1. Check dGPU power state (should print "suspended")
cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status

# 2. Check EnvyControl mode (should print "hybrid")
envycontrol --query

# 3. Verify NVIDIA modules are loaded
lsmod | grep nvidia

# 4. Verify gpu-manager is masked
systemctl status gpu-manager.service

# 5. Verify the GNOME extension is active
gnome-extensions show gpu-control@global.profile

# 6. (Optional) Confirm GPU wakes on demand — this WILL wake the GPU temporarily
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia glxinfo | head -5
```

> [!CAUTION]
> **Do NOT use `nvidia-smi` to check the power state.** Running `nvidia-smi` wakes the GPU from D3cold. Always use the `sysfs` interface (`cat .../runtime_status`) instead.

> [!NOTE]
> Your PCI device ID may differ from `0000:01:00.0`. Run `lspci | grep -i nvidia` to find yours.

---

## 🔄 Compatibility

> [!IMPORTANT]
> **This fix is NOT limited to Lenovo laptops.**
>
> Every file modified by the install script is a **standard Linux system file** — kernel modules, systemd services, udev rules, and GNOME extensions. Nothing is vendor-specific firmware. If your laptop has an **Intel CPU + NVIDIA GPU** in an Optimus configuration, this fix applies to you.

### Hardware Tested On

| Component | Specification |
|---|---|
| **Model** | Lenovo LOQ 15IAX9 |
| **CPU** | 12th Gen Intel Core i5-12450HX (Alder Lake) |
| **iGPU** | Intel UHD Graphics |
| **dGPU** | NVIDIA GeForce RTX 3050 6 GB |
| **OS** | Ubuntu 26.04 LTS |
| **Desktop** | GNOME 48 (Wayland) |
| **NVIDIA Driver** | 595+ (proprietary) |

### Expected to Work On

| Brand | Example Series |
|---|---|
| **Lenovo** | LOQ, IdeaPad Gaming, Legion |
| **ASUS** | TUF Gaming, ROG Strix, Vivobook Pro |
| **Acer** | Nitro, Aspire 7, Predator Helios |
| **HP** | Victus, Pavilion Gaming, Omen |
| **Dell** | G-Series, Inspiron Gaming |
| **MSI** | GF/GV Series, Katana, Pulse |

### Requirements

| Requirement | Minimum |
|---|---|
| **GPU** | NVIDIA Turing+ (GTX 16xx / RTX 20xx+) for RTD3/D3cold |
| **Desktop** | GNOME 45+ on Wayland (for the Quick Settings extension) |
| **Driver** | NVIDIA proprietary driver 525+ |

---

## 🔬 The Problem & Solution (Technical Deep-Dive)

This fix was developed through a multi-phase debugging process, solving 5 distinct engineering problems:

### Phase 1 — The Discrete GPU Power Bleed

**Problem:** The NVIDIA dGPU consistently drained 3–15W even with an empty process list. Legacy tools like `prime-select intel` reported "intel" mode but never triggered true PCIe power-down.

**Insight:** Using `nvidia-smi` to check power state creates a "refrigerator light" paradox — querying the GPU wakes it up, reporting false active status.

**Fix:** EnvyControl with `--rtd3` sets `NVreg_DynamicPowerManagement=0x02`, enabling D3cold. Power state verified via `/sys/bus/pci/devices/.../power/runtime_status` to avoid waking the card.

### Phase 2 — Missing PRIME Offload Menus

**Problem:** The GNOME "Launch using Discrete Graphics Card" context menu disappeared after removing legacy tools.

**Insight:** Old `prime-select intel` runs left orphaned blacklist files that blocked `nvidia_drm` modules from loading, making the DRM subsystem blind to the GPU.

**Fix:** Purged all orphaned blacklists and forced module loading via `/etc/modules`, restoring `switcheroo-control` registration.

### Phase 3 — GNOME Wayland VRAM Lockout

**Problem:** Even with RTD3 configured, the GPU refused to enter D3cold because `gnome-shell` held a persistent 1 MiB memory-map on the DRM device file.

**Insight:** Mutter (GNOME's Wayland compositor) opens `/dev/dri/card1` for display hotplug detection, keeping the PCIe lane powered.

**Fix:** Created a udev rule (`61-mutter-ignore-nvidia.rules`) with `mutter-device-ignore` tag, forcing the compositor to release the device file.

### Phase 4 — GNOME 45+ Extension API Changes

**Problem:** The custom Quick Settings extension failed to load with `TypeError: addItems is not a function`. GNOME 45+ deprecated the old shell grid modification API.

**Insight:** GNOME moved to a sandboxed extension model requiring `SystemIndicator` containers and `addExternalIndicator()` injection instead of direct `addItems()` calls.

**Fix:** Re-architected the extension using GObject subclassing with `QuickMenuToggle` inside a `SystemIndicator`, injected via `addExternalIndicator()`.

### Phase 5 — Profile-Level vs. System-Level Deployment

**Problem:** The initial extension was deployed to `~/.local/share/gnome-shell/extensions/`, which only worked for a single user account and broke with directory path changes.

**Insight:** User-profile paths are UID-specific. Any new user account created on the machine wouldn't see the extension.

**Fix:** Relocated the extension to `/usr/share/gnome-shell/extensions/` and the backend script to `/usr/local/bin/`, making both globally accessible to all user accounts.

---

## 🗑️ Uninstallation

To completely reverse all changes and restore your system to its default state:

```bash
sudo bash uninstall.sh
```

This script removes every modification made by the installer:

| What Gets Reversed | Details |
|---|---|
| GNOME extension | Disabled and deleted from `/usr/share/gnome-shell/extensions/` |
| Backend script | Deleted from `/usr/local/bin/gpu-quick-switch.sh` |
| Mutter udev rule | Deleted from `/etc/udev/rules.d/61-mutter-ignore-nvidia.rules` |
| Kernel modules | `nvidia`, `nvidia_modeset`, `nvidia_drm` removed from `/etc/modules` |
| gpu-manager | Service unmasked, restored to Ubuntu default |
| EnvyControl | Package purged from the system |

A reboot is required after uninstallation.

---

## ❓ FAQ

<details>
<summary><b>Will running <code>nvidia-smi</code> break the suspended state?</b></summary>

**Yes.** `nvidia-smi` wakes the GPU from D3cold. Use `cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status` to check non-intrusively. The GPU returns to sleep after `nvidia-smi` exits.
</details>

<details>
<summary><b>Can I still game with the GPU in hybrid mode?</b></summary>

**Absolutely.** The GPU sleeps until explicitly called. Use any of these methods:
- **GNOME:** Right-click an app → "Launch using Discrete Graphics Card"
- **Terminal:** `__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia <app>`
- **Steam:** Set launch options to `__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia %command%`
- **Quick Settings:** Switch to "NVIDIA Dedicated Mode" for full-time dGPU
</details>

<details>
<summary><b>What's the difference between P8 and D3cold?</b></summary>

**P8** is NVIDIA's lowest *performance* state — GPU idle but PCIe link active (3–15W). **D3cold** is a PCI *power* state — GPU completely powered off (0W). This fix achieves D3cold.
</details>

<details>
<summary><b>Is this safe for dual-boot?</b></summary>

**Yes.** All changes are within the Linux partition. Windows NVIDIA drivers are untouched.
</details>

<details>
<summary><b>Will kernel updates break this?</b></summary>

`/etc/modules` and udev rules persist. Major NVIDIA driver updates may require re-running `sudo envycontrol -s hybrid --rtd3`. The Quick Settings extension supports GNOME 45–50.
</details>

<details>
<summary><b>I use KDE/XFCE — can I use this?</b></summary>

The **core power fix** (Steps 1–5, 7) works on any desktop. The **Quick Settings extension** (Step 6) is GNOME-specific. KDE users should skip the extension or check KWin equivalents. Run the script and it will still configure all the non-GNOME parts correctly.
</details>

<details>
<summary><b>The extension doesn't show after install</b></summary>

1. Check that you rebooted after running `install.sh`
2. Wait a few seconds after logging in (it enables automatically via autostart)
3. If it still doesn't appear, try enabling manually: `gnome-extensions enable gpu-control@global.profile`
4. Log out and log back in (Wayland session refresh)
5. Check for errors: `journalctl -b 0 /usr/bin/gnome-shell | grep gpu-control`
</details>

---

## 🤝 Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

- 🧪 **Test** on your hardware and report results
- 🐛 **Report** bugs via [GitHub Issues](../../issues)
- 📝 **Submit PRs** for improvements or distro support
- ⭐ **Star** if it saved your battery

---

## 🙏 Credits

- **[EnvyControl](https://github.com/bayasdev/envycontrol)** — The core utility managing RTD3 power states
- **[NVIDIA Open GPU Kernel Modules](https://github.com/NVIDIA/open-gpu-kernel-modules)** — RTD3 documentation reference
- **The Linux community** — For the collective knowledge that made this possible

---

## 🔗 Related

- **[usb-audio-linux-fix](https://github.com/kinsukairav/usb-audio-linux-fix)** — Fix USB-C audio dropouts & PipeWire crashes on Linux

---

<p align="center">
  <sub>Made with ❤️ for the Linux community by <a href="https://github.com/kinsukairav">Shaurya Raj</a></sub><br/>
  <sub>If this guide saved your battery life, consider giving it a ⭐</sub>
</p>
