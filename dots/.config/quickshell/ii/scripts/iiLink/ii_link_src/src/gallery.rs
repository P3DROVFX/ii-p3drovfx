//! Phone gallery cache, filename validation, and thumbnail event batching.
//!
//! Gallery files (`galleryThumb` and `galleryFull`) bypass the shell's `<state>/incoming/`
//! staging and land straight in `$XDG_CACHE_HOME/quickshell/phone_gallery/<dev>/`,
//! answered `ok` by the helper itself so thumbnail bursts do not flood stdin/stdout.

use std::fs;
use std::path::PathBuf;
use std::time::Duration;

use serde_json::{json, Value};
use tokio::time::Instant;

const THUMB_COALESCE: Duration = Duration::from_millis(100);

/// Device ids from `random_hex(6)` are 12 hex characters; validate before building a path.
pub fn valid_dev_id(id: &str) -> bool {
    id.len() == 12 && id.bytes().all(|b| b.is_ascii_hexdigit())
}

pub fn cache_root() -> Option<PathBuf> {
    if let Ok(xdg) = std::env::var("XDG_CACHE_HOME") {
        if !xdg.is_empty() {
            return Some(PathBuf::from(xdg).join("quickshell/phone_gallery"));
        }
    }
    std::env::var_os("HOME")
        .filter(|h| !h.is_empty())
        .map(|h| PathBuf::from(h).join(".cache/quickshell/phone_gallery"))
}

pub fn dest_dir(dev: &str, thumb: bool) -> Option<PathBuf> {
    if !valid_dev_id(dev) {
        return None;
    }
    let sub = if thumb { "thumbs" } else { "full" };
    cache_root().map(|r| r.join(dev).join(sub))
}

/// Validates `<item_id>.<ext>` against the wire contract and returns the numeric item id.
/// - thumb: `^[0-9]{1,19}\.jpg$`
/// - full:  `^[0-9]{1,19}\.(jpg|jpeg|png|webp|gif)$`
pub fn parse_name(thumb: bool, name: &str) -> Option<u64> {
    let (stem, ext) = name.split_once('.')?;
    if stem.is_empty() || stem.len() > 19 || !stem.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let ext_ok = if thumb {
        ext == "jpg"
    } else {
        matches!(ext, "jpg" | "jpeg" | "png" | "webp" | "gif")
    };
    if !ext_ok {
        return None;
    }
    stem.parse::<u64>().ok()
}

/// Drops `<cache>/quickshell/phone_gallery/<id>/` when a phone is unpaired.
pub fn remove_cache(id: &str) {
    if !valid_dev_id(id) {
        return;
    }
    if let Some(root) = cache_root() {
        let _ = fs::remove_dir_all(root.join(id));
    }
}

/// Per-connection buffer that coalesces completed thumbnail ids for at most 100 ms.
pub struct ThumbBatch {
    ids: Vec<u64>,
    deadline: Option<Instant>,
}

impl ThumbBatch {
    pub fn new() -> Self {
        Self { ids: Vec::new(), deadline: None }
    }

    pub fn push(&mut self, id: u64) {
        if self.deadline.is_none() {
            self.deadline = Some(Instant::now() + THUMB_COALESCE);
        }
        if !self.ids.contains(&id) {
            self.ids.push(id);
        }
    }

    /// Only `Some` while items are buffered, so an idle connection sets no timer.
    pub fn deadline(&self) -> Option<Instant> {
        self.deadline
    }

    pub fn flush(&mut self, dev: &str) -> Option<Value> {
        self.deadline = None;
        if self.ids.is_empty() {
            return None;
        }
        let ids = std::mem::take(&mut self.ids);
        Some(json!({"ev": "galleryThumbs", "dev": dev, "ids": ids}))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_thumb_names() {
        assert_eq!(parse_name(true, "0.jpg"), Some(0));
        assert_eq!(parse_name(true, "1234567890123456789.jpg"), Some(1234567890123456789));
        assert_eq!(parse_name(true, "12345678901234567890.jpg"), None);
        assert_eq!(parse_name(true, ".jpg"), None);
        assert_eq!(parse_name(true, "12.jpeg"), None);
        assert_eq!(parse_name(true, "12.png"), None);
        assert_eq!(parse_name(true, "12.JPG"), None);
        assert_eq!(parse_name(true, "12.jpg.png"), None);
        assert_eq!(parse_name(true, "../12.jpg"), None);
        assert_eq!(parse_name(true, "12.jpg\n"), None);
        assert_eq!(parse_name(true, "-1.jpg"), None);
    }

    #[test]
    fn validates_full_names() {
        assert_eq!(parse_name(false, "1.jpg"), Some(1));
        assert_eq!(parse_name(false, "2.jpeg"), Some(2));
        assert_eq!(parse_name(false, "3.png"), Some(3));
        assert_eq!(parse_name(false, "4.webp"), Some(4));
        assert_eq!(parse_name(false, "5.gif"), Some(5));
        assert_eq!(parse_name(false, "6.heic"), None);
        assert_eq!(parse_name(false, "6.JPG"), None);
        assert_eq!(parse_name(false, "6.part"), None);
        assert_eq!(parse_name(false, "abc.png"), None);
        assert_eq!(parse_name(false, "12345678901234567890.png"), None);
    }

    #[test]
    fn validates_dev_id() {
        assert!(valid_dev_id("0123456789ab"));
        assert!(valid_dev_id("ABCDEF012345"));
        assert!(!valid_dev_id(""));
        assert!(!valid_dev_id("0123456789a"));
        assert!(!valid_dev_id("0123456789abc"));
        assert!(!valid_dev_id("../123456789"));
        assert!(!valid_dev_id("0123456789ag"));
    }

    #[test]
    fn thumb_batch_coalesces_and_clears_deadline() {
        let mut batch = ThumbBatch::new();
        assert!(batch.deadline().is_none());
        assert!(batch.flush("0123456789ab").is_none());

        batch.push(10);
        let first_deadline = batch.deadline().expect("deadline armed");
        batch.push(20);
        batch.push(10);
        assert_eq!(batch.deadline(), Some(first_deadline));

        let ev = batch.flush("0123456789ab").expect("event emitted");
        assert_eq!(ev, json!({"ev": "galleryThumbs", "dev": "0123456789ab", "ids": [10, 20]}));
        assert!(batch.deadline().is_none());
        assert!(batch.flush("0123456789ab").is_none());
    }
}
