// Compacts the focused monitor's workspaces so occupied ones become 1..N with no gaps.
//
// Nothing is moved between workspaces: the workspaces themselves are renumbered, so every window
// keeps its exact place — dwindle's split tree and ratios, floating geometry, fullscreen state and
// groups all survive untouched. Special and named workspaces are left alone.

use serde_json::Value;
use std::collections::HashMap;
use std::env;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;

/// Must match `lockWorkspaceMin` in `services/WorkspaceCompactor.qml`.
const LOCK_WORKSPACE_MIN: i64 = 10000;

/// Where empty workspaces are parked while the occupied ones are renumbered onto their ids. Far
/// above anything the bar shows and below `LOCK_WORKSPACE_MIN`, so neither the lock screen's
/// workspace sweep nor the guard below ever sees one. They are empty and invisible, so Hyprland
/// destroys them again on its own.
const PARK_BASE: i64 = 9000;

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

fn change_id(from: i64, to: i64) -> String {
    format!("hl.dsp.workspace.change_id({{ workspace = {}, id = {} }})", from, to)
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

/// Regular numbered workspaces only: special ones carry a negative id, named ones a
/// non-numeric name.
fn is_regular(ws: &Value) -> bool {
    let id = ws.get("id").and_then(|v| v.as_i64()).unwrap_or(0);
    let name = ws.get("name").and_then(|v| v.as_str()).unwrap_or("");
    id > 0 && name == id.to_string()
}

/// A workspace Hyprland is currently holding. `windows` counts every window on it, including any
/// the `clients` dump leaves out, so "empty" here really means nothing would be renumbered away.
/// Named workspaces are in here too even though they never take part in a compaction: they own a
/// perfectly ordinary positive id, so one of them can still be sitting on a target.
struct Existing {
    monitor_id: i64,
    windows: i64,
    regular: bool,
    persistent: bool,
}

/// Can this workspace be shoved aside to free its id? Only an empty, throwaway, numbered
/// workspace of the monitor being compacted. A named one carries its identity in its name, a
/// persistent one would survive the parking as a stray workspace and lose its rules, and one that
/// belongs to another monitor is not ours to renumber.
impl Existing {
    fn parkable(&self, mon_id: i64) -> bool {
        self.regular && !self.persistent && self.windows == 0 && self.monitor_id == mon_id
    }
}

fn existing_workspaces() -> HashMap<i64, Existing> {
    let Some(list) = query("workspaces") else {
        return HashMap::new();
    };
    let Some(arr) = list.as_array() else {
        return HashMap::new();
    };

    arr.iter()
        .filter_map(|ws| {
            Some((
                ws.get("id")?.as_i64()?,
                Existing {
                    monitor_id: ws.get("monitorID").and_then(|v| v.as_i64()).unwrap_or(-1),
                    windows: ws.get("windows").and_then(|v| v.as_i64()).unwrap_or(0),
                    regular: is_regular(ws),
                    persistent: ws.get("ispersistent").and_then(|v| v.as_bool()).unwrap_or(false),
                },
            ))
        })
        .collect()
}

/// Ids of the regular workspaces on `mon_id` that hold at least one window, ascending.
fn occupied_workspaces(mon_id: i64) -> Vec<i64> {
    let Some(clients) = query("clients") else {
        return Vec::new();
    };
    let Some(arr) = clients.as_array() else {
        return Vec::new();
    };

    let mut ids: Vec<i64> = arr
        .iter()
        .filter(|c| c.get("monitor").and_then(|v| v.as_i64()) == Some(mon_id))
        .filter(|c| c.get("workspace").map(is_regular).unwrap_or(false))
        .filter_map(|c| c.get("workspace")?.get("id")?.as_i64())
        .collect();
    ids.sort_unstable();
    ids.dedup();
    ids
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
    // Lock.qml). Compacting relative to one would renumber workspaces up next to it, and the lock
    // screen then sweeps them all onto a single workspace on unlock.
    if active_ws >= LOCK_WORKSPACE_MIN {
        return;
    }
    let ws_map_cfg = read_workspace_map_config();
    let block = active_block(&ws_map_cfg, monitor_index(&monitors, mon_name), active_ws, group_size);

    // Only the active block takes part. A monitor can hold several blocks at once (workspaces
    // 11-20 are the second page of a single monitor), and compacting across them would renumber
    // windows from every other page into this one instead of closing the gaps inside it.
    let occupied: Vec<i64> = occupied_workspaces(mon_id)
        .into_iter()
        .filter(|&ws| ws > block.base && ws <= block.base + block.span)
        .collect();
    if occupied.is_empty() {
        return;
    }

    let mapping: HashMap<i64, i64> = occupied
        .iter()
        .enumerate()
        .map(|(rank, &ws)| (ws, block.base + rank as i64 + 1))
        .collect();

    if mapping.iter().all(|(src, dst)| src == dst) {
        return; // already gapless
    }

    // Renumbering runs in ascending source order, so every target is either free already or
    // vacated by an earlier step — except where a workspace that is not taking part still owns the
    // id (the user standing on a blank workspace below the gap is the usual one). Throwaway empty
    // ones get parked out of the way first. Anything else sitting on a target — a named or
    // persistent workspace, or one belonging to another monitor — is not ours to renumber, and
    // half a compaction is worse than none, so the whole run is abandoned.
    let existing = existing_workspaces();
    let mut parked: Vec<(i64, i64)> = Vec::new();
    let mut park_next = PARK_BASE;
    for src in &occupied {
        let dst = mapping[src];
        let Some(blocker) = existing.get(&dst) else {
            continue;
        };
        if mapping.contains_key(&dst) {
            continue; // it is one of ours and moves out of the way on its own
        }
        if !blocker.parkable(mon_id) {
            eprintln!("workspace_compactor: workspace {} is in the way, not compacting", dst);
            return;
        }
        while existing.contains_key(&park_next) {
            park_next += 1;
        }
        if park_next >= LOCK_WORKSPACE_MIN {
            eprintln!("workspace_compactor: no free workspace id to park {} on", dst);
            return;
        }
        parked.push((dst, park_next));
        park_next += 1;
    }

    let mut cmds: Vec<String> = parked.iter().map(|&(from, to)| change_id(from, to)).collect();
    for src in &occupied {
        let dst = mapping[src];
        if dst != *src {
            cmds.push(change_id(*src, dst));
        }
    }

    // Where the view ends up. The active workspace keeps the monitor's focus through its own
    // renumbering, so the common case needs no dispatch at all and the focused window is never
    // touched. It only has to be told where to go when it was the blank workspace that got parked
    // (stay on the same number, which now holds what was compacted onto it), or when it is an
    // empty workspace above the gap: a manual run then falls back to the nearest occupied
    // workspace below it, while --auto stays put — a background compaction pulling the view off an
    // intentionally empty workspace would be focus theft.
    let parked_to = parked.iter().find(|&&(from, _)| from == active_ws).map(|&(_, to)| to);
    let landed_on = mapping.get(&active_ws).copied().or(parked_to).unwrap_or(active_ws);
    let target_ws = if let Some(dst) = mapping.get(&active_ws) {
        *dst
    } else if parked_to.is_some() {
        active_ws
    } else if auto {
        active_ws
    } else {
        occupied
            .iter()
            .filter(|&&ws| ws < active_ws)
            .max()
            .map(|ws| mapping[ws])
            .unwrap_or(active_ws)
    };
    if landed_on != target_ws {
        cmds.push(format!("hl.dsp.focus({{ workspace = {} }})", target_ws));
    }

    dispatch_batch(&cmds);
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
