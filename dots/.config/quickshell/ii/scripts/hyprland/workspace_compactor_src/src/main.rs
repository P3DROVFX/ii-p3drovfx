// Compacts the focused monitor's workspaces so occupied ones become 1..N with no gaps.
//
// Windows on a workspace stay together and keep their order; floating geometry is restored
// exactly, tiled geometry is replayed best-effort to nudge dwindle's split ratios back.
// Special and named workspaces are left alone.

use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::env;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;

/// Must match `lockWorkspaceMin` in `services/WorkspaceCompactor.qml`.
const LOCK_WORKSPACE_MIN: i64 = 10000;

/// Speaks the Hyprland IPC protocol directly — no `hyprctl` subprocess.
fn hyprctl(command: &str) -> Option<String> {
    let xdg_runtime = env::var("XDG_RUNTIME_DIR").ok()?;
    let sig = env::var("HYPRLAND_INSTANCE_SIGNATURE").ok()?;
    let path = format!("{}/hypr/{}/.socket.sock", xdg_runtime, sig);

    let mut stream = UnixStream::connect(&path).ok()?;
    stream.write_all(command.as_bytes()).ok()?;

    let mut response = String::new();
    stream.read_to_string(&mut response).ok()?;
    Some(response)
}

fn query(what: &str) -> Option<Value> {
    serde_json::from_str(&hyprctl(&format!("j/{}", what))?).ok()
}

/// This Hyprland evaluates `dispatch` payloads as Lua, so dispatchers use the `hl.dsp.*` form.
fn dispatch_batch(cmds: &[String]) {
    if cmds.is_empty() {
        return;
    }
    let joined = cmds
        .iter()
        .map(|c| format!("dispatch {}", c))
        .collect::<Vec<_>>()
        .join(";");
    hyprctl(&format!("[[BATCH]]{}", joined));
}

/// Mirrors `Config.options.bar.workspaces` (`~/.config/illogical-impulse/config.json`) — the
/// same per-monitor ranges the bar itself uses, so the compactor lands windows where the bar
/// already expects them.
struct WorkspaceMapConfig {
    use_map: bool,
    map: Vec<i64>,
    shown: i64,
}

fn read_workspace_map_config() -> WorkspaceMapConfig {
    let default = WorkspaceMapConfig { use_map: false, map: Vec::new(), shown: 7 };

    let Ok(config_home) = env::var("XDG_CONFIG_HOME")
        .or_else(|_| env::var("HOME").map(|h| format!("{}/.config", h)))
    else {
        return default;
    };
    let path = format!("{}/illogical-impulse/config.json", config_home);
    let Ok(contents) = std::fs::read_to_string(&path) else {
        return default;
    };
    let Ok(json) = serde_json::from_str::<Value>(&contents) else {
        return default;
    };

    let ws = &json["bar"]["workspaces"];
    WorkspaceMapConfig {
        use_map: ws["useWorkspaceMap"].as_bool().unwrap_or(false),
        map: ws["workspaceMap"]
            .as_array()
            .map(|a| a.iter().filter_map(|v| v.as_i64()).collect())
            .unwrap_or_default(),
        shown: ws["shown"].as_i64().unwrap_or(7),
    }
}

/// Position of `name` among the monitors Hyprland knows about — matches
/// `HyprlandData.monitors.findIndex(mon => mon.name === ...)` in the QML bar, so "monitor index
/// 1" here means the same output the bar calls index 1.
fn monitor_index(monitors: &Value, name: &str) -> i64 {
    monitors
        .as_array()
        .and_then(|arr| arr.iter().position(|m| m.get("name").and_then(|v| v.as_str()) == Some(name)))
        .map(|i| i as i64)
        .unwrap_or(0)
}

/// `workspaceGroupSize` from the Hyprland config — the page size `workspace_in_group()` counts in.
/// The keybind passes no argument, so read it rather than assuming the default of 10. `custom/`
/// wins: it is sourced last and overrides the shipped value.
fn read_group_size() -> Option<i64> {
    let home = env::var("HOME").ok()?;
    for rel in ["custom/variables.lua", "hyprland/variables.lua"] {
        let Ok(contents) = std::fs::read_to_string(format!("{}/.config/hypr/{}", home, rel)) else {
            continue;
        };
        let found = contents
            .lines()
            .filter_map(|line| {
                let line = line.trim();
                if line.starts_with("--") {
                    return None;
                }
                let value = line.strip_prefix("workspaceGroupSize")?.trim_start().strip_prefix('=')?;
                let token = value.split_whitespace().next()?.trim_end_matches(';');
                token.parse::<i64>().ok().filter(|&n| n > 0)
            })
            .last();
        if found.is_some() {
            return found;
        }
    }
    None
}

/// The block of workspaces the active one sits in: ids in `(base, base + span]`. `base` is one
/// below the block's first id, so the rank-`n` occupied workspace lands on `base + n`.
struct Block {
    base: i64,
    span: i64,
}

/// Which workspaces this compaction is allowed to touch. When the bar's own workspace-map
/// isolation is on, defer to it entirely so the compactor and the bar always agree: a monitor owns
/// the ids above its `workspaceMap` entry, paged into groups of `shown`. Otherwise fall back to
/// the Hyprland-lua `workspace_in_group()` convention (fixed-size blocks of `group_size`) that
/// actually places windows when `SUPER+digit` is pressed.
fn active_block(cfg: &WorkspaceMapConfig, monitor_idx: i64, active_ws: i64, group_size: i64) -> Block {
    if !cfg.use_map {
        let span = group_size.max(1);
        return Block { base: (active_ws - 1) / span * span, span };
    }
    let offset = cfg.map.get(monitor_idx as usize).copied().unwrap_or(monitor_idx * cfg.shown);
    let span = cfg.shown.max(1);
    // Mirrors `workspaceGroup` in Workspaces.qml: the page the bar is showing right now.
    let page = (active_ws - offset - 1).max(0) / span;
    Block { base: offset + page * span, span }
}

struct Snap {
    address: String,
    ws_id: i64,
    at: (i64, i64),
    size: (i64, i64),
    floating: bool,
    fullscreen: bool,
    group: Vec<String>,
}

fn pair(v: &Value, key: &str) -> Option<(i64, i64)> {
    let a = v.get(key)?.as_array()?;
    Some((a.first()?.as_i64()?, a.get(1)?.as_i64()?))
}

/// Regular numbered workspaces only: special ones carry a negative id, named ones a
/// non-numeric name.
fn is_regular(ws: &Value) -> bool {
    let id = ws.get("id").and_then(|v| v.as_i64()).unwrap_or(0);
    let name = ws.get("name").and_then(|v| v.as_str()).unwrap_or("");
    id > 0 && name == id.to_string()
}

fn snapshot(mon_id: i64) -> Vec<Snap> {
    let Some(clients) = query("clients") else {
        return Vec::new();
    };
    let Some(arr) = clients.as_array() else {
        return Vec::new();
    };

    // Preserves hyprctl's own ordering, the closest proxy we have to dwindle's insertion order.
    arr.iter()
        .filter(|c| c.get("monitor").and_then(|v| v.as_i64()) == Some(mon_id))
        .filter(|c| c.get("workspace").map(is_regular).unwrap_or(false))
        .filter_map(|c| {
            Some(Snap {
                address: c.get("address")?.as_str()?.to_string(),
                ws_id: c.get("workspace")?.get("id")?.as_i64()?,
                at: pair(c, "at")?,
                size: pair(c, "size")?,
                floating: c.get("floating").and_then(|v| v.as_bool()).unwrap_or(false),
                fullscreen: c.get("fullscreen").and_then(|v| v.as_i64()).unwrap_or(0) != 0,
                group: c
                    .get("grouped")
                    .and_then(|v| v.as_array())
                    .map(|a| a.iter().filter_map(|g| g.as_str().map(String::from)).collect())
                    .unwrap_or_default(),
            })
        })
        .collect()
}

fn main() {
    let Some(monitors) = query("monitors all") else {
        eprintln!("workspace_compactor: cannot reach the Hyprland socket");
        std::process::exit(1);
    };
    let Some(focused) = monitors
        .as_array()
        .and_then(|a| a.iter().find(|m| m.get("focused").and_then(|v| v.as_bool()) == Some(true)))
    else {
        eprintln!("workspace_compactor: no focused monitor");
        std::process::exit(1);
    };

    let mon_id = focused.get("id").and_then(|v| v.as_i64()).unwrap_or(0);
    let mon_name = focused.get("name").and_then(|v| v.as_str()).unwrap_or("");
    let active_ws = focused
        .get("activeWorkspace")
        .and_then(|w| w.get("id"))
        .and_then(|v| v.as_i64())
        .unwrap_or(1);

    // --auto marks a background invocation (Quickshell's Auto-Compact service): the user did
    // not ask for this compaction, so the view must never be moved on their behalf.
    let mut auto = false;
    // Only used when the bar's own workspace-map isolation (below) is off. An explicit argument
    // beats the value read out of the Hyprland config.
    let mut group_size: Option<i64> = None;
    for arg in env::args().skip(1) {
        if arg == "--auto" {
            auto = true;
        } else if let Some(n) = arg.parse::<i64>().ok().filter(|&n| n > 0) {
            group_size = Some(n);
        }
    }
    let group_size = group_size.or_else(read_group_size).unwrap_or(10);
    // The shell's lock screen parks monitors on temporary workspaces with ids >= 10000 (see
    // Lock.qml). Compacting relative to one would push every window up next to it, and the lock
    // screen then sweeps them all onto a single workspace on unlock.
    if active_ws >= LOCK_WORKSPACE_MIN {
        return;
    }
    let ws_map_cfg = read_workspace_map_config();
    let block = active_block(&ws_map_cfg, monitor_index(&monitors, mon_name), active_ws, group_size);

    // Only the active block takes part. A monitor can hold several blocks at once (workspaces
    // 11-20 are the second page of a single monitor), and compacting across them would renumber
    // windows from every other page into this one instead of closing the gaps inside it.
    let snaps: Vec<Snap> = snapshot(mon_id)
        .into_iter()
        .filter(|s| s.ws_id > block.base && s.ws_id <= block.base + block.span)
        .collect();
    if snaps.is_empty() {
        return;
    }

    let mut occupied: Vec<i64> = snaps.iter().map(|s| s.ws_id).collect();
    occupied.sort_unstable();
    occupied.dedup();

    let mapping: HashMap<i64, i64> = occupied
        .iter()
        .enumerate()
        .map(|(rank, &ws)| (ws, block.base + rank as i64 + 1))
        .collect();

    if mapping.iter().all(|(src, dst)| src == dst) {
        return; // already gapless
    }

    // Remember what to re-focus before anything moves. This can name a window on a workspace
    // we aren't even looking at: a silent move leaves focus attached to the window it sent away.
    let focused_window = query("activewindow")
        .and_then(|w| w.get("address").and_then(|v| v.as_str()).map(String::from));

    // Ascending source order means every target is either originally empty or already
    // vacated by an earlier move, so sources never collide with each other.
    let mut moves = Vec::new();
    let mut handled: HashSet<&str> = HashSet::new();
    for src in &occupied {
        let dst = mapping[src];
        if dst == *src {
            continue;
        }
        for s in snaps.iter().filter(|s| s.ws_id == *src) {
            if handled.contains(s.address.as_str()) {
                continue;
            }
            // Moving any member of a group drags the whole group along.
            handled.insert(&s.address);
            handled.extend(s.group.iter().map(String::as_str));

            moves.push(format!(
                "hl.dsp.window.move({{ workspace = {}, window = \"address:{}\", follow = false }})",
                dst, s.address
            ));
        }
    }
    dispatch_batch(&moves);

    // Replay geometry only for windows that actually moved. Fullscreen windows keep their
    // state across the move on their own and must not be resized.
    let mut geometry = Vec::new();
    for s in &snaps {
        if s.fullscreen || mapping[&s.ws_id] == s.ws_id {
            continue;
        }
        geometry.push(format!(
            "hl.dsp.window.resize({{ x = {}, y = {}, relative = false, window = \"address:{}\" }})",
            s.size.0, s.size.1, s.address
        ));
        if s.floating {
            geometry.push(format!(
                "hl.dsp.window.move({{ x = {}, y = {}, relative = false, window = \"address:{}\" }})",
                s.at.0, s.at.1, s.address
            ));
        }
    }
    dispatch_batch(&geometry);

    // Follow the active workspace to its new number. If it was empty it has no mapping:
    // manual runs fall back to the nearest occupied workspace below it (failing that, stay
    // put), while --auto runs always stay put — a background compaction pulling the view off
    // an intentionally empty workspace would be focus theft.
    let target_ws = mapping.get(&active_ws).copied().unwrap_or_else(|| {
        if auto {
            return active_ws;
        }
        occupied
            .iter()
            .filter(|&&ws| ws < active_ws)
            .max()
            .map(|ws| mapping[ws])
            .unwrap_or(active_ws)
    });

    // Restoring the remembered window is only right when it landed on the workspace we're
    // switching to. Otherwise focus is stale and re-applying it would drag the view off to
    // wherever that window went, overriding the choice made just above.
    let refocus = focused_window
        .filter(|addr| snaps.iter().any(|s| &s.address == addr && mapping[&s.ws_id] == target_ws));

    let mut focus = vec![format!("hl.dsp.focus({{ workspace = {} }})", target_ws)];
    if let Some(addr) = refocus {
        focus.push(format!("hl.dsp.focus({{ window = \"address:{}\" }})", addr));
    }
    dispatch_batch(&focus);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cfg(use_map: bool, map: Vec<i64>, shown: i64) -> WorkspaceMapConfig {
        WorkspaceMapConfig { use_map, map, shown }
    }

    #[test]
    fn fallback_blocks() {
        let c = cfg(false, vec![], 10);
        for (ws, base) in [(1, 0), (9, 0), (10, 0), (11, 10), (20, 10), (21, 20)] {
            let b = active_block(&c, 0, ws, 10);
            assert_eq!((b.base, b.span), (base, 10), "ws {}", ws);
        }
        // non-default page size
        let b = active_block(&c, 0, 8, 5);
        assert_eq!((b.base, b.span), (5, 5));
    }

    #[test]
    fn map_blocks() {
        let c = cfg(true, vec![0, 10], 10);
        assert_eq!(active_block(&c, 0, 3, 10).base, 0);
        assert_eq!(active_block(&c, 0, 11, 10).base, 10); // page 2 of monitor 0
        assert_eq!(active_block(&c, 1, 11, 10).base, 10);
        assert_eq!(active_block(&c, 1, 25, 10).base, 20);
    }
}
