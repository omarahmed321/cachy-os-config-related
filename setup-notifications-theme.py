#!/usr/bin/env python3
# =============================================================================
#   Dunst Notification Theme Customizer (100% Transparent Glass Capsule)
#   Part of: CachyOS + HyDE System Restorer
#   Repo:    https://github.com/omarahmed321/cachy-os-config-related
# =============================================================================

import os
import sys
import json
import subprocess
import tkinter as tk
from tkinter import ttk, messagebox

DUNST_CONF = os.path.expanduser("~/.config/dunst/dunstrc")
WAL_COLORS_JSON = os.path.expanduser("~/.cache/wal/colors.json")
USERPREFS_CONF = os.path.expanduser("~/.config/hypr/userprefs.conf")
WINDOWRULES_CONF = os.path.expanduser("~/.config/hypr/windowrules.conf")

def get_pywal_colors():
    bg = "#000000"
    fg = "#bac2b3"
    accent = "#6E835B"
    if os.path.exists(WAL_COLORS_JSON):
        try:
            with open(WAL_COLORS_JSON, 'r') as f:
                data = json.load(f)
                fg = data.get("special", {}).get("foreground", fg)
                accent = data.get("colors", {}).get("color4", accent)
                if not accent or accent == bg:
                    accent = data.get("colors", {}).get("color2", "#61775D")
        except Exception:
            pass
    return bg, fg, accent

py_bg, py_fg, py_accent = get_pywal_colors()

THEMES = {
    "1. 💎 Fully Transparent Glass Capsule (No Dark Background)": f"""[global]
    monitor = 0
    follow = mouse
    width = (280, 420)
    height = (70, 160)
    origin = top-right
    offset = 20x55
    scale = 0
    notification_limit = 5
    progress_bar = true
    progress_bar_height = 6
    progress_bar_frame_width = 0
    progress_bar_min_width = 150
    progress_bar_max_width = 300
    progress_bar_corner_radius = 8
    icon_corner_radius = 12
    indicate_hidden = yes
    transparency = 0
    separator_height = 1
    padding = 12
    horizontal_padding = 20
    text_icon_padding = 12
    frame_width = 1
    frame_color = "{py_accent}60"
    gap_size = 12
    separator_color = frame
    sort = yes
    font = JetBrains Mono 10
    corner_radius = 22
    background = "#00000025"
    foreground = "{py_fg}"
    format = "<b>%s</b>\\n%b"
    alignment = left
    vertical_alignment = center
    show_age_threshold = 60
    icon_position = left
    min_icon_size = 32
    max_icon_size = 64

[urgency_low]
    background = "#00000020"
    foreground = "{py_fg}"
    frame_color = "{py_accent}40"
    timeout = 5

[urgency_normal]
    background = "#00000030"
    foreground = "{py_fg}"
    frame_color = "{py_accent}80"
    timeout = 5

[urgency_critical]
    background = "#fb493430"
    foreground = "#fb4934"
    frame_color = "#fb4934"
    timeout = 0
""",

    "2. 📜 Gruvbox Retro Dark": """[global]
    monitor = 0
    follow = mouse
    width = 320
    height = 140
    origin = top-right
    offset = 15x45
    padding = 10
    horizontal_padding = 12
    frame_width = 2
    frame_color = "#fabd2f"
    font = JetBrains Mono 10
    corner_radius = 6
    background = "#282828"
    foreground = "#ebdbb2"

[urgency_low]
    background = "#282828"
    foreground = "#928374"
    frame_color = "#665c54"

[urgency_normal]
    background = "#282828"
    foreground = "#ebdbb2"
    frame_color = "#fabd2f"

[urgency_critical]
    background = "#282828"
    foreground = "#fb4934"
    frame_color = "#cc241d"
""",

    "3. 💜 Cyberpunk Neon": """[global]
    monitor = 0
    follow = mouse
    width = 350
    height = 150
    origin = top-right
    offset = 20x50
    padding = 14
    horizontal_padding = 18
    frame_width = 2
    frame_color = "#d3869b"
    font = JetBrains Mono 10
    corner_radius = 10
    background = "#1d2021"
    foreground = "#b8bb26"

[urgency_low]
    background = "#1d2021"
    foreground = "#8ec07c"
    frame_color = "#458588"

[urgency_normal]
    background = "#1d2021"
    foreground = "#b8bb26"
    frame_color = "#d3869b"

[urgency_critical]
    background = "#1d2021"
    foreground = "#fb4934"
    frame_color = "#fe8019"
""",

    "4. 💊 Minimalist Floating Pill": """[global]
    monitor = 0
    follow = mouse
    width = (240, 320)
    height = (60, 120)
    origin = top-center
    offset = 0x30
    padding = 10
    horizontal_padding = 16
    frame_width = 1
    frame_color = "#d5c4a1"
    font = JetBrains Mono 9
    corner_radius = 18
    background = "#3c3836a0"
    foreground = "#fbf1c7"

[urgency_low]
    background = "#3c3836a0"
    foreground = "#a89984"
    frame_color = "#665c54"

[urgency_normal]
    background = "#3c3836a0"
    foreground = "#fbf1c7"
    frame_color = "#83a598"

[urgency_critical]
    background = "#504945d0"
    foreground = "#fb4934"
    frame_color = "#fb4934"
"""
}

def fix_hyprland_layer_rules():
    # 1. Remove opaque ignore_alpha 1 from windowrules.conf if present
    if os.path.exists(WINDOWRULES_CONF):
        try:
            with open(WINDOWRULES_CONF, 'r') as f:
                lines = f.readlines()
            new_lines = []
            modified = False
            for line in lines:
                if "layerrule = ignore_alpha 1, match:namespace notifications" in line:
                    new_lines.append("# layerrule = ignore_alpha 1, match:namespace notifications # disabled for true glass transparency\n")
                    modified = True
                else:
                    new_lines.append(line)
            if modified:
                with open(WINDOWRULES_CONF, 'w') as f:
                    f.writelines(new_lines)
        except Exception as e:
            print(f"Warning updating windowrules.conf: {e}")

    # 2. Add glass blur rules to userprefs.conf
    if os.path.exists(USERPREFS_CONF):
        try:
            with open(USERPREFS_CONF, 'r') as f:
                content = f.read()
            if "match:namespace notifications" not in content or "ignore_alpha 1" in content:
                # remove old notification rules in userprefs if any
                lines = [
                    l for l in content.splitlines()
                    if "match:namespace notifications" not in l
                    and l.strip() != "# Glassmorphism Transparency & Blur for Notifications"
                ]
                lines.append("# Glassmorphism Transparency & Blur for Notifications")
                lines.append("layerrule = blur 1, match:namespace notifications")
                lines.append("layerrule = ignore_alpha 0.05, match:namespace notifications")
                with open(USERPREFS_CONF, 'w') as f:
                    f.write('\n'.join(lines) + '\n')
            subprocess.run(['hyprctl', 'reload'], capture_output=True)
        except Exception as e:
            print(f"Warning updating userprefs.conf: {e}")

def apply_dunst_theme(theme_name):
    if theme_name not in THEMES:
        return False
    try:
        fix_hyprland_layer_rules()
        os.makedirs(os.path.dirname(DUNST_CONF), exist_ok=True)
        with open(DUNST_CONF, 'w') as f:
            f.write(THEMES[theme_name])
            
        # Restart Dunst daemon
        subprocess.run(["pkill", "dunst"], capture_output=True)
        subprocess.Popen(["dunst"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
        # Send test notification
        subprocess.run(["notify-send", "-u", "normal", "💎 Transparent Glass Active", "Dark background removed! Glassmorphism active."])
        return True
    except Exception as e:
        # --auto runs without a Tk window, so fall back to stderr
        if tk._default_root is not None:
            messagebox.showerror("Error", f"Failed to apply Dunst theme: {e}")
        else:
            print(f"Error: Failed to apply Dunst theme: {e}", file=sys.stderr)
        return False

class DunstThemeApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Waybar Glassmorphism Notification Theme")
        self.geometry("540x440")
        self.configure(bg='#272727')
        
        self.selected_theme = tk.StringVar(value=list(THEMES.keys())[0])
        
        self.setup_styles()
        self.build_ui()
        
    def setup_styles(self):
        style = ttk.Style()
        style.theme_use('clam')
        style.configure('.', background='#272727', foreground='#ebdbb2', font=('JetBrains Mono', 10))
        style.configure('TLabel', background='#272727', foreground='#ebdbb2')
        style.configure('TRadiobutton', background='#3c3836', foreground='#ebdbb2', font=('JetBrains Mono', 10))
        style.configure('TButton', background='#3c3836', foreground='#ebdbb2', padding=[10, 5])
        style.map('TButton', background=[('active', '#504945')])

    def build_ui(self):
        ttk.Label(self, text="💎 Waybar Glassmorphism Notification Theme", font=('JetBrains Mono', 12, 'bold'), foreground='#83a598').pack(pady=(15, 5))
        ttk.Label(self, text="Match Dunst notification popups to your 3-island glass Waybar:", font=('JetBrains Mono', 9), foreground='#a89984').pack(pady=(0, 15))
        
        frame = ttk.Frame(self)
        frame.pack(fill='both', expand=True, padx=20, pady=10)
        
        for name in THEMES.keys():
            rb = ttk.Radiobutton(frame, text=f"  {name}", value=name, variable=self.selected_theme)
            rb.pack(fill='x', pady=8, padx=5, ipady=6)
            
        btn_frame = ttk.Frame(self)
        btn_frame.pack(fill='x', side='bottom', padx=20, pady=15)
        
        ttk.Button(btn_frame, text="Close", command=self.destroy).pack(side='left')
        ttk.Button(btn_frame, text="Apply Glassmorphism Theme & Test", command=self.save).pack(side='right')

    def save(self):
        theme = self.selected_theme.get()
        if apply_dunst_theme(theme):
            messagebox.showinfo("Success", f"Applied '{theme}' notification theme successfully!")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--auto":
        apply_dunst_theme(list(THEMES.keys())[0])
        sys.exit(0)
        
    if not os.environ.get('WAYLAND_DISPLAY') and not os.environ.get('DISPLAY'):
        print("Error: Display environment not found.")
        sys.exit(1)
    app = DunstThemeApp()
    app.mainloop()
