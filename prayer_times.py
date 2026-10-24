#!/usr/bin/env python3
import urllib.request
import json
import datetime
import os
import sys
import time

CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "prayer_times")
CACHE_FILE = os.path.join(CACHE_DIR, "timings.json")
LOC_CACHE = os.path.join(CACHE_DIR, "location.json")
FALLBACK = (30.0444, 31.2357, "Cairo")
RETRY_AFTER = 300  # seconds before retrying a failed location lookup

# Waybar runs this every second on every bar, so the network is only touched
# once a day (location) and once per day+location (timings). ip-api bans IPs
# that exceed 45 requests a minute.


def read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}


def write_json(path, data):
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        with open(path, "w") as f:
            json.dump(data, f)
    except Exception:
        pass


def get_location():
    today = datetime.date.today().isoformat()
    loc = read_json(LOC_CACHE)
    have = loc.get("lat") is not None and loc.get("lon") is not None
    recent_fail = time.time() - loc.get("last_try", 0) < RETRY_AFTER
    if have and (loc.get("date") == today or recent_fail):
        return loc["lat"], loc["lon"], loc.get("city")
    if not have and recent_fail:
        return FALLBACK
    try:
        req = urllib.request.Request("http://ip-api.com/json", headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode())
        if data.get("status") != "success" or data.get("lat") is None:
            raise ValueError("lookup failed")
        loc = {"date": today, "lat": data["lat"], "lon": data["lon"], "city": data.get("city")}
    except Exception:
        loc["last_try"] = time.time()  # keep the last good location, back off
    write_json(LOC_CACHE, loc)
    if loc.get("lat") is not None and loc.get("lon") is not None:
        return loc["lat"], loc["lon"], loc.get("city")
    return FALLBACK


def get_prayer_timings(lat, lon):
    today = datetime.date.today().isoformat()
    cached = read_json(CACHE_FILE)
    if cached.get("date") == today and cached.get("lat") == lat and cached.get("lon") == lon:
        return cached.get("timings")
    if time.time() - cached.get("last_try", 0) < RETRY_AFTER and cached.get("timings"):
        return cached["timings"]
    try:
        url = f"http://api.aladhan.com/v1/timings?latitude={lat}&longitude={lon}&method=5"
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=5) as response:
            timings = json.loads(response.read().decode())["data"]["timings"]
        write_json(CACHE_FILE, {"date": today, "lat": lat, "lon": lon, "timings": timings})
        return timings
    except Exception:
        cached["last_try"] = time.time()
        write_json(CACHE_FILE, cached)
        return cached.get("timings")


def parse_time(time_str):
    parts = time_str.split(":")
    return int(parts[0]), int(parts[1])

def main():
    lat, lon, city = get_location()
    timings = get_prayer_timings(lat, lon)
    if not timings:
        print("No timings")
        sys.exit(0)

    prayers = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    now = datetime.datetime.now()
    
    prayer_times = []
    for p in prayers:
        t_str = timings.get(p)
        if not t_str:
            continue
        h, m = parse_time(t_str)
        p_time = now.replace(hour=h, minute=m, second=0, microsecond=0)
        prayer_times.append((p, p_time))

    next_p = None
    next_p_time = None

    for name, p_time in prayer_times:
        if p_time > now:
            next_p = name
            next_p_time = p_time
            break

    if not next_p:
        next_p = "Fajr"
        f_str = timings.get("Fajr")
        h, m = parse_time(f_str)
        next_p_time = now.replace(hour=h, minute=m, second=0, microsecond=0) + datetime.timedelta(days=1)

    diff = next_p_time - now
    diff_seconds = diff.total_seconds()
    hours = int(diff_seconds // 3600)
    minutes = int((diff_seconds % 3600) // 60)
    seconds = int(diff_seconds % 60)

    next_p_time_str = next_p_time.strftime("%I:%M %p").lstrip('0')
    print(f"{next_p} in {hours}:{minutes:02d}:{seconds:02d} ({next_p_time_str})")

if __name__ == "__main__":
    main()
