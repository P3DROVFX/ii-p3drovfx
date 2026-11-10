//! health_watch — the System Health helper for the Quickshell `ii` shell.
//!
//! Watches the things that break quietly on a Linux desktop and reports them as
//! NDJSON on stdout: failed units and restart loops, crashes, new journal error
//! groups, drive SMART, filling filesystems, firmware and update chores, memory
//! pressure, throttling and time sync, packages that need a rebuild, the shell's
//! own helpers and memory, and how long the boot took. Commands arrive as NDJSON
//! on stdin. The contract is PROTOCOL.md beside this crate.
//!
//! Everything is read as the user. The only privileged operations are systemd
//! and UDisks method calls that systemd/UDisks themselves send through polkit.
//! Core dumps are never opened, only checked for readability.

mod boot;
mod coredump;
mod disks;
mod elf;
mod fingerprint;
mod fs;
mod fwupd;
mod hw;
mod journal;
mod packages;
mod pressure;
mod proto;
mod rebuild;
mod shell;
mod store;
mod units;

use serde_json::{json, Value};
use std::collections::{HashMap, HashSet, VecDeque};
use std::io::BufRead;
use std::path::PathBuf;
use std::sync::mpsc::{channel, Receiver, RecvTimeoutError, Sender};
use std::time::{Duration, Instant};

use coredump::CrashEvent;
use proto::{emit, jnum, jtext, log, now_ms};
use units::{Manager, Scope};

pub enum Ev {
    Stdin(String),
    StdinClosed,
    Units(Scope),
    Journal(Value),
    JournalDied,
    PackageLog,
    Fwupd(Value),
    Reply(Value),
    Rescan(Scope),
    /// The rebuild scan's result (rebuild.rs), from its thread.
    Rebuild(Vec<Value>),
    /// Helpers built from older sources (shell.rs), from its thread.
    Helpers(Vec<Value>),
}

#[derive(Clone)]
struct Config {
    state_dir: PathBuf,
    once: bool,
    sources: HashSet<String>,
    known_after: usize,
    of_last: usize,
    quiet_days: u64,
    disk_warn: f64,
    disk_crit: f64,
    psi_mem: f64,
    restart_loop: u64,
    history_days: usize,
    /// The shell's memory, in MiB, past which it is a finding.
    shell_mem_mb: u64,
    /// Battery health (full charge against design, %) below which it is a finding.
    battery_wear: f64,
}

/// The sources on when --sources is not given. `shellLog` is not among them: it
/// keeps a `qs log` follower running, so it is only ever asked for by name.
const ALL_SOURCES: [&str; 16] = [
    "units", "userUnits", "appLaunches", "crashes", "journal", "drives", "filesystems", "firmware", "packages", "pressure", "thermals", "timesync",
    "rebuild", "shell", "boot", "hardware",
];

fn parse_args() -> Config {
    let state_home = std::env::var("XDG_STATE_HOME")
        .ok()
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(proto::home_dir()).join(".local/state"));
    let mut c = Config {
        state_dir: state_home.join("quickshell/health"),
        once: false,
        sources: ALL_SOURCES.iter().map(|s| s.to_string()).collect(),
        known_after: 3,
        of_last: 5,
        quiet_days: 14,
        disk_warn: 90.0,
        disk_crit: 97.0,
        psi_mem: 10.0,
        restart_loop: 5,
        history_days: 30,
        shell_mem_mb: 1200,
        battery_wear: 80.0,
    };
    // "--disk-warn=90" and "--disk-warn 90" both work.
    let mut args: Vec<String> = Vec::new();
    for a in std::env::args().skip(1) {
        match a.split_once('=') {
            Some((k, v)) if k.starts_with("--") => {
                args.push(k.to_string());
                args.push(v.to_string());
            }
            _ => args.push(a),
        }
    }
    let num = |v: &str, d: f64| v.parse::<f64>().unwrap_or(d);
    let mut i = 0;
    while i < args.len() {
        if args[i] == "--once" {
            c.once = true;
            i += 1;
            continue;
        }
        let val = args.get(i + 1).cloned().unwrap_or_default();
        match args[i].as_str() {
            // A QML url (`file:///…`) is accepted as the path it names.
            "--state-dir" => c.state_dir = PathBuf::from(val.strip_prefix("file://").unwrap_or(&val)),
            "--sources" => c.sources = val.split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect(),
            "--known-after" => c.known_after = num(&val, 3.0).max(1.0) as usize,
            "--of-last" => c.of_last = num(&val, 5.0).max(1.0) as usize,
            "--quiet-days" => c.quiet_days = num(&val, 14.0).max(1.0) as u64,
            "--disk-warn" => c.disk_warn = num(&val, 90.0).clamp(1.0, 100.0),
            "--disk-crit" => c.disk_crit = num(&val, 97.0).clamp(1.0, 100.0),
            "--psi-mem" => c.psi_mem = num(&val, 10.0).clamp(0.1, 100.0),
            "--restart-loop" => c.restart_loop = num(&val, 5.0).max(2.0) as u64,
            "--history-days" => c.history_days = num(&val, 30.0).clamp(1.0, 366.0) as usize,
            "--shell-mem-mb" => c.shell_mem_mb = num(&val, 1200.0).clamp(200.0, 65536.0) as u64,
            "--battery-wear" => c.battery_wear = num(&val, 80.0).clamp(10.0, 100.0),
            _ => {
                i += 1;
                continue;
            }
        }
        i += 2;
    }
    c
}

#[derive(Default, Clone)]
struct Group {
    source: String,
    template: String,
    sample: String,
    priority: i64,
    count: u64,
    first: u64,
    last: u64,
}

struct App {
    cfg: Config,
    tx: Sender<Ev>,
    store: store::Store,
    home: String,
    user: String,
    boot: String,
    synced: bool,
    /// id → finding as last sent (alert flag stripped).
    findings: HashMap<String, Value>,
    sys: Option<Manager>,
    usr: Option<Manager>,
    restart_hist: HashMap<String, VecDeque<(u64, u64)>>,
    journal_access: &'static str,
    groups: HashMap<String, Group>,
    recent_boots: Vec<String>,
    journal_cursor: Option<String>,
    follower: Option<journal::Follower>,
    journal_dirty: bool,
    crash_events: Vec<CrashEvent>,
    pkg: packages::Manager,
    pkg_events: Vec<packages::PkgEvent>,
    transactions: Vec<packages::Transaction>,
    owner_cache: HashMap<String, Option<(String, String)>>,
    fs: fs::Fs,
    fs_last: Vec<Value>,
    throttle: pressure::Throttle,
    psi_hist: VecDeque<f64>,
    holds: HashMap<&'static str, pressure::Hold>,
    udisks: Option<zbus::blocking::Connection>,
    bus_sys: Option<zbus::blocking::Connection>,
    bus_user: Option<zbus::blocking::Connection>,
    drives_at: u64,
    kernel: Value,
    packages_info: Value,
    deleted_libs: Vec<Value>,
    deleted_at: u64,
    cleanup: Value,
    fwupd: Value,
    fwupd_pending: bool,
    ntp: Option<bool>,
    synced_clock: bool,
    unsynced_checks: u32,
    visible: bool,
    dump_access: String,
    /// "scope:unit" → (verb, when): what the user last did to a unit, so a finding
    /// that resolves right after can say it was fixed by that.
    last_act: HashMap<String, (String, u64)>,
    rebuild_cache: std::sync::Arc<std::sync::Mutex<rebuild::Cache>>,
    rebuild_running: bool,
    /// The shell's memory: the highest in its first hour (its normal), when it
    /// was first read, and since when it has been too high.
    shell_base: u64,
    shell_first: u64,
    shell_high_since: Option<u64>,
    shell_rss: Option<u64>,
    /// QML errors counted from the shell's log, and the follower process.
    shell_log: shell::LogErrors,
    shell_log_child: Option<std::process::Child>,
    boot_tries: u32,
    /// lspci's model name per GPU slot, asked once.
    gpu_names: HashMap<String, String>,
    /// Since when a fan has read 0 RPM with the CPU at 80 °C or more.
    fan_hot_since: Option<u64>,
    hardware_next: Instant,
    // timers
    rebuild_due: Option<Instant>,
    boot_due: Option<Instant>,
    helpers_next: Instant,
    units_due: HashMap<Scope, Instant>,
    units_first: HashMap<Scope, Instant>,
    pkg_due: Option<Instant>,
    journal_flush_due: Option<Instant>,
    vitals_next: Instant,
    fs_next: Instant,
    drives_next: Instant,
    fwupd_next: Instant,
    system_next: Instant,
    time_next: Instant,
    save_next: Instant,
    journal_restart: Option<Instant>,
    sync_deadline: Option<Instant>,
}

fn has(cfg: &Config, s: &str) -> bool {
    cfg.sources.contains(s)
}

impl App {
    fn new(cfg: Config, tx: Sender<Ev>) -> App {
        let now = Instant::now();
        App {
            store: store::Store::open(&cfg.state_dir),
            home: proto::home_dir(),
            user: proto::user_name(),
            boot: proto::boot_id(),
            synced: false,
            findings: HashMap::new(),
            sys: None,
            usr: None,
            restart_hist: HashMap::new(),
            journal_access: "none",
            groups: HashMap::new(),
            recent_boots: Vec::new(),
            journal_cursor: None,
            follower: None,
            journal_dirty: false,
            crash_events: Vec::new(),
            pkg: packages::Manager::None,
            pkg_events: Vec::new(),
            transactions: Vec::new(),
            owner_cache: HashMap::new(),
            fs: fs::Fs::default(),
            fs_last: Vec::new(),
            throttle: pressure::Throttle::default(),
            psi_hist: VecDeque::new(),
            holds: HashMap::new(),
            udisks: None,
            bus_sys: None,
            bus_user: None,
            drives_at: 0,
            kernel: json!({}),
            packages_info: json!({}),
            deleted_libs: Vec::new(),
            deleted_at: 0,
            cleanup: json!({}),
            fwupd: json!({"available": false, "hsi": "", "hsiLevel": null, "runtimeIssue": false, "attrs": [], "upgrades": []}),
            fwupd_pending: false,
            ntp: None,
            synced_clock: true,
            unsynced_checks: 0,
            visible: false,
            dump_access: "denied".into(),
            last_act: HashMap::new(),
            rebuild_cache: Default::default(),
            rebuild_running: false,
            shell_base: 0,
            shell_first: 0,
            shell_high_since: None,
            shell_rss: None,
            shell_log: Default::default(),
            shell_log_child: None,
            boot_tries: 0,
            gpu_names: HashMap::new(),
            fan_hot_since: None,
            hardware_next: now + Duration::from_secs(60),
            rebuild_due: None,
            boot_due: None,
            helpers_next: now + Duration::from_secs(6 * 3600),
            units_due: HashMap::new(),
            units_first: HashMap::new(),
            pkg_due: None,
            journal_flush_due: None,
            vitals_next: now,
            fs_next: now,
            drives_next: now + Duration::from_secs(600),
            fwupd_next: now + Duration::from_secs(6 * 3600),
            system_next: now + Duration::from_secs(1800),
            time_next: now + Duration::from_secs(300),
            save_next: now + Duration::from_secs(60),
            journal_restart: None,
            sync_deadline: None,
            cfg,
            tx,
        }
    }

    // ── Findings ────────────────────────────────────────────────────────

    fn is_muted(&self, fp: &str, kind: &str, data: &Value) -> bool {
        if kind == "crash" {
            let exe = data.get("exe").and_then(|v| v.as_str()).unwrap_or("");
            return self.store.state.muted_programs.iter().any(|p| p == exe);
        }
        !fp.is_empty() && self.store.state.fingerprints.get(fp).is_some_and(|r| r.muted)
    }

    /// A finding's `snoozed` field: the epoch ms it wakes at, "boot" for until the
    /// next boot, or null.
    fn snoozed(&self, id: &str) -> Value {
        match self.store.state.snoozed.get(id) {
            Some(s) if s.active(now_ms(), &self.boot) => {
                if s.boot.is_some() { json!("boot") } else { json!(s.until) }
            }
            _ => Value::Null,
        }
    }

    /// Kinds whose going away is a fix worth listing. A crash ageing out of the
    /// week, a journal group turning "known" or a failed app launch are not.
    fn fix_worth_listing(kind: &str) -> bool {
        !matches!(kind, "crash" | "journal" | "appLaunch")
    }

    /// Remembers a finding that went away for "Fixed recently", with what fixed it:
    /// the user's own action on that unit in the two minutes before, or "self".
    fn remember_resolved(&mut self, f: &Value) {
        let kind = f["kind"].as_str().unwrap_or("");
        let id = f["id"].as_str().unwrap_or("");
        if !Self::fix_worth_listing(kind) || self.store.state.dismissed.contains_key(id) {
            return;
        }
        let now = now_ms();
        let key = format!("{}:{}", f["data"]["scope"].as_str().unwrap_or(""), f["data"]["unit"].as_str().unwrap_or(""));
        let by = match self.last_act.get(&key) {
            Some((verb, at)) if now.saturating_sub(*at) <= 120_000 => verb.clone(),
            _ => "self".to_string(),
        };
        self.store.remember_resolved(json!({
            "id": id, "kind": kind, "sev": f["sev"], "data": f["data"], "since": f["since"],
            "resolvedAt": now, "by": by,
        }));
        self.publish_resolved();
    }

    fn publish_resolved(&self) {
        emit(&json!({"t": "resolved", "items": self.store.state.resolved}));
    }

    /// Lifts snoozes that ran out and re-sends their findings without the flag.
    fn expire_snoozes(&mut self) {
        let now = now_ms();
        let boot = self.boot.clone();
        let before = self.store.state.snoozed.len();
        self.store.state.snoozed.retain(|_, s| s.active(now, &boot));
        if self.store.state.snoozed.len() != before {
            self.store.dirty = true;
            self.refresh_muted();
        }
    }

    /// Replaces every finding whose id starts with one of `prefixes` by `fresh`:
    /// upserts what is new or changed, resolves what is gone. `fresh` carries each
    /// finding's event time, which decides whether a dismissal still hides it.
    fn apply(&mut self, prefixes: &[String], fresh: Vec<(Value, u64)>) {
        let mut keep: HashSet<String> = HashSet::new();
        for (mut f, event_ms) in fresh {
            let id = f["id"].as_str().unwrap_or("").to_string();
            if let Some(dismissed) = self.store.state.dismissed.get(&id) {
                if event_ms <= *dismissed {
                    continue;
                }
            }
            let kind = f["kind"].as_str().unwrap_or("").to_string();
            let fp = f["fp"].as_str().unwrap_or("").to_string();
            let muted = self.is_muted(&fp, &kind, &f["data"]);
            f["muted"] = json!(muted);
            f["snoozed"] = self.snoozed(&id);
            f["alert"] = json!(false);
            keep.insert(id.clone());
            let changed = self.findings.get(&id) != Some(&f);
            if !changed {
                continue;
            }
            let first_time = !self.findings.contains_key(&id);
            self.findings.insert(id.clone(), f.clone());
            let alert_key = if fp.is_empty() { id.clone() } else { fp.clone() };
            let alert = self.synced
                && first_time
                && f["sev"] == "critical"
                && !muted
                && f["snoozed"].is_null()
                && kind != "appLaunch"
                && self.store.state.alerted.get(&alert_key) != Some(&self.boot);
            if alert {
                self.store.state.alerted.insert(alert_key, self.boot.clone());
                self.store.dirty = true;
                f["alert"] = json!(true);
            }
            emit(&json!({"t": "finding", "op": "upsert", "f": f}));
        }
        let gone: Vec<String> = self
            .findings
            .keys()
            .filter(|id| prefixes.iter().any(|p| id.starts_with(p.as_str())) && !keep.contains(*id))
            .cloned()
            .collect();
        for id in gone {
            if let Some(f) = self.findings.remove(&id) {
                self.remember_resolved(&f);
            }
            emit(&json!({"t": "finding", "op": "resolve", "id": id}));
        }
    }

    fn finding(id: String, kind: &str, sev: &str, since: u64, count: u64, fp: String, data: Value) -> Value {
        json!({"id": id, "kind": kind, "sev": sev, "since": since, "count": count.max(1), "fp": fp, "data": data})
    }

    /// Re-sends every finding whose muted or snoozed flag changed.
    fn refresh_muted(&mut self) {
        let ids: Vec<String> = self.findings.keys().cloned().collect();
        for id in ids {
            let f = self.findings[&id].clone();
            let muted = self.is_muted(f["fp"].as_str().unwrap_or(""), f["kind"].as_str().unwrap_or(""), &f["data"]);
            let snoozed = self.snoozed(&id);
            if f["muted"] != json!(muted) || f["snoozed"] != snoozed {
                let mut g = f.clone();
                g["muted"] = json!(muted);
                g["snoozed"] = snoozed;
                self.findings.insert(id, g.clone());
                emit(&json!({"t": "finding", "op": "upsert", "f": g}));
            }
        }
    }

    // ── Units ───────────────────────────────────────────────────────────

    fn scan_units(&mut self, scope: Scope) {
        let mgr = match scope {
            Scope::System => self.sys.as_ref(),
            Scope::User => self.usr.as_ref(),
        };
        let Some(mgr) = mgr else { return };
        let res = mgr.scan();
        let now = now_ms();
        let s = scope.name();
        let mut fresh = Vec::new();
        for u in &res.failed {
            let why = units::classify(&u.result, u.exec_code, u.exec_status, &u.exec_path, u.exec_exists);
            let since = if u.since_ms > 0 { u.since_ms } else { now };
            let mut data = units::unit_data(scope, u, why);
            if units::is_app_launch(&u.name) {
                if !has(&self.cfg, "appLaunches") {
                    continue;
                }
                data["app"] = json!(units::app_id(&u.name));
                let id = format!("app:{s}:{}", u.name);
                fresh.push((Self::finding(id.clone(), "appLaunch", "info", since, 1, id, data), since));
            } else {
                let id = format!("unit:{s}:{}", u.name);
                let sev = if u.name.ends_with(".service") { "critical" } else { "warning" };
                fresh.push((Self::finding(id.clone(), "unit", sev, since, u.n_restarts.max(1), id, data), since));
            }
        }
        let mut live_keys = HashSet::new();
        for r in &res.restarting {
            let key = format!("{s}:{}", r.name);
            live_keys.insert(key.clone());
            let hist = self.restart_hist.entry(key).or_default();
            if hist.back().is_none_or(|(_, n)| *n != r.n_restarts) {
                hist.push_back((now, r.n_restarts));
            }
            while hist.len() > 1 && hist.front().is_some_and(|(t, _)| now.saturating_sub(*t) > 10 * 60 * 1000) {
                hist.pop_front();
            }
            let base = hist.front().map(|(_, n)| *n).unwrap_or(r.n_restarts);
            // A first sighting already deep into a loop counts its restarts so far.
            let delta = if hist.len() == 1 { r.n_restarts } else { r.n_restarts.saturating_sub(base) + 1 };
            if delta >= self.cfg.restart_loop {
                let id = format!("loop:{s}:{}", r.name);
                let data = json!({"scope": s, "unit": r.name, "description": r.description, "nRestarts": r.n_restarts,
                    "activeState": r.active, "subState": r.sub});
                let since = hist.front().map(|(t, _)| *t).unwrap_or(now);
                fresh.push((Self::finding(id.clone(), "restartLoop", "critical", since, r.n_restarts, id, data), now));
            }
        }
        self.restart_hist.retain(|k, _| !k.starts_with(&format!("{s}:")) || live_keys.contains(k));
        let prefixes = vec![format!("unit:{s}:"), format!("app:{s}:"), format!("loop:{s}:")];
        self.apply(&prefixes, fresh);
    }

    fn connect_units(&mut self) {
        if has(&self.cfg, "units") {
            self.sys = self.bus_sys.clone().and_then(|c| Manager::connect(Scope::System, c));
        }
        if has(&self.cfg, "userUnits") {
            self.usr = self.bus_user.clone().and_then(|c| Manager::connect(Scope::User, c));
        }
        if !self.cfg.once {
            if let Some(m) = &self.sys {
                m.spawn_watcher(self.tx.clone());
            }
            if let Some(m) = &self.usr {
                m.spawn_watcher(self.tx.clone());
            }
        }
    }

    // ── Journal ─────────────────────────────────────────────────────────

    fn group_state(&self, fp: &str) -> &'static str {
        let rec = self.store.state.fingerprints.get(fp);
        if rec.is_some_and(|r| r.muted) {
            return "muted";
        }
        if rec.is_some_and(|r| r.known) || self.boots_seen(fp) >= self.cfg.known_after {
            return "known";
        }
        "new"
    }

    fn boots_seen(&self, fp: &str) -> usize {
        let Some(rec) = self.store.state.fingerprints.get(fp) else { return 0 };
        rec.boots.iter().filter(|b| self.recent_boots.contains(b)).count()
    }

    /// Feeds one error entry into this boot's groups and the fingerprint history.
    fn take_entry(&mut self, e: &Value) {
        let (fp, source, template) = fingerprint::fingerprint(e, &self.home);
        let ts = (jnum(e.get("__REALTIME_TIMESTAMP")).unwrap_or(0).max(0) as u64) / 1000;
        let prio = jnum(e.get("PRIORITY")).unwrap_or(3);
        let msg = jtext(e.get("MESSAGE"));
        let g = self.groups.entry(fp.clone()).or_insert_with(|| Group {
            source,
            template,
            sample: msg.lines().next().unwrap_or("").chars().take(300).collect(),
            priority: prio,
            count: 0,
            first: ts,
            last: ts,
        });
        g.count += 1;
        g.last = g.last.max(ts);
        g.priority = g.priority.min(prio);
        let quiet_ms = self.cfg.quiet_days * 86_400_000;
        let boot = self.boot.clone();
        let rec = self.store.state.fingerprints.entry(fp).or_default();
        if !rec.boots.contains(&boot) {
            // Quiet long enough: the group is news again.
            if rec.last_seen > 0 && ts.saturating_sub(rec.last_seen) > quiet_ms {
                rec.boots.clear();
                rec.known = false;
            }
            rec.boots.push(boot);
            if rec.boots.len() > 12 {
                let excess = rec.boots.len() - 12;
                rec.boots.drain(..excess);
            }
            self.store.dirty = true;
        }
        if rec.first_seen == 0 {
            rec.first_seen = ts;
            self.store.dirty = true;
        }
        if ts > rec.last_seen {
            rec.last_seen = ts;
            self.store.dirty = true;
        }
        self.journal_dirty = true;
    }

    /// First run: every error group the kept boots hold becomes known.
    fn build_baseline(&mut self) {
        let previous: Vec<String> = self.recent_boots.iter().filter(|b| **b != self.boot).cloned().collect();
        for b in previous {
            let (entries, _) = journal::read_boot(Some(&b));
            for e in entries {
                if coredump::is_coredump(&e) {
                    continue;
                }
                let (fp, _, _) = fingerprint::fingerprint(&e, &self.home);
                let ts = (jnum(e.get("__REALTIME_TIMESTAMP")).unwrap_or(0).max(0) as u64) / 1000;
                let rec = self.store.state.fingerprints.entry(fp).or_default();
                if !rec.boots.contains(&b) {
                    rec.boots.push(b.clone());
                }
                rec.known = true;
                if rec.first_seen == 0 || ts < rec.first_seen {
                    rec.first_seen = ts;
                }
                rec.last_seen = rec.last_seen.max(ts);
            }
        }
        // This boot so far is history too.
        let current: Vec<String> = self.groups.keys().cloned().collect();
        for fp in current {
            self.store.state.fingerprints.entry(fp).or_default().known = true;
        }
        self.store.state.baseline = true;
        self.store.dirty = true;
    }

    fn start_journal(&mut self) {
        self.journal_access = journal::access();
        if self.journal_access == "none" {
            return;
        }
        let mut boots = journal::list_boots();
        if !boots.contains(&self.boot) {
            boots.push(self.boot.clone());
        }
        let keep = self.cfg.of_last.max(1);
        if boots.len() > keep {
            boots.drain(..boots.len() - keep);
        }
        self.recent_boots = boots;
        let (entries, cursor) = journal::read_boot(None);
        for e in &entries {
            if coredump::is_coredump(e) {
                continue;
            }
            self.take_entry(e);
        }
        self.journal_cursor = cursor;
        if !self.store.state.baseline {
            self.build_baseline();
        }
        if !self.cfg.once {
            self.follower = journal::follow(self.journal_cursor.as_deref(), self.tx.clone());
        }
        self.flush_journal();
    }

    fn on_journal(&mut self, e: Value) {
        let cursor = jtext(e.get("__CURSOR"));
        if !cursor.is_empty() {
            self.journal_cursor = Some(cursor);
        }
        if coredump::is_coredump(&e) {
            if has(&self.cfg, "crashes") {
                if let Some(ev) = coredump::parse_event(&e) {
                    self.add_crash(ev);
                    self.publish_crashes();
                }
            }
            return;
        }
        if !has(&self.cfg, "journal") {
            return;
        }
        self.take_entry(&e);
        if self.journal_flush_due.is_none() {
            self.journal_flush_due = Some(Instant::now() + Duration::from_secs(5));
        }
    }

    fn flush_journal(&mut self) {
        self.journal_flush_due = None;
        if !has(&self.cfg, "journal") || self.journal_access == "none" {
            return;
        }
        self.journal_dirty = false;
        let mut rows: Vec<(String, &'static str, Group)> =
            self.groups.iter().map(|(fp, g)| (fp.clone(), self.group_state(fp), g.clone())).collect();
        let rank = |s: &str| match s {
            "new" => 0,
            "muted" => 1,
            _ => 2,
        };
        rows.sort_by(|a, b| rank(a.1).cmp(&rank(b.1)).then(b.2.count.cmp(&a.2.count)));
        let known_groups = rows.iter().filter(|r| r.1 == "known").count();
        let known_lines: u64 = rows.iter().filter(|r| r.1 == "known").map(|r| r.2.count).sum();
        let muted_groups = rows.iter().filter(|r| r.1 == "muted").count();
        let mut out = Vec::new();
        let mut fresh = Vec::new();
        for (i, (fp, state, g)) in rows.iter().enumerate() {
            if i < 300 || *state != "known" {
                let rec = self.store.state.fingerprints.get(fp);
                out.push(json!({
                    "fp": fp, "source": g.source, "template": g.template, "sample": g.sample,
                    "priority": g.priority, "countBoot": g.count, "bootsSeen": self.boots_seen(fp).max(1),
                    "bootsWindow": self.recent_boots.len().max(1),
                    "firstSeen": rec.map(|r| r.first_seen).unwrap_or(g.first), "lastSeen": g.last, "state": state,
                }));
            }
            if *state == "new" {
                let sev = if g.priority <= 2 { "critical" } else { "warning" };
                let data = json!({"source": g.source, "template": g.template, "sample": g.sample, "priority": g.priority, "countBoot": g.count});
                fresh.push((Self::finding(format!("journal:{fp}"), "journal", sev, g.first, g.count, fp.clone(), data), g.last));
            }
        }
        out.truncate(300.max(out.iter().filter(|r| r["state"] != "known").count()));
        emit(&json!({"t": "journal", "access": self.journal_access, "groups": out,
            "noise": {"knownGroups": known_groups, "knownLines": known_lines, "mutedGroups": muted_groups}}));
        self.apply(&["journal:".to_string()], fresh);
        // Today's count of new groups, for the history row.
        let today = packages::local_date(now_ms());
        let new_today = rows
            .iter()
            .filter(|r| r.1 == "new" && packages::local_date(r.2.first) == today)
            .count() as u64;
        let keep = self.cfg.history_days;
        let (_, day) = self.store.today(&today, keep);
        if day.new_errors != new_today {
            day.new_errors = new_today;
            self.store.dirty = true;
        }
    }

    // ── Crashes ─────────────────────────────────────────────────────────

    fn add_crash(&mut self, ev: CrashEvent) {
        if self.crash_events.iter().any(|e| e.exe == ev.exe && e.time == ev.time && e.pid == ev.pid) {
            return;
        }
        self.crash_events.push(ev);
    }

    fn load_crashes(&mut self) {
        self.crash_events.clear();
        for e in journal::read_crashes() {
            if let Some(ev) = coredump::parse_event(&e) {
                self.add_crash(ev);
            }
        }
    }

    fn package_of(&mut self, exe: &str, pj: &str) -> Option<(String, String)> {
        if let Some(p) = coredump::package_from_json(pj) {
            return Some((p.name, p.version));
        }
        if let Some(cached) = self.owner_cache.get(exe) {
            return cached.clone();
        }
        let found = packages::owner(self.pkg, exe);
        self.owner_cache.insert(exe.to_string(), found.clone());
        found
    }

    fn publish_crashes(&mut self) {
        if !has(&self.cfg, "crashes") {
            return;
        }
        let now = now_ms();
        let cutoff = now.saturating_sub(coredump::WINDOW_MS);
        self.crash_events.retain(|e| e.time >= cutoff);
        let events = self.crash_events.clone();
        let groups = coredump::group(&events);
        let mut list = Vec::new();
        let mut fresh = Vec::new();
        let today = packages::local_date(now);
        let mut today_count = 0u64;
        for g in groups {
            let newest = *g.events.last().unwrap();
            let first = g.events.first().unwrap().time;
            today_count += g.events.iter().filter(|e| packages::local_date(e.time) == today).count() as u64;
            let pkg = self.package_of(&g.exe, &newest.package_json);
            let after = pkg.as_ref().and_then(|(name, _)| {
                self.pkg_events
                    .iter()
                    .filter(|p| &p.name == name && p.time < first && p.time >= cutoff)
                    .max_by_key(|p| p.time)
                    .map(|p| json!({"name": p.name, "from": p.from, "to": p.to, "time": p.time}))
            });
            let muted = self.store.state.muted_programs.iter().any(|p| p == &g.exe);
            let id = format!("crash:{}", g.exe);
            let dismissed = self.store.state.dismissed.get(&id).copied().unwrap_or(0);
            let core_readable = coredump::readable(&newest.core_file);
            let mut group = json!({
                "exe": g.exe,
                "name": coredump::exe_name(&g.exe),
                "root": newest.uid == 0,
                "count": g.events.len(),
                "package": pkg.as_ref().map(|p| p.0.clone()),
                "version": pkg.as_ref().map(|p| p.1.clone()),
                "signal": newest.signal,
                "signalName": newest.signal_name,
                "unit": newest.unit,
                "last": newest.time,
                "first": first,
                "trace": coredump::trace_json(&newest.trace),
                "ownFrame": coredump::own_frame(&newest.trace),
                "afterUpdate": after,
                "coreReadable": core_readable,
                "muted": muted,
                "dismissedAt": dismissed,
            });
            let data = group.clone();
            group["events"] = Value::Array(
                g.events
                    .iter()
                    .map(|e| json!({"time": e.time, "pid": e.pid, "uid": e.uid, "signal": e.signal,
                        "coreFile": e.core_file, "coreReadable": coredump::readable(&e.core_file)}))
                    .collect(),
            );
            list.push(group);
            let sev = if now.saturating_sub(newest.time) <= 24 * 3600 * 1000 { "critical" } else { "warning" };
            fresh.push((Self::finding(id, "crash", sev, first, g.events.len() as u64, String::new(), data), newest.time));
        }
        emit(&json!({"t": "crashes", "groups": list}));
        self.apply(&["crash:".to_string()], fresh);
        let keep = self.cfg.history_days;
        let (_, day) = self.store.today(&today, keep);
        if day.crashes != today_count {
            day.crashes = today_count;
            self.store.dirty = true;
        }
    }

    // ── Packages and system ─────────────────────────────────────────────

    fn read_packages(&mut self) {
        if !has(&self.cfg, "packages") || self.pkg == packages::Manager::None {
            return;
        }
        let since = now_ms().saturating_sub(coredump::WINDOW_MS);
        let (events, txs) = packages::read_log(self.pkg, since);
        self.pkg_events = events;
        self.transactions = txs;
        let list: Vec<Value> = self
            .transactions
            .iter()
            .map(|t| json!({"time": t.time, "count": t.count, "names": t.names}))
            .collect();
        emit(&json!({"t": "updates", "transactions": list}));
    }

    fn scan_system(&mut self, deep: bool) {
        let now = now_ms();
        if has(&self.cfg, "packages") && self.pkg != packages::Manager::None {
            self.kernel = packages::kernel_state();
            let last = self
                .transactions
                .last()
                .map(|t| t.time)
                .or_else(|| self.pkg_events.last().map(|e| e.time))
                .or_else(|| {
                    // Older than the 7-day window: read the whole log once for its last line.
                    let (ev, _) = packages::read_log(self.pkg, 0);
                    ev.last().map(|e| e.time)
                });
            self.packages_info = json!({
                "manager": self.pkg.name(),
                "lastUpgrade": last,
                "orphans": packages::orphans(self.pkg),
                "pacnew": packages::pending_configs(self.pkg),
            });
            if deep || now.saturating_sub(self.deleted_at) >= 30 * 60 * 1000 {
                self.deleted_libs = packages::deleted_libs();
                self.deleted_at = now;
            }
        } else {
            self.kernel = packages::kernel_state();
            self.packages_info = json!({"manager": self.pkg.name(), "lastUpgrade": null, "orphans": [], "pacnew": []});
        }
        self.cleanup = packages::cleanup_sizes();
        if has(&self.cfg, "timesync") {
            self.check_time(deep);
        }
        self.publish_system();
    }

    fn check_time(&mut self, ask_ntp: bool) {
        if ask_ntp || self.ntp.is_none() {
            if let Some(conn) = &self.bus_sys {
                self.ntp = pressure::ntp_enabled(conn);
            }
        }
        self.synced_clock = pressure::clock_synced();
        if self.synced_clock {
            self.unsynced_checks = 0;
        } else {
            self.unsynced_checks += 1;
        }
    }

    fn publish_system(&mut self) {
        emit(&json!({
            "t": "system",
            "kernel": self.kernel,
            "packages": self.packages_info,
            "deletedLibs": self.deleted_libs,
            "fwupd": self.fwupd,
            "timesync": {"ntp": self.ntp, "synced": self.synced_clock},
            "cleanup": self.cleanup,
        }));
        let now = now_ms();
        let mut fresh = Vec::new();
        if has(&self.cfg, "packages") {
            if self.kernel["modulesPresent"] == json!(false) && !self.kernel["running"].as_str().unwrap_or("").is_empty() {
                let data = json!({"running": self.kernel["running"], "installed": self.kernel["installed"]});
                fresh.push((Self::finding("reboot:kernel".into(), "reboot", "warning", now, 1, String::new(), data), now));
            }
            if !self.deleted_libs.is_empty() {
                let data = json!({"processes": self.deleted_libs});
                fresh.push((Self::finding("deletedLibs".into(), "deletedLibs", "info", self.deleted_at, self.deleted_libs.len() as u64, String::new(), data), self.deleted_at));
            }
            let pacnew = self.packages_info["pacnew"].as_array().cloned().unwrap_or_default();
            if !pacnew.is_empty() {
                let data = json!({"files": pacnew});
                fresh.push((Self::finding("pacnew".into(), "pacnew", "info", now, pacnew.len() as u64, String::new(), data), now));
            }
        }
        if has(&self.cfg, "timesync") && self.unsynced_checks >= 2 {
            let data = json!({"ntp": self.ntp, "synced": self.synced_clock});
            fresh.push((Self::finding("timesync".into(), "timesync", "warning", now, 1, String::new(), data), now));
        }
        // Keep earlier "since" values: a finding that did not change must not be re-sent.
        for (f, _) in fresh.iter_mut() {
            if let Some(old) = self.findings.get(f["id"].as_str().unwrap_or("")) {
                f["since"] = old["since"].clone();
            }
        }
        self.apply(&["reboot:".into(), "deletedLibs".into(), "pacnew".into(), "timesync".into()], fresh);
    }

    fn start_fwupd(&mut self) {
        if !has(&self.cfg, "firmware") || !fwupd::available() || self.fwupd_pending {
            return;
        }
        self.fwupd_pending = true;
        let tx = self.tx.clone();
        let conn = self.bus_sys.clone();
        std::thread::spawn(move || {
            let _ = tx.send(Ev::Fwupd(fwupd::scan(conn.as_ref())));
        });
    }

    fn on_fwupd(&mut self, v: Value) {
        self.fwupd_pending = false;
        self.fwupd = v;
        let now = now_ms();
        let mut fresh = Vec::new();
        for u in self.fwupd["upgrades"].as_array().cloned().unwrap_or_default() {
            let dev = u["device"].as_str().unwrap_or("").to_string();
            let sev = if u["security"] == json!(true) { "warning" } else { "info" };
            fresh.push((Self::finding(format!("firmware:{dev}"), "firmware", sev, now, 1, String::new(), u), now));
        }
        let level = self.fwupd["hsiLevel"].as_u64();
        if self.fwupd["available"] == json!(true)
            && (level.is_some_and(|l| l < 2) || self.fwupd["runtimeIssue"] == json!(true))
        {
            fresh.push((Self::finding("security:hsi".into(), "security", "info", now, 1, String::new(), self.fwupd.clone()), now));
        }
        for (f, _) in fresh.iter_mut() {
            if let Some(old) = self.findings.get(f["id"].as_str().unwrap_or("")) {
                f["since"] = old["since"].clone();
            }
        }
        self.apply(&["firmware:".into(), "security:".into()], fresh);
        self.publish_system();
    }

    // ── Drives, filesystems, vitals ─────────────────────────────────────

    fn scan_drives(&mut self) {
        let Some(conn) = &self.udisks else { return };
        let drives = disks::scan(conn);
        self.drives_at = now_ms();
        emit(&json!({"t": "drives", "drives": drives}));
        let mut fresh = Vec::new();
        for d in drives {
            let (problems, sev) = disks::problems(&d);
            if problems.is_empty() {
                continue;
            }
            let mut data = d.clone();
            data["problems"] = json!(problems);
            let id = format!("drive:{}", d["id"].as_str().unwrap_or(""));
            fresh.push((Self::finding(id, "drive", sev, self.drives_at, 1, String::new(), data), self.drives_at));
        }
        for (f, _) in fresh.iter_mut() {
            if let Some(old) = self.findings.get(f["id"].as_str().unwrap_or("")) {
                f["since"] = old["since"].clone();
            }
        }
        self.apply(&["drive:".into()], fresh);
    }

    fn scan_fs(&mut self) {
        if !has(&self.cfg, "filesystems") {
            return;
        }
        let now = now_ms();
        self.fs_last = self.fs.sample(now);
        let mut fresh = Vec::new();
        for f in &self.fs_last {
            let used = f["usedPct"].as_f64().unwrap_or(0.0);
            let inodes = f["inodesPct"].as_f64().unwrap_or(0.0);
            let worst = used.max(inodes);
            let sev = if worst >= self.cfg.disk_crit {
                "critical"
            } else if worst >= self.cfg.disk_warn {
                "warning"
            } else {
                continue;
            };
            let id = format!("disk:{}", f["mount"].as_str().unwrap_or(""));
            let since = self.findings.get(&id).and_then(|o| o["since"].as_u64()).unwrap_or(now);
            fresh.push((Self::finding(id, "disk", sev, since, 1, String::new(), f.clone()), since));
        }
        self.apply(&["disk:".into()], fresh);
        if let Some(root) = self.fs_last.iter().find(|f| f["mount"] == "/").or(self.fs_last.first()) {
            let pct = root["usedPct"].as_f64().unwrap_or(0.0);
            let today = packages::local_date(now);
            let keep = self.cfg.history_days;
            let (_, day) = self.store.today(&today, keep);
            if (day.disk_pct - pct).abs() > 0.05 {
                day.disk_pct = pct;
                self.store.dirty = true;
            }
        }
    }

    fn vitals(&mut self) {
        let now = now_ms();
        let mut psi = serde_json::Map::new();
        let mut fresh = Vec::new();
        if has(&self.cfg, "pressure") {
            for res in ["memory", "io", "cpu"] {
                let Some(p) = pressure::read_psi(res) else { continue };
                psi.insert(res.to_string(), pressure::psi_json(&p));
                if res == "memory" {
                    self.psi_hist.push_back(p.some10);
                    while self.psi_hist.len() > 120 {
                        self.psi_hist.pop_front();
                    }
                    let today = packages::local_date(now);
                    let keep = self.cfg.history_days;
                    let (_, day) = self.store.today(&today, keep);
                    if p.some10 > day.psi_mem_peak {
                        day.psi_mem_peak = p.some10;
                        self.store.dirty = true;
                    }
                }
                let threshold = if res == "memory" { self.cfg.psi_mem } else { 40.0 };
                let key: &'static str = match res {
                    "memory" => "memory",
                    "io" => "io",
                    _ => "cpu",
                };
                let held = self.holds.entry(key).or_default().update(p.some60, threshold, now, 60_000);
                if held {
                    let id = format!("pressure:{res}");
                    let since = self.findings.get(&id).and_then(|o| o["since"].as_u64()).unwrap_or(now);
                    let top = if res == "memory" { pressure::top_rss() } else { Vec::new() };
                    let data = json!({"resource": res, "avg10": p.some10, "avg60": p.some60, "top": top});
                    fresh.push((Self::finding(id, "pressure", "warning", since, 1, String::new(), data), since));
                }
            }
            self.apply(&["pressure:".into()], fresh);
        }
        let mut throttle = json!({"total": 0, "last5min": 0});
        let mut temp = None;
        if has(&self.cfg, "thermals") {
            let (total, recent) = self.throttle.sample(now);
            throttle = json!({"total": total, "last5min": recent});
            temp = pressure::cpu_temp();
            if let Some(t) = temp {
                let keep = self.cfg.history_days;
                let (_, day) = self.store.today(&packages::local_date(now), keep);
                if t > day.cpu_temp_peak {
                    day.cpu_temp_peak = t;
                    self.store.dirty = true;
                }
            }
            let mut tf = Vec::new();
            if recent >= 20 {
                let id = "thermal:throttle".to_string();
                let since = self.findings.get(&id).and_then(|o| o["since"].as_u64()).unwrap_or(now);
                tf.push((Self::finding(id, "thermal", "warning", since, recent, String::new(),
                    json!({"events5min": recent, "total": total, "tempC": temp})), since));
            }
            self.apply(&["thermal:".into()], tf);
        }
        if has(&self.cfg, "shell") {
            self.check_shell_memory(now);
        }
        if has(&self.cfg, "shellLog") {
            self.check_shell_log(now);
        }
        emit(&json!({
            "t": "vitals",
            "psi": Value::Object(psi),
            "psiHistory": self.psi_hist.iter().collect::<Vec<_>>(),
            "throttle": throttle,
            "cpuTempC": temp,
            "fs": self.fs_last,
            "memory": pressure::memory(),
            "shellRss": self.shell_rss,
        }));
        // Unit failures count toward today's row as the worst seen.
        let failed = self.findings.values().filter(|f| f["kind"] == "unit").count() as u64;
        let today = packages::local_date(now);
        let keep = self.cfg.history_days;
        let (rolled, day) = self.store.today(&today, keep);
        if failed > day.failed {
            day.failed = failed;
            self.store.dirty = true;
        }
        if rolled {
            self.publish_history();
        }
    }

    /// The shell's resident memory, and `shellMemory` when it has stayed above the
    /// limit, or 600 MiB above its own first hour, for five minutes. Rounded to
    /// 50 MiB in the finding, so it is not re-sent on every small change.
    fn check_shell_memory(&mut self, now: u64) {
        const MIB: u64 = 1 << 20;
        let Some((pid, rss)) = shell::shell_rss() else {
            self.shell_rss = None;
            return;
        };
        self.shell_rss = Some(rss);
        if self.shell_first == 0 {
            self.shell_first = now;
        }
        let settled = now.saturating_sub(self.shell_first) >= 3_600_000;
        if !settled {
            self.shell_base = self.shell_base.max(rss);
        }
        let limit = self.cfg.shell_mem_mb * MIB;
        let grown = settled && self.shell_base > 0 && rss > self.shell_base + 600 * MIB;
        if rss > limit || grown {
            self.shell_high_since.get_or_insert(now);
        } else {
            self.shell_high_since = None;
        }
        let mut fresh = Vec::new();
        if let Some(since) = self.shell_high_since.filter(|s| now.saturating_sub(*s) >= 300_000) {
            let round = |b: u64| (b + 25 * MIB) / (50 * MIB) * 50;
            let data = json!({"pid": pid, "rssMb": round(rss), "baseMb": round(self.shell_base), "limitMb": self.cfg.shell_mem_mb, "grown": grown});
            fresh.push((Self::finding("shellMemory".into(), "shellMemory", "warning", since, 1, String::new(), data), since));
        }
        self.apply(&["shellMemory".into()], fresh);
    }

    /// `shellErrors`: QML errors the shell logged in the last hour, the follower
    /// started the first time (the shell is this helper's parent).
    fn check_shell_log(&mut self, now: u64) {
        if self.shell_log_child.is_none() {
            let Some((pid, _)) = shell::shell_rss() else { return };
            self.shell_log_child = shell::follow_log(pid, self.shell_log.clone());
        }
        let mut recent: Vec<(String, u64, u64)> = match self.shell_log.lock() {
            Ok(m) => m.iter().filter(|(_, v)| now.saturating_sub(v.1) <= 3_600_000).map(|(k, v)| (k.clone(), v.0, v.1)).collect(),
            Err(_) => return,
        };
        recent.sort_by(|a, b| b.1.cmp(&a.1));
        let mut fresh = Vec::new();
        if !recent.is_empty() {
            let since = self.findings.get("shellErrors").and_then(|o| o["since"].as_u64()).unwrap_or(now);
            let total: u64 = recent.iter().map(|r| r.1).sum();
            let top: Vec<Value> = recent.iter().take(5).map(|(k, n, _)| json!({"message": k, "count": n})).collect();
            fresh.push((Self::finding("shellErrors".into(), "shellErrors", "warning", since, recent.len() as u64, String::new(),
                json!({"errors": top, "kinds": recent.len(), "total": total})), since));
        }
        self.apply(&["shellErrors".into()], fresh);
    }

    // ── Hardware ────────────────────────────────────────────────────────

    /// Batteries, GPUs, memory, fans and this boot's hardware complaints: the
    /// `hardware` message, its findings, and today's history fields.
    fn scan_hardware(&mut self) {
        if !has(&self.cfg, "hardware") {
            return;
        }
        let now = now_ms();
        let (own, peripherals) = hw::batteries();
        let gpus = hw::gpus(&mut self.gpu_names);
        let edac = hw::edac();
        let (swap_total, swap_free, zram) = hw::swap();
        let fans = hw::fans();
        let events = hw::read_events();
        let temp = pressure::cpu_temp();
        emit(&json!({
            "t": "hardware",
            "batteries": own,
            "peripherals": peripherals,
            "gpus": gpus,
            "cpu": {"tempC": temp, "throttleTotal": pressure::throttle_total()},
            "memory": {"edac": edac.map(|(ce, ue)| json!({"ce": ce, "ue": ue})), "swapTotal": swap_total, "swapFree": swap_free, "zram": zram},
            "fans": fans,
            "events": events.json(),
        }));

        let keep_since = |s: &Self, id: &str| s.findings.get(id).and_then(|o| o["since"].as_u64()).unwrap_or(now);
        let mut fresh: Vec<(Value, u64)> = Vec::new();
        let mut push = |s: &Self, id: String, kind: &str, sev: &str, count: u64, data: Value| {
            let since = keep_since(s, &id);
            fresh.push((Self::finding(id, kind, sev, since, count, String::new(), data), since));
        };
        for b in &own {
            if let Some(h) = b["healthPct"].as_f64().filter(|h| *h < self.cfg.battery_wear) {
                let sev = if h < self.cfg.battery_wear - 20.0 { "critical" } else { "warning" };
                push(self, format!("battery:{}", b["name"].as_str().unwrap_or("")), "battery", sev, 1,
                    json!({"name": b["name"], "model": b["model"], "healthPct": h, "cycles": b["cycles"], "limit": self.cfg.battery_wear}));
            }
        }
        for p in &peripherals {
            let low = p["capacity"].as_f64().is_some_and(|c| c <= 15.0);
            let charging = p["status"].as_str().is_some_and(|s| s == "Charging" || s == "Full");
            if low && !charging {
                push(self, format!("peripheral:{}", p["name"].as_str().unwrap_or("")), "peripheralBattery", "info", 1, p.clone());
            }
        }
        let details = |k: &str| events.details.get(k).cloned().unwrap_or_default();
        let mce = events.count("mce");
        if mce > 0 {
            push(self, "mce".into(), "mce", "critical", mce, json!({"count": mce}));
        }
        let resets = events.count("gpu");
        if resets > 0 {
            push(self, "gpu:resets".into(), "gpu", if resets >= 3 { "critical" } else { "warning" }, resets,
                json!({"count": resets, "drivers": details("gpu"), "gpus": gpus}));
        }
        let oom = events.count("oom");
        if oom > 0 {
            push(self, "oom".into(), "oom", "warning", oom, json!({"count": oom, "killed": details("oom")}));
        }
        if let Some((ce, ue)) = edac.filter(|(ce, ue)| *ce > 0 || *ue > 0) {
            push(self, "edac".into(), "edac", if ue > 0 { "critical" } else { "info" }, ce + ue, json!({"ce": ce, "ue": ue}));
        }
        for (dev, n) in details("radioFw") {
            push(self, format!("radioFw:{dev}"), "radioFw", "warning", n, json!({"device": dev, "count": n}));
        }
        for (port, n) in details("usb").into_iter().filter(|(_, n)| *n >= 3) {
            push(self, format!("usb:{port}"), "usb", "info", n, json!({"port": port, "count": n}));
        }
        let fatal = events.count("aerFatal");
        if fatal > 0 {
            push(self, "pcie:fatal".into(), "aer", "critical", fatal, json!({"count": fatal, "fatal": true}));
        }
        let corrected = events.count("aer");
        if corrected >= 100 {
            push(self, "pcie:corrected".into(), "aer", "info", corrected, json!({"count": corrected, "fatal": false}));
        }
        let overheat = events.count("thermal");
        if overheat > 0 {
            push(self, "overheat".into(), "overheat", "warning", overheat, json!({"count": overheat, "tempC": temp}));
        }
        // A fan at 0 RPM while the CPU is at 80 °C or more, for two minutes.
        let stopped: Vec<Value> = fans.iter().filter(|f| f["rpm"].as_f64() == Some(0.0)).cloned().collect();
        if !stopped.is_empty() && temp.is_some_and(|t| t >= 80.0) {
            self.fan_hot_since.get_or_insert(now);
        } else {
            self.fan_hot_since = None;
        }
        if self.fan_hot_since.is_some_and(|s| now.saturating_sub(s) >= 120_000) {
            push(self, "fan:stopped".into(), "fan", "warning", stopped.len() as u64, json!({"fans": stopped, "tempC": temp}));
        }
        self.apply(
            &["battery:", "peripheral:", "mce", "gpu:", "oom", "edac", "radioFw:", "usb:", "pcie:", "overheat", "fan:"]
                .map(String::from),
            fresh,
        );

        // Today's history: the battery's health, and this boot's resets and kills.
        let keep = self.cfg.history_days;
        let (_, day) = self.store.today(&packages::local_date(now), keep);
        if let Some(h) = own.iter().filter_map(|b| b["healthPct"].as_f64()).reduce(f64::min) {
            day.battery_health_pct = h;
        }
        day.gpu_resets = day.gpu_resets.max(resets);
        day.oom_kills = day.oom_kills.max(oom);
        self.store.dirty = true;
    }

    // ── Rebuilds, helpers, boot ─────────────────────────────────────────

    /// Runs the rebuild scan on its own thread: the first one reads every foreign
    /// package's programs, which can take a few seconds.
    fn start_rebuild(&mut self) {
        self.rebuild_due = None;
        if !has(&self.cfg, "rebuild") || self.pkg != packages::Manager::Pacman || self.rebuild_running {
            return;
        }
        self.rebuild_running = true;
        // The app says "Checking again…" meanwhile, and when it last looked after.
        emit(&json!({"t": "rebuildScan", "running": true, "at": now_ms()}));
        let cache = self.rebuild_cache.clone();
        let tx = self.tx.clone();
        std::thread::spawn(move || {
            let list = match cache.lock() {
                Ok(mut c) => rebuild::scan(&mut c),
                Err(_) => Vec::new(),
            };
            let _ = tx.send(Ev::Rebuild(list));
        });
    }

    fn on_rebuild(&mut self, list: Vec<Value>) {
        self.rebuild_running = false;
        emit(&json!({"t": "rebuildScan", "running": false, "at": now_ms(), "count": list.len()}));
        let mut fresh = Vec::new();
        if !list.is_empty() {
            let now = now_ms();
            let since = self.findings.get("rebuild").and_then(|o| o["since"].as_u64()).unwrap_or(now);
            // Quickshell needing a rebuild can leave the shell unable to start.
            let sev = if list.iter().any(|p| p["reason"] == "quickshell") { "critical" } else { "warning" };
            let aur = ["yay", "paru"].into_iter().find(|h| proto::which(h)).unwrap_or("");
            let data = json!({"packages": list, "aurHelper": aur});
            fresh.push((Self::finding("rebuild".into(), "rebuild", sev, since, list.len() as u64, String::new(), data), since));
        }
        self.apply(&["rebuild".into()], fresh);
    }

    fn start_helpers(&mut self) {
        self.helpers_next = Instant::now() + Duration::from_secs(6 * 3600);
        if !has(&self.cfg, "shell") {
            return;
        }
        let tx = self.tx.clone();
        std::thread::spawn(move || {
            let list = shell::scripts_dir().map(|d| shell::stale_helpers(&d)).unwrap_or_default();
            let _ = tx.send(Ev::Helpers(list));
        });
    }

    fn on_helpers(&mut self, list: Vec<Value>) {
        let now = now_ms();
        let fresh = list
            .into_iter()
            .filter_map(|h| {
                let name = h["name"].as_str()?.to_string();
                let id = format!("shellHelper:{name}");
                let since = self.findings.get(&id).and_then(|o| o["since"].as_u64()).unwrap_or(now);
                Some((Self::finding(id, "shellHelper", "warning", since, 1, String::new(), json!({"name": name})), since))
            })
            .collect();
        self.apply(&["shellHelper:".into()], fresh);
    }

    /// This boot's timing, once it has finished; tried again every minute for a
    /// quarter of an hour when it has not.
    fn record_boot(&mut self) {
        self.boot_due = None;
        if !has(&self.cfg, "boot") {
            return;
        }
        let Some(sys) = self.bus_sys.clone() else { return };
        let Some(mut t) = boot::times(&sys, self.bus_user.as_ref()) else {
            self.boot_tries += 1;
            if self.boot_tries < 15 {
                self.boot_due = Some(Instant::now() + Duration::from_secs(60));
            }
            return;
        };
        let now = now_ms();
        let uptime_ms = std::fs::read_to_string("/proc/uptime")
            .ok()
            .and_then(|s| s.split_whitespace().next()?.parse::<f64>().ok())
            .map(|s| (s * 1000.0) as u64)
            .unwrap_or(0);
        let total = t["total"].as_u64().unwrap_or(0);
        t["boot"] = json!(self.boot);
        t["at"] = json!(now.saturating_sub(uptime_ms));
        t["top"] = boot::blame(10).into_iter().map(|(unit, ms)| json!({"unit": unit, "ms": ms})).collect();
        if self.store.remember_boot(t) {
            let keep = self.cfg.history_days;
            let (_, day) = self.store.today(&packages::local_date(now), keep);
            day.boot_ms = total;
        }
        emit(&json!({"t": "boot", "boots": self.store.state.boots}));
        let mut fresh = Vec::new();
        if let Some(data) = boot::slow(&self.store.state.boots) {
            fresh.push((Self::finding("slowBoot".into(), "slowBoot", "info", now, 1, String::new(), data), now));
        }
        self.apply(&["slowBoot".into()], fresh);
    }

    fn publish_history(&mut self) {
        emit(&json!({"t": "history", "days": self.store.days}));
    }

    fn dump_access_state(&self) -> String {
        let out = proto::run("getfacl", &["-p", "--omit-header", "/var/lib/systemd/coredump"]).unwrap_or_default();
        dump_access_from_acl(&out, &self.user).to_string()
    }

    // ── Startup ─────────────────────────────────────────────────────────

    fn ready(&mut self) {
        self.pkg = packages::Manager::detect();
        self.dump_access = self.dump_access_state();
        self.bus_sys = zbus::blocking::Connection::system().ok();
        if has(&self.cfg, "userUnits") {
            self.bus_user = zbus::blocking::Connection::session().ok();
        }
        if has(&self.cfg, "drives") {
            self.udisks = self.bus_sys.clone().filter(disks::available);
        }
        self.connect_units();
        self.journal_access = if has(&self.cfg, "journal") || has(&self.cfg, "crashes") { journal::access() } else { "none" };
        let src = |k: &str| has(&self.cfg, k);
        emit(&json!({
            "t": "ready",
            "version": 1,
            "stateDir": self.cfg.state_dir.to_string_lossy(),
            "sources": {
                "units": self.sys.is_some(),
                "userUnits": self.usr.is_some(),
                "appLaunches": src("appLaunches") && (self.sys.is_some() || self.usr.is_some()),
                "crashes": src("crashes") && self.journal_access != "none",
                "journal": if src("journal") { self.journal_access } else { "none" },
                "drives": self.udisks.is_some(),
                "filesystems": src("filesystems"),
                "firmware": src("firmware") && fwupd::available(),
                "packages": if src("packages") { self.pkg.name() } else { "none" },
                "pressure": src("pressure") && std::path::Path::new("/proc/pressure/memory").exists(),
                "thermals": src("thermals") && (pressure::throttle_supported() || pressure::cpu_temp().is_some()),
                "timesync": src("timesync"),
                "rebuild": src("rebuild") && self.pkg == packages::Manager::Pacman,
                "shell": src("shell"),
                "boot": src("boot") && self.bus_sys.is_some(),
                "hardware": src("hardware"),
            },
            "dumpAccess": self.dump_access,
            "user": self.user,
            "bootId": self.boot,
        }));
    }

    fn initial_scan(&mut self) {
        let now = now_ms();
        let date = packages::local_date(now);
        let keep = self.cfg.history_days;
        self.store.today(&date, keep);
        if self.sys.is_some() {
            self.scan_units(Scope::System);
        }
        if self.usr.is_some() {
            self.scan_units(Scope::User);
        }
        self.read_packages();
        if has(&self.cfg, "packages") && !self.cfg.once {
            packages::watch_log(self.pkg, self.tx.clone());
        }
        if has(&self.cfg, "crashes") && self.journal_access != "none" {
            self.load_crashes();
            self.publish_crashes();
        }
        if has(&self.cfg, "journal") {
            self.start_journal();
        }
        if self.udisks.is_some() {
            self.scan_drives();
        }
        self.scan_fs();
        self.scan_system(true);
        self.record_boot();
        self.scan_hardware();
        self.vitals();
        // After every source has filled today's row.
        self.publish_history();
        self.publish_resolved();
        if !self.cfg.once {
            // Off the start's critical path: the first scan reads many files.
            self.rebuild_due = Some(Instant::now() + Duration::from_secs(10));
            self.start_helpers();
        }
        if has(&self.cfg, "firmware") && fwupd::available() {
            if self.cfg.once {
                let v = fwupd::scan(self.bus_sys.as_ref());
                self.on_fwupd(v);
            } else {
                self.start_fwupd();
                self.sync_deadline = Some(Instant::now() + Duration::from_secs(30));
            }
        }
        if !self.fwupd_pending {
            self.mark_synced();
        }
    }

    fn mark_synced(&mut self) {
        self.sync_deadline = None;
        if !self.synced {
            self.synced = true;
        }
        emit(&json!({"t": "synced"}));
    }

    fn rescan(&mut self) {
        if self.sys.is_some() {
            self.scan_units(Scope::System);
        }
        if self.usr.is_some() {
            self.scan_units(Scope::User);
        }
        self.read_packages();
        if has(&self.cfg, "crashes") && self.journal_access != "none" {
            self.load_crashes();
            self.publish_crashes();
        }
        self.flush_journal();
        self.scan_drives();
        self.scan_fs();
        self.scan_system(true);
        // "Check now" covers everything the pages show, the hardware cards included.
        self.scan_hardware();
        self.vitals();
        self.dump_access = self.dump_access_state();
        emit(&json!({"t": "access", "dumpAccess": self.dump_access}));
        self.start_fwupd();
        self.start_rebuild();
        self.start_helpers();
        self.mark_synced();
    }

    // ── stdin ───────────────────────────────────────────────────────────

    fn reply_ok(req: &Value, data: Value) {
        emit(&json!({"t": "reply", "req": req, "ok": true, "data": data}));
    }

    fn reply_err(req: &Value, code: &str, message: &str) {
        emit(&json!({"t": "reply", "req": req, "ok": false, "error": code, "message": message}));
    }

    fn on_stdin(&mut self, line: &str) -> bool {
        let Ok(msg) = serde_json::from_str::<Value>(line) else {
            log("warn", format!("bad stdin line: {}", line.chars().take(120).collect::<String>()));
            return true;
        };
        let t = msg["t"].as_str().unwrap_or("");
        let s = |k: &str| msg[k].as_str().unwrap_or("").to_string();
        let req = msg["req"].clone();
        match t {
            "visible" => {
                let v = msg["app"].as_bool().unwrap_or(false);
                if v && !self.visible {
                    self.vitals_next = Instant::now();
                    self.hardware_next = Instant::now();
                    if now_ms().saturating_sub(self.drives_at) > 60_000 {
                        self.scan_drives();
                    }
                }
                self.visible = v;
            }
            "rescan" => self.rescan(),
            "query" => self.on_query(&msg),
            "act" => self.on_act(&msg),
            "mute" | "unmute" | "markKnown" => {
                let fp = s("fp");
                if fp.is_empty() {
                    return true;
                }
                let rec = self.store.state.fingerprints.entry(fp).or_default();
                match t {
                    "mute" => rec.muted = true,
                    "unmute" => rec.muted = false,
                    _ => rec.known = true,
                }
                self.store.dirty = true;
                self.flush_journal();
                self.refresh_muted();
            }
            "muteProgram" | "unmuteProgram" => {
                let exe = s("exe");
                self.store.state.muted_programs.retain(|p| p != &exe);
                if t == "muteProgram" && !exe.is_empty() {
                    self.store.state.muted_programs.push(exe);
                }
                self.store.dirty = true;
                self.publish_crashes();
                self.refresh_muted();
            }
            "dismiss" => {
                let id = s("id");
                if id.is_empty() {
                    return true;
                }
                self.store.state.dismissed.insert(id.clone(), now_ms());
                self.store.dirty = true;
                if id.starts_with("crash:") {
                    self.publish_crashes();
                } else if let Some(rest) = id.strip_prefix("app:") {
                    let scope = if rest.starts_with("system:") { Scope::System } else { Scope::User };
                    self.scan_units(scope);
                } else if self.findings.remove(&id).is_some() {
                    emit(&json!({"t": "finding", "op": "resolve", "id": id}));
                }
            }
            "snooze" | "unsnooze" => {
                let id = s("id");
                if id.is_empty() {
                    return true;
                }
                if t == "snooze" {
                    let snooze = if msg["untilBoot"].as_bool() == Some(true) {
                        store::Snooze { until: 0, boot: Some(self.boot.clone()) }
                    } else {
                        let until = msg["until"].as_u64().unwrap_or(0);
                        if until <= now_ms() {
                            return true;
                        }
                        store::Snooze { until, boot: None }
                    };
                    self.store.state.snoozed.insert(id, snooze);
                } else {
                    self.store.state.snoozed.remove(&id);
                }
                self.store.dirty = true;
                self.refresh_muted();
            }
            "resetNoise" => {
                self.store.reset_noise();
                if self.journal_access != "none" {
                    self.build_baseline();
                }
                self.flush_journal();
                self.publish_crashes();
                self.refresh_muted();
                if self.sys.is_some() {
                    self.scan_units(Scope::System);
                }
                if self.usr.is_some() {
                    self.scan_units(Scope::User);
                }
            }
            "quit" => return false,
            _ => {
                if !req.is_null() {
                    Self::reply_err(&req, "unknown", t);
                }
            }
        }
        true
    }

    fn on_query(&mut self, msg: &Value) {
        let req = msg["req"].clone();
        let s = |k: &str| msg[k].as_str().unwrap_or("").to_string();
        let n = |k: &str, d: i64| msg[k].as_i64().unwrap_or(d);
        match msg["what"].as_str().unwrap_or("") {
            "unitLog" => {
                let unit = s("unit");
                if unit.is_empty() || unit.starts_with('-') {
                    return Self::reply_err(&req, "args", "unit");
                }
                let lines = journal::unit_log(s("scope") == "user", &unit, n("lines", 40).clamp(1, 200) as u32);
                Self::reply_ok(&req, json!({"lines": lines}));
            }
            "crashInfo" => {
                let exe = s("exe");
                match journal::crash_info(&exe) {
                    Some(v) => Self::reply_ok(&req, v),
                    None => Self::reply_err(&req, "not-found", &exe),
                }
            }
            "journalGroup" => {
                let fp = s("fp");
                let lines = journal::group_lines(&fp, n("lines", 20).clamp(1, 100) as u32, &self.home);
                Self::reply_ok(&req, json!({"lines": lines}));
            }
            "journalSearch" => {
                let q = journal::Search {
                    unit: s("unit"),
                    identifier: s("identifier"),
                    grep: s("grep"),
                    priority: n("priority", 3),
                    since_hours: n("sinceHours", 24),
                    limit: n("limit", 40),
                };
                if q.unit.starts_with('-') || q.identifier.starts_with('-') {
                    return Self::reply_err(&req, "args", "unit");
                }
                match journal::search(&q) {
                    Ok(lines) => Self::reply_ok(&req, json!({"lines": lines})),
                    Err((code, m)) => Self::reply_err(&req, &code, &m),
                }
            }
            "package" => {
                let path = s("path");
                match packages::owner(self.pkg, &path) {
                    Some((name, version)) => Self::reply_ok(&req, json!({"name": name, "version": version})),
                    None => Self::reply_err(&req, "not-found", &path),
                }
            }
            other => Self::reply_err(&req, "unknown", other),
        }
    }

    fn on_act(&mut self, msg: &Value) {
        let req = msg["req"].clone();
        let verb = msg["verb"].as_str().unwrap_or("").to_string();
        if verb == "selftest" {
            let Some(conn) = self.udisks.clone() else { return Self::reply_err(&req, "udisks", "unavailable") };
            let path = msg["drive"].as_str().unwrap_or("").to_string();
            let tx = self.tx.clone();
            std::thread::spawn(move || {
                let r = match disks::selftest(&conn, &path) {
                    Ok(()) => json!({"t": "reply", "req": req, "ok": true, "data": {}}),
                    Err((c, m)) => json!({"t": "reply", "req": req, "ok": false, "error": c, "message": m}),
                };
                let _ = tx.send(Ev::Reply(r));
            });
            return;
        }
        let Some(scope) = Scope::parse(msg["scope"].as_str().unwrap_or("")) else {
            return Self::reply_err(&req, "args", "scope");
        };
        let unit = msg["unit"].as_str().unwrap_or("").to_string();
        if unit.is_empty() {
            return Self::reply_err(&req, "args", "unit");
        }
        // Remembered for "Fixed recently": a finding that resolves soon after was
        // fixed by this.
        self.last_act.insert(format!("{}:{}", scope.name(), unit), (verb.clone(), now_ms()));
        // Each act runs on its own thread: a polkit prompt can hold the call for as
        // long as the user takes to answer, and the loop must not wait on it.
        let conn = match scope {
            Scope::System => self.bus_sys.clone(),
            Scope::User => self.bus_user.clone(),
        };
        let tx = self.tx.clone();
        std::thread::spawn(move || {
            // A bare manager, not `connect`: the scan already subscribed on this
            // shared connection, and systemd refuses a second Subscribe from it.
            let r = match conn.map(|c| Manager { scope, conn: c }) {
                None => json!({"t": "reply", "req": req, "ok": false, "error": "dbus", "message": "manager unavailable"}),
                Some(m) => match m.act(&verb, &unit) {
                    Ok(()) => json!({"t": "reply", "req": req, "ok": true, "data": {}}),
                    Err((c, msg)) => json!({"t": "reply", "req": req, "ok": false, "error": c, "message": msg}),
                },
            };
            let _ = tx.send(Ev::Reply(r));
            let _ = tx.send(Ev::Rescan(scope));
        });
    }

    // ── Loop ────────────────────────────────────────────────────────────

    fn next_deadline(&self) -> Instant {
        let mut d = self.vitals_next.min(self.fs_next).min(self.drives_next).min(self.fwupd_next).min(self.system_next)
            .min(self.time_next).min(self.save_next).min(self.helpers_next).min(self.hardware_next);
        for t in self.units_due.values() {
            d = d.min(*t);
        }
        for t in [self.pkg_due, self.journal_flush_due, self.journal_restart, self.sync_deadline, self.rebuild_due, self.boot_due]
            .into_iter()
            .flatten()
        {
            d = d.min(t);
        }
        d
    }

    fn run_timers(&mut self) {
        let now = Instant::now();
        let due: Vec<Scope> = self.units_due.iter().filter(|(_, t)| **t <= now).map(|(s, _)| *s).collect();
        for s in due {
            self.units_due.remove(&s);
            self.units_first.remove(&s);
            self.scan_units(s);
        }
        if self.pkg_due.is_some_and(|t| t <= now) {
            self.pkg_due = None;
            self.read_packages();
            self.owner_cache.clear();
            self.publish_crashes();
            self.scan_system(true);
            // After a transaction: what it installed may need others rebuilt.
            self.start_rebuild();
        }
        if self.rebuild_due.is_some_and(|t| t <= now) {
            self.start_rebuild();
        }
        if self.boot_due.is_some_and(|t| t <= now) {
            self.record_boot();
        }
        if self.hardware_next <= now {
            self.scan_hardware();
            self.hardware_next = now + Duration::from_secs(if self.visible { 10 } else { 60 });
        }
        if self.helpers_next <= now {
            self.start_helpers();
        }
        if self.journal_flush_due.is_some_and(|t| t <= now) {
            self.flush_journal();
        }
        if self.journal_restart.is_some_and(|t| t <= now) {
            self.journal_restart = None;
            self.follower = journal::follow(self.journal_cursor.as_deref(), self.tx.clone());
        }
        if self.sync_deadline.is_some_and(|t| t <= now) {
            self.mark_synced();
        }
        if self.vitals_next <= now {
            self.vitals();
            self.vitals_next = now + Duration::from_secs(if self.visible { 2 } else { 15 });
        }
        if self.fs_next <= now {
            self.scan_fs();
            self.fs_next = now + Duration::from_secs(60);
        }
        if self.drives_next <= now {
            self.scan_drives();
            self.drives_next = now + Duration::from_secs(600);
        }
        if self.fwupd_next <= now {
            self.start_fwupd();
            self.fwupd_next = now + Duration::from_secs(6 * 3600);
        }
        if self.system_next <= now {
            self.scan_system(false);
            self.system_next = now + Duration::from_secs(1800);
        }
        if self.time_next <= now {
            if has(&self.cfg, "timesync") {
                let before = (self.synced_clock, self.unsynced_checks >= 2);
                self.check_time(false);
                if before != (self.synced_clock, self.unsynced_checks >= 2) {
                    self.publish_system();
                }
            }
            self.time_next = now + Duration::from_secs(300);
        }
        if self.save_next <= now {
            self.expire_snoozes();
            self.store.prune(now_ms());
            self.store.save();
            // Queries and rescans read journal output in bulk; give it back.
            unsafe {
                libc::malloc_trim(0);
            }
            self.save_next = now + Duration::from_secs(60);
        }
    }

    fn handle(&mut self, ev: Ev) -> bool {
        match ev {
            Ev::Stdin(line) => return self.on_stdin(&line),
            Ev::StdinClosed => return false,
            Ev::Units(scope) | Ev::Rescan(scope) => {
                let now = Instant::now();
                let first = *self.units_first.entry(scope).or_insert(now);
                // Debounced, but never starved by a unit that keeps changing.
                let at = (now + Duration::from_millis(500)).min(first + Duration::from_secs(2));
                self.units_due.insert(scope, at);
            }
            Ev::Journal(e) => self.on_journal(e),
            Ev::JournalDied => {
                self.follower = None;
                self.journal_restart = Some(Instant::now() + Duration::from_secs(5));
            }
            Ev::PackageLog => {
                self.pkg_due = Some(Instant::now() + Duration::from_secs(5));
            }
            Ev::Fwupd(v) => {
                self.on_fwupd(v);
                if !self.synced || self.sync_deadline.is_some() {
                    self.mark_synced();
                }
            }
            Ev::Reply(v) => emit(&v),
            Ev::Rebuild(list) => self.on_rebuild(list),
            Ev::Helpers(list) => self.on_helpers(list),
        }
        true
    }
}

/// "granted" when both the access and the default ACL give `user` read.
fn dump_access_from_acl(acl: &str, user: &str) -> &'static str {
    if user.is_empty() {
        return "denied";
    }
    let access = format!("user:{user}:r");
    let default = format!("default:user:{user}:r");
    let has_access = acl.lines().any(|l| l.trim().starts_with(&access));
    let has_default = acl.lines().any(|l| l.trim().starts_with(&default));
    if has_access && has_default { "granted" } else { "denied" }
}

fn spawn_stdin(tx: Sender<Ev>) {
    std::thread::spawn(move || {
        let stdin = std::io::stdin();
        for line in stdin.lock().lines() {
            let Ok(line) = line else { break };
            let line = line.trim().to_string();
            if line.is_empty() {
                continue;
            }
            if tx.send(Ev::Stdin(line)).is_err() {
                return;
            }
        }
        let _ = tx.send(Ev::StdinClosed);
    });
}

fn run_loop(app: &mut App, rx: Receiver<Ev>) {
    loop {
        let wait = app.next_deadline().saturating_duration_since(Instant::now());
        match rx.recv_timeout(wait) {
            Ok(ev) => {
                if !app.handle(ev) {
                    break;
                }
                // Drain whatever else is queued before running timers.
                while let Ok(ev) = rx.try_recv() {
                    if !app.handle(ev) {
                        app.store.dirty = true;
                        app.store.save();
                        return;
                    }
                }
            }
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => break,
        }
        app.run_timers();
    }
    app.store.dirty = true;
    app.store.save();
}

fn main() {
    // One malloc arena: a dozen mostly idle threads would otherwise each keep
    // their own, and the helper's resident size is mostly that slack.
    unsafe {
        libc::mallopt(libc::M_ARENA_MAX, 1);
    }
    let cfg = parse_args();
    let (tx, rx) = channel();
    let once = cfg.once;
    let mut app = App::new(cfg, tx.clone());
    app.ready();
    if !once {
        spawn_stdin(tx);
    }
    app.initial_scan();
    // The start reads whole boots of journal into memory once; hand that back.
    unsafe {
        libc::malloc_trim(0);
    }
    if once {
        app.store.dirty = true;
        app.store.save();
        return;
    }
    run_loop(&mut app, rx);
    drop(app.follower.take());
    if let Some(mut child) = app.shell_log_child.take() {
        let _ = child.kill();
        let _ = child.wait();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn acl_parsing() {
        let granted = "user::rwx\nuser:scrimas:r-x\ngroup::r-x\nmask::r-x\nother::r-x\ndefault:user::rwx\ndefault:user:scrimas:r--\ndefault:group::r-x\n";
        assert_eq!(dump_access_from_acl(granted, "scrimas"), "granted");
        assert_eq!(dump_access_from_acl("user::rwx\ngroup::r-x\nother::r-x\n", "scrimas"), "denied");
        assert_eq!(dump_access_from_acl("user:scrimas:r-x\n", "scrimas"), "denied");
        assert_eq!(dump_access_from_acl(granted, "scrima"), "denied");
    }

    /// An App on a throwaway state dir; its events go nowhere.
    fn test_app(tag: &str) -> (App, PathBuf) {
        let dir = std::env::temp_dir().join(format!("health_app_{tag}_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let mut cfg = parse_args();
        cfg.state_dir = dir.clone();
        let (tx, _rx) = channel();
        let mut app = App::new(cfg, tx);
        app.synced = true;
        (app, dir)
    }

    fn unit_finding(name: &str) -> Value {
        let id = format!("unit:user:{name}");
        App::finding(id.clone(), "unit", "critical", 1, 1, id, json!({"scope": "user", "unit": name}))
    }

    #[test]
    fn snoozed_findings_do_not_alert_and_wake_up() {
        let (mut app, dir) = test_app("snooze");
        let id = "unit:user:a.service".to_string();
        let until = now_ms() + 60_000;
        app.store.state.snoozed.insert(id.clone(), store::Snooze { until, boot: None });
        app.apply(&["unit:user:".into()], vec![(unit_finding("a.service"), 1)]);
        assert_eq!(app.findings[&id]["snoozed"], json!(until));
        assert!(app.store.state.alerted.is_empty(), "a snoozed finding alerted");

        // Run out: the flag goes, the finding stays.
        app.store.state.snoozed.insert(id.clone(), store::Snooze { until: 1, boot: None });
        app.expire_snoozes();
        assert!(app.store.state.snoozed.is_empty());
        assert!(app.findings[&id]["snoozed"].is_null());

        // "Until restart" holds for this boot only.
        let s = store::Snooze { until: 0, boot: Some(app.boot.clone()) };
        assert!(s.active(now_ms(), &app.boot));
        assert!(!s.active(now_ms(), "another-boot"));

        // An unsnoozed critical finding seen for the first time does alert.
        app.apply(&["unit:user:".into()], vec![(unit_finding("a.service"), 1), (unit_finding("b.service"), 1)]);
        assert!(app.store.state.alerted.contains_key("unit:user:b.service"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn fixed_recently_says_what_fixed_it() {
        let (mut app, dir) = test_app("resolved");
        let prefix = vec!["unit:user:".to_string()];
        app.apply(&prefix, vec![(unit_finding("a.service"), 1), (unit_finding("b.service"), 1), (unit_finding("c.service"), 1)]);
        // The user restarted a; b recovers on its own; c was dismissed.
        app.last_act.insert("user:a.service".into(), ("restart".into(), now_ms()));
        app.store.state.dismissed.insert("unit:user:c.service".into(), now_ms());
        app.apply(&prefix, vec![]);
        fn by(app: &App, id: &str) -> Option<Value> {
            app.store.state.resolved.iter().find(|r| r["id"] == id).map(|r| r["by"].clone())
        }
        assert_eq!(by(&app, "unit:user:a.service"), Some(json!("restart")));
        assert_eq!(by(&app, "unit:user:b.service"), Some(json!("self")));
        assert_eq!(by(&app, "unit:user:c.service"), None, "a dismissed finding is not a fix");

        // Crashes ageing out are not fixes either.
        let crash = App::finding("crash:/usr/bin/x".into(), "crash", "warning", 1, 1, String::new(), json!({"exe": "/usr/bin/x"}));
        app.apply(&["crash:".into()], vec![(crash, 1)]);
        app.apply(&["crash:".into()], vec![]);
        assert_eq!(by(&app, "crash:/usr/bin/x"), None);

        // An action long before the fix does not claim it.
        app.apply(&prefix, vec![(unit_finding("d.service"), 1)]);
        app.last_act.insert("user:d.service".into(), ("restart".into(), now_ms() - 600_000));
        app.apply(&prefix, vec![]);
        assert_eq!(by(&app, "unit:user:d.service"), Some(json!("self")));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn rebuild_finding_severity() {
        let (mut app, dir) = test_app("rebuild");
        app.on_rebuild(vec![json!({"name": "thor-git", "reason": "lib", "foreign": true, "libs": ["libsfml-graphics.so.2.6"]})]);
        assert_eq!(app.findings["rebuild"]["sev"], "warning");
        app.on_rebuild(vec![json!({"name": "quickshell", "reason": "quickshell", "foreign": false})]);
        assert_eq!(app.findings["rebuild"]["sev"], "critical", "Quickshell can keep the shell from starting");
        app.on_rebuild(vec![]);
        assert!(!app.findings.contains_key("rebuild"));
        let _ = std::fs::remove_dir_all(&dir);
    }
}
