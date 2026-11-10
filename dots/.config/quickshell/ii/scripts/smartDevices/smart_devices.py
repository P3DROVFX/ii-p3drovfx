#!/usr/bin/env python3
"""
Smart Devices helper for Quickshell ii
Interacts with TinyTuya devices locally with automatic Cloud fallback.
"""

import sys
import os
import json
import time
import colorsys
from typing import List, Dict, Any, Optional

CACHE_FILE = "/tmp/quickshell-smart-devices-cache.json"

CONFIG_SEARCH_PATHS = [
    os.path.expanduser("~/.config/tinytuya/devices.json"),
    os.path.expanduser("~/.tinytuya/devices.json"),
    os.path.expanduser("~/.config/quickshell/ii/devices.json"),
    os.path.expanduser("~/Downloads/devices.json"),
    os.path.expanduser("~/devices.json"),
]

CLOUD_SEARCH_PATHS = [
    os.path.expanduser("~/.config/tinytuya/tinytuya.json"),
    os.path.expanduser("~/.tinytuya/tinytuya.json"),
    os.path.expanduser("~/.config/quickshell/ii/tinytuya.json"),
    os.path.expanduser("~/Downloads/tinytuya.json"),
    os.path.expanduser("~/tinytuya.json"),
]

def load_devices_config() -> List[Dict[str, Any]]:
    for path in CONFIG_SEARCH_PATHS:
        if os.path.isfile(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if isinstance(data, list):
                        return data
                    elif isinstance(data, dict) and "devices" in data:
                        return data["devices"]
            except Exception:
                pass
    return []

def load_cloud_config() -> Optional[Dict[str, Any]]:
    for path in CLOUD_SEARCH_PATHS:
        if os.path.isfile(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if "apiKey" in data and "apiSecret" in data:
                        return data
            except Exception:
                pass
    return None

def load_cache() -> Dict[str, Any]:
    if os.path.isfile(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}

def save_cache(cache: Dict[str, Any]):
    try:
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(cache, f)
    except Exception:
        pass

def kelvin_to_temp_val(kelvin: int) -> int:
    """Map 2700K..6500K to 0..255 (Tuya LT11 temp_value: 0 is warmest ~2700K, 255 is coolest ~6500K)."""
    k = max(2700, min(6500, int(kelvin)))
    pct = (k - 2700) / (6500 - 2700)
    return int(round(pct * 255))

def temp_val_to_kelvin(temp_val: int) -> int:
    """Map 0..255 to 2700K..6500K."""
    pct = max(0, min(255, int(temp_val))) / 255.0
    return int(round(2700 + pct * (6500 - 2700)))

def hsv_to_hex(h_deg: float, s_pct: float, v_pct: float) -> str:
    h = (h_deg % 360) / 360.0
    s = max(0.0, min(100.0, s_pct)) / 100.0
    v = max(0.0, min(100.0, v_pct)) / 100.0
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return f"#{int(r*255):02x}{int(g*255):02x}{int(b*255):02x}"

def tuya_hsv_to_hex(h: float, s: float, v: float) -> str:
    """Encode HSV (0..360, 0..100, 0..100) to Tuya bulb type A 14-char hex string: RRGGBBHHHHSSVV."""
    h_clamped = float(h) % 360.0
    s_clamped = max(0.0, min(100.0, float(s)))
    v_clamped = max(0.0, min(100.0, float(v)))

    r, g, b = colorsys.hsv_to_rgb(h_clamped / 360.0, s_clamped / 100.0, v_clamped / 100.0)
    rgb_hex = f"{int(round(r * 255)):02x}{int(round(g * 255)):02x}{int(round(b * 255)):02x}"
    h_hex = f"{int(round(h_clamped)):04x}"
    s_hex = f"{int(round(s_clamped * 2.55)):02x}"
    v_hex = f"{int(round(v_clamped * 2.55)):02x}"
    return f"{rgb_hex}{h_hex}{s_hex}{v_hex}"

def tuya_hex_to_hsv(hex_str: str) -> tuple[int, int, int]:
    """Decode Tuya hex string to (hue, sat_pct, val_pct)."""
    hex_str = hex_str.strip().lower()
    if len(hex_str) >= 14:
        try:
            h = int(hex_str[6:10], 16)
            s = int(round(int(hex_str[10:12], 16) / 2.55))
            v = int(round(int(hex_str[12:14], 16) / 2.55))
            return h % 360, max(0, min(100, s)), max(0, min(100, v))
        except Exception:
            pass
    elif len(hex_str) == 12:
        try:
            h = int(hex_str[0:4], 16)
            s = int(round(int(hex_str[4:8], 16) / 10.0))
            v = int(round(int(hex_str[8:12], 16) / 10.0))
            return h % 360, max(0, min(100, s)), max(0, min(100, v))
        except Exception:
            pass
    return 275, 100, 100

def parse_device_state(raw_dev: Dict[str, Any], dps: Dict[str, Any], cached: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    # Default fallback values
    is_on = bool(dps.get("1", False))
    mode = str(dps.get("2", "colour"))
    if mode not in ["white", "colour"]:
        mode = "colour"

    # Brightness (25..255 -> 0..100%)
    raw_bright = dps.get("3", 255)
    if isinstance(raw_bright, (int, float)):
        # Tuya bulbs: 25..255 -> 0..100%
        bright_pct = int(round(max(0, raw_bright - 25) * 100 / 230))
        bright_pct = max(1, min(100, bright_pct))
    else:
        bright_pct = 80

    # Temperature (0..255 -> 2700K..6500K)
    raw_temp = dps.get("4", 128)
    if isinstance(raw_temp, (int, float)):
        temp_k = temp_val_to_kelvin(int(raw_temp))
    else:
        temp_k = 4000

    # Colour data
    raw_colour = dps.get("5", "")
    hue = 275
    sat = 100
    val = bright_pct

    if isinstance(raw_colour, dict):
        hue = int(raw_colour.get("h", 275))
        sat = int(raw_colour.get("s", 255) * 100 / 255)
        val = int(raw_colour.get("v", 255) * 100 / 255)
    elif isinstance(raw_colour, str) and raw_colour.startswith("{"):
        try:
            cj = json.loads(raw_colour)
            hue = int(round(float(cj.get("h", 275))))
            s_val = float(cj.get("s", 255))
            v_val = float(cj.get("v", 255))
            sat = int(round(s_val * 100 / 255)) if s_val <= 255 else int(round(s_val / 10))
            val = int(round(v_val * 100 / 255)) if v_val <= 255 else int(round(v_val / 10))
        except Exception:
            pass
    elif isinstance(raw_colour, str) and len(raw_colour) >= 12:
        hue, sat, val = tuya_hex_to_hsv(raw_colour)

    if mode == "colour" and val > 0:
        bright_pct = val

    hex_col = hsv_to_hex(hue, sat, 100)

    res = {
        "id": raw_dev.get("id", ""),
        "name": raw_dev.get("name", "Smart Light"),
        "ip": raw_dev.get("ip", ""),
        "category": raw_dev.get("category", "dj"),
        "product_name": raw_dev.get("product_name", ""),
        "is_on": is_on,
        "mode": mode,
        "brightness": bright_pct,
        "temperature": temp_k,
        "temp_raw": raw_temp,
        "hue": hue,
        "saturation": sat,
        "value": val,
        "hex_color": hex_col,
        "online": True
    }
    return res

def query_local(dev_cfg: Dict[str, Any], timeout: float = 1.0) -> Optional[Dict[str, Any]]:
    import tinytuya
    dev_id = dev_cfg.get("id")
    ip = dev_cfg.get("ip")
    key = dev_cfg.get("key")
    ver = float(dev_cfg.get("version", 3.3))
    if not (dev_id and ip and key):
        return None

    bulb = tinytuya.BulbDevice(dev_id, ip, key)
    bulb.set_version(ver)
    bulb.set_retry(False)
    bulb.set_socketRetryLimit(1)
    bulb.set_socketRetryDelay(0)
    bulb.set_socketPersistent(False)
    bulb.set_socketTimeout(timeout)
    try:
        st = bulb.status()
        if st and "dps" in st:
            return st["dps"]
    except Exception:
        pass
    finally:
        try:
            bulb.close()
        except Exception:
            pass
    return None

def query_cloud(dev_id: str, cloud_cfg: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    import tinytuya
    try:
        c = tinytuya.Cloud(
            apiRegion=cloud_cfg["apiRegion"],
            apiKey=cloud_cfg["apiKey"],
            apiSecret=cloud_cfg["apiSecret"],
            apiDeviceID=dev_id
        )
        st = c.getstatus(dev_id)
        if st and st.get("success") and "result" in st:
            # result is list of {code, value}
            # map to dps
            dps = {}
            for item in st["result"]:
                code = item.get("code")
                val = item.get("value")
                if code == "switch_led":
                    dps["1"] = val
                elif code == "work_mode":
                    dps["2"] = val
                elif code == "bright_value":
                    dps["3"] = val
                elif code == "temp_value":
                    dps["4"] = val
                elif code == "colour_data":
                    dps["5"] = val
            return dps
    except Exception:
        pass
    return None

def get_devices(force_fresh: bool = False) -> List[Dict[str, Any]]:
    devices_raw = load_devices_config()
    if not devices_raw:
        return []

    cache = load_cache()
    cloud_cfg = load_cloud_config()
    out = []

    for dev in devices_raw:
        dev_id = dev.get("id", "")
        cached = cache.get(dev_id)

        dps = None
        # Try local first
        dps = query_local(dev, timeout=1.5)

        # Fallback to cloud if local failed
        if dps is None and cloud_cfg:
            dps = query_cloud(dev_id, cloud_cfg)

        if dps is not None:
            parsed = parse_device_state(dev, dps, cached)
            cache[dev_id] = parsed
            out.append(parsed)
        elif cached:
            # Use cached state if device momentarily offline
            c_copy = dict(cached)
            c_copy["online"] = False
            out.append(c_copy)
        else:
            # Default offline device
            def_st = parse_device_state(dev, {"1": False, "2": "colour", "3": 40, "4": 128, "5": "4400ff0100ffff"})
            def_st["online"] = False
            out.append(def_st)

    save_cache(cache)
    return out

def send_local_payload(dev_cfg: Dict[str, Any], dps_values: Dict[str, Any], timeout: float = 1.0) -> bool:
    import tinytuya
    dev_id = dev_cfg.get("id")
    ip = dev_cfg.get("ip")
    key = dev_cfg.get("key")
    ver = float(dev_cfg.get("version", 3.3))
    if not (dev_id and ip and key):
        return False

    bulb = tinytuya.BulbDevice(dev_id, ip, key)
    bulb.set_version(ver)
    bulb.set_retry(False)
    bulb.set_socketRetryLimit(1)
    bulb.set_socketRetryDelay(0)
    bulb.set_socketPersistent(False)
    bulb.set_socketTimeout(timeout)
    try:
        res = bulb.set_multiple_values(dps_values, nowait=False)
        return bool(res and "Error" not in res)
    except Exception:
        return False
    finally:
        try:
            bulb.close()
        except Exception:
            pass

def send_cloud_commands(dev_id: str, commands: List[Dict[str, Any]], cloud_cfg: Dict[str, Any]) -> bool:
    import tinytuya
    try:
        c = tinytuya.Cloud(
            apiRegion=cloud_cfg["apiRegion"],
            apiKey=cloud_cfg["apiKey"],
            apiSecret=cloud_cfg["apiSecret"],
            apiDeviceID=dev_id
        )
        res = c.sendcommand(dev_id, {"commands": commands})
        return bool(res and res.get("success"))
    except Exception:
        return False

def set_device_power(dev_id: str, on_state: bool) -> bool:
    devices = load_devices_config()
    target = next((d for d in devices if d.get("id") == dev_id), None)
    if not target:
        return False

    dps = {"1": on_state}
    cloud_cmds = [{"code": "switch_led", "value": on_state}]

    ok = send_local_payload(target, dps)
    if not ok:
        cloud_cfg = load_cloud_config()
        if cloud_cfg:
            ok = send_cloud_commands(dev_id, cloud_cmds, cloud_cfg)

    # Update cache
    cache = load_cache()
    if dev_id in cache:
        cache[dev_id]["is_on"] = on_state
        save_cache(cache)
    return ok

def set_device_white(dev_id: str, bright_pct: int, kelvin: int) -> bool:
    devices = load_devices_config()
    target = next((d for d in devices if d.get("id") == dev_id), None)
    if not target:
        return False

    bright_pct = max(1, min(100, int(bright_pct)))
    # Map 0..100% to 25..255
    raw_bright = int(round(25 + (bright_pct * 230 / 100)))
    raw_temp = kelvin_to_temp_val(kelvin)

    dps = {
        "1": True,
        "2": "white",
        "3": raw_bright,
        "4": raw_temp
    }
    cloud_cmds = [
        {"code": "switch_led", "value": True},
        {"code": "work_mode", "value": "white"},
        {"code": "bright_value", "value": raw_bright},
        {"code": "temp_value", "value": raw_temp}
    ]

    ok = send_local_payload(target, dps)
    if not ok:
        cloud_cfg = load_cloud_config()
        if cloud_cfg:
            ok = send_cloud_commands(dev_id, cloud_cmds, cloud_cfg)

    cache = load_cache()
    if dev_id in cache:
        cache[dev_id]["is_on"] = True
        cache[dev_id]["mode"] = "white"
        cache[dev_id]["brightness"] = bright_pct
        cache[dev_id]["temperature"] = kelvin
        save_cache(cache)
    return ok

def set_device_colour_hsv(dev_id: str, hue: int, sat_pct: int, val_pct: int) -> bool:
    devices = load_devices_config()
    target = next((d for d in devices if d.get("id") == dev_id), None)
    if not target:
        return False

    hue = int(hue) % 360
    sat_pct = max(1, min(100, int(sat_pct)))
    val_pct = max(1, min(100, int(val_pct)))

    hex_col = tuya_hsv_to_hex(hue, sat_pct, val_pct)

    dps = {
        "1": True,
        "2": "colour",
        "5": hex_col
    }
    cloud_cmds = [
        {"code": "switch_led", "value": True},
        {"code": "work_mode", "value": "colour"},
        {"code": "colour_data", "value": json.dumps({"h": float(hue), "s": float(sat_pct * 2.55), "v": float(val_pct * 2.55)})}
    ]

    ok = send_local_payload(target, dps)
    if not ok:
        cloud_cfg = load_cloud_config()
        if cloud_cfg:
            ok = send_cloud_commands(dev_id, cloud_cmds, cloud_cfg)

    cache = load_cache()
    if dev_id in cache:
        cache[dev_id]["is_on"] = True
        cache[dev_id]["mode"] = "colour"
        cache[dev_id]["brightness"] = val_pct
        cache[dev_id]["hue"] = hue
        cache[dev_id]["saturation"] = sat_pct
        cache[dev_id]["value"] = val_pct
        cache[dev_id]["hex_color"] = hsv_to_hex(hue, sat_pct, 100)
        save_cache(cache)
    return ok

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No command provided"}))
        sys.exit(1)

    cmd = sys.argv[1].lower()

    if cmd == "list":
        devs = get_devices(force_fresh=True)
        print(json.dumps(devs))
        return

    if cmd == "status":
        cache = load_cache()
        if len(sys.argv) >= 3:
            dev_id = sys.argv[2]
            print(json.dumps(cache.get(dev_id, {})))
        else:
            print(json.dumps(list(cache.values())))
        return

    if cmd == "set-power":
        if len(sys.argv) < 4:
            print(json.dumps({"error": "Usage: set-power <dev_id> <on|off|toggle>"}))
            sys.exit(1)
        dev_id = sys.argv[2]
        action = sys.argv[3].lower()

        target_on = True
        if action == "off":
            target_on = False
        elif action == "toggle":
            cache = load_cache()
            curr = cache.get(dev_id, {}).get("is_on", False)
            target_on = not curr

        ok = set_device_power(dev_id, target_on)
        print(json.dumps({"success": ok, "is_on": target_on}))
        return

    if cmd == "set-white":
        if len(sys.argv) < 5:
            print(json.dumps({"error": "Usage: set-white <dev_id> <bright_pct> <kelvin>"}))
            sys.exit(1)
        dev_id = sys.argv[2]
        bright = int(sys.argv[3])
        kelvin = int(sys.argv[4])
        ok = set_device_white(dev_id, bright, kelvin)
        print(json.dumps({"success": ok, "mode": "white", "brightness": bright, "temperature": kelvin}))
        return

    if cmd == "set-colour-hsv":
        if len(sys.argv) < 6:
            print(json.dumps({"error": "Usage: set-colour-hsv <dev_id> <hue> <sat_pct> <val_pct>"}))
            sys.exit(1)
        dev_id = sys.argv[2]
        hue = int(sys.argv[3])
        sat = int(sys.argv[4])
        val = int(sys.argv[5])
        ok = set_device_colour_hsv(dev_id, hue, sat, val)
        print(json.dumps({"success": ok, "mode": "colour", "hue": hue, "saturation": sat, "value": val}))
        return

    if cmd == "set-all-power":
        if len(sys.argv) < 3:
            print(json.dumps({"error": "Usage: set-all-power <on|off|toggle>"}))
            sys.exit(1)
        action = sys.argv[2].lower()
        devs = load_devices_config()
        cache = load_cache()

        any_on = any(cache.get(d.get("id"), {}).get("is_on", False) for d in devs)
        target_on = True
        if action == "off":
            target_on = False
        elif action == "toggle":
            target_on = not any_on

        results = {}
        for d in devs:
            did = d.get("id")
            if did:
                results[did] = set_device_power(did, target_on)
        print(json.dumps({"success": True, "target_on": target_on, "results": results}))
        return

    print(json.dumps({"error": f"Unknown command: {cmd}"}))
    sys.exit(1)

if __name__ == "__main__":
    main()
