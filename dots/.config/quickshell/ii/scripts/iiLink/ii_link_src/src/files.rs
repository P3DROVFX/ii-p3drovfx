//! Files from the phone: a `file` header, then the bytes as binary frames.
//!
//! The helper only lands them on disk (`<state>/incoming/`, 0600) and tells the shell,
//! which decides what a file is for (a wallpaper…) and moves or deletes it. One file at
//! a time per phone; a partial file never outlives its connection.

use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use serde_json::{json, Value};

use crate::gallery;

/// Large enough for any photo or screenshot, small enough that a stray upload
/// cannot fill the disk. A file on its own lane may be larger ([`crate::lane::MAX_SIZE`]).
pub const MAX_SIZE: u64 = 64 << 20;

enum Kind {
    Shell,
    GalleryThumb(u64),
    GalleryFull(u64),
}

pub struct Incoming {
    pub id: u64,
    kind: Kind,
    part_path: PathBuf,
    done_path: PathBuf,
    file: File,
    size: u64,
    remaining: u64,
    name: String,
    meta: Value,
    /// Progress is told at most every 1 % or 150 ms, whichever comes later.
    last_told: (u64, Instant),
}

const PROGRESS_EVERY: Duration = Duration::from_millis(150);

/// What a completed transfer turns into for the connection loop.
pub enum Done {
    /// Handed off to the shell as a `file` event.
    Shell(Value),
    /// Gallery thumbnail: reply `ok` directly and coalesce `item_id` into `galleryThumbs`.
    GalleryThumb { file_id: u64, item_id: u64 },
    /// Gallery full image: reply `ok` directly and emit `galleryFile`.
    GalleryFull { file_id: u64, event: Value },
}

/// What a header or a chunk led to.
pub enum Step {
    /// Waiting for more bytes.
    More,
    /// Waiting for more bytes; the progress event for the shell.
    Progress(Value),
    /// The file is complete.
    Done(Done),
    /// Refused or broken: the `err` reply for the phone.
    Failed(Value),
}

/// Keeps a plain file name: no path, no hidden file, a sane length.
fn clean_name(raw: &str) -> String {
    let base = raw.rsplit(['/', '\\']).next().unwrap_or("");
    let cleaned: String = base
        .chars()
        .filter(|c| !c.is_control())
        .map(|c| if c == ':' { '_' } else { c })
        .collect::<String>()
        .trim_start_matches('.')
        .chars()
        .take(120)
        .collect();
    if cleaned.is_empty() { "file".to_string() } else { cleaned }
}

pub fn start(dir: &Path, dev: &str, header: &Value, max: u64) -> Result<Incoming, Value> {
    let id = header["id"].as_u64().unwrap_or(0);
    let fail = |code: &str| json!({"t": "err", "id": id, "code": code});
    let size = header["size"].as_u64().unwrap_or(0);
    if size == 0 {
        return Err(fail("bad_arg"));
    }
    if size > max {
        return Err(fail("too_large"));
    }
    let purpose = header["purpose"].as_str().unwrap_or("");
    let (kind, part_path, done_path, name) = match purpose {
        "galleryThumb" | "galleryFull" => {
            let thumb = purpose == "galleryThumb";
            let raw_name = header["name"].as_str().ok_or_else(|| fail("bad_arg"))?;
            let item_id = gallery::parse_name(thumb, raw_name).ok_or_else(|| fail("bad_arg"))?;
            let dest_dir = gallery::dest_dir(dev, thumb).ok_or_else(|| fail("write"))?;
            fs::DirBuilder::new().recursive(true).mode(0o700).create(&dest_dir).map_err(|_| fail("write"))?;
            let part_path = dest_dir.join(format!("{raw_name}.part"));
            let done_path = dest_dir.join(raw_name);
            let kind = if thumb { Kind::GalleryThumb(item_id) } else { Kind::GalleryFull(item_id) };
            (kind, part_path, done_path, raw_name.to_string())
        }
        _ => {
            let incoming = dir.join("incoming");
            fs::DirBuilder::new().recursive(true).mode(0o700).create(&incoming).map_err(|_| fail("write"))?;
            let name = clean_name(header["name"].as_str().unwrap_or(""));
            let part_path = incoming.join(format!("{dev}-{id}.part"));
            let done_path = incoming.join(format!("{dev}-{id}-{name}"));
            (Kind::Shell, part_path, done_path, name)
        }
    };
    let file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&part_path)
        .map_err(|_| fail("write"))?;
    Ok(Incoming {
        id,
        kind,
        part_path,
        done_path,
        file,
        size,
        remaining: size,
        name,
        meta: json!({"purpose": header["purpose"], "target": header["target"]}),
        last_told: (0, Instant::now()),
    })
}

impl Incoming {
    /// The `fileStart` event: what is coming, before its first byte (`None` for gallery files).
    pub fn started(&self, dev: &str) -> Option<Value> {
        match self.kind {
            Kind::Shell => Some(json!({"ev": "fileStart", "dev": dev, "id": self.id, "name": self.name, "size": self.size,
                "purpose": self.meta["purpose"], "target": self.meta["target"]})),
            Kind::GalleryThumb(_) | Kind::GalleryFull(_) => None,
        }
    }

    /// The abort event for a transfer dropped before its end (`None` for gallery thumbnails).
    pub fn aborted(&self, dev: &str) -> Option<Value> {
        match self.kind {
            Kind::Shell => Some(json!({"ev": "fileAbort", "dev": dev, "id": self.id})),
            Kind::GalleryThumb(_) => None,
            Kind::GalleryFull(item_id) => Some(json!({"ev": "galleryAbort", "dev": dev, "id": item_id})),
        }
    }

    pub fn write(&mut self, data: &[u8], dev: &str) -> Step {
        let len = data.len() as u64;
        if len > self.remaining || self.file.write_all(data).is_err() {
            self.discard();
            return Step::Failed(json!({"t": "err", "id": self.id, "code": "write"}));
        }
        self.remaining -= len;
        if self.remaining > 0 {
            if matches!(self.kind, Kind::GalleryThumb(_)) {
                return Step::More;
            }
            let received = self.size - self.remaining;
            let step = (self.size / 100).max(1);
            if received - self.last_told.0 >= step && self.last_told.1.elapsed() >= PROGRESS_EVERY {
                self.last_told = (received, Instant::now());
                let ev = match self.kind {
                    Kind::Shell => json!({"ev": "fileProgress", "dev": dev, "id": self.id, "received": received}),
                    Kind::GalleryFull(item_id) => {
                        json!({"ev": "galleryProgress", "dev": dev, "id": item_id, "received": received, "size": self.size})
                    }
                    Kind::GalleryThumb(_) => unreachable!(),
                };
                return Step::Progress(ev);
            }
            return Step::More;
        }
        if self.file.flush().is_err() || fs::rename(&self.part_path, &self.done_path).is_err() {
            self.discard();
            return Step::Failed(json!({"t": "err", "id": self.id, "code": "write"}));
        }
        let done = match self.kind {
            Kind::Shell => Done::Shell(json!({
                "ev": "file", "dev": dev, "id": self.id, "path": self.done_path.to_string_lossy(), "name": self.name,
                "purpose": self.meta["purpose"], "target": self.meta["target"],
            })),
            Kind::GalleryThumb(item_id) => Done::GalleryThumb { file_id: self.id, item_id },
            Kind::GalleryFull(item_id) => Done::GalleryFull {
                file_id: self.id,
                event: json!({"ev": "galleryFile", "dev": dev, "id": item_id, "path": self.done_path.to_string_lossy()}),
            },
        };
        Step::Done(done)
    }

    /// Drops a transfer that will not finish.
    pub fn discard(&self) {
        let _ = fs::remove_file(&self.part_path);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn gallery_transfers_and_cleanup() {
        let base = std::env::temp_dir().join(format!("ii_link_test_{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        let state_dir = base.join("state");
        let cache_dir = base.join("cache");
        fs::create_dir_all(&state_dir).unwrap();
        fs::create_dir_all(&cache_dir).unwrap();
        let prev_xdg = std::env::var_os("XDG_CACHE_HOME");
        std::env::set_var("XDG_CACHE_HOME", &cache_dir);

        let dev = "0123456789ab";

        // Bad gallery filenames are rejected with bad_arg.
        let bad_thumb = start(&state_dir, dev, &json!({"id": 1, "name": "42.png", "size": 4, "purpose": "galleryThumb"}), MAX_SIZE);
        assert_eq!(bad_thumb.err(), Some(json!({"t": "err", "id": 1, "code": "bad_arg"})));
        let bad_full = start(&state_dir, dev, &json!({"id": 2, "name": "../42.jpg", "size": 4, "purpose": "galleryFull"}), MAX_SIZE);
        assert_eq!(bad_full.err(), Some(json!({"t": "err", "id": 2, "code": "bad_arg"})));

        // Valid galleryThumb writes to cache/quickshell/phone_gallery/<dev>/thumbs/<name> via .part.
        let mut inc = start(&state_dir, dev, &json!({"id": 7, "name": "42.jpg", "size": 4, "purpose": "galleryThumb"}), MAX_SIZE).unwrap();
        assert!(inc.started(dev).is_none());
        assert!(inc.aborted(dev).is_none());
        assert!(matches!(inc.write(b"ab", dev), Step::More));
        assert!(cache_dir.join("quickshell/phone_gallery/0123456789ab/thumbs/42.jpg.part").exists());
        match inc.write(b"cd", dev) {
            Step::Done(Done::GalleryThumb { file_id, item_id }) => {
                assert_eq!(file_id, 7);
                assert_eq!(item_id, 42);
            }
            _ => panic!("expected GalleryThumb Done"),
        }
        let thumb_file = cache_dir.join("quickshell/phone_gallery/0123456789ab/thumbs/42.jpg");
        assert_eq!(fs::read(&thumb_file).unwrap(), b"abcd");
        assert_eq!(fs::metadata(&thumb_file).unwrap().permissions().mode() & 0o777, 0o600);
        assert_eq!(fs::metadata(thumb_file.parent().unwrap()).unwrap().permissions().mode() & 0o777, 0o700);

        // Valid galleryFull emits galleryFile on completion and galleryAbort when broken.
        let mut full = start(&state_dir, dev, &json!({"id": 8, "name": "99.webp", "size": 3, "purpose": "galleryFull"}), MAX_SIZE).unwrap();
        assert!(full.started(dev).is_none());
        assert_eq!(full.aborted(dev), Some(json!({"ev": "galleryAbort", "dev": dev, "id": 99})));
        match full.write(b"xyz", dev) {
            Step::Done(Done::GalleryFull { file_id, event }) => {
                assert_eq!(file_id, 8);
                let expected_path = cache_dir.join("quickshell/phone_gallery/0123456789ab/full/99.webp");
                assert_eq!(event, json!({"ev": "galleryFile", "dev": dev, "id": 99, "path": expected_path.to_string_lossy()}));
            }
            _ => panic!("expected GalleryFull Done"),
        }

        // Cache cleanup removes the device's gallery dir and ignores missing/invalid ids.
        gallery::remove_cache("../bad");
        assert!(cache_dir.join("quickshell/phone_gallery/0123456789ab").exists());
        gallery::remove_cache(dev);
        assert!(!cache_dir.join("quickshell/phone_gallery/0123456789ab").exists());
        gallery::remove_cache(dev);

        match prev_xdg {
            Some(v) => std::env::set_var("XDG_CACHE_HOME", v),
            None => std::env::remove_var("XDG_CACHE_HOME"),
        }
        let _ = fs::remove_dir_all(&base);
    }
}
