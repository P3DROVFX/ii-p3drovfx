//! One pass over `/proc`: pid, ppid, comm, CPU ticks, RSS and start time.
//!
//! Everything is taken from `/proc/<pid>/stat` alone — RSS is field 24, so there is
//! no need to open `statm` as well. At ~450 processes the whole sweep is a few
//! hundred microseconds.

use std::collections::{HashMap, HashSet};
use std::fs;

/// PF_KTHREAD. Kernel threads have no userspace identity and never belong to an app.
const PF_KTHREAD: u64 = 0x0020_0000;

#[derive(Clone)]
pub struct Proc {
    pub pid: u32,
    pub ppid: u32,
    pub comm: String,
    /// utime + stime, in clock ticks.
    pub cpu_ticks: u64,
    pub rss_pages: u64,
    /// Boot-relative start time; disambiguates a recycled pid.
    pub starttime: u64,
}

pub struct Sweep {
    pub procs: Vec<Proc>,
    pub index: HashMap<u32, usize>,
    /// Sum of all non-idle CPU time across every core, in clock ticks.
    pub busy_ticks: u64,
}

pub fn page_size() -> u64 {
    unsafe { libc::sysconf(libc::_SC_PAGESIZE) as u64 }
}

pub fn clk_tck() -> u64 {
    unsafe { libc::sysconf(libc::_SC_CLK_TCK) as u64 }
}

/// Fields are 1-indexed in proc(5). `comm` may itself contain spaces and
/// parentheses, so the split starts after the *last* `)`, which puts field 3
/// (state) at `rest[0]` — hence every index below is `field - 3`.
fn parse_stat(pid: u32, s: &str) -> Option<Proc> {
    let open = s.find('(')?;
    let close = s.rfind(')')?;
    let comm = s.get(open + 1..close)?.to_string();
    let rest: Vec<&str> = s.get(close + 2..)?.split_whitespace().collect();
    if rest.len() < 22 {
        return None;
    }

    let flags: u64 = rest[6].parse().ok()?;
    if flags & PF_KTHREAD != 0 {
        return None;
    }

    Some(Proc {
        pid,
        ppid: rest[1].parse().ok()?,
        comm,
        cpu_ticks: rest[11].parse::<u64>().ok()? + rest[12].parse::<u64>().ok()?,
        starttime: rest[19].parse().ok()?,
        rss_pages: rest[21].parse().ok()?,
    })
}

/// Non-idle ticks from the aggregate `cpu` line: user, nice, system, irq,
/// softirq and steal. idle and iowait are deliberately excluded — the denominator
/// for a CPU share must be busy time, not wall time.
fn busy_ticks() -> u64 {
    let Ok(s) = fs::read_to_string("/proc/stat") else {
        return 0;
    };
    let Some(line) = s.lines().next() else {
        return 0;
    };
    let f: Vec<u64> = line
        .split_whitespace()
        .skip(1)
        .filter_map(|t| t.parse().ok())
        .collect();
    if f.len() < 8 {
        return 0;
    }
    f[0] + f[1] + f[2] + f[5] + f[6] + f[7]
}

pub fn sweep() -> Sweep {
    let mut procs = Vec::with_capacity(512);

    if let Ok(dir) = fs::read_dir("/proc") {
        for entry in dir.flatten() {
            let name = entry.file_name();
            let Some(name) = name.to_str() else { continue };
            let Ok(pid) = name.parse::<u32>() else { continue };

            // A process can exit between readdir and read; that is expected, not an error.
            let Ok(stat) = fs::read_to_string(format!("/proc/{pid}/stat")) else {
                continue;
            };
            if let Some(p) = parse_stat(pid, &stat) {
                procs.push(p);
            }
        }
    }

    let index = procs.iter().enumerate().map(|(i, p)| (p.pid, i)).collect();
    Sweep {
        procs,
        index,
        busy_ticks: busy_ticks(),
    }
}

impl Sweep {
    /// Nearest ancestor of `pid` (itself included) that owns a window, or `None`.
    ///
    /// The walk is bounded by `MAX_DEPTH` rather than by reaching pid 1, so a
    /// cycle introduced by a torn read of `/proc` cannot hang the sampler.
    pub fn window_root(&self, pid: u32, clients: &HashMap<u32, usize>) -> Option<usize> {
        const MAX_DEPTH: usize = 64;
        let mut cur = pid;
        for _ in 0..MAX_DEPTH {
            if let Some(&c) = clients.get(&cur) {
                return Some(c);
            }
            let idx = *self.index.get(&cur)?;
            let ppid = self.procs[idx].ppid;
            if ppid <= 1 {
                return None;
            }
            cur = ppid;
        }
        None
    }

    /// Ancestors of `pid`, itself excluded.
    ///
    /// The sampler's own ancestry is the session's spine — quickshell, the
    /// compositor, the login helper — and folding a daemon into any of those
    /// produces one enormous bucket instead of the per-service breakdown that makes
    /// background drain visible in the first place.
    pub fn ancestors(&self, pid: u32) -> HashSet<u32> {
        const MAX_DEPTH: usize = 64;
        let mut out = HashSet::new();
        let mut cur = pid;
        for _ in 0..MAX_DEPTH {
            let Some(&idx) = self.index.get(&cur) else { break };
            let ppid = self.procs[idx].ppid;
            if ppid <= 1 || !out.insert(ppid) {
                break;
            }
            cur = ppid;
        }
        out
    }

    /// Topmost ancestor below the nearest session boundary — the "leader" a headless
    /// tree is named after.
    pub fn service_root(&self, pid: u32, boundaries: &HashSet<u32>) -> u32 {
        const MAX_DEPTH: usize = 64;
        let mut cur = pid;
        for _ in 0..MAX_DEPTH {
            let Some(&idx) = self.index.get(&cur) else {
                return cur;
            };
            let ppid = self.procs[idx].ppid;
            if ppid <= 1 || boundaries.contains(&ppid) {
                return cur;
            }
            let Some(&pidx) = self.index.get(&ppid) else {
                return cur;
            };
            if is_session_leader(&self.procs[pidx].comm) {
                return cur;
            }
            cur = ppid;
        }
        cur
    }
}

/// Processes that own a session rather than do work in it. Named explicitly because
/// they are indistinguishable from ordinary parents otherwise — every process in a
/// Hyprland session shares one session id, so `getsid` cannot find this boundary.
/// The list only matters when the sampler is started outside the session (a systemd
/// unit, say); launched from the shell, its own ancestry already covers these.
pub fn is_session_leader(comm: &str) -> bool {
    matches!(
        comm,
        "systemd"
            | "init"
            | "Hyprland"
            | "start-hyprland"
            | "uwsm"
            | "sddm"
            | "sddm-helper"
            | "gdm"
            | "gdm-session-worker"
            | "lightdm"
            | "greetd"
            | "login"
            | "sshd"
            | "sshd-session"
    )
}
