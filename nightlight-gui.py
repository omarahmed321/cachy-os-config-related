#!/usr/bin/env python3
# =============================================================================
#   Night Light GUI Panel (Hyprland / hyprsunset) — Auto-Save Mode
#   Part of: CachyOS + HyDE System Restorer
#   Repo:    https://github.com/omarahmed321/cachy-os-config-related
# =============================================================================

import gi
import subprocess
import os
import re
import threading

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, GLib, Gdk

HYPRLAND_CONF = os.path.expanduser("~/.config/hypr/hyprland.conf")
CONFIG_FILE   = os.path.expanduser("~/.config/hypr/nightlight.conf")

# --- Temperature / Percentage Mapping ---
# 0% Night Light Warmth   = 6500K (Daylight / Off)
# 100% Night Light Warmth = 2000K (Max Warm Amber)
def pct_to_temp(pct):
    pct = max(0, min(100, pct))
    return int(6500 - (pct / 100.0) * 4500)

def temp_to_pct(temp):
    temp = max(2000, min(6500, temp))
    return int(round(((6500 - temp) / 4500.0) * 100))

def get_warmth_desc(pct):
    if pct <= 0:
        return "⚪ Off · Normal Daylight (6500K)"
    elif pct <= 35:
        return f"🟡 Soft Warmth ({pct_to_temp(pct)}K)"
    elif pct <= 70:
        return f"🟠 Balanced Night Warmth ({pct_to_temp(pct)}K)"
    else:
        return f"🔴 Deep Amber Night Mode ({pct_to_temp(pct)}K)"

# --- Backend Config Functions ---
def _load_conf():
    t, en = 3500, True
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r") as f:
                c = f.read()
            m_t = re.search(r"^\s*(?:ENABLE_NIGHTLIGHT|temperature)=(\d+)", c, re.M)
            m_e = re.search(r"^\s*(?:HYPRSUNSET_ENABLED|enabled)=(true|false)", c, re.M)
            if m_t: t = int(m_t.group(1))
            if m_e: en = (m_e.group(1) == "true")
        except Exception:
            pass
    return t, en

def _save_conf(t, en):
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    en_str = "true" if en else "false"
    with open(CONFIG_FILE, "w") as f:
        f.write(f"""# Night Light Configuration — managed by nightlight-gui.py
temperature={t}
enabled={en_str}
ENABLE_NIGHTLIGHT={t}
HYPRSUNSET_ENABLED={en_str}
""")

def _apply_live(t, en):
    # Kill any existing hyprsunset daemon instances
    subprocess.run(["pkill", "-9", "-x", "hyprsunset"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    if not en or t >= 6400:
        return

    try:
        # Spawn hyprsunset as a persistent background daemon
        subprocess.Popen(
            ["hyprsunset", "-t", str(t)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True
        )
    except Exception as e:
        print(f"[!] Failed to run hyprsunset: {e}")

def _patch_hyprland(t, en):
    if not os.path.exists(HYPRLAND_CONF):
        return
    try:
        with open(HYPRLAND_CONF, "r") as f:
            lines = f.readlines()
        exec_line = "exec-once = bash ~/.local/share/bin/nightlight-start.sh\n"
        has_exec = any("nightlight-start.sh" in l for l in lines)
        if not has_exec:
            lines.append("\n# Auto-start Night Light\n" + exec_line)
            with open(HYPRLAND_CONF, "w") as f:
                f.writelines(lines)
    except Exception:
        pass

# --- Clean & Modern UI Window ---
CSS = """
window { background-color: transparent; }

.main-card {
    background: alpha(@window_bg_color, 0.95);
    border-radius: 20px;
    border: 1px solid alpha(@window_fg_color, 0.1);
    padding: 24px;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.4);
}

.title-label {
    font-size: 17px;
    font-weight: 800;
}

.slider-label {
    font-size: 13px;
    font-weight: 700;
    margin-top: 10px;
}

.val-badge {
    font-size: 16px;
    font-weight: 800;
    color: @accent_color;
}

.desc-label {
    font-size: 11px;
    opacity: 0.75;
    margin-top: 2px;
}

.status-label {
    font-size: 11px;
    font-weight: 700;
    opacity: 0.6;
}

scale trough {
    border-radius: 8px;
    min-height: 12px;
}
"""

class NightLightApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id="org.cachyos.nightlight")
        self.connect("activate", self.on_activate)

    def on_activate(self, app):
        p = Gtk.CssProvider()
        p.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        win = Adw.ApplicationWindow(application=app, title="Night Light Control")
        win.set_default_size(380, 200)

        t, en = _load_conf()
        self._t = t
        self._en = en
        self._timer = None

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        card.add_css_class("main-card")

        # Header Row with Switch Toggle
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        title = Gtk.Label(label="🌙 Night Light Control")
        title.add_css_class("title-label")
        title.set_hexpand(True)
        title.set_halign(Gtk.Align.START)
        header.append(title)

        self.toggle = Gtk.Switch()
        self.toggle.set_active(self._en)
        self.toggle.connect("state-set", self._on_toggle)
        header.append(self.toggle)
        card.append(header)

        # Divider
        card.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        # Slider: Night Light Warmth (Percentage 0% - 100%)
        initial_pct = temp_to_pct(self._t)

        row_nl = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        lbl_nl = Gtk.Label(label="Night Light Warmth")
        lbl_nl.add_css_class("slider-label")
        lbl_nl.set_hexpand(True)
        lbl_nl.set_halign(Gtk.Align.START)
        row_nl.append(lbl_nl)

        self.val_nl = Gtk.Label(label=f"{initial_pct}%")
        self.val_nl.add_css_class("val-badge")
        row_nl.append(self.val_nl)
        card.append(row_nl)

        self.desc_nl = Gtk.Label(label=get_warmth_desc(initial_pct))
        self.desc_nl.add_css_class("desc-label")
        self.desc_nl.set_halign(Gtk.Align.START)
        card.append(self.desc_nl)

        self.scale_nl = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
        self.scale_nl.set_value(initial_pct)
        self.scale_nl.set_sensitive(self._en)
        self.scale_nl.connect("value-changed", self._on_temp_pct_changed)
        card.append(self.scale_nl)

        self.status_lbl = Gtk.Label(label="✓ Auto-saved")
        self.status_lbl.add_css_class("status-label")
        self.status_lbl.set_margin_top(4)
        card.append(self.status_lbl)

        win.set_content(card)
        win.present()

    def _on_toggle(self, sw, state):
        self._en = state
        self.scale_nl.set_sensitive(state)
        self._debounce()
        return False

    def _on_temp_pct_changed(self, sc):
        pct = int(sc.get_value())
        self.val_nl.set_label(f"{pct}%")
        self.desc_nl.set_label(get_warmth_desc(pct))
        self._t = pct_to_temp(pct)
        self._debounce()

    def _debounce(self):
        if self._timer:
            GLib.source_remove(self._timer)
        self._timer = GLib.timeout_add(250, self._do_apply_and_save)

    def _do_apply_and_save(self):
        self._timer = None
        def _do():
            _save_conf(self._t, self._en)
            _patch_hyprland(self._t, self._en)
            _apply_live(self._t, self._en)
        threading.Thread(target=_do, daemon=True).start()
        return False

if __name__ == "__main__":
    app = NightLightApp()
    app.run(None)
