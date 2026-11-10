//! Crashes, from systemd-coredump's journal entries.
//!
//! The journal message carries everything the UI shows: the executable, the
//! signal and the first thread's stack trace. The dump file itself is only
//! checked for readability, never opened: nothing here can hand its bytes on.

use serde_json::{json, Value};
use std::collections::HashMap;

use crate::proto::{jnum, jtext};

pub const COREDUMP_MESSAGE_ID: &str = "fc2e22bc6ee647b6b90729ab34a250b1";
pub const WINDOW_MS: u64 = 7 * 24 * 3600 * 1000;

#[derive(Clone, Debug)]
pub struct CrashEvent {
    pub time: u64,
    pub exe: String,
    pub pid: i64,
    pub uid: i64,
    pub signal: i64,
    pub signal_name: String,
    pub unit: String,
    pub core_file: String,
    pub package_json: String,
    pub trace: Vec<(String, String)>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Frame {
    pub func: String,
    pub module: String,
}

pub fn is_coredump(entry: &Value) -> bool {
    jtext(entry.get("MESSAGE_ID")) == COREDUMP_MESSAGE_ID
}

pub fn parse_event(entry: &Value) -> Option<CrashEvent> {
    let get = |k: &str| jtext(entry.get(k));
    let exe = get("COREDUMP_EXE");
    if exe.is_empty() {
        return None;
    }
    // COREDUMP_TIMESTAMP is when it crashed; the entry's own timestamp is when
    // systemd-coredump finished writing, seconds later.
    let ts_us = jnum(entry.get("COREDUMP_TIMESTAMP"))
        .or_else(|| jnum(entry.get("__REALTIME_TIMESTAMP")))
        .unwrap_or(0);
    let signal = jnum(entry.get("COREDUMP_SIGNAL")).unwrap_or(0);
    let mut signal_name = get("COREDUMP_SIGNAL_NAME");
    if signal_name.is_empty() {
        signal_name = signal_name_of(signal).to_string();
    }
    let unit = {
        let u = get("COREDUMP_USER_UNIT");
        if u.is_empty() { get("COREDUMP_UNIT") } else { u }
    };
    let message = get("MESSAGE");
    Some(CrashEvent {
        time: (ts_us.max(0) as u64) / 1000,
        pid: jnum(entry.get("COREDUMP_PID")).unwrap_or(0),
        uid: jnum(entry.get("COREDUMP_UID")).unwrap_or(-1),
        signal,
        signal_name,
        unit,
        core_file: get("COREDUMP_FILENAME"),
        package_json: get("COREDUMP_PACKAGE_JSON"),
        trace: parse_trace(&message).into_iter().map(|f| (f.func, f.module)).collect(),
        exe,
    })
}

pub fn signal_name_of(sig: i64) -> &'static str {
    match sig {
        1 => "SIGHUP",
        2 => "SIGINT",
        3 => "SIGQUIT",
        4 => "SIGILL",
        5 => "SIGTRAP",
        6 => "SIGABRT",
        7 => "SIGBUS",
        8 => "SIGFPE",
        9 => "SIGKILL",
        11 => "SIGSEGV",
        13 => "SIGPIPE",
        15 => "SIGTERM",
        24 => "SIGXCPU",
        25 => "SIGXFSZ",
        31 => "SIGSYS",
        _ => "",
    }
}

/// The first thread's frames from a systemd-coredump message, at most 12.
///
/// ```text
/// Stack trace of thread 3018:
/// #0  0x00007f49e18aeb8b pthread_kill (libc.so.6 + 0xaeb8b)
/// #3  0x00007f49e1e98105 n/a (libglib-2.0.so.0 + 0x98105)
/// ```
pub fn parse_trace(message: &str) -> Vec<Frame> {
    let mut frames = Vec::new();
    let mut inside = false;
    for line in message.lines() {
        let t = line.trim();
        if t.starts_with("Stack trace of thread") {
            if inside {
                break;
            }
            inside = true;
            continue;
        }
        if !inside {
            continue;
        }
        if t.is_empty() {
            if !frames.is_empty() {
                break;
            }
            continue;
        }
        if !t.starts_with('#') {
            continue;
        }
        if let Some(f) = parse_frame(t) {
            frames.push(f);
            if frames.len() >= 12 {
                break;
            }
        }
    }
    frames
}

fn parse_frame(line: &str) -> Option<Frame> {
    // "#N  0xADDR func (module + 0xOFF)" — func may contain spaces in C++.
    let mut rest = line.trim_start_matches('#');
    rest = rest.trim_start_matches(|c: char| c.is_ascii_digit()).trim_start();
    if rest.starts_with("0x") {
        rest = rest.split_once(char::is_whitespace).map(|(_, r)| r.trim_start()).unwrap_or("");
    }
    let (func, module) = match rest.rfind(" (") {
        Some(p) if rest.ends_with(')') => {
            let inner = &rest[p + 2..rest.len() - 1];
            let module = inner.split(" + ").next().unwrap_or(inner).trim().to_string();
            (rest[..p].trim().to_string(), module)
        }
        _ => (rest.trim().to_string(), String::new()),
    };
    if func.is_empty() && module.is_empty() {
        return None;
    }
    Some(Frame { func, module })
}

/// First frame outside the runtime libraries every crash passes through.
pub fn own_frame(trace: &[(String, String)]) -> i64 {
    const RUNTIME: [&str; 10] = [
        "libc.so", "libstdc++", "libgcc", "ld-linux", "libglib-", "libgobject-", "libgio-", "libpthread",
        "libsystemd", "libm.so",
    ];
    for (i, (_, module)) in trace.iter().enumerate() {
        if module.is_empty() {
            continue;
        }
        if !RUNTIME.iter().any(|r| module.starts_with(r)) {
            return i as i64;
        }
    }
    -1
}

pub fn exe_name(exe: &str) -> String {
    exe.rsplit('/').next().unwrap_or(exe).to_string()
}

/// Readable without opening it: `access(R_OK)` only.
pub fn readable(path: &str) -> bool {
    if path.is_empty() {
        return false;
    }
    let Ok(c) = std::ffi::CString::new(path) else { return false };
    unsafe { libc::access(c.as_ptr(), libc::R_OK) == 0 }
}

pub struct PackageInfo {
    pub name: String,
    pub version: String,
}

pub struct Group<'a> {
    pub exe: String,
    pub events: Vec<&'a CrashEvent>,
}

/// Groups events by executable, newest event last within each group.
pub fn group(events: &[CrashEvent]) -> Vec<Group<'_>> {
    let mut map: HashMap<&str, Vec<&CrashEvent>> = HashMap::new();
    for e in events {
        map.entry(e.exe.as_str()).or_default().push(e);
    }
    let mut groups: Vec<Group> = map
        .into_iter()
        .map(|(exe, mut evs)| {
            evs.sort_by_key(|e| e.time);
            Group { exe: exe.to_string(), events: evs }
        })
        .collect();
    groups.sort_by_key(|g| std::cmp::Reverse(g.events.last().map(|e| e.time).unwrap_or(0)));
    groups
}

pub fn package_from_json(pj: &str) -> Option<PackageInfo> {
    let v: Value = serde_json::from_str(pj).ok()?;
    let name = v.get("name")?.as_str()?.to_string();
    let version = v.get("version").and_then(|x| x.as_str()).unwrap_or("").to_string();
    Some(PackageInfo { name, version })
}

pub fn trace_json(trace: &[(String, String)]) -> Value {
    Value::Array(trace.iter().map(|(f, m)| json!({"fn": f, "module": m})).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A real systemd-coredump MESSAGE from this machine (gnome-keyring-daemon, SIGABRT).
    const MESSAGE: &str = include_str!("testdata/coredump_message.txt");

    #[test]
    fn trace_first_thread_only() {
        let t = parse_trace(MESSAGE);
        assert_eq!(t.len(), 12, "capped at 12 frames of the first thread");
        assert_eq!(t[0], Frame { func: "pthread_kill".into(), module: "libc.so.6".into() });
        assert_eq!(t[3], Frame { func: "n/a".into(), module: "libglib-2.0.so.0".into() });
        assert_eq!(t[9].func, "g_variant_new_va");
        assert_eq!(t[11].module, "gnome-keyring-daemon");
        let pairs: Vec<(String, String)> = t.into_iter().map(|f| (f.func, f.module)).collect();
        assert_eq!(own_frame(&pairs), 11);
    }

    #[test]
    fn cpp_frame_with_spaces() {
        let f = parse_frame("#2  0x0000 std::vector<int, std::allocator<int> >::at(unsigned long) (libfoo.so.1 + 0x10)").unwrap();
        assert_eq!(f.module, "libfoo.so.1");
        assert!(f.func.starts_with("std::vector"));
        let g = parse_frame("#7  0x00005564 n/a (n/a + 0x0)").unwrap();
        assert_eq!(g.module, "n/a");
    }

    #[test]
    fn real_journal_entry() {
        let entry = serde_json::json!({
            "MESSAGE_ID": COREDUMP_MESSAGE_ID,
            "COREDUMP_EXE": "/usr/bin/gnome-keyring-daemon",
            "COREDUMP_SIGNAL": "6",
            "COREDUMP_SIGNAL_NAME": "SIGABRT",
            "COREDUMP_TIMESTAMP": "1791834841000000",
            "COREDUMP_UID": "1000",
            "COREDUMP_PID": "3018",
            "COREDUMP_UNIT": "user@1000.service",
            "COREDUMP_USER_UNIT": "gnome-keyring-daemon.service",
            "MESSAGE": MESSAGE
        });
        assert!(is_coredump(&entry));
        let e = parse_event(&entry).unwrap();
        assert_eq!(e.time, 1791834841000);
        assert_eq!(e.unit, "gnome-keyring-daemon.service");
        assert_eq!(e.signal_name, "SIGABRT");
        assert_eq!(e.trace.len(), 12);
        assert_eq!(exe_name(&e.exe), "gnome-keyring-daemon");
    }
}
