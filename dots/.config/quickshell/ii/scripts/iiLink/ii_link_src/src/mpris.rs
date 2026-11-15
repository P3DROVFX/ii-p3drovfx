//! The phone's media players as MPRIS players on the session bus.
//!
//! The shell's media widgets, the island, the lock screen and the media keys all speak
//! MPRIS, as does KDE Connect's own bridge. So each app playing on the phone (`media`
//! messages: Spotify, YouTube…) becomes `org.mpris.MediaPlayer2.iitools_<app>` here, and
//! its buttons go straight back to the phone as `mediaCmd`: the shell is not involved.
//! Players live as long as their phone's connection; nothing runs without one.
//!
//! The phone side follows Sefirah's PlaybackFeature (GPL-3.0); see the app.

use std::collections::HashMap;
use std::path::PathBuf;
use std::time::Instant;

use base64::Engine;
use serde_json::{json, Value};
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::Message;
use zbus::object_server::SignalEmitter;
use zbus::zvariant::{ObjectPath, OwnedValue, Value as ZValue};
use zbus::{connection, interface, Connection};

const PATH: &str = "/org/mpris/MediaPlayer2";

pub enum Event {
    /// A `media` message from a phone, with that phone's name and its socket.
    Update { dev: String, phone: String, tx: mpsc::UnboundedSender<Message>, m: Value },
    Gone { dev: String, source: String },
    /// The phone disconnected, or the shell switched this off.
    DevGone { dev: String },
    Disable,
}

#[derive(Clone, Default)]
struct Track {
    app: String,
    title: String,
    artist: String,
    album: String,
    art: String,
    /// The track's web page, when the phone's app gives one.
    url: String,
    playing: bool,
    /// ms, at `at`.
    position: i64,
    at: Option<Instant>,
    length: i64,
    rate: f64,
    volume: f64,
    can_play: bool,
    can_pause: bool,
    can_next: bool,
    can_prev: bool,
    can_seek: bool,
    serial: u64,
}

impl Track {
    fn position_ms(&self) -> i64 {
        let elapsed = match (self.playing, self.at) {
            (true, Some(at)) => (at.elapsed().as_millis() as f64 * self.rate.max(0.0)) as i64,
            _ => 0,
        };
        let p = self.position + elapsed;
        if self.length > 0 { p.min(self.length) } else { p }
    }
}

struct Root {
    identity: String,
}

#[interface(name = "org.mpris.MediaPlayer2")]
impl Root {
    fn raise(&self) {}
    fn quit(&self) {}
    #[zbus(property)]
    fn can_quit(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn can_raise(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn has_track_list(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn identity(&self) -> String {
        self.identity.clone()
    }
    #[zbus(property)]
    fn desktop_entry(&self) -> String {
        String::new()
    }
    #[zbus(property)]
    fn supported_uri_schemes(&self) -> Vec<String> {
        Vec::new()
    }
    #[zbus(property)]
    fn supported_mime_types(&self) -> Vec<String> {
        Vec::new()
    }
}

struct Player {
    track: Track,
    source: String,
    tx: mpsc::UnboundedSender<Message>,
}

impl Player {
    fn send(&self, action: &str, value: Option<Value>) {
        let mut m = json!({"t": "mediaCmd", "source": self.source, "a": action});
        if let Some(v) = value {
            m["value"] = v;
        }
        let _ = self.tx.send(Message::Text(m.to_string().into()));
    }
}

fn owned(v: ZValue<'_>) -> OwnedValue {
    v.try_to_owned().unwrap_or_else(|_| OwnedValue::from(0u8))
}

#[interface(name = "org.mpris.MediaPlayer2.Player")]
impl Player {
    fn play(&self) {
        self.send("play", None);
    }
    fn pause(&self) {
        self.send("pause", None);
    }
    fn play_pause(&self) {
        self.send(if self.track.playing { "pause" } else { "play" }, None);
    }
    fn stop(&self) {
        self.send("pause", None);
    }
    fn next(&self) {
        self.send("next", None);
    }
    fn previous(&self) {
        self.send("previous", None);
    }
    /// MPRIS gives microseconds, relative.
    fn seek(&self, offset: i64) {
        self.send("seek", Some(json!((self.track.position_ms() + offset / 1000).max(0))));
    }
    fn set_position(&self, _track: ObjectPath<'_>, position: i64) {
        self.send("seek", Some(json!((position / 1000).max(0))));
    }
    fn open_uri(&self, _uri: String) {}

    #[zbus(signal)]
    async fn seeked(emitter: &SignalEmitter<'_>, position: i64) -> zbus::Result<()>;

    #[zbus(property)]
    fn playback_status(&self) -> String {
        if self.track.playing { "Playing" } else { "Paused" }.to_string()
    }
    #[zbus(property)]
    fn rate(&self) -> f64 {
        1.0
    }
    #[zbus(property)]
    fn minimum_rate(&self) -> f64 {
        1.0
    }
    #[zbus(property)]
    fn maximum_rate(&self) -> f64 {
        1.0
    }
    #[zbus(property)]
    fn metadata(&self) -> HashMap<String, OwnedValue> {
        let t = &self.track;
        let mut m = HashMap::new();
        let id = format!("/dev/ii/tools/track/{}", t.serial);
        if let Ok(path) = ObjectPath::try_from(id) {
            m.insert("mpris:trackid".into(), owned(ZValue::from(path)));
        }
        if t.length > 0 {
            m.insert("mpris:length".into(), owned(ZValue::from(t.length * 1000)));
        }
        if !t.art.is_empty() {
            m.insert("mpris:artUrl".into(), owned(ZValue::from(format!("file://{}", t.art))));
        }
        m.insert("xesam:title".into(), owned(ZValue::from(t.title.clone())));
        if !t.artist.is_empty() {
            m.insert("xesam:artist".into(), owned(ZValue::from(vec![t.artist.clone()])));
        }
        if !t.album.is_empty() {
            m.insert("xesam:album".into(), owned(ZValue::from(t.album.clone())));
        }
        if t.url.starts_with("http") {
            m.insert("xesam:url".into(), owned(ZValue::from(t.url.clone())));
        }
        m
    }
    #[zbus(property)]
    fn volume(&self) -> f64 {
        self.track.volume
    }
    #[zbus(property)]
    fn set_volume(&mut self, volume: f64) {
        self.track.volume = volume.clamp(0.0, 1.0);
        self.send("volume", Some(json!((self.track.volume * 100.0).round() as i64)));
    }
    #[zbus(property(emits_changed_signal = "false"))]
    fn position(&self) -> i64 {
        self.track.position_ms() * 1000
    }
    #[zbus(property)]
    fn can_go_next(&self) -> bool {
        self.track.can_next
    }
    #[zbus(property)]
    fn can_go_previous(&self) -> bool {
        self.track.can_prev
    }
    #[zbus(property)]
    fn can_play(&self) -> bool {
        self.track.can_play
    }
    #[zbus(property)]
    fn can_pause(&self) -> bool {
        self.track.can_pause
    }
    #[zbus(property)]
    fn can_seek(&self) -> bool {
        self.track.can_seek
    }
    #[zbus(property)]
    fn can_control(&self) -> bool {
        true
    }
}

/// One bus name per phone app: an app name like "com.spotify.music" made a D-Bus element.
fn bus_name(source: &str) -> String {
    let clean: String = source.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '_' }).collect();
    format!("org.mpris.MediaPlayer2.iitools_{clean}")
}

struct Live {
    conn: Connection,
    dev: String,
}

/// Owns the players; fed by the sessions (`Event`), so the D-Bus work never blocks a socket.
pub async fn run(mut rx: mpsc::UnboundedReceiver<Event>, art_dir: PathBuf) {
    let mut players: HashMap<String, Live> = HashMap::new();
    let mut serial: u64 = 0;
    while let Some(ev) = rx.recv().await {
        match ev {
            Event::Update { dev, phone, tx, m } => {
                let source = m["source"].as_str().unwrap_or("").to_string();
                if source.is_empty() {
                    continue;
                }
                let key = format!("{dev}/{source}");
                let mut track = Track {
                    app: m["app"].as_str().unwrap_or(&source).to_string(),
                    title: m["title"].as_str().unwrap_or("").to_string(),
                    artist: m["artist"].as_str().unwrap_or("").to_string(),
                    album: m["album"].as_str().unwrap_or("").to_string(),
                    url: m["url"].as_str().unwrap_or("").to_string(),
                    playing: m["playing"].as_bool().unwrap_or(false),
                    position: m["position"].as_i64().unwrap_or(0),
                    at: Some(Instant::now()),
                    length: m["length"].as_i64().unwrap_or(0),
                    rate: m["rate"].as_f64().unwrap_or(1.0),
                    volume: m["volume"].as_f64().map(|v| v / 100.0).unwrap_or(1.0),
                    can_play: m["canPlay"].as_bool().unwrap_or(true),
                    can_pause: m["canPause"].as_bool().unwrap_or(true),
                    can_next: m["canNext"].as_bool().unwrap_or(true),
                    can_prev: m["canPrevious"].as_bool().unwrap_or(true),
                    can_seek: m["canSeek"].as_bool().unwrap_or(false),
                    ..Default::default()
                };
                // A cover comes only with a new track; it is kept as a file for artUrl.
                if let Some(b64) = m["art"].as_str() {
                    if let Ok(bytes) = base64::engine::general_purpose::STANDARD.decode(b64) {
                        let name = ring::digest::digest(&ring::digest::SHA256, &bytes);
                        let file = art_dir.join(format!("{}.jpg", hex::encode(&name.as_ref()[..8])));
                        if std::fs::create_dir_all(&art_dir).is_ok() && std::fs::write(&file, &bytes).is_ok() {
                            track.art = file.to_string_lossy().into_owned();
                        }
                    }
                }
                if let Some(live) = players.get(&key) {
                    let Ok(iface) = live.conn.object_server().interface::<_, Player>(PATH).await else { continue };
                    let mut p = iface.get_mut().await;
                    let new_track = p.track.title != track.title || p.track.artist != track.artist || p.track.album != track.album || p.track.url != track.url;
                    if track.art.is_empty() && !new_track {
                        track.art = p.track.art.clone();
                    }
                    track.serial = if new_track {
                        serial += 1;
                        serial
                    } else {
                        p.track.serial
                    };
                    let jumped = (track.position - p.track.position_ms()).abs() > 2_000;
                    p.track = track;
                    p.tx = tx;
                    let emitter = iface.signal_emitter();
                    let _ = p.playback_status_changed(emitter).await;
                    let _ = p.metadata_changed(emitter).await;
                    let _ = p.can_go_next_changed(emitter).await;
                    let _ = p.can_go_previous_changed(emitter).await;
                    let _ = p.can_seek_changed(emitter).await;
                    let _ = p.volume_changed(emitter).await;
                    if jumped {
                        let _ = Player::seeked(emitter, p.track.position_ms() * 1000).await;
                    }
                    continue;
                }
                serial += 1;
                track.serial = serial;
                let identity = if phone.is_empty() { track.app.clone() } else { format!("{} · {phone}", track.app) };
                let built = connection::Builder::session()
                    .and_then(|b| b.name(bus_name(&source)))
                    .and_then(|b| b.serve_at(PATH, Root { identity }))
                    .and_then(|b| b.serve_at(PATH, Player { track, source: source.clone(), tx }));
                match built {
                    Ok(b) => match b.build().await {
                        Ok(conn) => {
                            players.insert(key, Live { conn, dev });
                        }
                        Err(e) => crate::emit(json!({"ev": "error", "code": "mpris", "msg": format!("mpris {source}: {e}")})),
                    },
                    Err(e) => crate::emit(json!({"ev": "error", "code": "mpris", "msg": format!("mpris {source}: {e}")})),
                }
            }
            Event::Gone { dev, source } => {
                players.remove(&format!("{dev}/{source}"));
            }
            Event::DevGone { dev } => players.retain(|_, live| live.dev != dev),
            Event::Disable => players.clear(),
        }
    }
}
