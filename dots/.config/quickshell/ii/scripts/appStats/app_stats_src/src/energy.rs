//! RAPL energy counters, with a battery-drain fallback.
//!
//! `/sys/class/powercap/intel-rapl:0` is the package domain and its children are
//! core, uncore (the integrated GPU on this silicon) and dram. The counters are
//! monotonic microjoules that wrap at `max_energy_range_uj` — roughly every
//! 4.8 hours at 15 W, so wrap detection is mandatory, not defensive.
//!
//! Reading these unprivileged depends on /etc/udev/rules.d/99-rapl-readable.rules;
//! without it every read fails with EACCES and the reader falls back to the battery.

use std::fs;
use std::path::PathBuf;

const RAPL_ROOT: &str = "/sys/class/powercap";

/// Fraction of package energy assigned to each sub-domain when only whole-battery
/// draw is observable. Crude by construction — the UI labels this source so the
/// numbers are never mistaken for measured ones.
const FALLBACK_CORE: f64 = 0.55;
const FALLBACK_UNCORE: f64 = 0.15;
const FALLBACK_DRAM: f64 = 0.04;

#[derive(Clone, Copy, PartialEq)]
pub enum Source {
    Rapl,
    Battery,
    Off,
}

impl Source {
    pub fn as_str(self) -> &'static str {
        match self {
            Source::Rapl => "rapl",
            Source::Battery => "battery",
            Source::Off => "off",
        }
    }
}

#[derive(Default, Clone, Copy)]
pub struct Delta {
    pub pkg_uj: u64,
    pub core_uj: u64,
    pub uncore_uj: u64,
    pub dram_uj: u64,
}

struct Domain {
    path: PathBuf,
    max: u64,
    last: Option<u64>,
}

impl Domain {
    fn open(dir: &PathBuf) -> Option<Domain> {
        let max = read_u64(&dir.join("max_energy_range_uj"))?;
        // Probe once: an unreadable energy_uj here is what selects the fallback.
        read_u64(&dir.join("energy_uj"))?;
        Some(Domain {
            path: dir.join("energy_uj"),
            max,
            last: None,
        })
    }

    fn delta(&mut self) -> u64 {
        let Some(now) = read_u64(&self.path) else {
            return 0;
        };
        let d = match self.last {
            // A counter that went backwards wrapped; anything else would inject a
            // 72 Wh spike into whichever app happened to be foreground.
            Some(prev) if now < prev => self.max - prev + now,
            Some(prev) => now - prev,
            None => 0,
        };
        self.last = Some(now);
        d
    }
}

pub struct Reader {
    pkg: Option<Domain>,
    core: Option<Domain>,
    uncore: Option<Domain>,
    dram: Option<Domain>,
    battery: Option<PathBuf>,
    pub source: Source,
}

fn read_u64(path: &PathBuf) -> Option<u64> {
    fs::read_to_string(path).ok()?.trim().parse().ok()
}

fn read_name(dir: &PathBuf) -> String {
    fs::read_to_string(dir.join("name"))
        .map(|s| s.trim().to_string())
        .unwrap_or_default()
}

fn find_battery() -> Option<PathBuf> {
    // BAT1 on this machine reports charge, not power: there is no power_now, so
    // draw has to be derived from current × voltage.
    crate::battery::system_battery()
        .filter(|dir| dir.join("power_now").exists() || dir.join("current_now").exists())
}

impl Reader {
    pub fn new(requested: &str) -> Reader {
        let mut r = Reader {
            pkg: None,
            core: None,
            uncore: None,
            dram: None,
            battery: find_battery(),
            source: Source::Off,
        };
        if requested == "off" {
            return r;
        }

        if requested != "battery" {
            r.discover_rapl();
        }
        if r.pkg.is_some() {
            r.source = Source::Rapl;
        } else if r.battery.is_some() && requested != "rapl" {
            r.source = Source::Battery;
        }
        r
    }

    fn discover_rapl(&mut self) {
        let Ok(dir) = fs::read_dir(RAPL_ROOT) else {
            return;
        };
        for entry in dir.flatten() {
            let path = entry.path();
            let Some(base) = path.file_name().and_then(|s| s.to_str()) else {
                continue;
            };
            // The intel-rapl-mmio tree mirrors the same package and would double-count.
            if !base.starts_with("intel-rapl:") {
                continue;
            }
            let name = read_name(&path);
            let slot = match name.as_str() {
                n if n.starts_with("package-") => &mut self.pkg,
                "core" => &mut self.core,
                "uncore" => &mut self.uncore,
                "dram" => &mut self.dram,
                _ => continue,
            };
            if slot.is_none() {
                *slot = Domain::open(&path);
            }
        }
    }

    /// Whole-battery discharge over `dt_ms`, in microjoules. Zero on AC, which is
    /// correct rather than merely convenient: on AC there is nothing to attribute.
    fn battery_uj(&self, dt_ms: u64) -> u64 {
        let Some(dir) = &self.battery else { return 0 };
        let uw = match read_u64(&dir.join("power_now")) {
            Some(p) => p,
            None => {
                let i = read_u64(&dir.join("current_now")).unwrap_or(0);
                let v = read_u64(&dir.join("voltage_now")).unwrap_or(0);
                i.saturating_mul(v) / 1_000_000
            }
        };
        uw.saturating_mul(dt_ms) / 1000
    }

    pub fn sample(&mut self, dt_ms: u64) -> Delta {
        match self.source {
            Source::Off => Delta::default(),
            Source::Rapl => {
                let pkg = self.pkg.as_mut().map(|d| d.delta()).unwrap_or(0);
                let core = self.core.as_mut().map(|d| d.delta()).unwrap_or(0);
                let uncore = self.uncore.as_mut().map(|d| d.delta()).unwrap_or(0);
                let dram = self.dram.as_mut().map(|d| d.delta()).unwrap_or(0);
                Delta {
                    // Sub-domains are reported separately from the package and can
                    // briefly exceed it after a wrap; keep the package the ceiling.
                    pkg_uj: pkg.max(core + uncore + dram),
                    core_uj: core,
                    uncore_uj: uncore,
                    dram_uj: dram,
                }
            }
            Source::Battery => {
                let pkg = self.battery_uj(dt_ms);
                let f = |frac: f64| (pkg as f64 * frac) as u64;
                Delta {
                    pkg_uj: pkg,
                    core_uj: f(FALLBACK_CORE),
                    uncore_uj: f(FALLBACK_UNCORE),
                    dram_uj: f(FALLBACK_DRAM),
                }
            }
        }
    }
}
