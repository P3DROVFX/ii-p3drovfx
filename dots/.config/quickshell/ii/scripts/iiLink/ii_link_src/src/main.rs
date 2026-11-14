//! ii link: the socket the ii tools Android app talks to.
//!
//! The helper owns the network side only — TLS, the WebSocket, pairing, the paired
//! devices and LAN discovery — and relays every authenticated message to the shell
//! as NDJSON on stdout. It executes nothing: what a message *does* is decided in QML
//! (services/IiLinkService.qml), against a list of allowed actions. The wire format
//! is in ../PROTOCOL.md.
//!
//! It is started only while a phone is paired (or being paired), and sleeps on its
//! sockets and stdin: no timers run while nothing happens.

mod files;
mod gallery;
mod icons;
mod input;
mod mpris;
mod screen;

use std::collections::HashMap;
use std::fs;
use std::io::Write;
use std::net::{IpAddr, SocketAddr};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use futures_util::{SinkExt, StreamExt};
use ring::digest::{digest, SHA256};
use ring::rand::{SecureRandom, SystemRandom};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::net::{TcpListener, TcpStream, UdpSocket};
use tokio::sync::mpsc;
use tokio::time::timeout;
use tokio_rustls::TlsAcceptor;
use tokio_tungstenite::tungstenite::handshake::server::{ErrorResponse, Request, Response};
use tokio_tungstenite::tungstenite::http::StatusCode;
use tokio_tungstenite::tungstenite::protocol::WebSocketConfig;
use tokio_tungstenite::tungstenite::Message;

const WS_PATH: &str = "/iilink/1";
const PAIR_WINDOW: Duration = Duration::from_secs(300);
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(10);
/// The app pings every 60 s and now stays connected in the background; three missed
/// pings is a phone that walked away without closing the socket.
const IDLE_TIMEOUT: Duration = Duration::from_secs(200);
const MAX_CONNECTIONS: usize = 8;

#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
struct Peer {
    id: String,
    name: String,
    model: String,
    token_hash: String,
    paired_at: u64,
    last_seen: u64,
}

struct Pairing {
    secret: String,
    serial: u64,
}

struct Conn {
    serial: u64,
    tx: mpsc::UnboundedSender<Message>,
}

struct Shared {
    dir: PathBuf,
    name: String,
    port: u16,
    fingerprint: String,
    peers: Vec<Peer>,
    pairing: Option<Pairing>,
    pair_serial: u64,
    conns: HashMap<String, Conn>,
    conn_serial: u64,
    open_sockets: usize,
    /// The phones' media as MPRIS players; the shell switches it (`config`).
    media: bool,
    media_tx: mpsc::UnboundedSender<mpris::Event>,
    /// Whether a phone may be this PC's touchpad and keyboard (the shell's setting).
    touchpad: bool,
    /// Whether a phone may be a slide clicker here (the shell's setting).
    present: bool,
    input_tx: std::sync::mpsc::Sender<input::Cmd>,
    /// The phone being a screen here (one at a time), and its device.
    screen: Option<(String, tokio::task::AbortHandle, tokio::sync::watch::Sender<String>)>,
}

type State = Arc<Mutex<Shared>>;

// ── Output ───────────────────────────────────────────────────────────────

fn emit(v: Value) {
    let mut out = std::io::stdout().lock();
    let _ = writeln!(out, "{v}");
    let _ = out.flush();
}

fn now_ms() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0)
}

fn random_hex(bytes: usize) -> String {
    let mut buf = vec![0u8; bytes];
    SystemRandom::new().fill(&mut buf).expect("system RNG");
    hex::encode(buf)
}

fn sha256_hex(data: &[u8]) -> String {
    hex::encode(digest(&SHA256, data))
}

/// Equal-length comparison that does not stop at the first difference.
fn same(a: &str, b: &str) -> bool {
    a.len() == b.len() && a.bytes().zip(b.bytes()).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

// ── Files ────────────────────────────────────────────────────────────────

fn write_private(path: &Path, data: &[u8]) -> std::io::Result<()> {
    let tmp = path.with_extension("tmp");
    {
        let mut f = fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&tmp)?;
        f.write_all(data)?;
        f.sync_all()?;
    }
    fs::rename(&tmp, path)
}

fn load_identity(dir: &Path) -> Result<(CertificateDer<'static>, PrivateKeyDer<'static>), String> {
    let cert_path = dir.join("cert.der");
    let key_path = dir.join("key.der");
    if let (Ok(cert), Ok(key)) = (fs::read(&cert_path), fs::read(&key_path)) {
        return Ok((CertificateDer::from(cert), PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(key))));
    }
    // The certificate is never checked by name: the app pins its fingerprint.
    let generated = rcgen::generate_simple_self_signed(vec!["ii-link".to_string()]).map_err(|e| e.to_string())?;
    let cert = generated.cert.der().to_vec();
    let key = generated.signing_key.serialize_der();
    write_private(&cert_path, &cert).map_err(|e| e.to_string())?;
    write_private(&key_path, &key).map_err(|e| e.to_string())?;
    Ok((CertificateDer::from(cert), PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(key))))
}

fn load_peers(dir: &Path) -> Vec<Peer> {
    fs::read(dir.join("peers.json")).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}

fn save_peers(dir: &Path, peers: &[Peer]) {
    if let Ok(data) = serde_json::to_vec_pretty(peers) {
        if let Err(e) = write_private(&dir.join("peers.json"), &data) {
            emit(json!({"ev": "error", "msg": format!("saving peers: {e}")}));
        }
    }
}

fn peers_event(peers: &[Peer]) -> Value {
    let list: Vec<Value> = peers
        .iter()
        .map(|p| json!({"id": p.id, "name": p.name, "model": p.model, "pairedAt": p.paired_at, "lastSeen": p.last_seen}))
        .collect();
    json!({"ev": "peers", "list": list})
}

// ── Pairing ──────────────────────────────────────────────────────────────

/// Addresses the phone can try, the LAN ones first. Container and VM bridges are
/// never reachable from the phone and would only slow its first attempt down.
fn addresses() -> Vec<String> {
    let mut lan = Vec::new();
    let mut other = Vec::new();
    for iface in if_addrs::get_if_addrs().unwrap_or_default() {
        let IpAddr::V4(ip) = iface.ip() else { continue };
        if ip.is_loopback() || ip.is_link_local() {
            continue;
        }
        let n = iface.name.as_str();
        if ["docker", "br-", "veth", "virbr", "podman", "lxc", "vmnet"].iter().any(|p| n.starts_with(p)) {
            continue;
        }
        if ip.is_private() { lan.push(ip.to_string()) } else { other.push(ip.to_string()) }
    }
    lan.extend(other);
    lan
}

/// What a phone needs to wake this PC (Wake-on-LAN): each LAN interface's MAC and its
/// subnet broadcast. Wired ones first: Wi-Fi rarely wakes from a magic packet.
fn wake_targets() -> Vec<Value> {
    let mut wired = Vec::new();
    let mut wifi = Vec::new();
    for iface in if_addrs::get_if_addrs().unwrap_or_default() {
        let if_addrs::IfAddr::V4(v4) = &iface.addr else { continue };
        if !v4.ip.is_private() || v4.ip.is_loopback() {
            continue;
        }
        let n = iface.name.as_str();
        if ["docker", "br-", "veth", "virbr", "podman", "lxc", "vmnet", "tailscale", "wg"].iter().any(|p| n.starts_with(p)) {
            continue;
        }
        let Ok(mac) = fs::read_to_string(format!("/sys/class/net/{n}/address")) else { continue };
        let mac = mac.trim().to_string();
        if mac.is_empty() || mac == "00:00:00:00:00:00" {
            continue;
        }
        let is_wifi = Path::new(&format!("/sys/class/net/{n}/wireless")).exists();
        let target = json!({"iface": n, "mac": mac, "broadcast": v4.broadcast.map(|b| b.to_string()), "wifi": is_wifi});
        if is_wifi { wifi.push(target) } else { wired.push(target) }
    }
    wired.extend(wifi);
    wired
}

fn percent_encode(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

fn start_pairing(state: &State) {
    let (url, serial) = {
        let mut s = state.lock().unwrap();
        s.pair_serial += 1;
        let serial = s.pair_serial;
        let secret = random_hex(16);
        let url = format!(
            "iilink://pair?v=1&h={}&p={}&fp={}&s={}&n={}",
            addresses().join(","),
            s.port,
            s.fingerprint,
            secret,
            percent_encode(&s.name)
        );
        s.pairing = Some(Pairing { secret, serial });
        (url, serial)
    };
    let qr = qrcodegen::QrCode::encode_text(&url, qrcodegen::QrCodeEcc::Medium)
        .map(|q| {
            (0..q.size())
                .map(|y| (0..q.size()).map(|x| if q.get_module(x, y) { '1' } else { '0' }).collect::<String>())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    emit(json!({"ev": "pairing", "url": url, "qr": qr, "expires": now_ms() + PAIR_WINDOW.as_millis() as u64}));

    let state = state.clone();
    tokio::spawn(async move {
        tokio::time::sleep(PAIR_WINDOW).await;
        let mut s = state.lock().unwrap();
        if s.pairing.as_ref().is_some_and(|p| p.serial == serial) {
            s.pairing = None;
            emit(json!({"ev": "pairingEnd", "reason": "timeout"}));
        }
    });
}

// ── Connections ──────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct Hello {
    t: String,
    #[serde(default)]
    id: String,
    #[serde(default)]
    token: String,
    #[serde(default)]
    secret: String,
    #[serde(default)]
    name: String,
    #[serde(default)]
    model: String,
}

/// Reads the first frame and turns it into a device id, or the reason to refuse.
fn authenticate(state: &State, hello: &Hello) -> Result<(String, Value), &'static str> {
    let mut s = state.lock().unwrap();
    match hello.t.as_str() {
        "pair" => {
            let Some(p) = s.pairing.as_ref() else { return Err("not_pairing") };
            if !same(&p.secret, &hello.secret) {
                return Err("bad_secret");
            }
            s.pairing = None;
            let id = random_hex(6);
            let token = random_hex(32);
            let name: String = hello.name.chars().take(64).collect();
            let model: String = hello.model.chars().take(64).collect();
            let now = now_ms();
            s.peers.push(Peer { id: id.clone(), name: name.clone(), model: model.clone(), token_hash: sha256_hex(token.as_bytes()), paired_at: now, last_seen: now });
            save_peers(&s.dir, &s.peers);
            // Peers before pairingEnd: the shell keeps the helper alive only while a
            // phone is paired or a pairing is open, and must never see neither.
            emit(peers_event(&s.peers));
            emit(json!({"ev": "paired", "dev": {"id": id, "name": name, "model": model}}));
            emit(json!({"ev": "pairingEnd", "reason": "paired"}));
            Ok((id.clone(), json!({"t": "paired", "id": id, "token": token, "name": s.name})))
        }
        "auth" => {
            let hash = sha256_hex(hello.token.as_bytes());
            let dir = s.dir.clone();
            let name = s.name.clone();
            let Some(peer) = s.peers.iter_mut().find(|p| p.id == hello.id) else { return Err("unknown_device") };
            if !same(&peer.token_hash, &hash) {
                return Err("bad_token");
            }
            peer.last_seen = now_ms();
            let peers = s.peers.clone();
            save_peers(&dir, &peers);
            Ok((hello.id.clone(), json!({"t": "authOk", "name": name})))
        }
        _ => Err("expected_auth"),
    }
}

async fn serve(stream: TcpStream, addr: SocketAddr, acceptor: TlsAcceptor, state: State) {
    let tls = match timeout(HANDSHAKE_TIMEOUT, acceptor.accept(stream)).await {
        Ok(Ok(tls)) => tls,
        _ => return,
    };
    let config = WebSocketConfig::default().max_message_size(Some(8 << 20)).max_frame_size(Some(1 << 20));
    let check_path = |req: &Request, resp: Response| -> Result<Response, ErrorResponse> {
        if req.uri().path() == WS_PATH {
            Ok(resp)
        } else {
            let mut err = ErrorResponse::new(None);
            *err.status_mut() = StatusCode::NOT_FOUND;
            Err(err)
        }
    };
    let ws = match timeout(HANDSHAKE_TIMEOUT, tokio_tungstenite::accept_hdr_async_with_config(tls, check_path, Some(config))).await {
        Ok(Ok(ws)) => ws,
        _ => return,
    };
    let (mut sink, mut stream) = ws.split();

    let hello: Option<Hello> = match timeout(HANDSHAKE_TIMEOUT, stream.next()).await {
        Ok(Some(Ok(Message::Text(text)))) => serde_json::from_str(text.as_str()).ok(),
        _ => None,
    };
    let Some(hello) = hello else { return };
    let (dev, reply) = match authenticate(&state, &hello) {
        Ok(ok) => ok,
        Err(code) => {
            let _ = sink.send(Message::text(json!({"t": "authErr", "code": code}).to_string())).await;
            let _ = sink.close().await;
            return;
        }
    };
    if sink.send(Message::text(reply.to_string())).await.is_err() {
        return;
    }

    let (tx, mut rx) = mpsc::unbounded_channel::<Message>();
    let serial = {
        let mut s = state.lock().unwrap();
        s.conn_serial += 1;
        let serial = s.conn_serial;
        // A phone that reconnects before its old socket timed out replaces it.
        if let Some(old) = s.conns.insert(dev.clone(), Conn { serial, tx: tx.clone() }) {
            let _ = old.tx.send(Message::Close(None));
        }
        let peer = s.peers.iter().find(|p| p.id == dev);
        emit(json!({"ev": "connected", "dev": dev, "addr": addr.ip().to_string(),
            "name": peer.map(|p| p.name.as_str()).unwrap_or(""), "model": peer.map(|p| p.model.as_str()).unwrap_or("")}));
        serial
    };

    let writer = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            let closing = matches!(msg, Message::Close(_));
            if sink.send(msg).await.is_err() || closing {
                break;
            }
        }
        let _ = sink.close().await;
    });

    let dir = state.lock().unwrap().dir.clone();
    let mut incoming: Option<files::Incoming> = None;
    let mut thumb_batch = gallery::ThumbBatch::new();
    let mut idle_deadline = tokio::time::Instant::now() + IDLE_TIMEOUT;
    loop {
        let thumb_deadline = thumb_batch.deadline();
        tokio::select! {
            _ = tokio::time::sleep_until(idle_deadline) => break,
            _ = async {
                match thumb_deadline {
                    Some(d) => tokio::time::sleep_until(d).await,
                    None => std::future::pending().await,
                }
            } => {
                if let Some(ev) = thumb_batch.flush(&dev) {
                    emit(ev);
                }
            }
            msg = stream.next() => {
                idle_deadline = tokio::time::Instant::now() + IDLE_TIMEOUT;
                match msg {
                    Some(Ok(Message::Text(text))) => match serde_json::from_str::<Value>(text.as_str()) {
                        // "Forget this PC" on the phone: the pairing ends on both sides.
                        Ok(m) if m["t"] == "unpair" => {
                            handle_op(&state, &json!({"op": "unpair", "id": dev}).to_string());
                            break;
                        }
                        // Icons are drawn here, from the font, without bothering the shell; on a
                        // blocking thread, since the font is read from disk for each request.
                        Ok(m) if m["t"] == "icons" => {
                            let names: Vec<String> = m["names"].as_array().map(|a| {
                                a.iter().filter_map(|v| v.as_str().map(str::to_owned)).take(icons::MAX_NAMES).collect()
                            }).unwrap_or_default();
                            let tx = tx.clone();
                            tokio::task::spawn_blocking(move || {
                                let reply = json!({"t": "icons", "paths": icons::paths(&names)});
                                let _ = tx.send(Message::Text(reply.to_string().into()));
                            });
                        }
                        // A file follows as binary frames; a new header drops an unfinished one.
                        Ok(m) if m["t"] == "file" => {
                            if let Some(old) = incoming.take() {
                                old.discard();
                                if let Some(ev) = old.aborted(&dev) {
                                    emit(ev);
                                }
                            }
                            match files::start(&dir, &dev, &m) {
                                Ok(inc) => {
                                    if let Some(ev) = inc.started(&dev) {
                                        emit(ev);
                                    }
                                    incoming = Some(inc);
                                }
                                Err(reply) => {
                                    let _ = tx.send(Message::Text(reply.to_string().into()));
                                }
                            }
                        }
                        // The phone's players: MPRIS here, the shell need not hear about them.
                        Ok(m) if m["t"] == "media" || m["t"] == "mediaGone" => {
                            let s = state.lock().unwrap();
                            if s.media {
                                let ev = if m["t"] == "media" {
                                    let phone = s.peers.iter().find(|p| p.id == dev).map(|p| p.name.clone()).unwrap_or_default();
                                    mpris::Event::Update { dev: dev.clone(), phone, tx: tx.clone(), m }
                                } else {
                                    mpris::Event::Gone { dev: dev.clone(), source: m["source"].as_str().unwrap_or("").to_string() }
                                };
                                let _ = s.media_tx.send(ev);
                            }
                        }
                        // Touchpad and keyboard: many a second, straight to the input thread.
                        Ok(m) if m["t"] == "pad" || m["t"] == "kbd" => {
                            let s = state.lock().unwrap();
                            if !s.touchpad {
                                let _ = tx.send(Message::Text(json!({"t": "pad", "err": "disabled"}).to_string().into()));
                                continue;
                            }
                            if let Some(cmd) = input_cmd(&dev, &m, &tx) {
                                let _ = s.input_tx.send(cmd);
                            }
                        }
                        // The slide clicker: its keys go to the input thread; start, stop and the
                        // laser go on to the shell, which draws the dot.
                        Ok(m) if m["t"] == "present" => {
                            let s = state.lock().unwrap();
                            if !s.present {
                                let _ = tx.send(Message::Text(json!({"t": "present", "err": "disabled"}).to_string().into()));
                                continue;
                            }
                            if let Some(key) = m["key"].as_str() {
                                // Only the keys presentation apps listen for: the phone drives slides, not the PC.
                                const KEYS: &[&str] = &["Left", "Right", "Page_Up", "Page_Down", "Home", "End", "F5", "Escape", "b", "w"];
                                if KEYS.contains(&key) {
                                    let _ = s.input_tx.send(input::Cmd::Key { dev: dev.clone(), key: key.to_string(), mods: Vec::new() });
                                }
                                continue;
                            }
                            match m["a"].as_str() {
                                Some("start") => {
                                    let tx = tx.clone();
                                    let _ = s.input_tx.send(input::Cmd::Keys {
                                        dev: dev.clone(),
                                        reply: Box::new(move |v| {
                                            let _ = tx.send(Message::Text(v.to_string().into()));
                                        }),
                                    });
                                }
                                Some("stop") => {
                                    let _ = s.input_tx.send(input::Cmd::Stop { dev: dev.clone() });
                                }
                                _ => {}
                            }
                            emit(json!({"ev": "msg", "dev": dev, "m": m}));
                        }
                        Ok(m) if m.is_object() => emit(json!({"ev": "msg", "dev": dev, "m": m})),
                        _ => {}
                    },
                    Some(Ok(Message::Binary(data))) => {
                        if let Some(inc) = incoming.as_mut() {
                            match inc.write(&data, &dev) {
                                files::Step::More => {}
                                files::Step::Progress(event) => emit(event),
                                files::Step::Done(done) => {
                                    incoming = None;
                                    match done {
                                        files::Done::Shell(event) => emit(event),
                                        files::Done::GalleryThumb { file_id, item_id } => {
                                            let _ = tx.send(Message::text(json!({"t": "ok", "id": file_id}).to_string()));
                                            thumb_batch.push(item_id);
                                        }
                                        files::Done::GalleryFull { file_id, event } => {
                                            let _ = tx.send(Message::text(json!({"t": "ok", "id": file_id}).to_string()));
                                            emit(event);
                                        }
                                    }
                                }
                                files::Step::Failed(reply) => {
                                    if let Some(inc) = incoming.take() {
                                        if let Some(ev) = inc.aborted(&dev) {
                                            emit(ev);
                                        }
                                    }
                                    let _ = tx.send(Message::Text(reply.to_string().into()));
                                }
                            }
                        }
                    }
                    // Pings are answered by tungstenite itself.
                    Some(Ok(Message::Close(_))) | Some(Err(_)) | None => break,
                    Some(Ok(_)) => {}
                }
            }
        }
    }

    writer.abort();
    if let Some(inc) = incoming.take() {
        inc.discard();
        if let Some(ev) = inc.aborted(&dev) {
            emit(ev);
        }
    }
    let mut s = state.lock().unwrap();
    if s.peers.iter().any(|p| p.id == dev) {
        if let Some(ev) = thumb_batch.flush(&dev) {
            emit(ev);
        }
    }
    if s.conns.get(&dev).is_some_and(|c| c.serial == serial) {
        // A phone that reconnected keeps the players its new socket feeds.
        let _ = s.media_tx.send(mpris::Event::DevGone { dev: dev.clone() });
        let _ = s.input_tx.send(input::Cmd::Stop { dev: dev.clone() });
        s.conns.remove(&dev);
        emit(json!({"ev": "disconnected", "dev": dev}));
    }
}

/// A `pad` or `kbd` message as a command for the input thread.
fn input_cmd(dev: &str, m: &Value, tx: &mpsc::UnboundedSender<Message>) -> Option<input::Cmd> {
    let dev = dev.to_string();
    if m["t"] == "kbd" {
        if let Some(text) = m["text"].as_str() {
            return Some(input::Cmd::Text { dev, text: text.chars().take(4096).collect() });
        }
        let key = m["key"].as_str()?.to_string();
        let mods = m["mods"].as_array().map(|a| a.iter().filter_map(|v| v.as_str().map(str::to_owned)).collect()).unwrap_or_default();
        return Some(input::Cmd::Key { dev, key, mods });
    }
    match m["a"].as_str() {
        Some("start") => {
            let tx = tx.clone();
            Some(input::Cmd::Start {
                dev,
                w: m["w"].as_f64().unwrap_or(70.0),
                h: m["h"].as_f64().unwrap_or(120.0),
                reply: Box::new(move |v| {
                    let _ = tx.send(Message::Text(v.to_string().into()));
                }),
            })
        }
        Some("stop") => Some(input::Cmd::Stop { dev }),
        _ => {
            if let Some(button) = m["btn"].as_str() {
                return Some(input::Cmd::Button { dev, button: button.to_string(), down: m["down"].as_bool().unwrap_or(false) });
            }
            let fingers = m["f"].as_array()?.iter().take(10).filter_map(|f| {
                let f = f.as_array()?;
                Some((f.first()?.as_i64()?, f.get(1)?.as_f64()?, f.get(2)?.as_f64()?))
            }).collect();
            Some(input::Cmd::Frame { dev, fingers })
        }
    }
}

// ── Shell commands ───────────────────────────────────────────────────────

fn handle_op(state: &State, line: &str) {
    let Ok(op) = serde_json::from_str::<Value>(line) else { return };
    match op["op"].as_str().unwrap_or("") {
        "pair" => start_pairing(state),
        "pairCancel" => {
            let mut s = state.lock().unwrap();
            if s.pairing.take().is_some() {
                emit(json!({"ev": "pairingEnd", "reason": "cancel"}));
            }
        }
        "unpair" => {
            let id = op["id"].as_str().unwrap_or("");
            let mut s = state.lock().unwrap();
            s.peers.retain(|p| p.id != id);
            let dir = s.dir.clone();
            let peers = s.peers.clone();
            save_peers(&dir, &peers);
            if let Some(conn) = s.conns.remove(id) {
                let _ = conn.tx.send(Message::text(json!({"t": "unpaired"}).to_string()));
                let _ = conn.tx.send(Message::Close(None));
                emit(json!({"ev": "disconnected", "dev": id}));
            }
            drop(s);
            gallery::remove_cache(id);
            emit(peers_event(&peers));
        }
        "send" => {
            let text = op["m"].to_string();
            let dev = op["dev"].as_str().unwrap_or("*");
            let s = state.lock().unwrap();
            for (id, conn) in &s.conns {
                if dev == "*" || dev == id {
                    let _ = conn.tx.send(Message::text(text.clone()));
                }
            }
        }
        // A file for a phone: a `file` header, then the bytes as binary frames, read
        // and queued off the async thread. The shell is told `fileSent` when it is all
        // on its way (the phone answers `ok`/`err` with the same id itself).
        "sendFile" => {
            let dev = op["dev"].as_str().unwrap_or("").to_string();
            let tx = state.lock().unwrap().conns.get(&dev).map(|c| c.tx.clone());
            let id = op["id"].as_u64().unwrap_or(0);
            let Some(tx) = tx else {
                emit(json!({"ev": "fileSendFailed", "dev": dev, "id": id}));
                return;
            };
            let path = PathBuf::from(op["path"].as_str().unwrap_or(""));
            let header = json!({"t": "file", "id": id, "purpose": op["purpose"],
                "name": op["name"].as_str().map(str::to_owned)
                    .unwrap_or_else(|| path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default())});
            let delete = op["delete"].as_bool().unwrap_or(false);
            tokio::task::spawn_blocking(move || {
                let data = match fs::read(&path) {
                    Ok(d) if !d.is_empty() && d.len() as u64 <= files::MAX_SIZE => d,
                    _ => {
                        emit(json!({"ev": "fileSendFailed", "dev": dev, "id": id}));
                        return;
                    }
                };
                let mut header = header;
                header["size"] = json!(data.len());
                let mut ok = tx.send(Message::Text(header.to_string().into())).is_ok();
                for chunk in data.chunks(256 * 1024) {
                    ok = ok && tx.send(Message::Binary(chunk.to_vec().into())).is_ok();
                }
                if delete {
                    let _ = fs::remove_file(&path);
                }
                emit(json!({"ev": if ok { "fileSent" } else { "fileSendFailed" }, "dev": dev, "id": id}));
            });
        }
        // Settings the shell holds: for now, whether the phones' media become MPRIS players.
        "config" => {
            let mut s = state.lock().unwrap();
            if let Some(on) = op["present"].as_bool() {
                s.present = on;
            }
            if let Some(on) = op["touchpad"].as_bool() {
                s.touchpad = on;
                if !on {
                    for dev in s.conns.keys() {
                        let _ = s.input_tx.send(input::Cmd::Stop { dev: dev.clone() });
                    }
                }
            }
            if let Some(on) = op["media"].as_bool() {
                s.media = on;
                if !on {
                    let _ = s.media_tx.send(mpris::Event::Disable);
                }
            }
        }
        // The phone as a screen (screen.rs): the shell made the output and runs adb.
        "screen" => {
            let mut s = state.lock().unwrap();
            // Another screen for the running session (mirror's switch).
            if op["a"] == "output" {
                if let (Some((_, _, out)), Some(name)) = (s.screen.as_ref(), op["output"].as_str()) {
                    let _ = out.send(name.to_string());
                }
                return;
            }
            if let Some((_, task, _)) = s.screen.take() {
                task.abort();
            }
            if op["a"] != "start" {
                return;
            }
            let dev = op["dev"].as_str().unwrap_or("").to_string();
            let sid = op["sid"].as_u64().unwrap_or(0);
            let (out_tx, out_rx) = tokio::sync::watch::channel(op["output"].as_str().unwrap_or("").to_string());
            let params = screen::Params {
                dev: dev.clone(),
                sid,
                output: out_rx,
                token: op["token"].as_str().unwrap_or("").to_string(),
                w: op["w"].as_i64().unwrap_or(1920) as i32,
                h: op["h"].as_i64().unwrap_or(1080) as i32,
                bitrate: op["bitrate"].as_u64().unwrap_or(16_000_000).clamp(1_000_000, 80_000_000),
                input_tx: s.input_tx.clone(),
            };
            if params.output.borrow().is_empty() || params.token.len() < 16 {
                emit(json!({"ev": "screenEnd", "dev": dev, "sid": sid, "reason": "bad_arg"}));
                return;
            }
            match screen::start(params) {
                Ok((port, task)) => {
                    s.screen = Some((dev.clone(), task, out_tx));
                    emit(json!({"ev": "screen", "dev": dev, "sid": sid, "port": port}));
                }
                Err(_) => emit(json!({"ev": "screenEnd", "dev": dev, "sid": sid, "reason": "bind"})),
            }
        }
        "kick" => {
            let dev = op["dev"].as_str().unwrap_or("");
            let s = state.lock().unwrap();
            if let Some(conn) = s.conns.get(dev) {
                let _ = conn.tx.send(Message::Close(None));
            }
        }
        _ => {}
    }
}

// ── Discovery ────────────────────────────────────────────────────────────

/// Answers "iilink?" broadcasts so a phone whose PC changed address finds it again.
/// mDNS would need UDP 5353, which Fedora's default zone keeps closed; the link's own
/// port is already open, as KDE Connect's is.
async fn discovery(sock: UdpSocket, state: State) {
    let mut buf = [0u8; 512];
    loop {
        let Ok((n, from)) = sock.recv_from(&mut buf).await else { continue };
        if !buf[..n].starts_with(b"iilink?") {
            continue;
        }
        let reply = {
            let s = state.lock().unwrap();
            json!({"iilink": 1, "port": s.port, "fp": s.fingerprint, "name": s.name}).to_string()
        };
        let _ = sock.send_to(reply.as_bytes(), from).await;
    }
}

// ── Main ─────────────────────────────────────────────────────────────────

fn arg(args: &[String], name: &str) -> Option<String> {
    args.iter().position(|a| a == name).and_then(|i| args.get(i + 1)).cloned()
}

fn hostname() -> String {
    fs::read_to_string("/proc/sys/kernel/hostname").map(|s| s.trim().to_string()).unwrap_or_else(|_| "Linux".into())
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    let Some(dir) = arg(&args, "--state-dir").map(PathBuf::from) else {
        eprintln!("usage: ii_link --state-dir DIR [--port N] [--name NAME] | ii_link unpair --state-dir DIR --id ID");
        std::process::exit(2);
    };
    if let Err(e) = fs::create_dir_all(&dir) {
        eprintln!("ii_link: {}: {e}", dir.display());
        std::process::exit(1);
    }
    let _ = fs::set_permissions(&dir, fs::Permissions::from_mode(0o700));

    // One-shot: forget a device while the helper is not running.
    if args.get(1).map(String::as_str) == Some("unpair") {
        let id = arg(&args, "--id").unwrap_or_default();
        let mut peers = load_peers(&dir);
        peers.retain(|p| p.id != id);
        save_peers(&dir, &peers);
        gallery::remove_cache(&id);
        return;
    }

    let port: u16 = arg(&args, "--port").and_then(|p| p.parse().ok()).unwrap_or(47210);
    let name = arg(&args, "--name").filter(|n| !n.is_empty()).unwrap_or_else(hostname);

    let _ = rustls::crypto::ring::default_provider().install_default();
    let (cert, key) = match load_identity(&dir) {
        Ok(id) => id,
        Err(e) => {
            emit(json!({"ev": "error", "msg": format!("identity: {e}")}));
            std::process::exit(1);
        }
    };
    let fingerprint = sha256_hex(cert.as_ref());
    let tls = match rustls::ServerConfig::builder().with_no_client_auth().with_single_cert(vec![cert], key) {
        Ok(c) => c,
        Err(e) => {
            emit(json!({"ev": "error", "msg": format!("tls: {e}")}));
            std::process::exit(1);
        }
    };
    let acceptor = TlsAcceptor::from(Arc::new(tls));

    let listener = match TcpListener::bind(("0.0.0.0", port)).await {
        Ok(l) => l,
        Err(e) => {
            emit(json!({"ev": "error", "code": "port", "msg": format!("port {port}: {e}")}));
            std::process::exit(1);
        }
    };
    let udp = UdpSocket::bind(("0.0.0.0", port)).await.ok();

    let peers = load_peers(&dir);
    let (media_tx, media_rx) = mpsc::unbounded_channel();
    tokio::spawn(mpris::run(media_rx, dir.join("media")));
    let state: State = Arc::new(Mutex::new(Shared {
        dir,
        name: name.clone(),
        port,
        fingerprint: fingerprint.clone(),
        peers,
        pairing: None,
        pair_serial: 0,
        conns: HashMap::new(),
        conn_serial: 0,
        open_sockets: 0,
        media: false,
        media_tx,
        touchpad: false,
        present: false,
        input_tx: input::spawn(),
        screen: None,
    }));

    emit(json!({"ev": "ready", "port": port, "fp": fingerprint, "name": name, "addrs": addresses(), "wake": wake_targets(), "discovery": udp.is_some()}));
    emit(peers_event(&state.lock().unwrap().peers));

    if let Some(sock) = udp {
        tokio::spawn(discovery(sock, state.clone()));
    }

    let mut stdin = BufReader::new(tokio::io::stdin()).lines();
    loop {
        tokio::select! {
            line = stdin.next_line() => match line {
                Ok(Some(line)) => handle_op(&state, &line),
                // The shell went away: so does the link.
                _ => break,
            },
            accepted = listener.accept() => {
                let Ok((stream, addr)) = accepted else { continue };
                {
                    let mut s = state.lock().unwrap();
                    if s.open_sockets >= MAX_CONNECTIONS {
                        continue;
                    }
                    s.open_sockets += 1;
                }
                let _ = stream.set_nodelay(true);
                let (acceptor, state) = (acceptor.clone(), state.clone());
                tokio::spawn(async move {
                    serve(stream, addr, acceptor, state.clone()).await;
                    state.lock().unwrap().open_sockets -= 1;
                });
            }
        }
    }
}
