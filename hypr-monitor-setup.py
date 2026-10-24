#!/usr/bin/env python3
# =============================================================================
#   Hyprland N-Monitor Layout Engine (1, 2, 3, 4+ screens)
#   Part of: CachyOS + HyDE System Restorer
#   Repo:    https://github.com/omarahmed321/cachy-os-config-related
#
#   Detects every connected display (hyprctl, or /sys/class/drm + EDID when
#   Hyprland is not running), picks the native mode at its highest refresh
#   rate, enables VRR only on panels whose EDID advertises Adaptive-Sync,
#   links ICC profiles, lays the screens out left-to-right using each one's
#   rotated/scaled width, spreads workspaces 1-10 over them and writes
#   ~/.config/hypr/monitors.conf.
#
#   Usage:
#     hypr-monitor-setup.py --auto            detect + write (no questions)
#     hypr-monitor-setup.py --interactive     ask order / primary / rotation
#     hypr-monitor-setup.py --calibrate       live menu (rotate, nudge, VRR...)
#     hypr-monitor-setup.py --refine          re-run --auto with exact modes once
#                                             Hyprland is up (first login hook)
#     hypr-monitor-setup.py --get-primary     print the saved primary output
#     hypr-monitor-setup.py --list            print detected monitors
#   Options: --dry-run (print instead of write), --no-apply (skip hyprctl reload),
#            --from-json FILE (use a saved `hyprctl monitors all -j` dump),
#            --sysfs-root DIR (alternate /sys/class/drm for testing)
# =============================================================================

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys

MONITORS_CONF = os.path.expanduser("~/.config/hypr/monitors.conf")
STATE_FILE = os.path.expanduser("~/.config/hypr/monitor-layout.json")
SYSFS_DRM = "/sys/class/drm"
ICC_DIRS = [
    "~/.config/hypr/icc",
    "~/.local/share/icc",
    "~/.local/share/color/icc",
    "/usr/share/color/icc",
    "/var/lib/colord/icc",
]
WORKSPACE_COUNT = 10
TRANSFORM_NAMES = {
    0: "landscape", 1: "portrait (90°)", 2: "landscape flipped (180°)",
    3: "portrait flipped (270°)", 4: "flipped", 5: "flipped 90°",
    6: "flipped 180°", 7: "flipped 270°",
}


# ----------------------------------------------------------------------------
# EDID parsing
# ----------------------------------------------------------------------------
def parse_edid(data):
    """Return model name, detailed timings and VRR capability from raw EDID."""
    info = {"name": "", "timings": [], "range": None, "vrr": False}
    if len(data) < 128 or data[:8] != b"\x00\xff\xff\xff\xff\xff\xff\x00":
        return info

    def detailed_timing(d):
        pixclk = d[0] | (d[1] << 8)
        if pixclk == 0 or d[17] & 0x80:  # descriptor or interlaced
            return None
        hactive = d[2] | ((d[4] >> 4) << 8)
        hblank = d[3] | ((d[4] & 0x0F) << 8)
        vactive = d[5] | ((d[7] >> 4) << 8)
        vblank = d[6] | ((d[7] & 0x0F) << 8)
        total = (hactive + hblank) * (vactive + vblank)
        if not total:
            return None
        return (hactive, vactive, round(pixclk * 10000 / total, 2))

    for off in (54, 72, 90, 108):
        d = data[off:off + 18]
        t = detailed_timing(d)
        if t:
            info["timings"].append(t)
            continue
        tag = d[3]
        if tag == 0xFC:
            info["name"] = d[5:18].split(b"\x0a")[0].decode("ascii", "ignore").strip()
        elif tag == 0xFD:
            vmin = d[5] + (255 if d[4] & 0x01 else 0)
            vmax = d[6] + (255 if d[4] & 0x02 else 0)
            info["range"] = (vmin, vmax)

    for b in range(1, len(data) // 128):
        ext = data[b * 128:(b + 1) * 128]
        if ext[0] == 0x02:  # CTA-861
            dtd_start = ext[2] or 128
            i = 4
            while i < min(dtd_start, 127):
                tag, length = ext[i] >> 5, ext[i] & 0x1F
                payload = ext[i + 1:i + 1 + length]
                if tag == 3 and len(payload) >= 3:
                    oui = payload[0] | (payload[1] << 8) | (payload[2] << 16)
                    if oui == 0x00001A:  # AMD FreeSync vendor block
                        info["vrr"] = True
                    elif oui == 0xC45DD8 and len(payload) >= 11:  # HDMI 2.1 HF-VSDB
                        vrr_max = ((payload[9] >> 6) << 8) | payload[10]
                        if vrr_max:
                            info["vrr"] = True
                i += 1 + length
            o = dtd_start
            while dtd_start and o + 18 <= 127:
                t = detailed_timing(ext[o:o + 18])
                if t:
                    info["timings"].append(t)
                o += 18
        elif ext[0] == 0x70:  # DisplayID
            i = 5
            end = min(5 + ext[2], 127)
            while i + 3 <= end:
                tag, length = ext[i], ext[i + 2]
                if tag == 0x2B:  # DisplayID 2.0 Adaptive-Sync block
                    info["vrr"] = True
                if tag == 0 and length == 0:
                    break
                i += 3 + length

    # A wide, high-refresh vertical range is how DisplayPort Adaptive-Sync
    # panels usually advertise themselves (e.g. 48-144 Hz). Fixed-rate panels
    # report narrow ranges such as 50-75 Hz.
    if info["range"]:
        vmin, vmax = info["range"]
        if vmax >= 75 and vmax - vmin >= 30:
            info["vrr"] = True
    return info


def read_edid(name, sysfs_root=SYSFS_DRM):
    for path in glob.glob(os.path.join(sysfs_root, f"card*-{name}", "edid")):
        try:
            with open(path, "rb") as f:
                data = f.read()
            if data:
                return parse_edid(data)
        except OSError:
            pass
    return parse_edid(b"")


# ----------------------------------------------------------------------------
# Detection
# ----------------------------------------------------------------------------
def best_mode(modes, fallback_w, fallback_h, fallback_hz):
    """Highest refresh rate at the largest (native) resolution."""
    parsed = []
    for m in modes:
        r = re.match(r"^(\d+)x(\d+)@([\d.]+)", m)
        if r:
            parsed.append((int(r.group(1)), int(r.group(2)), float(r.group(3))))
    if not parsed:
        return fallback_w, fallback_h, fallback_hz
    w, h = max(((p[0], p[1]) for p in parsed), key=lambda wh: wh[0] * wh[1])
    hz = max(p[2] for p in parsed if (p[0], p[1]) == (w, h))
    return w, h, hz


def detect_hyprctl(from_json=None, sysfs_root=SYSFS_DRM):
    if from_json:
        with open(from_json) as f:
            raw = json.load(f)
    else:
        if not shutil.which("hyprctl"):
            return None
        try:
            out = subprocess.run(["hyprctl", "monitors", "all", "-j"],
                                 capture_output=True, text=True, timeout=5)
            raw = json.loads(out.stdout) if out.returncode == 0 else None
        except (OSError, ValueError, subprocess.TimeoutExpired):
            raw = None
        if not raw:
            return None
    monitors = []
    for m in raw:
        if m.get("mirrorOf") not in (None, "", "none"):
            continue
        w, h, hz = best_mode(m.get("availableModes", []), m.get("width", 1920),
                             m.get("height", 1080), m.get("refreshRate", 60.0))
        edid = read_edid(m["name"], sysfs_root)
        monitors.append({
            "name": m["name"],
            "model": m.get("model") or edid["name"] or m.get("description", "Display"),
            "description": m.get("description", ""),
            "width": w, "height": h, "hz": hz, "mode": f"{w}x{h}@{hz:g}",
            "transform": int(m.get("transform", 0)),
            "scale": float(m.get("scale", 1.0)),
            "x": int(m.get("x", 0)), "y": int(m.get("y", 0)),
            "vrr": edid["vrr"],
        })
    return monitors


def detect_sysfs(sysfs_root=SYSFS_DRM):
    monitors = []
    for status_file in sorted(glob.glob(os.path.join(sysfs_root, "card*-*", "status"))):
        conn = os.path.dirname(status_file)
        try:
            with open(status_file) as f:
                if f.read().strip() != "connected":
                    continue
        except OSError:
            continue
        name = os.path.basename(conn).split("-", 1)[1]
        if name.startswith("Writeback"):
            continue
        edid = read_edid(name, sysfs_root)
        if edid["timings"]:
            w, h, _ = edid["timings"][0]  # first DTD = preferred (native) mode
        else:
            w, h = 1920, 1080
            try:
                with open(os.path.join(conn, "modes")) as f:
                    first = f.readline().strip()
                r = re.match(r"^(\d+)x(\d+)", first)
                if r:
                    w, h = int(r.group(1)), int(r.group(2))
            except OSError:
                pass
        hz = max([t[2] for t in edid["timings"] if (t[0], t[1]) == (w, h)] or [60.0])
        monitors.append({
            "name": name, "model": edid["name"] or name, "description": "",
            "width": w, "height": h, "hz": hz,
            # The EDID's detailed timings often omit the top refresh rate, so let
            # Hyprland pick it; --refine writes the exact mode at first login.
            "mode": "highrr",
            "transform": 0, "scale": 1.0, "x": 0, "y": 0, "vrr": edid["vrr"],
        })
    return monitors


def find_icc(monitor):
    """Return an .icc/.icm whose file name contains the connector or model name."""
    keys = {k for k in (monitor["name"], monitor["model"]) if k}
    norm = {re.sub(r"[^a-z0-9]", "", k.lower()) for k in keys}
    norm.discard("")
    for d in ICC_DIRS:
        for path in sorted(glob.glob(os.path.join(os.path.expanduser(d), "*"))):
            if not path.lower().endswith((".icc", ".icm")):
                continue
            base = re.sub(r"[^a-z0-9]", "", os.path.basename(path).lower())
            if any(k and k in base for k in norm):
                return path
    return None


# ----------------------------------------------------------------------------
# Layout
# ----------------------------------------------------------------------------
def load_state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_state(state):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)


def logical_size(m, transform, scale):
    w, h = (m["height"], m["width"]) if transform % 2 else (m["width"], m["height"])
    return round(w / scale), round(h / scale)


def default_primary(monitors):
    # Highest refresh rate wins, then the largest panel
    return max(monitors, key=lambda m: (m["hz"], m["width"] * m["height"]))["name"]


def resolve_choices(monitors, state):
    names = [m["name"] for m in monitors]
    saved = [n for n in state.get("order", []) if n in names]
    rest = sorted((m for m in monitors if m["name"] not in saved),
                  key=lambda m: (m["x"], m["y"], m["name"]))
    order = saved + [m["name"] for m in rest]
    primary = state.get("primary") if state.get("primary") in names else default_primary(monitors)
    return order, primary


def distribute_workspaces(order, primary, total=WORKSPACE_COUNT):
    """Primary gets double weight; every screen gets at least one workspace."""
    if len(order) == 1:
        return {primary: list(range(1, total + 1))}
    others = [n for n in order if n != primary]
    seq = [primary] + others
    weights = [2] + [1] * len(others)
    shares = [total * w / sum(weights) for w in weights]
    counts = [max(1, int(s)) for s in shares]
    while sum(counts) > total:
        counts[counts.index(max(counts))] -= 1
    rema = sorted(range(len(seq)), key=lambda i: shares[i] - int(shares[i]), reverse=True)
    i = 0
    while sum(counts) < total:
        counts[rema[i % len(rema)]] += 1
        i += 1
    result, ws = {}, 1
    for name, count in zip(seq, counts):
        result[name] = list(range(ws, ws + count))
        ws += count
    return result


def build_layout(monitors, state):
    order, primary = resolve_choices(monitors, state)
    by_name = {m["name"]: m for m in monitors}
    transforms = state.get("transforms", {})
    scales = state.get("scales", {})
    nudges = state.get("y_nudge", {})
    vrr_override = state.get("vrr", {})
    icc_override = state.get("icc", {})
    align = state.get("align", "center")

    sizes = {}
    for n in order:
        m = by_name[n]
        t = int(transforms.get(n, m["transform"]))
        s = float(scales.get(n, m["scale"]))
        sizes[n] = (t, s) + logical_size(m, t, s)
    tallest = max(v[3] for v in sizes.values())

    entries, offset_x = [], 0
    for n in order:
        m = by_name[n]
        t, s, lw, lh = sizes[n]
        if align == "top":
            y = 0
        elif align == "bottom":
            y = tallest - lh
        else:
            y = (tallest - lh) // 2
        y += int(nudges.get(n, 0))
        vrr = bool(vrr_override[n]) if n in vrr_override else m["vrr"]
        icc = icc_override.get(n, None) if n in icc_override else find_icc(m)
        entries.append({"name": n, "model": m["model"], "mode": m["mode"], "x": offset_x,
                        "y": max(0, y), "scale": s, "transform": t, "vrr": vrr,
                        "icc": icc or None, "width": lw, "height": lh})
        offset_x += lw  # next screen starts where this one's rotated width ends
    return order, primary, entries, distribute_workspaces(order, primary)


def fmt_scale(s):
    return f"{s:g}"


def monitor_rule(e):
    rule = f"monitor = {e['name']},{e['mode']},{e['x']}x{e['y']},{fmt_scale(e['scale'])}"
    if e["transform"]:
        rule += f",transform,{e['transform']}"
    if e["vrr"]:
        rule += ",vrr,1"
    if e["icc"]:
        rule += f",icc,{e['icc']}"
    return rule


def render(order, primary, entries, workspaces, refine_hook=False):
    lines = [
        "# █▀▄▀█ █▀█ █▄░█ █ ▀█▀ █▀█ █▀█ █▀",
        "# █░▀░█ █▄█ █░▀█ █ ░█░ █▄█ █▀▄ ▄█",
        "# Generated by hypr-monitor-setup.py. Re-run it (or monitor-alignment.sh)",
        "# instead of editing by hand; choices are kept in monitor-layout.json.",
        f"# Layout (left to right): {'  |  '.join(order)}   primary: {primary}",
        "",
    ]
    for e in entries:
        lines.append(f"# {e['name']}: {e['model']} -> {e['width']}x{e['height']} logical")
        lines.append(monitor_rule(e))
    lines += ["", "# Any other screen plugged in later", "monitor = ,preferred,auto,1", "",
              "# Workspace Rules"]
    for name in [primary] + [n for n in order if n != primary]:
        for i, ws in enumerate(workspaces[name]):
            lines.append(f"workspace = {ws}, monitor:{name}" + (", default:true" if i == 0 else ""))
    if refine_hook:
        lines += ["", "# Modes above came from EDID; this rewrites them exactly on first login",
                  f"exec-once = python3 {os.path.abspath(__file__)} --refine"]
    return "\n".join(lines) + "\n"


# ----------------------------------------------------------------------------
# Interaction
# ----------------------------------------------------------------------------
_TTY = None


def tty_input(prompt):
    # One handle for the whole run: reopening /dev/tty per prompt would drop
    # anything typed (or pasted) ahead along with the old read buffer
    global _TTY
    try:
        if _TTY is None:
            # separate read/write handles: a tty is not seekable, so "r+" fails
            _TTY = (open("/dev/tty"), open("/dev/tty", "w"))
        _TTY[1].write(prompt)
        _TTY[1].flush()
        return _TTY[0].readline().strip()
    except OSError:
        return ""


def describe(monitors, order, primary, entries):
    by_name = {e["name"]: e for e in entries}
    mons = {m["name"]: m for m in monitors}
    out = []
    for i, n in enumerate(order, 1):
        e, m = by_name[n], mons[n]
        tag = "  [PRIMARY]" if n == primary else ""
        out.append(f"  {i}) {n:<10} {m['model'][:24]:<24} {m['width']}x{m['height']}@{m['hz']:g}Hz "
                   f"{TRANSFORM_NAMES.get(e['transform'], e['transform'])}, scale {fmt_scale(e['scale'])}, "
                   f"VRR {'on' if e['vrr'] else 'off'}, pos {e['x']}x{e['y']}{tag}")
    return "\n".join(out)


def pick_index(answer, count):
    if answer.isdigit() and 1 <= int(answer) <= count:
        return int(answer) - 1
    return None


def interactive(monitors, state):
    order, primary, entries, _ = build_layout(monitors, state)
    print("\nDetected monitors (current left-to-right order):")
    print(describe(monitors, order, primary, entries))
    if len(order) > 1:
        ans = tty_input(f"\nLeft-to-right order as numbers, e.g. {' '.join(str(i) for i in range(len(order), 0, -1))} "
                        "[Enter = keep]: ")
        nums = ans.split()
        if nums and sorted(nums) == [str(i) for i in range(1, len(order) + 1)]:
            order = [order[int(i) - 1] for i in nums]
        elif nums:
            print("  Invalid order, keeping the current one.")
        state["order"] = order
        idx = pick_index(tty_input(f"Primary screen number [Enter = {order.index(primary) + 1} {primary}]: "),
                         len(order))
        if idx is not None:
            primary = order[idx]
        state["primary"] = primary
    else:
        state["order"], state["primary"] = order, primary
    for i, n in enumerate(order, 1):
        cur = int(state.get("transforms", {}).get(n, next(m for m in monitors if m["name"] == n)["transform"]))
        ans = tty_input(f"Rotation for {i}) {n}: 0=landscape 1=portrait 2=180° 3=270° [Enter = {cur}]: ")
        if ans in {"0", "1", "2", "3"}:
            state.setdefault("transforms", {})[n] = int(ans)
    return state


def calibrate(monitors, state, apply_live):
    while True:
        order, primary, entries, _ = build_layout(monitors, state)
        print("\n" + describe(monitors, order, primary, entries))
        print("\n  o) change order      p) primary       r) rotate a screen   s) scale a screen\n"
              "  a) vertical align (now: %s)   n) nudge a screen up/down   v) toggle VRR\n"
              "  w) write & apply     q) quit without writing" % state.get("align", "center"))
        choice = tty_input("Choice: ").lower()
        if choice in ("", "q"):
            return None
        if choice == "w":
            return state
        if choice == "o":
            ans = tty_input("New left-to-right order (numbers): ").split()
            if sorted(ans) == [str(i) for i in range(1, len(order) + 1)]:
                state["order"] = [order[int(i) - 1] for i in ans]
            continue
        idx = None
        if choice in ("p", "r", "s", "n", "v"):
            idx = pick_index(tty_input("Screen number: "), len(order))
            if idx is None:
                continue
        name = order[idx] if idx is not None else None
        if choice == "p":
            state["primary"] = name
        elif choice == "r":
            ans = tty_input("0=landscape 1=portrait 2=180° 3=270°: ")
            if ans in {"0", "1", "2", "3"}:
                state.setdefault("transforms", {})[name] = int(ans)
        elif choice == "s":
            try:
                val = float(tty_input("Scale (e.g. 1, 1.25, 1.5, 2): "))
                if val > 0:
                    state.setdefault("scales", {})[name] = val
            except ValueError:
                pass
        elif choice == "n":
            try:
                state.setdefault("y_nudge", {})[name] = int(tty_input("Extra Y offset in px (+ = down): "))
            except ValueError:
                pass
        elif choice == "v":
            cur = next(e for e in entries if e["name"] == name)["vrr"]
            state.setdefault("vrr", {})[name] = not cur
        elif choice == "a":
            ans = tty_input("top / center / bottom: ").lower()
            if ans in ("top", "center", "bottom"):
                state["align"] = ans
        if apply_live:
            order, primary, entries, _ = build_layout(monitors, state)
            for e in entries:
                subprocess.run(["hyprctl", "keyword", "monitor", monitor_rule(e).split("=", 1)[1].strip()],
                               capture_output=True)


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
def hyprland_running():
    if not shutil.which("hyprctl") or not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return False
    return subprocess.run(["hyprctl", "version"], capture_output=True).returncode == 0


def main():
    p = argparse.ArgumentParser(description=__doc__)
    mode = p.add_mutually_exclusive_group()
    for flag in ("--auto", "--interactive", "--calibrate", "--refine", "--get-primary", "--list"):
        mode.add_argument(flag, action="store_true")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--no-apply", action="store_true")
    p.add_argument("--from-json")
    p.add_argument("--sysfs-root", default=SYSFS_DRM)
    args = p.parse_args()

    state = load_state()
    if args.get_primary:
        if state.get("primary"):
            print(state["primary"])
            return 0
    # --refine is a one-shot first-login hook: only act while the file still
    # holds EDID-guessed modes, so a leftover exec-once line is harmless
    if args.refine and (state.get("source") != "sysfs" or not hyprland_running()):
        return 0

    monitors = detect_hyprctl(args.from_json, args.sysfs_root)
    source = "hyprctl" if monitors else "sysfs"
    if not monitors:
        monitors = detect_sysfs(args.sysfs_root)
    if not monitors:
        print("No connected monitors found; writing a generic rule.", file=sys.stderr)
        if not args.dry_run and not args.get_primary:
            os.makedirs(os.path.dirname(MONITORS_CONF), exist_ok=True)
            with open(MONITORS_CONF, "w") as f:
                f.write("monitor = ,preferred,auto,1\n")
        return 0

    if args.get_primary:
        print(resolve_choices(monitors, state)[1])
        return 0
    if args.list:
        order, primary, entries, _ = build_layout(monitors, state)
        print(f"Source: {source}")
        print(describe(monitors, order, primary, entries))
        return 0
    if args.interactive:
        state = interactive(monitors, state)
    elif args.calibrate:
        live = hyprland_running() and not args.dry_run
        result = calibrate(monitors, state, live)
        if result is None:
            if live:
                subprocess.run(["hyprctl", "reload"], capture_output=True)
            return 0
        state = result

    order, primary, entries, workspaces = build_layout(monitors, state)
    state.update({"order": order, "primary": primary, "source": source})
    text = render(order, primary, entries, workspaces, refine_hook=(source == "sysfs"))
    if args.dry_run:
        print(text, end="")
        return 0
    os.makedirs(os.path.dirname(MONITORS_CONF), exist_ok=True)
    if os.path.exists(MONITORS_CONF) and not os.path.exists(MONITORS_CONF + ".bak"):
        shutil.copy2(MONITORS_CONF, MONITORS_CONF + ".bak")
    with open(MONITORS_CONF, "w") as f:
        f.write(text)
    save_state(state)
    print(f"Wrote {MONITORS_CONF} ({len(order)} screen(s), primary {primary})")
    if not args.no_apply and hyprland_running():
        subprocess.run(["hyprctl", "reload"], capture_output=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
