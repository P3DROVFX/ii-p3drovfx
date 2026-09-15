use std::path::{Path, PathBuf};

pub fn read_text(path: impl AsRef<Path>) -> Option<String> {
    std::fs::read_to_string(path).ok()
}

pub fn read_f64(path: impl AsRef<Path>) -> Option<f64> {
    read_text(path)?.trim().parse().ok()
}

pub fn numbered_entries(dir: impl AsRef<Path>, prefix: &str) -> Vec<PathBuf> {
    let mut entries: Vec<_> = std::fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter(|entry| {
            entry
                .file_name()
                .to_str()
                .and_then(|name| name.strip_prefix(prefix))
                .is_some_and(|rest| !rest.is_empty() && rest.bytes().all(|b| b.is_ascii_digit()))
        })
        .map(|entry| entry.path())
        .collect();
    entries.sort();
    entries
}

pub fn hwmon_with_name(dir: impl AsRef<Path>, names: &[&str]) -> Option<PathBuf> {
    numbered_entries(dir, "hwmon").into_iter().find(|hwmon| {
        read_text(hwmon.join("name")).is_some_and(|name| names.contains(&name.trim()))
    })
}

pub fn suffixed_inputs(hwmon: &Path, prefix: &str, suffix: &str) -> Vec<PathBuf> {
    let mut inputs: Vec<_> = std::fs::read_dir(hwmon)
        .into_iter()
        .flatten()
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with(prefix) && name.ends_with(suffix))
        })
        .collect();
    inputs.sort();
    inputs
}

fn temp_inputs(hwmon: &Path) -> Vec<PathBuf> {
    suffixed_inputs(hwmon, "temp", "_input")
}

pub fn labelled_temp(hwmon: &Path, labels: &[&str]) -> Option<f64> {
    temp_inputs(hwmon).into_iter().find_map(|input| {
        let label_path = input.to_str()?.replace("_input", "_label");
        let label = read_text(label_path)?;
        labels
            .contains(&label.trim())
            .then(|| read_f64(input).map(|milli| milli / 1000.0))?
    })
}

pub fn first_temp(hwmon: &Path) -> Option<f64> {
    temp_inputs(hwmon)
        .into_iter()
        .find_map(|input| read_f64(input).map(|milli| milli / 1000.0))
}
