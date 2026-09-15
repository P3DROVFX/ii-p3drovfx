use crate::sysfs;
use std::ffi::CStr;
use std::os::unix::fs::MetadataExt;

const INTERPRETERS: &[&str] = &[
    "python", "python2", "python3", "node", "bash", "sh", "perl", "ruby", "java", "exe", "php",
    "lua", "luajit", "dotnet", "mono", "swift", "nim", "wine",
];

pub struct Raw {
    pub pid: i32,
    pub comm: String,
    pub cpu_ticks: u64,
    pub rss_kb: f64,
    pub uid: u32,
}

fn page_size_kb() -> f64 {
    let size = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
    if size > 0 {
        size as f64 / 1024.0
    } else {
        4.0
    }
}

fn parse_stat(text: &str) -> Option<(String, u64, f64)> {
    let open = text.find('(')?;
    let close = text.rfind(')')?;
    let comm = text.get(open + 1..close)?.to_owned();

    let fields: Vec<&str> = text.get(close + 1..)?.split_whitespace().collect();
    if fields.len() < 22 {
        return None;
    }

    let ticks = fields[11].parse::<u64>().ok()? + fields[12].parse::<u64>().ok()?;
    let rss_pages = fields[21].parse::<f64>().ok()?;
    Some((comm, ticks, rss_pages))
}

pub fn total_cpu_ticks() -> u64 {
    sysfs::read_text("/proc/stat")
        .and_then(|stat| {
            Some(
                stat.lines()
                    .next()?
                    .split_whitespace()
                    .skip(1)
                    .filter_map(|field| field.parse::<u64>().ok())
                    .sum(),
            )
        })
        .unwrap_or_default()
}

pub fn scan() -> Vec<Raw> {
    let page_kb = page_size_kb();

    std::fs::read_dir("/proc")
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name();
            let pid = name.to_str()?.parse().ok()?;
            let (comm, cpu_ticks, rss_pages) =
                parse_stat(&sysfs::read_text(entry.path().join("stat"))?)?;

            Some(Raw {
                pid,
                comm,
                cpu_ticks,
                rss_kb: rss_pages * page_kb,
                uid: entry.metadata().ok()?.uid(),
            })
        })
        .collect()
}

pub fn command_line(pid: i32, comm: &str) -> String {
    std::fs::read(format!("/proc/{pid}/cmdline"))
        .ok()
        .map(|raw| String::from_utf8_lossy(&raw).replace('\0', " "))
        .map(|command| command.trim().to_owned())
        .filter(|command| !command.is_empty())
        .unwrap_or_else(|| format!("[{comm}]"))
}

fn basename(path: &str) -> &str {
    path.rsplit('/').next().unwrap_or(path)
}

pub fn display_name(command: &str) -> String {
    if command.starts_with('[') && command.ends_with(']') {
        return command.to_owned();
    }

    let mut parts = command.split_whitespace();
    let Some(base) = parts.next().map(basename) else {
        return command.to_owned();
    };
    if !INTERPRETERS.contains(&base) {
        return base.to_owned();
    }

    parts.find(|part| !part.starts_with('-')).map_or_else(
        || base.to_owned(),
        |argument| format!("{base}: {}", basename(argument)),
    )
}

pub fn user_name(uid: u32) -> String {
    let passwd = unsafe { libc::getpwuid(uid) };
    if passwd.is_null() {
        return uid.to_string();
    }

    unsafe { CStr::from_ptr((*passwd).pw_name) }
        .to_string_lossy()
        .into_owned()
}

pub fn format_memory(kb: f64) -> String {
    if kb < 1024.0 {
        return format!("{kb:.0}KB");
    }

    let mb = kb / 1024.0;
    if mb < 1024.0 {
        let digits = usize::from(mb < 100.0);
        return format!("{mb:.digits$}MB");
    }

    let gb = mb / 1024.0;
    let digits = if gb >= 10.0 { 1 } else { 2 };
    format!("{gb:.digits$}GB")
}

fn send(pid: i32, signal: i32) {
    if pid > 0 {
        unsafe { libc::kill(pid, signal) };
    }
}

pub fn terminate(pid: i32) {
    send(pid, libc::SIGTERM);
}

pub fn kill(pid: i32) {
    send(pid, libc::SIGKILL);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stat_fields_are_indexed_past_the_command() {
        let tail: Vec<String> = (1..=23).map(|field| field.to_string()).collect();
        let (comm, ticks, rss_pages) =
            parse_stat(&format!("7 (my prog) S {}", tail.join(" "))).unwrap();

        assert_eq!(comm, "my prog");
        assert_eq!(ticks, 23);
        assert_eq!(rss_pages, 21.0);
    }

    #[test]
    fn interpreters_are_named_after_their_script() {
        assert_eq!(
            display_name("/usr/bin/python3 -u /opt/foo/bar.py"),
            "python3: bar.py"
        );
        assert_eq!(display_name("/usr/bin/kitty --single-instance"), "kitty");
        assert_eq!(display_name("[kworker/0:1]"), "[kworker/0:1]");
    }

    #[test]
    fn memory_precision_shrinks_as_the_unit_grows() {
        assert_eq!(format_memory(512.0), "512KB");
        assert_eq!(format_memory(2048.0), "2.0MB");
        assert_eq!(format_memory(204800.0), "200MB");
        assert_eq!(format_memory(2.0 * 1024.0 * 1024.0), "2.00GB");
        assert_eq!(format_memory(16.0 * 1024.0 * 1024.0), "16.0GB");
    }
}
