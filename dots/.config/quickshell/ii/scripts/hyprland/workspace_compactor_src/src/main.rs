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

/// First workspace id belonging to this monitor. When the bar's own workspace-map isolation is
/// on, defer to it entirely so the compactor and the bar always agree. Otherwise fall back to
/// the Hyprland-lua `workspace_in_group()` convention (fixed-size blocks per monitor) that
/// actually places windows when `SUPER+digit` is pressed.
fn block_base(cfg: &WorkspaceMapConfig, monitor_idx: i64, active_ws: i64, group_size: i64) -> i64 {
    if cfg.use_map {
        cfg.map.get(monitor_idx as usize).copied().unwrap_or(monitor_idx * cfg.shown)
    } else {
        (active_ws - 1) / group_size * group_size
    }
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

    // Only used when the bar's own workspace-map isolation (below) is off.
    let group_size: i64 =
        env::args().nth(1).and_then(|s| s.parse().ok()).filter(|&n| n > 0).unwrap_or(10);
    let ws_map_cfg = read_workspace_map_config();
    let base = block_base(&ws_map_cfg, monitor_index(&monitors, mon_name), active_ws, group_size);

    let snaps = snapshot(mon_id);
    if snaps.is_empty() {
        return;
    }

    let mut occupied: Vec<i64> = snaps.iter().map(|s| s.ws_id).collect();
    occupied.sort_unstable();
    occupied.dedup();

    let mapping: HashMap<i64, i64> = occupied
        .iter()
        .enumerate()
        .map(|(rank, &ws)| (ws, base + rank as i64 + 1))
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

    // Follow the active workspace to its new number. If it was empty it has no mapping, so
    // fall back to the nearest occupied workspace below it; failing that, stay put.
    let target_ws = mapping.get(&active_ws).copied().unwrap_or_else(|| {
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
