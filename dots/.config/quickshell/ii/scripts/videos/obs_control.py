#!/usr/bin/env python3
import obsws_python as obs
import os
import sys

def main():
    if len(sys.argv) < 2:
        print("Usage: obs_control.py [start|stop|toggle|status]")
        sys.exit(1)

    action = sys.argv[1]
    host = os.environ.get("OBS_API_HOST", "localhost")
    port = int(os.environ.get("OBS_API_PORT", 4455))
    password = os.environ.get("OBS_API_PASSWORD")

    # Connect to OBS WebSocket as a separate step so a connection failure can be
    # distinguished from a successful connection where recording is simply inactive.
    # Returning "error" lets the bash script keep waiting for OBS to come online
    # instead of mistaking a connection failure for "recording stopped" and killing OBS.
    try:
        cl = obs.ReqClient(host=host, port=port, password=password, timeout=3)
    except Exception:
        print("error")
        sys.exit(2)

    try:
        if action == "start":
            cl.start_record()
            print("started")
        elif action == "stop":
            cl.stop_record()
            print("stopped")
        elif action == "toggle":
            status = cl.get_record_status()
            if status.output_active:
                cl.stop_record()
                print("stopped")
            else:
                cl.start_record()
                print("started")
        elif action == "status":
            status = cl.get_record_status()
            print("active" if status.output_active else "inactive")
    except Exception:
        # The WebSocket was reachable but the request itself failed (e.g. start_record
        # raised because no source is configured). This is a real failure, not "inactive".
        print("error")
        sys.exit(3)

if __name__ == "__main__":
    main()
