#!/bin/bash
# Page_Up is bound in Hyprland: a double press (within 0.5s) toggles the terminal
# (Ctrl+`); a single press is forwarded to the focused window, so Page_Up still
# scrolls everywhere. sendshortcut bypasses the bind, so this can't loop.
LAST_FILE="${XDG_RUNTIME_DIR:-/tmp}/.pageup_last"
NOW=$(date +%s%N)

if [ -f "$LAST_FILE" ]; then
    LAST=$(cat "$LAST_FILE")
    DIFF=$(( (NOW - LAST) / 1000000 ))
    if [ "$DIFF" -lt 500 ]; then
        rm -f "$LAST_FILE"
        wtype -M ctrl -k grave
        exit 0
    fi
fi

echo "$NOW" > "$LAST_FILE"
sleep 0.5
# Still our timestamp: no second press came, so this was a plain Page_Up
if [ -f "$LAST_FILE" ] && [ "$(cat "$LAST_FILE" 2>/dev/null)" = "$NOW" ]; then
    rm -f "$LAST_FILE"
    hyprctl dispatch sendshortcut ", Page_Up," >/dev/null 2>&1
fi
