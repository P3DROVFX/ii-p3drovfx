//! The journal, through `journalctl`: one bounded read of the current boot's
//! errors at start, then a child following from that cursor. journalctl already
//! knows which journal files this user may read, so access is whatever it says.

use serde_json::{json, Value};
use std::io::{BufRead, BufReader};
use std::process::{Child, Command, Stdio};
use std::sync::mpsc::Sender;

use crate::coredump::COREDUMP_MESSAGE_ID;
use crate::fingerprint;
use crate::proto::{jnum, jtext, run};
use crate::Ev;

/// Fields the live reader needs. The coredump ones ride along so a crash can be
/// grouped from the same stream; environment, open files and mappings never do.
pub const FIELDS: &str = "MESSAGE,MESSAGE_ID,PRIORITY,_SYSTEMD_UNIT,_SYSTEMD_USER_UNIT,SYSLOG_IDENTIFIER,_COMM,_TRANSPORT,_UID,\
COREDUMP_EXE,COREDUMP_COMM,COREDUMP_PID,COREDUMP_UID,COREDUMP_SIGNAL,COREDUMP_SIGNAL_NAME,COREDUMP_TIMESTAMP,\
COREDUMP_UNIT,COREDUMP_USER_UNIT,COREDUMP_FILENAME,COREDUMP_PACKAGE_JSON";

/// "full" when the system journal is readable, "user" for the own journal only.
pub fn access() -> &'static str {
    if !crate::proto::which("journalctl") {
        return "none";
    }
    // PID 1 only logs to the system journal: a line from it proves we can read that.
    match run("journalctl", &["-q", "-n", "1", "_PID=1", "-o", "cat", "--no-pager"]) {
        Some(out) if !out.trim().is_empty() => "full",
        Some(_) => "user",
        None => "none",
    }
}

pub fn parse_lines(out: &str) -> Vec<Value> {
    out.lines().filter_map(|l| serde_json::from_str::<Value>(l).ok()).collect()
}

/// The current boot's errors so far, and the cursor to follow from.
pub fn read_boot(boot: Option<&str>) -> (Vec<Value>, Option<String>) {
    let mut args = vec!["-q", "--no-pager", "-o", "json", "-p", "0..3", "--output-fields", FIELDS];
    let b = boot.map(|b| format!("--boot={b}"));
    match &b {
        Some(arg) => args.push(arg.as_str()),
        None => args.push("-b"),
    }
    let out = run("journalctl", &args).unwrap_or_default();
    let entries = parse_lines(&out);
    let cursor = entries.last().map(|e| jtext(e.get("__CURSOR"))).filter(|c| !c.is_empty());
    (entries, cursor)
}

/// Boot ids, oldest first, newest (current) last.
pub fn list_boots() -> Vec<String> {
    let out = run("journalctl", &["--list-boots", "-o", "json", "-q", "--no-pager"]).unwrap_or_default();
    let mut ids: Vec<(i64, String)> = match serde_json::from_str::<Value>(out.trim()) {
        Ok(Value::Array(a)) => a
            .iter()
            .filter_map(|b| Some((b.get("index")?.as_i64()?, b.get("boot_id")?.as_str()?.to_string())))
            .collect(),
        _ => Vec::new(),
    };
    ids.sort_by_key(|(i, _)| *i);
    ids.into_iter().map(|(_, id)| id).collect()
}

/// Every coredump record of the last 7 days, all boots.
pub fn read_crashes() -> Vec<Value> {
    let msg = format!("MESSAGE_ID={COREDUMP_MESSAGE_ID}");
    let out = run(
        "journalctl",
        &["-q", "--no-pager", "-o", "json", "--since", "-7d", "--output-fields", FIELDS, &msg],
    )
    .unwrap_or_default();
    parse_lines(&out)
}

pub struct Follower {
    child: Child,
}

impl Drop for Follower {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

/// Follows the journal from `cursor` (or from now) and sends every entry.
pub fn follow(cursor: Option<&str>, tx: Sender<Ev>) -> Option<Follower> {
    let mut cmd = Command::new("journalctl");
    cmd.args(["-q", "--no-pager", "-f", "-o", "json", "-p", "0..3", "--output-fields", FIELDS]);
    match cursor {
        Some(c) => {
            cmd.arg(format!("--after-cursor={c}"));
        }
        None => {
            cmd.args(["-b", "-n", "0"]);
        }
    }
    // The follower dies with the helper, however the helper dies.
    unsafe {
        use std::os::unix::process::CommandExt;
        cmd.pre_exec(|| {
            libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
            Ok(())
        });
    }
    let mut child = cmd.stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().ok()?;
    let stdout = child.stdout.take()?;
    std::thread::spawn(move || {
        let reader = BufReader::new(stdout);
        for line in reader.lines() {
            let Ok(line) = line else { break };
            if let Ok(v) = serde_json::from_str::<Value>(&line) {
                if tx.send(Ev::Journal(v)).is_err() {
                    return;
                }
            }
        }
        let _ = tx.send(Ev::JournalDied);
    });
    Some(Follower { child })
}

/// Formats an entry the way `journalctl -o short` would, minus the host.
pub fn short_line(e: &Value) -> String {
    let ts = jnum(e.get("__REALTIME_TIMESTAMP")).unwrap_or(0) / 1000;
    let src = fingerprint::source(e);
    let msg = jtext(e.get("MESSAGE"));
    let first = msg.lines().next().unwrap_or("");
    format!("{} {src}: {first}", crate::packages::format_local(ts as u64))
}

pub fn unit_log(user: bool, unit: &str, lines: u32) -> Vec<String> {
    let n = lines.clamp(1, 200).to_string();
    let mut args = vec!["-q", "--no-pager", "-o", "short", "-n", n.as_str()];
    if user {
        args.push("--user");
    }
    args.push("-u");
    args.push(unit);
    run("journalctl", &args).unwrap_or_default().lines().map(String::from).collect()
}

/// The latest lines of one fingerprint group, from this boot.
pub fn group_lines(fp: &str, lines: u32, home: &str) -> Vec<String> {
    let src = fp.split('|').next().unwrap_or("");
    let mut args: Vec<String> = ["-q", "--no-pager", "-o", "json", "-b", "-p", "0..3", "--output-fields", FIELDS]
        .iter()
        .map(|s| s.to_string())
        .collect();
    // Narrow the read by the source where journalctl can match it.
    if src == "kernel" {
        args.push("-k".into());
    } else if let Some(rest) = src.strip_prefix("user@") {
        if let Some((_, unit)) = rest.split_once('/') {
            if !unit.contains('#') {
                args.push(format!("_SYSTEMD_USER_UNIT={unit}"));
            }
        }
    } else if src.ends_with(".service") || src.ends_with(".socket") || src.ends_with(".mount") {
        if !src.contains('#') {
            args.push(format!("_SYSTEMD_UNIT={src}"));
        }
    } else if !src.is_empty() && !src.contains('#') {
        args.push(format!("SYSLOG_IDENTIFIER={src}"));
    }
    let argv: Vec<&str> = args.iter().map(|s| s.as_str()).collect();
    let out = run("journalctl", &argv).unwrap_or_default();
    let mut matched: Vec<String> = parse_lines(&out)
        .into_iter()
        .filter(|e| fingerprint::fingerprint(e, home).0 == fp)
        .map(|e| short_line(&e))
        .collect();
    let keep = lines.clamp(1, 100) as usize;
    if matched.len() > keep {
        matched.drain(..matched.len() - keep);
    }
    matched
}

pub struct Search {
    pub unit: String,
    pub identifier: String,
    pub grep: String,
    pub priority: i64,
    pub since_hours: i64,
    pub limit: i64,
}

pub fn search(q: &Search) -> Result<Vec<String>, (String, String)> {
    let since = format!("-{}h", q.since_hours.clamp(1, 168));
    let limit = q.limit.clamp(1, 100).to_string();
    let prio = format!("0..{}", q.priority.clamp(0, 7));
    let mut args: Vec<String> = vec!["-q".into(), "--no-pager".into(), "-o".into(), "short".into(), "--since".into(), since,
        "-n".into(), limit, "-p".into(), prio];
    if !q.unit.is_empty() {
        args.push("-u".into());
        args.push(q.unit.clone());
    }
    if !q.identifier.is_empty() {
        args.push("-t".into());
        args.push(q.identifier.clone());
    }
    if !q.grep.is_empty() {
        args.push("--grep".into());
        args.push(q.grep.clone());
        args.push("--case-sensitive=false".into());
    }
    let out = Command::new("journalctl")
        .args(&args)
        .stdin(Stdio::null())
        .env("LC_ALL", "C")
        .output()
        .map_err(|e| ("spawn".to_string(), e.to_string()))?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    if !out.status.success() && stdout.trim().is_empty() {
        let err = String::from_utf8_lossy(&out.stderr).trim().to_string();
        // "No entries" is an empty answer, not a failure.
        if err.is_empty() || err.contains("No entries") {
            return Ok(Vec::new());
        }
        return Err(("journalctl".into(), err));
    }
    Ok(stdout.lines().map(String::from).collect())
}

/// The newest crash of `exe`: its message and the harmless fields. No
/// environment, command line, working directory, open files or mappings.
pub fn crash_info(exe: &str) -> Option<Value> {
    let m = format!("MESSAGE_ID={COREDUMP_MESSAGE_ID}");
    let e = format!("COREDUMP_EXE={exe}");
    let out = run(
        "journalctl",
        &["-q", "--no-pager", "-o", "json", "-n", "1", "--since", "-30d", "--output-fields", FIELDS, &m, &e],
    )?;
    let entry = parse_lines(&out).pop()?;
    let mut fields = serde_json::Map::new();
    for key in [
        "COREDUMP_EXE", "COREDUMP_COMM", "COREDUMP_PID", "COREDUMP_UID", "COREDUMP_SIGNAL", "COREDUMP_SIGNAL_NAME",
        "COREDUMP_TIMESTAMP", "COREDUMP_UNIT", "COREDUMP_USER_UNIT", "COREDUMP_FILENAME", "COREDUMP_PACKAGE_JSON",
    ] {
        let v = jtext(entry.get(key));
        if !v.is_empty() {
            fields.insert(key.to_string(), Value::String(v));
        }
    }
    Some(json!({"message": jtext(entry.get("MESSAGE")), "fields": Value::Object(fields)}))
}
