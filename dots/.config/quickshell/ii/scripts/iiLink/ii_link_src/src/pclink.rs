//! PC ↔ PC: this helper and another PC's, linked directly (PROTOCOL.md, "PC link").
//!
//! The same socket the phone uses: the PC that dials sends `pcPair` (once, with the
//! one-time secret the other PC handed the phone) or `pcAuth` as its first frame, and
//! the session then carries the shell's messages both ways (`pcMsg` / `pcSend`). Each
//! side keeps a credential for dialing the other and the hash of the one the other
//! dials it with. Only the PC with the lower fingerprint dials back after a drop, so
//! two PCs never race each other into two sockets.

use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use base64::Engine;
use futures_util::stream::{SplitSink, SplitStream};
use futures_util::{SinkExt, StreamExt};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{DigitallySignedStruct, SignatureScheme};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::net::TcpStream;
use tokio::sync::{mpsc, Notify};
use tokio::time::{timeout, Instant};
use tokio_tungstenite::tungstenite::protocol::WebSocketConfig;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::WebSocketStream;

use crate::{addresses, emit, now_ms, random_hex, same, sha256_hex, write_private, Conn, State, WS_PATH};

/// How long the secret handed to the phone stays good.
pub const PAIR_WINDOW: Duration = Duration::from_secs(120);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(4);
const REPLY_TIMEOUT: Duration = Duration::from_secs(10);
const PING_EVERY: Duration = Duration::from_secs(60);
const IDLE_TIMEOUT: Duration = Duration::from_secs(200);
const BACKOFF_MAX: Duration = Duration::from_secs(300);
/// An image copied on the other PC, decoded (the shell sends at most 5 MiB).
const CLIP_MAX: usize = 6 << 20;
/// A file between PCs (a shelf item, a file sent over).
const FILE_MAX: u64 = 4 << 30;
const FILE_CHUNK: usize = 256 * 1024;
/// A shelf thumbnail, as the shell rendered it.
const THUMB_MAX: u64 = 96 * 1024;

/// Where a linked PC's files go out: a bounded queue the session's writer drains between
/// its other messages, and a lock so two files never interleave their frames.
#[derive(Clone)]
pub struct FileLane {
    tx: mpsc::Sender<Message>,
    lock: Arc<tokio::sync::Mutex<()>>,
}

/// A file arriving from a linked PC, written as it comes.
struct Incoming {
    id: String,
    purpose: String,
    name: String,
    size: u64,
    written: u64,
    reported: u64,
    path: std::path::PathBuf,
    file: std::fs::File,
}

/// A file name as it may be written here: no folders, no hidden or empty names.
fn safe_name(name: &str) -> String {
    let base = name.rsplit(['/', '\\']).next().unwrap_or("");
    let clean: String = base.chars().filter(|c| !c.is_control()).take(180).collect();
    let clean = clean.trim().trim_start_matches('.').to_string();
    if clean.is_empty() { "file".into() } else { clean }
}

fn safe_id(id: &str) -> Option<String> {
    (!id.is_empty() && id.len() <= 64 && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')).then(|| id.to_string())
}

/// Where a linked PC's files land: `<state>/pcshelf/<fp prefix>`.
fn pc_dir(dir: &Path, fp: &str) -> std::path::PathBuf {
    dir.join("pcshelf").join(&fp[..fp.len().min(16)])
}

#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct PcPeer {
    pub fp: String,
    pub name: String,
    pub hosts: Vec<String>,
    pub port: u16,
    /// What this PC presents when it dials the other.
    pub out_id: String,
    pub out_token: String,
    /// What the other presents when it dials this PC.
    pub in_id: String,
    pub in_token_hash: String,
    pub paired_at: u64,
    pub last_seen: u64,
    /// Its LAN adapters (`pcHello.wake`), to wake it from this PC when it is off.
    #[serde(default)]
    pub wake: Vec<Value>,
}

pub struct PcPairing {
    pub secret: String,
    pub until: Instant,
    /// A 6-digit code typed on the other PC: one wrong try closes the window.
    pub short: bool,
}

// ── Storage ──────────────────────────────────────────────────────────────

pub fn load(dir: &Path) -> Vec<PcPeer> {
    std::fs::read(dir.join("pcs.json")).ok().and_then(|d| serde_json::from_slice(&d).ok()).unwrap_or_default()
}

fn save(dir: &Path, pcs: &[PcPeer]) {
    if let Ok(data) = serde_json::to_vec_pretty(pcs) {
        if let Err(e) = write_private(&dir.join("pcs.json"), &data) {
            emit(json!({"ev": "error", "msg": format!("saving pcs: {e}")}));
        }
    }
}

pub fn peers_event(pcs: &[PcPeer]) -> Value {
    let list: Vec<Value> = pcs
        .iter()
        .map(|p| json!({"fp": p.fp, "name": p.name, "hosts": p.hosts, "pairedAt": p.paired_at, "lastSeen": p.last_seen, "canWake": !p.wake.is_empty()}))
        .collect();
    json!({"ev": "pcPeers", "list": list})
}

fn valid_fp(fp: &str) -> bool {
    fp.len() == 64 && fp.bytes().all(|b| b.is_ascii_hexdigit())
}

fn strings(v: &Value, max: usize) -> Vec<String> {
    v.as_array()
        .map(|a| a.iter().filter_map(|h| h.as_str()).filter(|h| !h.is_empty() && h.len() <= 64).take(max).map(str::to_owned).collect())
        .unwrap_or_default()
}

/// Stores [peer], replacing an older pairing with the same PC, and tells the shell.
fn store(state: &State, peer: PcPeer) {
    let mut s = state.lock().unwrap();
    s.pcs.retain(|p| p.fp != peer.fp);
    s.pcs.push(peer);
    save(&s.dir, &s.pcs);
    emit(peers_event(&s.pcs));
}

// ── Shell ops ────────────────────────────────────────────────────────────

pub fn op(state: &State, op: &Value) {
    match op["op"].as_str().unwrap_or("") {
        // The phone asks this PC to accept another: a secret for it to carry over.
        "pcPairOpen" => {
            let mut s = state.lock().unwrap();
            if !s.pc_enabled {
                emit(json!({"ev": "pcPairOpen", "req": op["req"], "err": "disabled"}));
                return;
            }
            let short = op["code"].as_bool().unwrap_or(false);
            let secret = if short {
                // Six digits from the system RNG, uniform enough for a two-minute window with one try.
                let n = u64::from_str_radix(&random_hex(8), 16).unwrap_or(0) % 1_000_000;
                format!("{n:06}")
            } else {
                random_hex(16)
            };
            s.pc_pairing = Some(PcPairing { secret: secret.clone(), until: Instant::now() + PAIR_WINDOW, short });
            emit(json!({"ev": "pcPairOpen", "req": op["req"], "secret": secret, "fp": s.fingerprint,
                "port": s.port, "name": s.name, "hosts": addresses()}));
        }
        // The other PC's secret, through the phone: dial it and pair.
        // Other PCs on this LAN, for linking without the phone: the same broadcast the
        // phone uses to find a PC whose address changed.
        "pcDiscover" => {
            let (port, mine) = {
                let s = state.lock().unwrap();
                (s.port, s.fingerprint.clone())
            };
            tokio::spawn(async move {
                let list = discover(port, &mine).await;
                emit(json!({"ev": "pcFound", "list": list}));
            });
        }
        "pcPairClose" => {
            if state.lock().unwrap().pc_pairing.take().is_some() {
                emit(json!({"ev": "pcPairClosed", "reason": "cancel"}));
            }
        }
        "pcPairJoin" => {
            let state = state.clone();
            let op = op.clone();
            tokio::spawn(async move { join(state, op).await });
        }
        "pcSend" => {
            let text = op["m"].to_string();
            let pc = op["pc"].as_str().unwrap_or("*");
            let s = state.lock().unwrap();
            for (fp, conn) in &s.pc_conns {
                if pc == "*" || pc == fp {
                    let _ = conn.tx.send(Message::text(text.clone()));
                }
            }
        }
        // A file to a linked PC, streamed from disk at the pace the socket takes it.
        "pcSendFile" => {
            let fp = op["pc"].as_str().unwrap_or("").to_string();
            let lane = state.lock().unwrap().pc_files.get(&fp).cloned();
            let id = op["id"].as_str().unwrap_or("").to_string();
            let Some(lane) = lane else {
                emit(json!({"ev": "pcFileSent", "pc": fp, "id": id, "ok": false}));
                return;
            };
            let path = std::path::PathBuf::from(op["path"].as_str().unwrap_or(""));
            let name = op["name"].as_str().map(str::to_owned)
                .unwrap_or_else(|| path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default());
            let purpose = op["purpose"].as_str().unwrap_or("put").to_string();
            tokio::spawn(async move {
                let ok = send_file(&lane, &path, &id, &name, &purpose).await;
                emit(json!({"ev": "pcFileSent", "pc": fp, "id": id, "ok": ok}));
            });
        }
        // This PC's shelf, for the linked PCs: names, and thumbnails read here from the
        // files the shell rendered (base64 rides the text frame).
        "pcShelf" => {
            let items: Vec<Value> = op["items"].as_array().cloned().unwrap_or_default();
            let targets: Vec<mpsc::UnboundedSender<Message>> = {
                let s = state.lock().unwrap();
                let pc = op["pc"].as_str().unwrap_or("*");
                s.pc_conns.iter().filter(|(fp, _)| pc == "*" || pc == fp.as_str()).map(|(_, c)| c.tx.clone()).collect()
            };
            if targets.is_empty() {
                return;
            }
            tokio::task::spawn_blocking(move || {
                let list: Vec<Value> = items.into_iter().take(48).map(|mut it| {
                    let thumb = it["thumb"].as_str().unwrap_or("").to_string();
                    it["thumb"] = Value::Null;
                    if !thumb.is_empty() {
                        if let Ok(meta) = std::fs::metadata(&thumb) {
                            if meta.len() <= THUMB_MAX {
                                if let Ok(data) = std::fs::read(&thumb) {
                                    it["thumb"] = json!(base64::engine::general_purpose::STANDARD.encode(data));
                                }
                            }
                        }
                    }
                    it
                }).collect();
                let text = json!({"t": "shelf", "items": list}).to_string();
                for tx in targets {
                    let _ = tx.send(Message::text(text.clone()));
                }
            });
        }
        // Wake a linked PC that is off, from its last `pcHello`.
        "pcWake" => {
            let fp = op["pc"].as_str().unwrap_or("");
            let targets = state.lock().unwrap().pcs.iter().find(|p| p.fp == fp).map(|p| p.wake.clone()).unwrap_or_default();
            emit(json!({"ev": "pcWoke", "pc": fp, "ok": wake(&targets)}));
        }
        "pcUnpair" => {
            let fp = op["pc"].as_str().unwrap_or("").to_string();
            let mut s = state.lock().unwrap();
            s.pcs.retain(|p| p.fp != fp);
            save(&s.dir, &s.pcs);
            // Its shelf copies go with it.
            let _ = std::fs::remove_dir_all(pc_dir(&s.dir, &fp));
            if let Some(conn) = s.pc_conns.remove(&fp) {
                let _ = conn.tx.send(Message::text(json!({"t": "pcUnpaired"}).to_string()));
                let _ = conn.tx.send(Message::Close(None));
                emit(json!({"ev": "pcDisconnected", "pc": fp}));
            }
            emit(peers_event(&s.pcs));
            s.pc_wake.notify_waiters();
        }
        _ => {}
    }
}

/// The shell switched the PC link on or off (`config.pcLink`).
pub fn set_enabled(state: &State, on: bool) {
    let was = {
        let mut s = state.lock().unwrap();
        let was = s.pc_enabled;
        s.pc_enabled = on;
        if !on {
            s.pc_pairing = None;
            for conn in s.pc_conns.values() {
                let _ = conn.tx.send(Message::Close(None));
            }
        }
        was
    };
    if on && !was {
        start_dialers(state);
    } else if !on {
        state.lock().unwrap().pc_wake.notify_waiters();
    }
}

// ── Accepting ────────────────────────────────────────────────────────────

/// The first frame was `pcPair` or `pcAuth`: another PC dialed in.
pub async fn accept<S>(mut sink: SplitSink<WebSocketStream<S>, Message>, stream: SplitStream<WebSocketStream<S>>, first: Value, addr: std::net::SocketAddr, state: State)
where
    S: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    let outcome = match first["t"].as_str().unwrap_or("") {
        "pcPair" => accept_pair(&state, &first, addr),
        "pcAuth" => accept_auth(&state, &first),
        _ => Err("expected_auth"),
    };
    let (fp, reply) = match outcome {
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
    session(sink, stream, fp.clone(), state.clone(), false).await;
    ensure_dialer(&state, &fp);
}

fn accept_pair(state: &State, m: &Value, addr: std::net::SocketAddr) -> Result<(String, Value), &'static str> {
    let fp = m["fp"].as_str().unwrap_or("").to_lowercase();
    let (out_id, out_token) = (m["id"].as_str().unwrap_or(""), m["token"].as_str().unwrap_or(""));
    if !valid_fp(&fp) || out_id.is_empty() || out_token.len() < 32 {
        return Err("bad_arg");
    }
    let (reply, peer) = {
        let mut s = state.lock().unwrap();
        if !s.pc_enabled {
            return Err("disabled");
        }
        let Some(p) = s.pc_pairing.as_ref() else { return Err("not_pairing") };
        if Instant::now() > p.until {
            s.pc_pairing = None;
            return Err("expired");
        }
        if !same(&p.secret, m["secret"].as_str().unwrap_or("")) {
            if p.short {
                s.pc_pairing = None;
                emit(json!({"ev": "pcPairClosed", "reason": "bad_code"}));
            }
            return Err("bad_secret");
        }
        s.pc_pairing = None;
        if fp == s.fingerprint {
            return Err("same_pc");
        }
        let in_id = random_hex(6);
        let in_token = random_hex(32);
        let seen = addr.ip().to_string();
        let mut hosts = vec![seen.clone()];
        hosts.extend(strings(&m["hosts"], 8).into_iter().filter(|h| *h != seen));
        let now = now_ms();
        let peer = PcPeer {
            fp: fp.clone(),
            name: m["name"].as_str().unwrap_or("").chars().take(64).collect(),
            hosts,
            port: m["port"].as_u64().and_then(|p| u16::try_from(p).ok()).unwrap_or(s.port),
            out_id: out_id.to_string(),
            out_token: out_token.to_string(),
            in_id: in_id.clone(),
            in_token_hash: sha256_hex(in_token.as_bytes()),
            paired_at: now,
            last_seen: now,
            wake: Vec::new(),
        };
        let reply = json!({"t": "pcPaired", "id": in_id, "token": in_token, "name": s.name, "fp": s.fingerprint,
            "port": s.port, "hosts": addresses()});
        (reply, peer)
    };
    let name = peer.name.clone();
    store(state, peer);
    emit(json!({"ev": "pcPaired", "pc": fp, "name": name}));
    Ok((fp, reply))
}

fn accept_auth(state: &State, m: &Value) -> Result<(String, Value), &'static str> {
    let mut s = state.lock().unwrap();
    if !s.pc_enabled {
        return Err("disabled");
    }
    let hash = sha256_hex(m["token"].as_str().unwrap_or("").as_bytes());
    let id = m["id"].as_str().unwrap_or("");
    let name = s.name.clone();
    let dir = s.dir.clone();
    let Some(peer) = s.pcs.iter_mut().find(|p| p.in_id == id) else { return Err("unknown_device") };
    if !same(&peer.in_token_hash, &hash) {
        return Err("bad_token");
    }
    peer.last_seen = now_ms();
    let fp = peer.fp.clone();
    let pcs = s.pcs.clone();
    save(&dir, &pcs);
    Ok((fp, json!({"t": "pcAuthOk", "name": name})))
}

// ── Dialing ──────────────────────────────────────────────────────────────

/// Trusts exactly the certificate whose SHA-256 the other PC's pairing carried.
#[derive(Debug)]
struct Pinned {
    fp: String,
    algs: rustls::crypto::WebPkiSupportedAlgorithms,
}

impl ServerCertVerifier for Pinned {
    fn verify_server_cert(&self, end_entity: &CertificateDer<'_>, _: &[CertificateDer<'_>], _: &ServerName<'_>, _: &[u8], _: UnixTime) -> Result<ServerCertVerified, rustls::Error> {
        if same(&sha256_hex(end_entity.as_ref()), &self.fp) {
            Ok(ServerCertVerified::assertion())
        } else {
            Err(rustls::Error::General("certificate does not match the paired PC".into()))
        }
    }

    fn verify_tls12_signature(&self, message: &[u8], cert: &CertificateDer<'_>, dss: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls12_signature(message, cert, dss, &self.algs)
    }

    fn verify_tls13_signature(&self, message: &[u8], cert: &CertificateDer<'_>, dss: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(message, cert, dss, &self.algs)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.algs.supported_schemes()
    }
}

type ClientWs = WebSocketStream<tokio_rustls::client::TlsStream<TcpStream>>;

/// The first address of [hosts] that answers with the pinned certificate, as a WebSocket.
async fn dial(fp: &str, hosts: &[String], port: u16) -> Result<(ClientWs, String), &'static str> {
    let verifier = Pinned { fp: fp.to_string(), algs: rustls::crypto::ring::default_provider().signature_verification_algorithms };
    let config = rustls::ClientConfig::builder().dangerous().with_custom_certificate_verifier(Arc::new(verifier)).with_no_client_auth();
    let connector = tokio_rustls::TlsConnector::from(Arc::new(config));
    let ws_config = WebSocketConfig::default().max_message_size(Some(8 << 20)).max_frame_size(Some(4 << 20));
    let mut why = "unreachable";
    for host in hosts {
        let Ok(Ok(tcp)) = timeout(CONNECT_TIMEOUT, TcpStream::connect((host.as_str(), port))).await else { continue };
        let _ = tcp.set_nodelay(true);
        let Ok(name) = ServerName::try_from("iilink".to_string()) else { continue };
        let tls = match timeout(CONNECT_TIMEOUT, connector.connect(name, tcp)).await {
            Ok(Ok(tls)) => tls,
            _ => {
                why = "certificate";
                continue;
            }
        };
        let h = if host.contains(':') { format!("[{host}]") } else { host.clone() };
        let url = format!("ws://{h}:{port}{WS_PATH}");
        match timeout(CONNECT_TIMEOUT, tokio_tungstenite::client_async_with_config(url, tls, Some(ws_config))).await {
            Ok(Ok((ws, _))) => return Ok((ws, host.clone())),
            _ => why = "protocol",
        }
    }
    Err(why)
}

/// `pcPairJoin`: the phone brought the other PC's secret; dial it and exchange credentials.
async fn join(state: State, op: Value) {
    let req = op["req"].clone();
    let fail = |code: &str| emit(json!({"ev": "pcPairFailed", "req": req, "code": code}));
    let fp = op["fp"].as_str().unwrap_or("").to_lowercase();
    let hosts = strings(&op["hosts"], 8);
    let port = op["port"].as_u64().and_then(|p| u16::try_from(p).ok()).unwrap_or(0);
    let secret = op["secret"].as_str().unwrap_or("").to_string();
    let (me, enabled) = {
        let s = state.lock().unwrap();
        (json!({"name": s.name, "fp": s.fingerprint, "port": s.port}), s.pc_enabled)
    };
    if !enabled {
        return fail("disabled");
    }
    if !valid_fp(&fp) || hosts.is_empty() || port == 0 || secret.is_empty() {
        return fail("bad_arg");
    }
    if me["fp"] == fp {
        return fail("same_pc");
    }
    let (ws, host) = match dial(&fp, &hosts, port).await {
        Ok(ok) => ok,
        Err(code) => return fail(code),
    };
    let (mut sink, mut stream) = ws.split();
    let in_id = random_hex(6);
    let in_token = random_hex(32);
    let hello = json!({"t": "pcPair", "secret": secret, "name": me["name"], "fp": me["fp"], "port": me["port"],
        "hosts": addresses(), "id": in_id, "token": in_token});
    if sink.send(Message::text(hello.to_string())).await.is_err() {
        return fail("unreachable");
    }
    let reply: Option<Value> = match timeout(REPLY_TIMEOUT, stream.next()).await {
        Ok(Some(Ok(Message::Text(t)))) => serde_json::from_str(t.as_str()).ok(),
        _ => None,
    };
    let Some(reply) = reply else { return fail("protocol") };
    if reply["t"] != "pcPaired" {
        return fail(reply["code"].as_str().unwrap_or("refused"));
    }
    let mut known = vec![host.clone()];
    known.extend(strings(&reply["hosts"], 8).into_iter().filter(|h| *h != host));
    let now = now_ms();
    let name: String = reply["name"].as_str().unwrap_or("").chars().take(64).collect();
    store(&state, PcPeer {
        fp: fp.clone(),
        name: name.clone(),
        hosts: known,
        port,
        out_id: reply["id"].as_str().unwrap_or("").to_string(),
        out_token: reply["token"].as_str().unwrap_or("").to_string(),
        in_id,
        in_token_hash: sha256_hex(in_token.as_bytes()),
        paired_at: now,
        last_seen: now,
        wake: Vec::new(),
    });
    emit(json!({"ev": "pcPaired", "req": req, "pc": fp, "name": name}));
    session(sink, stream, fp.clone(), state.clone(), true).await;
    ensure_dialer(&state, &fp);
}

/// One loop per PC this helper dials back (the lower fingerprint), each ending when its
/// generation is replaced, the PC is unpaired or the link is switched off.
pub fn start_dialers(state: &State) {
    let targets = {
        let mut s = state.lock().unwrap();
        s.pc_gen += 1;
        s.pc_wake.notify_waiters();
        s.pcs.iter().map(|p| p.fp.clone()).collect::<Vec<_>>()
    };
    for fp in targets {
        ensure_dialer(state, &fp);
    }
}

/// A dial loop for [fp], if this PC is the one that dials it back and none runs yet.
/// The PC that dials back after a drop is the one with the lower fingerprint.
fn ensure_dialer(state: &State, fp: &str) {
    let gen = {
        let mut s = state.lock().unwrap();
        if !s.pc_enabled || s.fingerprint.as_str() >= fp || !s.pcs.iter().any(|p| p.fp == fp) {
            return;
        }
        let gen = s.pc_gen;
        if s.pc_dialing.get(fp) == Some(&gen) {
            return;
        }
        s.pc_dialing.insert(fp.to_string(), gen);
        gen
    };
    let (state, fp) = (state.clone(), fp.to_string());
    tokio::spawn(async move {
        dial_loop(state.clone(), fp.clone(), gen).await;
        let mut s = state.lock().unwrap();
        if s.pc_dialing.get(&fp) == Some(&gen) {
            s.pc_dialing.remove(&fp);
        }
    });
}

async fn dial_loop(state: State, fp: String, gen: u64) {
    let mut wait = Duration::from_secs(2);
    let wake = state.lock().unwrap().pc_wake.clone();
    loop {
        // Armed before the check, so a session ending in between is not missed.
        let notified = wake.notified();
        tokio::pin!(notified);
        notified.as_mut().enable();
        let (peer, connected) = {
            let s = state.lock().unwrap();
            if s.pc_gen != gen || !s.pc_enabled {
                return;
            }
            let Some(peer) = s.pcs.iter().find(|p| p.fp == fp).cloned() else { return };
            (peer, s.pc_conns.contains_key(&fp))
        };
        if connected {
            // Asleep until a session ends (or the PC link changes).
            notified.await;
            wait = Duration::from_secs(2);
            continue;
        }
        if let Ok((ws, host)) = dial(&peer.fp, &peer.hosts, peer.port).await {
            let (mut sink, mut stream) = ws.split();
            let auth = json!({"t": "pcAuth", "id": peer.out_id, "token": peer.out_token});
            if sink.send(Message::text(auth.to_string())).await.is_ok() {
                let reply: Option<Value> = match timeout(REPLY_TIMEOUT, stream.next()).await {
                    Ok(Some(Ok(Message::Text(t)))) => serde_json::from_str(t.as_str()).ok(),
                    _ => None,
                };
                match reply.as_ref().and_then(|r| r["t"].as_str()) {
                    Some("pcAuthOk") => {
                        remember_host(&state, &fp, &host);
                        session(sink, stream, fp.clone(), state.clone(), true).await;
                        wait = Duration::from_secs(2);
                        continue;
                    }
                    // The other PC forgot this one: so does this one.
                    Some("authErr") if reply.as_ref().is_some_and(|r| r["code"] == "unknown_device" || r["code"] == "bad_token") => {
                        forget(&state, &fp);
                        return;
                    }
                    _ => {}
                }
            }
        }
        // Away (off, asleep, another network): back off, but wake for a link change.
        let _ = timeout(wait, notified.as_mut()).await;
        wait = (wait * 2).min(BACKOFF_MAX);
    }
}

fn remember_host(state: &State, fp: &str, host: &str) {
    let mut s = state.lock().unwrap();
    let Some(p) = s.pcs.iter_mut().find(|p| p.fp == fp) else { return };
    if p.hosts.first().map(String::as_str) == Some(host) {
        return;
    }
    p.hosts.retain(|h| h != host);
    p.hosts.insert(0, host.to_string());
    let pcs = s.pcs.clone();
    save(&s.dir, &pcs);
}

fn forget(state: &State, fp: &str) {
    let mut s = state.lock().unwrap();
    let _ = std::fs::remove_dir_all(pc_dir(&s.dir, fp));
    s.pcs.retain(|p| p.fp != fp);
    save(&s.dir, &s.pcs);
    emit(peers_event(&s.pcs));
}

// ── Session ──────────────────────────────────────────────────────────────

/// A linked PC's socket, whichever side dialed: its messages go to the shell as
/// `pcMsg`, the shell's `pcSend` comes out here.
async fn session<S>(mut sink: SplitSink<WebSocketStream<S>, Message>, mut stream: SplitStream<WebSocketStream<S>>, fp: String, state: State, ping: bool)
where
    S: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    let (tx, mut rx) = mpsc::unbounded_channel::<Message>();
    let (file_tx, mut file_rx) = mpsc::channel::<Message>(8);
    let (serial, dir, hello) = {
        let mut s = state.lock().unwrap();
        s.conn_serial += 1;
        let serial = s.conn_serial;
        // A PC that reconnects before its old socket timed out replaces it.
        if let Some(old) = s.pc_conns.insert(fp.clone(), Conn { serial, tx: tx.clone() }) {
            let _ = old.tx.send(Message::Close(None));
        }
        s.pc_files.insert(fp.clone(), FileLane { tx: file_tx, lock: Arc::new(tokio::sync::Mutex::new(())) });
        let name = s.pcs.iter().find(|p| p.fp == fp).map(|p| p.name.clone()).unwrap_or_default();
        emit(json!({"ev": "pcConnected", "pc": fp, "name": name}));
        (serial, s.dir.clone(), json!({"t": "pcHello", "name": s.name, "port": s.port, "hosts": addresses(), "wake": crate::wake_targets()}))
    };
    let _ = tx.send(Message::text(hello.to_string()));

    // Messages first, file frames in between: a large file never holds the clipboard back.
    let writer = tokio::spawn(async move {
        loop {
            let msg = tokio::select! {
                biased;
                m = rx.recv() => m,
                m = file_rx.recv() => m,
            };
            let Some(msg) = msg else { break };
            let closing = matches!(msg, Message::Close(_));
            if sink.send(msg).await.is_err() || closing {
                break;
            }
        }
        let _ = sink.close().await;
    });

    let mut incoming: Option<Incoming> = None;
    let mut idle = Instant::now() + IDLE_TIMEOUT;
    let mut next_ping = Instant::now() + PING_EVERY;
    loop {
        tokio::select! {
            _ = tokio::time::sleep_until(idle) => break,
            _ = tokio::time::sleep_until(next_ping), if ping => {
                next_ping = Instant::now() + PING_EVERY;
                if tx.send(Message::Ping(Vec::new().into())).is_err() {
                    break;
                }
            }
            msg = stream.next() => {
                idle = Instant::now() + IDLE_TIMEOUT;
                match msg {
                    Some(Ok(Message::Text(text))) => {
                        let Ok(m) = serde_json::from_str::<Value>(text.as_str()) else { continue };
                        match m["t"].as_str().unwrap_or("") {
                            "pcHello" => hello_from(&state, &fp, &m),
                            "pcUnpaired" => {
                                forget(&state, &fp);
                                break;
                            }
                            // An image off the other PC's clipboard: onto disk here, so the shell
                            // gets a path instead of megabytes of base64.
                            "clip" if m["data"].is_string() => {
                                if let Some(path) = save_clip(&dir, m["data"].as_str().unwrap_or("")) {
                                    emit(json!({"ev": "pcMsg", "pc": fp, "m": {"t": "clip", "mime": "image/png", "path": path}}));
                                }
                            }
                            "shelf" => {
                                let m = shelf_thumbs(&dir, &fp, m);
                                emit(json!({"ev": "pcMsg", "pc": fp, "m": m}));
                            }
                            // A file follows as binary frames; a new header drops an unfinished one.
                            "file" => {
                                if let Some(old) = incoming.take() {
                                    let _ = std::fs::remove_file(&old.path);
                                }
                                incoming = start_file(&dir, &fp, &m);
                                if incoming.is_none() {
                                    emit(json!({"ev": "pcMsg", "pc": fp, "m": {"t": "fileFailed", "id": m["id"], "purpose": m["purpose"]}}));
                                }
                            }
                            _ if m.is_object() => emit(json!({"ev": "pcMsg", "pc": fp, "m": m})),
                            _ => {}
                        }
                    }
                    Some(Ok(Message::Binary(data))) => {
                        let Some(inc) = incoming.as_mut() else { continue };
                        if let Some(done) = write_chunk(inc, &data, &fp) {
                            let inc = incoming.take().unwrap();
                            if done {
                                emit(json!({"ev": "pcMsg", "pc": fp, "m": {"t": "file", "id": inc.id, "purpose": inc.purpose,
                                    "name": inc.name, "path": inc.path.to_string_lossy()}}));
                            } else {
                                let _ = std::fs::remove_file(&inc.path);
                                emit(json!({"ev": "pcMsg", "pc": fp, "m": {"t": "fileFailed", "id": inc.id, "purpose": inc.purpose}}));
                            }
                        }
                    }
                    Some(Ok(Message::Close(_))) | Some(Err(_)) | None => break,
                    Some(Ok(_)) => {}
                }
            }
        }
    }

    writer.abort();
    if let Some(inc) = incoming.take() {
        let _ = std::fs::remove_file(&inc.path);
        emit(json!({"ev": "pcMsg", "pc": fp, "m": {"t": "fileFailed", "id": inc.id, "purpose": inc.purpose}}));
    }
    let mut s = state.lock().unwrap();
    if s.pc_conns.get(&fp).is_some_and(|c| c.serial == serial) {
        s.pc_conns.remove(&fp);
        s.pc_files.remove(&fp);
        emit(json!({"ev": "pcDisconnected", "pc": fp}));
    }
    s.pc_wake.notify_waiters();
}

/// What the other PC says about itself on connect: its name and where it can be reached.
fn hello_from(state: &State, fp: &str, m: &Value) {
    let mut s = state.lock().unwrap();
    let Some(p) = s.pcs.iter_mut().find(|p| p.fp == fp) else { return };
    let name: String = m["name"].as_str().unwrap_or("").chars().take(64).collect();
    let mut hosts = p.hosts.first().cloned().into_iter().collect::<Vec<_>>();
    hosts.extend(strings(&m["hosts"], 8).into_iter().filter(|h| Some(h) != p.hosts.first()));
    let port = m["port"].as_u64().and_then(|v| u16::try_from(v).ok()).unwrap_or(p.port);
    let wake: Vec<Value> = m["wake"].as_array().map(|a| a.iter().take(8).cloned().collect()).unwrap_or_else(|| p.wake.clone());
    if (name.is_empty() || name == p.name) && hosts == p.hosts && port == p.port && wake == p.wake {
        return;
    }
    p.wake = wake;
    if !name.is_empty() {
        p.name = name;
    }
    p.hosts = hosts;
    p.port = port;
    let pcs = s.pcs.clone();
    save(&s.dir, &pcs);
    emit(peers_event(&pcs));
}

/// Sends one file on [lane]: a `file` header, then binary frames, each awaited into the
/// bounded queue so only a few chunks are ever in memory.
async fn send_file(lane: &FileLane, path: &Path, id: &str, name: &str, purpose: &str) -> bool {
    use tokio::io::AsyncReadExt;
    let _turn = lane.lock.lock().await;
    let Ok(mut file) = tokio::fs::File::open(path).await else { return false };
    let size = match file.metadata().await {
        Ok(m) if m.is_file() && m.len() > 0 && m.len() <= FILE_MAX => m.len(),
        _ => return false,
    };
    let header = json!({"t": "file", "id": id, "purpose": purpose, "name": name, "size": size});
    if lane.tx.send(Message::text(header.to_string())).await.is_err() {
        return false;
    }
    let mut sent = 0u64;
    let mut buf = vec![0u8; FILE_CHUNK];
    while sent < size {
        let want = FILE_CHUNK.min((size - sent) as usize);
        let n = match file.read(&mut buf[..want]).await {
            Ok(0) | Err(_) => return false,
            Ok(n) => n,
        };
        if lane.tx.send(Message::Binary(buf[..n].to_vec().into())).await.is_err() {
            return false;
        }
        sent += n as u64;
    }
    true
}

fn start_file(dir: &Path, fp: &str, m: &Value) -> Option<Incoming> {
    let id = safe_id(m["id"].as_str().unwrap_or(""))?;
    let purpose = match m["purpose"].as_str().unwrap_or("") {
        p @ ("shelf" | "put") => p.to_string(),
        _ => return None,
    };
    let size = m["size"].as_u64().filter(|s| *s > 0 && *s <= FILE_MAX)?;
    let name = safe_name(m["name"].as_str().unwrap_or(""));
    let folder = pc_dir(dir, fp).join(&purpose).join(&id);
    std::fs::create_dir_all(&folder).ok()?;
    let path = folder.join(&name);
    let file = std::fs::OpenOptions::new().create(true).write(true).truncate(true).mode(0o600).open(&path).ok()?;
    Some(Incoming { id, purpose, name, size, written: 0, reported: 0, path, file })
}

/// Writes a chunk: None while more is due, Some(true) once whole, Some(false) on a failure.
fn write_chunk(inc: &mut Incoming, data: &[u8], fp: &str) -> Option<bool> {
    use std::io::Write as _;
    inc.written += data.len() as u64;
    if inc.written > inc.size || inc.file.write_all(data).is_err() {
        return Some(false);
    }
    // Progress for the shelf's ring, every 5 %.
    let pct = inc.written * 100 / inc.size;
    if pct >= inc.reported + 5 && inc.written < inc.size {
        inc.reported = pct;
        emit(json!({"ev": "pcFileProgress", "pc": fp, "id": inc.id, "p": pct as f64 / 100.0}));
    }
    (inc.written == inc.size).then_some(true)
}

/// The other PC's shelf: its thumbnails onto disk here (`thumbPath`), the old ones pruned.
fn shelf_thumbs(dir: &Path, fp: &str, mut m: Value) -> Value {
    let folder = pc_dir(dir, fp).join("thumbs");
    let _ = std::fs::create_dir_all(&folder);
    let mut keep = std::collections::HashSet::new();
    if let Some(items) = m["items"].as_array_mut() {
        for it in items.iter_mut() {
            let thumb = it["thumb"].as_str().unwrap_or("").to_string();
            it["thumb"] = Value::Null;
            let Some(id) = safe_id(it["id"].as_str().unwrap_or("")) else { continue };
            if thumb.is_empty() || thumb.len() as u64 > THUMB_MAX * 2 {
                continue;
            }
            let Ok(bytes) = base64::engine::general_purpose::STANDARD.decode(thumb.trim()) else { continue };
            let path = folder.join(format!("{id}.jpg"));
            if write_private(&path, &bytes).is_ok() {
                keep.insert(format!("{id}.jpg"));
                it["thumbPath"] = json!(path.to_string_lossy());
            }
        }
    }
    if let Ok(list) = std::fs::read_dir(&folder) {
        for e in list.flatten() {
            if !keep.contains(&e.file_name().to_string_lossy().into_owned()) {
                let _ = std::fs::remove_file(e.path());
            }
        }
    }
    m
}

async fn discover(port: u16, mine: &str) -> Vec<Value> {
    let Ok(sock) = tokio::net::UdpSocket::bind(("0.0.0.0", 0)).await else { return Vec::new() };
    let _ = sock.set_broadcast(true);
    let _ = sock.send_to(b"iilink?", ("255.255.255.255", port)).await;
    let mut found: Vec<Value> = Vec::new();
    let mut buf = [0u8; 512];
    let end = Instant::now() + Duration::from_millis(1500);
    while let Ok(Ok((n, from))) = tokio::time::timeout_at(end, sock.recv_from(&mut buf)).await {
        let Ok(v) = serde_json::from_slice::<Value>(&buf[..n]) else { continue };
        let fp = v["fp"].as_str().unwrap_or("");
        if !valid_fp(fp) || fp == mine || found.iter().any(|f| f["fp"] == fp) {
            continue;
        }
        found.push(json!({"fp": fp, "name": v["name"], "port": v["port"], "addr": from.ip().to_string()}));
    }
    found
}

/// Wake-on-LAN: the magic packet (6 × FF, then the MAC 16 times) to each adapter, at its
/// subnet broadcast and 255.255.255.255, on ports 9 and 7. True if any went out.
pub fn wake(targets: &[Value]) -> bool {
    let Ok(sock) = std::net::UdpSocket::bind(("0.0.0.0", 0)) else { return false };
    let _ = sock.set_broadcast(true);
    let mut sent = false;
    for t in targets.iter().take(8) {
        let mac: Vec<u8> = t["mac"].as_str().unwrap_or("").split([':', '-']).filter_map(|h| u8::from_str_radix(h, 16).ok()).collect();
        if mac.len() != 6 {
            continue;
        }
        let mut packet = vec![0xFFu8; 6];
        for _ in 0..16 {
            packet.extend_from_slice(&mac);
        }
        let mut addrs = vec!["255.255.255.255".to_string()];
        if let Some(b) = t["broadcast"].as_str().filter(|b| b.parse::<std::net::Ipv4Addr>().is_ok()) {
            addrs.insert(0, b.to_string());
        }
        for addr in &addrs {
            for port in [9u16, 7] {
                if sock.send_to(&packet, (addr.as_str(), port)).is_ok() {
                    sent = true;
                }
            }
        }
    }
    sent
}

fn save_clip(dir: &Path, data: &str) -> Option<String> {
    if data.len() > CLIP_MAX / 3 * 4 + 4 {
        return None;
    }
    let bytes = base64::engine::general_purpose::STANDARD.decode(data.trim()).ok()?;
    let folder = dir.join("pcclip");
    std::fs::create_dir_all(&folder).ok()?;
    let path = folder.join(format!("{}.png", random_hex(8)));
    write_private(&path, &bytes).ok()?;
    Some(path.to_string_lossy().into_owned())
}

/// Shared by the helper: a no-op notifier the dial loops sleep on.
pub fn notifier() -> Arc<Notify> {
    Arc::new(Notify::new())
}
