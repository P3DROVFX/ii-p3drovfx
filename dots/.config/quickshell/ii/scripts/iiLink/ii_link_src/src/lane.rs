//! The file lane (PROTOCOL.md, "Files", *Fast lane*): a file's bytes on a TLS socket of
//! their own, beside the link's WebSocket, when the phone's *Faster* transfers are on.
//!
//! The WebSocket carries a file as 256 KiB binary messages queued behind everything else,
//! and the phone masks each byte of what it sends (RFC 6455) in Java: that, not the
//! network, set the speed. Here the bytes go as they are, in 1 MiB blocks, read from disk
//! by a thread of their own while the last block is still on the wire, so a transfer
//! runs at what the Wi-Fi gives. TCP keeps them in order and resends what is lost.
//!
//! The lane shares the link's port (the firewall already lets it in): it opens with
//! [`MAGIC`] in the clear, which no TLS ClientHello starts with, then TLS under the same
//! pinned certificate, then the 32-byte token the link's socket handed out for this one
//! file. A token is good once, for [`CLAIM_TIMEOUT`]. A file from the phone ends with one
//! byte back from us once it is on disk (0 landed, 1 failed): the phone closes only then.
//! Closing right after its last write, with our TLS session ticket still unread, made its
//! kernel answer with a reset, and a reset throws away what we had not read yet.

use std::fs::{self, File};
use std::io::Read;
use std::path::PathBuf;
use std::time::Duration;

use ring::rand::{SecureRandom, SystemRandom};
use serde_json::{json, Value};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::mpsc;
use tokio::time::timeout;
use tokio_rustls::TlsAcceptor;
use tokio_tungstenite::tungstenite::Message;

use crate::files;
use crate::{emit, State};

pub const MAGIC: &[u8; 4] = b"IIL1";
const TOKEN: usize = 32;
/// Large videos are what the lane is for; the phone checks its own free space.
pub const MAX_SIZE: u64 = 16 << 30;
/// Under this a second TLS handshake costs more than the lane saves.
pub const MIN_SIZE: u64 = 1 << 20;
const CLAIM_TIMEOUT: Duration = Duration::from_secs(15);
const HANDSHAKE: Duration = Duration::from_secs(10);
/// No byte for this long: the phone walked out of the Wi-Fi.
const STALL: Duration = Duration::from_secs(20);
const BLOCK: usize = 1 << 20;
/// Blocks read ahead of the socket: the disk never waits for the network or the other way.
const AHEAD: usize = 4;

/// What a token stands for until the phone claims it.
pub enum Job {
    /// Phone → PC: its bytes go into this file.
    Up { dev: String, inc: files::Incoming, tx: mpsc::UnboundedSender<Message> },
    /// PC → phone: this file goes out.
    Down { dev: String, id: u64, path: PathBuf, size: u64, delete: bool, purpose: Value, name: String },
}

impl Job {
    fn dev(&self) -> &str {
        match self {
            Job::Up { dev, .. } | Job::Down { dev, .. } => dev,
        }
    }
}

/// Holds [job] under a fresh token (hex, for the link's socket) until the phone claims it.
pub fn offer(state: &State, job: Job) -> String {
    let mut token = [0u8; TOKEN];
    let _ = SystemRandom::new().fill(&mut token);
    state.lock().unwrap().lanes.insert(token, job);
    let state = state.clone();
    tokio::spawn(async move {
        tokio::time::sleep(CLAIM_TIMEOUT).await;
        let job = state.lock().unwrap().lanes.remove(&token);
        if let Some(job) = job {
            expire(job);
        }
    });
    hex::encode(token)
}

/// A token nobody claimed: the phone could not reach the lane and did not say so.
fn expire(job: Job) {
    match job {
        Job::Up { dev, inc, tx } => {
            inc.discard();
            if let Some(ev) = inc.aborted(&dev) {
                emit(ev);
            }
            let _ = tx.send(Message::text(json!({"t": "err", "id": inc.id, "code": "timeout"}).to_string()));
        }
        Job::Down { dev, id, .. } => emit(json!({"ev": "fileSendFailed", "dev": dev, "id": id})),
    }
}

/// The phone sends this file over the link's socket after all: its offer goes, quietly.
pub fn withdraw_up(state: &State, dev: &str, id: u64) {
    let mut s = state.lock().unwrap();
    let token = s.lanes.iter().find_map(|(t, j)| match j {
        Job::Up { dev: d, inc, .. } if d == dev && inc.id == id => Some(*t),
        _ => None,
    });
    if let Some(Job::Up { inc, .. }) = token.and_then(|t| s.lanes.remove(&t)) {
        inc.discard();
    }
}

/// The phone could not open a lane for a file of ours: what it was for, if still unclaimed.
pub fn take_down(state: &State, dev: &str, id: u64) -> Option<Job> {
    let mut s = state.lock().unwrap();
    let token = s.lanes.iter().find_map(|(t, j)| match j {
        Job::Down { dev: d, id: i, .. } if d == dev && *i == id => Some(*t),
        _ => None,
    })?;
    s.lanes.remove(&token)
}

/// A phone that went away: its uploads will not come.
pub fn drop_dev(state: &State, dev: &str) {
    let mut s = state.lock().unwrap();
    let tokens: Vec<[u8; TOKEN]> = s.lanes.iter().filter(|(_, j)| j.dev() == dev).map(|(t, _)| *t).collect();
    for t in tokens {
        if let Some(job) = s.lanes.remove(&t) {
            expire(job);
        }
    }
}

/// A connection that opened with [`MAGIC`] (the caller peeked its first byte).
pub async fn serve(stream: TcpStream, acceptor: TlsAcceptor, state: State) {
    serve_with(stream, acceptor, move |token| state.lock().unwrap().lanes.remove(token)).await;
}

async fn serve_with(mut stream: TcpStream, acceptor: TlsAcceptor, claim: impl FnOnce(&[u8; TOKEN]) -> Option<Job>) {
    let mut magic = [0u8; 4];
    if !matches!(timeout(HANDSHAKE, stream.read_exact(&mut magic)).await, Ok(Ok(_))) || &magic != MAGIC {
        return;
    }
    // Bulk data: Nagle's coalescing is what we want here.
    let _ = stream.set_nodelay(false);
    let Ok(Ok(mut tls)) = timeout(HANDSHAKE, acceptor.accept(stream)).await else { return };
    let mut token = [0u8; TOKEN];
    if !matches!(timeout(HANDSHAKE, tls.read_exact(&mut token)).await, Ok(Ok(_))) {
        return;
    }
    let Some(job) = claim(&token) else { return };
    match job {
        Job::Up { dev, inc, tx } => receive(tls, dev, inc, tx).await,
        Job::Down { dev, id, path, size, delete, .. } => send(tls, dev, id, path, size, delete).await,
    }
}

async fn receive<S: AsyncRead + AsyncWrite + Unpin>(mut tls: S, dev: String, mut inc: files::Incoming, tx: mpsc::UnboundedSender<Message>) {
    let mut buf = vec![0u8; BLOCK];
    loop {
        let n = match timeout(STALL, tls.read(&mut buf)).await {
            Ok(Ok(n)) if n > 0 => n,
            _ => {
                inc.discard();
                if let Some(ev) = inc.aborted(&dev) {
                    emit(ev);
                }
                let _ = tx.send(Message::text(json!({"t": "err", "id": inc.id, "code": "write"}).to_string()));
                return;
            }
        };
        match inc.write(&buf[..n], &dev) {
            files::Step::More => {}
            files::Step::Progress(ev) => emit(ev),
            files::Step::Done(done) => {
                ack(&mut tls, 0).await;
                match done {
                    files::Done::Shell(ev) => emit(ev),
                    files::Done::GalleryFull { file_id, event } => {
                        let _ = tx.send(Message::text(json!({"t": "ok", "id": file_id}).to_string()));
                        emit(event);
                    }
                    // Thumbnails are never offered a lane (MIN_SIZE); answered all the same.
                    files::Done::GalleryThumb { file_id, item_id } => {
                        let _ = tx.send(Message::text(json!({"t": "ok", "id": file_id}).to_string()));
                        emit(json!({"ev": "galleryThumbs", "dev": dev, "ids": [item_id]}));
                    }
                }
                return;
            }
            files::Step::Failed(reply) => {
                ack(&mut tls, 1).await;
                if let Some(ev) = inc.aborted(&dev) {
                    emit(ev);
                }
                let _ = tx.send(Message::text(reply.to_string()));
                return;
            }
        }
    }
}

/// The phone's go-ahead to close (its outcome comes over the link, as `ok`/`err`).
async fn ack<S: AsyncWrite + Unpin>(tls: &mut S, code: u8) {
    let _ = timeout(HANDSHAKE, async {
        tls.write_all(&[code]).await?;
        tls.shutdown().await
    })
    .await;
}

async fn send<S: AsyncWrite + Unpin>(mut tls: S, dev: String, id: u64, path: PathBuf, size: u64, delete: bool) {
    let (blocks, mut rx) = mpsc::channel::<Vec<u8>>(AHEAD);
    let read_path = path.clone();
    tokio::task::spawn_blocking(move || {
        let Ok(mut file) = File::open(&read_path) else { return };
        loop {
            let mut block = vec![0u8; BLOCK];
            let mut filled = 0;
            while filled < BLOCK {
                match file.read(&mut block[filled..]) {
                    Ok(0) => break,
                    Ok(n) => filled += n,
                    Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
                    Err(_) => return,
                }
            }
            if filled == 0 {
                return;
            }
            block.truncate(filled);
            if blocks.blocking_send(block).is_err() {
                return;
            }
        }
    });
    let mut sent = 0u64;
    while let Some(block) = rx.recv().await {
        if !matches!(timeout(STALL, tls.write_all(&block)).await, Ok(Ok(()))) {
            break;
        }
        sent += block.len() as u64;
    }
    let ok = sent == size && matches!(timeout(STALL, tls.shutdown()).await, Ok(Ok(())));
    if ok && delete {
        let _ = fs::remove_file(&path);
    }
    emit(json!({"ev": if ok { "fileSent" } else { "fileSendFailed" }, "dev": dev, "id": id}));
}

/// The `file` header for a phone, with the lane's token when it goes over one.
pub fn header(id: u64, purpose: &Value, name: &str, size: u64, token: Option<&str>) -> Value {
    let mut h = json!({"t": "file", "id": id, "purpose": purpose, "name": name, "size": size});
    if let Some(token) = token {
        h["lane"] = json!(token);
    }
    h
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
    use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer, ServerName, UnixTime};
    use rustls::{DigitallySignedStruct, SignatureScheme};
    use tokio::net::TcpListener;

    /// The phone pins the fingerprint; here any certificate will do.
    #[derive(Debug)]
    struct AnyCert;
    impl ServerCertVerifier for AnyCert {
        fn verify_server_cert(&self, _: &CertificateDer, _: &[CertificateDer], _: &ServerName, _: &[u8], _: UnixTime) -> Result<ServerCertVerified, rustls::Error> {
            Ok(ServerCertVerified::assertion())
        }
        fn verify_tls12_signature(&self, _: &[u8], _: &CertificateDer, _: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, rustls::Error> {
            Ok(HandshakeSignatureValid::assertion())
        }
        fn verify_tls13_signature(&self, _: &[u8], _: &CertificateDer, _: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, rustls::Error> {
            Ok(HandshakeSignatureValid::assertion())
        }
        fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
            rustls::crypto::ring::default_provider().signature_verification_algorithms.supported_schemes()
        }
    }

    fn acceptor() -> TlsAcceptor {
        let _ = rustls::crypto::ring::default_provider().install_default();
        let cert = rcgen::generate_simple_self_signed(vec!["ii".into()]).unwrap();
        let key = PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(cert.signing_key.serialize_der()));
        let cfg = rustls::ServerConfig::builder().with_no_client_auth().with_single_cert(vec![cert.cert.der().clone()], key).unwrap();
        TlsAcceptor::from(Arc::new(cfg))
    }

    /// What the phone does: the magic, TLS, the token.
    async fn dial(port: u16, token: [u8; TOKEN]) -> tokio_rustls::client::TlsStream<TcpStream> {
        let mut tcp = TcpStream::connect(("127.0.0.1", port)).await.unwrap();
        tcp.write_all(MAGIC).await.unwrap();
        let cfg = rustls::ClientConfig::builder().dangerous().with_custom_certificate_verifier(Arc::new(AnyCert)).with_no_client_auth();
        let mut tls = tokio_rustls::TlsConnector::from(Arc::new(cfg)).connect(ServerName::try_from("ii").unwrap(), tcp).await.unwrap();
        tls.write_all(&token).await.unwrap();
        tls
    }

    fn data(len: usize) -> Vec<u8> {
        (0..len).map(|i| (i * 31 + i / 7) as u8).collect()
    }

    #[tokio::test(flavor = "current_thread")]
    async fn lanes_carry_files_both_ways_and_refuse_wrong_tokens() {
        let base = std::env::temp_dir().join(format!("ii_lane_test_{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        fs::create_dir_all(&base).unwrap();
        let acceptor = acceptor();
        let listener = TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let token = [7u8; TOKEN];

        // Phone → PC: 3.5 blocks land whole in incoming/ and the shell hears `file`.
        let size = BLOCK * 7 / 2;
        let payload = data(size);
        let inc = files::start(&base, "dev", &json!({"id": 5, "name": "big.mp4", "size": size, "purpose": "share"}), MAX_SIZE).unwrap();
        let (tx, _rx) = mpsc::unbounded_channel();
        let server = {
            let acceptor = acceptor.clone();
            let mut job = Some(Job::Up { dev: "dev".into(), inc, tx });
            tokio::spawn(async move {
                let (stream, _) = listener.accept().await.unwrap();
                serve_with(stream, acceptor.clone(), |t| if *t == token { job.take() } else { None }).await;
                listener
            })
        };
        let mut phone = dial(port, token).await;
        phone.write_all(&payload).await.unwrap();
        phone.flush().await.unwrap();
        let mut landed = [9u8; 1];
        phone.read_exact(&mut landed).await.unwrap();
        assert_eq!(landed, [0]);
        let listener = server.await.unwrap();
        assert_eq!(fs::read(base.join("incoming/dev-5-big.mp4")).unwrap(), payload);

        // PC → phone: the file comes back byte for byte, and is deleted when asked.
        let out = base.join("out.bin");
        let payload = data(BLOCK * 2 + 123);
        fs::write(&out, &payload).unwrap();
        let job = Job::Down { dev: "dev".into(), id: 9, path: out.clone(), size: payload.len() as u64, delete: true, purpose: json!("share"), name: "out.bin".into() };
        let server = {
            let acceptor = acceptor.clone();
            let mut job = Some(job);
            tokio::spawn(async move {
                let (stream, _) = listener.accept().await.unwrap();
                serve_with(stream, acceptor, |t| if *t == token { job.take() } else { None }).await;
                listener
            })
        };
        let mut phone = dial(port, token).await;
        let mut got = Vec::new();
        phone.read_to_end(&mut got).await.unwrap();
        let listener = server.await.unwrap();
        assert_eq!(got, payload);
        assert!(!out.exists());

        // A wrong token gets nothing and the connection closes.
        let server = {
            let acceptor = acceptor.clone();
            tokio::spawn(async move {
                let (stream, _) = listener.accept().await.unwrap();
                serve_with(stream, acceptor, |t| if *t == token { panic!("claimed") } else { None }).await;
            })
        };
        let mut phone = dial(port, [1u8; TOKEN]).await;
        let mut got = Vec::new();
        let _ = phone.read_to_end(&mut got).await;
        server.await.unwrap();
        assert!(got.is_empty());

        let _ = fs::remove_dir_all(&base);
    }
}
