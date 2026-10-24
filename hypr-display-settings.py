#!/usr/bin/env python3
# =============================================================================
#   CachyOS Display & Mouse Settings Panel (Hyprland)
#   Part of: CachyOS + HyDE Complete System Restorer
#   Repo:    https://github.com/omarahmed321/cachy-os-config-related
# =============================================================================

import os
import re
import sys
import subprocess
import tkinter as tk
from tkinter import ttk, messagebox

# --- CONFIG PATHS ---
MONITORS_CONF = os.path.expanduser('~/.config/hypr/monitors.conf')
USERPREFS_CONF = os.path.expanduser('~/.config/hypr/userprefs.conf')

# --- HELPERS ---
def get_monitor_info():
    try:
        output = subprocess.check_output(['hyprctl', 'monitors'], text=True)
    except Exception as e:
        messagebox.showerror("Error", f"Failed to run 'hyprctl monitors': {e}")
        sys.exit(1)

    monitors = {}
    chunks = output.split('Monitor ')[1:]
    for chunk in chunks:
        lines = chunk.strip().split('\n')
        if not lines:
            continue
        
        match_name = re.match(r'^(\S+)\s+\(ID', lines[0])
        if not match_name:
            continue
        name = match_name.group(1)
        
        info = {
            'name': name,
            'model': 'Unknown',
            'current_mode': '',
            'position': '0x0',
            'scale': '1.00',
            'available_modes': {},
            'transform': 0
        }
        
        if len(lines) > 1:
            match_mode = re.search(r'(\d+x\d+@\d+(?:\.\d+)?)\s+at\s+(-?\d+x-?\d+)', lines[1])
            if match_mode:
                info['current_mode'] = match_mode.group(1)
                info['position'] = match_mode.group(2)
        
        for line in lines:
            line_str = line.strip()
            if line_str.startswith('model:'):
                info['model'] = line_str.split('model:')[1].strip()
            elif line_str.startswith('scale:'):
                info['scale'] = line_str.split('scale:')[1].strip()
            elif line_str.startswith('transform:'):
                try:
                    info['transform'] = int(line_str.split('transform:')[1].strip())
                except ValueError:
                    pass
            elif line_str.startswith('availableModes:'):
                modes_str = line_str.split('availableModes:')[1].strip()
                modes_list = modes_str.split()
                
                # Group modes by resolution
                grouped = {}
                for mode in modes_list:
                    m = re.match(r'^(\d+x\d+)@([\d\.]+(?:Hz)?)$', mode)
                    if m:
                        res = m.group(1)
                        hz = m.group(2).replace('Hz', '')
                        try:
                            hz_float = float(hz)
                            hz_str = str(int(round(hz_float))) if abs(hz_float - round(hz_float)) < 0.05 else f"{hz_float:.2f}"
                        except ValueError:
                            hz_str = hz
                        
                        if res not in grouped:
                            grouped[res] = []
                        if hz_str not in grouped[res]:
                            grouped[res].append(hz_str)
                
                # Sort resolutions and refresh rates descending
                sorted_res = sorted(grouped.keys(), key=lambda r: [int(x) for x in r.split('x')], reverse=True)
                sorted_grouped = {}
                for r in sorted_res:
                    sorted_grouped[r] = sorted(grouped[r], key=float, reverse=True)
                
                info['available_modes'] = sorted_grouped
                
        monitors[name] = info
    
    # Parse existing monitors.conf to preserve position if set
    if os.path.exists(MONITORS_CONF):
        try:
            with open(MONITORS_CONF, 'r') as f:
                content = f.read()
            for name in monitors:
                match_line = re.search(r'^\s*monitor\s*=\s*' + re.escape(name) + r'\s*,\s*[^,\n]+\s*,\s*([^,\n]+)', content, re.MULTILINE)
                if match_line:
                    saved_pos = match_line.group(1).strip()
                    if saved_pos and saved_pos != 'auto':
                        monitors[name]['position'] = saved_pos
        except Exception:
            pass

    return monitors

def get_mouse_sensitivity():
    if not os.path.exists(USERPREFS_CONF):
        return 0.0
    try:
        with open(USERPREFS_CONF, 'r') as f:
            content = f.read()
        match = re.search(r'^\s*sensitivity\s*=\s*([-\d\.]+)', content, re.MULTILINE)
        if match:
            return float(match.group(1))
    except Exception:
        pass
    return 0.0

def set_mouse_sensitivity(value):
    try:
        os.makedirs(os.path.dirname(USERPREFS_CONF), exist_ok=True)
        if not os.path.exists(USERPREFS_CONF):
            with open(USERPREFS_CONF, 'w') as f:
                f.write("# User Preferences\ninput {\n    sensitivity = 0.00\n}\n")
        
        with open(USERPREFS_CONF, 'r') as f:
            content = f.read()
        
        pattern = r'^(\s*sensitivity\s*=\s*)[-\d\.]+'
        if re.search(pattern, content, re.MULTILINE):
            new_content = re.sub(pattern, rf'\g<1>{value:.2f}', content, flags=re.MULTILINE)
        else:
            match = re.search(r'input\s*\{', content)
            if match:
                start_idx = match.end()
                brace_count = 1
                end_idx = -1
                for i in range(start_idx, len(content)):
                    if content[i] == '{':
                        brace_count += 1
                    elif content[i] == '}':
                        brace_count -= 1
                        if brace_count == 0:
                            end_idx = i
                            break
                if end_idx != -1:
                    before = content[:end_idx]
                    after = content[end_idx:]
                    if before and not before.endswith('\n'):
                        before += '\n'
                    new_content = before + f"    sensitivity = {value:.2f}\n" + after
                else:
                    new_content = content + f"\ninput {{\n    sensitivity = {value:.2f}\n}}\n"
            else:
                new_content = content + f"\ninput {{\n    sensitivity = {value:.2f}\n}}\n"
                
        with open(USERPREFS_CONF, 'w') as f:
            f.write(new_content)
        return True
    except Exception:
        return False

def get_touchpad_natural_scroll():
    if not os.path.exists(USERPREFS_CONF):
        return True
    try:
        with open(USERPREFS_CONF, 'r') as f:
            content = f.read()
        match = re.search(r'natural_scroll\s*=\s*(true|false)', content)
        if match:
            return match.group(1) == 'true'
    except Exception:
        pass
    return True

def set_touchpad_natural_scroll(enabled):
    try:
        os.makedirs(os.path.dirname(USERPREFS_CONF), exist_ok=True)
        if not os.path.exists(USERPREFS_CONF):
            with open(USERPREFS_CONF, 'w') as f:
                f.write("# User Preferences\n")
        
        with open(USERPREFS_CONF, 'r') as f:
            content = f.read()
        
        touchpad_pattern = r'(touchpad\s*\{[^}]*natural_scroll\s*=\s*)(true|false)'
        if re.search(touchpad_pattern, content):
            new_content = re.sub(touchpad_pattern, rf'\g<1>{"true" if enabled else "false"}', content)
        else:
            touchpad_block_pattern = r'touchpad\s*\{'
            match_tp = re.search(touchpad_block_pattern, content)
            if match_tp:
                start_idx = match_tp.end()
                brace_count = 1
                end_idx = -1
                for i in range(start_idx, len(content)):
                    if content[i] == '{':
                        brace_count += 1
                    elif content[i] == '}':
                        brace_count -= 1
                        if brace_count == 0:
                            end_idx = i
                            break
                if end_idx != -1:
                    before = content[:end_idx]
                    after = content[end_idx:]
                    if before and not before.endswith('\n'):
                        before += '\n'
                    new_content = before + f"        natural_scroll = {'true' if enabled else 'false'}\n" + after
                else:
                    new_content = content + f"\ninput {{\n    touchpad {{\n        natural_scroll = {'true' if enabled else 'false'}\n    }}\n}}\n"
            else:
                match_in = re.search(r'input\s*\{', content)
                if match_in:
                    start_idx = match_in.end()
                    brace_count = 1
                    end_idx = -1
                    for i in range(start_idx, len(content)):
                        if content[i] == '{':
                            brace_count += 1
                        elif content[i] == '}':
                            brace_count -= 1
                            if brace_count == 0:
                                end_idx = i
                                break
                    if end_idx != -1:
                        before = content[:end_idx]
                        after = content[end_idx:]
                        if before and not before.endswith('\n'):
                            before += '\n'
                        tp_block = f"    touchpad {{\n        natural_scroll = {'true' if enabled else 'false'}\n    }}\n"
                        new_content = before + tp_block + after
                    else:
                        new_content = content + f"\ninput {{\n    touchpad {{\n        natural_scroll = {'true' if enabled else 'false'}\n    }}\n}}\n"
                else:
                    new_content = content + f"\ninput {{\n    touchpad {{\n        natural_scroll = {'true' if enabled else 'false'}\n    }}\n}}\n"
                
        with open(USERPREFS_CONF, 'w') as f:
            f.write(new_content)
        return True
    except Exception:
        return False

def update_monitor_config(name, resolution, hz, scale, pos, transform_val=0):
    try:
        os.makedirs(os.path.dirname(MONITORS_CONF), exist_ok=True)
        if not os.path.exists(MONITORS_CONF):
            with open(MONITORS_CONF, 'w') as f:
                f.write("# Monitor Rules\n")
                
        with open(MONITORS_CONF, 'r') as f:
            lines = f.readlines()
        
        position = pos if pos and pos != 'auto' else '0x0'
        res_hz = f"{resolution}@{hz}"

        def build_line(extras):
            # extras: key/value pairs after the scale (vrr, icc, bitdepth, cm, ...);
            # only transform is owned by this dialog, everything else is kept
            pairs = [(k, v) for k, v in extras if k != 'transform']
            if transform_val > 0:
                pairs.insert(0, ('transform', str(transform_val)))
            extra_str = "".join(f",{k},{v}" for k, v in pairs)
            return f"monitor = {name},{res_hz},{position},{scale}{extra_str}\n"

        updated = False
        for i, line in enumerate(lines):
            match = re.match(r'^\s*monitor\s*=\s*([\w\-]+)\s*,(.*)$', line)
            if match and match.group(1) == name:
                fields = [f.strip() for f in match.group(2).split('#')[0].split(',')]
                rest = fields[3:]
                extras = list(zip(rest[0::2], rest[1::2]))
                lines[i] = build_line(extras)
                updated = True
                break
        new_line = build_line([])
                
        if not updated:
            insert_idx = len(lines)
            for idx, line in enumerate(lines):
                if 'Workspace Rules' in line:
                    insert_idx = idx
                    break
            lines.insert(insert_idx, new_line)
            
        with open(MONITORS_CONF, 'w') as f:
            f.writelines(lines)
        return True
    except Exception:
        return False

# --- GUI APP ---
class DisplaySettingsApp(tk.Tk):
    def __init__(self):
        super().__init__()
        
        self.title("CachyOS Display & Mouse Settings")
        self.geometry("540x500")
        self.configure(bg='#272727')
        
        # Load data
        self.monitors = get_monitor_info()
        self.current_sens = get_mouse_sensitivity()
        
        # Style
        self.setup_styles()
        
        # Build UI
        self.build_ui()
        
    def setup_styles(self):
        style = ttk.Style()
        style.theme_use('clam')
        
        style.configure('.', background='#272727', foreground='#ebdbb2', font=('JetBrains Mono', 10))
        style.configure('TLabel', background='#272727', foreground='#ebdbb2')
        style.configure('TFrame', background='#272727')
        
        style.configure('TNotebook', background='#272727', borderwidth=0)
        style.configure('TNotebook.Tab', background='#3c3836', foreground='#a89984', padding=[12, 6])
        style.map('TNotebook.Tab', background=[('selected', '#272727')], foreground=[('selected', '#ebdbb2')])
        
        style.configure('TCombobox', fieldbackground='#3c3836', background='#504945', foreground='#ebdbb2')
        style.map('TCombobox', fieldbackground=[('readonly', '#3c3836')], foreground=[('readonly', '#ebdbb2')])

        style.configure('TEntry', fieldbackground='#3c3836', foreground='#ebdbb2')
        
        style.configure('TButton', background='#3c3836', foreground='#ebdbb2', borderwidth=1, focuscolor='none', padding=[10, 5])
        style.map('TButton', background=[('active', '#504945')])

    def build_ui(self):
        # Notebook for Tabs
        notebook = ttk.Notebook(self)
        notebook.pack(fill='both', expand=True, padx=15, pady=15)
        
        # --- TAB 1: DISPLAY ---
        display_frame = ttk.Frame(notebook)
        notebook.add(display_frame, text="Display Settings")
        
        # Monitor Select
        ttk.Label(display_frame, text="Monitor:").grid(row=0, column=0, sticky='w', pady=10, padx=10)
        self.monitor_names = list(self.monitors.keys())
        self.monitor_display_names = [f"{name} ({self.monitors[name]['model']})" for name in self.monitor_names]
        
        self.monitor_combo = ttk.Combobox(display_frame, values=self.monitor_display_names, state="readonly", width=32)
        self.monitor_combo.grid(row=0, column=1, sticky='w', pady=10, padx=10)
        self.monitor_combo.bind("<<ComboboxSelected>>", self.on_monitor_select)
        
        # Resolution Select
        ttk.Label(display_frame, text="Resolution:").grid(row=1, column=0, sticky='w', pady=10, padx=10)
        self.res_combo = ttk.Combobox(display_frame, state="readonly", width=20)
        self.res_combo.grid(row=1, column=1, sticky='w', pady=10, padx=10)
        self.res_combo.bind("<<ComboboxSelected>>", self.on_res_select)
        
        # Refresh Rate Input (Direct Custom Text Entry + Detected Presets Dropdown)
        ttk.Label(display_frame, text="Refresh Rate (Hz):").grid(row=2, column=0, sticky='w', pady=10, padx=10)
        hz_input_frame = ttk.Frame(display_frame)
        hz_input_frame.grid(row=2, column=1, sticky='w', pady=10, padx=10)

        self.hz_entry = ttk.Entry(hz_input_frame, width=10, font=('JetBrains Mono', 10))
        self.hz_entry.pack(side='left', padx=(0, 10))
        self.hz_entry.insert(0, "60")

        self.hz_preset_combo = ttk.Combobox(hz_input_frame, state="readonly", width=14)
        self.hz_preset_combo.pack(side='left', padx=2)
        self.hz_preset_combo.bind("<<ComboboxSelected>>", self.on_hz_preset_select)

        # Scaling Select (Direct Custom Text Entry + Preset Selector)
        ttk.Label(display_frame, text="System Zoom (Scale):").grid(row=3, column=0, sticky='w', pady=10, padx=10)
        scale_input_frame = ttk.Frame(display_frame)
        scale_input_frame.grid(row=3, column=1, sticky='w', pady=10, padx=10)

        self.scale_entry = ttk.Entry(scale_input_frame, width=10, font=('JetBrains Mono', 10))
        self.scale_entry.pack(side='left', padx=(0, 10))
        self.scale_entry.insert(0, "1")

        self.scale_preset_combo = ttk.Combobox(
            scale_input_frame,
            values=["1 (100%)", "1.25 (125%)", "1.5 (150%)", "1.67 (167%)", "1.75 (175%)", "2 (200%)"],
            state="readonly", width=14
        )
        self.scale_preset_combo.pack(side='left', padx=2)
        self.scale_preset_combo.bind("<<ComboboxSelected>>", self.on_scale_preset_select)

        # Orientation Select
        ttk.Label(display_frame, text="Orientation:").grid(row=4, column=0, sticky='w', pady=10, padx=10)
        self.rot_values = ["Landscape (Normal)", "Portrait (90°)", "Flipped Landscape (180°)", "Flipped Portrait (270°)"]
        self.rot_combo = ttk.Combobox(display_frame, values=self.rot_values, state="readonly", width=25)
        self.rot_combo.grid(row=4, column=1, sticky='w', pady=10, padx=10)
        
        # --- TAB 2: MOUSE ---
        mouse_frame = ttk.Frame(notebook)
        notebook.add(mouse_frame, text="Mouse Sensitivity")
        
        ttk.Label(mouse_frame, text="Adjust Pointer Sensitivity:", font=('JetBrains Mono', 11, 'bold')).pack(anchor='w', pady=15, padx=15)
        ttk.Label(mouse_frame, text="Slide left to slow down, right to speed up (-1.00 to +1.00):").pack(anchor='w', pady=5, padx=15)
        
        # Sens Slider Frame
        slider_frame = ttk.Frame(mouse_frame)
        slider_frame.pack(fill='x', padx=15, pady=20)
        
        self.sens_val_var = tk.StringVar(value=f"{self.current_sens:.2f}")
        
        self.sens_slider = tk.Scale(
            slider_frame, from_=-1.0, to=1.0, resolution=0.05, orient='horizontal',
            bg='#3c3836', fg='#ebdbb2', troughcolor='#272727', highlightbackground='#272727',
            activebackground='#504945', showvalue=False, command=self.on_slider_move
        )
        self.sens_slider.set(self.current_sens)
        self.sens_slider.pack(side='left', fill='x', expand=True, padx=5)
        
        sens_label = ttk.Label(slider_frame, textvariable=self.sens_val_var, font=('JetBrains Mono', 12, 'bold'), width=6, anchor='center')
        sens_label.pack(side='right', padx=10)
        
        # Accel Note
        ttk.Label(mouse_frame, text="* Accel profile is forced to 'flat' to ensure raw mouse precision.", foreground='#a89984').pack(anchor='w', padx=15, pady=10)

        # Touchpad Settings Separator
        ttk.Separator(mouse_frame, orient='horizontal').pack(fill='x', padx=15, pady=15)
        
        ttk.Label(mouse_frame, text="Touchpad Settings:", font=('JetBrains Mono', 11, 'bold')).pack(anchor='w', padx=15, pady=5)
        
        self.touchpad_var = tk.BooleanVar(value=not get_touchpad_natural_scroll())
        self.touchpad_check = ttk.Checkbutton(
            mouse_frame, text="Windows-style Touchpad Scrolling (Reverse/Standard)",
            variable=self.touchpad_var
        )
        self.touchpad_check.pack(anchor='w', padx=20, pady=10)

        # --- BOTTOM ACTION PANEL ---
        btn_frame = ttk.Frame(self)
        btn_frame.pack(fill='x', side='bottom', padx=15, pady=15)
        
        cancel_btn = ttk.Button(btn_frame, text="Close", command=self.destroy)
        cancel_btn.pack(side='left', padx=5)
        
        apply_btn = ttk.Button(btn_frame, text="Apply & Save Settings", command=self.apply_settings)
        apply_btn.pack(side='right', padx=5)
        
        # Set defaults if monitors exist
        if self.monitor_names:
            self.monitor_combo.current(0)
            self.on_monitor_select(None)

    def on_hz_preset_select(self, event):
        selected = self.hz_preset_combo.get().replace('Hz', '').strip()
        self.hz_entry.delete(0, tk.END)
        self.hz_entry.insert(0, selected)

    def on_scale_preset_select(self, event):
        selected = self.scale_preset_combo.get().split()[0]
        self.scale_entry.delete(0, tk.END)
        self.scale_entry.insert(0, selected)

    def on_monitor_select(self, event):
        m_idx = self.monitor_combo.current()
        m_name = self.monitor_names[m_idx]
        m_info = self.monitors[m_name]
        
        # Update resolutions
        resolutions = list(m_info['available_modes'].keys())
        self.res_combo.configure(values=resolutions)
        
        # Pre-select current or highest resolution
        current_res = m_info['current_mode'].split('@')[0]
        if current_res in resolutions:
            self.res_combo.set(current_res)
        elif resolutions:
            self.res_combo.current(0)
            
        self.on_res_select(None)
        
        # Pre-select current scale into Entry
        curr_scale = m_info['scale']
        self.scale_entry.delete(0, tk.END)
        self.scale_entry.insert(0, curr_scale)

        # Pre-select current transform/rotation
        trans_val = m_info.get('transform', 0)
        if trans_val < len(self.rot_values):
            self.rot_combo.current(trans_val)
        else:
            self.rot_combo.current(0)

    def on_res_select(self, event):
        m_idx = self.monitor_combo.current()
        m_name = self.monitor_names[m_idx]
        m_info = self.monitors[m_name]
        
        selected_res = self.res_combo.get()
        if selected_res in m_info['available_modes']:
            refresh_rates = m_info['available_modes'][selected_res]
            self.hz_preset_combo.configure(values=[f"{r} Hz" for r in refresh_rates])
            
            # Match current refresh rate
            current_hz = m_info['current_mode'].split('@')[1] if '@' in m_info['current_mode'] else ''
            try:
                hz_float = float(current_hz)
                curr_hz_str = str(int(round(hz_float))) if abs(hz_float - round(hz_float)) < 0.05 else f"{hz_float:.2f}"
            except ValueError:
                curr_hz_str = current_hz
            
            self.hz_entry.delete(0, tk.END)
            self.hz_entry.insert(0, curr_hz_str if curr_hz_str else "60")
            
            if refresh_rates:
                self.hz_preset_combo.current(0)

    def on_slider_move(self, value):
        self.sens_val_var.set(f"{float(value):+.2f}")

    def apply_settings(self):
        m_idx = self.monitor_combo.current()
        if m_idx < 0:
            messagebox.showerror("Error", "No monitor selected.")
            return
            
        m_name = self.monitor_names[m_idx]
        m_info = self.monitors[m_name]
        
        selected_res = self.res_combo.get()
        selected_hz_raw = self.hz_entry.get().strip().replace('Hz', '').strip()
        selected_scale = self.scale_entry.get().strip()
        
        try:
            scale_val = float(selected_scale)
            if scale_val <= 0:
                raise ValueError
        except ValueError:
            messagebox.showerror("Error", "Please enter a valid positive number for scaling (e.g., 1, 1.25, 1.5, 1.67).")
            return
            
        try:
            hz_val = float(selected_hz_raw)
            if hz_val <= 0:
                raise ValueError
            selected_hz = str(int(round(hz_val))) if abs(hz_val - round(hz_val)) < 0.05 else f"{hz_val:.2f}"
        except ValueError:
            messagebox.showerror("Error", "Please enter a valid positive number for refresh rate (e.g., 60, 120, 144, 165, 240).")
            return
        
        if not selected_res or not selected_hz or not selected_scale:
            messagebox.showerror("Error", "Please make sure resolution, refresh rate, and scaling are set.")
            return
            
        position = m_info['position'] if m_info['position'] and m_info['position'] != 'auto' else '0x0'
        transform_val = self.rot_combo.current()
        extra_str = f",transform,{transform_val}" if transform_val > 0 else ""
        
        cmd_str = f"{m_name},{selected_res}@{selected_hz},{position},{selected_scale}{extra_str}"
        
        try:
            # 1. Apply live keyword setting
            subprocess.run(['hyprctl', 'keyword', 'monitor', cmd_str], check=True)
            # 2. Update monitors.conf file permanently
            update_monitor_config(m_name, selected_res, selected_hz, selected_scale, position, transform_val)
            # 3. Trigger Hyprland config reload
            subprocess.run(['hyprctl', 'reload'], capture_output=True)
        except Exception as e:
            messagebox.showerror("Error", f"Failed to apply display settings: {e}")
            return
            
        # 4. Update Mouse Sensitivity
        sens_value = self.sens_slider.get()
        try:
            subprocess.run(['hyprctl', 'keyword', 'input:sensitivity', f"{sens_value:.2f}"], check=True)
            set_mouse_sensitivity(sens_value)
        except Exception as e:
            messagebox.showerror("Error", f"Failed to apply mouse sensitivity: {e}")
            return

        # 5. Update Touchpad Scrolling Direction
        touchpad_windows_style = self.touchpad_var.get()
        natural_scroll = not touchpad_windows_style
        try:
            subprocess.run(['hyprctl', 'keyword', 'input:touchpad:natural_scroll', 'true' if natural_scroll else 'false'], check=True)
            set_touchpad_natural_scroll(natural_scroll)
        except Exception as e:
            messagebox.showerror("Error", f"Failed to apply touchpad settings: {e}")
            return
            
        messagebox.showinfo("Success", f"Display mode ({selected_res}@{selected_hz}Hz) and scale ({selected_scale}) applied successfully!")
        
        self.monitors = get_monitor_info()
        self.current_sens = get_mouse_sensitivity()
        self.touchpad_var.set(not get_touchpad_natural_scroll())

if __name__ == "__main__":
    if not os.environ.get('WAYLAND_DISPLAY'):
        print("Error: Wayland display not found. This tool is designed for Hyprland.")
        sys.exit(1)
    
    app = DisplaySettingsApp()
    app.mainloop()
