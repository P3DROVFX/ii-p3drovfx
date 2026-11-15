//! The phone as a screen for this PC (PROTOCOL.md, "Second screen"): an output the shell
//! picked (a headless one to extend, a real one to mirror) goes to the phone as H.264,
//! and the phone's touches come back as a touchscreen mapped onto that output.
//!
//! Over USB only, for now: the shell runs `adb reverse` so the phone reaches the port
//! bound here on 127.0.0.1, and the first line it sends is the one-time token the shell
//! gave it over the authenticated link. The video is not on the link: a plain socket
//! carries frames as they are encoded, with no TLS or WebSocket framing in the way.
//!
//! Capture and encoding are wf-recorder's (wlr-screencopy, the GPU's encoder: NVENC,
//! then VA-API, then x264). It writes FLV, whose tags carry their own length and leave
//! it one per frame, so a frame goes out the moment it is encoded rather than when the
//! next one starts. The stream is damage-driven: a still screen sends nothing.
//!
//! To the phone: `[u32 length][u8 kind][u64 pts µs][Annex-B bytes]`, kind 0 the SPS and
//! PPS (codec config), 1 a frame, 2 a key frame. From the phone: `[1][n]` then n ×
//! `[u8 id][u16 x][u16 y]`, every finger down with x and y over 0–65535 of the picture;
//! `[2][u16 n][utf-8]` typed text; `[3][u8 n][key name][u8 mods]` one named key (mods:
//! 1 shift, 2 ctrl, 4 alt, 8 super).

use std::process::Stdio;
use std::sync::mpsc::Sender;

use serde_json::json;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::net::{TcpListener, TcpStream};
use tokio::process::{Child, ChildStdout, Command};
use tokio::time::{timeout, Duration};

use crate::input::Cmd;

pub struct Params {
    pub dev: String,
    /// The shell's number for this session, in every event: an old one's end can arrive
    /// after a new one began.
    pub sid: u64,
    /// The output to capture; the shell can point a session at another one (mirror's
    /// screen switch) and the capture starts again there.
    pub output: tokio::sync::watch::Receiver<String>,
    pub token: String,
    /// The output's size in pixels: the touchscreen's.
    pub w: i32,
    pub h: i32,
    pub bitrate: u64,
    pub input_tx: Sender<Cmd>,
}

/// Binds the port for the phone and serves it in the background; the shell is told
/// `screenEnd` when it is over, whatever ended it (aborting the task included).
pub fn start(mut p: Params) -> std::io::Result<(u16, tokio::task::AbortHandle)> {
    p.output.mark_unchanged();
    let std_listener = std::net::TcpListener::bind(("127.0.0.1", 0))?;
    std_listener.set_nonblocking(true)?;
    let port = std_listener.local_addr()?.port();
    let listener = TcpListener::from_std(std_listener)?;
    let task = tokio::spawn(async move {
        let mut guard = Guard { dev: p.dev.clone(), sid: p.sid, input_tx: p.input_tx.clone(), reason: "stopped" };
        guard.reason = run(listener, &p).await;
    });
    Ok((port, task.abort_handle()))
}

struct Guard {
    dev: String,
    sid: u64,
    input_tx: Sender<Cmd>,
    reason: &'static str,
}

impl Drop for Guard {
    fn drop(&mut self) {
        let _ = self.input_tx.send(Cmd::ScreenStop);
        crate::emit(json!({"ev": "screenEnd", "dev": self.dev, "sid": self.sid, "reason": self.reason}));
    }
}

async fn run(listener: TcpListener, p: &Params) -> &'static str {
    // The phone connects once the shell's `adb reverse` is up and it was told the port.
    let sock = loop {
        let Ok(Ok((mut s, _))) = timeout(Duration::from_secs(60), listener.accept()).await else {
            return "timeout";
        };
        let _ = s.set_nodelay(true);
        if let Ok(Ok(line)) = timeout(Duration::from_secs(5), read_line(&mut s)).await {
            if crate::same(&line, &p.token) {
                break s;
            }
        }
    };
    drop(listener);

    let Some(mut rec) = Recorder::start(p).await else { return "encoder" };
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
    let mut restarts: Vec<std::time::Instant> = Vec::new();
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
                    restarts.push(std::time::Instant::now());
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
        rec = match Recorder::start(p).await {
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

async fn touch_loop<R: AsyncRead + Unpin>(rd: &mut R, input_tx: &Sender<Cmd>) -> std::io::Result<()> {
    loop {
        match rd.read_u8().await? {
            1 => {
                let n = rd.read_u8().await? as usize;
                let mut fingers = Vec::with_capacity(n);
                for _ in 0..n {
                    let id = rd.read_u8().await? as i64;
                    let x = rd.read_u16().await? as f64 / 65535.0;
                    let y = rd.read_u16().await? as f64 / 65535.0;
                    fingers.push((id, x, y));
                }
                let _ = input_tx.send(Cmd::ScreenFrame { fingers });
            }
            2 => {
                let n = rd.read_u16().await? as usize;
                let mut text = vec![0u8; n];
                rd.read_exact(&mut text).await?;
                let _ = input_tx.send(Cmd::ScreenText { text: String::from_utf8_lossy(&text).into_owned() });
            }
            3 => {
                let n = rd.read_u8().await? as usize;
                let mut key = vec![0u8; n];
                rd.read_exact(&mut key).await?;
                let mask = rd.read_u8().await?;
                let mods = [(1, "shift"), (2, "ctrl"), (4, "alt"), (8, "super")]
                    .iter()
                    .filter(|(bit, _)| mask & bit != 0)
                    .map(|(_, m)| m.to_string())
                    .collect();
                let _ = input_tx.send(Cmd::ScreenKey { key: String::from_utf8_lossy(&key).into_owned(), mods });
            }
            _ => return Err(std::io::ErrorKind::InvalidData.into()),
        }
    }
}

// ── The encoder ──────────────────────────────────────────────────────────

struct Recorder {
    _child: Child,
    out: ChildStdout,
    encoder: &'static str,
    /// The video tag that proved the encoder works, sent before the rest.
    first: Option<(u32, Vec<u8>)>,
    nal_len: usize,
}

impl Recorder {
    /// The first encoder that produces a picture within a few seconds.
    async fn start(p: &Params) -> Option<Recorder> {
        let output = p.output.borrow().clone();
        let b = format!("b={}", p.bitrate);
        let mut candidates: Vec<(&'static str, Vec<String>)> = vec![(
            "nvenc",
            ["-c", "h264_nvenc", "-p", "preset=p1", "-p", "tune=ull", "-p", "zerolatency=1", "-p", "rc=cbr", "-p", &b, "-p", "g=240"]
                .map(String::from)
                .to_vec(),
        )];
        let mut nodes: Vec<String> = std::fs::read_dir("/dev/dri")
            .map(|d| d.filter_map(|e| e.ok()).map(|e| e.path().to_string_lossy().into_owned()).filter(|p| p.contains("renderD")).collect())
            .unwrap_or_default();
        nodes.sort();
        for node in nodes {
            candidates.push(("vaapi", ["-c", "h264_vaapi", "-d", &node, "-p", &b, "-p", "g=240"].map(String::from).to_vec()));
        }
        candidates.push((
            "x264",
            ["-c", "libx264", "-x", "yuv420p", "-p", "preset=ultrafast", "-p", "tune=zerolatency", "-p", &b, "-p", "g=240"]
                .map(String::from)
                .to_vec(),
        ));
        for (name, args) in candidates {
            let Ok(mut child) = Command::new("wf-recorder")
                .args(["-o", &output, "-b", "0", "-m", "flv", "-f", "/dev/stdout", "-y"])
                .args(&args)
                .stdin(Stdio::null())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .kill_on_drop(true)
                .spawn()
            else {
                return None;
            };
            let Some(mut out) = child.stdout.take() else { continue };
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
                return Some(Recorder { _child: child, out, encoder: name, first: Some(first), nal_len: 4 });
            }
        }
        None
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

    /// One FLV video tag as a packet for the phone, its NAL units in Annex-B.
    async fn forward<W: AsyncWriteExt + Unpin>(&mut self, ts: u32, data: &[u8], wr: &mut W) -> std::io::Result<()> {
        if data.len() < 5 || data[0] & 0x0f != 7 {
            return Ok(());
        }
        let key = data[0] >> 4 == 1;
        let cts = (i32::from_be_bytes([data[2], data[3], data[4], 0]) >> 8) as i64;
        let pts_us = ((ts as i64 + cts).max(0) as u64) * 1000;
        let body = &data[5..];
        let (kind, annexb) = match data[1] {
            0 => match config_annexb(body) {
                Some((len, bytes)) => {
                    self.nal_len = len;
                    (0u8, bytes)
                }
                None => return Ok(()),
            },
            1 => (if key { 2 } else { 1 }, nalus_annexb(body, self.nal_len)),
            _ => return Ok(()),
        };
        if annexb.is_empty() {
            return Ok(());
        }
        let mut pkt = Vec::with_capacity(13 + annexb.len());
        pkt.extend_from_slice(&((9 + annexb.len()) as u32).to_be_bytes());
        pkt.push(kind);
        pkt.extend_from_slice(&pts_us.to_be_bytes());
        pkt.extend_from_slice(&annexb);
        wr.write_all(&pkt).await
    }
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
