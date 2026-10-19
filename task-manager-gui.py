#!/usr/bin/env python3
# =============================================================================
#   Interactive Task Manager GUI Picker (doing / donetask / rmtask / edittask)
#   Part of: CachyOS + HyDE System Restorer
#   Repo:    https://github.com/omarahmed321/cachy-os-config-related
# =============================================================================

import os
import sys
import tkinter as tk
from tkinter import ttk, messagebox, simpledialog

TASKS_FILE = os.path.expanduser("~/.config/fastfetch/tasks.txt")

def read_tasks():
    if not os.path.exists(TASKS_FILE):
        return []
    with open(TASKS_FILE, 'r') as f:
        return [line.strip() for line in f if line.strip()]

def write_tasks(tasks):
    os.makedirs(os.path.dirname(TASKS_FILE), exist_ok=True)
    with open(TASKS_FILE, 'w') as f:
        for t in tasks:
            f.write(t + "\n")

class TaskManagerGUI(tk.Tk):
    def __init__(self, mode="all"):
        super().__init__()
        self.mode = mode  # 'doing', 'done', 'remove', 'edit', 'all'
        self.title(f"Task Manager GUI - Mode: {self.mode.upper()}")
        self.geometry("580x480")
        self.configure(bg='#272727')
        
        self.setup_styles()
        self.build_ui()
        self.refresh_task_list()
        
    def setup_styles(self):
        style = ttk.Style()
        style.theme_use('clam')
        style.configure('.', background='#272727', foreground='#ebdbb2', font=('JetBrains Mono', 10))
        style.configure('TLabel', background='#272727', foreground='#ebdbb2')
        style.configure('TFrame', background='#272727')
        style.configure('TButton', background='#3c3836', foreground='#ebdbb2', padding=[8, 4])
        style.map('TButton', background=[('active', '#504945')])

    def build_ui(self):
        # Header
        header_frame = ttk.Frame(self)
        header_frame.pack(fill='x', padx=15, pady=10)
        
        ttk.Label(header_frame, text="📝 Interactive Task Manager", font=('JetBrains Mono', 12, 'bold'), foreground='#fabd2f').pack(side='left')
        
        # Task Listbox Frame
        list_frame = ttk.Frame(self)
        list_frame.pack(fill='both', expand=True, padx=15, pady=5)
        
        scrollbar = ttk.Scrollbar(list_frame, orient='vertical')
        self.task_listbox = tk.Listbox(
            list_frame,
            bg='#3c3836',
            fg='#ebdbb2',
            selectbackground='#504945',
            selectforeground='#b8bb26',
            font=('JetBrains Mono', 10),
            activestyle='none',
            highlightthickness=0,
            yscrollcommand=scrollbar.set
        )
        scrollbar.config(command=self.task_listbox.yview)
        
        scrollbar.pack(side='right', fill='y')
        self.task_listbox.pack(side='left', fill='both', expand=True)
        
        # Action Buttons
        act_frame = ttk.Frame(self)
        act_frame.pack(fill='x', padx=15, pady=10)
        
        ttk.Button(act_frame, text="🟡 Mark Doing [/]", command=lambda: self.change_status("[/]")).pack(side='left', padx=3)
        ttk.Button(act_frame, text="🟢 Mark Done [x]", command=lambda: self.change_status("[x]")).pack(side='left', padx=3)
        ttk.Button(act_frame, text="⚪ Mark Todo [ ]", command=lambda: self.change_status("[ ]")).pack(side='left', padx=3)
        ttk.Button(act_frame, text="✏️ Edit Task", command=self.edit_selected).pack(side='left', padx=3)
        ttk.Button(act_frame, text="❌ Delete Task", command=self.delete_selected).pack(side='left', padx=3)
        
        # Bottom New Task & Fastfetch Refresh
        bottom_frame = ttk.Frame(self)
        bottom_frame.pack(fill='x', padx=15, pady=(0, 10))
        
        self.new_entry = ttk.Entry(bottom_frame, font=('JetBrains Mono', 10))
        self.new_entry.pack(side='left', fill='x', expand=True, padx=(0, 5))
        self.new_entry.bind("<Return>", lambda e: self.add_new_task())
        
        ttk.Button(bottom_frame, text="➕ Add Task", command=self.add_new_task).pack(side='right')

    def refresh_task_list(self):
        self.tasks = read_tasks()
        self.task_listbox.delete(0, tk.END)
        for t in self.tasks:
            self.task_listbox.insert(tk.END, f"  {t}")

    def get_selected_idx(self):
        sel = self.task_listbox.curselection()
        if not sel:
            messagebox.showwarning("Warning", "Please select a task from the list.")
            return None
        return sel[0]

    def change_status(self, new_prefix):
        idx = self.get_selected_idx()
        if idx is None:
            return
            
        raw_text = self.tasks[idx]
        content = raw_text
        for pfx in ["[ ]", "[/]", "[x]", "- "]:
            if raw_text.startswith(pfx):
                content = raw_text[len(pfx):].strip()
                break
                
        self.tasks[idx] = f"{new_prefix} {content}"
        write_tasks(self.tasks)
        self.refresh_task_list()

    def edit_selected(self):
        idx = self.get_selected_idx()
        if idx is None:
            return
            
        raw_text = self.tasks[idx]
        pfx_found = "[ ]"
        content = raw_text
        for pfx in ["[ ]", "[/]", "[x]", "- "]:
            if raw_text.startswith(pfx):
                pfx_found = pfx
                content = raw_text[len(pfx):].strip()
                break
                
        edited = simpledialog.askstring("Edit Task", "Update task description:", initialvalue=content, parent=self)
        if edited and edited.strip():
            self.tasks[idx] = f"{pfx_found} {edited.strip()}"
            write_tasks(self.tasks)
            self.refresh_task_list()

    def delete_selected(self):
        idx = self.get_selected_idx()
        if idx is None:
            return
            
        del self.tasks[idx]
        write_tasks(self.tasks)
        self.refresh_task_list()

    def add_new_task(self):
        text = self.new_entry.get().strip()
        if text:
            self.tasks.append(f"[ ] {text}")
            write_tasks(self.tasks)
            self.new_entry.delete(0, tk.END)
            self.refresh_task_list()

if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"
    app = TaskManagerGUI(mode)
    app.mainloop()
