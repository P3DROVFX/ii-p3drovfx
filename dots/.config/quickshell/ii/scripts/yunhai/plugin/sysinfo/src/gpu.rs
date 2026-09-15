mod amd;
mod intel;
mod nvidia;

use crate::{pci, sysfs};
use std::path::{Path, PathBuf};

const DRM_ROOT: &str = "/sys/class/drm";

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Vendor {
    Unknown,
    Amd,
    Intel,
    Nvidia,
}

impl Vendor {
    pub fn as_str(self) -> &'static str {
        match self {
            Vendor::Amd => "amd",
            Vendor::Intel => "intel",
            Vendor::Nvidia => "nvidia",
            Vendor::Unknown => "",
        }
    }
}

#[derive(Default)]
pub struct Sample {
    pub usage: f64,
    pub vram_used: f64,
    pub vram_total: f64,
    pub temperature: Option<f64>,
    pub temperature_junction: Option<f64>,
    pub temperature_memory: Option<f64>,
    pub fan_rpm: Option<f64>,
    pub fan_percent: Option<f64>,
    pub power: Option<f64>,
    pub power_limit: Option<f64>,
}

enum Backend {
    Amd(amd::Amd),
    Intel(intel::Intel),
    Nvidia(nvidia::Nvidia),
}

pub struct Device {
    backend: Backend,
    name: String,
    card: String,
    vendor: Vendor,
    integrated: bool,
}

impl Device {
    pub fn name(&self) -> &str {
        &self.name
    }

    pub fn card(&self) -> &str {
        &self.card
    }

    pub fn vendor(&self) -> Vendor {
        self.vendor
    }

    pub fn integrated(&self) -> bool {
        self.integrated
    }

    pub fn sample(&mut self) -> Sample {
        match &mut self.backend {
            Backend::Amd(backend) => backend.sample(),
            Backend::Intel(backend) => backend.sample(),
            Backend::Nvidia(backend) => backend.sample(),
        }
    }
}

fn suspended(device_path: &Path) -> bool {
    sysfs::read_text(device_path.join("power_state"))
        .is_some_and(|state| state.trim().eq_ignore_ascii_case("d3cold"))
}

fn hwmon_for(device_path: &Path, names: &[&str]) -> Option<PathBuf> {
    let root = device_path.join("hwmon");
    sysfs::hwmon_with_name(&root, names)
        .or_else(|| sysfs::numbered_entries(&root, "hwmon").into_iter().next())
}

fn device_for(device_path: PathBuf, card: String) -> Option<Device> {
    match pci::field(&device_path, "vendor").as_str() {
        "1002" => {
            let integrated = sysfs::read_f64(device_path.join("mem_info_vram_total"))
                .is_none_or(|vram| vram <= 0.0);
            let backend = amd::Amd::new(device_path.clone());
            let name = pci::amd_marketing_name(&device_path).unwrap_or_else(|| {
                pci::device_name(
                    &device_path,
                    if integrated { "AMD iGPU" } else { "AMD GPU" },
                )
            });
            Some(Device {
                backend: Backend::Amd(backend),
                name,
                card,
                vendor: Vendor::Amd,
                integrated,
            })
        }
        "8086" => {
            let integrated = sysfs::read_f64(device_path.join("lmem_total_bytes"))
                .is_none_or(|lmem| lmem <= 0.0);
            let name = pci::device_name(
                &device_path,
                if integrated {
                    "Intel iGPU"
                } else {
                    "Intel GPU"
                },
            );
            Some(Device {
                backend: Backend::Intel(intel::Intel::new(device_path, integrated)),
                name,
                card,
                vendor: Vendor::Intel,
                integrated,
            })
        }
        "10de" => {
            let backend = nvidia::Nvidia::new(device_path.clone());
            let name = backend
                .device_name()
                .unwrap_or_else(|| pci::device_name(&device_path, "NVIDIA GPU"));
            Some(Device {
                backend: Backend::Nvidia(backend),
                name,
                card,
                vendor: Vendor::Nvidia,
                integrated: false,
            })
        }
        _ => None,
    }
}

pub fn discover() -> Vec<Device> {
    sysfs::numbered_entries(DRM_ROOT, "card")
        .into_iter()
        .filter_map(|card| {
            let device_path = card.join("device").canonicalize().ok()?;
            if suspended(&device_path) {
                return None;
            }
            let name = card.file_name()?.to_str()?.to_owned();
            device_for(device_path, name)
        })
        .collect()
}
