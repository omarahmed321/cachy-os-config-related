#!/usr/bin/env python3
# =============================================================================
#   Hyprland Initial Boot Cursor Screen Selector
#   Part of: CachyOS + HyDE System Restorer
#   Repo:    https://github.com/omarahmed321/cachy-os-config-related
# =============================================================================

import os
import sys
import re
import subprocess
import tkinter as tk
from tkinter import ttk, messagebox

USERPREFS_CONF = os.path.expanduser('~/.config/hypr/userprefs.conf')

def get_monitors_list():
    monitors = []
    try:
        output = subprocess.check_output(['hyprctl', 'monitors'], text=True)
        for line in output.splitlines():
            m = re.match(r'^Monitor\s+(\S+)\s+\(ID', line)
            if m:
                monitors.append(m.group(1))
    except Exception:
        pass
    return monitors

def apply_initial_cursor_screen(screen_name):
    if not os.path.exists(USERPREFS_CONF):
        os.makedirs(os.path.dirname(USERPREFS_CONF), exist_ok=True)
        with open(USERPREFS_CONF, 'w') as f:
            f.write("# User Preferences\n")

    try:
        with open(USERPREFS_CONF, 'r') as f:
            content = f.read()

        # Remove previous initial cursor screen entries only; keybinds that use
        # focusmonitor (e.g. bind = ..., focusmonitor, ...) must be kept.
        lines = content.splitlines()
        new_lines = [
            l for l in lines
            if "initial_cursor_screen" not in l
            and not (l.strip().startswith("exec-once") and "focusmonitor" in l)
        ]

        # Append new exec-once entry
        entry = f"exec-once = hyprctl dispatch focusmonitor {screen_name} # initial_cursor_screen"
        new_lines.append(entry)

        with open(USERPREFS_CONF, 'w') as f:
            f.write('\n'.join(new_lines) + '\n')

        # Apply live; the config is already saved, so a missing Hyprland session is not an error
        try:
            subprocess.run(['hyprctl', 'dispatch', 'focusmonitor', screen_name], capture_output=True)
        except FileNotFoundError:
            pass
        return True
    except Exception as e:
        show_error(f"Failed to save initial cursor screen: {e}")
        return False

def show_error(message):
    # --set runs from the installer without a Tk window, so fall back to stderr
    if tk._default_root is not None:
        messagebox.showerror("Error", message)
    else:
        print(f"Error: {message}", file=sys.stderr)

class BootCursorApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Initial Boot Cursor Screen Selector")
        self.geometry("480x360")
        self.configure(bg='#272727')

        self.monitors = get_monitors_list()
        self.selected_screen = tk.StringVar(value=self.monitors[0] if self.monitors else "eDP-1")

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
        ttk.Label(self, text="🎯 Initial Boot Cursor Screen", font=('JetBrains Mono', 13, 'bold'), foreground='#8ec07c').pack(pady=(15, 5))
        ttk.Label(self, text="Select which screen the mouse cursor defaults to on startup:", font=('JetBrains Mono', 9), foreground='#a89984').pack(pady=(0, 15))

        frame = ttk.Frame(self)
        frame.pack(fill='both', expand=True, padx=20, pady=10)

        if not self.monitors:
            ttk.Label(frame, text="No monitors detected via hyprctl.", foreground='#fb4934').pack()
            return

        for m in self.monitors:
            rb = ttk.Radiobutton(frame, text=f"  Screen: {m}", value=m, variable=self.selected_screen)
            rb.pack(fill='x', pady=8, padx=5, ipady=6)

        btn_frame = ttk.Frame(self)
        btn_frame.pack(fill='x', side='bottom', padx=20, pady=15)

        ttk.Button(btn_frame, text="Close", command=self.destroy).pack(side='left')
        ttk.Button(btn_frame, text="Save Default Screen", command=self.save).pack(side='right')

    def save(self):
        screen = self.selected_screen.get()
        if apply_initial_cursor_screen(screen):
            messagebox.showinfo("Success", f"Initial boot cursor screen set to '{screen}'!\nSaved to ~/.config/hypr/userprefs.conf")

if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--set":
        screen_name = sys.argv[2]
        if apply_initial_cursor_screen(screen_name):
            print(f"Initial boot cursor screen set to '{screen_name}' successfully.")
            sys.exit(0)
        sys.exit(1)

    if not os.environ.get('WAYLAND_DISPLAY') and not os.environ.get('DISPLAY'):
        print("Error: Display environment not found.")
        sys.exit(1)
    app = BootCursorApp()
    app.mainloop()
