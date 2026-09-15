use super::{hwmon_for, Sample};
use crate::sysfs;
use std::path::PathBuf;

const HWMON_NAMES: &[&str] = &["amdgpu"];
const EDGE: &[&str] = &["edge"];
const JUNCTION: &[&str] = &["junction"];
const MEMORY: &[&str] = &["mem"];

const VRAM_SOURCES: &[(&str, &str)] = &[
    ("mem_info_vram_used", "mem_info_vram_total"),
    ("mem_info_vis_vram_used", "mem_info_vis_vram_total"),
    ("gtt_used", "gtt_total"),
];

pub struct Amd {
    device_path: PathBuf,
    hwmon: Option<PathBuf>,
}

impl Amd {
    pub fn new(device_path: PathBuf) -> Self {
        let hwmon = hwmon_for(&device_path, HWMON_NAMES);
        Self { device_path, hwmon }
    }

    pub fn sample(&mut self) -> Sample {
        let mut out = Sample {
            usage: sysfs::read_f64(self.device_path.join("gpu_busy_percent"))
                .map(|busy| (busy / 100.0).clamp(0.0, 1.0))
                .unwrap_or_default(),
            ..Sample::default()
        };

        if let Some((used, total)) = VRAM_SOURCES.iter().find_map(|(used, total)| {
            let total = sysfs::read_f64(self.device_path.join(total)).filter(|t| *t > 0.0)?;
            Some((
                sysfs::read_f64(self.device_path.join(used)).unwrap_or_default(),
                total,
            ))
        }) {
            out.vram_used = used;
            out.vram_total = total;
        }

        let Some(hwmon) = self.hwmon.as_deref() else {
            return out;
        };

        out.temperature = sysfs::labelled_temp(hwmon, EDGE).or_else(|| sysfs::first_temp(hwmon));
        out.temperature_junction = sysfs::labelled_temp(hwmon, JUNCTION);
        out.temperature_memory = sysfs::labelled_temp(hwmon, MEMORY);

        out.fan_rpm = sysfs::suffixed_inputs(hwmon, "fan", "_input")
            .into_iter()
            .find_map(sysfs::read_f64);
        out.fan_percent = sysfs::read_f64(hwmon.join("pwm1")).map(|pwm| pwm / 255.0 * 100.0);

        out.power = sysfs::read_f64(hwmon.join("power1_average"))
            .or_else(|| sysfs::read_f64(hwmon.join("power1_input")))
            .map(|microwatts| microwatts / 1_000_000.0);
        out.power_limit =
            sysfs::read_f64(hwmon.join("power1_cap")).map(|microwatts| microwatts / 1_000_000.0);

        out
    }
}
