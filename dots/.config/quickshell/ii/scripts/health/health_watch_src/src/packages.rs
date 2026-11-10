//! Update chores: the package log, orphans, config files waiting to be merged,
//! a kernel replaced under the running one, and programs still mapping
//! libraries an update deleted.

use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::Path;
use std::sync::mpsc::Sender;

use crate::proto::{run, run_ok, which};
use crate::Ev;

pub const PACMAN_LOG: &str = "/var/log/pacman.log";
const DNF_LOG: &str = "/var/log/dnf.rpm.log";

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Manager {
    Pacman,
    Dnf,
    None,
}

impl Manager {
    pub fn detect() -> Manager {
        if which("pacman") && Path::new(PACMAN_LOG).exists() {
            Manager::Pacman
        } else if which("dnf") || which("rpm") {
            Manager::Dnf
        } else {
            Manager::None
        }
    }
    pub fn name(self) -> &'static str {
        match self {
            Manager::Pacman => "pacman",
            Manager::Dnf => "dnf",
            Manager::None => "none",
        }
    }
    pub fn log_path(self) -> Option<&'static str> {
        match self {
            Manager::Pacman => Some(PACMAN_LOG),
            Manager::Dnf => Some(DNF_LOG),
            Manager::None => None,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct PkgEvent {
    pub time: u64,
    pub name: String,
    pub from: String,
    pub to: String,
}

#[derive(Clone, Debug, Default)]
pub struct Transaction {
    pub time: u64,
    pub names: Vec<String>,
    pub count: usize,
}

/// Days since 1970-01-01 for a proleptic Gregorian date (Howard Hinnant's algorithm).
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

/// `2026-10-13T07:57:11+0200` (pacman) or `2026-10-13T07:57:11+0200`-style with a
/// colon in the offset (dnf). Returns Unix ms.
pub fn parse_ts(s: &str) -> Option<u64> {
    let b = s.as_bytes();
    if b.len() < 19 {
        return None;
    }
    let num = |a: usize, n: usize| s.get(a..a + n)?.parse::<i64>().ok();
    let (y, mo, d, h, mi, se) = (num(0, 4)?, num(5, 2)?, num(8, 2)?, num(11, 2)?, num(14, 2)?, num(17, 2)?);
    let mut offset = 0i64;
    let rest = &s[19..];
    let rest = rest.trim_start_matches(|c: char| c == '.' || c.is_ascii_digit());
    if let Some(sign) = rest.chars().next() {
        if sign == '+' || sign == '-' {
            let digits: String = rest[1..].chars().filter(|c| c.is_ascii_digit()).take(4).collect();
            if digits.len() == 4 {
                let oh: i64 = digits[..2].parse().ok()?;
                let om: i64 = digits[2..].parse().ok()?;
                offset = (oh * 60 + om) * 60 * if sign == '-' { -1 } else { 1 };
            }
        }
    }
    let secs = days_from_civil(y, mo, d) * 86400 + h * 3600 + mi * 60 + se - offset;
    if secs < 0 { None } else { Some(secs as u64 * 1000) }
}

/// Upgrades and installs from pacman.log at or after `since_ms`, plus transactions.
pub fn parse_pacman_log(text: &str, since_ms: u64) -> (Vec<PkgEvent>, Vec<Transaction>) {
    let mut events = Vec::new();
    let mut txs: Vec<Transaction> = Vec::new();
    let mut current: Option<Transaction> = None;
    for line in text.lines() {
        if !line.starts_with('[') {
            continue;
        }
        let Some(end) = line.find(']') else { continue };
        let Some(ts) = parse_ts(&line[1..end]) else { continue };
        if ts < since_ms {
            continue;
        }
        let rest = line[end + 1..].trim_start();
        let Some(body) = rest.strip_prefix("[ALPM] ") else { continue };
        if body.starts_with("transaction started") {
            current = Some(Transaction { time: ts, ..Default::default() });
            continue;
        }
        if body.starts_with("transaction completed") || body.starts_with("transaction interrupted") {
            if let Some(mut t) = current.take() {
                if t.count > 0 {
                    t.time = ts;
                    txs.push(t);
                }
            }
            continue;
        }
        let (kind, tail) = if let Some(t) = body.strip_prefix("upgraded ") {
            ("upgraded", t)
        } else if let Some(t) = body.strip_prefix("installed ") {
            ("installed", t)
        } else if let Some(t) = body.strip_prefix("downgraded ") {
            ("upgraded", t)
        } else if let Some(t) = body.strip_prefix("reinstalled ") {
            ("installed", t)
        } else {
            continue;
        };
        let Some((name, vers)) = tail.split_once(" (") else { continue };
        let vers = vers.trim_end_matches(')');
        let (from, to) = match (kind, vers.split_once(" -> ")) {
            ("upgraded", Some((a, b))) => (a.to_string(), b.to_string()),
            _ => (String::new(), vers.to_string()),
        };
        events.push(PkgEvent { time: ts, name: name.to_string(), from, to });
        let t = current.get_or_insert_with(|| Transaction { time: ts, ..Default::default() });
        t.count += 1;
        if t.names.len() < 30 {
            t.names.push(name.to_string());
        }
    }
    if let Some(t) = current {
        if t.count > 0 {
            txs.push(t);
        }
    }
    (events, txs)
}

/// dnf.rpm.log: `2026-10-13T07:57:11+0200 SUBDEBUG Upgrade: name-1.2-3.fc40.x86_64`.
pub fn parse_dnf_log(text: &str, since_ms: u64) -> (Vec<PkgEvent>, Vec<Transaction>) {
    let mut events = Vec::new();
    let mut by_time: HashMap<u64, Transaction> = HashMap::new();
    for line in text.lines() {
        let Some((ts_s, rest)) = line.split_once(' ') else { continue };
        let Some(ts) = parse_ts(ts_s) else { continue };
        if ts < since_ms {
            continue;
        }
        let Some(pos) = rest.find("Upgrade: ").or_else(|| rest.find("Install: ")) else { continue };
        let nevra = rest[pos..].split_once(": ").map(|x| x.1).unwrap_or("").trim();
        // name-version-release.arch: the name is everything before the second-last '-'.
        let parts: Vec<&str> = nevra.rsplitn(3, '-').collect();
        if parts.len() < 3 {
            continue;
        }
        let name = parts[2].to_string();
        let to = format!("{}-{}", parts[1], parts[0]);
        events.push(PkgEvent { time: ts, name: name.clone(), from: String::new(), to });
        let minute = ts / 60000;
        let t = by_time.entry(minute).or_insert_with(|| Transaction { time: ts, ..Default::default() });
        t.count += 1;
        if t.names.len() < 30 {
            t.names.push(name);
        }
    }
    let mut txs: Vec<Transaction> = by_time.into_values().collect();
    txs.sort_by_key(|t| t.time);
    (events, txs)
}

pub fn read_log(m: Manager, since_ms: u64) -> (Vec<PkgEvent>, Vec<Transaction>) {
    let Some(path) = m.log_path() else { return (Vec::new(), Vec::new()) };
    let text = std::fs::read(path).map(|b| String::from_utf8_lossy(&b).into_owned()).unwrap_or_default();
    match m {
        Manager::Pacman => parse_pacman_log(&text, since_ms),
        Manager::Dnf => parse_dnf_log(&text, since_ms),
        Manager::None => (Vec::new(), Vec::new()),
    }
}

/// Wakes the main loop whenever the package log is written.
pub fn watch_log(m: Manager, tx: Sender<Ev>) {
    let Some(path) = m.log_path() else { return };
    let Ok(cpath) = std::ffi::CString::new(path) else { return };
    std::thread::spawn(move || unsafe {
        let fd = libc::inotify_init1(libc::IN_CLOEXEC);
        if fd < 0 {
            return;
        }
        let wd = libc::inotify_add_watch(fd, cpath.as_ptr(), libc::IN_MODIFY | libc::IN_CLOSE_WRITE | libc::IN_MOVE_SELF | libc::IN_DELETE_SELF);
        if wd < 0 {
            libc::close(fd);
            return;
        }
        let mut buf = [0u8; 4096];
        loop {
            let n = libc::read(fd, buf.as_mut_ptr() as *mut libc::c_void, buf.len());
            if n <= 0 {
                if n < 0 && *libc::__errno_location() == libc::EINTR {
                    continue;
                }
                break;
            }
            if tx.send(Ev::PackageLog).is_err() {
                break;
            }
            // Log rotation: re-arm on the new file.
            let ev = &*(buf.as_ptr() as *const libc::inotify_event);
            if ev.mask & (libc::IN_MOVE_SELF | libc::IN_DELETE_SELF | libc::IN_IGNORED) != 0 {
                std::thread::sleep(std::time::Duration::from_secs(2));
                libc::inotify_add_watch(fd, cpath.as_ptr(), libc::IN_MODIFY | libc::IN_CLOSE_WRITE | libc::IN_MOVE_SELF | libc::IN_DELETE_SELF);
            }
        }
        libc::close(fd);
    });
}

pub fn orphans(m: Manager) -> Vec<String> {
    match m {
        Manager::Pacman => run("pacman", &["-Qdtq"]).unwrap_or_default().lines().map(String::from).filter(|s| !s.is_empty()).collect(),
        _ => Vec::new(),
    }
}

/// `.pacnew` / `.rpmnew` files under /etc, skipping what this user cannot read.
pub fn pending_configs(m: Manager) -> Vec<String> {
    let ext = match m {
        Manager::Pacman => ".pacnew",
        Manager::Dnf => ".rpmnew",
        Manager::None => return Vec::new(),
    };
    let mut found = Vec::new();
    let mut stack = vec![std::path::PathBuf::from("/etc")];
    let mut budget = 20000u32;
    while let Some(dir) = stack.pop() {
        let Ok(rd) = std::fs::read_dir(&dir) else { continue };
        for entry in rd.flatten() {
            if budget == 0 || found.len() >= 200 {
                return found;
            }
            budget -= 1;
            let Ok(ft) = entry.file_type() else { continue };
            let p = entry.path();
            if ft.is_dir() {
                stack.push(p);
            } else if p.to_string_lossy().ends_with(ext) {
                found.push(p.to_string_lossy().into_owned());
            }
        }
    }
    found.sort();
    found
}

pub fn kernel_release() -> String {
    unsafe {
        let mut u: libc::utsname = std::mem::zeroed();
        if libc::uname(&mut u) == 0 {
            return std::ffi::CStr::from_ptr(u.release.as_ptr()).to_string_lossy().into_owned();
        }
    }
    String::new()
}

pub fn kernel_state() -> Value {
    let running = kernel_release();
    let mut installed: Vec<String> = std::fs::read_dir("/usr/lib/modules")
        .map(|rd| {
            rd.flatten()
                .filter(|e| e.path().join("modules.dep").exists() || e.path().join("vmlinuz").exists())
                .map(|e| e.file_name().to_string_lossy().into_owned())
                .collect()
        })
        .unwrap_or_default();
    installed.sort();
    let present = !running.is_empty() && Path::new("/usr/lib/modules").join(&running).join("kernel").exists();
    json!({"running": running, "modulesPresent": present, "installed": installed})
}

/// Owner package of a path, cached by the caller.
pub fn owner(m: Manager, path: &str) -> Option<(String, String)> {
    match m {
        Manager::Pacman => {
            let (ok, out) = run_ok("pacman", &["-Qo", path])?;
            if !ok {
                return None;
            }
            // "/usr/lib/fprintd is owned by fprintd 1.94.5-1"
            let tail = out.trim().rsplit_once(" is owned by ")?.1;
            let (name, version) = tail.split_once(' ')?;
            Some((name.to_string(), version.to_string()))
        }
        Manager::Dnf => {
            let (ok, out) = run_ok("rpm", &["-qf", "--qf", "%{NAME} %{VERSION}-%{RELEASE}", path])?;
            if !ok {
                return None;
            }
            let (name, version) = out.trim().split_once(' ')?;
            Some((name.to_string(), version.to_string()))
        }
        Manager::None => None,
    }
}

/// This user's processes still mapping a shared library that has been deleted.
pub fn deleted_libs() -> Vec<Value> {
    let me = crate::proto::uid();
    let mut out = Vec::new();
    let Ok(rd) = std::fs::read_dir("/proc") else { return out };
    for entry in rd.flatten() {
        let name = entry.file_name();
        let Some(pid) = name.to_str().and_then(|s| s.parse::<u32>().ok()) else { continue };
        let Ok(md) = std::fs::metadata(entry.path()) else { continue };
        use std::os::unix::fs::MetadataExt;
        if md.uid() != me {
            continue;
        }
        let Ok(maps) = std::fs::read_to_string(entry.path().join("maps")) else { continue };
        let mut libs: Vec<String> = Vec::new();
        for line in maps.lines() {
            if !line.ends_with("(deleted)") {
                continue;
            }
            let Some(pos) = line.find('/') else { continue };
            let path = line[pos..].trim_end_matches("(deleted)").trim();
            if !(path.starts_with("/usr/") || path.starts_with("/lib") || path.starts_with("/opt/")) {
                continue;
            }
            if !path.contains(".so") {
                continue;
            }
            if !libs.iter().any(|l| l == path) {
                libs.push(path.to_string());
            }
        }
        if libs.is_empty() {
            continue;
        }
        let comm = std::fs::read_to_string(entry.path().join("comm")).unwrap_or_default().trim().to_string();
        let exe = std::fs::read_link(entry.path().join("exe"))
            .map(|p| p.to_string_lossy().trim_end_matches(" (deleted)").to_string())
            .unwrap_or_default();
        libs.truncate(20);
        out.push(json!({"pid": pid, "comm": comm, "exe": exe, "libs": libs}));
        if out.len() >= 100 {
            break;
        }
    }
    out
}

pub fn cleanup_sizes() -> Value {
    let mut b1 = 200_000u32;
    let journal = crate::proto::tree_size(Path::new("/var/log/journal"), &mut b1)
        + crate::proto::tree_size(Path::new("/run/log/journal"), &mut b1);
    let mut b2 = 50_000u32;
    let cache = crate::proto::tree_size(Path::new("/var/cache/pacman/pkg"), &mut b2);
    let mut b3 = 10_000u32;
    let cores = crate::proto::tree_size(Path::new("/var/lib/systemd/coredump"), &mut b3);
    let mut b4 = 100_000u32;
    let trash_dir = Path::new(&crate::proto::home_dir()).join(".local/share/Trash/files");
    let trash = crate::proto::tree_size(&trash_dir, &mut b4);
    json!({"journal": journal, "pacmanCache": cache, "coredumps": cores, "trash": trash})
}

/// `Oct 13 11:28:44`, local time.
pub fn format_local(ms: u64) -> String {
    unsafe {
        let t: libc::time_t = (ms / 1000) as libc::time_t;
        let mut tm: libc::tm = std::mem::zeroed();
        if libc::localtime_r(&t, &mut tm).is_null() {
            return String::new();
        }
        const MONTHS: [&str; 12] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        format!(
            "{} {:02} {:02}:{:02}:{:02}",
            MONTHS[(tm.tm_mon.clamp(0, 11)) as usize],
            tm.tm_mday,
            tm.tm_hour,
            tm.tm_min,
            tm.tm_sec
        )
    }
}

pub fn local_date(ms: u64) -> String {
    unsafe {
        let t: libc::time_t = (ms / 1000) as libc::time_t;
        let mut tm: libc::tm = std::mem::zeroed();
        if libc::localtime_r(&t, &mut tm).is_null() {
            return String::new();
        }
        format!("{:04}-{:02}-{:02}", tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timestamps() {
        // 2026-10-13T07:57:11+0200 = 05:57:11 UTC.
        let ms = parse_ts("2026-10-13T07:57:11+0200").unwrap();
        assert_eq!(ms, (days_from_civil(2026, 10, 13) * 86400 + 5 * 3600 + 57 * 60 + 11) as u64 * 1000);
        assert_eq!(parse_ts("1970-01-01T00:00:00+0000"), Some(0));
        assert_eq!(parse_ts("2026-10-13T07:57:11+02:00"), Some(ms));
    }

    #[test]
    fn pacman_log() {
        let log = "\
[2026-10-09T10:00:00+0200] [PACMAN] Running 'pacman -Syu'
[2026-10-09T10:00:05+0200] [ALPM] transaction started
[2026-10-09T10:00:06+0200] [ALPM] upgraded fprintd (1.94.4-1 -> 1.94.5-1)
[2026-10-09T10:00:07+0200] [ALPM] installed libfoo (2.0-1)
[2026-10-09T10:00:07+0200] [ALPM-SCRIPTLET] some output
[2026-10-09T10:00:09+0200] [ALPM] transaction completed
[2026-10-13T07:57:11+0200] [PACMAN] Running 'pacman -D -q --asexplicit'
[2026-10-13T08:00:00+0200] [ALPM] transaction started
[2026-10-13T08:00:01+0200] [ALPM] upgraded hyprland (0.56.2-3 -> 0.56.2-4)
[2026-10-13T08:00:02+0200] [ALPM] transaction completed
";
        let (ev, tx) = parse_pacman_log(log, 0);
        assert_eq!(ev.len(), 3);
        assert_eq!(ev[0].name, "fprintd");
        assert_eq!(ev[0].from, "1.94.4-1");
        assert_eq!(ev[0].to, "1.94.5-1");
        assert_eq!(ev[1].from, "");
        assert_eq!(ev[1].to, "2.0-1");
        assert_eq!(tx.len(), 2);
        assert_eq!(tx[0].count, 2);
        assert_eq!(tx[0].names, vec!["fprintd", "libfoo"]);
        assert_eq!(tx[1].names, vec!["hyprland"]);
        let since = parse_ts("2026-10-12T00:00:00+0200").unwrap();
        let (ev2, tx2) = parse_pacman_log(log, since);
        assert_eq!(ev2.len(), 1);
        assert_eq!(tx2.len(), 1);
    }

    #[test]
    fn real_pacman_log_parses() {
        // The machine's own log, when there is one: every upgraded line must parse.
        let Ok(text) = std::fs::read_to_string(PACMAN_LOG) else { return };
        let upgraded = text.lines().filter(|l| l.contains("[ALPM] upgraded ")).count();
        let mut bad = Vec::new();
        for line in text.lines().filter(|l| l.contains("[ALPM] upgraded ")) {
            let (ev, _) = parse_pacman_log(line, 0);
            if ev.len() != 1 || ev[0].from.is_empty() {
                bad.push(line.to_string());
            }
        }
        assert!(bad.is_empty(), "unparsed: {:?}", &bad[..bad.len().min(5)]);
        let (ev, _) = parse_pacman_log(&text, 0);
        let parsed = ev.iter().filter(|e| !e.from.is_empty()).count();
        assert!(parsed >= upgraded);
    }
}
