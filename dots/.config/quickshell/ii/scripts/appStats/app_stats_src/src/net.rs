//! Per-socket TCP byte counters, read without privileges.
//!
//! The kernel publishes `tcp_info` for every TCP socket through
//! `NETLINK_SOCK_DIAG` — the same dump `ss -ti` prints — and `tcpi_bytes_acked` /
//! `tcpi_bytes_received` are cumulative per socket. A socket is matched to its
//! process by inode, through `/proc/<pid>/fd/*` pointing at `socket:[<inode>]`.
//!
//! Sockets are keyed by their kernel cookie rather than their inode: a socket the
//! application has closed but the kernel is still flushing (FIN_WAIT, an orphan) has
//! lost its inode, and so has the final record the kernel broadcasts when it frees
//! one. Both still carry the cookie, which is how the last bytes of a connection the
//! sampler already knew reach the right app instead of the residual.
//!
//! What this cannot see, and why the device row carries a residual: UDP has no byte
//! counters here, so QUIC (HTTP/3) is invisible; a connection that opens and closes
//! between two samples was never matched to a process; and sockets of other users
//! (root daemons) are left out. The physical interfaces' own counters give the total
//! those gaps are measured against.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::mem::size_of;

const SOCK_DIAG_BY_FAMILY: u16 = 20;
const NLMSG_ERROR: u16 = 2;
const NLMSG_DONE: u16 = 3;
const INET_DIAG_INFO: u16 = 2;

/// `struct inet_diag_msg`: the fixed head of every reply, before its attributes.
const DIAG_MSG_LEN: usize = 72;
const DIAG_MSG_UID: usize = 64;
const DIAG_MSG_INODE: usize = 68;
const DIAG_MSG_DST: usize = 24;
const DIAG_MSG_COOKIE: usize = 44;
/// `struct tcp_info` offsets, checked against <linux/tcp.h>.
const TCPI_BYTES_ACKED: usize = 120;
const TCPI_BYTES_RECEIVED: usize = 128;

/// Every state a socket can carry data in. LISTEN holds none, and TIME_WAIT/CLOSE
/// sockets no longer belong to any process (their inode is 0).
const STATES: u32 = (1 << 1) // ESTABLISHED
    | (1 << 2) // SYN_SENT
    | (1 << 3) // SYN_RECV
    | (1 << 4) // FIN_WAIT1
    | (1 << 5) // FIN_WAIT2
    | (1 << 8) // CLOSE_WAIT
    | (1 << 9) // LAST_ACK
    | (1 << 11); // CLOSING

/// Multicast groups SKNLGRP_INET_TCP_DESTROY (1) and SKNLGRP_INET6_TCP_DESTROY (3),
/// as a bind mask. Joining them needs no privilege.
const GROUPS_TCP_DESTROY: u32 = (1 << 0) | (1 << 2);

pub struct Sock {
    pub cookie: u64,
    /// 0 once the application has let go of the socket.
    pub inode: u64,
    pub uid: u32,
    /// Bytes the peer acknowledged — sent, retransmissions excluded.
    pub tx: u64,
    pub rx: u64,
}

#[repr(C)]
struct NlMsgHdr {
    len: u32,
    kind: u16,
    flags: u16,
    seq: u32,
    pid: u32,
}

#[repr(C)]
struct DiagReq {
    family: u8,
    protocol: u8,
    ext: u8,
    pad: u8,
    states: u32,
    /// `struct inet_diag_sockid`, left zeroed: no filter.
    id: [u8; 48],
}

#[repr(C)]
struct Request {
    hdr: NlMsgHdr,
    req: DiagReq,
}

fn u32_at(b: &[u8], off: usize) -> Option<u32> {
    Some(u32::from_ne_bytes(b.get(off..off + 4)?.try_into().ok()?))
}

fn u64_at(b: &[u8], off: usize) -> Option<u64> {
    Some(u64::from_ne_bytes(b.get(off..off + 8)?.try_into().ok()?))
}

/// A connection to this machine itself is not network use.
fn is_loopback(family: u8, dst: &[u8]) -> bool {
    match family {
        f if f as i32 == libc::AF_INET => dst.first() == Some(&127),
        f if f as i32 == libc::AF_INET6 => {
            let Some(a) = dst.get(..16) else { return false };
            let v6_lo = a[..15].iter().all(|&x| x == 0) && a[15] == 1;
            let v4_mapped_lo =
                a[..10].iter().all(|&x| x == 0) && a[10] == 0xff && a[11] == 0xff && a[12] == 127;
            v6_lo || v4_mapped_lo
        }
        _ => false,
    }
}

/// One `SOCK_DIAG_BY_FAMILY` dump for one address family, appended to `out`.
fn dump_family(fd: i32, family: u8, out: &mut Vec<Sock>) -> bool {
    let req = Request {
        hdr: NlMsgHdr {
            len: size_of::<Request>() as u32,
            kind: SOCK_DIAG_BY_FAMILY,
            flags: (libc::NLM_F_REQUEST | libc::NLM_F_DUMP) as u16,
            seq: family as u32,
            pid: 0,
        },
        req: DiagReq {
            family,
            protocol: libc::IPPROTO_TCP as u8,
            ext: 1 << (INET_DIAG_INFO - 1),
            pad: 0,
            states: STATES,
            id: [0; 48],
        },
    };
    let sent = unsafe {
        libc::send(
            fd,
            &req as *const Request as *const libc::c_void,
            size_of::<Request>(),
            0,
        )
    };
    if sent < 0 {
        return false;
    }

    let mut buf = vec![0u8; 64 * 1024];
    loop {
        let n = unsafe { libc::recv(fd, buf.as_mut_ptr() as *mut libc::c_void, buf.len(), 0) };
        if n <= 0 {
            return false;
        }
        let data = &buf[..n as usize];
        let mut off = 0usize;
        while off + 16 <= data.len() {
            let Some(len) = u32_at(data, off).map(|l| l as usize) else {
                break;
            };
            let kind = u16::from_ne_bytes([data[off + 4], data[off + 5]]);
            if len < 16 || off + len > data.len() {
                break;
            }
            match kind {
                NLMSG_DONE => return true,
                NLMSG_ERROR => return false,
                SOCK_DIAG_BY_FAMILY => {
                    if let Some(s) = parse_msg(&data[off + 16..off + len]) {
                        out.push(s);
                    }
                }
                _ => {}
            }
            off += (len + 3) & !3;
        }
    }
}

/// One `inet_diag_msg` with its `tcp_info`. Ownership is not filtered here: an
/// orphaned socket reports uid 0, and the caller knows which cookies are its own.
fn parse_msg(msg: &[u8]) -> Option<Sock> {
    if msg.len() < DIAG_MSG_LEN {
        return None;
    }
    if is_loopback(msg[0], &msg[DIAG_MSG_DST..DIAG_MSG_DST + 16]) {
        return None;
    }
    let uid = u32_at(msg, DIAG_MSG_UID)?;
    let inode = u32_at(msg, DIAG_MSG_INODE)? as u64;
    let cookie =
        u32_at(msg, DIAG_MSG_COOKIE)? as u64 | (u32_at(msg, DIAG_MSG_COOKIE + 4)? as u64) << 32;

    // Attributes follow the fixed head, each 4-byte aligned: u16 len, u16 type.
    let mut off = DIAG_MSG_LEN;
    while off + 4 <= msg.len() {
        let alen = u16::from_ne_bytes([msg[off], msg[off + 1]]) as usize;
        let atype = u16::from_ne_bytes([msg[off + 2], msg[off + 3]]);
        if alen < 4 || off + alen > msg.len() {
            break;
        }
        if atype == INET_DIAG_INFO {
            let info = &msg[off + 4..off + alen];
            // An older kernel's shorter tcp_info lacks the byte counters; reading
            // past it would be garbage, so such a socket is simply not counted.
            return Some(Sock {
                cookie,
                inode,
                uid,
                tx: u64_at(info, TCPI_BYTES_ACKED)?,
                rx: u64_at(info, TCPI_BYTES_RECEIVED)?,
            });
        }
        off += (alen + 3) & !3;
    }
    None
}

/// Every non-loopback TCP socket on the machine that can carry traffic, IPv4 and
/// IPv6. Empty when the netlink socket cannot be opened, which reads as "no traffic
/// seen", never an error.
pub fn dump() -> Vec<Sock> {
    let fd = unsafe {
        libc::socket(
            libc::AF_NETLINK,
            libc::SOCK_DGRAM | libc::SOCK_CLOEXEC,
            libc::NETLINK_SOCK_DIAG,
        )
    };
    if fd < 0 {
        return Vec::new();
    }
    let mut out = Vec::with_capacity(256);
    dump_family(fd, libc::AF_INET as u8, &mut out);
    dump_family(fd, libc::AF_INET6 as u8, &mut out);
    unsafe { libc::close(fd) };
    out
}

/// Block on the kernel's TCP destroy broadcast and hand each freed socket's final
/// counters to `on_closed`. Machine-wide: the receiver drops cookies it never saw.
/// Returns only if the netlink socket cannot be set up or fails.
pub fn watch_closed(mut on_closed: impl FnMut(Sock) -> bool) {
    let fd = unsafe {
        libc::socket(
            libc::AF_NETLINK,
            libc::SOCK_DGRAM | libc::SOCK_CLOEXEC,
            libc::NETLINK_SOCK_DIAG,
        )
    };
    if fd < 0 {
        return;
    }
    let mut addr: libc::sockaddr_nl = unsafe { std::mem::zeroed() };
    addr.nl_family = libc::AF_NETLINK as u16;
    addr.nl_groups = GROUPS_TCP_DESTROY;
    let ok = unsafe {
        libc::bind(
            fd,
            &addr as *const libc::sockaddr_nl as *const libc::sockaddr,
            size_of::<libc::sockaddr_nl>() as u32,
        )
    };
    if ok != 0 {
        unsafe { libc::close(fd) };
        return;
    }

    let mut buf = vec![0u8; 64 * 1024];
    loop {
        let n = unsafe { libc::recv(fd, buf.as_mut_ptr() as *mut libc::c_void, buf.len(), 0) };
        if n < 0 {
            // ENOBUFS: a burst outran the socket buffer. Those tails go to the
            // residual; the stream itself is still good.
            if std::io::Error::last_os_error().raw_os_error() == Some(libc::ENOBUFS) {
                continue;
            }
            break;
        }
        let data = &buf[..n as usize];
        let mut off = 0usize;
        while off + 16 <= data.len() {
            let Some(len) = u32_at(data, off).map(|l| l as usize) else {
                break;
            };
            if len < 16 || off + len > data.len() {
                break;
            }
            if let Some(s) = parse_msg(&data[off + 16..off + len]) {
                if !on_closed(s) {
                    unsafe { libc::close(fd) };
                    return;
                }
            }
            off += (len + 3) & !3;
        }
    }
    unsafe { libc::close(fd) };
}

/// Interfaces backed by hardware: Wi-Fi, Ethernet, a USB tether. Tunnels, bridges,
/// veths and loopback have no `device` link, and leaving them out is what keeps a
/// VPN's traffic from being counted once inside the tunnel and again outside it.
pub fn iface_counters() -> HashMap<String, (u64, u64)> {
    let mut out = HashMap::new();
    let Ok(dir) = fs::read_dir("/sys/class/net") else {
        return out;
    };
    for entry in dir.flatten() {
        let path = entry.path();
        if !path.join("device").exists() {
            continue;
        }
        let read = |f: &str| {
            fs::read_to_string(path.join("statistics").join(f))
                .ok()
                .and_then(|s| s.trim().parse::<u64>().ok())
        };
        if let (Some(rx), Some(tx)) = (read("rx_bytes"), read("tx_bytes")) {
            out.insert(entry.file_name().to_string_lossy().into_owned(), (rx, tx));
        }
    }
    out
}

/// Map the wanted socket inodes to the pid holding them, reading `fd` links of the
/// given pids only. Stops as soon as every wanted inode is found. A socket shared
/// between processes (inherited across fork) goes to the first pid seen holding it.
pub fn owners(pids: &[u32], wanted: &HashSet<u64>) -> HashMap<u64, u32> {
    let mut out = HashMap::new();
    if wanted.is_empty() {
        return out;
    }
    for &pid in pids {
        let Ok(fds) = fs::read_dir(format!("/proc/{pid}/fd")) else {
            continue;
        };
        for fd in fds.flatten() {
            let Ok(target) = fs::read_link(fd.path()) else {
                continue;
            };
            let Some(t) = target.to_str() else { continue };
            let Some(inode) = t
                .strip_prefix("socket:[")
                .and_then(|r| r.strip_suffix(']'))
                .and_then(|n| n.parse::<u64>().ok())
            else {
                continue;
            };
            if wanted.contains(&inode) {
                out.entry(inode).or_insert(pid);
                if out.len() == wanted.len() {
                    return out;
                }
            }
        }
    }
    out
}
