//! The shell's own health: its Rust helpers built from sources older than the
//! ones on disk, and the shell process's memory. The shell is this helper's
//! parent, so its memory is read from /proc without looking for it.

use serde_json::{json, Value};
use std::path::Path;

/// Helpers whose binary was built from older sources (`rust-helpers.sh status`
/// says "stale"). One that was never built is not listed: most are optional.
/// `scripts` is the shell's scripts directory.
pub fn stale_helpers(scripts: &Path) -> Vec<Value> {
    let script = scripts.join("rust-helpers.sh");
    if !script.exists() {
        return Vec::new();
    }
    let out = crate::proto::run("bash", &[&script.to_string_lossy(), "status"]).unwrap_or_default();
    parse_status(&out)
}

pub fn parse_status(out: &str) -> Vec<Value> {
    out.lines()
        .filter_map(|l| {
            let mut w = l.split_whitespace();
            let name = w.next()?;
            let state = w.last()?;
            (state == "stale").then(|| json!({"name": name, "state": state}))
        })
        .collect()
}

/// The scripts directory of the running helper: <scripts>/health/health_watch.
pub fn scripts_dir() -> Option<std::path::PathBuf> {
    let exe = std::fs::read_link("/proc/self/exe").ok()?;
    Some(exe.parent()?.parent()?.to_path_buf())
}

/// The shell process (this helper's parent): (pid, resident bytes). None when the
/// parent is not Quickshell, as when the helper is run by hand.
pub fn shell_rss() -> Option<(u32, u64)> {
    let ppid = unsafe { libc::getppid() } as u32;
    let comm = std::fs::read_to_string(format!("/proc/{ppid}/comm")).ok()?;
    let comm = comm.trim();
    if !(comm.starts_with("quickshell") || comm == "qs" || comm.starts_with(".quickshell")) {
        return None;
    }
    let status = std::fs::read_to_string(format!("/proc/{ppid}/status")).ok()?;
    let kb = status
        .lines()
        .find_map(|l| l.strip_prefix("VmRSS:"))?
        .split_whitespace()
        .next()?
        .parse::<u64>()
        .ok()?;
    Some((ppid, kb * 1024))
}

/// QML error key → (times seen, last seen ms), filled by `follow_log`.
pub type LogErrors = std::sync::Arc<std::sync::Mutex<std::collections::HashMap<String, (u64, u64)>>>;

/// The part of a log line worth counting: a QML error, as "File.qml:12: TypeError: …".
/// Warnings in general are not: a session's log is mostly a tray's D-Bus chatter.
pub fn qml_error(line: &str) -> Option<String> {
    const KINDS: [&str; 7] = ["TypeError", "ReferenceError", "SyntaxError", "is not a type", "is not defined", "Cannot assign", "is not a function"];
    if !KINDS.iter().any(|k| line.contains(k)) {
        return None;
    }
    let at = line.find(".qml:")?;
    let start = line[..at].rfind('/').map(|i| i + 1).unwrap_or(0);
    Some(line[start..].trim().chars().take(200).collect())
}

/// Follows the shell's log (`qs log --pid <shell> -f`) on its own thread and
/// counts its QML errors into `sink`. Off by default: the follower is a ~50 MB
/// process for as long as the shell runs.
pub fn follow_log(pid: u32, sink: LogErrors) -> Option<std::process::Child> {
    use std::io::BufRead;
    let mut child = std::process::Command::new("qs")
        .args(["log", "--pid", &pid.to_string(), "-f"])
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()
        .ok()?;
    let out = child.stdout.take()?;
    std::thread::spawn(move || {
        for line in std::io::BufReader::new(out).lines() {
            let Ok(line) = line else { break };
            let Some(key) = qml_error(&line) else { continue };
            if let Ok(mut m) = sink.lock() {
                let e = m.entry(key).or_insert((0, 0));
                e.0 += 1;
                e.1 = crate::proto::now_ms();
            }
        }
    });
    Some(child)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn qml_errors_only() {
        let l = "\u{1b}[33m  WARN\u{1b}[0m scene: file:///home/u/.config/quickshell/ii/modules/x/Bar.qml:42: TypeError: Cannot read property 'width' of null";
        assert_eq!(qml_error(l).as_deref(), Some("Bar.qml:42: TypeError: Cannot read property 'width' of null"));
        assert!(qml_error("WARN quickshell.dbus.properties: Error updating property :1.104/StatusNotifierItem").is_none());
        assert!(qml_error("WARN qml: [Health] helper: something").is_none());
    }

    #[test]
    fn only_stale_helpers() {
        let out = "osk_autoshow ok\nhealth_watch stale\nsni_watcher missing\napp_stats unknown\n";
        let v = parse_status(out);
        assert_eq!(v.len(), 1);
        assert_eq!(v[0]["name"], "health_watch");
    }
}
