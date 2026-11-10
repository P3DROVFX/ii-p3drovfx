//! Drive health from UDisks2: NVMe controller SMART and ATA SMART, both
//! readable without root. Temperatures arrive in kelvin.

use serde_json::{json, Value};
use std::collections::HashMap;
use zbus::blocking::Connection;
use zbus::zvariant::{OwnedObjectPath, OwnedValue};

use crate::proto::{zbool, zf64, zi64, zstr, zstrs, zu64};

const DEST: &str = "org.freedesktop.UDisks2";

type Ifaces = HashMap<String, HashMap<String, OwnedValue>>;

pub fn available(conn: &Connection) -> bool {
    managed(conn).is_some()
}

fn managed(conn: &Connection) -> Option<HashMap<OwnedObjectPath, Ifaces>> {
    let msg = conn
        .call_method(Some(DEST), "/org/freedesktop/UDisks2", Some("org.freedesktop.DBus.ObjectManager"), "GetManagedObjects", &())
        .ok()?;
    msg.body().deserialize::<HashMap<OwnedObjectPath, Ifaces>>().ok()
}

fn g<'a>(m: &'a HashMap<String, OwnedValue>, k: &str) -> Option<&'a zbus::zvariant::Value<'static>> {
    m.get(k).map(|v| &**v)
}

fn kelvin_to_c(k: f64) -> Option<f64> {
    if k <= 0.0 { None } else { Some(((k - 273.15) * 10.0).round() / 10.0) }
}

pub fn scan(conn: &Connection) -> Vec<Value> {
    let Some(objects) = managed(conn) else { return Vec::new() };
    let mut drives = Vec::new();
    for (path, ifaces) in objects.iter() {
        let path = path.to_string();
        let Some(drive) = ifaces.get("org.freedesktop.UDisks2.Drive") else { continue };
        let nvme = ifaces.get("org.freedesktop.UDisks2.NVMe.Controller");
        let ata = ifaces.get("org.freedesktop.UDisks2.Drive.Ata");
        if nvme.is_none() && ata.is_none() {
            continue;
        }
        let id = g(drive, "Id").and_then(zstr).unwrap_or_else(|| path.rsplit('/').next().unwrap_or("").to_string());
        let mut d = json!({
            "id": id,
            "path": path,
            "model": g(drive, "Model").and_then(zstr).unwrap_or_default().trim().to_string(),
            "kind": if nvme.is_some() { "nvme" } else { "ata" },
            "size": g(drive, "Size").and_then(zu64),
            "tempC": null, "percentUsed": null, "availSpare": null, "spareThresh": null,
            "powerOnHours": null, "dataWritten": null, "dataRead": null, "mediaErrors": null,
            "unsafeShutdowns": null, "criticalWarning": [], "ataFailing": false, "ataFailingAttrs": 0,
            "selftest": null, "selftestPct": -1, "smartUpdated": null,
        });
        if let Some(n) = nvme {
            d["tempC"] = json!(g(n, "SmartTemperature").and_then(zf64).and_then(kelvin_to_c));
            d["powerOnHours"] = json!(g(n, "SmartPowerOnHours").and_then(zu64));
            d["criticalWarning"] = json!(g(n, "SmartCriticalWarning").map(zstrs).unwrap_or_default());
            d["selftest"] = json!(g(n, "SmartSelftestStatus").and_then(zstr));
            d["selftestPct"] = json!(g(n, "SmartSelftestPercentRemaining").and_then(zi64).unwrap_or(-1));
            d["smartUpdated"] = json!(g(n, "SmartUpdated").and_then(zu64).filter(|s| *s > 0).map(|s| s * 1000));
            if let Some(attrs) = nvme_attributes(conn, &path) {
                let a = |k: &str| g(&attrs, k);
                d["percentUsed"] = json!(a("percent_used").and_then(zu64));
                d["availSpare"] = json!(a("avail_spare").and_then(zu64));
                d["spareThresh"] = json!(a("spare_thresh").and_then(zu64));
                d["dataWritten"] = json!(a("total_data_written").and_then(zu64));
                d["dataRead"] = json!(a("total_data_read").and_then(zu64));
                d["mediaErrors"] = json!(a("media_errors").and_then(zu64));
                d["unsafeShutdowns"] = json!(a("unsafe_shutdowns").and_then(zu64));
            }
        }
        if let Some(a) = ata {
            let supported = g(a, "SmartSupported").and_then(zbool).unwrap_or(false);
            if !supported {
                continue;
            }
            d["tempC"] = json!(g(a, "SmartTemperature").and_then(zf64).and_then(kelvin_to_c));
            d["powerOnHours"] = json!(g(a, "SmartPowerOnSeconds").and_then(zu64).map(|s| s / 3600));
            d["ataFailing"] = json!(g(a, "SmartFailing").and_then(zbool).unwrap_or(false));
            d["ataFailingAttrs"] = json!(g(a, "SmartNumAttributesFailing").and_then(zi64).unwrap_or(0).max(0));
            d["selftest"] = json!(g(a, "SmartSelftestStatus").and_then(zstr));
            d["selftestPct"] = json!(g(a, "SmartSelftestPercentRemaining").and_then(zi64).unwrap_or(-1));
            d["smartUpdated"] = json!(g(a, "SmartUpdated").and_then(zu64).filter(|s| *s > 0).map(|s| s * 1000));
        }
        drives.push(d);
    }
    drives.sort_by(|a, b| a["path"].as_str().cmp(&b["path"].as_str()));
    drives
}

fn nvme_attributes(conn: &Connection, path: &str) -> Option<HashMap<String, OwnedValue>> {
    let opts: HashMap<&str, zbus::zvariant::Value> = HashMap::new();
    let msg = conn
        .call_method(Some(DEST), path, Some("org.freedesktop.UDisks2.NVMe.Controller"), "SmartGetAttributes", &(opts,))
        .ok()?;
    msg.body().deserialize::<HashMap<String, OwnedValue>>().ok()
}

/// What is wrong with a drive, as problem codes; empty when healthy.
pub fn problems(d: &Value) -> (Vec<&'static str>, &'static str) {
    let mut p = Vec::new();
    let mut critical = false;
    let n = |k: &str| d.get(k).and_then(|v| v.as_f64());
    if d.get("criticalWarning").and_then(|v| v.as_array()).is_some_and(|a| !a.is_empty()) {
        p.push("critical-warning");
        critical = true;
    }
    if let (Some(spare), Some(thresh)) = (n("availSpare"), n("spareThresh")) {
        if thresh > 0.0 && spare <= thresh {
            p.push("spare");
            critical = true;
        }
    }
    if n("mediaErrors").is_some_and(|m| m > 0.0) {
        p.push("media");
        critical = true;
    }
    if n("percentUsed").is_some_and(|u| u >= 90.0) {
        p.push("wear");
    }
    if d.get("ataFailing").and_then(|v| v.as_bool()).unwrap_or(false) || n("ataFailingAttrs").is_some_and(|x| x > 0.0) {
        p.push("ata-failing");
        critical = true;
    }
    if let Some(st) = d.get("selftest").and_then(|v| v.as_str()) {
        if st.starts_with("fatal") || st == "electrical" || st == "servo" || st == "read" || st == "handling"
            || st == "known_seg_fail" || st == "fatal_error" || st == "unknown_seg_fail"
        {
            p.push("selftest");
        }
    }
    if n("tempC").is_some_and(|t| t >= 70.0) {
        p.push("temperature");
    }
    let sev = if critical { "critical" } else { "warning" };
    (p, sev)
}

pub fn selftest(conn: &Connection, path: &str) -> Result<(), (String, String)> {
    let objects = managed(conn).ok_or_else(|| ("udisks".to_string(), "UDisks2 unavailable".to_string()))?;
    let ifaces = objects
        .iter()
        .find(|(p, _)| p.as_str() == path)
        .map(|(_, i)| i)
        .ok_or_else(|| ("no-drive".to_string(), path.to_string()))?;
    let iface = if ifaces.contains_key("org.freedesktop.UDisks2.NVMe.Controller") {
        "org.freedesktop.UDisks2.NVMe.Controller"
    } else {
        "org.freedesktop.UDisks2.Drive.Ata"
    };
    let proxy = zbus::blocking::Proxy::new(conn, DEST, path.to_string(), iface).map_err(|e| ("dbus".to_string(), e.to_string()))?;
    let opts: HashMap<&str, zbus::zvariant::Value> = HashMap::new();
    let flags = enumflags2::BitFlags::from(zbus::proxy::MethodFlags::AllowInteractiveAuth);
    proxy
        .call_with_flags::<_, _, ()>("SmartSelftestStart", flags, &("short", opts))
        .map(|_| ())
        .map_err(|e| {
            let t = e.to_string();
            (if t.contains("NotAuthorized") || t.contains("AccessDenied") { "denied" } else { "dbus" }.to_string(), t)
        })
}
