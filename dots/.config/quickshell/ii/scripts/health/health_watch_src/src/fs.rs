//! Filesystem fill: statvfs on every real filesystem, one entry per device,
//! with a 24 h ring of samples to tell how fast each one is filling.

use serde_json::{json, Value};
use std::collections::{HashMap, VecDeque};

const REAL: [&str; 15] = [
    "ext2", "ext3", "ext4", "btrfs", "xfs", "f2fs", "vfat", "exfat", "ntfs3", "ntfs", "fuseblk", "zfs", "bcachefs", "jfs", "reiserfs",
];
const RING_STEP_MS: u64 = 10 * 60 * 1000;
const RING_SPAN_MS: u64 = 24 * 3600 * 1000;

#[derive(Default)]
pub struct Fs {
    rings: HashMap<String, VecDeque<(u64, u64)>>,
}

pub struct Mount {
    pub device: String,
    pub mount: String,
    pub fstype: String,
}

fn unescape_mount(s: &str) -> String {
    // /proc/self/mounts escapes space, tab, newline and backslash as \ooo.
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'\\' && i + 3 < b.len() {
            if let Ok(v) = u8::from_str_radix(&s[i + 1..i + 4], 8) {
                out.push(v);
                i += 4;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

pub fn mounts() -> Vec<Mount> {
    let text = std::fs::read_to_string("/proc/self/mounts").unwrap_or_default();
    let mut by_dev: HashMap<String, Mount> = HashMap::new();
    for line in text.lines() {
        let mut it = line.split_whitespace();
        let (Some(dev), Some(mnt), Some(fstype)) = (it.next(), it.next(), it.next()) else { continue };
        if !REAL.contains(&fstype) {
            continue;
        }
        let mnt = unescape_mount(mnt);
        if mnt.starts_with("/run/") || mnt.starts_with("/proc") || mnt.starts_with("/sys") || mnt.starts_with("/var/lib/docker") || mnt.starts_with("/snap/") {
            continue;
        }
        let entry = Mount { device: dev.to_string(), mount: mnt.clone(), fstype: fstype.to_string() };
        match by_dev.get(dev) {
            // The shortest mount point names a device best: `/` over `/home` on one partition.
            Some(existing) if existing.mount.len() <= mnt.len() => {}
            _ => {
                by_dev.insert(dev.to_string(), entry);
            }
        }
    }
    let mut v: Vec<Mount> = by_dev.into_values().collect();
    v.sort_by(|a, b| a.mount.cmp(&b.mount));
    v
}

pub struct Stat {
    pub total: u64,
    pub avail: u64,
    pub free: u64,
    pub files: u64,
    pub ffree: u64,
}

pub fn statvfs(path: &str) -> Option<Stat> {
    let c = std::ffi::CString::new(path).ok()?;
    unsafe {
        let mut s: libc::statvfs = std::mem::zeroed();
        if libc::statvfs(c.as_ptr(), &mut s) != 0 {
            return None;
        }
        let frsize = if s.f_frsize > 0 { s.f_frsize } else { s.f_bsize } as u64;
        Some(Stat {
            total: s.f_blocks as u64 * frsize,
            avail: s.f_bavail as u64 * frsize,
            free: s.f_bfree as u64 * frsize,
            files: s.f_files as u64,
            ffree: s.f_ffree as u64,
        })
    }
}

impl Fs {
    pub fn sample(&mut self, now: u64) -> Vec<Value> {
        let mut out = Vec::new();
        for m in mounts() {
            let Some(st) = statvfs(&m.mount) else { continue };
            if st.total == 0 {
                continue;
            }
            let used = st.total.saturating_sub(st.free);
            // Percent of what this user can use, the way df reports it.
            let usable = used + st.avail;
            let used_pct = if usable > 0 { used as f64 * 100.0 / usable as f64 } else { 0.0 };
            let inodes_pct = if st.files > 0 { (st.files - st.ffree.min(st.files)) as f64 * 100.0 / st.files as f64 } else { 0.0 };
            let ring = self.rings.entry(m.device.clone()).or_default();
            if ring.back().is_none_or(|(t, _)| now.saturating_sub(*t) >= RING_STEP_MS) {
                ring.push_back((now, used));
            }
            while ring.front().is_some_and(|(t, _)| now.saturating_sub(*t) > RING_SPAN_MS) {
                ring.pop_front();
            }
            let eta = eta_days(ring, now, used, st.avail);
            out.push(json!({
                "mount": m.mount,
                "device": m.device,
                "fstype": m.fstype,
                "total": st.total,
                "avail": st.avail,
                "usedPct": (used_pct * 10.0).round() / 10.0,
                "inodesPct": (inodes_pct * 10.0).round() / 10.0,
                "etaDays": eta,
            }));
        }
        out
    }
}

/// Days until full at the observed fill rate, when the span is at least an hour
/// and the filesystem is growing.
fn eta_days(ring: &VecDeque<(u64, u64)>, now: u64, used: u64, avail: u64) -> Option<f64> {
    let (t0, u0) = *ring.front()?;
    let span = now.saturating_sub(t0);
    if span < 3600 * 1000 || used <= u0 {
        return None;
    }
    let per_ms = (used - u0) as f64 / span as f64;
    let days = avail as f64 / per_ms / 86_400_000.0;
    if days > 3650.0 { None } else { Some((days * 10.0).round() / 10.0) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn eta() {
        let mut r = VecDeque::new();
        r.push_back((0u64, 100u64));
        // 100 bytes per hour, 2400 bytes left: one day.
        assert_eq!(eta_days(&r, 3_600_000, 200, 2400), Some(1.0));
        assert_eq!(eta_days(&r, 1000, 200, 2400), None);
        assert_eq!(eta_days(&r, 3_600_000, 100, 2400), None);
    }

    #[test]
    fn mount_escapes() {
        assert_eq!(unescape_mount("/mnt/my\\040disk"), "/mnt/my disk");
    }
}
