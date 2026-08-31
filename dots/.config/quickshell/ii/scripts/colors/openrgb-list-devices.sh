#!/usr/bin/env bash

# Check if openrgb CLI binary exists
binary_installed=false
if command -v openrgb >/dev/null 2>&1; then
    binary_installed=true
fi

# Check if python3 exists
python_installed=false
if command -v python3 >/dev/null 2>&1; then
    python_installed=true
fi

# Check if Python openrgb and scipy modules are importable
python_module_installed=false
if [ "$python_installed" = true ]; then
    if python3 -c "import openrgb, scipy" >/dev/null 2>&1; then
        python_module_installed=true
    fi
fi

# Check if openrgb process is running
server_running=false
if pgrep -x openrgb >/dev/null 2>&1; then
    server_running=true
fi

# If openrgb binary is missing
if [ "$binary_installed" = false ]; then
    printf '{"ok":false,"binaryInstalled":false,"pythonModuleInstalled":%s,"serverRunning":false,"errorType":"missing_binary","error":"OpenRGB binary not found in PATH","devices":[]}\n' "$python_module_installed"
    exit 0
fi

# If python3 is missing
if [ "$python_installed" = false ]; then
    printf '{"ok":false,"binaryInstalled":true,"pythonModuleInstalled":false,"serverRunning":%s,"errorType":"missing_python","error":"python3 not installed","devices":[]}\n' "$server_running"
    exit 0
fi

# Query devices from openrgb CLI
list_output=$(openrgb --list-devices 2>/dev/null || true)

if [[ -z "$list_output" ]]; then
    printf '{"ok":true,"binaryInstalled":true,"pythonModuleInstalled":%s,"serverRunning":%s,"errorType":"no_devices","error":"No OpenRGB devices found or server not responding","devices":[]}\n' "$python_module_installed" "$server_running"
    exit 0
fi

json_output=$(printf '%s\n' "$list_output" | python3 -c '
import json
import re
import sys

binary_installed = sys.argv[1] == "true"
py_module_installed = sys.argv[2] == "true"
server_running = sys.argv[3] == "true"

devices = []
for line in sys.stdin:
    match = re.match(r"^(\d+):\s*(.+)$", line.strip())
    if match:
        devices.append({
            "id": int(match.group(1)),
            "name": match.group(2),
        })

print(json.dumps({
    "ok": True,
    "binaryInstalled": binary_installed,
    "pythonModuleInstalled": py_module_installed,
    "serverRunning": server_running,
    "devices": devices,
    "errorType": "",
    "error": ""
}))
' "$binary_installed" "$python_module_installed" "$server_running")

printf '%s\n' "$json_output"