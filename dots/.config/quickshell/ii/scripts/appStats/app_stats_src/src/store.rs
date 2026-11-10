//! On-disk history: one sparse file per local day.
//!
//! A single 30-day file would have to be parsed in full just to draw today's chart.
//! One file per day keeps today's read small, makes yesterday immutable, and turns
//! retention into an unlink.
//!
//! The files are written here rather than through JsonAdapter on the QML side, so
//! the numeric tuples cannot be silently coerced to another type.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

/// Bumped only when the tuple layout changes; readers must reject what they
/// cannot interpret rather than misread it.
const SCHEMA: u64 = 1;

/// Fields are stored internally at higher resolution than they are written, so a
/// day's worth of 10 s samples cannot accumulate rounding drift.
#[derive(Default, Clone)]
pub struct Bucket {
    pub fg_ms: u64,
    pub bg_ms: u64,
    pub focus_ms: u64,
    pub cpu_ms: u64,
    pub gpu_ms: u64,
    ram_sum_mib: u64,
    ram_n: u64,
    ram_peak_mib: u64,
    /// Energy in microjoules; written out as integer millijoules.
    pub uj_fg: u64,
    pub uj_bg: u64,
    pub launches: u64,
    pub sessions: u64,
    /// TCP bytes received and sent, and the part of both that moved while the app
    /// was in the background; written out as KiB.
    pub net_rx: u64,
    pub net_tx: u64,
    pub net_bg: u64,
}

impl Bucket {
    pub fn observe_ram(&mut self, mib: u64) {
        self.ram_sum_mib += mib;
        self.ram_n += 1;
        self.ram_peak_mib = self.ram_peak_mib.max(mib);
    }

    fn ram_avg(&self) -> u64 {
        if self.ram_n == 0 {
            0
        } else {
            self.ram_sum_mib / self.ram_n
        }
    }

    fn to_tuple(&self) -> Vec<u64> {
        let mut t = vec![
            (self.fg_ms + 500) / 1000,
            (self.bg_ms + 500) / 1000,
            (self.focus_ms + 500) / 1000,
            (self.cpu_ms + 500) / 1000,
            (self.gpu_ms + 500) / 1000,
            self.ram_avg(),
            self.ram_peak_mib,
            self.uj_fg / 1000,
            self.uj_bg / 1000,
            self.launches,
            self.sessions,
        ];
        // The network fields trail the rest and readers default anything missing to
        // zero, so a row that never touched the network keeps its old 11-field
        // shape — most headless rows, and every file a machine offline all day writes.
        let mut net = [self.net_rx, self.net_tx, self.net_bg].map(|b| (b + 512) / 1024);
        // Rounded one by one, two sub-KiB directions can both come out 0 while their
        // background sum rounds to 1; background is never more than the whole.
        net[2] = net[2].min(net[0] + net[1]);
        if net.iter().any(|&k| k > 0) {
            t.extend(net);
        }
        t
    }

    /// Reload after a restart. Sub-second and sub-millijoule remainders are lost,
    /// and the RAM mean collapses to a single sample — the alternative is losing
    /// the whole morning whenever the shell reloads.
    fn from_tuple(t: &[u64]) -> Bucket {
        let g = |i: usize| t.get(i).copied().unwrap_or(0);
        Bucket {
            fg_ms: g(0) * 1000,
            bg_ms: g(1) * 1000,
            focus_ms: g(2) * 1000,
            cpu_ms: g(3) * 1000,
            gpu_ms: g(4) * 1000,
            ram_sum_mib: g(5),
            ram_n: if g(5) > 0 { 1 } else { 0 },
            ram_peak_mib: g(6),
            uj_fg: g(7) * 1000,
            uj_bg: g(8) * 1000,
            launches: g(9),
            sessions: g(10),
            net_rx: g(11) * 1024,
            net_tx: g(12) * 1024,
            net_bg: g(13) * 1024,
        }
    }
}

pub struct AppRec {
    pub exe: String,
    pub headless: bool,
    pub hours: BTreeMap<u32, Bucket>,
}

/// The battery over one hour, kept beside the apps rather than among them: it
/// belongs to no application, and unlike every other row here it is a level as
/// well as an amount — a curve needs to know where the hour started and ended,
/// not only how much moved.
#[derive(Default, Clone)]
pub struct BatBucket {
    /// Tenths of a percent, so the curve is not a staircase of whole percents.
    pub start_deci: u64,
    pub end_deci: u64,
    pub min_deci: u64,
    pub max_deci: u64,
    /// Energy out of and into the pack, microwatt-hours.
    pub out_uwh: u64,
    pub in_uwh: u64,
    /// Time on battery, taking charge, and plugged in without charging.
    pub off_ac_ms: u64,
    pub charge_ms: u64,
    pub ac_ms: u64,
    seen: bool,
}

impl BatBucket {
    pub fn observe(&mut self, deci: u64) {
        if !self.seen {
            self.start_deci = deci;
            self.min_deci = deci;
            self.max_deci = deci;
            self.seen = true;
        }
        self.end_deci = deci;
        self.min_deci = self.min_deci.min(deci);
        self.max_deci = self.max_deci.max(deci);
    }

    fn to_tuple(&self) -> Vec<u64> {
        vec![
            self.start_deci,
            self.end_deci,
            self.min_deci,
            self.max_deci,
            (self.out_uwh + 500) / 1000,
            (self.in_uwh + 500) / 1000,
            (self.off_ac_ms + 500) / 1000,
            (self.charge_ms + 500) / 1000,
            (self.ac_ms + 500) / 1000,
        ]
    }

    fn from_tuple(t: &[u64]) -> BatBucket {
        let g = |i: usize| t.get(i).copied().unwrap_or(0);
        BatBucket {
            start_deci: g(0),
            end_deci: g(1),
            min_deci: g(2),
            max_deci: g(3),
            out_uwh: g(4) * 1000,
            in_uwh: g(5) * 1000,
            off_ac_ms: g(6) * 1000,
            charge_ms: g(7) * 1000,
            ac_ms: g(8) * 1000,
            // An hour on disk with a level was written from samples, so its opening
            // level stands. One without was written while the pack could not be read,
            // and the first reading now is its opening level, not a drop from zero.
            seen: g(3) > 0,
        }
    }
}

/// What `retention_days` means.
#[derive(Clone, Copy, PartialEq)]
pub enum Retention {
    /// Keep exactly that many days back from today.
    Fixed,
    /// Keep that many days *at least*, and never drop a day the previous calendar
    /// month still holds — so the month just gone can always be compared against
    /// the one running. The window slides between roughly 31 and 62 days.
    PreviousMonth,
}

impl Retention {
    pub fn parse(s: &str) -> Retention {
        match s {
            "previous-month" | "previousMonth" | "month" => Retention::PreviousMonth,
            _ => Retention::Fixed,
        }
    }
}

pub struct Store {
    dir: PathBuf,
    retention_days: i64,
    retention_mode: Retention,
    date: String,
    gmtoff: i64,
    apps: BTreeMap<String, AppRec>,
    bat: BTreeMap<u32, BatBucket>,
    bat_full_mwh: u64,
    dirty: bool,
}

/// Local calendar date, hour of day, and UTC offset for an epoch instant.
pub fn local(epoch_secs: i64) -> (String, u32, i64) {
    let t = epoch_secs as libc::time_t;
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    unsafe { libc::localtime_r(&t, &mut tm) };
    let date = format!(
        "{:04}-{:02}-{:02}",
        tm.tm_year + 1900,
        tm.tm_mon + 1,
        tm.tm_mday
    );
    (date, tm.tm_hour as u32, tm.tm_gmtoff as i64)
}

/// First day of the month before the one `date` falls in, as a "YYYY-MM-DD" key.
/// Takes the string rather than an instant because that is what it is compared
/// against — ISO dates sort lexicographically, so no calendar arithmetic is needed.
fn first_of_previous_month(date: &str) -> String {
    let year: i32 = date[0..4].parse().unwrap_or(1970);
    let month: u32 = date[5..7].parse().unwrap_or(1);
    if month <= 1 {
        format!("{:04}-12-01", year - 1)
    } else {
        format!("{:04}-{:02}-01", year, month - 1)
    }
}

pub fn now_ms() -> i64 {
    let mut ts: libc::timespec = unsafe { std::mem::zeroed() };
    unsafe { libc::clock_gettime(libc::CLOCK_REALTIME, &mut ts) };
    ts.tv_sec as i64 * 1000 + ts.tv_nsec as i64 / 1_000_000
}

fn offset_string(gmtoff: i64) -> String {
    let sign = if gmtoff < 0 { '-' } else { '+' };
    let a = gmtoff.abs();
    format!("{}{:02}:{:02}", sign, a / 3600, (a % 3600) / 60)
}

impl Store {
    pub fn new(dir: PathBuf, retention_days: i64, retention_mode: Retention) -> Store {
        let _ = fs::create_dir_all(&dir);
        let (date, _, gmtoff) = local(now_ms() / 1000);
        let mut store = Store {
            dir,
            retention_days,
            retention_mode,
            date,
            gmtoff,
            apps: BTreeMap::new(),
            bat: BTreeMap::new(),
            bat_full_mwh: 0,
            dirty: false,
        };
        store.load();
        store.prune();
        store
    }

    fn path_for(&self, date: &str) -> PathBuf {
        self.dir.join(format!("{date}.json"))
    }

    /// Pick up where a previous run left off, if it ran today.
    fn load(&mut self) {
        let Ok(raw) = fs::read_to_string(self.path_for(&self.date)) else {
            return;
        };
        let Ok(json) = serde_json::from_str::<serde_json::Value>(&raw) else {
            return;
        };
        if json.get("v").and_then(|v| v.as_u64()) != Some(SCHEMA) {
            return;
        }

        // Written by a sampler that knew about batteries, or absent because it did
        // not. Either is a readable file — the tuple layout is untouched, so the
        // section is additive and a day without one is simply a day with no curve.
        if let Some(bat) = json.get("bat") {
            self.bat_full_mwh = bat.get("full").and_then(|v| v.as_u64()).unwrap_or(0);
            if let Some(hours) = bat.get("h").and_then(|h| h.as_object()) {
                for (hour, tuple) in hours {
                    let Ok(hour) = hour.parse::<u32>() else { continue };
                    let Some(arr) = tuple.as_array() else { continue };
                    let vals: Vec<u64> = arr.iter().map(|v| v.as_u64().unwrap_or(0)).collect();
                    self.bat.insert(hour, BatBucket::from_tuple(&vals));
                }
            }
        }

        let Some(apps) = json.get("apps").and_then(|a| a.as_object()) else {
            return;
        };

        for (key, rec) in apps {
            let mut hours = BTreeMap::new();
            if let Some(h) = rec.get("h").and_then(|h| h.as_object()) {
                for (hour, tuple) in h {
                    let Ok(hour) = hour.parse::<u32>() else { continue };
                    let Some(arr) = tuple.as_array() else { continue };
                    let vals: Vec<u64> = arr.iter().map(|v| v.as_u64().unwrap_or(0)).collect();
                    hours.insert(hour, Bucket::from_tuple(&vals));
                }
            }
            self.apps.insert(
                key.clone(),
                AppRec {
                    exe: rec
                        .get("exe")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string(),
                    headless: rec
                        .get("headless")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false),
                    hours,
                },
            );
        }
    }

    /// Hour of `epoch_ms`, rolling the day file over first if the date changed.
    fn roll(&mut self, epoch_ms: i64) -> u32 {
        let (date, hour, gmtoff) = local(epoch_ms / 1000);
        if date != self.date {
            self.flush();
            self.apps.clear();
            self.bat.clear();
            self.date = date;
            self.gmtoff = gmtoff;
            self.prune();
        }
        self.dirty = true;
        hour
    }

    /// Bucket for `epoch_ms`, rolling the day file over first if the date changed.
    pub fn bucket(&mut self, epoch_ms: i64, key: &str, exe: &str, headless: bool) -> &mut Bucket {
        let hour = self.roll(epoch_ms);

        let rec = self.apps.entry(key.to_string()).or_insert_with(|| AppRec {
            exe: exe.to_string(),
            headless,
            hours: BTreeMap::new(),
        });
        // A name learned later (the proc sweep runs after the window appears) is
        // better than the placeholder recorded at first sight.
        if rec.exe.is_empty() && !exe.is_empty() {
            rec.exe = exe.to_string();
        }
        rec.hours.entry(hour).or_default()
    }

    /// The battery's bucket for `epoch_ms`.
    pub fn bat_bucket(&mut self, epoch_ms: i64) -> &mut BatBucket {
        let hour = self.roll(epoch_ms);
        self.bat.entry(hour).or_default()
    }

    pub fn set_bat_full(&mut self, mwh: u64) {
        self.bat_full_mwh = mwh;
    }

    /// End of the local hour containing `epoch_ms`, so a span can be split across
    /// an hour boundary instead of landing wholly in the wrong bucket.
    pub fn hour_end_ms(&self, epoch_ms: i64) -> i64 {
        let (_, _, gmtoff) = local(epoch_ms / 1000);
        let local_secs = epoch_ms / 1000 + gmtoff;
        ((local_secs / 3600) + 1) * 3600 * 1000 - gmtoff * 1000
    }

    pub fn flush(&mut self) -> Option<PathBuf> {
        if !self.dirty {
            return None;
        }

        let mut apps_map: serde_json::Map<String, serde_json::Value> = self
            .apps
            .iter()
            .map(|(key, rec)| {
                let hours: serde_json::Map<String, serde_json::Value> = rec
                    .hours
                    .iter()
                    .map(|(h, b)| (h.to_string(), serde_json::json!(b.to_tuple())))
                    .collect();
                (
                    key.clone(),
                    serde_json::json!({
                        "exe": rec.exe,
                        "headless": rec.headless,
                        "h": hours,
                    }),
                )
            })
            .collect();

        let mut bat_hours: serde_json::Map<String, serde_json::Value> = self
            .bat
            .iter()
            .map(|(h, b)| (h.to_string(), serde_json::json!(b.to_tuple())))
            .collect();
        let mut bat_full = self.bat_full_mwh;

        // Merge existing hours on disk so historical hours of the day are never erased or lost
        let path = self.path_for(&self.date);
        if let Ok(raw) = fs::read_to_string(&path) {
            if let Ok(disk_json) = serde_json::from_str::<serde_json::Value>(&raw) {
                if let Some(disk_bat) = disk_json.get("bat") {
                    if bat_full == 0 {
                        bat_full = disk_bat.get("full").and_then(|v| v.as_u64()).unwrap_or(0);
                    }
                    if let Some(disk_h) = disk_bat.get("h").and_then(|h| h.as_object()) {
                        for (hour_str, tuple) in disk_h {
                            if !bat_hours.contains_key(hour_str) {
                                bat_hours.insert(hour_str.clone(), tuple.clone());
                            }
                        }
                    }
                }
                if let Some(disk_apps) = disk_json.get("apps").and_then(|a| a.as_object()) {
                    for (app_key, disk_rec) in disk_apps {
                        let Some(disk_h) = disk_rec.get("h").and_then(|h| h.as_object()) else { continue };
                        let exe = disk_rec.get("exe").and_then(|v| v.as_str()).unwrap_or("");
                        let headless = disk_rec.get("headless").and_then(|v| v.as_bool()).unwrap_or(false);

                        let entry = apps_map.entry(app_key.clone()).or_insert_with(|| {
                            serde_json::json!({
                                "exe": exe,
                                "headless": headless,
                                "h": serde_json::Map::<String, serde_json::Value>::new(),
                            })
                        });

                        if let Some(entry_obj) = entry.as_object_mut() {
                            if let Some(entry_h) = entry_obj.get_mut("h").and_then(|h| h.as_object_mut()) {
                                for (hour_str, tuple) in disk_h {
                                    if !entry_h.contains_key(hour_str) {
                                        entry_h.insert(hour_str.clone(), tuple.clone());
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        let mut doc = serde_json::json!({
            "v": SCHEMA,
            "date": self.date,
            "tz": offset_string(self.gmtoff),
            "apps": apps_map,
        });

        // Left out entirely on a machine with no battery, so its files stay byte
        // for byte what a sampler without any of this would have written.
        if !bat_hours.is_empty() || bat_full > 0 {
            doc["bat"] = serde_json::json!({
                "full": bat_full,
                "h": bat_hours,
            });
        }

        // Write-then-rename: a reader must never see a half-written day.
        let tmp = path.with_extension("json.tmp");
        if fs::write(&tmp, doc.to_string()).is_err() {
            return None;
        }
        if fs::rename(&tmp, &path).is_err() {
            let _ = fs::remove_file(&tmp);
            return None;
        }
        self.dirty = false;
        Some(path)
    }

    /// Oldest date worth keeping, or None when nothing is ever dropped. Recomputed
    /// on every prune rather than at startup, so the month-relative window slides
    /// with the calendar instead of freezing at whatever day the sampler launched.
    fn cutoff(&self) -> Option<String> {
        if self.retention_days <= 0 {
            return None;
        }
        let by_days = local(now_ms() / 1000 - self.retention_days * 86400).0;
        if self.retention_mode == Retention::Fixed {
            return Some(by_days);
        }
        let first_of_previous = first_of_previous_month(&local(now_ms() / 1000).0);
        Some(std::cmp::min(by_days, first_of_previous))
    }

    fn prune(&mut self) {
        let Some(cutoff) = self.cutoff() else {
            return;
        };
        let Ok(dir) = fs::read_dir(&self.dir) else {
            return;
        };
        for entry in dir.flatten() {
            let path = entry.path();
            let Some(stem) = path.file_stem().and_then(|s| s.to_str()) else {
                continue;
            };
            if path.extension().and_then(|e| e.to_str()) != Some("json") {
                continue;
            }
            // ISO dates sort lexicographically, so a string compare is a date compare.
            if stem.len() == 10 && stem < cutoff.as_str() {
                let _ = fs::remove_file(&path);
            }
        }
    }

    pub fn dir(&self) -> &Path {
        &self.dir
    }
}
