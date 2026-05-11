#!/usr/bin/env python3
import obsws_python as obs
import os
import sys

def main():
    host = os.environ.get("OBS_API_HOST", "localhost")
    port = int(os.environ.get("OBS_API_PORT", 4455))
    # NOTE: For this to work, you must either disable the OBS WebSocket password
    # in OBS Settings -> General -> WebSocket Server Settings, or define it
    # in your environment as OBS_API_PASSWORD.
    password = os.environ.get("OBS_API_PASSWORD")

    try:
        cl = obs.ReqClient(host=host, port=port, password=password, timeout=3)
        cl.toggle_record_pause()
        print("Successfully toggled OBS recording pause.")
    except Exception as e:
        print(f"Error connecting to OBS or toggling pause: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
