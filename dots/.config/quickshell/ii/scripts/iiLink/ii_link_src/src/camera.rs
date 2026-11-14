//! The phone as this PC's webcam (PROTOCOL.md, "Webcam"): H.264 from the phone's
//! hardware encoder, decoded here into a camera every app can open.
//!
//! The shell arms a session (`camera` op, `a: "arm"`) once the phone asked over the
//! link; the phone then opens a second WebSocket on the link's own port and path
//! [`WS_PATH`] (same TLS and pinning, no other port to open, USB's `adb reverse`
//! covers it) and sends the session's token. The video is one message per encoder
//! buffer: `[u8 kind][u64 pts µs][Annex-B]`, kind 0 the SPS/PPS, 1 a frame, 2 a key
//! frame; text `meta` messages carry the size, how far to turn it and the mirror.
//!
//! Two stages, so the camera never goes away while the session lasts:
//!
//! - the **decoder** (`ffmpeg`, H.264 in, raw I420 out at the session's fixed size,
//!   turned, mirrored and fitted) starts again whenever the picture changes (a new
//!   size, turn or mirror) at the next key frame, which the phone is asked for;
//! - the **writer** (`ffmpeg … -f v4l2` into a v4l2loopback device, every app lists it;
//!   or `gst-launch-1.0 … pipewiresink`, a PipeWire camera with no kernel module) stays
//!   open the whole session and repeats the last picture while no new one comes (a
//!   decoder restarting, the phone reconfiguring its camera, a Wi-Fi hiccup), so apps
//!   reading the camera never see it vanish. A loopback device with exclusive caps is
//!   a camera only while something writes to it.
//!
//! A phone whose socket drops gets [`RECONNECT_GRACE`] to come back with the same token
//! before the session ends.

use std::process::Stdio;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Instant;

use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::process::{ChildStdin, Command};
use tokio::sync::{mpsc, oneshot, watch};
use tokio::time::{sleep_until, timeout, Duration};
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::WebSocketStream;

use crate::State;

pub const WS_PATH: &str = "/iilink/1/camera";
pub type Ws = WebSocketStream<tokio_rustls::server::TlsStream<TcpStream>>;

/// The phone has this long to connect after the shell armed the session.
const ARM_TIMEOUT: Duration = Duration::from_secs(30);
/// A camera streams 30 frames a second: this much silence is a socket gone.
const IDLE_TIMEOUT: Duration = Duration::from_secs(10);
/// How long the camera stays up, showing its last picture, for a phone to reconnect.
const RECONNECT_GRACE: Duration = Duration::from_secs(20);
/// With nothing new, the last picture again this often: apps take a camera that sends
/// nothing for a few seconds for a broken one.
const REPEAT_EVERY: Duration = Duration::from_millis(200);

#[derive(Clone, Copy, PartialEq)]
pub struct Cfg {
    pub mirror: bool,
    /// The PC's own extra turn, on top of the phone's.
    pub rotate: u32,
}

#[derive(Clone, PartialEq)]
enum Output {
    V4l2(String),
    PipeWire,
}

/// The armed or running session (one at a time).
pub struct Slot {
    sid: u64,
    token: String,
    /// The phone's camera sockets, handed to the session (again after a reconnect).
    conns: mpsc::UnboundedSender<Ws>,
    task: tokio::task::AbortHandle,
    end: Arc<End>,
    cfg: watch::Sender<Cfg>,
}

/// `cameraEnd`, exactly once per session, whoever ends it first.
struct End {
    dev: String,
    sid: u64,
    done: AtomicBool,
}

impl End {
    fn emit(&self, reason: &str) {
        if !self.done.swap(true, Ordering::SeqCst) {
            crate::emit(json!({"ev": "cameraEnd", "dev": self.dev, "sid": self.sid, "reason": reason}));
        }
    }
}

fn cfg_of(op: &Value) -> Cfg {
    Cfg { mirror: op["mirror"].as_bool().unwrap_or(false), rotate: (op["rotate"].as_u64().unwrap_or(0) as u32 / 90 % 4) * 90 }
}

/// The shell's `camera` ops: `arm`, `config`, `stop`.
pub fn op(state: &State, op: &Value) {
    let mut s = state.lock().unwrap();
    match op["a"].as_str().unwrap_or("") {
        "config" => {
            if let Some(slot) = &s.camera {
                slot.cfg.send_replace(cfg_of(op));
            }
        }
        "arm" => {
            if let Some(old) = s.camera.take() {
                old.task.abort();
                old.end.emit("stopped");
            }
            let dev = op["dev"].as_str().unwrap_or("").to_string();
            let sid = op["sid"].as_u64().unwrap_or(0);
            let end = Arc::new(End { dev: dev.clone(), sid, done: AtomicBool::new(false) });
            let output = match (op["sink"].as_str(), op["device"].as_str()) {
                (Some("pipewire"), _) => Output::PipeWire,
                (_, Some(d)) if d.starts_with("/dev/video") && !d.contains("..") => Output::V4l2(d.to_string()),
                _ => {
                    end.emit("device");
                    return;
                }
            };
            let (cfg_tx, cfg_rx) = watch::channel(cfg_of(op));
            let (conn_tx, conn_rx) = mpsc::unbounded_channel();
            let token = crate::random_hex(16);
            let guard = Guard { state: state.clone(), sid, end: end.clone(), reason: "stopped" };
            let task = tokio::spawn(session(conn_rx, output, cfg_rx, guard)).abort_handle();
            s.camera = Some(Slot { sid, token: token.clone(), conns: conn_tx, task, end, cfg: cfg_tx });
            crate::emit(json!({"ev": "camera", "dev": dev, "sid": sid, "token": token}));
        }
        _ => {
            if let Some(old) = s.camera.take() {
                old.task.abort();
                old.end.emit("stopped");
            }
        }
    }
}

/// The phone's camera socket, from the link's listener: the token, then on to the session.
pub async fn serve(mut ws: Ws, state: State) {
    let token = match timeout(Duration::from_secs(5), ws.next()).await {
        Ok(Some(Ok(Message::Text(t)))) => serde_json::from_str::<Value>(t.as_str())
            .ok()
            .filter(|v| v["t"] == "hello")
            .and_then(|v| v["token"].as_str().map(str::to_owned)),
        _ => None,
    };
    let Some(token) = token else { return };
    let s = state.lock().unwrap();
    if let Some(slot) = s.camera.as_ref().filter(|slot| crate::same(&token, &slot.token)) {
        let _ = slot.conns.send(ws);
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
        // The shell's stop already took the slot while holding the lock.
        if let Ok(mut s) = self.state.try_lock() {
            if s.camera.as_ref().is_some_and(|c| c.sid == self.sid) {
                s.camera = None;
            }
        }
        self.end.emit(self.reason);
    }
}

#[derive(Clone, Copy, PartialEq)]
struct Meta {
    w: u32,
    h: u32,
    rot: u32,
    /// The phone's own mirror switch, on top of the PC's.
    mirror: bool,
}

impl Meta {
    fn turned(&self, cfg: Cfg) -> (u32, u32) {
        if (self.rot + cfg.rotate) % 180 == 90 { (self.h, self.w) } else { (self.w, self.h) }
    }
}

async fn session(mut conns: mpsc::UnboundedReceiver<Ws>, output: Output, cfg_rx: watch::Receiver<Cfg>, mut guard: Guard) {
    let dev = guard.end.dev.clone();
    let sid = guard.sid;
    guard.reason = run(&mut conns, &output, cfg_rx, &dev, sid).await;
}

/// Why a phone's socket stopped.
enum Lost {
    /// It said goodbye, or went silent past the grace: the session is over.
    End(&'static str),
    /// It dropped: wait for it to come back.
    Dropped,
}

async fn run(conns: &mut mpsc::UnboundedReceiver<Ws>, output: &Output, mut cfg_rx: watch::Receiver<Cfg>, dev: &str, sid: u64) -> &'static str {
    let Ok(Some(mut ws)) = timeout(ARM_TIMEOUT, conns.recv()).await else { return "timeout" };
    let (exit_tx, mut exit_rx) = mpsc::unbounded_channel::<u64>();
    let mut cfg = *cfg_rx.borrow_and_update();
    let mut meta: Option<Meta> = None;
    let mut config: Option<Vec<u8>> = None;
    let mut dec: Option<Decoder> = None;
    let mut generation = 0u64;
    let mut writer: Option<Writer> = None;
    let mut restarts: Vec<Instant> = Vec::new();

    loop {
        let (mut tx, mut rx) = ws.split();
        // A fresh socket (a reconnect) starts at a key frame.
        let mut need_key = true;
        let _ = tx.send(Message::text(json!({"t": "key"}).to_string())).await;
        let lost = loop {
            tokio::select! {
                msg = timeout(IDLE_TIMEOUT, rx.next()) => match msg {
                    Ok(Some(Ok(Message::Text(t)))) => {
                        let Ok(v) = serde_json::from_str::<Value>(t.as_str()) else { continue };
                        if v["t"] == "bye" {
                            break Lost::End("closed");
                        }
                        if v["t"] != "meta" {
                            continue;
                        }
                        let m = Meta {
                            w: v["w"].as_u64().unwrap_or(0).clamp(16, 7680) as u32 & !1,
                            h: v["h"].as_u64().unwrap_or(0).clamp(16, 4320) as u32 & !1,
                            rot: (v["rot"].as_u64().unwrap_or(0) as u32 / 90 % 4) * 90,
                            mirror: v["mirror"].as_bool().unwrap_or(false),
                        };
                        if meta != Some(m) {
                            meta = Some(m);
                            if let Some(d) = dec.take() {
                                d.stop();
                            }
                            need_key = true;
                        }
                    }
                    Ok(Some(Ok(Message::Binary(b)))) => {
                        if b.len() < 9 {
                            continue;
                        }
                        let (kind, payload) = (b[0], &b[9..]);
                        if kind == 0 {
                            config = Some(payload.to_vec());
                        }
                        let Some(m) = meta else { continue };
                        if need_key {
                            if kind != 2 {
                                continue;
                            }
                            // The camera's size is the first picture's, for the whole session:
                            // a later aspect or turn is fitted into it, never a new device format.
                            let w = match writer.as_ref() {
                                Some(w) => w,
                                None => {
                                    let size = m.turned(cfg);
                                    let Some(w) = Writer::start(output, size) else { return "device" };
                                    crate::emit(json!({"ev": "cameraLive", "dev": dev, "sid": sid, "w": size.0, "h": size.1,
                                        "sink": if *output == Output::PipeWire { "pipewire" } else { "v4l2" }}));
                                    &*writer.insert(w)
                                }
                            };
                            if dec.is_none() {
                                generation += 1;
                                dec = Decoder::start(m, cfg, w.size, generation, exit_tx.clone(), w.frames.clone());
                            }
                            let Some(d) = dec.as_mut() else { return "decoder" };
                            // Key frames carry their SPS/PPS too; the stored ones cover a phone that does not.
                            if let Some(c) = &config {
                                let _ = d.write(c).await;
                            }
                            need_key = false;
                        }
                        if let Some(d) = dec.as_mut() {
                            // A write that fails is a decoder gone: its exit comes next.
                            let _ = d.write(payload).await;
                        }
                    }
                    Ok(Some(Ok(Message::Close(_)))) | Ok(Some(Err(_))) | Ok(None) | Err(_) => break Lost::Dropped,
                    Ok(Some(Ok(_))) => {}
                },
                Some(gen) = exit_rx.recv() => {
                    if !dec.as_ref().is_some_and(|d| d.generation == gen) {
                        continue;
                    }
                    dec = None;
                    restarts.retain(|t| t.elapsed() < Duration::from_secs(30));
                    if restarts.len() >= 5 {
                        return "decoder";
                    }
                    restarts.push(Instant::now());
                    need_key = true;
                    let _ = tx.send(Message::text(json!({"t": "key"}).to_string())).await;
                },
                changed = cfg_rx.changed() => {
                    if changed.is_err() {
                        return "stopped";
                    }
                    cfg = *cfg_rx.borrow_and_update();
                    if let Some(d) = dec.take() {
                        d.stop();
                    }
                    need_key = true;
                    let _ = tx.send(Message::text(json!({"t": "key"}).to_string())).await;
                },
                _ = async {
                    match writer.as_mut() {
                        Some(w) => { let _ = (&mut w.dead).await; }
                        None => std::future::pending::<()>().await,
                    }
                } => return "device",
            }
        };
        // Answer the phone's close (or say ours) and let the old socket go, so neither
        // side waits for the other.
        let _ = timeout(Duration::from_secs(1), tx.close()).await;
        drop((tx, rx));
        match lost {
            Lost::End(reason) => return reason,
            Lost::Dropped => {
                // The writer keeps the camera up, repeating the last picture, meanwhile.
                match timeout(RECONNECT_GRACE, conns.recv()).await {
                    Ok(Some(next)) => ws = next,
                    _ => return "closed",
                }
            }
        }
    }
}

/// Every picture out as it comes, none dropped or doubled: `-fps_mode` since ffmpeg 5.1,
/// `-vsync` before it (Debian 11, Ubuntu 22.04 ship 4.x). Asked once.
fn passthrough() -> [&'static str; 2] {
    static OLD: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    let old = *OLD.get_or_init(|| {
        let out = std::process::Command::new("ffmpeg").arg("-version").output().map(|o| o.stdout).unwrap_or_default();
        // "ffmpeg version 8.1.2 …", "ffmpeg version n7.1 …", "ffmpeg version 4.4.2-0ubuntu0.22.04.1 …"
        let v = String::from_utf8_lossy(&out);
        let ver = v.split_whitespace().nth(2).unwrap_or("").trim_start_matches('n');
        let mut parts = ver.split(|c: char| !c.is_ascii_digit()).map(|p| p.parse::<u32>().ok());
        match (parts.next().flatten(), parts.next().flatten()) {
            (Some(major), minor) => major < 5 || (major == 5 && minor.unwrap_or(0) < 1),
            // A git build ("N-112345-g…"): new.
            _ => false,
        }
    });
    if old { ["-vsync", "passthrough"] } else { ["-fps_mode", "passthrough"] }
}

/// The child that turns H.264 into raw pictures for the [`Writer`], fed on stdin.
struct Decoder {
    stdin: ChildStdin,
    kill: Option<oneshot::Sender<()>>,
    generation: u64,
}

impl Decoder {
    fn start(m: Meta, cfg: Cfg, size: (u32, u32), generation: u64, exit: mpsc::UnboundedSender<u64>, frames: mpsc::Sender<Vec<u8>>) -> Option<Decoder> {
        let rot = (m.rot + cfg.rotate) % 360;
        let mut vf: Vec<String> = Vec::new();
        match rot {
            90 => vf.push("transpose=clock".into()),
            180 => vf.push("hflip,vflip".into()),
            270 => vf.push("transpose=cclock".into()),
            _ => {}
        }
        if cfg.mirror != m.mirror {
            vf.push("hflip".into());
        }
        let (w, h) = size;
        vf.push(format!("scale={w}:{h}:force_original_aspect_ratio=decrease,pad={w}:{h}:(ow-iw)/2:(oh-ih)/2,format=yuv420p"));
        let mut child = Command::new("ffmpeg")
            .args([
                "-hide_banner", "-loglevel", "error", "-nostats", "-fflags", "nobuffer", "-flags", "low_delay",
                "-probesize", "32", "-analyzeduration", "0", "-f", "h264", "-i", "pipe:0", "-vf",
            ])
            .arg(vf.join(","))
            .args(passthrough())
            .args(["-f", "rawvideo", "pipe:1"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .ok()?;
        let stdin = child.stdin.take()?;
        let mut stdout = child.stdout.take()?;
        let (kill_tx, kill_rx) = oneshot::channel::<()>();
        let frame_len = (w * h * 3 / 2) as usize;
        tokio::spawn(async move {
            // Whole pictures only: a decoder killed mid-picture leaves no torn one behind.
            let read = async {
                loop {
                    let mut buf = vec![0u8; frame_len];
                    if stdout.read_exact(&mut buf).await.is_err() {
                        break;
                    }
                    // A writer behind (a PipeWire camera nobody reads blocks) loses this
                    // picture rather than stalling the decoder and, through it, the socket.
                    if let Err(mpsc::error::TrySendError::Closed(_)) = frames.try_send(buf) {
                        break;
                    }
                }
            };
            tokio::select! {
                _ = read => {}
                // Stopped, or the session dropped its sender.
                _ = kill_rx => {}
            }
            let _ = child.kill().await;
            let _ = exit.send(generation);
        });
        Some(Decoder { stdin, kill: Some(kill_tx), generation })
    }

    async fn write(&mut self, data: &[u8]) -> std::io::Result<()> {
        self.stdin.write_all(data).await
    }

    fn stop(mut self) {
        if let Some(k) = self.kill.take() {
            let _ = k.send(());
        }
    }
}

/// The camera itself: one child for the whole session, fed raw pictures (and the last
/// one again while none comes). Dropping it ends the child and with it the camera.
struct Writer {
    size: (u32, u32),
    frames: mpsc::Sender<Vec<u8>>,
    /// Fires when the child is gone (the device refused it, PipeWire went away).
    dead: oneshot::Receiver<()>,
    _task: AbortOnDrop,
}

struct AbortOnDrop(tokio::task::AbortHandle);

impl Drop for AbortOnDrop {
    fn drop(&mut self) {
        self.0.abort();
    }
}

impl Writer {
    fn start(output: &Output, size: (u32, u32)) -> Option<Writer> {
        let (w, h) = size;
        let mut cmd = match output {
            Output::V4l2(device) => {
                let mut c = Command::new("ffmpeg");
                c.args(["-hide_banner", "-loglevel", "error", "-nostats", "-f", "rawvideo", "-pix_fmt", "yuv420p", "-video_size"])
                    .arg(format!("{w}x{h}"))
                    .args(["-framerate", "30", "-i", "pipe:0"])
                    .args(passthrough())
                    .args(["-f", "v4l2"])
                    .arg(device);
                c
            }
            Output::PipeWire => {
                let mut c = Command::new("gst-launch-1.0");
                c.args(["-q", "fdsrc", "fd=0", "!", "rawvideoparse"])
                    .arg(format!("width={w}"))
                    .arg(format!("height={h}"))
                    .args([
                        "format=i420", "framerate=30/1", "!", "videoconvert", "!", "pipewiresink", "mode=provide", "sync=false",
                        "client-name=ii-tools-camera",
                        "stream-properties=\"props,media.class=Video/Source,media.role=Camera,node.name=ii-tools-camera,node.description=\\\"ii tools camera\\\"\"",
                    ]);
                c
            }
        };
        let mut child = cmd.stdin(Stdio::piped()).stdout(Stdio::null()).stderr(Stdio::null()).kill_on_drop(true).spawn().ok()?;
        let mut stdin = child.stdin.take()?;
        // Two pictures in flight at most; a writer further behind drops the rest.
        let (frames_tx, mut frames_rx) = mpsc::channel::<Vec<u8>>(2);
        let (dead_tx, dead_rx) = oneshot::channel::<()>();
        let task = tokio::spawn(async move {
            let mut last: Option<Vec<u8>> = None;
            let mut due = tokio::time::Instant::now() + REPEAT_EVERY;
            loop {
                tokio::select! {
                    frame = frames_rx.recv() => {
                        let Some(frame) = frame else { break };
                        if stdin.write_all(&frame).await.is_err() {
                            break;
                        }
                        last = Some(frame);
                        due = tokio::time::Instant::now() + REPEAT_EVERY;
                    }
                    _ = sleep_until(due), if last.is_some() => {
                        if let Some(f) = &last {
                            if stdin.write_all(f).await.is_err() {
                                break;
                            }
                        }
                        due = tokio::time::Instant::now() + REPEAT_EVERY;
                    }
                    _ = child.wait() => break,
                }
            }
            let _ = child.kill().await;
            let _ = dead_tx.send(());
        });
        Some(Writer { size, frames: frames_tx, dead: dead_rx, _task: AbortOnDrop(task.abort_handle()) })
    }
}
