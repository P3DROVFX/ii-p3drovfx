use crate::sysfs;
use std::path::Path;

const PCI_IDS: &str = "/usr/share/hwdata/pci.ids";
const AMDGPU_IDS: &str = "/usr/share/libdrm/amdgpu.ids";

#[derive(Default)]
struct Names {
    device: String,
    subsystem: String,
}

pub fn field(device_path: &Path, file: &str) -> String {
    sysfs::read_text(device_path.join(file))
        .map(|raw| {
            let raw = raw.trim();
            raw.strip_prefix("0x").unwrap_or(raw).to_lowercase()
        })
        .unwrap_or_default()
}

fn bracketed(raw: &str) -> String {
    match (raw.find('['), raw.rfind(']')) {
        (Some(open), Some(close)) if close > open => raw[open + 1..close].trim().to_owned(),
        _ => raw.to_owned(),
    }
}

fn lookup(device_path: &Path) -> Names {
    let vendor_id = field(device_path, "vendor");
    let device_id = field(device_path, "device");
    let sub_prefix = format!(
        "{} {}",
        field(device_path, "subsystem_vendor"),
        field(device_path, "subsystem_device")
    );

    let Some(ids) = sysfs::read_text(PCI_IDS) else {
        return Names::default();
    };
    if vendor_id.is_empty() || device_id.is_empty() {
        return Names::default();
    }

    let mut names = Names::default();
    let mut in_vendor = false;
    let mut in_device = false;

    for line in ids.lines() {
        if line.is_empty() || line.starts_with('#') {
            continue;
        }

        let Some(entry) = line.strip_prefix('\t') else {
            if in_vendor {
                break;
            }
            in_vendor = line.starts_with(&vendor_id);
            continue;
        };
        if !in_vendor {
            continue;
        }

        let Some(sub_entry) = entry.strip_prefix('\t') else {
            if in_device {
                break;
            }
            if let Some(rest) = entry.strip_prefix(&device_id) {
                names.device = rest.trim().to_owned();
                in_device = true;
            }
            continue;
        };
        if !in_device {
            continue;
        }

        if let Some(rest) = sub_entry.strip_prefix(&sub_prefix) {
            names.subsystem = rest.trim().to_owned();
            break;
        }
    }

    names
}

pub fn device_name(device_path: &Path, fallback: &str) -> String {
    let names = lookup(device_path);
    if !names.subsystem.is_empty() {
        return bracketed(&names.subsystem);
    }
    if !names.device.is_empty() {
        return bracketed(&names.device);
    }
    fallback.to_owned()
}

pub fn amd_marketing_name(device_path: &Path) -> Option<String> {
    let device_id = field(device_path, "device");
    let revision = field(device_path, "revision");
    if device_id.is_empty() || revision.is_empty() {
        return None;
    }

    sysfs::read_text(AMDGPU_IDS)?.lines().find_map(|line| {
        let mut fields = line.split(',');
        let id = fields.next()?.trim();
        let rev = fields.next()?.trim();
        let name = fields.next()?.trim();
        (id.eq_ignore_ascii_case(&device_id) && rev.eq_ignore_ascii_case(&revision))
            .then(|| name.to_owned())
    })
}
