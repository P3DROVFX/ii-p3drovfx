//! The second screen's video over UDP (PROTOCOL.md, "Second screen", `udp`).
//!
//! Over the WebSocket a lost packet holds back every frame behind it until TCP resends it:
//! on Wi-Fi that was the stream's freezes. Here each frame goes out as datagrams on the
//! link's own UDP port (the one discovery answers on, so no firewall rule of its own), cut
//! into [`SHARD`]-byte shards with Reed–Solomon parity per block of up to [`KMAX`]: the
//! phone rebuilds a frame from any `k` of a block's `k + m` shards, and nothing waits for a
//! resend. A frame that can't be rebuilt is the phone's to skip (it asks for a key frame).
//!
//! Every datagram is AES-256-GCM sealed with a key sent over the link's TLS socket, the
//! nonce a direction and a counter that never repeats under one key. The phone's hellos
//! (every 500 ms, sealed the same way) tell the PC where to send and keep NAT and Wi-Fi
//! power saving open; without one for [`PEER_TIMEOUT`] the video goes back to the WebSocket.
//!
//! Shard datagram: `[0xA7][1][u64 counter][u32 frame][u32 frame_len][u8 block][u8 blocks]
//! [u8 shard][u8 k][u8 m][0]` (24 bytes, the AEAD's associated data), then the sealed shard
//! (always SHARD bytes; the frame length says where the last one's padding starts) and its
//! 16-byte tag. The frame is the WebSocket's video payload as is: `[u8 kind][u64 pts][…]`.
//! Phone hello: `[0xA7][2][u64 counter]`, then the sealed `u32` session id and the tag.

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use reed_solomon_erasure::galois_8::ReedSolomon;
use ring::aead::{Aad, LessSafeKey, Nonce, UnboundKey, AES_256_GCM};
use ring::rand::{SecureRandom, SystemRandom};
use tokio::net::UdpSocket;

/// First byte of every screen datagram (never ASCII: discovery's "iilink?" shares the port).
pub const MAGIC: u8 = 0xA7;
const T_SHARD: u8 = 1;
const T_HELLO: u8 = 2;
/// Shard bytes: header, shard and tag (1164) plus IP and UDP fit Tailscale's 1280 MTU.
pub const SHARD: usize = 1100;
/// Data shards per Reed–Solomon block (k + m stays under GF(2^8)'s 256).
const KMAX: usize = 128;
const HEADER: usize = 24;
const TAG: usize = 16;
/// A phone not heard from this long has gone (or its UDP is blocked): back to the WebSocket.
const PEER_TIMEOUT: Duration = Duration::from_secs(3);
/// A large frame (a key frame, ~500 KB) goes out no faster than this: a burst the size of
/// the AP's queue is where Wi-Fi drops packets in a row, more than parity can cover.
const PACE_BPS: u64 = 200_000_000;
const BURST: usize = 32;

/// The session's key and where its phone is: shared by the session's sender and the
/// discovery socket's reader, which hands it the phone's hellos.
pub struct Peer {
    key: LessSafeKey,
    raw_key: [u8; 32],
    sid: u32,
    addr: Mutex<Option<(SocketAddr, Instant)>>,
    last_hello: AtomicU64,
}

impl Peer {
    pub fn new(sid: u32) -> Option<Arc<Peer>> {
        let mut raw_key = [0u8; 32];
        SystemRandom::new().fill(&mut raw_key).ok()?;
        let key = LessSafeKey::new(UnboundKey::new(&AES_256_GCM, &raw_key).ok()?);
        Some(Arc::new(Peer { key, raw_key, sid, addr: Mutex::new(None), last_hello: AtomicU64::new(0) }))
    }

    /// What the phone needs to receive: `{"t":"udp","port","key","sid"}` over the WebSocket.
    pub fn offer(&self, port: u16) -> serde_json::Value {
        use base64::Engine;
        serde_json::json!({
            "t": "udp",
            "port": port,
            "key": base64::engine::general_purpose::STANDARD.encode(self.raw_key),
            "sid": self.sid,
        })
    }

    /// A datagram from the phone. A sealed hello with this session's id, newer than the
    /// last, points the video at the address it came from.
    pub fn hello(&self, pkt: &[u8], from: SocketAddr) -> bool {
        if pkt.len() < 10 + 4 + TAG || pkt[0] != MAGIC || pkt[1] != T_HELLO {
            return false;
        }
        let counter = u64::from_be_bytes(pkt[2..10].try_into().unwrap());
        let mut body = pkt[10..].to_vec();
        let Ok(plain) = self.key.open_in_place(nonce(1, counter), Aad::from(&pkt[..10]), &mut body) else {
            return false;
        };
        if plain.len() < 4 || u32::from_be_bytes(plain[..4].try_into().unwrap()) != self.sid {
            return false;
        }
        // A replayed hello can't redirect the stream.
        if self.last_hello.fetch_max(counter, Ordering::SeqCst) >= counter {
            return false;
        }
        *self.addr.lock().unwrap() = Some((from, Instant::now()));
        true
    }

    /// Where to send, while the phone keeps saying hello.
    pub fn addr(&self) -> Option<SocketAddr> {
        self.addr.lock().unwrap().filter(|(_, seen)| seen.elapsed() < PEER_TIMEOUT).map(|(a, _)| a)
    }
}

/// 96-bit GCM nonce: direction (0 PC → phone, 1 phone → PC) and a per-direction counter.
fn nonce(direction: u32, counter: u64) -> Nonce {
    let mut n = [0u8; 12];
    n[..4].copy_from_slice(&direction.to_be_bytes());
    n[4..].copy_from_slice(&counter.to_be_bytes());
    Nonce::assume_unique_for_key(n)
}

/// One session's frames out over UDP.
pub struct Sender {
    sock: Arc<UdpSocket>,
    peer: Arc<Peer>,
    counter: u64,
    frame: u32,
    /// Parity as a share of each block's data shards, in percent (at least one shard).
    fec_pct: usize,
    codecs: HashMap<(usize, usize), ReedSolomon>,
    bytes: u64,
    frames: u64,
}

impl Sender {
    pub fn new(sock: Arc<UdpSocket>, peer: Arc<Peer>) -> Sender {
        Sender { sock, peer, counter: 0, frame: 0, fec_pct: 20, codecs: HashMap::new(), bytes: 0, frames: 0 }
    }

    pub fn peer(&self) -> &Arc<Peer> {
        &self.peer
    }

    pub fn port(&self) -> u16 {
        self.sock.local_addr().map(|a| a.port()).unwrap_or(0)
    }

    /// The phone's report: `loss_pct` of datagrams lost in the last second, `lost_frames`
    /// it couldn't rebuild. Parity is 3× the loss (Wi-Fi loses in bursts) over a 10% floor,
    /// and 10 points more after a frame was lost, up to 60%: raised at once, lowered by 2
    /// points a second, so one calm second doesn't undo it.
    pub fn adapt_fec(&mut self, loss_pct: f64, lost_frames: u64) {
        let mut want = (loss_pct.max(0.0) * 3.0).ceil() as usize + 10;
        if lost_frames > 0 {
            want = want.max(self.fec_pct + 10);
        }
        let want = want.clamp(10, 60);
        self.fec_pct = if want > self.fec_pct { want } else { self.fec_pct.saturating_sub(2).max(want) };
    }

    pub fn fec_pct(&self) -> usize {
        self.fec_pct
    }

    /// Bytes and frames sent since the last call (the stats line).
    pub fn take_stats(&mut self) -> (u64, u64) {
        (std::mem::take(&mut self.bytes), std::mem::take(&mut self.frames))
    }

    /// Sends one frame; false when the phone has no UDP address (send it another way).
    pub async fn send_frame(&mut self, payload: &[u8]) -> bool {
        let Some(addr) = self.peer.addr() else { return false };
        let len = payload.len();
        let per_block = SHARD * KMAX;
        let blocks = len.div_ceil(per_block).max(1);
        if blocks > u8::MAX as usize {
            return false;
        }
        self.frame = self.frame.wrapping_add(1);
        let started = Instant::now();
        let mut sent_bytes = 0u64;
        let mut in_burst = 0usize;
        for b in 0..blocks {
            let data = &payload[b * per_block..len.min((b + 1) * per_block)];
            let k = data.len().div_ceil(SHARD).max(1);
            let m = (k * self.fec_pct).div_ceil(100).max(1).min(255 - k);
            let mut shards: Vec<Vec<u8>> = (0..k + m)
                .map(|i| {
                    let mut s = vec![0u8; SHARD];
                    if i < k {
                        let from = i * SHARD;
                        let to = data.len().min(from + SHARD);
                        s[..to - from].copy_from_slice(&data[from..to]);
                    }
                    s
                })
                .collect();
            let rs = match self.codecs.entry((k, m)) {
                std::collections::hash_map::Entry::Occupied(e) => e.into_mut(),
                std::collections::hash_map::Entry::Vacant(e) => match ReedSolomon::new(k, m) {
                    Ok(rs) => e.insert(rs),
                    Err(_) => return false,
                },
            };
            if rs.encode(&mut shards).is_err() {
                return false;
            }
            for (i, shard) in shards.into_iter().enumerate() {
                self.counter += 1;
                let mut pkt = Vec::with_capacity(HEADER + SHARD + TAG);
                pkt.push(MAGIC);
                pkt.push(T_SHARD);
                pkt.extend_from_slice(&self.counter.to_be_bytes());
                pkt.extend_from_slice(&self.frame.to_be_bytes());
                pkt.extend_from_slice(&(len as u32).to_be_bytes());
                pkt.extend_from_slice(&[b as u8, blocks as u8, i as u8, k as u8, m as u8, 0]);
                let mut body = shard;
                if self.key_seal(&pkt, &mut body).is_err() {
                    return false;
                }
                pkt.extend_from_slice(&body);
                // A full socket buffer loses this datagram, as the air would: parity covers it.
                let _ = self.sock.send_to(&pkt, addr).await;
                sent_bytes += pkt.len() as u64;
                in_burst += 1;
                if in_burst == BURST {
                    in_burst = 0;
                    let due = Duration::from_nanos(sent_bytes * 8 * 1_000_000_000 / PACE_BPS);
                    if let Some(wait) = due.checked_sub(started.elapsed()) {
                        tokio::time::sleep(wait).await;
                    }
                }
            }
        }
        self.bytes += len as u64;
        self.frames += 1;
        true
    }

    fn key_seal(&self, header: &[u8], body: &mut Vec<u8>) -> Result<(), ring::error::Unspecified> {
        self.peer.key.seal_in_place_append_tag(nonce(0, self.counter), Aad::from(header), body)
    }
}
