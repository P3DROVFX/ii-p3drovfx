#!/usr/bin/env python3
import os
import sys
import json
import glob
import re
import hashlib
import base64
import quopri
import time
import argparse
from pathlib import Path
from datetime import date

# Try importing Gio for efficient file watching
try:
    import gi
    gi.require_version('Gio', '2.0')
    gi.require_version('GLib', '2.0')
    from gi.repository import Gio, GLib
    HAS_GIO = True
except Exception:
    HAS_GIO = False


CACHE_DIR = Path.home() / ".cache" / "illogical-impulse" / "phone" / "contacts"

def get_kpeoplevcard_root():
    xdg_data = os.environ.get("XDG_DATA_HOME")
    if xdg_data:
        root = Path(xdg_data) / "kpeoplevcard"
    else:
        root = Path.home() / ".local" / "share" / "kpeoplevcard"
    return root

def find_device_directory(target_device_id=None):
    root = get_kpeoplevcard_root()
    if not root.exists() or not root.is_dir():
        return None

    dirs = [d for d in root.iterdir() if d.is_dir() and d.name.startswith("kdeconnect-")]
    if not dirs:
        return None

    if target_device_id:
        target_name = f"kdeconnect-{target_device_id}"
        for d in dirs:
            if d.name == target_name or target_device_id in d.name:
                return d

    # Pick the most recently modified directory if no exact match
    dirs.sort(key=lambda d: d.stat().st_mtime, reverse=True)
    return dirs[0]

def unescape_vcard_val(val):
    val = val.replace(r"\n", "\n").replace(r"\N", "\n")
    val = val.replace(r"\,", ",").replace(r"\;", ";")
    return val.strip()

def decode_quoted_printable(text):
    try:
        return quopri.decodestring(text.encode('utf-8')).decode('utf-8', errors='replace')
    except Exception:
        return text

def normalize_phone(phone_str):
    # Remove spaces, dashes, parens, dots
    cleaned = re.sub(r'[\s\-\(\)\.]', '', phone_str)
    return cleaned

def looks_like_number(text):
    # True when the text carries no actual name, just a dialable number.
    # Android hands us the raw number as DISPLAY_NAME for raw contacts that
    # never had a structured name (SIM imports, messaging sync adapters,
    # call-blocker lists), so those arrive as FN/N fields full of digits.
    stripped = re.sub(r'[\s\-\(\)\.\/]', '', text)
    return bool(re.fullmatch(r'\+?\d+', stripped))

def parse_birthday(value):
    """Return a JSON-friendly BDAY shape, or None for malformed values.

    Android/KDE Connect exports both complete ISO dates and vCard's
    yearless ``--MM-DD`` form.  Time suffixes are deliberately ignored: a
    birthday is a calendar day, never an instant in a timezone.
    """
    raw = unescape_vcard_val(value)
    match = re.search(r'(?:(\d{4})-)?(\d{2})-(\d{2})(?:T.*)?$', raw)
    if not match:
        return None

    year_text, month_text, day_text = match.groups()
    year = int(year_text) if year_text else None
    month = int(month_text)
    day = int(day_text)
    try:
        # 2000 keeps Feb 29 valid when the vCard intentionally omits a year.
        date(year if year is not None else 2000, month, day)
    except ValueError:
        return None
    return {"year": year, "month": month, "day": day}

def parse_vcard_file(file_path, source_id):
    try:
        content = file_path.read_text(encoding='utf-8', errors='replace')
    except Exception:
        return None

    # Unfold lines (lines starting with space or tab are continuations)
    raw_lines = content.splitlines()
    unfolded_lines = []
    for line in raw_lines:
        if line.startswith((' ', '\t')) and unfolded_lines:
            unfolded_lines[-1] += line[1:]
        else:
            unfolded_lines.append(line)

    fn = ""
    given_name = ""
    family_name = ""
    org = ""
    uid = ""
    rev = 0
    phones = []
    emails = []
    photo_data = None
    photo_ext = "jpg"
    birthday = None

    for line in unfolded_lines:
        line = line.strip()
        if not line or ":" not in line:
            continue

        parts = line.split(":", 1)
        key_params = parts[0].upper().split(";")
        key = key_params[0]
        params = key_params[1:]
        val = parts[1]

        param_dict = {}
        for p in params:
            if "=" in p:
                pk, pv = p.split("=", 1)
                param_dict[pk] = pv
            else:
                param_dict[p] = True

        # Check quoted-printable encoding
        is_qp = param_dict.get("ENCODING") == "QUOTED-PRINTABLE" or "QUOTED-PRINTABLE" in param_dict
        if is_qp:
            val = decode_quoted_printable(val)

        if key == "FN":
            fn = unescape_vcard_val(val)
        elif key == "N":
            n_parts = [unescape_vcard_val(p) for p in val.split(";")]
            family_name = n_parts[0] if len(n_parts) > 0 else ""
            given_name = n_parts[1] if len(n_parts) > 1 else ""
        elif key == "ORG":
            org = unescape_vcard_val(val)
        elif key == "UID":
            uid = val.strip()
        elif key.startswith("X-KDECONNECT-ID-DEV-"):
            if not uid:
                uid = val.strip()
        elif key == "REV":
            try:
                # ISO date string or timestamp
                rev_str = val.strip().replace("-", "").replace(":", "")
                if rev_str.isdigit():
                    rev = int(rev_str[:10])
            except Exception:
                pass
        elif key == "BDAY":
            birthday = parse_birthday(val)
        elif key == "TEL":
            phone_val = unescape_vcard_val(val)
            if phone_val:
                ptype = "mobile"
                for p in params:
                    if p in ("CELL", "MOBILE"):
                        ptype = "mobile"
                    elif p in ("HOME", "WORK", "MAIN", "OTHER"):
                        ptype = p.lower()
                is_primary = "PREF" in param_dict or "PREF" in params
                phones.append({
                    "value": phone_val,
                    "normalized": normalize_phone(phone_val),
                    "type": ptype,
                    "primary": is_primary or (len(phones) == 0)
                })
        elif key == "EMAIL":
            email_val = unescape_vcard_val(val)
            if email_val:
                etype = "personal"
                for p in params:
                    if p in ("WORK", "HOME"):
                        etype = p.lower()
                is_primary = "PREF" in param_dict or "PREF" in params
                emails.append({
                    "value": email_val,
                    "type": etype,
                    "primary": is_primary or (len(emails) == 0)
                })
        elif key == "PHOTO":
            try:
                # Extract photo base64
                b64_str = val.strip()
                if "BASE64" in param_dict or param_dict.get("ENCODING") in ("B", "BASE64") or "B" in params:
                    photo_data = base64.b64decode(b64_str)
                    if "JPEG" in line.upper() or "JPG" in line.upper():
                        photo_ext = "jpg"
                    elif "PNG" in line.upper():
                        photo_ext = "png"
            except Exception:
                pass

    # Deduplicate phones while preserving order
    unique_phones = []
    seen_phone_vals = set()
    for p in phones:
        norm = p["normalized"]
        if norm not in seen_phone_vals:
            seen_phone_vals.add(norm)
            unique_phones.append(p)
    phones = unique_phones

    # Deduplicate emails
    unique_emails = []
    seen_email_vals = set()
    for e in emails:
        val_lower = e["value"].lower()
        if val_lower not in seen_email_vals:
            seen_email_vals.add(val_lower)
            unique_emails.append(e)
    emails = unique_emails

    display_name = fn or f"{given_name} {family_name}".strip() or (phones[0]["value"] if phones else "")
    if not display_name:
        display_name = "Unnamed Contact"

    # Filter out empty contacts with no name, no phone, no email
    if display_name == "Unnamed Contact" and not phones and not emails:
        return None

    # Flag contacts that carry no human-readable identity at all, so the shell
    # can optionally hide them. Reported in the wild as ~1000 bare numbers from
    # anti-spam / carrier apps that write into Android's contacts provider.
    nameless = not any(
        part and not looks_like_number(part)
        for part in (fn, given_name, family_name, org)
    )

    if not uid:
        # Fallback UID: hash of filename + display_name
        uid_str = f"{file_path.name}_{display_name}_{phones[0]['value'] if phones else ''}"
        uid = hashlib.sha256(uid_str.encode('utf-8')).hexdigest()[:16]

    avatar_path = ""
    if photo_data:
        try:
            CACHE_DIR.mkdir(parents=True, exist_ok=True)
            img_hash = hashlib.sha256(photo_data).hexdigest()[:16]
            img_file = CACHE_DIR / f"{img_hash}.{photo_ext}"
            if not img_file.exists():
                img_file.write_bytes(photo_data)
            avatar_path = str(img_file)
        except Exception as e:
            sys.stderr.write(f"Error saving avatar for {display_name}: {e}\n")

    mtime = int(file_path.stat().st_mtime)

    return {
        "id": uid,
        "displayName": display_name,
        "givenName": given_name,
        "familyName": family_name,
        "organization": org,
        "phones": phones,
        "emails": emails,
        "avatarPath": avatar_path,
        "birthday": birthday,
        "source": source_id,
        "nameless": nameless,
        "mtime": mtime
    }

def read_contacts_from_dir(dir_path):
    contacts = []
    source_id = dir_path.name
    for vcf_file in dir_path.glob("*.vcf"):
        parsed = parse_vcard_file(vcf_file, source_id)
        if parsed:
            contacts.append(parsed)

    # Sort contacts alphabetically by displayName
    contacts.sort(key=lambda c: c["displayName"].lower())
    return contacts

class ContactMonitor:
    def __init__(self, target_device_id=None):
        self.target_device_id = target_device_id
        self.current_dir = None
        self.last_hash = ""

    def update_and_emit(self):
        self.current_dir = find_device_directory(self.target_device_id)
        if not self.current_dir or not self.current_dir.exists():
            msg = {"event": "error", "code": "no_contact_source", "message": "No KDE Connect contacts directory found"}
            print(json.dumps(msg), flush=True)
            return False

        contacts = read_contacts_from_dir(self.current_dir)
        payload = json.dumps(contacts)
        payload_hash = hashlib.sha256(payload.encode('utf-8')).hexdigest()

        if payload_hash != self.last_hash:
            self.last_hash = payload_hash
            ready_msg = {
                "event": "ready",
                "sourcePath": str(self.current_dir),
                "count": len(contacts)
            }
            print(json.dumps(ready_msg), flush=True)

            snapshot_msg = {
                "event": "snapshot",
                "contacts": contacts
            }
            print(json.dumps(snapshot_msg), flush=True)
        return True

    def run_gio(self):
        if not self.update_and_emit():
            return

        gfile = Gio.File.new_for_path(str(self.current_dir))
        monitor = gfile.monitor_directory(Gio.FileMonitorFlags.NONE, None)

        timer_id = [None]

        def on_change(file_monitor, file, other_file, event_type):
            if timer_id[0] is not None:
                GLib.source_remove(timer_id[0])
            # Debounce 250ms
            timer_id[0] = GLib.timeout_add(250, self.update_and_emit)

        monitor.connect("changed", on_change)

        loop = GLib.MainLoop()
        try:
            loop.run()
        except KeyboardInterrupt:
            pass

    def run_fallback(self):
        while True:
            self.update_and_emit()
            time.sleep(3.0)

def main():
    parser = argparse.ArgumentParser(description="KDE Connect Contacts Monitor for II")
    parser.add_argument("--device", help="Target KDE Connect device ID")
    parser.add_argument("--once", action="store_true", help="Print contacts once and exit")
    args = parser.parse_args()

    monitor = ContactMonitor(target_device_id=args.device)

    if args.once:
        monitor.update_and_emit()
        sys.exit(0)

    if HAS_GIO:
        monitor.run_gio()
    else:
        monitor.run_fallback()

if __name__ == "__main__":
    main()
