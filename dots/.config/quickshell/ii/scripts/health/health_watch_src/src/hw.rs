//! Hardware health beyond the drives: batteries (the laptop's wear, peripherals'
//! charge), the GPUs and their resets, memory (EDAC, OOM kills, swap), fans, and
//! the kernel's hardware complaints — machine checks, Wi-Fi/Bluetooth firmware
//! crashes, USB and PCIe errors. Everything from sysfs and this boot's kernel log
//! (plus systemd-oomd's kills); all readable as the user.

use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

fn read(p: &Path) -> Option<String> {
    std::fs::read_to_string(p).ok().map(|s| s.trim().to_string()).filter(|s| !s.is_empty())
}
fn num(p: &Path) -> Option<f64> {
    read(p)?.parse().ok()
}

// ── Batteries ───────────────────────────────────────────────────────────

/// Every power_supply of type Battery: the system's own (scope not "Device") with
/// wear, and peripherals (mice, keyboards, headsets) with their charge.
pub fn batteries() -> (Vec<Value>, Vec<Value>) {
    let mut own = Vec::new();
    let mut peripherals = Vec::new();
    let Ok(rd) = std::fs::read_dir("/sys/class/power_supply") else { return (own, peripherals) };
    let mut entries: Vec<PathBuf> = rd.flatten().map(|e| e.path()).collect();
    entries.sort();
    for p in entries {
        if read(&p.join("type")).as_deref() != Some("Battery") {
            continue;
        }
        let name = p.file_name().unwrap_or_default().to_string_lossy().into_owned();
        let capacity = num(&p.join("capacity"));
        let model = read(&p.join("model_name"));
        let status = read(&p.join("status"));
        if read(&p.join("scope")).as_deref() == Some("Device") {
            peripherals.push(json!({"name": name, "model": model, "capacity": capacity, "status": status}));
            continue;
        }
        // energy_* (µWh) or charge_* (µAh), whichever the driver gives.
        let (full, design) = match (num(&p.join("energy_full")), num(&p.join("energy_full_design"))) {
            (Some(f), Some(d)) => (Some(f), Some(d)),
            _ => (num(&p.join("charge_full")), num(&p.join("charge_full_design"))),
        };
        let health = match (full, design) {
            (Some(f), Some(d)) if d > 0.0 => Some((f / d * 1000.0).round() / 10.0),
            _ => None,
        };
        own.push(json!({
            "name": name,
            "model": model,
            "manufacturer": read(&p.join("manufacturer")),
            "technology": read(&p.join("technology")),
            "capacity": capacity,
            "status": status,
            "cycles": num(&p.join("cycle_count")).filter(|c| *c > 0.0),
            // Full charge against design, in %. Can read above 100 on a new pack.
            "healthPct": health,
        }));
    }
    (own, peripherals)
}

// ── GPUs ────────────────────────────────────────────────────────────────

fn vendor_name(id: &str) -> &'static str {
    match id {
        "0x8086" => "Intel",
        "0x1002" => "AMD",
        "0x10de" => "NVIDIA",
        "0x5143" => "Qualcomm",
        _ => "",
    }
}

/// One entry per DRM card: driver, PCI slot, vendor, and what the driver exposes
/// (temperature, busy %). `names` caches lspci's model name per slot.
pub fn gpus(names: &mut HashMap<String, String>) -> Vec<Value> {
    let mut out = Vec::new();
    let Ok(rd) = std::fs::read_dir("/sys/class/drm") else { return out };
    let mut cards: Vec<PathBuf> = rd
        .flatten()
        .map(|e| e.path())
        .filter(|p| {
            let n = p.file_name().unwrap_or_default().to_string_lossy();
            n.starts_with("card") && n[4..].chars().all(|c| c.is_ascii_digit())
        })
        .collect();
    cards.sort();
    for card in cards {
        let dev = card.join("device");
        let driver = std::fs::read_link(dev.join("driver")).ok().and_then(|p| p.file_name().map(|n| n.to_string_lossy().into_owned()));
        let slot = std::fs::read_link(&dev).ok().and_then(|p| p.file_name().map(|n| n.to_string_lossy().into_owned())).unwrap_or_default();
        let vendor = read(&dev.join("vendor")).unwrap_or_default();
        let model = if slot.is_empty() {
            String::new()
        } else {
            names
                .entry(slot.clone())
                .or_insert_with(|| {
                    // lspci -mm: `00:02.0 "VGA…" "Intel Corporation" "Arc Graphics 140V" …`
                    crate::proto::run("lspci", &["-mm", "-s", &slot])
                        .and_then(|o| o.split('"').nth(5).map(str::to_string))
                        .unwrap_or_default()
                })
                .clone()
        };
        let mut temp = None;
        if let Ok(hw) = std::fs::read_dir(dev.join("hwmon")) {
            for h in hw.flatten() {
                if let Some(t) = num(&h.path().join("temp1_input")) {
                    temp = Some((t / 100.0).round() / 10.0);
                    break;
                }
            }
        }
        out.push(json!({
            "card": card.file_name().unwrap_or_default().to_string_lossy(),
            "driver": driver,
            "slot": slot,
            "vendor": vendor_name(&vendor),
            "model": model,
            "tempC": temp,
            "busyPct": num(&dev.join("gpu_busy_percent")),
        }));
    }
    out
}

// ── Memory ──────────────────────────────────────────────────────────────

/// Corrected and uncorrected error counts summed over EDAC memory controllers;
/// None when there are none (no ECC memory, the common laptop case).
pub fn edac() -> Option<(u64, u64)> {
    let rd = std::fs::read_dir("/sys/devices/system/edac/mc").ok()?;
    let mut any = false;
    let (mut ce, mut ue) = (0u64, 0u64);
    for e in rd.flatten() {
        let p = e.path();
        if !p.file_name().unwrap_or_default().to_string_lossy().starts_with("mc") {
            continue;
        }
        any = true;
        ce += num(&p.join("ce_count")).unwrap_or(0.0) as u64;
        ue += num(&p.join("ue_count")).unwrap_or(0.0) as u64;
    }
    any.then_some((ce, ue))
}

/// (SwapTotal, SwapFree) bytes, and whether a zram device is in use.
pub fn swap() -> (u64, u64, bool) {
    let info = std::fs::read_to_string("/proc/meminfo").unwrap_or_default();
    let kb = |k: &str| info.lines().find_map(|l| l.strip_prefix(k)).and_then(|r| r.split_whitespace().next()?.parse::<u64>().ok()).unwrap_or(0) * 1024;
    let zram = std::fs::read_to_string("/proc/swaps").unwrap_or_default().lines().any(|l| l.starts_with("/dev/zram"));
    (kb("SwapTotal:"), kb("SwapFree:"), zram)
}

// ── Fans ────────────────────────────────────────────────────────────────

/// Fan inputs whose read failed with EIO: the firmware's own fan method is
/// broken there (Samsung's `FAN0._FST` aborts on every evaluation, and the
/// kernel logs three ACPI errors per read), so it is not asked again until
/// the daemon restarts.
static BROKEN_FANS: std::sync::Mutex<Vec<PathBuf>> = std::sync::Mutex::new(Vec::new());

pub fn fans() -> Vec<Value> {
    let mut out = Vec::new();
    let mut broken = BROKEN_FANS.lock().unwrap_or_else(|e| e.into_inner());
    let Ok(rd) = std::fs::read_dir("/sys/class/hwmon") else { return out };
    for h in rd.flatten() {
        let p = h.path();
        let chip = read(&p.join("name")).unwrap_or_default();
        let Ok(files) = std::fs::read_dir(&p) else { continue };
        for f in files.flatten() {
            let n = f.file_name().to_string_lossy().into_owned();
            let Some(idx) = n.strip_prefix("fan").and_then(|r| r.strip_suffix("_input")) else { continue };
            let path = f.path();
            if broken.contains(&path) {
                continue;
            }
            let rpm = match std::fs::read_to_string(&path) {
                Ok(s) => s.trim().parse::<f64>().ok(),
                Err(e) => {
                    if e.raw_os_error() == Some(5) {
                        broken.push(path.clone());
                    }
                    None
                }
            };
            let Some(rpm) = rpm else { continue };
            let label = read(&p.join(format!("fan{idx}_label"))).unwrap_or_else(|| format!("{chip} {idx}"));
            out.push(json!({"label": label, "rpm": rpm}));
        }
    }
    out
}

// ── Kernel complaints ───────────────────────────────────────────────────

/// What a kernel (or systemd-oomd) line is about, and a short detail for it:
/// ("gpu" | "mce" | "oom" | "radioFw" | "usb" | "aer" | "aerFatal" | "thermal", detail).
pub fn classify(message: &str, identifier: &str) -> Option<(&'static str, String)> {
    let m = message.to_lowercase();
    if identifier == "systemd-oomd" {
        // "Killed /user.slice/…/app-firefox@….service due to memory pressure …"
        if m.starts_with("killed ") {
            let what = message.split_whitespace().nth(1).unwrap_or("").rsplit('/').next().unwrap_or("").to_string();
            return Some(("oom", what));
        }
        return None;
    }
    if m.contains("out of memory: killed process") {
        // "Out of memory: Killed process 1234 (firefox) total-vm:…"
        let name = message.split_once('(').and_then(|(_, r)| r.split_once(')')).map(|(n, _)| n.to_string()).unwrap_or_default();
        return Some(("oom", name));
    }
    if m.contains("mce:") && m.contains("hardware error") || m.contains("machine check events logged") || m.starts_with("[hardware error]") {
        return Some(("mce", String::new()));
    }
    let gpu_driver = ["xe ", "i915 ", "amdgpu", "nouveau", "nvrm"].iter().find(|d| m.contains(*d));
    if let Some(d) = gpu_driver {
        let hang = m.contains("gpu hang") || m.contains("engine reset") || m.contains("gt reset") || m.contains("wedged")
            || m.contains("resetting chip") || (m.contains("ring") && m.contains("timeout")) || m.contains("gpu reset")
            || m.contains("gpu recovery") || m.contains("xid");
        if hang {
            return Some(("gpu", d.trim().to_string()));
        }
    }
    if (m.contains("iwlwifi") && (m.contains("microcode sw error") || m.contains("fw error") || m.contains("firmware crashed")))
        || (m.contains("ath1") && m.contains("firmware crashed"))
        || (m.contains("mt7") && m.contains("firmware") && m.contains("crash"))
        || (m.contains("bluetooth: hci") && m.contains("hardware error"))
    {
        let dev = message.split(|c: char| c == ' ' || c == ':').next().unwrap_or("").to_string();
        return Some(("radioFw", dev));
    }
    if m.starts_with("usb ") && (m.contains("device descriptor read") || m.contains("error -71") || m.contains("over-current")) {
        // "usb 3-2: device descriptor read/64, error -71" → the port, "3-2".
        let port = message.split_whitespace().nth(1).unwrap_or("").trim_end_matches(':').to_string();
        return Some(("usb", port));
    }
    if m.contains("aer:") {
        if m.contains("uncorrected") || m.contains("fatal") {
            return Some(("aerFatal", String::new()));
        }
        if m.contains("corrected") {
            return Some(("aer", String::new()));
        }
    }
    if m.contains("critical temperature reached") || m.contains("temperature above threshold") {
        return Some(("thermal", String::new()));
    }
    None
}

#[derive(Default, Clone)]
pub struct Events {
    /// kind → count this boot.
    pub counts: HashMap<String, u64>,
    /// kind → detail → count: which GPU driver, process, port, radio.
    pub details: HashMap<String, HashMap<String, u64>>,
}

impl Events {
    pub fn add(&mut self, kind: &str, detail: String) {
        *self.counts.entry(kind.to_string()).or_insert(0) += 1;
        if !detail.is_empty() {
            *self.details.entry(kind.to_string()).or_default().entry(detail).or_insert(0) += 1;
        }
    }
    pub fn count(&self, kind: &str) -> u64 {
        self.counts.get(kind).copied().unwrap_or(0)
    }
    pub fn json(&self) -> Value {
        json!({"counts": self.counts, "details": self.details})
    }
}

/// This boot's kernel and systemd-oomd lines at notice or worse, classified.
/// The kernel log of one boot is a few hundred lines, so it is read whole.
pub fn read_events() -> Events {
    let mut ev = Events::default();
    let out = crate::proto::run("journalctl", &[
        "-b", "-p", "5", "-o", "json", "--no-pager",
        "--output-fields=MESSAGE,SYSLOG_IDENTIFIER,_TRANSPORT",
        "_TRANSPORT=kernel", "+", "SYSLOG_IDENTIFIER=systemd-oomd",
    ])
    .unwrap_or_default();
    for line in out.lines() {
        let Ok(e) = serde_json::from_str::<Value>(line) else { continue };
        let msg = crate::proto::jtext(e.get("MESSAGE"));
        let ident = crate::proto::jtext(e.get("SYSLOG_IDENTIFIER"));
        if let Some((kind, detail)) = classify(&msg, &ident) {
            ev.add(kind, detail);
        }
    }
    ev
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kernel_lines() {
        let c = |m: &str| classify(m, "kernel").map(|(k, d)| (k.to_string(), d));
        assert_eq!(c("xe 0000:00:02.0: [drm] GT0: Engine reset: engine_class=rcs, logical_mask: 0x1, guc_id=2"), Some(("gpu".into(), "xe".into())));
        assert_eq!(c("i915 0000:00:02.0: [drm] GPU HANG: ecode 12:1:85dffffb"), Some(("gpu".into(), "i915".into())));
        assert_eq!(c("amdgpu 0000:03:00.0: amdgpu: ring gfx_0.0.0 timeout, signaled seq=1, emitted seq=3"), Some(("gpu".into(), "amdgpu".into())));
        assert_eq!(c("NVRM: Xid (PCI:0000:01:00): 79, pid=1234, GPU has fallen off the bus."), Some(("gpu".into(), "nvrm".into())));
        assert_eq!(c("Out of memory: Killed process 4242 (firefox) total-vm:123kB"), Some(("oom".into(), "firefox".into())));
        assert_eq!(c("mce: [Hardware Error]: Machine check events logged"), Some(("mce".into(), String::new())));
        assert_eq!(c("iwlwifi 0000:00:14.3: Microcode SW error detected. Restarting 0x0."), Some(("radioFw".into(), "iwlwifi".into())));
        assert_eq!(c("usb 3-2: device descriptor read/64, error -71"), Some(("usb".into(), "3-2".into())));
        assert_eq!(c("pcieport 0000:00:1c.0: AER: Corrected error message received from 0000:00:1c.0"), Some(("aer".into(), String::new())));
        assert_eq!(c("pcieport 0000:00:1c.0: AER: Uncorrected (Non-Fatal) error message received"), Some(("aerFatal".into(), String::new())));
        // The usual noise is none of these.
        assert_eq!(c("xe 0000:00:02.0: [drm] Using GuC firmware from xe/lnl_guc_70.bin version 70.36.0"), None);
        assert_eq!(c("usb 3-2: new high-speed USB device number 5 using xhci_hcd"), None);
    }

    #[test]
    fn oomd_kill() {
        let k = classify("Killed /user.slice/user-1000.slice/user@1000.service/app.slice/app-firefox@123.service due to memory pressure for /user.slice being 82.06% > 80.00% for > 20s with reclaim activity", "systemd-oomd");
        assert_eq!(k, Some(("oom", "app-firefox@123.service".to_string())));
        assert_eq!(classify("Considered 12 cgroups for killing", "systemd-oomd"), None);
    }

    #[test]
    fn this_machine_reads() {
        let (own, _) = batteries();
        for b in &own {
            if let Some(h) = b["healthPct"].as_f64() {
                assert!(h > 0.0 && h < 200.0);
            }
        }
        let _ = gpus(&mut HashMap::new());
        let _ = fans();
        let (total, free, _) = swap();
        assert!(free <= total);
    }
}
