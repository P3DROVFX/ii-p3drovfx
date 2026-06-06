#!/usr/bin/env python3
import sys
import json
import subprocess

def main():
    if len(sys.argv) < 2:
        return

    try:
        ws_map = json.loads(sys.argv[1])
        monitors = json.loads(sys.argv[2])
    except Exception as e:
        print(f"Error parsing arguments: {e}")
        return

    shown = 10 
    if len(sys.argv) > 3:
        try:
            shown = int(sys.argv[3])
        except:
            pass

    if len(ws_map) == 0 or len(monitors) == 0:
        return

    lua_commands = []
    
    for i, mon in enumerate(monitors):
        start_offset = ws_map[i]
        
        if i + 1 < len(ws_map):
            end_offset = ws_map[i+1]
        else:
            end_offset = start_offset + shown
            
        start_ws = start_offset + 1
        end_ws = end_offset
        
        for ws in range(start_ws, end_ws + 1):
            # Set the default monitor so it opens on the correct monitor
            lua_commands.append(f"hl.workspace_rule({{workspace='{ws}', monitor='{mon}'}})")
            # Move it if it's already open on another monitor
            lua_commands.append(f"hl.dispatch(hl.dsp.workspace.move({{workspace={ws}, monitor='{mon}'}}))")

    if lua_commands:
        script = "; ".join(lua_commands)
        subprocess.run(["hyprctl", "eval", script])

if __name__ == "__main__":
    main()
