#!/usr/bin/env python3
# =============================================================================
#   CachyOS & HyDE Unified Task Manager CLI & GUI Backend
#   Part of: CachyOS + HyDE System Restorer
# =============================================================================

import sys
import os

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

def strip_prefix(task):
    for pfx in ["[ ]", "[/]", "[x]", "- "]:
        if task.startswith(pfx):
            return task[len(pfx):].strip()
    return task

def add_or_update(task_text, new_prefix):
    tasks = read_tasks()
    found = False
    new_tasks = []
    
    raw_query = task_text.strip()
    cleaned_query = raw_query.lower()
    
    # Strip prefix from query if provided
    for pfx in ["[ ]", "[/]", "[x]", "- "]:
        if cleaned_query.startswith(pfx.lower()):
            cleaned_query = cleaned_query[len(pfx):].strip()
            break

    for t in tasks:
        content = t
        for pfx in ["[ ]", "[/]", "[x]", "- "]:
            if t.startswith(pfx):
                content = t[len(pfx):].strip()
                break
        
        if content.lower() == cleaned_query or t.strip().lower() == raw_query.lower():
            new_tasks.append(f"{new_prefix} {content}")
            found = True
        else:
            new_tasks.append(t)
            
    if not found:
        new_tasks.append(f"{new_prefix} {raw_query}")
        
    write_tasks(new_tasks)

def main():
    if len(sys.argv) < 3:
        sys.exit(0)
        
    action = sys.argv[1]
    target_task = ' '.join(sys.argv[2:])
    
    if action == "todo":
        add_or_update(target_task, "[ ]")
    elif action == "doing":
        add_or_update(target_task, "[/]")
    elif action == "done":
        add_or_update(target_task, "[x]")
    elif action == "remove":
        tasks = read_tasks()
        # Exact match only: a substring match would also delete unrelated tasks
        # (removing "test" must not remove "[ ] test website").
        query = target_task.strip().lower()
        new_tasks = [t for t in tasks if t.strip().lower() != query and strip_prefix(t).lower() != query]
        write_tasks(new_tasks)
    elif action == "edit_text":
        if len(sys.argv) >= 4:
            old_t = sys.argv[2]
            new_text = sys.argv[3]
            tasks = read_tasks()
            new_tasks = []
            for t in tasks:
                if t.strip().lower() == old_t.strip().lower():
                    pfx = "[ ]"
                    for p in ["[ ]", "[/]", "[x]", "- "]:
                        if t.startswith(p):
                            pfx = p.strip()
                            break
                    new_tasks.append(f"{pfx} {new_text.strip()}")
                else:
                    new_tasks.append(t)
            write_tasks(new_tasks)

if __name__ == "__main__":
    main()
