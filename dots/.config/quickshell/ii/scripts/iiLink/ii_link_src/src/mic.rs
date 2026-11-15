//! The phone as this PC's microphone (PROTOCOL.md, "Microphone"): raw 16-bit PCM from the
//! phone's `AudioRecord`, written into a PipeWire source every app lists as a microphone.
//!
//! Like the webcam (camera.rs), the shell arms a session (`mic` op, `a: "arm"`) once the phone
//! asked over the link; the phone then opens a second WebSocket on the link's own port and
//! path [`WS_PATH`] (same TLS and pinning, USB's `adb reverse` covers it) and sends the
//! session's token. Audio is one binary message per ~20 ms chunk of mono `s16le`; a text
//! `meta` message names the sample rate. `pw-cat` plays the chunks into a node with
//! `media.class=Audio/Source` (`ii-tools-mic`), which is the whole "virtual microphone": no
//! kernel module, no null sink, and nothing for the shell to route.
//!
//! PCM and not a codec: 48 kHz mono is 768 kbit/s, nothing for Wi-Fi or a cable, and there is
//! no encoder or decoder to add a frame of delay.
//!
//! A phone whose socket drops gets [`RECONNECT_GRACE`] to come back with the same token before
//! the session ends; the source stays up meanwhile (silent), so the apps recording it keep going.

use std::process::Stdio;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use tokio::io::AsyncWriteExt;
use tokio::net::TcpStream;
use tokio::process::Command;
use tokio::sync::{mpsc, oneshot};
use tokio::time::{timeout, Duration};
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::WebSocketStream;

use crate::State;

pub const WS_PATH: &str = "/iilink/1/mic";
pub type Ws = WebSocketStream<tokio_rustls::server::TlsStream<TcpStream>>;

/// The phone has this long to connect after the shell armed the session.
const ARM_TIMEOUT: Duration = Duration::from_secs(30);
/// Audio streams 50 chunks a second: this much silence is a socket gone.
const IDLE_TIMEOUT: Duration = Duration::from_secs(5);
/// How long the source stays up, silent, for a phone to reconnect.
const RECONNECT_GRACE: Duration = Duration::from_secs(20);
/// Chunks waiting for `pw-cat` (about 20 ms each): past this the oldest news is dropped, so a
/// stalled reader costs a click, never a growing delay.
const QUEUE_CHUNKS: usize = 12;

/// The armed or running session (one at a time).
pub struct Slot {
    sid: u64,
    token: String,
    /// The phone's mic sockets, handed to the session (again after a reconnect).
    conns: mpsc::UnboundedSender<Ws>,
    task: tokio::task::AbortHandle,
    end: Arc<End>,
}

/// `micEnd`, exactly once per session, whoever ends it first.
struct End {
    dev: String,
    sid: u64,
    done: AtomicBool,
}

impl End {
    fn emit(&self, reason: &str) {
        if !self.done.swap(true, Ordering::SeqCst) {
            crate::emit(json!({"ev": "micEnd", "dev": self.dev, "sid": self.sid, "reason": reason}));
        }
    }
}

/// The shell's `mic` ops: `arm` and `stop`.
pub fn op(state: &State, op: &Value) {
    let mut s = state.lock().unwrap();
    match op["a"].as_str().unwrap_or("") {
        "arm" => {
            if let Some(old) = s.mic.take() {
                old.task.abort();
                old.end.emit("stopped");
            }
            let dev = op["dev"].as_str().unwrap_or("").to_string();
            let sid = op["sid"].as_u64().unwrap_or(0);
            let end = Arc::new(End { dev: dev.clone(), sid, done: AtomicBool::new(false) });
            let (conn_tx, conn_rx) = mpsc::unbounded_channel();
            let token = crate::random_hex(16);
            let guard = Guard { state: state.clone(), sid, end: end.clone(), reason: "stopped" };
            let task = tokio::spawn(session(conn_rx, guard)).abort_handle();
            s.mic = Some(Slot { sid, token: token.clone(), conns: conn_tx, task, end });
            crate::emit(json!({"ev": "mic", "dev": dev, "sid": sid, "token": token}));
        }
        _ => {
            if let Some(old) = s.mic.take() {
                old.task.abort();
                old.end.emit("stopped");
            }
        }
    }
}

/// The phone's mic socket, from the link's listener: the token, then on to the session.
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
    if let Some(slot) = s.mic.as_ref().filter(|slot| crate::same(&token, &slot.token)) {
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
            if s.mic.as_ref().is_some_and(|c| c.sid == self.sid) {
                s.mic = None;
            }
        }
        self.end.emit(self.reason);
    }
}

async fn session(mut conns: mpsc::UnboundedReceiver<Ws>, mut guard: Guard) {
    let dev = guard.end.dev.clone();
    let sid = guard.sid;
    guard.reason = run(&mut conns, &dev, sid).await;
}

/// `pw-cat` as a microphone: the node is a source (`Audio/Source`) fed from its stdin.
struct Writer {
    chunks: mpsc::Sender<Vec<u8>>,
    /// Fires when the child is gone (PipeWire went away, `pw-cat` died).
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
    fn start(rate: u32) -> Option<Writer> {
        let mut child = Command::new("pw-cat")
            .args(["--playback", "--raw", "--rate"])
            .arg(rate.to_string())
            .args(["--channels", "1", "--format", "s16", "--latency", "40ms", "-P"])
            .arg("{ media.class=Audio/Source node.name=ii-tools-mic node.description=\"ii tools microphone\" media.role=Communication }")
            .arg("-")
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .ok()?;
        let mut stdin = child.stdin.take()?;
        let (chunks_tx, mut chunks_rx) = mpsc::channel::<Vec<u8>>(QUEUE_CHUNKS);
        let (dead_tx, dead_rx) = oneshot::channel::<()>();
        let task = tokio::spawn(async move {
            loop {
                tokio::select! {
                    chunk = chunks_rx.recv() => {
                        let Some(chunk) = chunk else { break };
                        if stdin.write_all(&chunk).await.is_err() {
                            break;
                        }
                    }
                    _ = child.wait() => break,
                }
            }
            let _ = child.kill().await;
            let _ = dead_tx.send(());
        })
        .abort_handle();
        Some(Writer { chunks: chunks_tx, dead: dead_rx, _task: AbortOnDrop(task) })
    }
}

async fn run(conns: &mut mpsc::UnboundedReceiver<Ws>, dev: &str, sid: u64) -> &'static str {
    let Ok(Some(mut ws)) = timeout(ARM_TIMEOUT, conns.recv()).await else { return "timeout" };
    let mut rate = 48_000u32;
    let mut writer: Option<Writer> = None;

    loop {
        let (mut tx, mut rx) = ws.split();
        let lost = loop {
            tokio::select! {
                msg = timeout(IDLE_TIMEOUT, rx.next()) => match msg {
                    Ok(Some(Ok(Message::Text(t)))) => {
                        let Ok(v) = serde_json::from_str::<Value>(t.as_str()) else { continue };
                        if v["t"] == "bye" {
                            break Err("closed");
                        }
                        if v["t"] == "meta" && writer.is_none() {
                            rate = v["rate"].as_u64().unwrap_or(48_000).clamp(8_000, 48_000) as u32;
                        }
                    }
                    Ok(Some(Ok(Message::Binary(b)))) => {
                        // Whole 16-bit samples only.
                        if b.len() < 2 {
                            continue;
                        }
                        if writer.is_none() {
                            let Some(w) = Writer::start(rate) else { return "device" };
                            crate::emit(json!({"ev": "micLive", "dev": dev, "sid": sid, "rate": rate}));
                            writer = Some(w);
                        }
                        if let Some(w) = &writer {
                            // A full queue drops this chunk: a click now, instead of a delay that grows.
                            let _ = w.chunks.try_send(b[..b.len() & !1].to_vec());
                        }
                    }
                    Ok(Some(Ok(Message::Close(_)))) | Ok(Some(Err(_))) | Ok(None) | Err(_) => break Ok(()),
                    Ok(Some(Ok(_))) => {}
                },
                _ = async {
                    match writer.as_mut() {
                        Some(w) => { let _ = (&mut w.dead).await; }
                        None => std::future::pending::<()>().await,
                    }
                } => return "device",
            }
        };
        let _ = timeout(Duration::from_secs(1), tx.close()).await;
        drop((tx, rx));
        if let Err(reason) = lost {
            return reason;
        }
        // Dropped: the source stays up, silent, while the phone comes back.
        match timeout(RECONNECT_GRACE, conns.recv()).await {
            Ok(Some(next)) => ws = next,
            _ => return "closed",
        }
    }
}
