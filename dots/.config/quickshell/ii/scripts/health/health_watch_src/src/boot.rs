//! How long this boot took, the way `systemd-analyze` splits it: firmware,
//! loader, kernel, initrd, userspace, and the user's own manager after login;
//! plus the slowest units from `systemd-analyze blame`. Read once per boot.

use serde_json::{json, Value};

const DEST: &str = "org.freedesktop.systemd1";
const PATH: &str = "/org/freedesktop/systemd1";
const MANAGER: &str = "org.freedesktop.systemd1.Manager";

fn prop(conn: &zbus::blocking::Connection, name: &str) -> Option<u64> {
    let proxy = zbus::blocking::Proxy::new(conn, DEST, PATH, MANAGER).ok()?;
    proxy.get_property::<u64>(name).ok()
}

/// Milliseconds per phase, or None while the boot has not finished (systemd's
/// FinishTimestamp is still 0). The timestamps are microseconds; firmware and
/// loader count back from the kernel's start, the rest forward from it.
pub fn times(sys: &zbus::blocking::Connection, user: Option<&zbus::blocking::Connection>) -> Option<Value> {
    let finish = prop(sys, "FinishTimestampMonotonic")?;
    if finish == 0 {
        return None;
    }
    let firmware = prop(sys, "FirmwareTimestampMonotonic").unwrap_or(0);
    let loader = prop(sys, "LoaderTimestampMonotonic").unwrap_or(0);
    let initrd = prop(sys, "InitRDTimestampMonotonic").unwrap_or(0);
    let userspace = prop(sys, "UserspaceTimestampMonotonic").unwrap_or(0);
    let kernel_end = if initrd > 0 { initrd } else { userspace };
    let ms = |us: u64| us / 1000;
    let user_ms = user.and_then(|c| {
        let start = prop(c, "UserspaceTimestampMonotonic")?;
        let end = prop(c, "FinishTimestampMonotonic")?;
        (end > start).then(|| ms(end - start))
    });
    let fw = ms(firmware.saturating_sub(loader));
    let ld = ms(loader);
    let total = fw + ld + ms(finish);
    Some(json!({
        "firmware": fw,
        "loader": ld,
        "kernel": ms(kernel_end),
        "initrd": if initrd > 0 { ms(userspace.saturating_sub(initrd)) } else { 0 },
        "userspace": ms(finish.saturating_sub(userspace)),
        "user": user_ms,
        "total": total,
    }))
}

/// "1min 2.345s" → 62345; "812ms" → 812; "148us" → 0. None if no part parses.
pub fn parse_span(text: &str) -> Option<u64> {
    let mut total = 0f64;
    let mut any = false;
    for part in text.split_whitespace() {
        let split = part.find(|c: char| !(c.is_ascii_digit() || c == '.'))?;
        let (num, unit) = part.split_at(split);
        let v: f64 = num.parse().ok()?;
        total += v * match unit {
            "h" => 3_600_000.0,
            "min" => 60_000.0,
            "s" => 1000.0,
            "ms" => 1.0,
            "us" | "µs" => 0.001,
            _ => return None,
        };
        any = true;
    }
    any.then_some(total.round() as u64)
}

/// The `limit` slowest units: [(unit, ms)], slowest first.
pub fn parse_blame(text: &str, limit: usize) -> Vec<(String, u64)> {
    let mut out = Vec::new();
    for line in text.lines() {
        let words: Vec<&str> = line.split_whitespace().collect();
        let Some((unit, span)) = words.split_last() else { continue };
        if let Some(ms) = parse_span(&span.join(" ")) {
            out.push((unit.to_string(), ms));
        }
        if out.len() >= limit {
            break;
        }
    }
    out
}

pub fn blame(limit: usize) -> Vec<(String, u64)> {
    parse_blame(&crate::proto::run("systemd-analyze", &["blame", "--no-pager"]).unwrap_or_default(), limit)
}

fn median(mut v: Vec<u64>) -> Option<u64> {
    if v.is_empty() {
        return None;
    }
    v.sort_unstable();
    Some(v[v.len() / 2])
}

/// A boot noticeably slower than usual: over 1.5× the median of the boots
/// before it and more than 5 s over it. Names the unit whose time grew most
/// against its own median. `boots` is oldest first, the newest is judged.
pub fn slow(boots: &[Value]) -> Option<Value> {
    let (last, before) = boots.split_last()?;
    let prev: Vec<&Value> = before.iter().rev().take(10).collect();
    if prev.len() < 3 {
        return None;
    }
    let total = last["total"].as_u64()?;
    let med = median(prev.iter().filter_map(|b| b["total"].as_u64()).collect())?;
    if (total as f64) <= med as f64 * 1.5 || total <= med + 5000 {
        return None;
    }
    let mut worst: Option<(String, u64, u64)> = None;
    for u in last["top"].as_array().into_iter().flatten() {
        let name = u["unit"].as_str().unwrap_or("");
        let ms = u["ms"].as_u64().unwrap_or(0);
        let usual = median(
            prev.iter()
                .filter_map(|b| b["top"].as_array()?.iter().find(|x| x["unit"] == name)?["ms"].as_u64())
                .collect(),
        )
        .unwrap_or(0);
        if worst.as_ref().is_none_or(|w| ms.saturating_sub(usual) > w.1.saturating_sub(w.2)) {
            worst = Some((name.to_string(), ms, usual));
        }
    }
    Some(json!({
        "total": total,
        "median": med,
        "unit": worst.as_ref().map(|w| w.0.clone()),
        "unitMs": worst.as_ref().map(|w| w.1),
        "unitMedian": worst.as_ref().map(|w| w.2),
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn spans() {
        assert_eq!(parse_span("11.051s"), Some(11051));
        assert_eq!(parse_span("812ms"), Some(812));
        assert_eq!(parse_span("1min 2.345s"), Some(62345));
        assert_eq!(parse_span("148us"), Some(0));
        assert_eq!(parse_span("logid.service"), None);
    }

    #[test]
    fn blame_lines() {
        let text = "11.051s logid.service\n 2.290s ipu-bridge-check-upstream.service\n1min 3s slow.service\n";
        assert_eq!(parse_blame(text, 10), vec![
            ("logid.service".to_string(), 11051),
            ("ipu-bridge-check-upstream.service".to_string(), 2290),
            ("slow.service".to_string(), 63000),
        ]);
        assert_eq!(parse_blame(text, 1).len(), 1);
    }

    #[test]
    fn slow_boot_named() {
        let b = |t: u64, unit_ms: u64| json!({"total": t, "top": [{"unit": "a.service", "ms": unit_ms}, {"unit": "b.service", "ms": 500}]});
        let mut boots = vec![b(17000, 1000), b(18000, 1100), b(17500, 900), b(17200, 1000)];
        assert!(slow(&boots).is_none());
        boots.push(b(30000, 12000));
        let s = slow(&boots).expect("slow");
        assert_eq!(s["unit"], "a.service");
        assert_eq!(s["median"], 17500);
        // Too few earlier boots to judge.
        assert!(slow(&boots[2..]).is_none());
    }
}
