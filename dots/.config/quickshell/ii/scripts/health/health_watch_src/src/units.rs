//! Failed units and restart loops on the system and user managers.
//!
//! systemd is asked once to `Subscribe()`, and from then on any unit changing
//! state wakes a debounced re-list. The re-list is cheap (one ListUnitsFiltered
//! plus a GetAll per failed unit) and always correct, which matters more here
//! than tracking each unit's transitions by hand.

use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::mpsc::Sender;
use zbus::blocking::{Connection, MessageIterator};
use zbus::zvariant::{OwnedValue, Value as ZValue};
use zbus::MatchRule;

use crate::proto::{zi64, zstr, zu64};
use crate::Ev;

const DEST: &str = "org.freedesktop.systemd1";
const PATH: &str = "/org/freedesktop/systemd1";
const MANAGER: &str = "org.freedesktop.systemd1.Manager";

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Scope {
    System,
    User,
}

impl Scope {
    pub fn name(self) -> &'static str {
        match self {
            Scope::System => "system",
            Scope::User => "user",
        }
    }
    pub fn parse(s: &str) -> Option<Scope> {
        match s {
            "system" => Some(Scope::System),
            "user" => Some(Scope::User),
            _ => None,
        }
    }
}

pub struct Manager {
    pub scope: Scope,
    pub conn: Connection,
}

impl Manager {
    /// A manager on a shared bus connection: one connection per bus for the whole
    /// helper, so a second source on the system bus costs no second executor.
    pub fn connect(scope: Scope, conn: Connection) -> Option<Manager> {
        let m = Manager { scope, conn };
        // A manager that cannot be reached is a source that does not exist here.
        m.call::<()>("Subscribe", &()).ok()?;
        Some(m)
    }

    fn call<R>(&self, method: &str, body: &(impl serde::Serialize + zbus::zvariant::DynamicType)) -> zbus::Result<R>
    where
        R: serde::de::DeserializeOwned + zbus::zvariant::Type,
    {
        let msg = self.conn.call_method(Some(DEST), PATH, Some(MANAGER), method, body)?;
        msg.body().deserialize::<R>()
    }

    fn get_all(&self, path: &str, iface: &str) -> HashMap<String, OwnedValue> {
        self.conn
            .call_method(Some(DEST), path, Some("org.freedesktop.DBus.Properties"), "GetAll", &(iface,))
            .ok()
            .and_then(|m| m.body().deserialize::<HashMap<String, OwnedValue>>().ok())
            .unwrap_or_default()
    }

    /// Units whose load, active or sub state matches any of `states`.
    fn list(&self, states: &[&str]) -> Vec<(String, String, String, String, String)> {
        type Row = (String, String, String, String, String, String, zbus::zvariant::OwnedObjectPath, u32, String, zbus::zvariant::OwnedObjectPath);
        let rows: Vec<Row> = self.call("ListUnitsFiltered", &(states.to_vec(),)).unwrap_or_default();
        rows.into_iter().map(|r| (r.0, r.1, r.3, r.4, r.6.to_string())).collect()
    }

    /// Watches this manager's unit changes and pings the main loop.
    pub fn spawn_watcher(&self, tx: Sender<Ev>) {
        let conn = self.conn.clone();
        let scope = self.scope;
        let rules = [
            MatchRule::builder()
                .msg_type(zbus::message::Type::Signal)
                .interface(MANAGER)
                .ok()
                .map(|b| b.build()),
            MatchRule::builder()
                .msg_type(zbus::message::Type::Signal)
                .interface("org.freedesktop.DBus.Properties")
                .and_then(|b| b.member("PropertiesChanged"))
                .and_then(|b| b.path_namespace("/org/freedesktop/systemd1/unit"))
                .and_then(|b| b.arg(0, "org.freedesktop.systemd1.Unit"))
                .ok()
                .map(|b| b.build()),
        ];
        for rule in rules.into_iter().flatten() {
            let conn = conn.clone();
            let tx = tx.clone();
            std::thread::spawn(move || {
                let Ok(iter) = MessageIterator::for_match_rule(rule, &conn, Some(256)) else { return };
                for msg in iter {
                    if msg.is_err() {
                        continue;
                    }
                    if tx.send(Ev::Units(scope)).is_err() {
                        return;
                    }
                }
            });
        }
    }

    /// Every failed unit and every unit caught restarting.
    pub fn scan(&self) -> ScanResult {
        let mut failed = Vec::new();
        for (name, description, active, sub, path) in self.list(&["failed"]) {
            failed.push(self.details(&name, &description, &active, &sub, &path));
        }
        let mut restarting = Vec::new();
        for (name, description, active, sub, path) in self.list(&["auto-restart", "activating"]) {
            if !name.ends_with(".service") {
                continue;
            }
            let svc = self.get_all(&path, "org.freedesktop.systemd1.Service");
            let n = svc.get("NRestarts").and_then(|v| zu64(v)).unwrap_or(0);
            if n == 0 {
                continue;
            }
            restarting.push(Restarting { name, description, n_restarts: n, active, sub });
        }
        ScanResult { failed, restarting }
    }

    fn details(&self, name: &str, description: &str, active: &str, sub: &str, path: &str) -> UnitInfo {
        let unit = self.get_all(path, "org.freedesktop.systemd1.Unit");
        let kind_iface = match name.rsplit('.').next().unwrap_or("") {
            "service" => "Service",
            "socket" => "Socket",
            "mount" => "Mount",
            "timer" => "Timer",
            "swap" => "Swap",
            "path" => "Path",
            "scope" => "Scope",
            "automount" => "Automount",
            _ => "",
        };
        let svc = if kind_iface.is_empty() {
            HashMap::new()
        } else {
            self.get_all(path, &format!("org.freedesktop.systemd1.{kind_iface}"))
        };
        let s = |m: &HashMap<String, OwnedValue>, k: &str| m.get(k).and_then(|v| zstr(v)).unwrap_or_default();
        let exec_path = svc.get("ExecStart").and_then(|v| first_exec_path(v)).unwrap_or_default();
        let exec_exists = exec_path.is_empty() || std::path::Path::new(&exec_path).exists();
        UnitInfo {
            name: name.to_string(),
            description: description.to_string(),
            active: active.to_string(),
            sub: sub.to_string(),
            result: s(&svc, "Result"),
            exec_code: svc.get("ExecMainCode").and_then(|v| zi64(v)).unwrap_or(0),
            exec_status: svc.get("ExecMainStatus").and_then(|v| zi64(v)).unwrap_or(0),
            n_restarts: svc.get("NRestarts").and_then(|v| zu64(v)).unwrap_or(0),
            fragment: s(&unit, "FragmentPath"),
            since_ms: unit.get("InactiveEnterTimestamp").and_then(|v| zu64(v)).unwrap_or(0) / 1000,
            exec_path,
            exec_exists,
        }
    }

    pub fn act(&self, verb: &str, unit: &str) -> Result<(), (String, String)> {
        let interactive = self.scope == Scope::System;
        let proxy = zbus::blocking::Proxy::new(&self.conn, DEST, PATH, MANAGER)
            .map_err(|e| ("dbus".to_string(), e.to_string()))?;
        let flags = if interactive {
            enumflags2::BitFlags::from(zbus::proxy::MethodFlags::AllowInteractiveAuth)
        } else {
            enumflags2::BitFlags::empty()
        };
        let res: zbus::Result<()> = match verb {
            "restart" => proxy
                .call_with_flags::<_, _, zbus::zvariant::OwnedObjectPath>("RestartUnit", flags, &(unit, "replace"))
                .map(|_| ()),
            "start" => proxy
                .call_with_flags::<_, _, zbus::zvariant::OwnedObjectPath>("StartUnit", flags, &(unit, "replace"))
                .map(|_| ()),
            "stop" => proxy
                .call_with_flags::<_, _, zbus::zvariant::OwnedObjectPath>("StopUnit", flags, &(unit, "replace"))
                .map(|_| ()),
            "resetFailed" => proxy.call_with_flags::<_, _, ()>("ResetFailedUnit", flags, &(unit,)).map(|_| ()),
            "disable" => proxy
                .call_with_flags::<_, _, Vec<(String, String, String)>>("DisableUnitFiles", flags, &(vec![unit], false))
                .and_then(|_| proxy.call_with_flags::<_, _, ()>("Reload", flags, &()).map(|_| ())),
            "enable" => proxy
                .call_with_flags::<_, _, (bool, Vec<(String, String, String)>)>("EnableUnitFiles", flags, &(vec![unit], false, false))
                .and_then(|_| proxy.call_with_flags::<_, _, ()>("Reload", flags, &()).map(|_| ())),
            _ => return Err(("verb".into(), format!("unknown verb {verb}"))),
        };
        res.map_err(|e| {
            let text = e.to_string();
            let code = if text.contains("AccessDenied") || text.contains("InteractiveAuthorizationRequired") || text.contains("not authorized") {
                "denied"
            } else if text.contains("NoSuchUnit") || text.contains("not found") {
                "no-unit"
            } else {
                "dbus"
            };
            (code.to_string(), text)
        })
    }
}

fn first_exec_path(v: &ZValue) -> Option<String> {
    let mut v = v;
    while let ZValue::Value(inner) = v {
        v = inner;
    }
    if let ZValue::Array(arr) = v {
        for item in arr.iter() {
            if let ZValue::Structure(s) = item {
                if let Some(first) = s.fields().first() {
                    return zstr(first);
                }
            }
        }
    }
    None
}

pub struct ScanResult {
    pub failed: Vec<UnitInfo>,
    pub restarting: Vec<Restarting>,
}

#[derive(Clone, Debug)]
pub struct UnitInfo {
    pub name: String,
    pub description: String,
    pub active: String,
    pub sub: String,
    pub result: String,
    pub exec_code: i64,
    pub exec_status: i64,
    pub n_restarts: u64,
    pub fragment: String,
    pub since_ms: u64,
    pub exec_path: String,
    pub exec_exists: bool,
}

pub struct Restarting {
    pub name: String,
    pub description: String,
    pub n_restarts: u64,
    pub active: String,
    pub sub: String,
}

pub fn exit_code_name(code: i64) -> &'static str {
    match code {
        1 => "exited",
        2 => "killed",
        3 => "dumped",
        _ => "",
    }
}

/// Why a unit failed, as a code the UI explains. Causes that say what to fix
/// (a missing program) win over causes that only say what systemd did about it
/// (gave up retrying).
pub fn classify(result: &str, exec_code: i64, exec_status: i64, exec_path: &str, exec_exists: bool) -> &'static str {
    let exited = exec_code == 1;
    if !exec_path.is_empty() && !exec_exists {
        return "exec-missing";
    }
    if exited {
        match exec_status {
            203 => return if exec_exists && !exec_path.is_empty() { "exec-perm" } else { "exec-missing" },
            126 => return "exec-perm",
            217 => return "user",
            226 => return "namespace",
            _ => {}
        }
    }
    match result {
        "oom-kill" => return "oom",
        "timeout" => return "timeout",
        "start-limit-hit" => return "start-limit",
        _ => {}
    }
    if exec_code == 3 || result == "core-dump" {
        return "core";
    }
    if exec_code == 2 || result == "signal" {
        return "signal";
    }
    if result == "dependency" || (result.is_empty() && exec_status == 0 && !exited) {
        return "dependency";
    }
    if exited && exec_status != 0 || result == "exit-code" {
        return "exit";
    }
    "unknown"
}

/// uwsm / app2unit launches: `app-<id>@<random>.service`, `app-<…>.scope`.
pub fn is_app_launch(unit: &str) -> bool {
    unit.starts_with("app-") && (unit.ends_with(".scope") || (unit.contains('@') && unit.ends_with(".service")))
}

/// The desktop id inside an app unit name, unescaped.
pub fn app_id(unit: &str) -> String {
    let body = unit.trim_start_matches("app-");
    let body = body.split('@').next().unwrap_or(body);
    let body = body.trim_end_matches(".scope").trim_end_matches(".service");
    unescape(body)
}

pub fn unescape(s: &str) -> String {
    let mut out: Vec<u8> = Vec::with_capacity(s.len());
    let b = s.as_bytes();
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'\\' && i + 3 < b.len() && b[i + 1] == b'x' {
            if let Some(byte) = s.get(i + 2..i + 4).and_then(|h| u8::from_str_radix(h, 16).ok()) {
                out.push(byte);
                i += 4;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

pub fn unit_data(scope: Scope, u: &UnitInfo, why: &str) -> Value {
    json!({
        "scope": scope.name(),
        "unit": u.name,
        "description": u.description,
        "result": u.result,
        "exitCode": exit_code_name(u.exec_code),
        "exitStatus": u.exec_status,
        "why": why,
        "execPath": u.exec_path,
        "execExists": u.exec_exists,
        "nRestarts": u.n_restarts,
        "fragmentPath": u.fragment,
        "activeState": u.active,
        "subState": u.sub,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zeron_is_exec_missing() {
        // Result=start-limit-hit, ExecMainCode=1 (exited), ExecMainStatus=203, binary gone.
        assert_eq!(classify("start-limit-hit", 1, 203, "/home/scrimas/.zeron/app/current/zeron", false), "exec-missing");
    }

    #[test]
    fn why_codes() {
        assert_eq!(classify("exit-code", 1, 203, "/usr/bin/true", true), "exec-perm");
        assert_eq!(classify("exit-code", 1, 217, "/usr/bin/true", true), "user");
        assert_eq!(classify("exit-code", 1, 226, "/usr/bin/true", true), "namespace");
        assert_eq!(classify("oom-kill", 2, 9, "/usr/bin/x", true), "oom");
        assert_eq!(classify("timeout", 2, 15, "/usr/bin/x", true), "timeout");
        assert_eq!(classify("start-limit-hit", 1, 1, "/usr/bin/false", true), "start-limit");
        assert_eq!(classify("core-dump", 3, 11, "/usr/bin/x", true), "core");
        assert_eq!(classify("signal", 2, 11, "/usr/bin/x", true), "signal");
        assert_eq!(classify("exit-code", 1, 1, "/usr/bin/false", true), "exit");
        assert_eq!(classify("dependency", 0, 0, "", true), "dependency");
        assert_eq!(classify("success", 0, 0, "", true), "unknown");
    }

    #[test]
    fn app_units() {
        let u = "app-open\\x2das\\x2droot@02e2ada0ce6043e2a51bf5b7afd3680a.service";
        assert!(is_app_launch(u));
        assert_eq!(app_id(u), "open-as-root");
        assert_eq!(app_id("app-com.anthropic.Claude.OpenInCode@d893caa679714b99be754ff75b728959.service"), "com.anthropic.Claude.OpenInCode");
        assert!(!is_app_launch("zeron.service"));
    }
}
