#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qlist.h");
        type QList_f64 = cxx_qt_lib::QList<f64>;
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        type QList_QString = cxx_qt_lib::QList<cxx_qt_lib::QString>;
        type QList_bool = cxx_qt_lib::QList<bool>;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        #[qproperty(bool, poll_cpu, cxx_name = "pollCpu")]
        #[qproperty(bool, poll_memory, cxx_name = "pollMemory")]
        #[qproperty(bool, poll_gpu, cxx_name = "pollGpu")]
        #[qproperty(QString, cpu_model, cxx_name = "cpuModel")]
        #[qproperty(i32, cpu_threads, cxx_name = "cpuThreads")]
        #[qproperty(f64, cpu_max_frequency, cxx_name = "cpuMaxFrequency")]
        #[qproperty(f64, cpu_usage, cxx_name = "cpuUsage")]
        #[qproperty(f64, cpu_frequency, cxx_name = "cpuFrequency")]
        #[qproperty(f64, cpu_temperature, cxx_name = "cpuTemperature")]
        #[qproperty(bool, cpu_has_temperature, cxx_name = "cpuHasTemperature")]
        #[qproperty(f64, memory_total, cxx_name = "memoryTotal")]
        #[qproperty(f64, memory_used, cxx_name = "memoryUsed")]
        #[qproperty(f64, memory_free, cxx_name = "memoryFree")]
        #[qproperty(f64, memory_usage, cxx_name = "memoryUsage")]
        #[qproperty(f64, swap_total, cxx_name = "swapTotal")]
        #[qproperty(f64, swap_used, cxx_name = "swapUsed")]
        #[qproperty(f64, swap_free, cxx_name = "swapFree")]
        #[qproperty(f64, swap_usage, cxx_name = "swapUsage")]
        #[qproperty(QList_QString, gpu_cards, cxx_name = "gpuCards")]
        #[qproperty(QList_QString, gpu_names, cxx_name = "gpuNames")]
        #[qproperty(QList_QString, gpu_vendors, cxx_name = "gpuVendors")]
        #[qproperty(QList_bool, gpu_integrated, cxx_name = "gpuIntegrated")]
        #[qproperty(QList_f64, gpu_usages, cxx_name = "gpuUsages")]
        #[qproperty(QList_f64, gpu_vram_used, cxx_name = "gpuVramUsed")]
        #[qproperty(QList_f64, gpu_vram_total, cxx_name = "gpuVramTotal")]
        #[qproperty(QList_f64, gpu_vram_usages, cxx_name = "gpuVramUsages")]
        #[qproperty(QList_f64, gpu_temperatures, cxx_name = "gpuTemperatures")]
        #[qproperty(
            QList_f64,
            gpu_temperatures_junction,
            cxx_name = "gpuTemperaturesJunction"
        )]
        #[qproperty(QList_f64, gpu_temperatures_memory, cxx_name = "gpuTemperaturesMemory")]
        #[qproperty(QList_f64, gpu_fan_rpm, cxx_name = "gpuFanRpm")]
        #[qproperty(QList_f64, gpu_fan_percents, cxx_name = "gpuFanPercents")]
        #[qproperty(QList_f64, gpu_power, cxx_name = "gpuPower")]
        #[qproperty(QList_f64, gpu_power_limits, cxx_name = "gpuPowerLimits")]
        type SysMon = super::SysMonRust;
    }

    unsafe extern "RustQt" {
        #[qinvokable]
        fn refresh(self: Pin<&mut SysMon>);

        #[qsignal]
        fn refreshed(self: Pin<&mut SysMon>);
    }

    impl cxx_qt::Constructor<()> for SysMon {}
}

use core::pin::Pin;
use cxx_qt::CxxQtType;
use cxx_qt_lib::{QList, QString};
use std::path::PathBuf;
use sysinfo::{cpu, gpu, memory};

pub struct SysMonRust {
    poll_cpu: bool,
    poll_memory: bool,
    poll_gpu: bool,
    cpu_model: QString,
    cpu_threads: i32,
    cpu_max_frequency: f64,
    cpu_usage: f64,
    cpu_frequency: f64,
    cpu_temperature: f64,
    cpu_has_temperature: bool,
    memory_total: f64,
    memory_used: f64,
    memory_free: f64,
    memory_usage: f64,
    swap_total: f64,
    swap_used: f64,
    swap_free: f64,
    swap_usage: f64,
    gpu_cards: QList<QString>,
    gpu_names: QList<QString>,
    gpu_vendors: QList<QString>,
    gpu_integrated: QList<bool>,
    gpu_usages: QList<f64>,
    gpu_vram_used: QList<f64>,
    gpu_vram_total: QList<f64>,
    gpu_vram_usages: QList<f64>,
    gpu_temperatures: QList<f64>,
    gpu_temperatures_junction: QList<f64>,
    gpu_temperatures_memory: QList<f64>,
    gpu_fan_rpm: QList<f64>,
    gpu_fan_percents: QList<f64>,
    gpu_power: QList<f64>,
    gpu_power_limits: QList<f64>,
    devices: Vec<gpu::Device>,
    cpu_hwmon: Option<PathBuf>,
    last_total: i64,
    last_idle: i64,
}

impl Default for SysMonRust {
    fn default() -> Self {
        Self {
            poll_cpu: true,
            poll_memory: true,
            poll_gpu: true,
            cpu_model: QString::default(),
            cpu_threads: 0,
            cpu_max_frequency: 0.0,
            cpu_usage: 0.0,
            cpu_frequency: 0.0,
            cpu_temperature: 0.0,
            cpu_has_temperature: false,
            memory_total: 0.0,
            memory_used: 0.0,
            memory_free: 0.0,
            memory_usage: 0.0,
            swap_total: 0.0,
            swap_used: 0.0,
            swap_free: 0.0,
            swap_usage: 0.0,
            gpu_cards: QList::default(),
            gpu_names: QList::default(),
            gpu_vendors: QList::default(),
            gpu_integrated: QList::default(),
            gpu_usages: QList::default(),
            gpu_vram_used: QList::default(),
            gpu_vram_total: QList::default(),
            gpu_vram_usages: QList::default(),
            gpu_temperatures: QList::default(),
            gpu_temperatures_junction: QList::default(),
            gpu_temperatures_memory: QList::default(),
            gpu_fan_rpm: QList::default(),
            gpu_fan_percents: QList::default(),
            gpu_power: QList::default(),
            gpu_power_limits: QList::default(),
            devices: gpu::discover(),
            cpu_hwmon: cpu::hwmon(),
            last_total: 0,
            last_idle: 0,
        }
    }
}

fn collect<T>(values: impl IntoIterator<Item = T>) -> QList<T>
where
    T: cxx_qt_lib::QListElement + cxx::ExternType<Kind = cxx::kind::Trivial>,
{
    let mut list = QList::<T>::default();
    for value in values {
        list.append(value);
    }
    list
}

impl cxx_qt::Initialize for qobject::SysMon {
    fn initialize(mut self: Pin<&mut Self>) {
        let statics = cpu::statics();
        self.as_mut().set_cpu_model(QString::from(&statics.model));
        self.as_mut().set_cpu_threads(statics.threads);
        self.as_mut().set_cpu_max_frequency(statics.max_frequency);

        let cards = collect(self.devices.iter().map(|d| QString::from(d.card())));
        let names = collect(self.devices.iter().map(|d| QString::from(d.name())));
        let vendors = collect(
            self.devices
                .iter()
                .map(|d| QString::from(d.vendor().as_str())),
        );
        let integrated = collect(self.devices.iter().map(gpu::Device::integrated));
        self.as_mut().set_gpu_cards(cards);
        self.as_mut().set_gpu_names(names);
        self.as_mut().set_gpu_vendors(vendors);
        self.as_mut().set_gpu_integrated(integrated);

        self.refresh();
    }
}

impl qobject::SysMon {
    fn refresh(mut self: Pin<&mut Self>) {
        if *self.poll_cpu() {
            self.as_mut().refresh_cpu();
        }
        if *self.poll_memory() {
            self.as_mut().refresh_memory();
        }
        if *self.poll_gpu() {
            self.as_mut().refresh_gpu();
        }
        self.refreshed();
    }

    fn refresh_cpu(mut self: Pin<&mut Self>) {
        if let Some(sample) = cpu::sample(self.last_total, self.last_idle) {
            self.as_mut().rust_mut().last_total = sample.total;
            self.as_mut().rust_mut().last_idle = sample.idle;
            if let Some(usage) = sample.usage {
                self.as_mut().set_cpu_usage(usage);
            }
        }

        if let Some(frequency) = cpu::frequency() {
            self.as_mut().set_cpu_frequency(frequency);
        }

        let reading = self.cpu_hwmon.clone().as_deref().and_then(cpu::temperature);
        self.as_mut().set_cpu_has_temperature(reading.is_some());
        if let Some(temperature) = reading {
            self.as_mut().set_cpu_temperature(temperature);
        }
    }

    fn refresh_memory(mut self: Pin<&mut Self>) {
        let Some(sample) = memory::sample() else {
            return;
        };

        self.as_mut().set_memory_total(sample.total);
        self.as_mut().set_memory_used(sample.used);
        self.as_mut().set_memory_free(sample.free);
        self.as_mut().set_memory_usage(sample.usage);
        self.as_mut().set_swap_total(sample.swap_total);
        self.as_mut().set_swap_used(sample.swap_used);
        self.as_mut().set_swap_free(sample.swap_free);
        self.as_mut().set_swap_usage(sample.swap_usage);
    }

    fn refresh_gpu(mut self: Pin<&mut Self>) {
        let samples: Vec<gpu::Sample> = self
            .as_mut()
            .rust_mut()
            .devices
            .iter_mut()
            .map(gpu::Device::sample)
            .collect();

        let field = |pick: fn(&gpu::Sample) -> f64| collect(samples.iter().map(pick));

        let usages = field(|s| s.usage);
        let vram_used = field(|s| s.vram_used);
        let vram_total = field(|s| s.vram_total);
        let vram_usages = field(|s| {
            if s.vram_total > 0.0 {
                s.vram_used / s.vram_total
            } else {
                0.0
            }
        });

        self.as_mut().set_gpu_usages(usages);
        self.as_mut().set_gpu_vram_used(vram_used);
        self.as_mut().set_gpu_vram_total(vram_total);
        self.as_mut().set_gpu_vram_usages(vram_usages);

        let temperatures = field(|s| s.temperature.unwrap_or_default());
        let junction = field(|s| s.temperature_junction.unwrap_or_default());
        let memory_temp = field(|s| s.temperature_memory.unwrap_or_default());
        let fan_rpm = field(|s| s.fan_rpm.unwrap_or_default());
        let fan_percents = field(|s| s.fan_percent.unwrap_or_default());
        let power = field(|s| s.power.unwrap_or_default());
        let power_limits = field(|s| s.power_limit.unwrap_or_default());

        self.as_mut().set_gpu_temperatures(temperatures);
        self.as_mut().set_gpu_temperatures_junction(junction);
        self.as_mut().set_gpu_temperatures_memory(memory_temp);
        self.as_mut().set_gpu_fan_rpm(fan_rpm);
        self.as_mut().set_gpu_fan_percents(fan_percents);
        self.as_mut().set_gpu_power(power);
        self.as_mut().set_gpu_power_limits(power_limits);
    }
}
