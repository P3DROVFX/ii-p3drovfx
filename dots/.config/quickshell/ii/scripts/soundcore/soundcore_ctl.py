#!/usr/bin/env python3
"""
Soundcore Life Q30 / Soundcore Bluetooth Direct RFCOMM Controller
Bypasses BlueZ ProfileManager1 registration to prevent UUID conflicts with BudsLink.
"""

import sys
import os
import json
import socket

CACHE_DIR = "/tmp/quickshell-soundcore"

def sanitize_mac(mac: str) -> str:
    return mac.strip().upper().replace("-", ":")

def get_cache_file(mac: str) -> str:
    os.makedirs(CACHE_DIR, exist_ok=True)
    mac_clean = mac.replace(":", "_")
    return os.path.join(CACHE_DIR, f"{mac_clean}.json")

def read_cached_mode(mac: str) -> str:
    cf = get_cache_file(mac)
    if os.path.isfile(cf):
        try:
            with open(cf, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data.get("mode", "Normal")
        except Exception:
            pass
    return "Normal"

def write_cached_mode(mac: str, mode: str):
    cf = get_cache_file(mac)
    try:
        with open(cf, "w", encoding="utf-8") as f:
            json.dump({"mac": mac, "mode": mode}, f)
    except Exception:
        pass

def build_packet(cmd, body=b"") -> bytes:
    direction = bytes([0x08, 0xEE, 0x00, 0x00, 0x00])
    total_len = len(direction) + len(cmd) + 2 + len(body) + 1
    len_bytes = total_len.to_bytes(2, "little")
    header_and_body = direction + bytes(cmd) + len_bytes + bytes(body)
    chk = sum(header_and_body) & 0xFF
    return header_and_body + bytes([chk])

def set_sound_mode(mac: str, mode_name: str) -> bool:
    mode_normalized = mode_name.strip().lower()
    
    # 0 = ANC / NoiseCanceling, 1 = Transparency, 2 = Normal / Off
    val_map = {
        "noisecanceling": (0x00, "NoiseCanceling"),
        "anc": (0x00, "NoiseCanceling"),
        "transparency": (0x01, "Transparency"),
        "normal": (0x02, "Normal"),
        "off": (0x02, "Normal")
    }
    
    if mode_normalized not in val_map:
        print(f"Unknown mode: {mode_name}", file=sys.stderr)
        return False
        
    mode_val, canonical_name = val_map[mode_normalized]
    pkt = build_packet([0x06, 0x81], [mode_val, 0x00, 0x00, 0x00])
    
    # Try channel 13 first (standard Soundcore channel), then fallback channels
    success = False
    for ch in [13, 1, 2, 3]:
        try:
            s = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_STREAM, socket.BTPROTO_RFCOMM)
            s.settimeout(1.5)
            s.connect((mac, ch))
            s.send(pkt)
            s.close()
            success = True
            break
        except Exception:
            continue
            
    if success:
        write_cached_mode(mac, canonical_name)
        return True
    return False

def main():
    if len(sys.argv) < 3:
        print("Usage: soundcore_ctl.py {get|set} <MAC> [MODE]", file=sys.stderr)
        sys.exit(1)
        
    cmd = sys.argv[1].lower()
    mac = sanitize_mac(sys.argv[2])
    
    if cmd == "get":
        mode = read_cached_mode(mac)
        print(mode)
        sys.exit(0)
    elif cmd == "set":
        if len(sys.argv) < 4:
            print("Missing MODE argument", file=sys.stderr)
            sys.exit(1)
        mode = sys.argv[3]
        if set_sound_mode(mac, mode):
            sys.exit(0)
        else:
            print("Failed to send command to device", file=sys.stderr)
            sys.exit(1)
    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
