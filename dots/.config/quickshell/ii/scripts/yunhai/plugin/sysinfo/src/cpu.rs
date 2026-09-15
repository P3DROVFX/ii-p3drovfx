use crate::sysfs;
use std::path::{Path, PathBuf};

const CPU_ROOT: &str = "/sys/devices/system/cpu";
const HWMON_NAMES: &[&str] = &["coretemp", "k10temp", "zenpower"];
const TEMP_LABELS: &[&str] = &["Package id 0", "Tctl", "Tdie"];

#[derive(Default)]
pub struct Statics {
    pub model: String,
    pub threads: i32,
    pub max_frequency: f64,
}

pub struct Sample {
    pub usage: Option<f64>,
    pub total: i64,
    pub idle: i64,
}

fn labelled_value<'a>(line: &'a str, label: &str) -> Option<&'a str> {
    let (key, value) = line.split_once(':')?;
    (key.trim() == label).then(|| value.trim())
}

pub fn statics() -> Statics {
    let mut statics = Statics {
        max_frequency: ["cpuinfo_max_freq", "scaling_max_freq"]
            .into_iter()
            .find_map(|file| sysfs::read_f64(format!("{CPU_ROOT}/cpu0/cpufreq/{file}")))
            .map(|khz| khz / 1_000_000.0)
            .unwrap_or_default(),
        ..Statics::default()
    };

    let Some(cpuinfo) = sysfs::read_text("/proc/cpuinfo") else {
        return statics;
    };

    for line in cpuinfo.lines() {
        if statics.model.is_empty() {
            if let Some(model) = labelled_value(line, "model name") {
                statics.model = model.to_owned();
            }
        }
        if line.starts_with("processor") {
            statics.threads += 1;
        }
    }

    statics
}

pub fn hwmon() -> Option<PathBuf> {
    sysfs::hwmon_with_name("/sys/class/hwmon", HWMON_NAMES)
}

pub fn temperature(hwmon: &Path) -> Option<f64> {
    sysfs::labelled_temp(hwmon, TEMP_LABELS).or_else(|| sysfs::first_temp(hwmon))
}

pub fn sample(last_total: i64, last_idle: i64) -> Option<Sample> {
    let stat = sysfs::read_text("/proc/stat")?;
    let fields: Vec<i64> = stat
        .lines()
        .next()?
        .split_whitespace()
        .skip(1)
        .filter_map(|field| field.parse().ok())
        .collect();
    if fields.len() < 4 {
        return None;
    }

    let total: i64 = fields.iter().sum();
    let idle = fields[3] + fields.get(4).copied().unwrap_or(0);

    let total_delta = total - last_total;
    let idle_delta = idle - last_idle;
    let usage =
        (total_delta > 0).then(|| (1.0 - idle_delta as f64 / total_delta as f64).clamp(0.0, 1.0));

    Some(Sample { usage, total, idle })
}

pub fn frequency() -> Option<f64> {
    let mut sum = 0.0;
    let mut count = 0;

    for cpu in sysfs::numbered_entries(CPU_ROOT, "cpu") {
        if let Some(khz) = sysfs::read_f64(cpu.join("cpufreq/scaling_cur_freq")) {
            sum += khz / 1_000_000.0;
            count += 1;
        }
    }

    if count == 0 {
        for line in sysfs::read_text("/proc/cpuinfo")?.lines() {
            if let Some(mhz) = labelled_value(line, "cpu MHz").and_then(|v| v.parse::<f64>().ok()) {
                sum += mhz / 1000.0;
                count += 1;
            }
        }
    }

    (count > 0).then(|| sum / count as f64)
}
