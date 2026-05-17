#!/usr/bin/env python3
"""Normalize and import an ICS file into khal.

Some email clients (e.g. Microsoft Exchange) generate ICS files with
double carriage returns (\r\r\n) instead of the RFC 5545-compliant \r\n.
This script normalizes the line endings before passing the file to khal.

Usage: import_ics.py <path_to_ics>
Outputs JSON: { "success": true/false, "event_count": N, "error": "..." }
"""
import sys
import json
import os
import subprocess
import tempfile
import re

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"success": False, "error": "No ICS file provided"}))
        return

    path = sys.argv[1]
    if not os.path.exists(path):
        print(json.dumps({"success": False, "error": f"File not found: {path}"}))
        return

    try:
        with open(path, 'rb') as f:
            raw = f.read()

        # Normalize line endings:
        # Some Exchange servers produce \r\r\n, we normalize to \r\n
        normalized = raw.replace(b'\r\r\n', b'\r\n')
        # Also normalize bare \r to nothing if not followed by \n
        normalized = re.sub(rb'\r(?!\n)', b'', normalized)

        # Count events in the file
        event_count = normalized.count(b'BEGIN:VEVENT')

        # Write to a temp file
        with tempfile.NamedTemporaryFile(suffix='.ics', delete=False, mode='wb') as tmp:
            tmp.write(normalized)
            tmp_path = tmp.name

        try:
            result = subprocess.run(
                ['khal', 'import', '--batch', '--random_uid', tmp_path],
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode == 0:
                print(json.dumps({"success": True, "event_count": event_count}))
            else:
                print(json.dumps({
                    "success": False,
                    "event_count": 0,
                    "error": result.stderr.strip() or result.stdout.strip()
                }))
        finally:
            os.unlink(tmp_path)
            # Delete original if requested
            if len(sys.argv) > 2 and sys.argv[2].lower() == "true":
                try:
                    os.unlink(path)
                except:
                    pass

    except subprocess.TimeoutExpired:
        print(json.dumps({"success": False, "error": "khal timed out"}))
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}))

if __name__ == "__main__":
    main()
