use dirs::home_dir;
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use std::os::unix::net::UnixStream;
use std::io::{Write, Read};
use which::which;

fn profiles_dir() -> PathBuf {
    let mut path = home_dir().expect("Home dir not found");
    path.push(".config/illogical-impulse/workspace_profiles");
    fs::create_dir_all(&path).ok();
    path
}

fn default_true() -> bool { true }
fn default_emoji() -> String { "🗂️".to_string() }

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
struct SavedWindow {
    #[serde(rename = "class")]
    class: String,
    #[serde(default)]
    initial_class: String,
    workspace_id: Value,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    #[serde(default)]
    floating: bool,
    #[serde(default = "default_true")]
    autolaunch: bool,
    #[serde(default)]
    launch_cmd: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
struct Profile {
    id: String,
    name: String,
    #[serde(default = "default_emoji")]
    emoji: String,
    #[serde(default)]
    description: String,
    created_at: u64,
    #[serde(default)]
    close_others: bool,
    #[serde(default)]
    kill_others: bool,
    #[serde(default)]
    pinned: bool,
    #[serde(default)]
    windows: Vec<SavedWindow>,
}

fn workspace_sort_key(ws_val: &Value) -> (u8, i64, String) {
    if let Some(n) = ws_val.as_i64() {
        (0, n, "".to_string())
    } else if let Some(s) = ws_val.as_str() {
        if let Ok(n) = s.parse::<i64>() {
            (0, n, "".to_string())
        } else {
            (1, 0, s.to_string())
        }
    } else {
        (2, 0, ws_val.to_string())
    }
}

fn is_special_workspace(ws: &Value) -> bool {
    if let Some(s) = ws.as_str() {
        s.starts_with("special")
    } else if let Some(n) = ws.as_i64() {
        n < 0
    } else {
        false
    }
}

fn get_dispatcher_workspace(ws_val: &Value, clients: &[Value]) -> String {
    if let Some(n) = ws_val.as_i64() {
        if n < 0 {
            for c in clients {
                if let Some(ws) = c.get("workspace") {
                    if ws.get("id").and_then(|i| i.as_i64()) == Some(n) {
                        if let Some(name) = ws.get("name").and_then(|n| n.as_str()) {
                            let mut out_name = name;
                            if out_name == "special:special" {
                                out_name = "special";
                            }
                            return format!("\"{}\"", out_name);
                        }
                    }
                }
            }
            return "\"special\"".to_string();
        }
        n.to_string()
    } else if let Some(s) = ws_val.as_str() {
        format!("\"{}\"", s)
    } else {
        ws_val.to_string()
    }
}

fn slugify(name: &str) -> String {
    let slug = name.to_lowercase();
    let re1 = Regex::new(r"[^\w\s-]").unwrap();
    let slug = re1.replace_all(&slug, "");
    let re2 = Regex::new(r"[\s_-]+").unwrap();
    let slug = re2.replace_all(&slug, "_");
    let slug = slug.trim_matches('_');
    if slug.is_empty() { "profile".to_string() } else { slug.to_string() }
}

fn unique_slug(name: &str, exclude: Option<&str>) -> String {
    let base = slugify(name);
    let mut slug = base.clone();
    let mut i = 1;
    let dir = profiles_dir();
    while dir.join(format!("{}.json", slug)).exists() {
        if let Some(exc) = exclude {
            if slug == exc { break; }
        }
        slug = format!("{}_{}", base, i);
        i += 1;
    }
    slug
}

fn load_profile(slug: &str) -> Option<Profile> {
    let path = profiles_dir().join(format!("{}.json", slug));
    let data = fs::read_to_string(path).ok()?;
    serde_json::from_str(&data).ok()
}

fn write_profile(profile: &Profile, slug: &str) {
    let dir = profiles_dir();
    fs::create_dir_all(&dir).ok();
    let path = dir.join(format!("{}.json", slug));
    if let Ok(data) = serde_json::to_string_pretty(profile) {
        fs::write(path, data).ok();
    }
}

fn hyprctl(args: &[&str]) -> (i32, String, String) {
    let command = if args.len() == 2 && args[0] == "clients" && args[1] == "-j" {
        "j/clients".to_string()
    } else if args.len() == 2 && args[0] == "activeworkspace" && args[1] == "-j" {
        "j/activeworkspace".to_string()
    } else if args[0] == "dispatch" {
        format!("/dispatch {}", args[1..].join(" "))
    } else if args[0] == "--batch" {
        format!("[[BATCH]]{}", args[1..].join(" "))
    } else {
        args.join(" ")
    };
    
    let xdg_runtime = match env::var("XDG_RUNTIME_DIR") {
        Ok(s) => s,
        Err(_) => return (1, "".to_string(), "XDG_RUNTIME_DIR not set".to_string()),
    };
    let sig = match env::var("HYPRLAND_INSTANCE_SIGNATURE") {
        Ok(s) => s,
        Err(_) => return (1, "".to_string(), "HYPRLAND_INSTANCE_SIGNATURE not set".to_string()),
    };
    
    let path = format!("{}/hypr/{}/.socket.sock", xdg_runtime, sig);
    
    let mut stream = match UnixStream::connect(&path) {
        Ok(s) => s,
        Err(e) => return (1, "".to_string(), format!("Failed to connect to socket at {}: {}", path, e)),
    };
    
    if let Err(e) = stream.write_all(command.as_bytes()) {
        return (1, "".to_string(), e.to_string());
    }
    
    let mut response = String::new();
    if let Err(e) = stream.read_to_string(&mut response) {
        return (1, "".to_string(), e.to_string());
    }
    
    (0, response, "".to_string())
}

fn live_clients() -> Vec<Value> {
    let (rc, stdout, _) = hyprctl(&["clients", "-j"]);
    if rc == 0 {
        if let Ok(json) = serde_json::from_str::<Value>(&stdout) {
            if let Some(arr) = json.as_array() {
                return arr.clone();
            }
        }
    }
    vec![]
}

fn cmd_list() {
    let dir = profiles_dir();
    let mut results = vec![];
    
    if let Ok(entries) = fs::read_dir(&dir) {
        let mut paths: Vec<_> = entries.filter_map(|e| e.ok()).map(|e| e.path()).collect();
        paths.sort();
        for path in paths {
            if path.extension().and_then(|s| s.to_str()) == Some("json") {
                if let Ok(data) = fs::read_to_string(&path) {
                    if let Ok(profile) = serde_json::from_str::<Profile>(&data) {
                        let slug = path.file_stem().unwrap().to_str().unwrap().to_string();
                        let mut ws_ids: Vec<Value> = profile.windows.iter().map(|w| w.workspace_id.clone()).collect();
                        ws_ids.sort_by(|a, b| workspace_sort_key(a).cmp(&workspace_sort_key(b)));
                        ws_ids.dedup();
                        
                        let has_dup = {
                            let mut seen = HashSet::new();
                            let mut dup = false;
                            for w in &profile.windows {
                                if !seen.insert(w.class.clone()) { dup = true; break; }
                            }
                            dup
                        };

                        results.push(json!({
                            "slug": slug,
                            "id": profile.id,
                            "name": profile.name,
                            "emoji": profile.emoji,
                            "description": profile.description,
                            "createdAt": profile.created_at,
                            "closeOthers": profile.close_others,
                            "killOthers": profile.kill_others,
                            "pinned": profile.pinned,
                            "windowCount": profile.windows.len(),
                            "workspaceIdsJson": serde_json::to_string(&ws_ids).unwrap(),
                            "windowsJson": serde_json::to_string(&profile.windows).unwrap(),
                            "hasDuplicateClasses": has_dup,
                        }));
                    }
                }
            }
        }
    }
    
    results.sort_by(|a, b| {
        let a_pinned = a.get("pinned").and_then(|v| v.as_bool()).unwrap_or(false);
        let b_pinned = b.get("pinned").and_then(|v| v.as_bool()).unwrap_or(false);
        if a_pinned != b_pinned {
            b_pinned.cmp(&a_pinned) // true before false
        } else {
            let a_time = a.get("createdAt").and_then(|v| v.as_u64()).unwrap_or(0);
            let b_time = b.get("createdAt").and_then(|v| v.as_u64()).unwrap_or(0);
            b_time.cmp(&a_time) // newer first
        }
    });

    println!("{}", serde_json::to_string(&results).unwrap());
}

fn cmd_snapshot(meta_json: &str) {
    let meta: Value = match serde_json::from_str(meta_json) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("[error] Invalid JSON from args. Raw: '{}'. Error: {}", meta_json, e);
            std::process::exit(1);
        }
    };
    let (_rc, stdout, _) = hyprctl(&["activeworkspace", "-j"]);
    let _active_ws = match serde_json::from_str::<Value>(&stdout) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("[error] Invalid JSON from j/activeworkspace. Raw: '{}'. Error: {}", stdout, e);
            std::process::exit(1);
        }
    };
    let clients = live_clients();
    let default_map = serde_json::Map::new();
    let overrides = meta.get("windowOverrides").and_then(|v| v.as_object()).unwrap_or(&default_map);
    
    let mut windows = vec![];
    let empty_ws = json!({});
    for w in clients {
        let ws = w.get("workspace").unwrap_or(&empty_ws);
        let ws_id = ws.get("id").and_then(|v| v.as_i64()).unwrap_or(0);
        let ws_name = ws.get("name").and_then(|v| v.as_str()).unwrap_or("");
        if ws_id == 0 { continue; }
        
        let target_ws = if ws_name.starts_with("special:") || ws_id < 0 {
            if ws_name.is_empty() { json!("special:special") } else { json!(ws_name) }
        } else {
            json!(ws_id)
        };
        
        let cls = w.get("class").and_then(|v| v.as_str()).unwrap_or("").to_string();
        let ov = overrides.get(&cls).and_then(|v| v.as_object());
        
        let mut launch_cmd = ov.and_then(|o| o.get("launchCmd")).and_then(|v| v.as_str()).unwrap_or("").to_string();
        
        if launch_cmd.is_empty() {
            if let Some(pid) = w.get("pid").and_then(|v| v.as_i64()) {
                if let Ok(cmdline) = fs::read(format!("/proc/{}/cmdline", pid)) {
                    let parts: Vec<&[u8]> = cmdline.split(|&b| b == 0).collect();
                    if !parts.is_empty() && !parts[0].is_empty() {
                        let detected = String::from_utf8_lossy(parts[0]).to_string();
                        let file_name = Path::new(&detected).file_name().and_then(|n| n.to_str()).unwrap_or("");
                        let is_interpreter = matches!(file_name, "python" | "python3" | "node" | "java" | "ruby" | "bash" | "sh" | "zsh" | "electron");
                        
                        if !detected.starts_with("/tmp/") && !detected.starts_with("./") && !is_interpreter {
                            if detected.starts_with('/') {
                                if Path::new(&detected).exists() {
                                    launch_cmd = detected;
                                }
                            } else if which(&detected).is_ok() {
                                launch_cmd = detected;
                            }
                        }
                    }
                }
            }
        }
        
        if launch_cmd.is_empty() {
            let initial = w.get("initialClass").and_then(|v| v.as_str()).unwrap_or(&cls);
            let raw_cmd = if initial.is_empty() { &cls } else { initial };
            let cls_lower = raw_cmd.to_lowercase();
            let guesses = vec![
                raw_cmd.to_string(),
                cls_lower.replace(" ", "-"),
                cls_lower.replace(" ", ""),
                cls_lower.split_whitespace().next().unwrap_or("").to_string(),
            ];
            for guess in guesses {
                if !guess.is_empty() && which(&guess).is_ok() {
                    launch_cmd = guess;
                    break;
                }
            }
        }
        
        windows.push(SavedWindow {
            class: cls.clone(),
            initial_class: w.get("initialClass").and_then(|v| v.as_str()).unwrap_or(&cls).to_string(),
            workspace_id: target_ws,
            x: w.get("at").and_then(|arr| arr.get(0)).and_then(|v| v.as_i64()).unwrap_or(0) as i32,
            y: w.get("at").and_then(|arr| arr.get(1)).and_then(|v| v.as_i64()).unwrap_or(0) as i32,
            width: w.get("size").and_then(|arr| arr.get(0)).and_then(|v| v.as_i64()).unwrap_or(0) as i32,
            height: w.get("size").and_then(|arr| arr.get(1)).and_then(|v| v.as_i64()).unwrap_or(0) as i32,
            floating: w.get("floating").and_then(|v| v.as_bool()).unwrap_or(false),
            autolaunch: ov.and_then(|o| o.get("autolaunch")).and_then(|v| v.as_bool()).unwrap_or(true),
            launch_cmd,
        });
    }
    
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
    let name = meta.get("name").and_then(|v| v.as_str()).unwrap_or("Profile").to_string();
    let slug = unique_slug(&name, None);
    
    let profile = Profile {
        id: format!("{}_{:x}", slug, now),
        name: name.clone(),
        emoji: meta.get("emoji").and_then(|v| v.as_str()).unwrap_or("🗂️").to_string(),
        description: meta.get("description").and_then(|v| v.as_str()).unwrap_or("").to_string(),
        created_at: now,
        close_others: meta.get("closeOthers").and_then(|v| v.as_bool()).unwrap_or(false),
        kill_others: meta.get("killOthers").and_then(|v| v.as_bool()).unwrap_or(false),
        pinned: false,
        windows,
    };
    
    write_profile(&profile, &slug);
    println!("{}", slug);
}

fn get_app_root_pid(mut pid: i64) -> i64 {
    let mut top_pid = pid;
    loop {
        let stat_path = format!("/proc/{}/stat", pid);
        if let Ok(stat) = std::fs::read_to_string(&stat_path) {
            let parts: Vec<&str> = stat.split_whitespace().collect();
            if parts.len() > 3 {
                let ppid = parts[3].parse::<i64>().unwrap_or(0);
                if ppid <= 1 { break; }
                
                if let Ok(exe_path) = std::fs::read_link(format!("/proc/{}/exe", ppid)) {
                    let exe_str = exe_path.to_string_lossy();
                    if exe_str.contains("systemd") || 
                       exe_str.ends_with("/bash") || 
                       exe_str.ends_with("/fish") || 
                       exe_str.ends_with("/zsh") || 
                       exe_str.ends_with("kitty") ||
                       exe_str.ends_with("gnome-terminal") ||
                       exe_str.ends_with("konsole") ||
                       exe_str.ends_with("Hyprland") ||
                       exe_str.ends_with("/quickshell") ||
                       exe_str.ends_with("/qs") {
                        break;
                    }
                } else {
                    break;
                }
                
                pid = ppid;
                top_pid = pid;
            } else {
                break;
            }
        } else {
            break;
        }
    }
    top_pid
}

fn cmd_watch(class: &str, target_ws_str: &str, width: i32, height: i32, x: i32, y: i32, is_floating: bool) {
    let target_ws: Value = serde_json::from_str(target_ws_str).unwrap_or(json!(target_ws_str));
    let timeout_iterations = 150; // 30 seconds
    
    for _ in 0..timeout_iterations {
        let clients = live_clients();
        let mut found = None;
        
        for c in &clients {
            let cls = c.get("class").and_then(|v| v.as_str()).unwrap_or("");
            if cls.eq_ignore_ascii_case(class) {
                let init_title = c.get("initialTitle").and_then(|v| v.as_str()).unwrap_or("").to_lowercase();
                if class.eq_ignore_ascii_case("discord") && init_title.contains("updater") { continue; }
                if class.eq_ignore_ascii_case("steam") && (init_title.contains("updating") || init_title == "sign in to steam") { continue; }
                
                found = Some(c.clone());
                break;
            }
        }
        
        if let Some(c) = found {
            let addr = c.get("address").and_then(|v| v.as_str()).unwrap_or("");
            let addr_sel = if addr.starts_with("0x") { format!("address:{}", addr) } else { format!("address:0x{}", addr) };
            
            let mut batch = Vec::new();
            let ws_param = get_dispatcher_workspace(&target_ws, &clients);
            
            batch.push(format!("dispatch hl.dsp.window.move({{ workspace = {}, window = \"{}\", follow = false }})", ws_param, addr_sel));
            
            let float_action = if is_floating { "set" } else { "disable" };
            batch.push(format!("dispatch hl.dsp.window.float({{ action = \"{}\", window = \"{}\" }})", float_action, addr_sel));
            
            if width > 0 && height > 0 {
                batch.push(format!("dispatch hl.dsp.window.resize({{ x = {}, y = {}, relative = false, window = \"{}\" }})", width, height, addr_sel));
                if is_floating {
                    batch.push(format!("dispatch hl.dsp.window.move({{ x = {}, y = {}, relative = false, window = \"{}\" }})", x, y, addr_sel));
                }
            }
            
            hyprctl(&["--batch", &batch.join(";")]);
            return;
        }
        thread::sleep(Duration::from_millis(200));
    }
    eprintln!("[error] Timeout waiting for window class '{}'", class);
}

fn cmd_restore(slug: &str) {
    let profile = match load_profile(slug) {
        Some(p) => p,
        None => return,
    };
    if profile.windows.is_empty() {
        println!("ok");
        return;
    }
    
    let mut errors = 0;
    let clients = live_clients();
    let mut live_by_class: HashMap<String, Vec<Value>> = HashMap::new();
    for c in clients.clone() {
        let cls = c.get("class").and_then(|v| v.as_str()).unwrap_or("").to_string();
        live_by_class.entry(cls).or_default().push(c);
    }
    
    let mut saved_by_class: HashMap<String, Vec<SavedWindow>> = HashMap::new();
    for sw in &profile.windows {
        saved_by_class.entry(sw.class.clone()).or_default().push(sw.clone());
    }
    
    let mut missing_to_launch = vec![];
    for (cls, saved_list) in &saved_by_class {
        let available_count = live_by_class.get(cls).map(|v| v.len()).unwrap_or(0);
        let needed_count = saved_list.len();
        let mut missing_count = needed_count.saturating_sub(available_count);
        
        if missing_count > 0 {
            for sw in saved_list {
                if sw.autolaunch && missing_count > 0 {
                    let mut launch_cmd = sw.launch_cmd.clone();
                    if launch_cmd.is_empty() {
                        let raw_cmd = if sw.initial_class.is_empty() { &sw.class } else { &sw.initial_class };
                        let mappings = HashMap::from([
                            ("brave-browser", "brave"),
                            ("Brave-browser", "brave"),
                            ("Navigator", "firefox"),
                            ("firefox-esr", "firefox"),
                            ("google-chrome", "google-chrome-stable"),
                            ("chrome", "google-chrome-stable"),
                            ("dev.zed.Zed", "zeditor"),
                        ]);
                        if let Some(mapped) = mappings.get(raw_cmd.as_str()) {
                            launch_cmd = mapped.to_string();
                        } else {
                            let cls_lower = raw_cmd.to_lowercase();
                            let guesses = vec![
                                raw_cmd.to_string(),
                                cls_lower.replace(" ", "-"),
                                cls_lower.replace(" ", ""),
                                cls_lower.split_whitespace().next().unwrap_or("").to_string(),
                            ];
                            for guess in guesses {
                                if !guess.is_empty() && which(&guess).is_ok() {
                                    launch_cmd = guess;
                                    break;
                                }
                            }
                            if launch_cmd.is_empty() { launch_cmd = raw_cmd.to_string(); }
                        }
                    }
                    if !launch_cmd.is_empty() {
                        missing_to_launch.push(launch_cmd);
                        missing_count -= 1;
                    }
                }
            }
        }
    }
    
    for cmd in &missing_to_launch {
        Command::new("sh")
            .arg("-c")
            .arg(cmd)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .ok();
    }
    
    if !missing_to_launch.is_empty() {
        for _ in 0..15 {
            thread::sleep(Duration::from_millis(200));
            let fresh = live_clients();
            live_by_class.clear();
            for c in fresh {
                let cls = c.get("class").and_then(|v| v.as_str()).unwrap_or("").to_string();
                live_by_class.entry(cls).or_default().push(c);
            }
            let mut all_found = true;
            for (cls, saved_list) in &saved_by_class {
                if live_by_class.get(cls).map(|v| v.len()).unwrap_or(0) < saved_list.len() {
                    all_found = false;
                    break;
                }
            }
            if all_found { break; }
        }
    }
    
    let mut assigned = HashSet::new();
    let mut pairs = vec![];
    
    for (cls, saved_list) in saved_by_class {
        let mut available = live_by_class.get(&cls).cloned().unwrap_or_default();
        available.retain(|lw| {
            let addr = lw.get("address").and_then(|v| v.as_str()).unwrap_or("");
            !assigned.contains(addr)
        });
        
        for sw in saved_list {
            if available.is_empty() {
                errors += 1;
                let exe = std::env::current_exe().unwrap_or_else(|_| std::path::PathBuf::from("workspace_profile_manager"));
                Command::new(exe)
                    .arg("watch")
                    .arg(&sw.class)
                    .arg(sw.workspace_id.to_string())
                    .arg(sw.width.to_string())
                    .arg(sw.height.to_string())
                    .arg(sw.x.to_string())
                    .arg(sw.y.to_string())
                    .arg(if sw.floating { "1" } else { "0" })
                    .spawn()
                    .ok();
                continue;
            }
            let saved_area = sw.width * sw.height;
            
            available.sort_by(|a, b| {
                let empty_ws = json!({});
                let a_ws = a.get("workspace").unwrap_or(&empty_ws);
                let b_ws = b.get("workspace").unwrap_or(&empty_ws);
                let a_ws_id = a_ws.get("id").and_then(|v| v.as_i64()).unwrap_or(0);
                let b_ws_id = b_ws.get("id").and_then(|v| v.as_i64()).unwrap_or(0);
                let a_ws_name = a_ws.get("name").and_then(|v| v.as_str()).unwrap_or("");
                let b_ws_name = b_ws.get("name").and_then(|v| v.as_str()).unwrap_or("");
                
                let target_special = is_special_workspace(&sw.workspace_id);
                
                let a_special = a_ws_id < 0;
                let b_special = b_ws_id < 0;
                
                let a_dist = if a_special != target_special { 100 } else {
                    if target_special {
                        if let Some(target_str) = sw.workspace_id.as_str() {
                            if a_ws_name == target_str { 0 } else { 10 }
                        } else {
                            (a_ws_id - sw.workspace_id.as_i64().unwrap_or(0)).abs()
                        }
                    } else {
                        (a_ws_id - sw.workspace_id.as_i64().unwrap_or(0)).abs()
                    }
                };
                
                let b_dist = if b_special != target_special { 100 } else {
                    if target_special {
                        if let Some(target_str) = sw.workspace_id.as_str() {
                            if b_ws_name == target_str { 0 } else { 10 }
                        } else {
                            (b_ws_id - sw.workspace_id.as_i64().unwrap_or(0)).abs()
                        }
                    } else {
                        (b_ws_id - sw.workspace_id.as_i64().unwrap_or(0)).abs()
                    }
                };
                
                let a_area = a.get("size").and_then(|arr| arr.get(0)).and_then(|v| v.as_i64()).unwrap_or(0) * a.get("size").and_then(|arr| arr.get(1)).and_then(|v| v.as_i64()).unwrap_or(0);
                let b_area = b.get("size").and_then(|arr| arr.get(0)).and_then(|v| v.as_i64()).unwrap_or(0) * b.get("size").and_then(|arr| arr.get(1)).and_then(|v| v.as_i64()).unwrap_or(0);
                let a_diff = (a_area - saved_area as i64).abs();
                let b_diff = (b_area - saved_area as i64).abs();
                
                a_dist.cmp(&b_dist).then(a_diff.cmp(&b_diff))
            });
            
            let best = available.remove(0);
            let addr = best.get("address").and_then(|v| v.as_str()).unwrap_or("").to_string();
            assigned.insert(addr.clone());
            pairs.push((sw, addr));
        }
    }
    
    let clients = live_clients();
    
    let mut batch_commands = Vec::new();
    for (sw, addr) in pairs {
        let addr_clean = if addr.starts_with("0x") { addr.clone() } else { format!("0x{}", addr) };
        let addr_sel = format!("address:{}", addr_clean);
        let ws_param = get_dispatcher_workspace(&sw.workspace_id, &clients);
        
        batch_commands.push(format!("dispatch hl.dsp.window.move({{ workspace = {}, window = \"{}\", follow = false }})", ws_param, addr_sel));
        
        let float_action = if sw.floating { "set" } else { "disable" };
        batch_commands.push(format!("dispatch hl.dsp.window.float({{ action = \"{}\", window = \"{}\" }})", float_action, addr_sel));
        
        batch_commands.push(format!("dispatch hl.dsp.window.resize({{ x = {}, y = {}, relative = false, window = \"{}\" }})", sw.width, sw.height, addr_sel));
        
        if sw.floating {
            batch_commands.push(format!("dispatch hl.dsp.window.move({{ x = {}, y = {}, relative = false, window = \"{}\" }})", sw.x, sw.y, addr_sel));
        }
    }
    
    if profile.close_others || profile.kill_others {
        let final_clients = live_clients();
        let assigned_clean: HashSet<String> = assigned.into_iter().map(|a| if a.starts_with("0x") { a } else { format!("0x{}", a) }).collect();
        for c in final_clients {
            if let Some(addr) = c.get("address").and_then(|v| v.as_str()) {
                let addr_clean = if addr.starts_with("0x") { addr.to_string() } else { format!("0x{}", addr) };
                if !assigned_clean.contains(&addr_clean) {
                    if let Some(ws_id) = c.get("workspace").and_then(|w| w.get("id")).and_then(|v| v.as_i64()) {
                        if ws_id != 0 {
                            if profile.kill_others {
                                if let Some(pid) = c.get("pid").and_then(|v| v.as_i64()) {
                                    let top_pid = get_app_root_pid(pid);
                                    let kill_cmd = format!(
                                        "kill -15 {0} 2>/dev/null; for p in $(pstree -p {0} | grep -o '([0-9]*)' | tr -d '()'); do kill -15 $p 2>/dev/null; done; sleep 0.1; kill -9 {0} 2>/dev/null; for p in $(pstree -p {0} | grep -o '([0-9]*)' | tr -d '()'); do kill -9 $p 2>/dev/null; done",
                                        top_pid
                                    );
                                    Command::new("sh").arg("-c").arg(&kill_cmd).spawn().ok();
                                }
                            } else {
                                batch_commands.push(format!("dispatch hl.dsp.window.close({{ window = \"address:{}\" }})", addr_clean));
                            }
                        }
                    }
                }
            }
        }
    }
    
    if !batch_commands.is_empty() {
        let batch_str = batch_commands.join(";");
        hyprctl(&["--batch", &batch_str]);
    }
    
    if errors == 0 { println!("ok"); } else { println!("partial:{}", errors); }
}

fn cmd_delete(slug: &str) {
    let path = profiles_dir().join(format!("{}.json", slug));
    if path.exists() {
        match fs::remove_file(path) {
            Ok(_) => println!("ok"),
            Err(e) => eprintln!("[error] Failed to delete file: {}", e),
        }
    } else {
        println!("ok"); // missing_ok=True equivalent
    }
}

fn cmd_update_window(slug: &str, idx_str: &str, autolaunch_str: &str, launch_cmd: &str) {
    if let Some(mut profile) = load_profile(slug) {
        if let Ok(idx) = idx_str.parse::<usize>() {
            if idx < profile.windows.len() {
                profile.windows[idx].autolaunch = ["true", "1", "yes"].contains(&autolaunch_str.to_lowercase().as_str());
                profile.windows[idx].launch_cmd = launch_cmd.trim().to_string();
                write_profile(&profile, slug);
                println!("ok");
                return;
            }
        }
    }
    std::process::exit(1);
}

fn cmd_update_profile(slug: &str, close_others_str: &str, kill_others_str: &str) {
    if let Some(mut profile) = load_profile(slug) {
        profile.close_others = ["true", "1", "yes"].contains(&close_others_str.to_lowercase().as_str());
        profile.kill_others = ["true", "1", "yes"].contains(&kill_others_str.to_lowercase().as_str());
        write_profile(&profile, slug);
        println!("ok");
    }
}

fn cmd_add_window(slug: &str, class_name: &str, workspace_str: &str, autolaunch_str: &str, launch_cmd: &str) {
    if let Some(mut profile) = load_profile(slug) {
        let ws = if let Ok(n) = workspace_str.parse::<i64>() { json!(n) } else { json!(workspace_str.trim()) };
        profile.windows.push(SavedWindow {
            class: class_name.trim().to_string(),
            initial_class: class_name.trim().to_string(),
            workspace_id: ws,
            x: 100, y: 100, width: 1200, height: 800,
            floating: false,
            autolaunch: ["true", "1", "yes"].contains(&autolaunch_str.to_lowercase().as_str()),
            launch_cmd: launch_cmd.trim().to_string(),
        });
        write_profile(&profile, slug);
        println!("ok");
    }
}

fn cmd_delete_window(slug: &str, idx_str: &str) {
    if let Some(mut profile) = load_profile(slug) {
        if let Ok(idx) = idx_str.parse::<usize>() {
            if idx < profile.windows.len() {
                profile.windows.remove(idx);
                write_profile(&profile, slug);
                println!("ok");
                return;
            }
        }
    }
    std::process::exit(1);
}

fn cmd_update_window_workspace(slug: &str, idx_str: &str, workspace_str: &str) {
    if let Some(mut profile) = load_profile(slug) {
        if let Ok(idx) = idx_str.parse::<usize>() {
            if idx < profile.windows.len() {
                let ws = if let Ok(n) = workspace_str.parse::<i64>() { json!(n) } else { json!(workspace_str.trim()) };
                profile.windows[idx].workspace_id = ws;
                write_profile(&profile, slug);
                println!("ok");
                return;
            }
        }
    }
    std::process::exit(1);
}

fn cmd_rename(old_slug: &str, new_name: &str) {
    if let Some(mut profile) = load_profile(old_slug) {
        profile.name = new_name.to_string();
        let new_slug = unique_slug(new_name, Some(old_slug));
        let path = profiles_dir().join(format!("{}.json", old_slug));
        fs::remove_file(path).ok();
        write_profile(&profile, &new_slug);
        println!("{}", new_slug);
    }
}

fn cmd_update_emoji(slug: &str, new_emoji: &str) {
    if let Some(mut profile) = load_profile(slug) {
        profile.emoji = new_emoji.to_string();
        write_profile(&profile, slug);
        println!("ok");
    }
}

fn cmd_toggle_pin(slug: &str) {
    if let Some(mut profile) = load_profile(slug) {
        profile.pinned = !profile.pinned;
        write_profile(&profile, slug);
        println!("ok");
    }
}

fn cmd_update_description(slug: &str, new_description: &str) {
    if let Some(mut profile) = load_profile(slug) {
        profile.description = new_description.trim().to_string();
        write_profile(&profile, slug);
        println!("ok");
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 { std::process::exit(1); }
    
    match args[1].as_str() {
        "list" => cmd_list(),
        "snapshot" if args.len() >= 3 => cmd_snapshot(&args[2]),
        "restore" if args.len() >= 3 => cmd_restore(&args[2]),
        "delete" if args.len() >= 3 => cmd_delete(&args[2]),
        "rename" if args.len() >= 4 => cmd_rename(&args[2], &args[3]),
        "update_emoji" if args.len() >= 4 => cmd_update_emoji(&args[2], &args[3]),
        "update_description" if args.len() >= 4 => cmd_update_description(&args[2], &args[3]),
        "update_window" if args.len() >= 6 => cmd_update_window(&args[2], &args[3], &args[4], &args[5]),
        "update_profile" if args.len() >= 5 => cmd_update_profile(&args[2], &args[3], &args[4]),
        "add_window" if args.len() >= 7 => cmd_add_window(&args[2], &args[3], &args[4], &args[5], &args[6]),
        "delete_window" if args.len() >= 4 => cmd_delete_window(&args[2], &args[3]),
        "update_window_workspace" if args.len() >= 5 => cmd_update_window_workspace(&args[2], &args[3], &args[4]),
        "toggle_pin" if args.len() >= 3 => cmd_toggle_pin(&args[2]),
        "watch" if args.len() >= 9 => {
            let width = args[4].parse().unwrap_or(0);
            let height = args[5].parse().unwrap_or(0);
            let x = args[6].parse().unwrap_or(0);
            let y = args[7].parse().unwrap_or(0);
            let floating = args[8] == "1";
            cmd_watch(&args[2], &args[3], width, height, x, y, floating);
        },
        _ => std::process::exit(1),
    }
}
