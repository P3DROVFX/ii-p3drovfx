use super::{hwmon_for, Sample};
use crate::sysfs;
use libloading::{Library, Symbol};
use std::ffi::{c_char, c_int, c_uint, CString};
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

const HWMON_NAMES: &[&str] = &["nvidia", "nouveau"];

type Device = *mut std::ffi::c_void;

#[repr(C)]
#[derive(Default)]
struct Utilization {
    gpu: c_uint,
    memory: c_uint,
}

#[repr(C)]
#[derive(Default)]
struct Memory {
    total: u64,
    free: u64,
    used: u64,
}

struct Nvml {
    _library: Library,
    handle_by_pci_bus_id: unsafe extern "C" fn(*const c_char, *mut Device) -> c_int,
    device_name: unsafe extern "C" fn(Device, *mut c_char, c_uint) -> c_int,
    utilization: unsafe extern "C" fn(Device, *mut Utilization) -> c_int,
    memory_info: unsafe extern "C" fn(Device, *mut Memory) -> c_int,
    temperature: unsafe extern "C" fn(Device, c_int, *mut c_uint) -> c_int,
    power_usage: unsafe extern "C" fn(Device, *mut c_uint) -> c_int,
    power_limit: unsafe extern "C" fn(Device, *mut c_uint) -> c_int,
    fan_speed: unsafe extern "C" fn(Device, *mut c_uint) -> c_int,
}

unsafe impl Send for Nvml {}
unsafe impl Sync for Nvml {}

impl Nvml {
    fn load() -> Option<Self> {
        unsafe {
            let library = Library::new("libnvidia-ml.so.1").ok()?;

            let init: Symbol<unsafe extern "C" fn() -> c_int> =
                library.get(b"nvmlInit_v2\0").ok()?;
            if init() != 0 {
                return None;
            }

            Some(Self {
                handle_by_pci_bus_id: *library.get(b"nvmlDeviceGetHandleByPciBusId_v2\0").ok()?,
                device_name: *library.get(b"nvmlDeviceGetName\0").ok()?,
                utilization: *library.get(b"nvmlDeviceGetUtilizationRates\0").ok()?,
                memory_info: *library.get(b"nvmlDeviceGetMemoryInfo\0").ok()?,
                temperature: *library.get(b"nvmlDeviceGetTemperature\0").ok()?,
                power_usage: *library.get(b"nvmlDeviceGetPowerUsage\0").ok()?,
                power_limit: *library.get(b"nvmlDeviceGetEnforcedPowerLimit\0").ok()?,
                fan_speed: *library.get(b"nvmlDeviceGetFanSpeed\0").ok()?,
                _library: library,
            })
        }
    }
}

fn nvml() -> Option<&'static Nvml> {
    static NVML: OnceLock<Option<Nvml>> = OnceLock::new();
    NVML.get_or_init(Nvml::load).as_ref()
}

fn bus_id(device_path: &Path) -> Option<CString> {
    let bdf = device_path.file_name()?.to_str()?;
    let (domain, rest) = bdf.split_once(':')?;
    CString::new(format!("{domain:0>8}:{rest}")).ok()
}

pub struct Nvidia {
    hwmon: Option<PathBuf>,
    device: Option<Device>,
}

impl Nvidia {
    pub fn new(device_path: PathBuf) -> Self {
        let hwmon = hwmon_for(&device_path, HWMON_NAMES);
        let device = nvml().and_then(|nvml| {
            let id = bus_id(&device_path)?;
            let mut device: Device = std::ptr::null_mut();
            unsafe { (nvml.handle_by_pci_bus_id)(id.as_ptr(), &mut device) };
            (!device.is_null()).then_some(device)
        });

        Self { hwmon, device }
    }

    pub fn device_name(&self) -> Option<String> {
        let nvml = nvml()?;
        let device = self.device?;
        let mut buffer = [0u8; 96];

        let status = unsafe {
            (nvml.device_name)(device, buffer.as_mut_ptr().cast(), buffer.len() as c_uint)
        };
        if status != 0 {
            return None;
        }

        let end = buffer.iter().position(|byte| *byte == 0)?;
        String::from_utf8(buffer[..end].to_vec()).ok()
    }

    pub fn sample(&mut self) -> Sample {
        let mut out = Sample::default();

        let (Some(nvml), Some(device)) = (nvml(), self.device) else {
            if let Some(hwmon) = self.hwmon.as_deref() {
                out.temperature = sysfs::first_temp(hwmon);
            }
            return out;
        };

        unsafe {
            let mut utilization = Utilization::default();
            if (nvml.utilization)(device, &mut utilization) == 0 {
                out.usage = (f64::from(utilization.gpu) / 100.0).clamp(0.0, 1.0);
            }

            let mut memory = Memory::default();
            if (nvml.memory_info)(device, &mut memory) == 0 {
                out.vram_used = memory.used as f64;
                out.vram_total = memory.total as f64;
            }

            let mut celsius: c_uint = 0;
            if (nvml.temperature)(device, 0, &mut celsius) == 0 {
                out.temperature = Some(f64::from(celsius));
            }

            let mut milliwatts: c_uint = 0;
            if (nvml.power_usage)(device, &mut milliwatts) == 0 {
                out.power = Some(f64::from(milliwatts) / 1000.0);
            }

            let mut limit: c_uint = 0;
            if (nvml.power_limit)(device, &mut limit) == 0 {
                out.power_limit = Some(f64::from(limit) / 1000.0);
            }

            let mut percent: c_uint = 0;
            if (nvml.fan_speed)(device, &mut percent) == 0 {
                out.fan_percent = Some(f64::from(percent));
            }
        }

        out
    }
}
