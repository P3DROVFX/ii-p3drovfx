//! Exact per-process network bytes for the `app_stats` sampler.
//!
//! Loads `net.bpf.c` (see there for what is counted and how sockets are tied to
//! processes), then answers the sampler over stdin/stdout. It needs `CAP_BPF`,
//! `CAP_PERFMON` and `CAP_NET_ADMIN`, granted as file capabilities on a root-owned
//! copy (see the README); it never runs as root.
//!
//! Every program is attached through a BPF link owned by this process, so all of them
//! detach the moment it exits, however it exits. Nothing is pinned.
//!
//! Protocol, one line each way:
//!   stdin  `d`   dump: bytes moved since the previous dump
//!   stdin  `q`   (or EOF) exit
//!   stdout `{"t":"ready"}` once attached
//!   stdout `{"t":"dump","p":[[tgid,ppid,"comm",rx,tx],...],"u":[rx,tx]}` per `d`
//!   stdout `{"t":"error","msg":"..."}` then exit 1, when loading or attaching fails
//!
//! `p` holds one entry per process that moved data since the last dump; `u` is data on
//! sockets no process ever touched through sendmsg/recvmsg (kernel-owned sockets).

use std::collections::{HashMap, HashSet};
use std::error::Error;
use std::fs::File;
use std::io::{BufRead, Write};
use std::mem::MaybeUninit;
use std::os::fd::AsRawFd;

use libbpf_rs::skel::{OpenSkel, SkelBuilder};
use libbpf_rs::{Link, MapCore, MapFlags};

mod skel {
    include!(concat!(env!("OUT_DIR"), "/net.skel.rs"));
}
use skel::*;

/// Dumps a socket may sit unchanged before it is forgotten. A closed socket stops
/// changing at once; an idle one that wakes up later just starts again from zero.
const PRUNE_IDLE: u32 = 6;
/// Dumps a socket may move data without an owner before that data is reported as
/// unowned. Normally the owner arrives within milliseconds, with the first read.
const UNTAGGED_GRACE: u32 = 3;
const BATCH: u32 = 512;

#[derive(Default)]
struct Prev {
    rx: u64,
    tx: u64,
    idle: u32,
    untagged: u32,
}

struct Owner {
    tgid: u32,
    ppid: u32,
    comm: String,
}

fn u32_at(b: &[u8], off: usize) -> u32 {
    b.get(off..off + 4)
        .and_then(|s| s.try_into().ok())
        .map(u32::from_ne_bytes)
        .unwrap_or(0)
}

fn u64_at(b: &[u8], off: usize) -> u64 {
    b.get(off..off + 8)
        .and_then(|s| s.try_into().ok())
        .map(u64::from_ne_bytes)
        .unwrap_or(0)
}

fn json_str(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

fn parse_owner(v: &[u8]) -> Owner {
    let comm = v.get(8..24).unwrap_or(&[]);
    let end = comm.iter().position(|&b| b == 0).unwrap_or(comm.len());
    Owner {
        tgid: u32_at(v, 0),
        ppid: u32_at(v, 4),
        comm: String::from_utf8_lossy(&comm[..end]).into_owned(),
    }
}

struct State {
    prev: HashMap<u64, Prev>,
    /// Owners whose socket has had no packet counted for this many dumps — almost
    /// always a loopback socket, which is tagged on use but never counted.
    orphan_owner: HashMap<u64, u32>,
}

fn dump(skel: &NetSkel, st: &mut State) -> Result<String, Box<dyn Error>> {
    let owners: HashMap<u64, Owner> = skel
        .maps
        .owners
        .lookup_batch(BATCH, MapFlags::ANY, MapFlags::ANY)?
        .map(|(k, v)| (u64_at(&k, 0), parse_owner(&v)))
        .collect();

    let mut per: HashMap<u32, (u32, String, u64, u64)> = HashMap::new();
    let (mut un_rx, mut un_tx) = (0u64, 0u64);
    let mut seen: HashSet<u64> = HashSet::new();
    let mut stale: Vec<u64> = Vec::new();

    for (k, v) in skel
        .maps
        .bytes
        .lookup_batch(BATCH, MapFlags::ANY, MapFlags::ANY)?
    {
        let cookie = u64_at(&k, 0);
        let (rx, tx) = (u64_at(&v, 0), u64_at(&v, 8));
        seen.insert(cookie);
        let p = st.prev.entry(cookie).or_default();
        let (drx, dtx) = (rx.saturating_sub(p.rx), tx.saturating_sub(p.tx));
        if drx + dtx == 0 {
            p.idle += 1;
            if p.idle >= PRUNE_IDLE {
                stale.push(cookie);
            }
            continue;
        }
        p.idle = 0;
        match owners.get(&cookie) {
            Some(o) => {
                let e = per
                    .entry(o.tgid)
                    .or_insert_with(|| (o.ppid, o.comm.clone(), 0, 0));
                e.2 += drx;
                e.3 += dtx;
                p.rx = rx;
                p.tx = tx;
                p.untagged = 0;
            }
            // Held back, not lost: the bytes stay on the cookie and go to the owner
            // with its first read. Only a socket that never gets one is let go.
            None => {
                p.untagged += 1;
                if p.untagged >= UNTAGGED_GRACE {
                    un_rx += drx;
                    un_tx += dtx;
                    p.rx = rx;
                    p.tx = tx;
                }
            }
        }
    }

    for cookie in &stale {
        let key = cookie.to_ne_bytes();
        let _ = skel.maps.bytes.delete(&key);
        let _ = skel.maps.owners.delete(&key);
        st.prev.remove(cookie);
    }
    // Entries the kernel's LRU dropped on its own.
    st.prev.retain(|k, _| seen.contains(k));

    for cookie in owners.keys() {
        if seen.contains(cookie) {
            st.orphan_owner.remove(cookie);
            continue;
        }
        let n = st.orphan_owner.entry(*cookie).or_insert(0);
        *n += 1;
        if *n >= PRUNE_IDLE {
            let _ = skel.maps.owners.delete(&cookie.to_ne_bytes());
        }
    }
    st.orphan_owner
        .retain(|k, n| owners.contains_key(k) && *n < PRUNE_IDLE);

    let mut out = String::from("{\"t\":\"dump\",\"p\":[");
    for (i, (tgid, (ppid, comm, rx, tx))) in per.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        out.push_str(&format!("[{tgid},{ppid},{},{rx},{tx}]", json_str(comm)));
    }
    out.push_str(&format!("],\"u\":[{un_rx},{un_tx}]}}"));
    Ok(out)
}

fn run() -> Result<(), Box<dyn Error>> {
    // Each stage names itself: "Permission denied" alone could be a missing capability
    // (the file was copied), the group, or the verifier refusing the program.
    let ctx = |stage: &'static str| move |e: libbpf_rs::Error| format!("{stage}: {e}");
    let mut object = MaybeUninit::uninit();
    let skel = NetSkelBuilder::default()
        .open(&mut object)
        .map_err(ctx("opening the BPF object"))?
        .load()
        .map_err(ctx(
            "loading the BPF programs (capabilities, or the kernel's verifier)",
        ))?;

    let cgroup =
        File::open("/sys/fs/cgroup").map_err(|e| format!("opening /sys/fs/cgroup: {e}"))?;
    let mut links: Vec<Link> = vec![
        skel.progs
            .count_ingress
            .attach_cgroup(cgroup.as_raw_fd())
            .map_err(ctx("attaching to the root cgroup"))?,
        skel.progs
            .count_egress
            .attach_cgroup(cgroup.as_raw_fd())
            .map_err(ctx("attaching to the root cgroup"))?,
    ];
    for prog in [
        &skel.progs.tag_tcp_send,
        &skel.progs.tag_tcp_recv,
        &skel.progs.tag_udp_send,
        &skel.progs.tag_udp_recv,
        &skel.progs.tag_udp6_send,
        &skel.progs.tag_udp6_recv,
    ] {
        links.push(
            prog.attach()
                .map_err(ctx("attaching a send/receive hook"))?,
        );
    }

    let mut stdout = std::io::stdout().lock();
    writeln!(stdout, "{{\"t\":\"ready\"}}")?;
    stdout.flush()?;

    let mut st = State {
        prev: HashMap::new(),
        orphan_owner: HashMap::new(),
    };
    for line in std::io::stdin().lock().lines() {
        match line?.trim() {
            "d" => {
                let reply = dump(&skel, &mut st)?;
                writeln!(stdout, "{reply}")?;
                stdout.flush()?;
            }
            "q" => break,
            _ => {}
        }
    }
    drop(links);
    Ok(())
}

fn main() {
    // A file-capability binary loses an inherited parent-death signal at exec, so it
    // is set again here: the programs must not outlive the sampler that reads them.
    unsafe {
        libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
    }
    if let Err(e) = run() {
        println!("{{\"t\":\"error\",\"msg\":{}}}", json_str(&e.to_string()));
        std::process::exit(1);
    }
}
