use super::{hwmon_for, Sample};
use crate::sysfs;
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::path::PathBuf;
use std::time::Instant;

const PMU_ROOT: &str = "/sys/bus/event_source/devices";
const HWMON_NAMES: &[&str] = &["i915", "xe"];
const TEMP_LABELS: &[&str] = &["gpu", "gt", "package"];

fn pmu_event_config(pmu: &str, event: &str) -> Option<u64> {
    let text = sysfs::read_text(format!("{PMU_ROOT}/{pmu}/events/{event}"))?;
    text.split(',').find_map(|field| {
        let value = field.trim().strip_prefix("config=")?;
        let (radix, digits) = match value.strip_prefix("0x") {
            Some(hex) => (16, hex),
            None => (10, value),
        };
        u64::from_str_radix(digits, radix).ok()
    })
}

#[repr(C)]
#[derive(Default)]
struct PerfEventAttr {
    kind: u32,
    size: u32,
    config: u64,
    sample_period: u64,
    sample_type: u64,
    read_format: u64,
    flags: u64,
    wakeup_events: u32,
    bp_type: u32,
    config1: u64,
}

fn open_busy_counter(pmu: &str) -> Option<OwnedFd> {
    let kind = sysfs::read_f64(format!("{PMU_ROOT}/{pmu}/type"))? as u32;
    let config = pmu_event_config(pmu, "rcs0-busy")?;

    let attr = PerfEventAttr {
        kind,
        size: std::mem::size_of::<PerfEventAttr>() as u32,
        config,
        ..PerfEventAttr::default()
    };

    let fd = unsafe { libc::syscall(libc::SYS_perf_event_open, &attr, -1, 0, -1, 0) };
    (fd >= 0).then(|| unsafe { OwnedFd::from_raw_fd(fd as i32) })
}

fn package_temp() -> Option<f64> {
    let zone = sysfs::numbered_entries("/sys/class/thermal", "thermal_zone")
        .into_iter()
        .find(|zone| {
            sysfs::read_text(zone.join("type")).is_some_and(|kind| kind.trim() == "x86_pkg_temp")
        });

    if let Some(temp) = zone.and_then(|zone| sysfs::read_f64(zone.join("temp"))) {
        return Some(temp / 1000.0);
    }

    let coretemp = sysfs::hwmon_with_name("/sys/class/hwmon", &["coretemp"])?;
    sysfs::first_temp(&coretemp)
}

pub struct Intel {
    device_path: PathBuf,
    hwmon: Option<PathBuf>,
    integrated: bool,
    busy_fd: Option<OwnedFd>,
    elapsed: Instant,
    last_busy: u64,
    last_energy: f64,
}

impl Intel {
    pub fn new(device_path: PathBuf, integrated: bool) -> Self {
        let hwmon = hwmon_for(&device_path, HWMON_NAMES);
        let busy_fd = open_busy_counter("i915").or_else(|| open_busy_counter("xe"));
        Self {
            device_path,
            hwmon,
            integrated,
            busy_fd,
            elapsed: Instant::now(),
            last_busy: 0,
            last_energy: 0.0,
        }
    }

    pub fn sample(&mut self) -> Sample {
        let nanoseconds = self.elapsed.elapsed().as_nanos() as f64;
        self.elapsed = Instant::now();

        let mut out = Sample {
            usage: self.busy(nanoseconds).unwrap_or_default(),
            ..Sample::default()
        };

        if let Some(total) =
            sysfs::read_f64(self.device_path.join("lmem_total_bytes")).filter(|t| *t > 0.0)
        {
            out.vram_used =
                sysfs::read_f64(self.device_path.join("lmem_used_bytes")).unwrap_or_default();
            out.vram_total = total;
        }

        out.power = self.power(nanoseconds);

        if let Some(hwmon) = self.hwmon.as_deref() {
            out.temperature =
                sysfs::labelled_temp(hwmon, TEMP_LABELS).or_else(|| sysfs::first_temp(hwmon));
        }
        if out.temperature.is_none() && self.integrated {
            out.temperature = package_temp();
        }

        out
    }

    fn busy(&mut self, nanoseconds: f64) -> Option<f64> {
        let fd = self.busy_fd.as_ref()?;
        if nanoseconds <= 0.0 {
            return None;
        }

        let mut busy: u64 = 0;
        let read = unsafe {
            libc::read(
                fd.as_raw_fd(),
                std::ptr::from_mut(&mut busy).cast(),
                std::mem::size_of::<u64>(),
            )
        };
        if read != std::mem::size_of::<u64>() as isize {
            return None;
        }

        let usage = (self.last_busy > 0 && busy >= self.last_busy)
            .then(|| ((busy - self.last_busy) as f64 / nanoseconds).clamp(0.0, 1.0));
        self.last_busy = busy;
        usage
    }

    fn power(&mut self, nanoseconds: f64) -> Option<f64> {
        let hwmon = self.hwmon.as_deref()?;
        if nanoseconds <= 0.0 {
            return None;
        }

        if let Some(microwatts) = sysfs::read_f64(hwmon.join("power1_input")) {
            return Some(microwatts / 1_000_000.0);
        }

        let microjoules = sysfs::read_f64(hwmon.join("energy1_input"))?;
        let power = (self.last_energy > 0.0 && microjoules >= self.last_energy)
            .then(|| (microjoules - self.last_energy) / 1_000_000.0 / (nanoseconds / 1e9));
        self.last_energy = microjoules;
        power
    }
}
