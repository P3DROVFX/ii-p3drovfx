//! The wire: one JSON object per line on stdout, and the small helpers every
//! source shares (clock, subprocesses, D-Bus value coercion).

use serde_json::{json, Value};
use std::io::Write;
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};
use zbus::zvariant::Value as ZValue;

/// Writes one message. A closed stdout means the shell went away: exit quietly.
pub fn emit(v: &Value) {
    let line = v.to_string();
    let stdout = std::io::stdout();
    let mut lock = stdout.lock();
    if writeln!(lock, "{line}").is_err() || lock.flush().is_err() {
        std::process::exit(0);
    }
}

pub fn log(level: &str, msg: impl AsRef<str>) {
    emit(&json!({"t": "log", "level": level, "msg": msg.as_ref()}));
}

pub fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// Runs a command to completion and returns stdout, or None when it could not
/// start. The exit code is ignored on purpose: `pacman -Qdtq` exits 1 when there
/// is nothing to list, `fwupdmgr get-updates` exits 2 when there is nothing to do.
pub fn run(cmd: &str, args: &[&str]) -> Option<String> {
    let out = Command::new(cmd)
        .args(args)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .env("LC_ALL", "C")
        .output()
        .ok()?;
    Some(String::from_utf8_lossy(&out.stdout).into_owned())
}

pub fn run_ok(cmd: &str, args: &[&str]) -> Option<(bool, String)> {
    let out = Command::new(cmd)
        .args(args)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .env("LC_ALL", "C")
        .output()
        .ok()?;
    Some((out.status.success(), String::from_utf8_lossy(&out.stdout).into_owned()))
}

pub fn which(cmd: &str) -> bool {
    std::env::var_os("PATH")
        .map(|paths| std::env::split_paths(&paths).any(|p| p.join(cmd).is_file()))
        .unwrap_or(false)
}

// ── D-Bus value coercion ──────────────────────────────────────────────────

pub fn zu64(v: &ZValue) -> Option<u64> {
    match v {
        ZValue::U8(x) => Some(*x as u64),
        ZValue::U16(x) => Some(*x as u64),
        ZValue::U32(x) => Some(*x as u64),
        ZValue::U64(x) => Some(*x),
        ZValue::I16(x) => Some((*x).max(0) as u64),
        ZValue::I32(x) => Some((*x).max(0) as u64),
        ZValue::I64(x) => Some((*x).max(0) as u64),
        ZValue::F64(x) => Some(x.max(0.0) as u64),
        ZValue::Value(inner) => zu64(inner),
        _ => None,
    }
}

pub fn zi64(v: &ZValue) -> Option<i64> {
    match v {
        ZValue::U8(x) => Some(*x as i64),
        ZValue::U16(x) => Some(*x as i64),
        ZValue::U32(x) => Some(*x as i64),
        ZValue::U64(x) => Some(*x as i64),
        ZValue::I16(x) => Some(*x as i64),
        ZValue::I32(x) => Some(*x as i64),
        ZValue::I64(x) => Some(*x),
        ZValue::F64(x) => Some(*x as i64),
        ZValue::Value(inner) => zi64(inner),
        _ => None,
    }
}

pub fn zf64(v: &ZValue) -> Option<f64> {
    match v {
        ZValue::F64(x) => Some(*x),
        ZValue::Value(inner) => zf64(inner),
        other => zi64(other).map(|x| x as f64),
    }
}

pub fn zstr(v: &ZValue) -> Option<String> {
    match v {
        ZValue::Str(s) => Some(s.to_string()),
        ZValue::ObjectPath(p) => Some(p.to_string()),
        ZValue::Value(inner) => zstr(inner),
        _ => None,
    }
}

pub fn zbool(v: &ZValue) -> Option<bool> {
    match v {
        ZValue::Bool(b) => Some(*b),
        ZValue::Value(inner) => zbool(inner),
        _ => None,
    }
}

pub fn zstrs(v: &ZValue) -> Vec<String> {
    match v {
        ZValue::Array(a) => a.iter().filter_map(zstr).collect(),
        ZValue::Value(inner) => zstrs(inner),
        _ => Vec::new(),
    }
}

/// Lossy text out of a journal JSON field: a string, or a byte array when the
/// message was not valid UTF-8.
pub fn jtext(v: Option<&Value>) -> String {
    match v {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Array(a)) => {
            let bytes: Vec<u8> = a.iter().filter_map(|b| b.as_u64().map(|x| x as u8)).collect();
            String::from_utf8_lossy(&bytes).into_owned()
        }
        _ => String::new(),
    }
}

pub fn jnum(v: Option<&Value>) -> Option<i64> {
    match v {
        Some(Value::String(s)) => s.trim().parse().ok(),
        Some(Value::Number(n)) => n.as_i64(),
        _ => None,
    }
}

pub fn home_dir() -> String {
    std::env::var("HOME").unwrap_or_else(|_| "/".into())
}

pub fn user_name() -> String {
    if let Ok(u) = std::env::var("USER") {
        if !u.is_empty() {
            return u;
        }
    }
    unsafe {
        let pw = libc::getpwuid(libc::getuid());
        if !pw.is_null() {
            let name = std::ffi::CStr::from_ptr((*pw).pw_name);
            return name.to_string_lossy().into_owned();
        }
    }
    String::new()
}

pub fn uid() -> u32 {
    unsafe { libc::getuid() }
}

pub fn boot_id() -> String {
    std::fs::read_to_string("/proc/sys/kernel/random/boot_id")
        .map(|s| s.trim().replace('-', ""))
        .unwrap_or_default()
}

/// Recursive size of a tree in bytes, not following symlinks, capped in entries
/// so a huge Trash cannot stall the loop.
pub fn tree_size(path: &std::path::Path, budget: &mut u32) -> u64 {
    let mut total = 0;
    let Ok(rd) = std::fs::read_dir(path) else { return 0 };
    for entry in rd.flatten() {
        if *budget == 0 {
            break;
        }
        *budget -= 1;
        let Ok(md) = entry.path().symlink_metadata() else { continue };
        if md.is_dir() {
            total += tree_size(&entry.path(), budget);
        } else if md.is_file() {
            total += md.len();
        }
    }
    total
}
