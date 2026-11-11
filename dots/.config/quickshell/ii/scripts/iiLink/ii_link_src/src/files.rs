//! Files from the phone: a `file` header, then the bytes as binary frames.
//!
//! The helper only lands them on disk (`<state>/incoming/`, 0600) and tells the shell,
//! which decides what a file is for (a wallpaper…) and moves or deletes it. One file at
//! a time per phone; a partial file never outlives its connection.

use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};

use serde_json::{json, Value};

/// Large enough for any photo or screenshot, small enough that a stray upload
/// cannot fill the disk.
pub const MAX_SIZE: u64 = 64 << 20;

pub struct Incoming {
    pub id: u64,
    path: PathBuf,
    file: File,
    remaining: u64,
    name: String,
    meta: Value,
}

/// What a header or a chunk led to.
pub enum Step {
    /// Waiting for more bytes.
    More,
    /// The file is complete: the `file` event for the shell.
    Done(Value),
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

pub fn start(dir: &Path, dev: &str, header: &Value) -> Result<Incoming, Value> {
    let id = header["id"].as_u64().unwrap_or(0);
    let fail = |code: &str| json!({"t": "err", "id": id, "code": code});
    let size = header["size"].as_u64().unwrap_or(0);
    if size == 0 {
        return Err(fail("bad_arg"));
    }
    if size > MAX_SIZE {
        return Err(fail("too_large"));
    }
    let incoming = dir.join("incoming");
    fs::DirBuilder::new().recursive(true).mode(0o700).create(&incoming).map_err(|_| fail("write"))?;
    let path = incoming.join(format!("{dev}-{id}.part"));
    let file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&path)
        .map_err(|_| fail("write"))?;
    Ok(Incoming {
        id,
        path,
        file,
        remaining: size,
        name: clean_name(header["name"].as_str().unwrap_or("")),
        meta: json!({"purpose": header["purpose"], "target": header["target"]}),
    })
}

impl Incoming {
    pub fn write(&mut self, data: &[u8], dev: &str) -> Step {
        let len = data.len() as u64;
        if len > self.remaining || self.file.write_all(data).is_err() {
            self.discard();
            return Step::Failed(json!({"t": "err", "id": self.id, "code": "write"}));
        }
        self.remaining -= len;
        if self.remaining > 0 {
            return Step::More;
        }
        let done = self.path.with_file_name(format!("{dev}-{}-{}", self.id, self.name));
        if self.file.flush().is_err() || fs::rename(&self.path, &done).is_err() {
            self.discard();
            return Step::Failed(json!({"t": "err", "id": self.id, "code": "write"}));
        }
        Step::Done(json!({
            "ev": "file", "dev": dev, "id": self.id, "path": done.to_string_lossy(), "name": self.name,
            "purpose": self.meta["purpose"], "target": self.meta["target"],
        }))
    }

    /// Drops a transfer that will not finish.
    pub fn discard(&self) {
        let _ = fs::remove_file(&self.path);
    }
}
