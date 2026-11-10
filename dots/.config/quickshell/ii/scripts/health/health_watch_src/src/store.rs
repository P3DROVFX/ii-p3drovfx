//! What survives a restart: fingerprints and their boots, mutes, dismissals,
//! what was already alerted this boot, and the daily summaries.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

#[derive(Serialize, Deserialize, Default, Clone, Debug)]
pub struct FpRec {
    #[serde(default)]
    pub boots: Vec<String>,
    #[serde(default, rename = "firstSeen")]
    pub first_seen: u64,
    #[serde(default, rename = "lastSeen")]
    pub last_seen: u64,
    #[serde(default)]
    pub muted: bool,
    #[serde(default)]
    pub known: bool,
}

#[derive(Serialize, Deserialize, Default, Debug)]
pub struct State {
    #[serde(default)]
    pub version: u32,
    #[serde(default)]
    pub baseline: bool,
    #[serde(default)]
    pub fingerprints: HashMap<String, FpRec>,
    #[serde(default, rename = "mutedPrograms")]
    pub muted_programs: Vec<String>,
    #[serde(default)]
    pub dismissed: HashMap<String, u64>,
    #[serde(default)]
    pub alerted: HashMap<String, String>,
    #[serde(default, rename = "journalCursor")]
    pub journal_cursor: Option<String>,
    /// Finding id → until when it stays quiet.
    #[serde(default)]
    pub snoozed: HashMap<String, Snooze>,
    /// Findings that went away, newest last (see `remember_resolved`).
    #[serde(default)]
    pub resolved: Vec<serde_json::Value>,
    /// One row per boot: its phases and slowest units, oldest first.
    #[serde(default)]
    pub boots: Vec<serde_json::Value>,
}

#[derive(Serialize, Deserialize, Default, Clone, Debug, PartialEq)]
pub struct Snooze {
    /// Epoch ms; 0 with `boot` set means "until the next boot".
    #[serde(default)]
    pub until: u64,
    /// The boot id it was snoozed in, for "until restart".
    #[serde(default)]
    pub boot: Option<String>,
}

impl Snooze {
    pub fn active(&self, now: u64, boot: &str) -> bool {
        match &self.boot {
            Some(b) => b == boot,
            None => now < self.until,
        }
    }
}

/// How many resolved findings, and for how long, are remembered.
pub const RESOLVED_KEEP: usize = 50;
pub const RESOLVED_DAYS_MS: u64 = 7 * 86_400_000;
/// How many boots are remembered.
pub const BOOTS_KEEP: usize = 30;

#[derive(Serialize, Deserialize, Default, Clone, Debug, PartialEq)]
pub struct Day {
    pub date: String,
    #[serde(default)]
    pub failed: u64,
    #[serde(default)]
    pub crashes: u64,
    #[serde(default, rename = "newErrors")]
    pub new_errors: u64,
    #[serde(default, rename = "diskPct")]
    pub disk_pct: f64,
    #[serde(default, rename = "psiMemPeak")]
    pub psi_mem_peak: f64,
    /// This day's boot, start to finish, in ms; 0 when it did not boot that day.
    #[serde(default, rename = "bootMs")]
    pub boot_ms: u64,
    /// The laptop battery's full charge against its design, %; 0 when unknown.
    #[serde(default, rename = "batteryHealthPct")]
    pub battery_health_pct: f64,
    /// The hottest the CPU read that day, °C.
    #[serde(default, rename = "cpuTempPeak")]
    pub cpu_temp_peak: f64,
    /// GPU resets and OOM kills: the most counted in one boot that day.
    #[serde(default, rename = "gpuResets")]
    pub gpu_resets: u64,
    #[serde(default, rename = "oomKills")]
    pub oom_kills: u64,
}

pub struct Store {
    dir: PathBuf,
    pub state: State,
    pub days: Vec<Day>,
    pub dirty: bool,
}

fn read_json<T: for<'d> Deserialize<'d> + Default>(path: &Path) -> T {
    std::fs::read(path).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}

fn write_atomic(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, bytes)?;
    std::fs::rename(&tmp, path)
}

impl Store {
    pub fn open(dir: &Path) -> Store {
        let _ = std::fs::create_dir_all(dir);
        let state: State = read_json(&dir.join("state.json"));
        let days: Vec<Day> = read_json(&dir.join("history.json"));
        Store { dir: dir.to_path_buf(), state, days, dirty: false }
    }

    pub fn save(&mut self) {
        if !self.dirty {
            return;
        }
        self.state.version = 1;
        if let Ok(b) = serde_json::to_vec(&self.state) {
            let _ = write_atomic(&self.dir.join("state.json"), &b);
        }
        if let Ok(b) = serde_json::to_vec(&self.days) {
            let _ = write_atomic(&self.dir.join("history.json"), &b);
        }
        self.dirty = false;
    }

    /// Today's summary row, created when the day rolls. Returns true on a roll.
    pub fn today(&mut self, date: &str, keep: usize) -> (bool, &mut Day) {
        let rolled = self.days.last().map(|d| d.date != date).unwrap_or(true);
        if rolled {
            self.days.push(Day { date: date.to_string(), ..Default::default() });
            if self.days.len() > keep.max(1) {
                let excess = self.days.len() - keep.max(1);
                self.days.drain(..excess);
            }
            self.dirty = true;
        }
        (rolled, self.days.last_mut().unwrap())
    }

    /// Forgets every mute, known group and dismissal; the baseline is rebuilt.
    pub fn reset_noise(&mut self) {
        self.state.fingerprints.clear();
        self.state.muted_programs.clear();
        self.state.dismissed.clear();
        self.state.baseline = false;
        self.dirty = true;
    }

    /// Keeps the fingerprint table bounded: drops groups unseen for 60 days that
    /// carry no user decision. Also lets old resolved entries go.
    pub fn prune(&mut self, now: u64) {
        let cutoff = now.saturating_sub(60 * 86_400_000);
        let before = self.state.fingerprints.len();
        self.state.fingerprints.retain(|_, r| r.muted || r.last_seen >= cutoff);
        if self.state.fingerprints.len() != before {
            self.dirty = true;
        }
        let before = self.state.resolved.len();
        let keep_after = now.saturating_sub(RESOLVED_DAYS_MS);
        self.state.resolved.retain(|r| r["resolvedAt"].as_u64().unwrap_or(0) >= keep_after);
        if self.state.resolved.len() != before {
            self.dirty = true;
        }
    }

    /// Adds a finding that went away to the recently-fixed list.
    pub fn remember_resolved(&mut self, entry: serde_json::Value) {
        let id = entry["id"].clone();
        self.state.resolved.retain(|r| r["id"] != id);
        self.state.resolved.push(entry);
        if self.state.resolved.len() > RESOLVED_KEEP {
            let excess = self.state.resolved.len() - RESOLVED_KEEP;
            self.state.resolved.drain(..excess);
        }
        self.dirty = true;
    }

    /// Records this boot once; returns false when it was already there.
    pub fn remember_boot(&mut self, entry: serde_json::Value) -> bool {
        if self.state.boots.iter().any(|b| b["boot"] == entry["boot"]) {
            return false;
        }
        self.state.boots.push(entry);
        if self.state.boots.len() > BOOTS_KEEP {
            let excess = self.state.boots.len() - BOOTS_KEEP;
            self.state.boots.drain(..excess);
        }
        self.dirty = true;
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_and_roll() {
        let dir = std::env::temp_dir().join(format!("health_watch_test_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let mut s = Store::open(&dir);
        s.state.fingerprints.insert("k|x".into(), FpRec { boots: vec!["b1".into()], first_seen: 1, last_seen: 2, muted: true, known: false });
        let (rolled, day) = s.today("2026-10-13", 30);
        assert!(rolled);
        day.failed = 3;
        let (rolled2, _) = s.today("2026-10-13", 30);
        assert!(!rolled2);
        s.dirty = true;
        s.save();
        let s2 = Store::open(&dir);
        assert!(s2.state.fingerprints["k|x"].muted);
        assert_eq!(s2.days.len(), 1);
        assert_eq!(s2.days[0].failed, 3);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn resolved_and_boots_are_bounded() {
        let dir = std::env::temp_dir().join(format!("health_watch_ring_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let mut s = Store::open(&dir);
        let now = 10 * RESOLVED_DAYS_MS;
        for i in 0..(RESOLVED_KEEP + 5) {
            s.remember_resolved(serde_json::json!({"id": format!("x{i}"), "resolvedAt": now}));
        }
        assert_eq!(s.state.resolved.len(), RESOLVED_KEEP);
        // The same id again replaces its entry rather than adding one.
        s.remember_resolved(serde_json::json!({"id": format!("x{}", RESOLVED_KEEP + 4), "resolvedAt": now}));
        assert_eq!(s.state.resolved.len(), RESOLVED_KEEP);
        // Older than a week goes on prune.
        s.state.resolved[0]["resolvedAt"] = serde_json::json!(now - RESOLVED_DAYS_MS - 1);
        s.prune(now);
        assert_eq!(s.state.resolved.len(), RESOLVED_KEEP - 1);

        assert!(s.remember_boot(serde_json::json!({"boot": "b1", "total": 1})));
        assert!(!s.remember_boot(serde_json::json!({"boot": "b1", "total": 2})), "a boot is recorded once");
        for i in 0..BOOTS_KEEP + 3 {
            s.remember_boot(serde_json::json!({"boot": format!("x{i}")}));
        }
        assert_eq!(s.state.boots.len(), BOOTS_KEEP);

        // An old state file, without the new fields, still loads.
        std::fs::write(dir.join("state.json"), br#"{"version":1,"baseline":true,"fingerprints":{}}"#).unwrap();
        let old = Store::open(&dir);
        assert!(old.state.baseline && old.state.snoozed.is_empty() && old.state.resolved.is_empty());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
