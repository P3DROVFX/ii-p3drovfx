//! The phone as a screen for this PC (PROTOCOL.md, "Second screen"): an output the shell
//! picked (a headless one to extend, a real one to mirror) goes to the phone as H.264,
//! and the phone's touches come back as a touchscreen mapped onto that output.
//!
//! Two transports:
//! - **USB** (raw TCP on `127.0.0.1` via `adb reverse`): the first line is the one-time
//!   token; video is `[u32 length][u8 kind][u64 pts µs][Annex-B bytes]`.
//! - **Wi-Fi / link WebSocket** ([`WS_PATH`], `transport: "ws"`): a side WebSocket on
//!   the link's TLS port, authenticated by `{"t":"hello","token":"…"}`, with a 10 s
//!   reconnect grace, non-blocking writer queue, congestion dropping, adaptive bitrate,
//!   ordered `ping`/`pong`, `stats`, `quality`, and `idr`.
//!
//! Capture and encoding are wf-recorder's (wlr-screencopy, the GPU's encoder: NVENC,
//! then VA-API, then x264). It writes FLV, whose tags carry their own length and leave
//! it one per frame, so a frame goes out the moment it is encoded rather than when the
//! next one starts. The stream is damage-driven: a still screen sends nothing.

use std::collections::VecDeque;
use std::process::Stdio;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::Sender;
use std::sync::{Arc, Mutex};
use std::time::Instant;

use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::net::{TcpListener, TcpStream};
use tokio::process::{Child, ChildStdout, Command};
use tokio::sync::{mpsc, oneshot, watch, Notify};
use tokio::time::{timeout, Duration};
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::WebSocketStream;

use crate::input::Cmd;
use crate::udp;
use crate::State;

pub const WS_PATH: &str = "/iilink/1/screen";
pub type Ws = WebSocketStream<tokio_rustls::server::TlsStream<TcpStream>>;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(60);
const HELLO_TIMEOUT: Duration = Duration::from_secs(5);
const RECONNECT_GRACE: Duration = Duration::from_secs(10);
const MIN_BITRATE: u64 = 1_000_000;
const MAX_BITRATE: u64 = 80_000_000;
const FLOOR_BITRATE: u64 = 2_000_000;
const MAX_QUEUE_ITEMS: usize = 256;
const MAX_QUEUE_BYTES: usize = 16 << 20;
/// A backlog this old is dropped rather than shown late. Shorter spikes drain on their own:
/// a drop costs a frozen picture until the next key frame (an encoder restart, ~300 ms).
const CONGESTION_AGE: Duration = Duration::from_millis(200);
const CONGESTION_WINDOW: Duration = Duration::from_secs(3);
const STEP_UP_QUIET: Duration = Duration::from_secs(10);
const RATE_COOLDOWN: Duration = Duration::from_secs(2);
/// Over UDP: a second with this many frames parity couldn't rebuild is congestion (single
/// losses are Wi-Fi's own, which a lower bitrate doesn't cure).
const UDP_CONGESTED_LOST: u64 = 3;
/// Over UDP the bitrate steps back up only after this long without congestion: each change
/// restarts a VA-API encoder (a frozen picture), and UDP has no queue to show room early.
const UDP_STEP_UP_QUIET: Duration = Duration::from_secs(30);
/// A phone waiting for a key frame holds a frozen picture: answer again soon.
const IDR_COOLDOWN: Duration = Duration::from_millis(500);
/// 10 ms packets: half a second.
const AUDIO_QUEUE: usize = 50;
/// Dropping this long without a key frame: restart the encoder for one (the GOP is 2 s).
const DROP_IDR_AFTER: Duration = Duration::from_millis(250);
/// VA-API's key-frame interval in frames: none after the first, in practice (~2.3 h at
/// 120 Hz). A key frame is ~500 KB against ~30 KB frames, and every periodic one was a
/// 100 ms hitch on Wi-Fi; the phone asks (`idr`) when it needs one.
const VAAPI_GOP: u32 = 1_000_000;
/// The VUI for a picture converted BT.601 limited range from the desktop's sRGB, so the
/// phone decodes it as it was made. Unlabelled, Android assumed BT.709 and a video gamma.
const BT601_LIMITED_SRGB: [&str; 8] = [
    "-p", "colorspace=smpte170m", "-p", "color_range=tv", "-p", "color_primaries=bt709", "-p", "color_trc=iec61966-2-1",
];

/// CLOCK_MONOTONIC in µs: frame pts and `pong`'s `now` (the phone's System.nanoTime is
/// the same clock on its side; the offset between the two comes from the pings).
pub fn mono_us() -> u64 {
    let mut t = libc::timespec { tv_sec: 0, tv_nsec: 0 };
    // SAFETY: a valid timespec to fill.
    unsafe { libc::clock_gettime(libc::CLOCK_MONOTONIC, &mut t) };
    t.tv_sec as u64 * 1_000_000 + t.tv_nsec as u64 / 1000
}

/// One line on stderr (the shell's log, `[IiLink]`) for each event that costs the picture:
/// an encoder restart or a lost connection, with why. Rare by design, so always on.
fn trace(what: &str, why: &str) {
    eprintln!("screen {what}: {why}");
}

fn conn_lost(why: &str) -> WsConnEnd {
    trace("conn", why);
    WsConnEnd::Dropped
}

/// The active or pending screen session (one at a time).
pub struct Slot {
    sid: u64,
    token: Option<String>,
    conns: Option<mpsc::UnboundedSender<PhoneConn>>,
    task: tokio::task::AbortHandle,
    end: Arc<End>,
    output: watch::Sender<String>,
    /// The PC's sound for the phone: the PulseAudio source to capture, or none.
    audio: watch::Sender<Option<String>>,
    /// Wi-Fi sessions: the UDP video's key and the phone's address (udp.rs).
    udp_peer: Option<Arc<udp::Peer>>,
}

/// A phone's screen socket, and whether it asked for the video over UDP (its hello's `udp`).
type PhoneConn = (Ws, bool);

struct End {
    dev: String,
    sid: u64,
    input_tx: Sender<Cmd>,
    done: AtomicBool,
}

impl End {
    fn emit(&self, reason: &str) {
        if !self.done.swap(true, Ordering::SeqCst) {
            let _ = self.input_tx.send(Cmd::ScreenStop);
            crate::emit(json!({"ev": "screenEnd", "dev": self.dev, "sid": self.sid, "reason": reason}));
        }
    }
}

struct Guard {
    state: State,
    sid: u64,
    end: Arc<End>,
    reason: &'static str,
}

impl Drop for Guard {
    fn drop(&mut self) {
        if let Ok(mut s) = self.state.try_lock() {
            if s.screen.as_ref().is_some_and(|c| c.sid == self.sid) {
                s.screen = None;
            }
        }
        self.end.emit(self.reason);
    }
}

struct AbortOnDrop(tokio::task::AbortHandle);

impl Drop for AbortOnDrop {
    fn drop(&mut self) {
        self.0.abort();
    }
}

pub struct Params {
    pub dev: String,
    /// The shell's number for this session, in every event: an old one's end can arrive
    /// after a new one began.
    pub sid: u64,
    /// The output to capture; the shell can point a session at another one (mirror's
    /// screen switch) and the capture starts again there.
    pub output: watch::Receiver<String>,
    pub token: String,
    /// The output's size in pixels: the touchscreen's.
    pub w: i32,
    pub h: i32,
    pub bitrate: u64,
    pub fps: u32,
    pub adaptive: bool,
    /// Frames per second to cap the capture at (mirror of a fast screen), 0 for the output's own rate.
    pub rate: u32,
    pub audio: watch::Receiver<Option<String>>,
    /// The phone asked for HEVC (`codec`), H.264 still the fallback.
    pub hevc: bool,
    /// The link's UDP socket and this session's peer, for a phone that asks (Wi-Fi only).
    pub udp: Option<(Arc<tokio::net::UdpSocket>, Arc<udp::Peer>)>,
    pub input_tx: Sender<Cmd>,
}

/// The shell's `screen` ops: `start`, `output`, `stop`.
pub fn op(state: &State, op: &Value) {
    let mut s = state.lock().unwrap();
    if op["a"] == "output" {
        if let (Some(slot), Some(name)) = (s.screen.as_ref(), op["output"].as_str()) {
            let _ = slot.output.send(name.to_string());
        }
        return;
    }
    // The PC's sound on the phone, on or off, for the running Wi-Fi session.
    if op["a"] == "audio" {
        if let Some(slot) = s.screen.as_ref() {
            let src = op["source"].as_str().filter(|_| op["on"].as_bool() == Some(true)).map(str::to_owned);
            let _ = slot.audio.send(src);
        }
        return;
    }
    if let Some(old) = s.screen.take() {
        old.task.abort();
        old.end.emit("stopped");
    }
    if op["a"] != "start" {
        return;
    }
    let dev = op["dev"].as_str().unwrap_or("").to_string();
    let sid = op["sid"].as_u64().unwrap_or(0);
    let (out_tx, mut out_rx) = watch::channel(op["output"].as_str().unwrap_or("").to_string());
    out_rx.mark_unchanged();
    let (audio_tx, audio_rx) = watch::channel(None);
    let params = Params {
        dev: dev.clone(),
        sid,
        output: out_rx,
        token: op["token"].as_str().unwrap_or("").to_string(),
        w: op["w"].as_i64().unwrap_or(1920) as i32,
        h: op["h"].as_i64().unwrap_or(1080) as i32,
        bitrate: op["bitrate"].as_u64().unwrap_or(16_000_000).clamp(MIN_BITRATE, MAX_BITRATE),
        fps: op["fps"].as_u64().unwrap_or(60).clamp(15, 240) as u32,
        adaptive: op["adaptive"].as_bool().unwrap_or(true),
        rate: op["rate"].as_u64().unwrap_or(0).min(240) as u32,
        audio: audio_rx,
        input_tx: s.input_tx.clone(),
        udp: None,
        hevc: op["codec"].as_str() == Some("hevc"),
    };
    let mut params = params;
    if params.output.borrow().is_empty() || params.token.len() < 16 {
        crate::emit(json!({"ev": "screenEnd", "dev": dev, "sid": sid, "reason": "bad_arg"}));
        return;
    }
    let end = Arc::new(End { dev: dev.clone(), sid, input_tx: s.input_tx.clone(), done: AtomicBool::new(false) });
    let guard = Guard { state: state.clone(), sid, end: end.clone(), reason: "stopped" };

    if op["transport"].as_str() == Some("ws") {
        let token = params.token.clone();
        let udp_peer = s.udp.as_ref().and_then(|_| udp::Peer::new(sid as u32));
        params.udp = s.udp.clone().zip(udp_peer.clone());
        let (conn_tx, conn_rx) = mpsc::unbounded_channel();
        let task = tokio::spawn(async move {
            let mut guard = guard;
            guard.reason = run_ws(conn_rx, &params).await;
        })
        .abort_handle();
        s.screen = Some(Slot { sid, token: Some(token), conns: Some(conn_tx), task, end, output: out_tx, audio: audio_tx, udp_peer });
        crate::emit(json!({"ev": "screen", "dev": dev, "sid": sid, "port": 0, "transport": "ws"}));
        return;
    }

    let listener = match std::net::TcpListener::bind(("127.0.0.1", 0))
        .and_then(|l| {
            l.set_nonblocking(true)?;
            let port = l.local_addr()?.port();
            Ok((port, TcpListener::from_std(l)?))
        }) {
        Ok(ok) => ok,
        Err(_) => {
            // Avoid Guard::drop sending ScreenStop/stopped when bind never created a session.
            std::mem::forget(guard);
            crate::emit(json!({"ev": "screenEnd", "dev": dev, "sid": sid, "reason": "bind"}));
            return;
        }
    };
    let (port, listener) = listener;
    let task = tokio::spawn(async move {
        let mut guard = guard;
        guard.reason = run_usb(listener, &params).await;
    })
    .abort_handle();
    s.screen = Some(Slot { sid, token: None, conns: None, task, end, output: out_tx, audio: audio_tx, udp_peer: None });
    crate::emit(json!({"ev": "screen", "dev": dev, "sid": sid, "port": port}));
}

/// The phone's `/iilink/1/screen` socket: validate the hello token within 5 s, then hand
/// it to the pending or reconnecting session.
pub async fn serve(mut ws: Ws, state: State) {
    let hello = match timeout(HELLO_TIMEOUT, ws.next()).await {
        Ok(Some(Ok(Message::Text(t)))) => serde_json::from_str::<Value>(t.as_str()).ok().filter(|v| v["t"] == "hello"),
        _ => None,
    };
    let wants_udp = hello.as_ref().is_some_and(|v| v["udp"].as_bool() == Some(true));
    let token = hello.and_then(|v| v["token"].as_str().map(str::to_owned));
    let Some(token) = token else {
        let _ = ws.close(None).await;
        return;
    };
    let tx = {
        let s = state.lock().unwrap();
        s.screen
            .as_ref()
            .filter(|slot| slot.token.as_deref().is_some_and(|t| crate::same(&token, t)))
            .and_then(|slot| slot.conns.clone())
    };
    if let Some(tx) = tx {
        let _ = tx.send((ws, wants_udp));
    } else {
        let _ = ws.close(None).await;
    }
}

// ── USB path (raw TCP + adb reverse, unchanged behaviour) ────────────────

async fn run_usb(listener: TcpListener, p: &Params) -> &'static str {
    // The phone connects once the shell's `adb reverse` is up and it was told the port.
    let sock = loop {
        let Ok(Ok((mut s, _))) = timeout(CONNECT_TIMEOUT, listener.accept()).await else {
            return "timeout";
        };
        let _ = s.set_nodelay(true);
        if let Ok(Ok(line)) = timeout(HELLO_TIMEOUT, read_line(&mut s)).await {
            if crate::same(&line, &p.token) {
                break s;
            }
        }
    };
    drop(listener);

    let out_name = p.output.borrow().clone();
    let Some(mut rec) = Recorder::start(&out_name, p.bitrate, 240, p.rate, p.fps, false, p.hevc).await else { return "encoder" };
    crate::emit(json!({"ev": "screenLive", "dev": p.dev, "sid": p.sid, "encoder": rec.encoder}));
    let _ = p.input_tx.send(Cmd::ScreenStart { w: p.w, h: p.h });

    let (rd, mut wr) = sock.into_split();
    let input_tx = p.input_tx.clone();
    let mut touches = std::pin::pin!(async move {
        let mut rd = BufReader::new(rd);
        let _ = touch_loop(&mut rd, &input_tx).await;
    });
    // wf-recorder gives up when the output changes under it (a new scale or mode from
    // the Displays page, a config reload): it starts again on the same socket, and the
    // phone takes the new codec config. Five times in 30 s is a broken output instead.
    let mut restarts: Vec<Instant> = Vec::new();
    let mut output = p.output.clone();
    loop {
        tokio::select! {
            _ = &mut touches => return "closed",
            r = rec.pump(&mut wr) => match r {
                Pump::Phone => return "closed",
                Pump::Encoder => {
                    restarts.retain(|t| t.elapsed() < Duration::from_secs(30));
                    if restarts.len() >= 5 {
                        return "encoder_exit";
                    }
                    restarts.push(Instant::now());
                }
            },
            // Another screen to show: the same restart, asked for.
            changed = output.changed() => if changed.is_err() { return "stopped" },
        }
        drop(rec);
        tokio::select! {
            _ = &mut touches => return "closed",
            _ = tokio::time::sleep(Duration::from_millis(300)) => {}
        }
        let out_name = output.borrow().clone();
        rec = match Recorder::start(&out_name, p.bitrate, 240, p.rate, p.fps, false, p.hevc).await {
            Some(r) => r,
            None => return "encoder_exit",
        };
        crate::emit(json!({"ev": "screenLive", "dev": p.dev, "sid": p.sid, "encoder": rec.encoder}));
    }
}

/// Why the frames stopped: the encoder (it may start again) or the phone (it is over).
enum Pump {
    Encoder,
    Phone,
}

async fn read_line(s: &mut TcpStream) -> std::io::Result<String> {
    let mut line = Vec::new();
    loop {
        let b = s.read_u8().await?;
        if b == b'\n' {
            return Ok(String::from_utf8_lossy(&line).into_owned());
        }
        if line.len() >= 128 {
            return Err(std::io::ErrorKind::InvalidData.into());
        }
        line.push(b);
    }
}

// ── Shared input decoding ────────────────────────────────────────────────

fn parse_input_msg(data: &[u8], input_tx: &Sender<Cmd>) -> std::io::Result<()> {
    let Some(&tag) = data.first() else {
        return Err(std::io::ErrorKind::InvalidData.into());
    };
    let rest = &data[1..];
    match tag {
        1 => {
            let Some(&n) = rest.first() else {
                return Err(std::io::ErrorKind::InvalidData.into());
            };
            let n = n as usize;
            let body = rest.get(1..1 + n * 5).ok_or(std::io::ErrorKind::InvalidData)?;
            let mut fingers = Vec::with_capacity(n);
            for chunk in body.chunks_exact(5) {
                let id = chunk[0] as i64;
                let x = u16::from_be_bytes([chunk[1], chunk[2]]) as f64 / 65535.0;
                let y = u16::from_be_bytes([chunk[3], chunk[4]]) as f64 / 65535.0;
                fingers.push((id, x, y));
            }
            let _ = input_tx.send(Cmd::ScreenFrame { fingers });
            Ok(())
        }
        2 => {
            if rest.len() < 2 {
                return Err(std::io::ErrorKind::InvalidData.into());
            }
            let n = u16::from_be_bytes([rest[0], rest[1]]) as usize;
            let text = rest.get(2..2 + n).ok_or(std::io::ErrorKind::InvalidData)?;
            let _ = input_tx.send(Cmd::ScreenText { text: String::from_utf8_lossy(text).into_owned() });
            Ok(())
        }
        3 => {
            let Some(&n) = rest.first() else {
                return Err(std::io::ErrorKind::InvalidData.into());
            };
            let n = n as usize;
            let key = rest.get(1..1 + n).ok_or(std::io::ErrorKind::InvalidData)?;
            let Some(&mask) = rest.get(1 + n) else {
                return Err(std::io::ErrorKind::InvalidData.into());
            };
            let mods = [(1, "shift"), (2, "ctrl"), (4, "alt"), (8, "super")]
                .iter()
                .filter(|(bit, _)| mask & bit != 0)
                .map(|(_, m)| m.to_string())
                .collect();
            let _ = input_tx.send(Cmd::ScreenKey { key: String::from_utf8_lossy(key).into_owned(), mods });
            Ok(())
        }
        _ => Err(std::io::ErrorKind::InvalidData.into()),
    }
}

async fn touch_loop<R: AsyncRead + Unpin>(rd: &mut R, input_tx: &Sender<Cmd>) -> std::io::Result<()> {
    loop {
        let msg = match rd.read_u8().await? {
            1 => {
                let n = rd.read_u8().await? as usize;
                let mut buf = vec![0u8; 2 + n * 5];
                buf[0] = 1;
                buf[1] = n as u8;
                rd.read_exact(&mut buf[2..]).await?;
                buf
            }
            2 => {
                let n = rd.read_u16().await? as usize;
                let mut buf = vec![0u8; 3 + n];
                buf[0] = 2;
                buf[1..3].copy_from_slice(&(n as u16).to_be_bytes());
                rd.read_exact(&mut buf[3..]).await?;
                buf
            }
            3 => {
                let n = rd.read_u8().await? as usize;
                let mut buf = vec![0u8; 3 + n];
                buf[0] = 3;
                buf[1] = n as u8;
                rd.read_exact(&mut buf[2..]).await?;
                buf
            }
            _ => return Err(std::io::ErrorKind::InvalidData.into()),
        };
        parse_input_msg(&msg, input_tx)?;
    }
}

// ── Wi-Fi / link WebSocket path ──────────────────────────────────────────

struct WriterItem {
    enqueued_at: Instant,
    video_bytes: usize,
    is_frame: bool,
    msg: Message,
}

struct QueueInner {
    items: VecDeque<WriterItem>,
    /// Sound: written before any queued video, so a video backlog never delays it.
    prio: VecDeque<WriterItem>,
    queued_bytes: usize,
    in_flight_since: Option<Instant>,
    closed: bool,
    bytes_sent: u64,
    frames_sent: u64,
}

struct WriterQueue {
    inner: Mutex<QueueInner>,
    notify: Notify,
}

impl WriterQueue {
    fn new() -> Arc<Self> {
        Arc::new(Self {
            inner: Mutex::new(QueueInner {
                items: VecDeque::new(),
                prio: VecDeque::new(),
                queued_bytes: 0,
                in_flight_since: None,
                closed: false,
                bytes_sent: 0,
                frames_sent: 0,
            }),
            notify: Notify::new(),
        })
    }

    fn is_congested(&self, bitrate: u64) -> bool {
        let g = self.inner.lock().unwrap();
        // As much as CONGESTION_AGE carries at the target rate: one key frame is not a backlog.
        let byte_limit = ((bitrate as f64 / 8.0) * CONGESTION_AGE.as_secs_f64()) as usize;
        let oldest_item = g.items.front().map(|i| i.enqueued_at.elapsed());
        let oldest_flight = g.in_flight_since.map(|t| t.elapsed());
        let oldest = match (oldest_item, oldest_flight) {
            (Some(a), Some(b)) => a.max(b),
            (Some(a), None) => a,
            (None, Some(b)) => b,
            (None, None) => Duration::ZERO,
        };
        oldest > CONGESTION_AGE || g.queued_bytes > byte_limit
    }

    fn push_video(&self, kind: u8, payload: Vec<u8>) -> bool {
        let mut g = self.inner.lock().unwrap();
        if g.closed {
            return false;
        }
        let len = payload.len();
        if g.items.len() >= MAX_QUEUE_ITEMS || g.queued_bytes + len > MAX_QUEUE_BYTES {
            g.closed = true;
            return false;
        }
        g.queued_bytes += len;
        g.items.push_back(WriterItem {
            enqueued_at: Instant::now(),
            video_bytes: len,
            is_frame: kind != 0,
            msg: Message::Binary(payload.into()),
        });
        self.notify.notify_one();
        true
    }

    fn push_control(&self, msg: Message) -> bool {
        let mut g = self.inner.lock().unwrap();
        if g.closed {
            return false;
        }
        if g.items.len() >= MAX_QUEUE_ITEMS {
            g.closed = true;
            return false;
        }
        g.items.push_back(WriterItem {
            enqueued_at: Instant::now(),
            video_bytes: 0,
            is_frame: false,
            msg,
        });
        self.notify.notify_one();
        true
    }

    /// A sound packet. Half a second waiting is stale: the oldest goes first, keeping any OpusHead.
    fn push_prio(&self, payload: Vec<u8>) -> bool {
        let mut g = self.inner.lock().unwrap();
        if g.closed {
            return false;
        }
        let is_head = payload.first() == Some(&8);
        if is_head {
            // A fresh OpusHead replaces any leftover packets from an earlier capture.
            g.prio.clear();
        } else if g.prio.len() >= AUDIO_QUEUE {
            let head_at_front = g
                .prio
                .front()
                .is_some_and(|i| matches!(&i.msg, Message::Binary(b) if b.first() == Some(&8)));
            if head_at_front && g.prio.len() > 1 {
                g.prio.remove(1);
            } else {
                g.prio.pop_front();
            }
        }
        g.prio.push_back(WriterItem { enqueued_at: Instant::now(), video_bytes: 0, is_frame: false, msg: Message::Binary(payload.into()) });
        self.notify.notify_one();
        true
    }

    fn take_stats(&self) -> (u64, u64) {
        let mut g = self.inner.lock().unwrap();
        let b = g.bytes_sent;
        let f = g.frames_sent;
        g.bytes_sent = 0;
        g.frames_sent = 0;
        (b, f)
    }
}

fn spawn_writer(ws_tx: futures_util::stream::SplitSink<Ws, Message>, queue: Arc<WriterQueue>) -> (oneshot::Receiver<()>, AbortOnDrop) {
    let (dead_tx, dead_rx) = oneshot::channel();
    let task = tokio::spawn(async move {
        let mut ws_tx = ws_tx;
        loop {
            let item = loop {
                let notified = queue.notify.notified();
                tokio::pin!(notified);
                notified.as_mut().enable();
                {
                    let mut g = queue.inner.lock().unwrap();
                    if g.closed {
                        let _ = dead_tx.send(());
                        return;
                    }
                    if let Some(item) = g.prio.pop_front().or_else(|| g.items.pop_front()) {
                        g.queued_bytes -= item.video_bytes;
                        g.in_flight_since = Some(Instant::now());
                        break item;
                    }
                }
                notified.await;
            };
            let vbytes = item.video_bytes as u64;
            let is_frame = item.is_frame;
            if ws_tx.send(item.msg).await.is_err() {
                queue.inner.lock().unwrap().closed = true;
                let _ = dead_tx.send(());
                return;
            }
            let mut g = queue.inner.lock().unwrap();
            g.in_flight_since = None;
            g.bytes_sent += vbytes;
            if is_frame {
                g.frames_sent += 1;
            }
        }
    });
    (dead_rx, AbortOnDrop(task.abort_handle()))
}

struct LiveEncoder {
    packets: mpsc::Receiver<(u8, Vec<u8>)>,
    child: Child,
    encoder: &'static str,
    /// The patched wf-recorder's stdin (`--ii-control`): key frames and bitrate without a restart.
    control: Option<tokio::process::ChildStdin>,
    _reader: AbortOnDrop,
    _stderr: Option<AbortOnDrop>,
}

impl LiveEncoder {
    /// One `--ii-control` line; false without control or when the encoder is gone.
    async fn command(&mut self, line: &str) -> bool {
        match self.control.as_mut() {
            Some(c) => c.write_all(line.as_bytes()).await.is_ok() && c.flush().await.is_ok(),
            None => false,
        }
    }

    async fn stop(mut self) {
        // Abort reader task first so stdout closes, then reap child before starting another.
        drop(self._reader);
        let _ = self.child.kill().await;
    }
}

struct StartingEncoder {
    rx: oneshot::Receiver<Option<Recorder>>,
    _task: AbortOnDrop,
}

impl StartingEncoder {
    fn spawn(output: String, bitrate: u64, gop: u32, rate: u32, hevc: bool) -> Self {
        let (tx, rx) = oneshot::channel();
        let task = tokio::spawn(async move {
            // gop is the session's fps (run_ws).
            let rec = Recorder::start(&output, bitrate, gop, rate, gop, true, hevc).await;
            let _ = tx.send(rec);
        });
        Self { rx, _task: AbortOnDrop(task.abort_handle()) }
    }
}

enum WsConnEnd {
    Dropped,
    Replaced(PhoneConn),
    End(&'static str),
}

struct WsSession {
    dev: String,
    sid: u64,
    w: i32,
    h: i32,
    gop: u32,
    rate: u32,
    max_bitrate: u64,
    target_bitrate: u64,
    adaptive: bool,
    screen_started: bool,
    encoder_name: &'static str,
    /// The live encoder refreshes the picture in waves (no periodic key frame): a dropped
    /// frame heals within one GOP on its own, so nothing waits for a key frame or restarts.
    refresh: bool,
    restarts: Vec<Instant>,
    output: watch::Receiver<String>,
    input_tx: Sender<Cmd>,
    audio_src: watch::Receiver<Option<String>>,
    audio: Option<Audio>,
    /// The video over UDP, used while the phone that asked for it keeps saying hello.
    udp: Option<udp::Sender>,
    wants_udp: bool,
    hevc: bool,
}

impl WsSession {
    fn emit_rate(&self) {
        crate::emit(json!({"ev": "screenRate", "dev": self.dev, "sid": self.sid, "bitrate": self.target_bitrate}));
    }

    fn emit_live(&self, encoder: &'static str) {
        crate::emit(json!({"ev": "screenLive", "dev": self.dev, "sid": self.sid, "encoder": encoder}));
    }

    fn apply_quality(&mut self, v: &Value) -> bool {
        let old_max = self.max_bitrate;
        if let Some(b) = v["bitrate"].as_u64() {
            self.max_bitrate = b.clamp(MIN_BITRATE, MAX_BITRATE);
        }
        if let Some(a) = v["adaptive"].as_bool() {
            self.adaptive = a;
        }
        let new_target = if !self.adaptive || self.max_bitrate < self.target_bitrate || self.target_bitrate == old_max {
            self.max_bitrate
        } else {
            self.target_bitrate
        };
        if new_target != self.target_bitrate {
            self.target_bitrate = new_target;
            self.emit_rate();
            true
        } else {
            false
        }
    }
}

async fn run_ws(mut conns: mpsc::UnboundedReceiver<PhoneConn>, p: &Params) -> &'static str {
    let Ok(Some(mut ws)) = timeout(CONNECT_TIMEOUT, conns.recv()).await else {
        return "timeout";
    };
    let mut sess = WsSession {
        dev: p.dev.clone(),
        sid: p.sid,
        w: p.w,
        h: p.h,
        // With intra refresh, the period a damaged picture takes to heal.
        gop: p.fps,
        rate: p.rate,
        max_bitrate: p.bitrate,
        target_bitrate: p.bitrate,
        adaptive: p.adaptive,
        screen_started: false,
        encoder_name: "",
        refresh: false,
        restarts: Vec::new(),
        output: p.output.clone(),
        input_tx: p.input_tx.clone(),
        audio_src: p.audio.clone(),
        audio: None,
        udp: p.udp.clone().map(|(sock, peer)| udp::Sender::new(sock, peer)),
        wants_udp: false,
        hevc: p.hevc,
    };

    loop {
        match run_ws_conn(ws, &mut sess, &mut conns).await {
            WsConnEnd::End(reason) => return reason,
            WsConnEnd::Replaced(next) => {
                trace("conn", "replaced");
                ws = next;
            }
            WsConnEnd::Dropped => {
                // A finger down when Wi-Fi went would stay down on the PC until it came back.
                let _ = sess.input_tx.send(Cmd::ScreenFrame { fingers: Vec::new() });
                match timeout(RECONNECT_GRACE, conns.recv()).await {
                    Ok(Some(next)) => ws = next,
                    _ => return "closed",
                }
            }
        }
    }
}

async fn run_ws_conn((ws, wants_udp): PhoneConn, sess: &mut WsSession, conns: &mut mpsc::UnboundedReceiver<PhoneConn>) -> WsConnEnd {
    sess.wants_udp = wants_udp;
    limit_unsent(&ws);
    let (ws_tx, mut ws_rx) = ws.split();
    let queue = WriterQueue::new();
    let (mut writer_dead, _writer_guard) = spawn_writer(ws_tx, queue.clone());
    // A phone that reconnects needs the sound's codec header again.
    if let Some(head) = sess.audio.as_ref().and_then(|a| a.head.clone()) {
        queue.push_prio(head);
    }
    // The UDP video's key and port: the phone starts its hellos, and frames move there.
    if let Some(u) = sess.udp.as_ref().filter(|_| sess.wants_udp) {
        queue.push_control(Message::text(u.peer().offer(u.port()).to_string()));
    }

    let mut starting: Option<StartingEncoder> = Some(StartingEncoder::spawn(
        sess.output.borrow().clone(),
        sess.target_bitrate,
        sess.gop,
        sess.rate,
        sess.hevc,
    ));
    let mut live: Option<LiveEncoder> = None;
    let mut backoff_until: Option<tokio::time::Instant> = None;

    let mut dropping = false;
    let mut dropping_since: Option<Instant> = None;
    let mut restarted_this_drop = false;
    let mut congestion_events: Vec<Instant> = Vec::new();
    let mut last_congestion_at = Instant::now();
    let mut last_rate_change: Option<Instant> = None;
    let mut last_idr: Option<Instant> = None;
    let mut dropped_s: u64 = 0;

    let mut stats_tick = tokio::time::interval_at(
        tokio::time::Instant::now() + Duration::from_secs(1),
        Duration::from_secs(1),
    );
    stats_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);

    // Helper to trigger an intended encoder restart without counting toward crash limits.
    async fn restart_intended(
        why: &'static str,
        sess: &WsSession,
        live: &mut Option<LiveEncoder>,
        starting: &mut Option<StartingEncoder>,
        backoff_until: &mut Option<tokio::time::Instant>,
        dropping: &mut bool,
        dropping_since: &mut Option<Instant>,
        restarted_this_drop: &mut bool,
    ) {
        // The patched wf-recorder answers without a restart: a key frame on the next frame,
        // and a new bitrate where the encoder reconfigures (NVENC, x264; not VA-API).
        if let Some(enc) = live.as_mut() {
            let line = match why {
                "idr" | "drop_recovery" => Some("idr\n".to_string()),
                "rate_up" | "rate_down" | "quality" if enc.encoder != "vaapi" => Some(format!("bitrate {}\n", sess.target_bitrate)),
                _ => None,
            };
            if let Some(line) = line {
                if enc.command(&line).await {
                    trace(if line == "idr\n" { "key" } else { "bitrate" }, why);
                    return;
                }
            }
        }
        trace("restart", why);
        *dropping = false;
        *dropping_since = None;
        *restarted_this_drop = false;
        *backoff_until = None;
        *starting = None;
        if let Some(enc) = live.take() {
            enc.stop().await;
        }
        *starting = Some(StartingEncoder::spawn(
            sess.output.borrow().clone(),
            sess.target_bitrate,
            sess.gop,
            sess.rate,
            sess.hevc,
        ));
    }

    loop {
        tokio::select! {
            rec = async {
                match starting.as_mut() {
                    Some(s) => (&mut s.rx).await.ok().flatten(),
                    None => std::future::pending().await,
                }
            }, if starting.is_some() => {
                starting = None;
                let Some(rec) = rec else {
                    return WsConnEnd::End(if !sess.screen_started { "encoder" } else { "encoder_exit" });
                };
                sess.encoder_name = rec.encoder;
                sess.refresh = rec.refresh;
                sess.emit_live(rec.encoder);
                if !sess.screen_started {
                    let _ = sess.input_tx.send(Cmd::ScreenStart { w: sess.w, h: sess.h });
                    sess.screen_started = true;
                }
                dropping = false;
                dropping_since = None;
                restarted_this_drop = false;
                let enc = rec.into_live();
                live = Some(enc);
            }
            pkt = async {
                match live.as_mut() {
                    Some(enc) => enc.packets.recv().await,
                    None => std::future::pending().await,
                }
            }, if live.is_some() => {
                match pkt {
                    None => {
                        // Unexpected encoder exit: count toward 5-in-30s limit and settle 300 ms.
                        trace("restart", "encoder_exit");
                        if let Some(enc) = live.take() {
                            enc.stop().await;
                        }
                        sess.restarts.retain(|t| t.elapsed() < Duration::from_secs(30));
                        if sess.restarts.len() >= 5 {
                            return WsConnEnd::End("encoder_exit");
                        }
                        sess.restarts.push(Instant::now());
                        backoff_until = Some(tokio::time::Instant::now() + Duration::from_millis(300));
                    }
                    Some((kind, payload)) => {
                        // UDP while the phone is there: no queue, no head-of-line blocking.
                        if sess.wants_udp {
                            if let Some(u) = sess.udp.as_mut() {
                                if u.send_frame(&payload).await {
                                    if kind == 2 {
                                        dropping = false;
                                        dropping_since = None;
                                        restarted_this_drop = false;
                                    }
                                    continue;
                                }
                            }
                        }
                        if kind == 0 {
                            if !queue.push_video(kind, payload) {
                                return conn_lost("queue_full");
                            }
                        } else if kind == 2 {
                            dropping = false;
                            dropping_since = None;
                            restarted_this_drop = false;
                            if !queue.push_video(kind, payload) {
                                return conn_lost("queue_full");
                            }
                        } else {
                            let congested = queue.is_congested(sess.target_bitrate);
                            if dropping && !congested && sess.refresh {
                                dropping = false;
                                dropping_since = None;
                                restarted_this_drop = false;
                            }
                            if congested {
                                last_congestion_at = Instant::now();
                            }
                            if dropping || congested {
                                if !dropping {
                                    dropping = true;
                                    dropping_since = Some(Instant::now());
                                    restarted_this_drop = false;
                                    if sess.adaptive {
                                        congestion_events.retain(|t| t.elapsed() < CONGESTION_WINDOW);
                                        if congestion_events.last().is_none_or(|t| t.elapsed() >= Duration::from_millis(400)) {
                                            congestion_events.push(Instant::now());
                                        }
                                    }
                                }
                                dropped_s += 1;

                                if sess.adaptive {
                                    congestion_events.retain(|t| t.elapsed() < CONGESTION_WINDOW);
                                    let floor = sess.max_bitrate.min(FLOOR_BITRATE);
                                    let next_rate = ((sess.target_bitrate as f64) * 0.7).round().max(floor as f64) as u64;
                                    if congestion_events.len() >= 2
                                        && next_rate < sess.target_bitrate
                                        && last_rate_change.is_none_or(|t| t.elapsed() >= RATE_COOLDOWN)
                                    {
                                        sess.target_bitrate = next_rate;
                                        last_rate_change = Some(Instant::now());
                                        last_congestion_at = Instant::now();
                                        congestion_events.clear();
                                        sess.emit_rate();
                                        restart_intended(
                                            "rate_down",
                                            sess,
                                            &mut live,
                                            &mut starting,
                                            &mut backoff_until,
                                            &mut dropping,
                                            &mut dropping_since,
                                            &mut restarted_this_drop,
                                        )
                                        .await;
                                    } else if !sess.refresh && !restarted_this_drop && dropping_since.is_some_and(|t| t.elapsed() > DROP_IDR_AFTER) {
                                        restarted_this_drop = true;
                                        restart_intended(
                                            "drop_recovery",
                                            sess,
                                            &mut live,
                                            &mut starting,
                                            &mut backoff_until,
                                            &mut dropping,
                                            &mut dropping_since,
                                            &mut restarted_this_drop,
                                        )
                                        .await;
                                    }
                                } else if !sess.refresh && !restarted_this_drop && dropping_since.is_some_and(|t| t.elapsed() > DROP_IDR_AFTER) {
                                    restarted_this_drop = true;
                                    restart_intended(
                                        "drop_recovery",
                                        sess,
                                        &mut live,
                                        &mut starting,
                                        &mut backoff_until,
                                        &mut dropping,
                                        &mut dropping_since,
                                        &mut restarted_this_drop,
                                    )
                                    .await;
                                }
                            } else if !queue.push_video(kind, payload) {
                                return conn_lost("queue_full");
                            }
                        }
                    }
                }
            }
            _ = async {
                match backoff_until {
                    Some(deadline) => tokio::time::sleep_until(deadline).await,
                    None => std::future::pending::<()>().await,
                }
            }, if backoff_until.is_some() => {
                backoff_until = None;
                starting = Some(StartingEncoder::spawn(
                    sess.output.borrow().clone(),
                    sess.target_bitrate,
                    sess.gop,
                    sess.rate,
                    sess.hevc,
                ));
            }
            _ = stats_tick.tick() => {
                let quiet = if sess.wants_udp && sess.udp.is_some() { UDP_STEP_UP_QUIET } else { STEP_UP_QUIET };
                if sess.adaptive
                    && sess.target_bitrate < sess.max_bitrate
                    && last_congestion_at.elapsed() >= quiet
                    && last_rate_change.is_none_or(|t| t.elapsed() >= RATE_COOLDOWN)
                {
                    let next_rate = (((sess.target_bitrate as f64) * 1.25).round() as u64).min(sess.max_bitrate);
                    if next_rate > sess.target_bitrate {
                        sess.target_bitrate = next_rate;
                        last_rate_change = Some(Instant::now());
                        last_congestion_at = Instant::now();
                        sess.emit_rate();
                        restart_intended(
                            "rate_up",
                            sess,
                            &mut live,
                            &mut starting,
                            &mut backoff_until,
                            &mut dropping,
                            &mut dropping_since,
                            &mut restarted_this_drop,
                        )
                        .await;
                    }
                }
                if sess.screen_started {
                    let (cap_mean, cap_max) = match CAPTURE_LAG.lock() {
                        Ok(mut l) => {
                            let r = if l.1 > 0 { (Some(l.0 / l.1 / 1000), Some(l.2 / 1000)) } else { (None, None) };
                            *l = (0, 0, 0);
                            r
                        }
                        Err(_) => (None, None),
                    };
                    let (mut bytes_sent, mut frames_sent) = queue.take_stats();
                    if let Some(u) = sess.udp.as_mut() {
                        let (b, f) = u.take_stats();
                        bytes_sent += b;
                        frames_sent += f;
                    }
                    let dropped = std::mem::take(&mut dropped_s);
                    let kbps = (bytes_sent * 8) / 1000;
                    let msg = json!({
                        "t": "stats",
                        "bitrate": sess.target_bitrate,
                        "max": sess.max_bitrate,
                        "kbps": kbps,
                        "fps": frames_sent,
                        "dropped": dropped,
                        "encoder": sess.encoder_name,
                        // Capture → send (ms, mean and max over the second): the PC's share
                        // of the phone's capture → decoded latency (patched wf-recorder only).
                        "cap": cap_mean,
                        "capmax": cap_max,
                        // UDP parity in percent (udp.rs adapt_fec), absent on the WebSocket.
                        "fec": sess.udp.as_ref().filter(|_| sess.wants_udp).map(|u| u.fec_pct()),
                    })
                    .to_string();
                    if !queue.push_control(Message::text(msg)) {
                        return conn_lost("queue_full");
                    }
                } else {
                    dropped_s = 0;
                    let _ = queue.take_stats();
                }
            }
            msg = ws_rx.next() => match msg {
                Some(Ok(Message::Binary(b))) => {
                    let _ = parse_input_msg(&b, &sess.input_tx);
                }
                Some(Ok(Message::Text(t))) => {
                    let Ok(v) = serde_json::from_str::<Value>(t.as_str()) else { continue };
                    match v["t"].as_str().unwrap_or("") {
                        "ping" => {
                            // `now`: the PC's clock for the phone's offset (encode_tag's pts).
                            let pong = json!({"t": "pong", "id": v["id"], "now": mono_us()}).to_string();
                            if !queue.push_control(Message::text(pong)) {
                                return conn_lost("queue_full");
                            }
                        }
                        "quality" => {
                            if sess.apply_quality(&v) {
                                last_rate_change = Some(Instant::now());
                                last_congestion_at = Instant::now();
                                congestion_events.clear();
                                restart_intended(
                                    "quality",
                                    sess,
                                    &mut live,
                                    &mut starting,
                                    &mut backoff_until,
                                    &mut dropping,
                                    &mut dropping_since,
                                    &mut restarted_this_drop,
                                )
                                .await;
                            }
                        }
                        // The phone's UDP report each second: size the parity to the loss.
                        "net" => {
                            let lost = v["lost"].as_u64().unwrap_or(0);
                            if let Some(u) = sess.udp.as_mut() {
                                u.adapt_fec(v["loss"].as_f64().unwrap_or(0.0), lost);
                            }
                            // UDP has no queue to back up: frames the parity couldn't save are the
                            // congestion signal. Two such seconds within the window lower the rate
                            // like a congested WebSocket queue does.
                            if sess.adaptive && sess.wants_udp && lost >= UDP_CONGESTED_LOST {
                                last_congestion_at = Instant::now();
                                congestion_events.retain(|t| t.elapsed() < CONGESTION_WINDOW);
                                congestion_events.push(Instant::now());
                                let floor = sess.max_bitrate.min(FLOOR_BITRATE);
                                let next_rate = ((sess.target_bitrate as f64) * 0.7).round().max(floor as f64) as u64;
                                if congestion_events.len() >= 2
                                    && next_rate < sess.target_bitrate
                                    && last_rate_change.is_none_or(|t| t.elapsed() >= RATE_COOLDOWN)
                                {
                                    sess.target_bitrate = next_rate;
                                    last_rate_change = Some(Instant::now());
                                    congestion_events.clear();
                                    sess.emit_rate();
                                    restart_intended(
                                        "rate_down",
                                        sess,
                                        &mut live,
                                        &mut starting,
                                        &mut backoff_until,
                                        &mut dropping,
                                        &mut dropping_since,
                                        &mut restarted_this_drop,
                                    )
                                    .await;
                                }
                            }
                        }
                        "idr" => {
                            // A refreshing encoder heals the phone's picture by itself: a restart
                            // would only freeze it ~300 ms and send the burst refresh avoids.
                            if !sess.refresh && last_idr.is_none_or(|t| t.elapsed() >= IDR_COOLDOWN) {
                                last_idr = Some(Instant::now());
                                restart_intended(
                                    "idr",
                                    sess,
                                    &mut live,
                                    &mut starting,
                                    &mut backoff_until,
                                    &mut dropping,
                                    &mut dropping_since,
                                    &mut restarted_this_drop,
                                )
                                .await;
                            }
                        }
                        _ => {}
                    }
                }
                Some(Ok(Message::Close(_))) => return conn_lost("phone_closed"),
                Some(Err(_)) | None => return conn_lost("read_error"),
                Some(Ok(_)) => {}
            },
            changed = sess.output.changed() => {
                if changed.is_err() {
                    return WsConnEnd::End("stopped");
                }
                starting = None;
                if let Some(enc) = live.take() {
                    enc.stop().await;
                }
                backoff_until = Some(tokio::time::Instant::now() + Duration::from_millis(300));
            }
            _ = &mut writer_dead => return conn_lost("write_failed"),
            changed = sess.audio_src.changed() => {
                if changed.is_err() {
                    return WsConnEnd::End("stopped");
                }
                let src = sess.audio_src.borrow_and_update().clone();
                // Stop the previous capture before opening the next (e.g. default sink switch).
                sess.audio = None;
                sess.audio = src.and_then(|s| Audio::start(&s));
                crate::emit(json!({"ev": "screenAudio", "dev": sess.dev, "sid": sess.sid, "on": sess.audio.is_some()}));
            }
            pkt = async {
                match sess.audio.as_mut() {
                    Some(a) => a.rx.recv().await,
                    None => std::future::pending().await,
                }
            }, if sess.audio.is_some() => match pkt {
                Some(pkt) => {
                    if pkt[0] == 8 {
                        if let Some(a) = sess.audio.as_mut() {
                            a.head = Some(pkt.clone());
                        }
                    }
                    queue.push_prio(pkt);
                }
                None => {
                    // ffmpeg ended (PulseAudio went, the source vanished): the phone hears nothing.
                    sess.audio = None;
                    crate::emit(json!({"ev": "screenAudio", "dev": sess.dev, "sid": sess.sid, "on": false}));
                }
            },
            next = conns.recv() => match next {
                Some(next_ws) => return WsConnEnd::Replaced(next_ws),
                None => return WsConnEnd::End("stopped"),
            },
        }
    }
}

/// The kernel's send buffer grows to megabytes: seconds of video at Wi-Fi rates, queued
/// where the congestion check cannot see it. With little unsent data allowed there, a
/// slow link backs up into [`WriterQueue`], whose age the dropping and the bitrate follow.
fn limit_unsent(ws: &Ws) {
    use std::os::fd::AsRawFd;
    const NOTSENT_LOWAT: libc::c_int = 32 * 1024;
    let fd = ws.get_ref().get_ref().0.as_raw_fd();
    // SAFETY: a live socket's fd and a c_int option of the right size.
    unsafe {
        libc::setsockopt(
            fd,
            libc::IPPROTO_TCP,
            libc::TCP_NOTSENT_LOWAT,
            &NOTSENT_LOWAT as *const libc::c_int as *const libc::c_void,
            std::mem::size_of::<libc::c_int>() as libc::socklen_t,
        );
    }
}

// ── The PC's sound ───────────────────────────────────────────────────────

/// The PC's sound for the phone: ffmpeg captures a PulseAudio source (the shell's
/// virtual sink's monitor) as Opus, 10 ms packets in Ogg, which are unwrapped here.
/// To the phone: `[8][u64 0][OpusHead]` once (codec config), then `[9][u64 pts µs][packet]`.
/// Opus rather than PCM: 128 kbit/s instead of 1.5 Mbit/s on a Wi-Fi that drops packets.
struct Audio {
    rx: mpsc::Receiver<Vec<u8>>,
    head: Option<Vec<u8>>,
    _child: Child,
    _reader: AbortOnDrop,
}

impl Audio {
    fn start(source: &str) -> Option<Audio> {
        let mut child = Command::new("ffmpeg")
            .args(["-hide_banner", "-loglevel", "error", "-fflags", "nobuffer"])
            // 10 ms fragments from PulseAudio: its default is far larger, and waits that long.
            .args(["-f", "pulse", "-fragment_size", "1920", "-i", source])
            .args(["-ac", "2", "-ar", "48000", "-c:a", "libopus", "-application", "lowdelay", "-frame_duration", "10", "-b:a", "128k"])
            // One Ogg page per packet (its default holds a second), out at once.
            .args(["-flush_packets", "1", "-page_duration", "10000", "-f", "ogg", "-"])
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .ok()?;
        let out = child.stdout.take()?;
        let (tx, rx) = mpsc::channel(64);
        let task = tokio::spawn(async move {
            let mut out = BufReader::new(out);
            let mut n: u64 = 0;
            let mut packet = Vec::new();
            loop {
                let mut h = [0u8; 27];
                if out.read_exact(&mut h).await.is_err() || &h[..4] != b"OggS" {
                    return;
                }
                let mut segs = vec![0u8; h[26] as usize];
                if out.read_exact(&mut segs).await.is_err() {
                    return;
                }
                for len in segs {
                    let at = packet.len();
                    packet.resize(at + len as usize, 0);
                    if out.read_exact(&mut packet[at..]).await.is_err() {
                        return;
                    }
                    if len == 255 {
                        continue;
                    }
                    let data = std::mem::take(&mut packet);
                    let pkt = if data.starts_with(b"OpusHead") {
                        Some(audio_packet(8, 0, &data))
                    } else if data.starts_with(b"OpusTags") {
                        None
                    } else {
                        n += 1;
                        Some(audio_packet(9, n * 10_000, &data))
                    };
                    // Never wait on the phone: a full channel loses the packet, not the timing.
                    if let Some(pkt) = pkt {
                        if let Err(mpsc::error::TrySendError::Closed(_)) = tx.try_send(pkt) {
                            return;
                        }
                    }
                }
            }
        });
        Some(Audio { rx, head: None, _child: child, _reader: AbortOnDrop(task.abort_handle()) })
    }
}

fn audio_packet(kind: u8, pts: u64, data: &[u8]) -> Vec<u8> {
    let mut pkt = Vec::with_capacity(9 + data.len());
    pkt.push(kind);
    pkt.extend_from_slice(&pts.to_be_bytes());
    pkt.extend_from_slice(data);
    pkt
}

// ── The encoder ──────────────────────────────────────────────────────────

struct Recorder {
    child: Child,
    out: ChildStdout,
    encoder: &'static str,
    refresh: bool,
    /// The video tag that proved the encoder works, sent before the rest.
    first: Option<(u32, Vec<u8>)>,
    nal_len: usize,
    control: Option<tokio::process::ChildStdin>,
    /// The first frame's capture time (µs, CLOCK_MONOTONIC) from the patched binary's stderr:
    /// FLV times are ms after it. 0 = unknown (stock wf-recorder): frames are timed at send.
    base: Arc<std::sync::atomic::AtomicU64>,
    stderr: Option<AbortOnDrop>,
}

/// The patched wf-recorder (`ii-wf-recorder`, the fork's scripts/wf-recorder-ii): on PATH
/// (NixOS, the flake's package) or where its build script puts it (Arch, Fedora); else the
/// stock one, whose key frames and bitrate changes cost a restart.
fn recorder_bin() -> (std::path::PathBuf, bool) {
    use std::os::unix::fs::PermissionsExt;
    let exec = |p: &std::path::Path| std::fs::metadata(p).is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0);
    if let Some(path) = std::env::var_os("PATH") {
        for dir in std::env::split_paths(&path) {
            let p = dir.join("ii-wf-recorder");
            if exec(&p) {
                return (p, true);
            }
        }
    }
    let data = std::env::var_os("XDG_DATA_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".local/share")));
    if let Some(p) = data.map(|d| d.join("ii-wf-recorder/bin/ii-wf-recorder")).filter(|p| exec(p)) {
        return (p, true);
    }
    ("wf-recorder".into(), false)
}

fn render_nodes() -> Vec<String> {
    let mut nodes: Vec<String> = std::fs::read_dir("/dev/dri")
        .map(|d| d.filter_map(|e| e.ok()).map(|e| e.path().to_string_lossy().into_owned()).filter(|p| p.contains("renderD")).collect())
        .unwrap_or_default();
    nodes.sort();
    nodes
}

/// One VA-API encoder's wf-recorder args (h264_vaapi or hevc_vaapi).
///
/// VA-API has no intra refresh, so every GOP is a full key frame (~500 KB at 3120×1440): each
/// one was a burst Wi-Fi delivered late. Key frames come at the start and on request only.
fn vaapi_args(codec: &str, node: &str, b: &str, gop: u32) -> Vec<String> {
    let g = format!("g={}", gop.max(VAAPI_GOP));
    [
        // The pixels' real shape, said explicitly: Intel's VPP writes BT.601 limited range
        // whatever `out_range` asks, and wf-recorder's own filter asks for full, which
        // labelled limited pixels full: grey blacks and dim whites on the phone.
        "-F", "scale_vaapi=format=nv12:out_range=limited:out_color_matrix=bt470bg",
        "-c", codec, "-d", node, "-p", b, "-p", &g,
        // One frame in flight instead of two: a frame less behind (measured 38 → 20 ms).
        "-p", "async_depth=1",
    ]
    .into_iter()
    .chain(BT601_LIMITED_SRGB)
    .map(String::from)
    .collect()
}

/// Capture → send per frame (µs) since the last stats line: sum, count, max.
static CAPTURE_LAG: Mutex<(u64, u64, u64)> = Mutex::new((0, 0, 0));

/// A frame's pts: its capture time when the patched binary gave the base (and the capture →
/// send time is counted), else the send time.
fn frame_pts(base: &std::sync::atomic::AtomicU64, ts_ms: u32) -> u64 {
    let b = base.load(Ordering::Relaxed);
    let now = mono_us();
    if b == 0 {
        return now;
    }
    let pts = b + ts_ms as u64 * 1000;
    let lag = now.saturating_sub(pts);
    if let Ok(mut l) = CAPTURE_LAG.lock() {
        l.0 += lag;
        l.1 += 1;
        l.2 = l.2.max(lag);
    }
    pts
}

impl Recorder {
    /// The first encoder that produces a picture within a few seconds.
    /// `rate` caps the capture (a screen faster than the stream), 0 for none; `fps` is the
    /// stream's rate, which the encoder's rate control needs either way.
    async fn start(output: &str, bitrate: u64, gop: u32, rate: u32, fps: u32, ws: bool, hevc: bool) -> Option<Recorder> {
        let b = format!("b={bitrate}");
        let g = format!("g={gop}");
        let mut nvenc_args = vec![
            "-c", "h264_nvenc", "-p", "preset=p1", "-p", "tune=ull", "-p", "zerolatency=1", "-p", "rc=cbr", "-p", &b, "-p", &g,
            // A requested key frame (ii-control's idr) as an IDR, not a plain I frame.
            "-p", "forced-idr=1",
        ];
        if ws {
            // Intra refresh: no key frame after the first. A key frame is ~10× a frame (350 KB at
            // 8 Mbit/s): a burst Wi-Fi delivers late every GOP, which was the periodic stutter.
            nvenc_args.extend(["-p", "delay=0", "-p", "intra-refresh=1"]);
        }
        let mut candidates: Vec<(&'static str, Vec<String>)> = Vec::new();
        let nodes_for_hevc: Vec<String> = render_nodes();
        // HEVC first when the phone asked for it (better picture at the same bitrate, as fast
        // to encode here); H.264 is the fallback either way. No libx265: too slow for this.
        if hevc {
            let hevc_nvenc: Vec<String> = nvenc_args.iter().map(|a| if *a == "h264_nvenc" { "hevc_nvenc" } else { a }).map(String::from).collect();
            candidates.push(("nvenc", hevc_nvenc));
            for node in &nodes_for_hevc {
                candidates.push(("vaapi", vaapi_args("hevc_vaapi", node, &b, gop)));
            }
        }
        candidates.push(("nvenc", nvenc_args.into_iter().map(String::from).collect()));
        for node in &nodes_for_hevc {
            candidates.push(("vaapi", vaapi_args("h264_vaapi", node, &b, gop)));
        }
        candidates.push((
            "x264",
            // crf=-1: wf-recorder sets crf=20 for x264, which ignored the bitrate entirely.
            ["-c", "libx264", "-x", "yuv420p", "-p", "preset=ultrafast", "-p", "tune=zerolatency", "-p", &b, "-p", &g, "-p", "crf=-1", "-p", "forced-idr=1"]
                .into_iter()
                // swscale's RGB→YUV is BT.601 limited too; wf-recorder labelled it full range.
                .chain(BT601_LIMITED_SRGB)
                .chain(if ws { ["-p", "intra-refresh=1"].to_vec() } else { Vec::new() })
                .map(String::from)
                .collect(),
        ));
        let (bin, patched) = recorder_bin();
        for (name, args) in candidates {
            let Ok(mut child) = Command::new(&bin)
                .args(if patched { vec!["--ii-control"] } else { Vec::new() })
                .args(["-o", output, "-b", "0", "-m", "flv", "-f", "/dev/stdout", "-y"])
                // Every refresh, not only damaged ones: a hardware cursor moves without
                // damaging the output, so a damage-driven capture froze while only the mouse
                // moved, and a still headless output gave no first frame (5 s per encoder tried).
                // A still screen costs ~100-byte frames, which also keep the phone's radio awake.
                .arg("-D")
                // The rate control needs the frame rate: the patched binary takes it as is
                // (--ii-rate); the stock one only through -r, whose fps filter costs a frame.
                // Without either, VA-API budgeted the bitrate over a million frames a second.
                .args(match (patched, rate) {
                    (true, 0) => vec!["--ii-rate".to_string(), fps.to_string()],
                    (true, r) => vec!["--ii-rate".to_string(), fps.to_string(), "-r".to_string(), r.to_string()],
                    (false, 0) => vec!["-r".to_string(), fps.to_string()],
                    (false, r) => vec!["-r".to_string(), r.to_string()],
                })
                .args(&args)
                .stdin(if patched { Stdio::piped() } else { Stdio::null() })
                .stdout(Stdio::piped())
                .stderr(if patched { Stdio::piped() } else { Stdio::null() })
                .kill_on_drop(true)
                .spawn()
            else {
                return None;
            };
            let Some(mut out) = child.stdout.take() else { continue };
            let control = child.stdin.take();
            let base = Arc::new(std::sync::atomic::AtomicU64::new(0));
            let stderr = child.stderr.take().map(|err| {
                let base = base.clone();
                AbortOnDrop(
                    tokio::spawn(async move {
                        use tokio::io::AsyncBufReadExt;
                        let mut lines = BufReader::new(err).lines();
                        while let Ok(Some(l)) = lines.next_line().await {
                            if let Some(v) = l.strip_prefix("ii-base-usec=").and_then(|v| v.trim().parse().ok()) {
                                base.store(v, Ordering::Relaxed);
                            }
                        }
                    })
                    .abort_handle(),
                )
            });
            let first = timeout(Duration::from_secs(5), async {
                let mut header = [0u8; 13];
                out.read_exact(&mut header).await?;
                if &header[..3] != b"FLV" {
                    return Err(std::io::ErrorKind::InvalidData.into());
                }
                loop {
                    let (kind, ts, data) = read_tag(&mut out).await?;
                    if kind == 9 {
                        return Ok::<_, std::io::Error>((ts, data));
                    }
                }
            })
            .await;
            if let Ok(Ok(first)) = first {
                // The base is printed as the first frame is captured: on stderr, just before.
                for _ in 0..20 {
                    if !patched || base.load(Ordering::Relaxed) != 0 {
                        break;
                    }
                    tokio::time::sleep(Duration::from_millis(5)).await;
                }
                let refresh = ws && name != "vaapi";
                return Some(Recorder { child, out, encoder: name, refresh, first: Some(first), nal_len: 4, control, base, stderr });
            }
        }
        None
    }

    fn into_live(self) -> LiveEncoder {
        let Recorder { child, mut out, mut first, mut nal_len, encoder, control, base, stderr, .. } = self;
        let (tx, rx) = mpsc::channel(8);
        let task = tokio::spawn(async move {
            if let Some((ts, data)) = first.take() {
                if let Some(pkt) = encode_tag(&mut nal_len, frame_pts(&base, ts), &data) {
                    if tx.send(pkt).await.is_err() {
                        return;
                    }
                }
            }
            loop {
                let Ok((kind, ts, data)) = read_tag(&mut out).await else { break };
                if kind == 9 {
                    if let Some(pkt) = encode_tag(&mut nal_len, frame_pts(&base, ts), &data) {
                        if tx.send(pkt).await.is_err() {
                            break;
                        }
                    }
                }
            }
        });
        LiveEncoder { packets: rx, child, encoder, control, _reader: AbortOnDrop(task.abort_handle()), _stderr: stderr }
    }

    async fn pump<W: AsyncWriteExt + Unpin>(&mut self, wr: &mut W) -> Pump {
        if let Some((ts, data)) = self.first.take() {
            if self.forward(ts, &data, wr).await.is_err() {
                return Pump::Phone;
            }
        }
        loop {
            let Ok((kind, ts, data)) = read_tag(&mut self.out).await else { return Pump::Encoder };
            if kind == 9 && self.forward(ts, &data, wr).await.is_err() {
                return Pump::Phone;
            }
        }
    }

    /// One FLV video tag as a USB packet (`[u32 length]` + WS payload).
    async fn forward<W: AsyncWriteExt + Unpin>(&mut self, ts: u32, data: &[u8], wr: &mut W) -> std::io::Result<()> {
        let pts = frame_pts(&self.base, ts);
        let Some((_, payload)) = encode_tag(&mut self.nal_len, pts, data) else {
            return Ok(());
        };
        let mut pkt = Vec::with_capacity(4 + payload.len());
        pkt.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        pkt.extend_from_slice(&payload);
        wr.write_all(&pkt).await
    }
}

/// Encode one FLV video tag into `[u8 kind][u64 pts µs BE][Annex-B]`.
///
/// `pts_us` is on this PC's CLOCK_MONOTONIC ([`frame_pts`]): the capture time with the
/// patched wf-recorder, else the send time. With `pong`'s `now` the phone maps it onto its
/// own clock and times every frame (no B-frames, so presentation order is send order).
///
/// HEVC comes as enhanced FLV (FFmpeg ≥ 6.1): the first byte has the ex-header bit, the
/// frame type and a packet type, then the FourCC `hvc1`. Its codec config goes out as kind
/// [`KIND_HEVC_CONFIG`], so the phone switches decoder at exactly that frame, whichever way
/// (UDP or the WebSocket) it came.
fn encode_tag(nal_len: &mut usize, pts_us: u64, data: &[u8]) -> Option<(u8, Vec<u8>)> {
    if data.first().is_some_and(|b| b & 0x80 != 0) {
        return encode_ex_tag(nal_len, pts_us, data);
    }
    if data.len() < 5 || data[0] & 0x0f != 7 {
        return None;
    }
    let key = data[0] >> 4 == 1;
    let body = &data[5..];
    let (kind, annexb) = match data[1] {
        0 => match config_annexb(body) {
            Some((len, bytes)) => {
                *nal_len = len;
                (0u8, bytes)
            }
            None => return None,
        },
        1 => (if key { 2 } else { 1 }, nalus_annexb(body, *nal_len)),
        _ => return None,
    };
    if annexb.is_empty() {
        return None;
    }
    let mut pkt = Vec::with_capacity(9 + annexb.len());
    pkt.push(kind);
    pkt.extend_from_slice(&pts_us.to_be_bytes());
    pkt.extend_from_slice(&annexb);
    Some((kind, pkt))
}

async fn read_tag<R: AsyncRead + Unpin>(out: &mut R) -> std::io::Result<(u8, u32, Vec<u8>)> {
    let mut h = [0u8; 11];
    out.read_exact(&mut h).await?;
    let size = u32::from_be_bytes([0, h[1], h[2], h[3]]) as usize;
    if size > 16 << 20 {
        return Err(std::io::ErrorKind::InvalidData.into());
    }
    let ts = u32::from_be_bytes([h[7], h[4], h[5], h[6]]);
    let mut data = vec![0u8; size];
    out.read_exact(&mut data).await?;
    let mut prev = [0u8; 4];
    out.read_exact(&mut prev).await?;
    Ok((h[0], ts, data))
}

const START: [u8; 4] = [0, 0, 0, 1];

/// The AVCDecoderConfigurationRecord's SPS and PPS, and its NAL length size.
/// The phone's packet kind for an HEVC codec config (VPS/SPS/PPS, Annex-B); 0 is H.264's.
const KIND_HEVC_CONFIG: u8 = 10;

/// An enhanced-FLV video tag (HEVC): `[1 ex|3 frame type|4 packet type][fourcc]…`.
fn encode_ex_tag(nal_len: &mut usize, pts_us: u64, data: &[u8]) -> Option<(u8, Vec<u8>)> {
    if data.len() < 5 || &data[1..5] != b"hvc1" {
        return None;
    }
    let key = (data[0] >> 4) & 0x07 == 1;
    let body = &data[5..];
    let (kind, annexb) = match data[0] & 0x0f {
        // SequenceStart: the HEVCDecoderConfigurationRecord.
        0 => {
            let (len, bytes) = hvcc_annexb(body)?;
            *nal_len = len;
            (KIND_HEVC_CONFIG, bytes)
        }
        // CodedFrames: a 24-bit composition offset (0 without B-frames), then the NAL units.
        1 => (if key { 2 } else { 1 }, nalus_annexb(body.get(3..)?, *nal_len)),
        // CodedFramesX: the NAL units, no offset.
        3 => (if key { 2 } else { 1 }, nalus_annexb(body, *nal_len)),
        _ => return None,
    };
    if annexb.is_empty() {
        return None;
    }
    let mut pkt = Vec::with_capacity(9 + annexb.len());
    pkt.push(kind);
    pkt.extend_from_slice(&pts_us.to_be_bytes());
    pkt.extend_from_slice(&annexb);
    Some((kind, pkt))
}

/// HEVCDecoderConfigurationRecord → its NAL units (VPS, SPS, PPS…) with start codes, and
/// the length size of the frames' NAL units. The arrays start at byte 23.
fn hvcc_annexb(rec: &[u8]) -> Option<(usize, Vec<u8>)> {
    let len = (*rec.get(21)? & 3) as usize + 1;
    let arrays = *rec.get(22)? as usize;
    let mut out = Vec::new();
    let mut i = 23;
    for _ in 0..arrays {
        let count = u16::from_be_bytes([*rec.get(i + 1)?, *rec.get(i + 2)?]) as usize;
        i += 3;
        for _ in 0..count {
            let n = u16::from_be_bytes([*rec.get(i)?, *rec.get(i + 1)?]) as usize;
            out.extend_from_slice(&START);
            out.extend_from_slice(rec.get(i + 2..i + 2 + n)?);
            i += 2 + n;
        }
    }
    Some((len, out))
}

fn config_annexb(rec: &[u8]) -> Option<(usize, Vec<u8>)> {
    let len = (*rec.get(4)? & 3) as usize + 1;
    let mut out = Vec::new();
    let mut i = 5;
    for _ in 0..2 {
        let count = (*rec.get(i)? & if out.is_empty() { 0x1f } else { 0xff }) as usize;
        i += 1;
        for _ in 0..count {
            let n = u16::from_be_bytes([*rec.get(i)?, *rec.get(i + 1)?]) as usize;
            out.extend_from_slice(&START);
            out.extend_from_slice(rec.get(i + 2..i + 2 + n)?);
            i += 2 + n;
        }
    }
    Some((len, out))
}

fn nalus_annexb(mut body: &[u8], len: usize) -> Vec<u8> {
    let mut out = Vec::with_capacity(body.len() + 16);
    while body.len() > len {
        let n = body[..len].iter().fold(0usize, |acc, b| acc << 8 | *b as usize);
        let Some(nal) = body.get(len..len + n) else { break };
        out.extend_from_slice(&START);
        out.extend_from_slice(nal);
        body = &body[len + n..];
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn input_msg_parses_all_kinds_and_rejects_bad() {
        let (tx, rx) = std::sync::mpsc::channel();
        // Touch frame: 1 finger at (65535, 0)
        parse_input_msg(&[1, 1, 2, 0xff, 0xff, 0x00, 0x00], &tx).unwrap();
        match rx.recv().unwrap() {
            Cmd::ScreenFrame { fingers } => {
                assert_eq!(fingers.len(), 1);
                assert_eq!(fingers[0].0, 2);
                assert!((fingers[0].1 - 1.0).abs() < 1e-6);
                assert!((fingers[0].2 - 0.0).abs() < 1e-6);
            }
            _ => panic!("expected ScreenFrame"),
        }
        // Text frame
        parse_input_msg(&[2, 0, 2, b'h', b'i'], &tx).unwrap();
        match rx.recv().unwrap() {
            Cmd::ScreenText { text } => assert_eq!(text, "hi"),
            _ => panic!("expected ScreenText"),
        }
        // Key frame: "Return" with shift+ctrl (1 | 2 = 3)
        parse_input_msg(&[3, 6, b'R', b'e', b't', b'u', b'r', b'n', 3], &tx).unwrap();
        match rx.recv().unwrap() {
            Cmd::ScreenKey { key, mods } => {
                assert_eq!(key, "Return");
                assert_eq!(mods, vec!["shift".to_string(), "ctrl".to_string()]);
            }
            _ => panic!("expected ScreenKey"),
        }
        // Truncated / unknown
        assert!(parse_input_msg(&[], &tx).is_err());
        assert!(parse_input_msg(&[1, 1, 0], &tx).is_err());
        assert!(parse_input_msg(&[9], &tx).is_err());
    }

    #[test]
    fn writer_queue_congestion_by_bytes_and_age() {
        let q = WriterQueue::new();
        // 8 Mbps -> 0.2 s = 200_000 bytes
        assert!(!q.is_congested(8_000_000));
        assert!(q.push_video(1, vec![0u8; 150_000]));
        assert!(!q.is_congested(8_000_000));
        assert!(q.push_video(1, vec![0u8; 60_000]));
        assert!(q.is_congested(8_000_000));

        // Older than CONGESTION_AGE triggers congestion even with a tiny payload
        let q2 = WriterQueue::new();
        {
            let mut g = q2.inner.lock().unwrap();
            g.items.push_back(WriterItem {
                enqueued_at: Instant::now() - CONGESTION_AGE - Duration::from_millis(20),
                video_bytes: 100,
                is_frame: true,
                msg: Message::Binary(vec![0u8; 100].into()),
            });
            g.queued_bytes = 100;
        }
        assert!(q2.is_congested(80_000_000));
    }

    #[test]
    fn apply_quality_respects_adaptive_and_clamps() {
        let (_out_tx, out_rx) = watch::channel(String::from("HDMI-A-1"));
        let (in_tx, _in_rx) = std::sync::mpsc::channel();
        let mut sess = WsSession {
            dev: "d".into(),
            sid: 1,
            w: 1920,
            h: 1080,
            gop: 120,
            rate: 0,
            max_bitrate: 16_000_000,
            target_bitrate: 16_000_000,
            adaptive: true,
            screen_started: true,
            encoder_name: "nvenc",
            refresh: true,
            restarts: Vec::new(),
            output: out_rx,
            input_tx: in_tx,
            audio_src: watch::channel(None).1,
            audio: None,
            udp: None,
            wants_udp: false,
            hevc: false,
        };
        // Same settings -> no target change
        assert!(!sess.apply_quality(&json!({"t": "quality", "bitrate": 16_000_000, "adaptive": true})));
        // Lowered due to congestion, raising max doesn't immediately jump target while adaptive
        sess.target_bitrate = 11_200_000;
        assert!(!sess.apply_quality(&json!({"t": "quality", "bitrate": 24_000_000, "adaptive": true})));
        assert_eq!(sess.max_bitrate, 24_000_000);
        assert_eq!(sess.target_bitrate, 11_200_000);
        // Turning adaptive off snaps target to max
        assert!(sess.apply_quality(&json!({"t": "quality", "bitrate": 24_000_000, "adaptive": false})));
        assert_eq!(sess.target_bitrate, 24_000_000);
        // Clamp to 1..80 Mbps
        assert!(sess.apply_quality(&json!({"t": "quality", "bitrate": 200_000_000, "adaptive": false})));
        assert_eq!(sess.max_bitrate, 80_000_000);
        assert_eq!(sess.target_bitrate, 80_000_000);
    }
}

/// A datagram for the second screen on the link's UDP port (main.rs `discovery`): the
/// phone's hello for the session's UDP video.
pub fn udp_in(state: &State, pkt: &[u8], from: std::net::SocketAddr) {
    let peer = state.lock().unwrap().screen.as_ref().and_then(|slot| slot.udp_peer.clone());
    if let Some(peer) = peer {
        peer.hello(pkt, from);
    }
}
