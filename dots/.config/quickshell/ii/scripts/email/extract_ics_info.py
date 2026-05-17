#!/usr/bin/env python3
import sys, json, re, os
from datetime import datetime

def parse_ics_date(date_str):
    # Formats: 20260427T133000Z or 20260427T133000 or 20260427
    if not date_str:
        return None
    date_str = date_str.strip()
    try:
        # Remove any parameters if they leaked in (should be handled by regex but just in case)
        if ':' in date_str:
            date_str = date_str.split(':')[-1]
            
        if 'T' in date_str:
            # Handle YYYYMMDDTHHMMSS...
            clean_date = re.sub(r'[^0-9T]', '', date_str)
            if len(clean_date) >= 15: # YYYYMMDDTHHMMSS
                return datetime.strptime(clean_date[:15], "%Y%m%dT%H%M%S")
        else:
            # Handle YYYYMMDD
            clean_date = re.sub(r'[^0-9]', '', date_str)
            if len(clean_date) >= 8:
                return datetime.strptime(clean_date[:8], "%Y%m%d")
        return None
    except:
        return None

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No file provided"}))
        return

    path = sys.argv[1]
    if not os.path.exists(path):
        print(json.dumps({"error": "File not found"}))
        return

    try:
        with open(path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
        
        # Unfold lines (ICS lines starting with space/tab are continuations)
        content = ""
        for line in lines:
            if line.startswith((' ', '\t')):
                content += line[1:].rstrip('\r\n')
            else:
                content += "\n" + line.rstrip('\r\n')
        
        events = []
        # Basic VEVENT extraction
        vevents = re.findall(r'BEGIN:VEVENT.*?END:VEVENT', content, re.DOTALL | re.IGNORECASE)
        
        for vevent in vevents:
            def find_prop(key):
                # Search for the property line and handle parameters
                # KEY[;params]:VALUE
                pattern = rf'^{key}(?:;.*?)?:(.*)'
                m = re.search(pattern, vevent, re.MULTILINE | re.IGNORECASE)
                if m:
                    return m.group(1).strip()
                return None

            s = find_prop('SUMMARY') or "No Title"
            dtstart_raw = find_prop('DTSTART')
            dtend_raw = find_prop('DTEND')
            desc = find_prop('DESCRIPTION') or ""
            loc = find_prop('LOCATION') or ""

            d_start = parse_ics_date(dtstart_raw) if dtstart_raw else None
            d_end = parse_ics_date(dtend_raw) if dtend_raw else d_start

            if d_start:
                events.append({
                    "title": s,
                    "date": d_start.strftime("%Y-%m-%d"),
                    "startTime": d_start.strftime("%H:%M"),
                    "endTime": d_end.strftime("%H:%M") if d_end else d_start.strftime("%H:%M"),
                    "description": desc + (f" @ {loc}" if loc else ""),
                })

        print(json.dumps({"success": True, "events": events}))

    except Exception as e:
        print(json.dumps({"error": str(e)}))

if __name__ == "__main__":
    main()
