# CachyOS + Hyprland Complete System Replicator & Restorer

This repository contains an automated setup script designed to replicate and restore a highly customized, gorgeous **CachyOS + Hyprland + HyDE** desktop environment in a single execution.

It was created and verified to run flawlessly on Arch Linux / CachyOS bases.

---

## 🚀 Quick Start (Replicate on Any Device)

To deploy your complete setup onto a fresh installation, you can run it either as a combined **one-liner command** or by executing the steps individually.

### Option 1: The Automated One-Liner (Recommended)
Copy and paste this single command into your terminal to clone, enter, and execute the restorer automatically:
```bash
git clone https://github.com/omarahmed321/cachy-os-config-related.git && cd cachy-os-config-related && chmod +x restore_my_setup.sh && ./restore_my_setup.sh
```

### Option 2: Run directly via `curl` (No manual cloning required)
Since the restoration script is fully self-contained, you can execute it directly from the cloud without even cloning the repository manually:
```bash
curl -sSL https://raw.githubusercontent.com/omarahmed321/cachy-os-config-related/main/restore_my_setup.sh | bash
```

### Option 3: Step-by-Step Execution
If you prefer running each step individually:
```bash
# 1. Clone the repository
git clone https://github.com/omarahmed321/cachy-os-config-related.git

# 2. Enter the repository directory
cd cachy-os-config-related

# 3. Make the script executable
chmod +x restore_my_setup.sh

# 4. Run the replicator script
./restore_my_setup.sh
```

---

## 🖥️ GUI Tools Included

The setup script installs two graphical settings panels that are also available as standalone tools in this repository.

### 🌙 Night Light GUI (`nightlight-gui.py`)

A GTK4/Adwaita panel for controlling **display color warmth** via `hyprsunset` with real-time **auto-saving**.

**During installation** — the Night Light wizard opens automatically at the end of the setup process, letting you choose your preferred color temperature before the first reboot.

**After installation** — open it anytime with:

| Method | Command |
|--------|---------|
| **Keyboard shortcut** | `Super + Alt + N` |
| **Terminal** | `python3 ~/.local/share/bin/nightlight-gui.py` |
| **App launcher** (Rofi/wofi) | Search for **"Night Light"** |

**Features:**
- 🎚️ **Warmth Percentage slider**: 0% (Daylight / 6500K) → 100% (Deep Amber Night / 2000K)
- ⚡ **Toggle Switch**: Enable or disable night light instantly
- 💾 **Real-time Auto-save**: Changes save automatically to `~/.config/hypr/nightlight.conf` and persist across reboots
- 🔄 **Live preview**: Changes apply instantly in real time as a persistent background daemon

**Run the setup wizard manually:**
```bash
python3 ~/.local/share/bin/nightlight-gui.py
```

---

### 🖥️ Display & Mouse Settings GUI (`hypr-display-settings.py`)

A GTK4 panel for configuring **monitor resolution, refresh rate, scaling, and mouse sensitivity**.

| Method | Command |
|--------|---------|
| **Keyboard shortcut** | `Super + Alt + D` |
| **Terminal** | `python3 ~/.local/share/bin/hypr-display-settings.py` |
| **App launcher** | Search for **"Display & Mouse Settings"** |

---

## 🛠️ What this config actually does

The `restore_my_setup.sh` script automates the entire installation and configuration pipeline:

- **Core & AUR Preparation**: Checks for an AUR helper (`yay`/`paru`), installs `yay` if missing, and ensures basic system utilities (`git`, `zsh`) are installed.
- **Dynamic Kernel Headers Installation**: Automatically detects the running kernel (`uname -r`) and installs the matching headers package (e.g. `linux-cachyos-headers` or `linux-lts-headers`), which is required for compiling out-of-tree kernel modules.
- **Dynamic GPU Driver & Package Deployment**: Automatically detects your graphics hardware (Nvidia, AMD, or Intel) at startup, dynamically appends the correct graphics drivers and Vulkan packages (e.g. `nvidia-dkms`, `vulkan-radeon`, or `vulkan-intel`), installs **50+ system, font, and GUI packages** (including `hyprland`, `waybar`, `dunst`, `rofi-wayland`, `sddm`, `kitty`, `firefox`, `visual-studio-code-bin`, `dolphin`, `ananicy-cpp`, `antigravity`, etc.), configures modesetting and GPU-specific compositor configurations modularly, and automatically enables core system services (`bluetooth`, `NetworkManager`, `sddm`, and `ananicy-cpp`).
- **VS Code Settings & Extensions Restoration**: Deploys your custom editor settings (`settings.json`) and automatically installs all your active VS Code extensions (Tailwind CSS, animations, Gruvbox theme, Prettier, etc.) automatically.
- **Self-Sufficient Fallback Installer**: Uses a batch installation method with an automatic individual package installer fallback loop to prevent minor package or AUR failures from crashing the setup.
- **Dynamic Monitor & G-Sync Setup**: Automatically queries monitor layouts, native resolutions, and maximum refresh rates; configures the highest refresh rate monitor as the primary display, rotates the secondary monitor to portrait on the left, and configures G-Sync/VRR.
- **Interactive Mouse Offset Calibration**: Launches an interactive Zenity calibration loop at the end of the script, allowing the user to shift and align the monitors in real time.
- **Custom Keyboard Layout**: Integrates a custom Arabic layout variant (`thal_bksl` on the standard `ara` layout) mapping the letter `ذ` to the backslash key, allowing quick `Alt+Shift` toggles between US and Arabic layouts.
- **Antigravity Keyring & Token Persistence**: Configures Electron keyring flags (`--password-store=gnome-libsecret`) and unmasks `gnome-keyring-daemon` services to securely persist login tokens on reboot.
- **Nvidia & Firefox Stability Fix**: Writes `/etc/modprobe.d/nvidia.conf` with DRM modesetting and the registry tweak `PerfLevelSrc=0x2222` to stop Firefox crash/stutter loops between P0 and P8 GPU states.
- **SDDM Login Screen (Astronaut Theme)**: Installs `sddm-astronaut-theme`, selects its Jake the Dog variant, and enables VT1 reuse (`MinimumVT=1`).
- **Wi-Fi Hotspot Wrapper**: Copies a helper script (`start_hotspot.sh`) that starts a hotspot through NetworkManager (falling back to `create_ap`), shows a QR code, and disables Wi-Fi power-save via `iw` for maximum stability.
- **Zsh & Fastfetch Customization**: Configures Oh My Zsh, Powerlevel10k, zsh autocomplete/syntax plugins, and displays a custom Braille anime mascot fastfetch logo.
- **Automated Wi-Fi Driver Patching**: Detects `/usr/src/8188eu-*` driver source directories and automatically executes `patch_driver.py` to fix compilation issues on kernels 6.1+, followed by rebuilding/reinstalling via DKMS.
- **HyDE Framework Setup**: Clones the official `hyprdots` (HyDE) framework, automated using pre-seeded inputs to skip standard installation prompt timers.
- **Night Light & Display GUI Wizards**: At the end of the installation, graphical setup wizards open automatically to let you configure your display color temperature and monitor layout before the first reboot.
- **Compositor Animations**: Completely preserves native Hyprland/HyDE default animations and does not overwrite or touch any animation configuration files, letting you manage your curves via the standard HyDE animation selector.
- **Optional Lockout Disabler**: Provides an optional prompt at start to permanently disable the `pam_faillock` account lockout policy (`deny = 0`) on the system, preventing annoying user lockouts if authentication fails multiple times (backups of config files are saved as `.bak` files).

---

## 📂 Repository File Structure & Descriptions

When you clone this repository, you will find the following files:

| File | Description |
| :--- | :--- |
| **`restore_my_setup.sh`** | **The main installer & configuration script.** Handles core packages, kernel headers, SDDM Astronaut theme, HyDE config, monitor layout, VS Code sync, keyboard layout, and driver building. |
| **`cachy_tools_menu.sh`** | **Unified Tools Control Panel Launcher.** Master bash script providing an interactive CLI or GUI (Rofi/Zenity) selection menu for the repository's system tools. |
| **`omar-fav-setup.sh`** | **Omar's Favorite Setup Controller.** One-click script that configures the 3-island Glassmorphism Waybar and sets `background-for-me.jpg` paper wallpaper with Pywal color generation. |
| **`setup-wordpress-local.sh`** | **Local WordPress Development Installer.** Automated script that installs LocalWP (#1 local WordPress development tool) from AUR with automatic fallback options. |
| **`fix-polkit-localwp.sh`** | **Polkit Authentication Agent Fixer.** Utility script that installs, starts, and configures the Polkit authentication agent required for LocalWP elevated privileges. |
| **`sddm-screen-config.py`** | **SDDM Display & Screen Selector.** GUI/CLI tool to select which monitor the SDDM login screen appears on and view connected display properties. |
| **`task-manager-gui.py`** | **Interactive Task Manager GUI Picker.** GTK/Tkinter visual task selector for `doing`, `donetask`, `rmtask`, and `edittask` without retyping text. |
| **`setup-notifications-theme.py`** | **Notification Theme Customizer.** Dunst popup customizer offering Glassmorphism, Gruvbox, Cyberpunk, and Minimalist Pill themes. |
| **`setup-initial-cursor-screen.py`** | **Boot Cursor Screen Selector.** Tool to select which display the mouse pointer defaults to when booting into Hyprland. |
| **`background-for-me.jpg`** | **Signature Paper Wallpaper Asset.** High-resolution background image used by `omar-fav-setup.sh`. |
| **`setup-waybar-glassmorphism.sh`** | **Glassmorphism 3-Islands Waybar Controller.** Standalone script that configures 3 floating glassmorphic capsules, rounded workspace numbers, laptop battery indicator, and click-to-manage Wi-Fi menu with Pywal integration. |
| **`hypr-display-settings.py`** | **Display & Mouse Settings GUI.** GTK/Tkinter panel for configuring monitor resolution, custom Hz refresh rate text entry, scaling, and mouse pointer sensitivity. |
| **`monitor-alignment.sh`** | **Dual Monitor Cursor Alignment Tool.** Zenity interactive wizard to calibrate screen rotation and vertical Y-offset alignment so mouse pointer transitions smoothly between dual displays. |
| **`nightlight-gui.py`** | **Night Light settings GUI.** A GTK4/Adwaita panel for controlling display color warmth (2000–6500K) via `hyprsunset` with real-time auto-saving. Installed to `~/.local/share/bin/nightlight-gui.py`. Launch with `Super + Alt + N`. |
| **`patch_driver.py`** | **Wi-Fi driver patcher.** Automatically modifies the RTL8188EUS (`8188eu`) wireless driver source files so it compiles on 6.x/7.x kernels. |
| **`start_hotspot.sh`** | **Hotspot activation utility.** Auto-detects the Wi-Fi interface and spawns a hotspot via NetworkManager, with a `create_ap` fallback. |
| **`double-pageup.sh`** | **Key-binding helper.** Captures double-taps of the `Page_Up` key and simulates `Ctrl + \`` to toggle the integrated terminal. |
| **`ara-custom`** | **Custom keyboard layout reference.** Maps the Arabic letter `ذ` (Thal) to the backslash (`\`) key for natural Arabic typing. |
| **`ioctl_cfg80211_patched.c`** | **Patched source reference.** Backup of the patched wireless driver configuration interfaces. |
| **`install_my_setup.sh`** | **Lightweight restorer.** Copies dotfiles from a local `configs/` folder. That folder is git-ignored, so on a fresh clone use `restore_my_setup.sh` instead. |
| **`interactive_restore.sh`** | **Interactive modular installer.** Asks before each module (packages, Waybar, SDDM, VS Code, LocalWP, GUIs, themes, task manager). |
| **`setup-task-manager.sh`** | **Task manager installer.** Deploys `todo`, `doing`, `donetask`, `rmtask`, `edittask`, `manage_tasks.py` and the GUI, and adds shell functions to Fish/Zsh. |
| **`manage_tasks.py`** | **Task manager backend.** Reads and writes `~/.config/fastfetch/tasks.txt` for the task commands. |
| **`todo` / `doing` / `donetask` / `rmtask` / `edittask`** | **Task commands.** Add a task, or pick one with `fzf` and mark it in progress, done, remove it, or edit it. |
| **`setup-sddm-screen.sh`** | **SDDM screen selector wrapper.** Opens `sddm-screen-config.py` in a graphical session, or asks in the terminal otherwise. |
| **`setup-zen-browser-theme.sh`** | **Zen Browser glass theme.** Writes glass `userChrome.css` / `userContent.css` into your Zen profiles and enables custom stylesheets. `Profile/chrome/` and `(release)/chrome/` hold reference copies of the CSS. |
| **`setup_clipboard.sh`** | **Clipboard history setup.** Installs `cliphist` (Wayland/Hyprland) or `greenclip` (X11/i3) and binds a clipboard history picker. |
| **`setup_arabic_keyboard.sh`** | **Arabic keyboard customizer.** Adds the `thal_bksl` layout variant (ذ on backslash) to the system XKB files. |
| **`README.md`** | **Documentation.** This file. |

---

## ⚙️ Detailed Configuration Files Deployed

The restore script deploys and configures the following files on your system:

### 1. Hyprland Configuration (`~/.config/hypr/`)
- **`hyprland.conf`**: The main compositor entry point. Sources modular configs (`nvidia.conf`, `keybindings.conf`, `windowrules.conf`, `userprefs.conf`) and imports Wayland-specific systemd environments.
- **`userprefs.conf`**: Customizes system preferences:
  - **Shadows**: Accent border shadow enabled (`#8ec07cff`).
  - **Input**: Dual keyboard layouts (`us, ara` with a custom Arabic `thal_bksl` variant allowing the `ذ` key to map to backslash, toggled via `Alt+Shift`), mouse sensitivity `-0.5`, flat acceleration curve, and auto-starts the gnome keyring daemon.
- **`nvidia.conf`**: Defines necessary environment variables for Nvidia GPU configurations on Wayland (`__GLX_VENDOR_LIBRARY_NAME,nvidia`, `GBM_BACKEND,nvidia-drm`, `LIBVA_DRIVER_NAME,nvidia`).
- **`keybindings.conf`**: Adds convenient global keyboard shortcuts:
  - **Apps**: `Super + F` (Firefox), `Super + C` (VS Code), `Super + E` (Dolphin).
  - **GUI Controls**: `Super + Alt + N` (Night Light GUI), `Super + Alt + D` (Display & Mouse settings GUI).
  - **Media**: System audio, brightness, and player controls mapped to physical media keys.
- **`windowrules.conf`**: Styles application window rules, layout settings, custom transparency behaviors for popups, and disables active compositor animations for specific tools like color pickers (`hyprpicker`) or screenshot areas.
- **`sync_cursor.sh`**: Shell daemon to sync cursor sizes and icon paths between Hyprland, X11, and GTK interfaces.
- **`close_kitty_or_copy.sh`**: Intelligent script bound to `Ctrl+C` inside the terminal to copy selected text if present, or send an interrupt signal.

### 2. Kitty Terminal Configuration (`~/.config/kitty/`)
- **`kitty.conf`**: Configures the terminal emulator and sources `userprefs.conf`.
- **`userprefs.conf`**: Adds copy-on-select integration, binds `Ctrl+Backspace` for natural word deletion, and sets terminal text scale (`13.0`). Keep terminal cursor animations fully default.

### 3. Waybar Configuration (`~/.config/waybar/`)
- **`config.jsonc` & `style.css`**: Renders a highly responsive status bar at the top of the monitor displaying workspaces, current active window, system performance indicators (RAM, CPU), sound, date, and quick action system tray icons.

### 4. Zsh & System Info (`~/.zshrc` & `~/.config/fastfetch/`)
- **`~/.zshrc`**: Configures Oh My Zsh shell with zsh auto-suggestions, syntax-highlighting, and the Powerlevel10k custom theme.
- **`fastfetch/config.jsonc` & `logo.txt`**: Prints hardware diagnostic information alongside a custom braille anime logo on terminal startup.

### 5. VS Code Configuration (`~/.config/Code/User/settings.json`)
- Syncs settings to use the `Gruvbox Material Dark` theme, `Material Icon Theme`, disables minimap visualizers, configures tab size `4`, and auto-formats code on save.

### 6. Cava Visualizer Configuration (`~/.config/cava/config`)
- Configures the terminal audio visualizer with precise framerate adjustments and equalizer curves.

