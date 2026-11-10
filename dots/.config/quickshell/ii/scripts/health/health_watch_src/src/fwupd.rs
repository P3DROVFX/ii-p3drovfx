//! Firmware: pending upgrades and the Host Security ID, from fwupd. Read only:
//! metadata is never refreshed here, fwupd-refresh.timer owns that.

use serde_json::{json, Value};

use crate::proto::{run, which};

pub fn available() -> bool {
    which("fwupdmgr")
}

/// The whole fwupd picture. Slow (a second or two), so it runs on a worker thread.
pub fn scan(conn: Option<&zbus::blocking::Connection>) -> Value {
    if !available() {
        return json!({"available": false, "hsi": "", "hsiLevel": null, "runtimeIssue": false, "attrs": [], "upgrades": []});
    }
    let hsi = conn.and_then(host_security_id).unwrap_or_default();
    // "HSI:1! (v2.1.8)" → "HSI:1!", level 1, runtime issue.
    let short = hsi.split_whitespace().next().unwrap_or("").to_string();
    let level = short
        .strip_prefix("HSI:")
        .and_then(|r| r.chars().next())
        .and_then(|c| c.to_digit(10));
    let runtime_issue = short.contains('!');
    json!({
        "available": true,
        "hsi": short,
        "hsiLevel": level,
        "runtimeIssue": runtime_issue,
        "attrs": security_attrs(),
        "upgrades": upgrades(),
    })
}

fn host_security_id(conn: &zbus::blocking::Connection) -> Option<String> {
    let msg = conn
        .call_method(
            Some("org.freedesktop.fwupd"),
            "/",
            Some("org.freedesktop.DBus.Properties"),
            "Get",
            &("org.freedesktop.fwupd", "HostSecurityId"),
        )
        .ok()?;
    let v: zbus::zvariant::OwnedValue = msg.body().deserialize().ok()?;
    crate::proto::zstr(&v)
}

fn security_attrs() -> Vec<Value> {
    let out = run("fwupdmgr", &["security", "--json", "--no-unreported-check"]).unwrap_or_default();
    parse_security(&out)
}

pub fn parse_security(out: &str) -> Vec<Value> {
    let Ok(v) = serde_json::from_str::<Value>(out.trim()) else { return Vec::new() };
    let Some(arr) = v.get("SecurityAttributes").and_then(|a| a.as_array()) else { return Vec::new() };
    arr.iter()
        .map(|a| {
            let flags: Vec<&str> = a.get("Flags").and_then(|f| f.as_array()).map(|f| f.iter().filter_map(|x| x.as_str()).collect()).unwrap_or_default();
            json!({
                "id": a.get("AppstreamId").and_then(|x| x.as_str()).unwrap_or(""),
                "name": a.get("Name").and_then(|x| x.as_str()).unwrap_or(""),
                "success": flags.contains(&"success"),
                "result": a.get("HsiResult").and_then(|x| x.as_str()).unwrap_or(""),
                // Runtime attributes carry no level: they only add the "!" suffix.
                "level": a.get("HsiLevel").and_then(|x| x.as_u64()).unwrap_or(0),
                "runtimeIssue": flags.contains(&"runtime-issue"),
                "flags": flags,
            })
        })
        .collect()
}

fn upgrades() -> Vec<Value> {
    let out = run("fwupdmgr", &["get-updates", "--json", "--no-unreported-check"]).unwrap_or_default();
    parse_upgrades(&out)
}

pub fn parse_upgrades(out: &str) -> Vec<Value> {
    let Ok(v) = serde_json::from_str::<Value>(out.trim()) else { return Vec::new() };
    let Some(devices) = v.get("Devices").and_then(|d| d.as_array()) else { return Vec::new() };
    let s = |v: &Value, k: &str| v.get(k).and_then(|x| x.as_str()).unwrap_or("").to_string();
    let mut list = Vec::new();
    for d in devices {
        let Some(release) = d.get("Releases").and_then(|r| r.as_array()).and_then(|r| r.first()) else { continue };
        let issues = release.get("Issues").and_then(|i| i.as_array()).is_some_and(|i| !i.is_empty());
        let security = issues
            || release.get("Flags").and_then(|f| f.as_array()).is_some_and(|f| f.iter().any(|x| x.as_str() == Some("is-security")))
            || s(release, "Urgency") == "critical";
        list.push(json!({
            "device": s(d, "DeviceId"),
            "name": s(d, "Name"),
            "vendor": s(d, "Vendor"),
            "version": s(d, "Version"),
            "newVersion": s(release, "Version"),
            "summary": s(release, "Summary"),
            "urgency": s(release, "Urgency"),
            "security": security,
        }));
    }
    list
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn security_shape() {
        let out = r#"{"SecurityAttributes":[{"AppstreamId":"org.fwupd.hsi.Kernel.Lockdown","HsiResult":"not-enabled","Name":"Linux kernel lockdown","Flags":["runtime-issue","action-config-os"]},{"AppstreamId":"org.fwupd.hsi.Spi.Ble","HsiLevel":1,"HsiResult":"enabled","Name":"SPI BIOS Lock Enable","Flags":["success"]}]}"#;
        let a = parse_security(out);
        assert_eq!(a.len(), 2);
        assert_eq!(a[0]["success"], false);
        assert_eq!(a[0]["runtimeIssue"], true);
        assert_eq!(a[1]["level"], 1);
    }

    #[test]
    fn upgrades_shape() {
        assert!(parse_upgrades("{\n  \"Devices\": [\n  ]\n}").is_empty());
        let out = r#"{"Devices":[{"DeviceId":"abc","Name":"System Firmware","Vendor":"Samsung","Version":"1.0","Releases":[{"Version":"1.1","Summary":"UEFI update","Urgency":"high","Issues":["CVE-2026-1"]}]}]}"#;
        let u = parse_upgrades(out);
        assert_eq!(u[0]["newVersion"], "1.1");
        assert_eq!(u[0]["security"], true);
    }
}
