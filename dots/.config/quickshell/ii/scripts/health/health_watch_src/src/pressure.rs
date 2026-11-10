//! Pressure stall information, CPU throttling and temperature, time sync.

use serde_json::{json, Value};
use std::collections::VecDeque;

#[derive(Clone, Copy, Default, Debug, PartialEq)]
pub struct Psi {
    pub some10: f64,
    pub some60: f64,
    pub full10: f64,
}

/// `some avg10=0.00 avg60=0.03 avg300=0.01 total=…` / `full …`.
pub fn parse_psi(text: &str) -> Psi {
    let mut p = Psi::default();
    for line in text.lines() {
        let mut it = line.split_whitespace();
        let kind = it.next().unwrap_or("");
        for kv in it {
            let Some((k, v)) = kv.split_once('=') else { continue };
            let Ok(x) = v.parse::<f64>() else { continue };
            match (kind, k) {
                ("some", "avg10") => p.some10 = x,
                ("some", "avg60") => p.some60 = x,
                ("full", "avg10") => p.full10 = x,
                _ => {}
            }
        }
    }
    p
}

pub fn read_psi(resource: &str) -> Option<Psi> {
    std::fs::read_to_string(format!("/proc/pressure/{resource}")).ok().map(|t| parse_psi(&t))
}

pub fn psi_json(p: &Psi) -> Value {
    json!({"some10": p.some10, "some60": p.some60, "full10": p.full10})
}

/// Holds whether a resource has been above its threshold long enough to count.
#[derive(Default)]
pub struct Hold {
    pub above_since: Option<u64>,
}

impl Hold {
    /// True once `value > threshold` has held for `hold_ms`.
    pub fn update(&mut self, value: f64, threshold: f64, now: u64, hold_ms: u64) -> bool {
        if value > threshold {
            let since = *self.above_since.get_or_insert(now);
            now.saturating_sub(since) >= hold_ms
        } else {
            self.above_since = None;
            false
        }
    }
}

/// The three own processes using the most memory.
pub fn top_rss() -> Vec<Value> {
    use std::os::unix::fs::MetadataExt;
    let me = crate::proto::uid();
    let page = unsafe { libc::sysconf(libc::_SC_PAGESIZE) }.max(4096) as u64;
    let mut procs: Vec<(u64, u32, String)> = Vec::new();
    if let Ok(rd) = std::fs::read_dir("/proc") {
        for e in rd.flatten() {
            let Some(pid) = e.file_name().to_str().and_then(|s| s.parse::<u32>().ok()) else { continue };
            if std::fs::metadata(e.path()).map(|m| m.uid() != me).unwrap_or(true) {
                continue;
            }
            let Ok(statm) = std::fs::read_to_string(e.path().join("statm")) else { continue };
            let rss = statm.split_whitespace().nth(1).and_then(|x| x.parse::<u64>().ok()).unwrap_or(0) * page;
            let comm = std::fs::read_to_string(e.path().join("comm")).unwrap_or_default().trim().to_string();
            procs.push((rss, pid, comm));
        }
    }
    procs.sort_by_key(|p| std::cmp::Reverse(p.0));
    procs.into_iter().take(3).map(|(rss, pid, comm)| json!({"pid": pid, "comm": comm, "rssBytes": rss})).collect()
}

pub fn memory() -> Value {
    let text = std::fs::read_to_string("/proc/meminfo").unwrap_or_default();
    let field = |name: &str| {
        text.lines()
            .find(|l| l.starts_with(name))
            .and_then(|l| l.split_whitespace().nth(1))
            .and_then(|x| x.parse::<u64>().ok())
            .map(|kb| kb * 1024)
    };
    json!({"total": field("MemTotal:"), "available": field("MemAvailable:")})
}

// ── Thermals ────────────────────────────────────────────────────────────

pub fn throttle_supported() -> bool {
    std::path::Path::new("/sys/devices/system/cpu/cpu0/thermal_throttle").exists()
}

pub fn throttle_total() -> u64 {
    let mut total = 0;
    let Ok(rd) = std::fs::read_dir("/sys/devices/system/cpu") else { return 0 };
    for e in rd.flatten() {
        let name = e.file_name();
        let n = name.to_string_lossy();
        if !n.starts_with("cpu") || !n[3..].chars().all(|c| c.is_ascii_digit()) || n.len() == 3 {
            continue;
        }
        for f in ["core_throttle_count", "package_throttle_count"] {
            if let Ok(t) = std::fs::read_to_string(e.path().join("thermal_throttle").join(f)) {
                total += t.trim().parse::<u64>().unwrap_or(0);
            }
        }
    }
    total
}

/// Package temperature: coretemp "Package id 0", k10temp "Tctl", or the
/// x86_pkg_temp thermal zone.
pub fn cpu_temp() -> Option<f64> {
    if let Ok(rd) = std::fs::read_dir("/sys/class/hwmon") {
        for e in rd.flatten() {
            let name = std::fs::read_to_string(e.path().join("name")).unwrap_or_default();
            let want = match name.trim() {
                "coretemp" => "Package id 0",
                "k10temp" | "zenpower" => "Tctl",
                _ => continue,
            };
            for i in 1..64 {
                let label = std::fs::read_to_string(e.path().join(format!("temp{i}_label"))).unwrap_or_default();
                if label.trim() == want {
                    if let Ok(v) = std::fs::read_to_string(e.path().join(format!("temp{i}_input"))) {
                        return v.trim().parse::<f64>().ok().map(|m| (m / 100.0).round() / 10.0);
                    }
                }
            }
        }
    }
    if let Ok(rd) = std::fs::read_dir("/sys/class/thermal") {
        for e in rd.flatten() {
            if std::fs::read_to_string(e.path().join("type")).unwrap_or_default().trim() == "x86_pkg_temp" {
                if let Ok(v) = std::fs::read_to_string(e.path().join("temp")) {
                    return v.trim().parse::<f64>().ok().map(|m| (m / 100.0).round() / 10.0);
                }
            }
        }
    }
    None
}

#[derive(Default)]
pub struct Throttle {
    ring: VecDeque<(u64, u64)>,
}

impl Throttle {
    /// (total, events in the last 5 minutes)
    pub fn sample(&mut self, now: u64) -> (u64, u64) {
        let total = throttle_total();
        self.ring.push_back((now, total));
        while self.ring.front().is_some_and(|(t, _)| now.saturating_sub(*t) > 5 * 60 * 1000) {
            self.ring.pop_front();
        }
        let base = self.ring.front().map(|(_, v)| *v).unwrap_or(total);
        (total, total.saturating_sub(base))
    }
}

// ── Time sync ───────────────────────────────────────────────────────────

/// Whether the kernel clock is synchronised, read the way timedated does
/// (adjtimex without the unsync flag) but without waking timedated.
pub fn clock_synced() -> bool {
    unsafe {
        let mut tx: libc::timex = std::mem::zeroed();
        let state = libc::adjtimex(&mut tx);
        state != libc::TIME_ERROR && (tx.status & libc::STA_UNSYNC) == 0
    }
}

pub fn ntp_enabled(conn: &zbus::blocking::Connection) -> Option<bool> {
    let msg = conn
        .call_method(
            Some("org.freedesktop.timedate1"),
            "/org/freedesktop/timedate1",
            Some("org.freedesktop.DBus.Properties"),
            "Get",
            &("org.freedesktop.timedate1", "NTP"),
        )
        .ok()?;
    let v: zbus::zvariant::OwnedValue = msg.body().deserialize().ok()?;
    crate::proto::zbool(&v)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn psi_lines() {
        let t = "some avg10=0.00 avg60=0.03 avg300=0.01 total=15227016\nfull avg10=1.50 avg60=0.02 avg300=0.00 total=14776157\n";
        let p = parse_psi(t);
        assert_eq!(p, Psi { some10: 0.0, some60: 0.03, full10: 1.5 });
        // The cpu file has no meaningful "full" line on older kernels: missing is zero.
        let cpu = parse_psi("some avg10=12.34 avg60=5.00 avg300=1.00 total=1\n");
        assert_eq!(cpu.some10, 12.34);
        assert_eq!(cpu.full10, 0.0);
    }

    #[test]
    fn hold() {
        let mut h = Hold::default();
        assert!(!h.update(20.0, 10.0, 0, 60_000));
        assert!(!h.update(20.0, 10.0, 30_000, 60_000));
        assert!(h.update(20.0, 10.0, 60_000, 60_000));
        assert!(!h.update(5.0, 10.0, 61_000, 60_000));
        assert!(!h.update(20.0, 10.0, 62_000, 60_000));
    }
}
