//! Per-app usage and energy sampler for the Quickshell `ii` shell.
//!
//! Window state is event-driven (Hyprland's socket2), counters are polled every
//! `--interval-ms`. That split is what makes a window switch exact while the
//! expensive work still happens only six times a minute.
//!
//! Runs standalone: `./app_stats` prints one NDJSON object per sample on stdout and
//! writes an hourly history under the state directory. Reads no privileged file —
//! RAPL access comes from the udev rule, never from sudo.
//!
//! Input protocol, one JSON object per line on stdin:
//!   {"t":"state","locked":true,"idle":false,"dpms":"off"}   screen state changed
//!   {"t":"flush"}                                           write the day file now
//!   {"t":"quit"}                                            flush and exit
//!
//! Output protocol, one JSON object per line on stdout:
//!   {"t":"ready",...}     startup: energy source, paths, interval
//!   {"t":"sample",...}    per-interval deltas for every tracked app
//!   {"t":"flush",...}     a day file was written

mod battery;
mod energy;
mod exact;
mod gpu;
mod hypr;
mod net;
mod procs;
mod store;

use std::collections::{HashMap, HashSet};
use std::env;
use std::io::{BufRead, Write};
use std::path::PathBuf;
use std::sync::mpsc::{channel, Sender};
use std::thread;
use std::time::Duration;

/// The device itself rather than any one app. Carries two things no application
/// row can: the energy attributed to nothing — idle package draw, kernel threads,
/// display and radios, reported as its own row rather than normalised away, since
/// the size of that residual is the honest measure of how far to trust the rest —
/// and, in `fg_ms`, screen time counted once no matter how many windows were up.
const SYSTEM_KEY: &str = "__system";


pub enum Msg {
    WindowsChanged,
    SocketClosed(net::Sock),
    Stdin(String),
    Tick,
    Shutdown,
}

struct Args {
    interval_ms: u64,
    flush_ms: u64,
    retention_days: i64,
    /// Whether `retention_days` is exact or a floor under the previous calendar month.
    retention_mode: store::Retention,
    state_dir: PathBuf,
    energy_source: String,
    track_headless: bool,
    /// Sample intervals between full `/proc` sweeps for new GPU clients. Only a
    /// backstop — a new window triggers one immediately, and that is how a newly
    /// launched app is normally picked up.
    gpu_full_every: u32,
    /// Per-app TCP data, from the socket diagnostics dump. Off skips the dump and
    /// the fd walk entirely.
    track_network: bool,
    /// The eBPF helper to try first; without it the socket counters are used.
    net_helper: String,
    quiet: bool,
}

fn default_state_dir() -> PathBuf {
    let base = env::var("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            PathBuf::from(env::var("HOME").unwrap_or_else(|_| "/tmp".into())).join(".local/state")
        });
    base.join("quickshell/user/app_stats")
}

impl Args {
    fn parse() -> Args {
        let mut a = Args {
            interval_ms: 10_000,
            flush_ms: 60_000,
            retention_days: 30,
            retention_mode: store::Retention::Fixed,
            state_dir: default_state_dir(),
            energy_source: "auto".into(),
            track_headless: true,
            gpu_full_every: 30,
            track_network: true,
            net_helper: exact::DEFAULT_PATH.into(),
            quiet: false,
        };

        let argv: Vec<String> = env::args().skip(1).collect();
        let mut i = 0;
        while i < argv.len() {
            let (key, inline) = match argv[i].split_once('=') {
                Some((k, v)) => (k.to_string(), Some(v.to_string())),
                None => (argv[i].clone(), None),
            };
            let mut value = || {
                inline.clone().unwrap_or_else(|| {
                    i += 1;
                    argv.get(i).cloned().unwrap_or_default()
                })
            };
            match key.as_str() {
                "--interval-ms" => a.interval_ms = value().parse().unwrap_or(a.interval_ms),
                "--flush-ms" => a.flush_ms = value().parse().unwrap_or(a.flush_ms),
                "--retention-days" => {
                    a.retention_days = value().parse().unwrap_or(a.retention_days)
                }
                "--retention-mode" => a.retention_mode = store::Retention::parse(&value()),
                "--state-dir" => a.state_dir = PathBuf::from(value()),
                "--energy" => a.energy_source = value(),
                "--gpu-full-every" => {
                    a.gpu_full_every = value().parse().unwrap_or(a.gpu_full_every)
                }
                "--no-headless" => a.track_headless = false,
                "--no-network" => a.track_network = false,
                "--net-helper" => a.net_helper = value(),
                "--quiet" => a.quiet = true,
                _ => {}
            }
            i += 1;
        }
        a.interval_ms = a.interval_ms.max(1000);
        a
    }
}

fn emit(v: &serde_json::Value) {
    let mut out = std::io::stdout().lock();
    let _ = writeln!(out, "{v}");
    let _ = out.flush();
}

/// Boot-relative time in clock ticks, used to tell a process that started after the
/// sampler from one that was already running when it began.
fn uptime_ticks(clk_tck: u64) -> u64 {
    let secs = std::fs::read_to_string("/proc/uptime")
        .ok()
        .and_then(|s| s.split_whitespace().next()?.parse::<f64>().ok())
        .unwrap_or(0.0);
    (secs * clk_tck as f64) as u64
}

#[derive(Default)]
struct AppState {
    exe: String,
    headless: bool,
    visible: bool,
    focused: bool,
    alive: bool,
    was_fg: bool,
    /// Foreground and background milliseconds within the current sample interval,
    /// used to split that interval's energy. Reset every tick.
    d_fg_ms: u64,
    d_bg_ms: u64,
}

/// A window on screen only counts as foreground while there is a screen to see it
/// on; a headless process never does.
fn effective_fg(app: &AppState, blocked: bool) -> bool {
    app.visible && !app.headless && !blocked
}

struct Tracker {
    args: Args,
    store: store::Store,
    energy: energy::Reader,
    battery: battery::Reader,
    apps: HashMap<String, AppState>,
    known_classes: HashSet<String>,
    /// Whether the window layout has been read at least once. Until it has, an
    /// unfamiliar class is one that was already open, not one that just launched.
    seen_windows: bool,
    /// Last known window list. Refreshed from Hyprland on every event that can
    /// change it, so polling it again each tick would only cost the compositor two
    /// extra serialisations of the whole client list on its own thread.
    clients: Vec<(u32, String)>,

    locked: bool,
    idle: bool,
    dpms_off: bool,

    /// Mains and charge state as of the last tick. The accrual loop credits time
    /// against these, so a cable pulled between two ticks moves at most one
    /// interval of time into the wrong one of the three.
    bat_on_ac: bool,
    bat_charging: bool,

    last_accrual_ms: i64,
    last_tick_ms: i64,
    last_flush_ms: i64,

    prev_busy: u64,
    prev_cpu: HashMap<(u32, u64), u64>,
    prev_gpu: HashMap<(String, u64), u64>,
    prev_gpu_total: u64,
    gpu_fds: HashMap<u32, Vec<u32>>,
    ticks_since_full_gpu: u32,
    gpu_rescan_pending: bool,

    /// Last cumulative (rx, tx) of every socket of ours still alive, by cookie.
    prev_net: HashMap<u64, (u64, u64)>,
    /// The app each socket was matched to when first seen, by cookie; empty when its
    /// process is not one the sampler tracks. Only a socket not in here costs an fd
    /// walk, so a long-lived connection is looked up once.
    sock_key: HashMap<u64, String>,
    /// Final bytes of sockets freed since the last tick, by app, from the kernel's
    /// destroy broadcast.
    closed_tail: HashMap<String, (u64, u64)>,
    prev_iface: HashMap<String, (u64, u64)>,
    uid: u32,
    /// "exact" with the eBPF helper, "sockets" on the socket counters, "off".
    net_mode: &'static str,
    /// Why the helper is not in use, when it is installed but failed.
    net_error: String,
    net_helper: Option<exact::Helper>,
    /// Feeds the socket-close listener, started only once the socket counters are
    /// the method in use.
    msg_tx: Option<Sender<Msg>>,
    /// The next socket-counter pass only takes baselines: after a fallback from the
    /// helper, every open socket's whole history would otherwise count as new.
    net_rebase: bool,

    clk_tck: u64,
    page_kib: u64,
    start_ticks: u64,
    warm: bool,
}

impl Tracker {
    fn new(args: Args) -> Tracker {
        let clk_tck = procs::clk_tck().max(1);
        let store = store::Store::new(
            args.state_dir.clone(),
            args.retention_days,
            args.retention_mode,
        );
        let energy = energy::Reader::new(&args.energy_source);
        let battery = battery::Reader::new();
        // Read now rather than left false until the first tick, or the span before
        // that tick is credited as time on battery.
        let bat_on_ac = battery.on_ac();
        let now = store::now_ms();

        Tracker {
            store,
            energy,
            battery,
            apps: HashMap::new(),
            known_classes: HashSet::new(),
            seen_windows: false,
            clients: Vec::new(),
            locked: false,
            idle: false,
            dpms_off: false,
            bat_on_ac,
            bat_charging: false,
            last_accrual_ms: now,
            last_tick_ms: now,
            last_flush_ms: now,
            prev_busy: 0,
            prev_cpu: HashMap::new(),
            prev_gpu: HashMap::new(),
            prev_gpu_total: 0,
            gpu_fds: HashMap::new(),
            ticks_since_full_gpu: u32::MAX,
            gpu_rescan_pending: false,
            prev_net: HashMap::new(),
            sock_key: HashMap::new(),
            closed_tail: HashMap::new(),
            prev_iface: HashMap::new(),
            uid: unsafe { libc::getuid() },
            net_mode: "off",
            net_error: String::new(),
            net_helper: None,
            msg_tx: None,
            net_rebase: false,
            page_kib: procs::page_size() / 1024,
            start_ticks: uptime_ticks(clk_tck),
            clk_tck,
            warm: false,
            args,
        }
    }

    /// True when nothing is on screen for the user to look at, whatever the window
    /// layout says. Foreground time must not accrue behind a lock screen.
    fn blocked(&self) -> bool {
        self.locked || self.idle || self.dpms_off
    }

    /// Longest span the sampler is willing to describe from one end of it.
    ///
    /// Ticks arrive every interval and window events more often than that, so
    /// anything much longer than a few intervals is a stretch of time the sampler
    /// was not running through: a suspend, a hibernate, or a stall. Nothing about
    /// it was observed, and the machine was almost certainly not doing the thing it
    /// was doing when the gap opened.
    fn max_gap_ms(&self) -> i64 {
        (self.args.interval_ms as i64 * 3).max(60_000)
    }

    /// Credit the time since the last accrual to whichever counter each app was
    /// earning. Called on every window event as well as every tick, so a switch is
    /// recorded at the instant it happened rather than rounded to a sample.
    ///
    /// A gap past `max_gap_ms` is skipped rather than credited. Filling it would
    /// write an hour of background time into every hour the machine slept through,
    /// for every process that happened to be alive when it went down — which both
    /// invents the time and is what makes the day files large.
    fn accrue(&mut self, now_ms: i64) {
        if now_ms <= self.last_accrual_ms {
            return;
        }
        if now_ms - self.last_accrual_ms > self.max_gap_ms() {
            self.last_accrual_ms = now_ms;
            return;
        }
        let blocked = self.blocked();
        let has_battery = self.battery.present();
        let (on_ac, charging) = (self.bat_on_ac, self.bat_charging);
        let mut t = self.last_accrual_ms;
        self.last_accrual_ms = now_ms;

        while t < now_ms {
            // A span may cross into the next hour; split it rather than dropping
            // ten seconds of the previous hour into the next one.
            let end = self.store.hour_end_ms(t).min(now_ms);
            let dt = (end - t) as u64;
            let apps = &mut self.apps;
            let store = &mut self.store;
            let mut any_fg = false;

            for (key, app) in apps.iter_mut() {
                if !app.alive && !app.visible {
                    continue;
                }
                let b = store.bucket(t, key, &app.exe, app.headless);
                if effective_fg(app, blocked) {
                    any_fg = true;
                    b.fg_ms += dt;
                    app.d_fg_ms += dt;
                    if app.focused {
                        b.focus_ms += dt;
                    }
                } else {
                    b.bg_ms += dt;
                    app.d_bg_ms += dt;
                }
            }

            // Device screen time: the span during which *something* was on screen,
            // kept on the system row. Adding up the apps' own foreground time counts
            // every moment two windows were visible at once twice over, which is how
            // an hour bucket ends up claiming to hold more than an hour.
            //
            // Its background counterpart is time the machine was up with nothing to
            // look at. Both are counted here rather than at sample time so they are
            // split at the hour boundary like everything else; credited per tick they
            // land wholly in the hour the tick fired in, which is what put an hour
            // bucket over 3600 s.
            let b = store.bucket(t, SYSTEM_KEY, SYSTEM_KEY, true);
            if any_fg {
                b.fg_ms += dt;
            } else {
                b.bg_ms += dt;
            }

            // Time on battery is counted here for the same reason as screen time:
            // an hour boundary in the middle of a span belongs to both hours, and a
            // suspend belongs to neither, which the early return above already took
            // care of.
            if has_battery {
                let b = store.bat_bucket(t);
                if !on_ac {
                    b.off_ac_ms += dt;
                } else if charging {
                    b.charge_ms += dt;
                } else {
                    b.ac_ms += dt;
                }
            }
            t = end;
        }
    }

    /// Count foreground entries, after the state that caused them has been applied.
    fn mark_sessions(&mut self, now_ms: i64) {
        let blocked = self.blocked();
        let apps = &mut self.apps;
        let store = &mut self.store;
        for (key, app) in apps.iter_mut() {
            let fg = effective_fg(app, blocked);
            if fg && !app.was_fg {
                store.bucket(now_ms, key, &app.exe, app.headless).sessions += 1;
            }
            app.was_fg = fg;
        }
    }

    fn refresh_windows(&mut self) {
        let now = store::now_ms();
        self.accrue(now);

        let clients = hypr::clients();
        let mut classes: HashSet<String> = HashSet::new();
        let mut visible: HashSet<String> = HashSet::new();
        let mut focused: HashSet<String> = HashSet::new();

        for c in &clients {
            classes.insert(c.class.clone());
            if c.visible {
                visible.insert(c.class.clone());
            }
            if c.focused && c.visible {
                focused.insert(c.class.clone());
            }
        }

        // A class that has no window right now but reappears later is a fresh launch.
        // Whatever was already up when the sampler started is not one of those: the
        // first pass only learns the layout, or every window open across a shell
        // reload would be counted as having been launched again.
        for class in &classes {
            if self.seen_windows && !self.known_classes.contains(class) {
                let exe = self
                    .apps
                    .get(class)
                    .map(|a| a.exe.clone())
                    .unwrap_or_default();
                self.store.bucket(now, class, &exe, false).launches += 1;
            }
            // A newly launched app is the only common source of new DRM clients, so
            // this is what makes the periodic full sweep a backstop rather than the
            // discovery mechanism.
            if !self.known_classes.contains(class) {
                self.gpu_rescan_pending = true;
            }
        }
        self.known_classes = classes.clone();
        self.seen_windows = true;
        self.clients = clients.iter().map(|c| (c.pid, c.class.clone())).collect();

        for class in &classes {
            let app = self.apps.entry(class.clone()).or_default();
            app.headless = false;
            app.alive = true;
        }
        for (key, app) in self.apps.iter_mut() {
            app.visible = visible.contains(key);
            app.focused = focused.contains(key);
        }

        self.mark_sessions(now);
    }

    fn set_screen_state(&mut self, line: &str) {
        let Ok(v) = serde_json::from_str::<serde_json::Value>(line) else {
            return;
        };
        let now = store::now_ms();
        self.accrue(now);

        if let Some(b) = v.get("locked").and_then(|x| x.as_bool()) {
            self.locked = b;
        }
        if let Some(b) = v.get("idle").and_then(|x| x.as_bool()) {
            self.idle = b;
        }
        if let Some(s) = v.get("dpms").and_then(|x| x.as_str()) {
            self.dpms_off = s == "off";
        }
        self.mark_sessions(now);
    }

    /// Fold every process onto the app that owns it, then apportion the interval's
    /// counters. This is the only place that touches /proc and RAPL.
    fn tick(&mut self) {
        let now = store::now_ms();
        // The span this tick accounts for is the whole interval since the previous
        // tick, not since the last accrual — a window event in between advances the
        // accrual clock without consuming any of the counters sampled here.
        //
        // The first tick after a suspend covers hours of wall clock that no counter
        // ran through. Treating it as a zero-length interval is what keeps a night's
        // worth of GPU share and one enormous RAPL delta out of whichever apps were
        // still resident; the counters are still read below, to rebase them.
        let raw_dt = (now - self.last_tick_ms).max(0);
        let resumed = raw_dt > self.max_gap_ms();
        let dt_ms = if resumed { 0 } else { raw_dt as u64 };
        self.last_tick_ms = now;
        self.accrue(now);

        // Read after accruing, so the span that just closed was credited against the
        // state it actually ran under rather than the one this reading introduces.
        //
        // Nothing is integrated across a resume, for the same reason the RAPL delta
        // is dropped there: the pack really did empty overnight, but no hour on
        // record is the one it emptied in — `dt_ms` is zero and the draw falls out.
        // The level itself is still taken, so the curve steps down where the machine
        // slept rather than pretending it did not.
        if let Some(sample) = self.battery.sample() {
            self.bat_on_ac = sample.on_ac;
            self.bat_charging = sample.charging;
            let full_mwh = self.battery.full_mwh;
            // Microwatts over milliseconds, into microwatt-hours.
            let uwh = sample.uw.saturating_mul(dt_ms) / 3_600_000;

            let b = self.store.bat_bucket(now);
            b.observe(sample.deci_pct);
            if sample.charging {
                b.in_uwh += uwh;
            } else if !sample.on_ac {
                b.out_uwh += uwh;
            }
            self.store.set_bat_full(full_mwh);
        } else {
            // The pack could not be read, but the mains line still can: crediting the
            // next span against a state left over from before would put a night on the
            // charger down as a night on battery.
            self.bat_on_ac = self.battery.on_ac();
            self.bat_charging = false;
        }

        let clients = self.clients.clone();
        let mut client_of_pid: HashMap<u32, usize> = HashMap::new();
        for (i, (pid, _)) in clients.iter().enumerate() {
            client_of_pid.insert(*pid, i);
        }

        let sweep = procs::sweep();
        let boundaries = sweep.ancestors(std::process::id());

        // ---- fold pids onto apps -------------------------------------------------
        struct Agg {
            exe: String,
            headless: bool,
            cpu_ticks: u64,
            rss_pages: u64,
            pids: Vec<u32>,
        }
        let mut agg: HashMap<String, Agg> = HashMap::new();

        for p in &sweep.procs {
            let (key, exe, headless) = match sweep.window_root(p.pid, &client_of_pid) {
                Some(ci) => {
                    let (root_pid, class) = &clients[ci];
                    let exe = sweep
                        .index
                        .get(root_pid)
                        .map(|&i| sweep.procs[i].comm.clone())
                        .unwrap_or_else(|| class.clone());
                    (class.clone(), exe, false)
                }
                None if self.args.track_headless => {
                    let root = sweep.service_root(p.pid, &boundaries);
                    let comm = sweep
                        .index
                        .get(&root)
                        .map(|&i| sweep.procs[i].comm.clone())
                        .unwrap_or_else(|| p.comm.clone());
                    (comm.clone(), comm, true)
                }
                None => continue,
            };

            let e = agg.entry(key).or_insert_with(|| Agg {
                exe,
                headless,
                cpu_ticks: 0,
                rss_pages: 0,
                pids: Vec::new(),
            });

            let ident = (p.pid, p.starttime);
            let prev = self.prev_cpu.insert(ident, p.cpu_ticks);
            e.cpu_ticks += match prev {
                Some(prev) => p.cpu_ticks.saturating_sub(prev),
                // A process that started after the sampler brings its whole history;
                // one that predates it must not, or its lifetime CPU lands in one bucket.
                None if p.starttime >= self.start_ticks => p.cpu_ticks,
                None => 0,
            };
            e.rss_pages += p.rss_pages;
            e.pids.push(p.pid);
        }

        // Dead processes would otherwise leak one map entry each, forever.
        let live: HashSet<(u32, u64)> = sweep.procs.iter().map(|p| (p.pid, p.starttime)).collect();
        self.prev_cpu.retain(|k, _| live.contains(k));

        // ---- GPU ------------------------------------------------------------------
        let full_gpu =
            self.gpu_rescan_pending || self.ticks_since_full_gpu >= self.args.gpu_full_every;
        let scan = gpu::scan(&self.gpu_fds, full_gpu);
        if full_gpu {
            self.gpu_fds = scan.gpu_fds.clone();
            self.ticks_since_full_gpu = 0;
            self.gpu_rescan_pending = false;
        } else {
            self.ticks_since_full_gpu += 1;
        }

        let mut gpu_cycles_of_pid: HashMap<u32, u64> = HashMap::new();
        for c in &scan.clients {
            let prev = self.prev_gpu.insert(c.key.clone(), c.cycles);
            // A DRM client's counter starts at zero when the client is created, so a
            // client seen for the first time contributes its full count — unlike a pid.
            let delta = match prev {
                Some(prev) => c.cycles.saturating_sub(prev),
                None if self.warm => c.cycles,
                None => 0,
            };
            *gpu_cycles_of_pid.entry(c.pid).or_insert(0) += delta;
        }
        if full_gpu {
            let seen: HashSet<(String, u64)> = scan.clients.iter().map(|c| c.key.clone()).collect();
            self.prev_gpu.retain(|k, _| seen.contains(k));
        }

        let gpu_total_delta = scan.total_cycles.saturating_sub(self.prev_gpu_total);
        if scan.total_cycles > 0 {
            self.prev_gpu_total = scan.total_cycles;
        }

        // ---- network --------------------------------------------------------------
        let (net_of_key, sys_rx, sys_tx) = if self.args.track_network {
            let pids_of_key = agg
                .iter()
                .map(|(k, a)| (k.clone(), a.pids.clone()))
                .collect();
            if self.net_helper.is_some() {
                self.sample_network_exact(&sweep, &pids_of_key, resumed)
            } else {
                self.sample_network(&sweep, &pids_of_key, resumed)
            }
        } else {
            (HashMap::new(), 0, 0)
        };

        // ---- shares ---------------------------------------------------------------
        let busy_delta = sweep.busy_ticks.saturating_sub(self.prev_busy);
        self.prev_busy = sweep.busy_ticks;

        let total_rss: u64 = agg.values().map(|a| a.rss_pages).sum();
        // Sampled either way: the reader has to see the post-resume counter to have a
        // baseline for the next interval. Its delta spans the whole sleep, and on
        // hardware that clears RAPL across S3 it reads as a wrap, so it is dropped
        // rather than attributed.
        let sampled = self.energy.sample(dt_ms);
        let e = if resumed {
            energy::Delta::default()
        } else {
            sampled
        };

        struct Share {
            key: String,
            s_cpu: f64,
            s_gpu: f64,
            s_mem: f64,
            cpu_ms: u64,
            gpu_ms: u64,
            ram_mib: u64,
        }
        let mut shares: Vec<Share> = Vec::with_capacity(agg.len());

        for (key, a) in &agg {
            let s_cpu = if busy_delta > 0 {
                a.cpu_ticks as f64 / busy_delta as f64
            } else {
                0.0
            };
            let cycles: u64 = a.pids.iter().filter_map(|p| gpu_cycles_of_pid.get(p)).sum();
            let s_gpu = if gpu_total_delta > 0 {
                cycles as f64 / gpu_total_delta as f64
            } else {
                0.0
            };
            let s_mem = if total_rss > 0 {
                a.rss_pages as f64 / total_rss as f64
            } else {
                0.0
            };
            shares.push(Share {
                key: key.clone(),
                s_cpu,
                s_gpu,
                s_mem,
                cpu_ms: a.cpu_ticks * 1000 / self.clk_tck,
                gpu_ms: (s_gpu * dt_ms as f64) as u64,
                ram_mib: a.rss_pages * self.page_kib / 1024,
            });
        }

        // Engine shares can sum past 1 when several engines run at once; scaling them
        // back keeps the uncore domain from being over-assigned and the residual
        // from going negative.
        let gpu_sum: f64 = shares.iter().map(|s| s.s_gpu).sum();
        let gpu_norm = if gpu_sum > 1.0 { 1.0 / gpu_sum } else { 1.0 };

        // ---- write ----------------------------------------------------------------
        let mut out_apps = Vec::new();
        let mut attributed_uj = 0u64;

        for s in shares {
            let Some(a) = agg.get(&s.key) else { continue };
            let uj = (e.core_uj as f64 * s.s_cpu
                + e.uncore_uj as f64 * s.s_gpu * gpu_norm
                + e.dram_uj as f64 * s.s_mem) as u64;
            attributed_uj += uj;

            let app = self.apps.entry(s.key.clone()).or_default();
            app.alive = true;
            app.exe = a.exe.clone();
            if a.headless {
                app.headless = true;
            }
            let (d_fg, d_bg) = (app.d_fg_ms, app.d_bg_ms);
            let (exe, headless) = (app.exe.clone(), app.headless);

            let span = (d_fg + d_bg).max(1);
            let uj_fg = uj * d_fg / span;

            let b = self.store.bucket(now, &s.key, &exe, headless);
            b.cpu_ms += s.cpu_ms;
            b.gpu_ms += s.gpu_ms;
            b.observe_ram(s.ram_mib);
            b.uj_fg += uj_fg;
            b.uj_bg += uj - uj_fg;

            // Split like energy: by how much of the interval the app spent on screen.
            let (rx, tx) = net_of_key.get(&s.key).copied().unwrap_or((0, 0));
            let bytes_fg = (rx + tx) * d_fg / span;
            b.net_rx += rx;
            b.net_tx += tx;
            b.net_bg += rx + tx - bytes_fg;

            if !self.args.quiet {
                out_apps.push(serde_json::json!({
                    "k": s.key, "exe": exe, "hl": headless,
                    "fg": d_fg, "bg": d_bg,
                    "cpu": s.cpu_ms, "gpu": s.gpu_ms, "ram": s.ram_mib,
                    "mj": uj / 1000,
                    "rx": rx, "tx": tx,
                    "sCpu": (s.s_cpu * 1e4).round() / 1e4,
                    "sGpu": (s.s_gpu * 1e4).round() / 1e4,
                    "sMem": (s.s_mem * 1e4).round() / 1e4,
                }));
            }
        }

        // The share of the package that belongs to no app. Its time counterpart is
        // kept by `accrue`, which can split it at the hour boundary.
        let system_uj = e.pkg_uj.saturating_sub(attributed_uj);
        if system_uj > 0 {
            self.store.bucket(now, SYSTEM_KEY, SYSTEM_KEY, true).uj_bg += system_uj;
        }
        // Data of processes that have no row this tick: ones that exited before the
        // sweep, credited to their own name. All of it background — nothing of theirs
        // is on screen any more.
        for (key, &(rx, tx)) in &net_of_key {
            if agg.contains_key(key) {
                continue;
            }
            let (exe, headless) = self
                .apps
                .get(key)
                .map(|a| (a.exe.clone(), a.headless))
                .unwrap_or_else(|| (key.clone(), true));
            let b = self.store.bucket(now, key, &exe, headless);
            b.net_rx += rx;
            b.net_tx += tx;
            b.net_bg += rx + tx;
            if !self.args.quiet {
                out_apps.push(serde_json::json!({
                    "k": key, "exe": exe, "hl": headless, "rx": rx, "tx": tx,
                }));
            }
        }

        // The data no app could be credited with. With the eBPF helper that is only
        // traffic of no socket at all (ARP, DHCP, ICMP) and link-layer framing; on the
        // socket counters also QUIC and other UDP, connections that came and went
        // between two samples, and other users' daemons.
        if sys_rx + sys_tx > 0 {
            let b = self.store.bucket(now, SYSTEM_KEY, SYSTEM_KEY, true);
            b.net_rx += sys_rx;
            b.net_tx += sys_tx;
        }

        // Apps whose last process exited stop accruing; entries with neither
        // processes nor windows are dropped so the map tracks reality.
        let alive_keys: HashSet<&String> = agg.keys().collect();
        for (key, app) in self.apps.iter_mut() {
            app.alive = alive_keys.contains(key);
            app.d_fg_ms = 0;
            app.d_bg_ms = 0;
        }
        self.apps.retain(|_, a| a.alive || a.visible);

        if !self.args.quiet {
            emit(&serde_json::json!({
                "t": "sample",
                "ts": now,
                "dtMs": dt_ms,
                "src": self.energy.source.as_str(),
                "locked": self.locked, "idle": self.idle, "dpms": !self.dpms_off,
                "pkgMj": e.pkg_uj / 1000,
                "systemMj": system_uj / 1000,
                "sysRx": sys_rx, "sysTx": sys_tx,
                "netMode": self.net_mode,
                "netError": self.net_error,
                "apps": out_apps,
            }));
        }

        self.warm = true;
        if now - self.last_flush_ms >= self.args.flush_ms as i64 {
            self.flush(now);
        }
    }

    /// Pick the network method: the eBPF helper when it is installed and attaches,
    /// the socket counters otherwise. Called once, before the first tick.
    fn start_network(&mut self, tx: Sender<Msg>) {
        self.msg_tx = Some(tx);
        if !self.args.track_network {
            self.net_mode = "off";
            return;
        }
        match exact::Helper::start(&self.args.net_helper) {
            exact::Start::Ready(h) => {
                self.net_helper = Some(h);
                self.net_mode = "exact";
            }
            exact::Start::Absent => self.use_socket_counters(),
            exact::Start::Failed(msg) => {
                self.net_error = msg;
                self.use_socket_counters();
            }
        }
    }

    fn use_socket_counters(&mut self) {
        self.net_helper = None;
        self.net_mode = "sockets";
        self.net_rebase = true;
        self.prev_net.clear();
        self.sock_key.clear();
        if let Some(tx) = self.msg_tx.take() {
            thread::spawn(move || net::watch_closed(|s| tx.send(Msg::SocketClosed(s)).is_ok()));
        }
    }

    /// The helper's per-process bytes, folded onto apps. A process still running has
    /// its row already; one that exited before this tick is placed through the parent
    /// it had (a curl run from a terminal belongs to the terminal), and failing that
    /// under its own name. The remainder against the interfaces goes to the device.
    fn sample_network_exact(
        &mut self,
        sweep: &procs::Sweep,
        pids_of_key: &HashMap<String, Vec<u32>>,
        resumed: bool,
    ) -> (HashMap<String, (u64, u64)>, u64, u64) {
        let dumped = self.net_helper.as_mut().and_then(|h| h.dump());
        let ifaces = net::iface_counters();
        let (mut dev_rx, mut dev_tx) = (0u64, 0u64);
        for (name, &(rx, tx)) in &ifaces {
            if let Some(&(prx, ptx)) = self.prev_iface.get(name) {
                if rx >= prx && tx >= ptx {
                    dev_rx += rx - prx;
                    dev_tx += tx - ptx;
                }
            }
        }
        self.prev_iface = ifaces;

        let Some(procs) = dumped else {
            self.net_error = "the helper stopped answering".into();
            self.use_socket_counters();
            return (HashMap::new(), 0, 0);
        };
        if resumed {
            return (HashMap::new(), 0, 0);
        }

        let mut key_of_pid: HashMap<u32, &String> = HashMap::new();
        for (key, pids) in pids_of_key {
            for &p in pids {
                key_of_pid.insert(p, key);
            }
        }
        let leader = |pid: u32| {
            sweep
                .index
                .get(&pid)
                .map(|&i| procs::is_session_leader(&sweep.procs[i].comm))
                .unwrap_or(true)
        };

        let mut out: HashMap<String, (u64, u64)> = HashMap::new();
        for p in procs {
            let key = if let Some(k) = key_of_pid.get(&p.tgid) {
                Some((*k).clone())
            } else if sweep.index.contains_key(&p.tgid) {
                // Alive, but folded onto nothing: an untracked background process.
                None
            } else if let Some(k) = key_of_pid.get(&p.ppid).filter(|_| !leader(p.ppid)) {
                Some((*k).clone())
            } else if self.args.track_headless && !p.comm.is_empty() {
                Some(p.comm.clone())
            } else {
                None
            };
            if let Some(key) = key {
                let e = out.entry(key).or_insert((0, 0));
                e.0 += p.rx;
                e.1 += p.tx;
            }
        }
        let app_rx: u64 = out.values().map(|v| v.0).sum();
        let app_tx: u64 = out.values().map(|v| v.1).sum();
        (
            out,
            dev_rx.saturating_sub(app_rx),
            dev_tx.saturating_sub(app_tx),
        )
    }

    /// A socket the kernel freed. Its last bytes since the previous dump belong to
    /// the app already matched to it; a socket never matched (one that came and went
    /// between two dumps) is not ours to credit and stays in the residual.
    fn socket_closed(&mut self, s: net::Sock) {
        let Some((r, t)) = self.prev_net.remove(&s.cookie) else {
            return;
        };
        let key = self.sock_key.remove(&s.cookie).unwrap_or_default();
        if key.is_empty() {
            return;
        }
        let e = self.closed_tail.entry(key).or_insert((0, 0));
        e.0 += s.rx.saturating_sub(r);
        e.1 += s.tx.saturating_sub(t);
    }

    /// This interval's TCP bytes per app key, plus the device's unattributed
    /// remainder as (rx, tx). After a resume every counter is rebased and nothing is
    /// credited, for the same reason the RAPL delta is dropped there.
    fn sample_network(
        &mut self,
        sweep: &procs::Sweep,
        pids_of_key: &HashMap<String, Vec<u32>>,
        resumed: bool,
    ) -> (HashMap<String, (u64, u64)>, u64, u64) {
        let mut key_of_pid: HashMap<u32, &String> = HashMap::new();
        for (key, pids) in pids_of_key {
            for &p in pids {
                key_of_pid.insert(p, key);
            }
        }

        // A socket is ours once it has been seen open under our uid. After that it is
        // followed by cookie alone: a closing socket loses both its inode and, once
        // orphaned, its uid.
        let socks: Vec<net::Sock> = net::dump()
            .into_iter()
            .filter(|s| {
                self.prev_net.contains_key(&s.cookie) || (s.uid == self.uid && s.inode != 0)
            })
            .collect();

        // Match every new socket to its process straight away, not only those that
        // already moved data: one that opens just before a dump and does all its
        // work before the next would otherwise close unmatched, and its tail with it.
        let wanted: HashSet<u64> = socks
            .iter()
            .filter(|s| s.inode != 0 && !self.sock_key.contains_key(&s.cookie))
            .map(|s| s.inode)
            .collect();
        if !wanted.is_empty() {
            // App processes first: they hold nearly every socket that moves data, so
            // the walk usually ends before it reaches the rest of /proc.
            let mut order: Vec<u32> = pids_of_key.values().flatten().copied().collect();
            let seen: HashSet<u32> = order.iter().copied().collect();
            order.extend(
                sweep
                    .procs
                    .iter()
                    .map(|p| p.pid)
                    .filter(|p| !seen.contains(p)),
            );
            let owners = net::owners(&order, &wanted);
            for s in socks.iter().filter(|s| wanted.contains(&s.inode)) {
                // An empty key marks a socket looked for and not placed (its process
                // is not tracked, or already gone), so it is not looked for again.
                let key = owners
                    .get(&s.inode)
                    .and_then(|pid| key_of_pid.get(pid))
                    .map(|k| (*k).clone())
                    .unwrap_or_default();
                self.sock_key.insert(s.cookie, key);
            }
        }

        let mut out: HashMap<String, (u64, u64)> = HashMap::new();
        for s in &socks {
            let prev = self.prev_net.insert(s.cookie, (s.rx, s.tx));
            let (drx, dtx) = match prev {
                Some((r, t)) => (s.rx.saturating_sub(r), s.tx.saturating_sub(t)),
                // Opened since the last dump, so everything it carried is new. On the
                // first tick it may be days old, and is only a baseline.
                None if self.warm && !self.net_rebase => (s.rx, s.tx),
                None => (0, 0),
            };
            if drx + dtx == 0 {
                continue;
            }
            match self.sock_key.get(&s.cookie) {
                Some(k) if !k.is_empty() => {
                    let e = out.entry(k.clone()).or_insert((0, 0));
                    e.0 += drx;
                    e.1 += dtx;
                }
                _ => {}
            }
        }
        for (key, (rx, tx)) in self.closed_tail.drain() {
            let e = out.entry(key).or_insert((0, 0));
            e.0 += rx;
            e.1 += tx;
        }

        self.net_rebase = false;
        let live: HashSet<u64> = socks.iter().map(|s| s.cookie).collect();
        self.prev_net.retain(|k, _| live.contains(k));
        self.sock_key.retain(|k, _| live.contains(k));

        // An interface that appeared since the last tick (a tether plugged in) is a
        // baseline, and one whose counter went backwards was recreated.
        let ifaces = net::iface_counters();
        let (mut dev_rx, mut dev_tx) = (0u64, 0u64);
        for (name, &(rx, tx)) in &ifaces {
            if let Some(&(prx, ptx)) = self.prev_iface.get(name) {
                if rx >= prx && tx >= ptx {
                    dev_rx += rx - prx;
                    dev_tx += tx - ptx;
                }
            }
        }
        self.prev_iface = ifaces;

        if resumed {
            return (HashMap::new(), 0, 0);
        }
        let app_rx: u64 = out.values().map(|v| v.0).sum();
        let app_tx: u64 = out.values().map(|v| v.1).sum();
        (
            out,
            dev_rx.saturating_sub(app_rx),
            dev_tx.saturating_sub(app_tx),
        )
    }

    fn flush(&mut self, now_ms: i64) {
        self.last_flush_ms = now_ms;
        if let Some(path) = self.store.flush() {
            if !self.args.quiet {
                emit(&serde_json::json!({ "t": "flush", "file": path.to_string_lossy() }));
            }
        }
    }
}

/// Block the termination signals everywhere, then wait for one on a dedicated
/// thread: an unflushed day file is the one thing worth being careful about here.
fn spawn_signal_thread(tx: Sender<Msg>) {
    unsafe {
        let mut set: libc::sigset_t = std::mem::zeroed();
        libc::sigemptyset(&mut set);
        libc::sigaddset(&mut set, libc::SIGTERM);
        libc::sigaddset(&mut set, libc::SIGINT);
        libc::sigaddset(&mut set, libc::SIGHUP);
        libc::pthread_sigmask(libc::SIG_BLOCK, &set, std::ptr::null_mut());

        thread::spawn(move || {
            let mut sig: libc::c_int = 0;
            libc::sigwait(&set, &mut sig);
            let _ = tx.send(Msg::Shutdown);
        });
    }
}

fn ensure_single_instance(state_dir: &PathBuf) -> Option<std::fs::File> {
    let _ = std::fs::create_dir_all(state_dir);
    let lock_path = state_dir.join("app_stats.lock");
    let file = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(&lock_path)
        .ok()?;

    use std::os::unix::io::AsRawFd;
    let fd = file.as_raw_fd();
    let res = unsafe { libc::flock(fd, libc::LOCK_EX | libc::LOCK_NB) };
    if res != 0 {
        if let Ok(pid_str) = std::fs::read_to_string(&lock_path) {
            if let Ok(pid) = pid_str.trim().parse::<i32>() {
                if pid > 0 && pid != (std::process::id() as i32) {
                    unsafe { libc::kill(pid, libc::SIGTERM); }
                    std::thread::sleep(Duration::from_millis(300));
                }
            }
        }
        let res2 = unsafe { libc::flock(fd, libc::LOCK_EX | libc::LOCK_NB) };
        if res2 != 0 {
            let _ = unsafe { libc::flock(fd, libc::LOCK_EX) };
        }
    }

    let _ = unsafe { libc::ftruncate(fd, 0) };
    use std::io::Write;
    let mut file_ref = &file;
    let _ = writeln!(file_ref, "{}", std::process::id());
    Some(file)
}

fn main() {
    let args = Args::parse();
    let _lock_file = ensure_single_instance(&args.state_dir);
    let interval = Duration::from_millis(args.interval_ms);
    let (tx, rx) = channel::<Msg>();

    spawn_signal_thread(tx.clone());

    {
        let tx = tx.clone();
        thread::spawn(move || hypr::watch(tx));
    }
    {
        let tx = tx.clone();
        thread::spawn(move || {
            for line in std::io::stdin().lock().lines().map_while(Result::ok) {
                if tx.send(Msg::Stdin(line)).is_err() {
                    return;
                }
            }
        });
    }
    {
        let tx = tx.clone();
        thread::spawn(move || loop {
            thread::sleep(interval);
            if tx.send(Msg::Tick).is_err() {
                return;
            }
        });
    }

    let mut t = Tracker::new(args);
    t.start_network(tx.clone());
    emit(&serde_json::json!({
        "t": "ready",
        "src": t.energy.source.as_str(),
        "intervalMs": t.args.interval_ms,
        "flushMs": t.args.flush_ms,
        "retentionDays": t.args.retention_days,
        "retentionMode": if t.args.retention_mode == store::Retention::PreviousMonth { "previous-month" } else { "fixed" },
        "stateDir": t.store.dir().to_string_lossy(),
        "headless": t.args.track_headless,
        "network": t.args.track_network,
        "netMode": t.net_mode,
        "netError": t.net_error,
    }));

    t.refresh_windows();
    // Establish counter baselines immediately, so the first real sample covers one
    // interval rather than the machine's entire uptime. It carries no deltas worth
    // reporting, so it is not emitted.
    let quiet = t.args.quiet;
    t.args.quiet = true;
    t.tick();
    t.args.quiet = quiet;

    for msg in rx {
        match msg {
            Msg::WindowsChanged => t.refresh_windows(),
            Msg::SocketClosed(s) => t.socket_closed(s),
            Msg::Tick => t.tick(),
            Msg::Stdin(line) => {
                let kind = serde_json::from_str::<serde_json::Value>(&line)
                    .ok()
                    .and_then(|v| v.get("t").and_then(|t| t.as_str()).map(String::from));
                match kind.as_deref() {
                    Some("state") => t.set_screen_state(&line),
                    Some("flush") => {
                        let now = store::now_ms();
                        t.accrue(now);
                        t.flush(now);
                    }
                    Some("quit") => break,
                    _ => {}
                }
            }
            Msg::Shutdown => break,
        }
    }

    let now = store::now_ms();
    t.accrue(now);
    t.flush(now);
}
