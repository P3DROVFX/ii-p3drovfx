//! Battery level, charge state and pack energy, read from sysfs.
//!
//! Separate from `energy.rs`, which only ever wants a draw figure to divide
//! between apps: this reads the pack itself, so a discharge curve can be drawn
//! for the device rather than attributed to anything.
//!
//! Level comes from `charge_now / charge_full` (or the energy pair on packs that
//! report watt-hours), not from `capacity` — the kernel rounds that to whole
//! percent, and a whole percent is an hour of a flat curve.
//!
//! Watt-hours in and out are integrated from the instantaneous draw rather than
//! differenced from the level: `charge_now` is refreshed by the firmware every few
//! minutes at best, so a whole hour of moderate use can pass with the reported
//! charge never moving, and then step by a percent all at once.
//!
//! The pack's full capacity is charge times the *nominal* voltage, not the
//! instantaneous one — `voltage_now` sags under load and springs back when the
//! machine goes quiet.

use std::fs;
use std::path::PathBuf;

const POWER_SUPPLY: &str = "/sys/class/power_supply";

fn read_u64(path: &PathBuf) -> Option<u64> {
    fs::read_to_string(path).ok()?.trim().parse().ok()
}

fn read_str(path: &PathBuf) -> Option<String> {
    Some(fs::read_to_string(path).ok()?.trim().to_string())
}

fn is_type(dir: &PathBuf, want: &str) -> bool {
    read_str(&dir.join("type")).map(|t| t == want).unwrap_or(false)
}

pub struct Sample {
    /// Level in tenths of a percent, 0..=1000.
    pub deci_pct: u64,
    /// Draw at this instant, microwatts, whichever direction it is flowing in.
    pub uw: u64,
    /// Whether the mains line is live, which is not the same question as whether
    /// the battery is charging: at a charge limit the firmware reports Discharging
    /// on AC at roughly zero draw.
    pub on_ac: bool,
    pub charging: bool,
}

pub struct Reader {
    dir: Option<PathBuf>,
    mains: Option<PathBuf>,
    /// Nominal pack voltage in microvolts, for the amp-hour conversion.
    nominal_uv: u64,
    /// Capacity when full, milliwatt-hours. Reported once per day file so a
    /// percentage can be read back as an amount of energy.
    pub full_mwh: u64,
}

/// The machine's own pack, not a peripheral's.
///
/// A Bluetooth mouse, keyboard or game controller registers a `Battery` supply of
/// its own, with a `status` file but only a `capacity` — no charge or energy pair,
/// and `scope` set to `Device`. Taking the first `Battery` in directory order picks
/// one of those whenever it was connected when the sampler started, and then every
/// read fails for the life of the process.
pub fn system_battery() -> Option<PathBuf> {
    for entry in fs::read_dir(POWER_SUPPLY).ok()?.flatten() {
        let dir = entry.path();
        if !is_type(&dir, "Battery") || !dir.join("status").exists() {
            continue;
        }
        if read_str(&dir.join("scope")).is_some_and(|s| s == "Device") {
            continue;
        }
        let has_level = (dir.join("charge_now").exists() && dir.join("charge_full").exists())
            || (dir.join("energy_now").exists() && dir.join("energy_full").exists());
        if has_level {
            return Some(dir);
        }
    }
    None
}

impl Reader {
    pub fn new() -> Reader {
        let mut mains = None;
        if let Ok(entries) = fs::read_dir(POWER_SUPPLY) {
            for entry in entries.flatten() {
                let dir = entry.path();
                if is_type(&dir, "Mains") {
                    mains = Some(dir);
                    break;
                }
            }
        }

        let mut r = Reader {
            dir: system_battery(),
            mains,
            nominal_uv: 0,
            full_mwh: 0,
        };
        r.measure_pack();
        r
    }

    pub fn present(&self) -> bool {
        self.dir.is_some()
    }

    /// Nominal voltage and full capacity. Read once at startup: `charge_full` only
    /// moves when the firmware re-learns the pack, which is a monthly event.
    fn measure_pack(&mut self) {
        let Some(dir) = &self.dir else { return };
        self.nominal_uv = read_u64(&dir.join("voltage_min_design"))
            .or_else(|| read_u64(&dir.join("voltage_now")))
            .unwrap_or(0);

        if let Some(uwh) = read_u64(&dir.join("energy_full")) {
            self.full_mwh = uwh / 1000;
        } else if let Some(uah) = read_u64(&dir.join("charge_full")) {
            self.full_mwh = uah.saturating_mul(self.nominal_uv) / 1_000_000_000;
        }
    }

    pub fn on_ac(&self) -> bool {
        match &self.mains {
            Some(dir) => read_u64(&dir.join("online")).unwrap_or(0) == 1,
            // No mains device to ask: fall back to what the pack says about itself.
            None => self
                .dir
                .as_ref()
                .and_then(|d| read_str(&d.join("status")))
                .map(|s| s != "Discharging")
                .unwrap_or(false),
        }
    }

    pub fn sample(&self) -> Option<Sample> {
        let dir = self.dir.as_ref()?;
        let charging = read_str(&dir.join("status"))
            .map(|s| s == "Charging")
            .unwrap_or(false);

        let (now, full) = match (
            read_u64(&dir.join("charge_now")),
            read_u64(&dir.join("charge_full")),
        ) {
            (Some(now), Some(full)) => (now, full),
            _ => (
                read_u64(&dir.join("energy_now"))?,
                read_u64(&dir.join("energy_full"))?,
            ),
        };
        if full == 0 {
            return None;
        }

        // Same derivation as the energy reader's battery fallback: packs that report
        // amp-hours have no power_now to read.
        let uw = read_u64(&dir.join("power_now")).unwrap_or_else(|| {
            let i = read_u64(&dir.join("current_now")).unwrap_or(0);
            let v = read_u64(&dir.join("voltage_now")).unwrap_or(0);
            i.saturating_mul(v) / 1_000_000
        });

        Some(Sample {
            deci_pct: (now.saturating_mul(1000) / full).min(1000),
            uw,
            on_ac: self.on_ac(),
            charging,
        })
    }
}
