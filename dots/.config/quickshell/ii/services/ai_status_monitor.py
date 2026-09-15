#!/usr/bin/env python3
"""
AI Process Status Monitor for Quickshell ii Dynamic Island
Scans for active AI CLI/IDE agents (Antigravity, Command Code, Claude, Gemini, Aider, Goose)
and outputs JSON status stream on stdout ONLY when an agent is actively processing/executing a task.
"""
import subprocess
import json
import time
import os
import sys

AI_PROCESSES = [
    {"pattern": "language_server_linux_x64", "name": "Antigravity", "icon": "material-symbols_antigravity.svg"},
    {"pattern": "antigravity-cli", "name": "Antigravity CLI", "icon": "material-symbols_antigravity.svg"},
    {"pattern": "antigravity_cli", "name": "Antigravity CLI", "icon": "material-symbols_antigravity.svg"},
    {"pattern": "commandcode", "name": "Command Code", "icon": "openai-symbolic.svg"},
    {"pattern": "claude", "name": "Claude CLI", "icon": "bootstrap_claude.svg"},
    {"pattern": "gemini", "name": "Gemini CLI", "icon": "google-gemini-symbolic.svg"},
    {"pattern": "aider", "name": "Aider", "icon": "google-gemini-symbolic.svg"},
    {"pattern": "goose", "name": "Goose", "icon": "google-gemini-symbolic.svg"},
]

TOOL_PROCESS_NAMES = {"bash", "sh", "zsh", "python", "python3", "git", "curl", "rg", "grep", "cat", "chmod", "cargo", "make"}

# Track active execution state across loop iterations
# pid -> {"prev_ticks": int, "active_since": float, "idle_count": int, "is_active": bool}
PROC_STATES = {}

def get_cpu_ticks(pid):
    try:
        with open(f"/proc/{pid}/stat", "r") as f:
            stat_content = f.read()
        rparen_idx = stat_content.rfind(')')
        if rparen_idx == -1:
            return 0
        fields = stat_content[rparen_idx+1:].split()
        utime = int(fields[11])
        stime = int(fields[12])
        cutime = int(fields[13])
        cstime = int(fields[14])
        return utime + stime + cutime + cstime
    except Exception:
        return 0

def has_tool_execution_child(pid):
    try:
        out = subprocess.check_output(["pgrep", "-P", str(pid), "-a"], text=True, stderr=subprocess.DEVNULL)
        for line in out.strip().splitlines():
            parts = line.strip().split(None, 1)
            if len(parts) >= 2:
                cmd = parts[1]
                # Filter out persistent background MCP servers
                if "chrome-devtools-mcp" in cmd or "mcp" in cmd or "language_server" in cmd:
                    continue
                proc_base = cmd.split()[0].split("/")[-1].lower()
                if proc_base in TOOL_PROCESS_NAMES:
                    return True
    except Exception:
        pass
    return False

def scan_ai_processes():
    agents_candidates = []
    seen_pids = set()
    self_pid = os.getpid()

    try:
        patterns = [p["pattern"] for p in AI_PROCESSES]
        cmd_args = ["pgrep", "-a", "-f", "|".join(patterns)]
        out = subprocess.check_output(cmd_args, text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return []

    for line in out.strip().splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split(None, 1)
        if len(parts) < 2:
            continue
        try:
            pid = int(parts[0])
        except ValueError:
            continue

        cmd = parts[1]
        if pid == self_pid or pid in seen_pids:
            continue

        # Skip self, python scripts monitoring, pgrep wrappers, bash subshells
        if "ai_status_monitor.py" in cmd or "pgrep" in cmd or "grep" in cmd:
            continue
        if cmd.startswith("bash -c") or cmd.startswith("sh -c"):
            continue

        # Ignore OpenCode completely + ignore Electron main window frame & helper daemons
        if any(ignore_flag in cmd for ignore_flag in [
            "opencode", "oh-my-opencode", "companion",
            "--type=zygote", "--type=gpu-process", "--type=utility",
            "chrome_crashpad_handler", "pyrefly lsp", "tailwindServer",
            "serverWorkerMain", "cpuUsage.sh", "jsonServerMain"
        ]):
            continue

        # Skip Electron main window binary
        if cmd.endswith("antigravity-ide") or "/antigravity-ide --" in cmd:
            continue

        for proc_spec in AI_PROCESSES:
            pattern = proc_spec["pattern"]
            if pattern in cmd:
                seen_pids.add(pid)
                agents_candidates.append({
                    "id": f"{pattern}_{pid}",
                    "pid": pid,
                    "name": proc_spec["name"],
                    "icon": proc_spec["icon"],
                    "source": "cli",
                    "cmd": cmd[:100]
                })
                break

    current_time = time.time()
    active_agents = []

    # Clean up state for dead PIDs
    dead_pids = [p for p in PROC_STATES if p not in seen_pids]
    for dp in dead_pids:
        del PROC_STATES[dp]

    for candidate in agents_candidates:
        pid = candidate["pid"]
        curr_ticks = get_cpu_ticks(pid)
        has_tool = has_tool_execution_child(pid)

        if pid not in PROC_STATES:
            PROC_STATES[pid] = {
                "prev_ticks": curr_ticks,
                "active_since": 0,
                "idle_count": 0,
                "is_active": False
            }
            continue # First cycle baseline

        state_obj = PROC_STATES[pid]
        cpu_delta = curr_ticks - state_obj["prev_ticks"]
        state_obj["prev_ticks"] = curr_ticks

        # Active work threshold: CPU tick delta >= 15 or active tool execution child processes
        is_working = (cpu_delta >= 15) or has_tool

        if is_working:
            if not state_obj["is_active"]:
                state_obj["is_active"] = True
                state_obj["active_since"] = current_time
            state_obj["idle_count"] = 0
        else:
            if state_obj["is_active"]:
                state_obj["idle_count"] += 1
                # Require 2 consecutive idle cycles before turning off
                if state_obj["idle_count"] >= 2:
                    state_obj["is_active"] = False
                    state_obj["active_since"] = 0

        if state_obj["is_active"]:
            runtime = max(0, int(current_time - state_obj["active_since"]))
            candidate["runtime"] = runtime
            candidate["state"] = "running"
            active_agents.append(candidate)

    # Group by agent name to present one primary entry per active agent type
    grouped = {}
    for a in active_agents:
        name = a["name"]
        if name not in grouped or a["runtime"] > grouped[name]["runtime"]:
            grouped[name] = a

    return list(grouped.values())

def main():
    while True:
        try:
            agents = scan_ai_processes()
            print(json.dumps({"agents": agents}), flush=True)
        except BrokenPipeError:
            sys.exit(0)
        except Exception as e:
            try:
                print(json.dumps({"agents": [], "error": str(e)}), flush=True)
            except BrokenPipeError:
                sys.exit(0)
        time.sleep(1)

if __name__ == "__main__":
    main()
