//! Noise fingerprints: `<source>|<template>`.
//!
//! The same complaint from the same program must land on the same fingerprint
//! on every boot, whatever pid, address, device number or session it carried.
//! Everything that changes between occurrences is replaced by `#`; everything
//! that names the thing (a driver, a unit, a word) is kept, so a template stays
//! readable in the UI.

use serde_json::Value;

use crate::proto::{jnum, jtext};

/// Where a journal entry came from, stable across boots.
///
/// Scope and session units (`session-3.scope`, `app-…-1234.scope`) and the user
/// manager itself are named per boot, so for those the program's identifier is
/// used instead. Instance names (`foo@1-4097-1166032.service`) lose their
/// instance.
pub fn source(entry: &Value) -> String {
    let get = |k: &str| jtext(entry.get(k));
    if get("_TRANSPORT") == "kernel" {
        return "kernel".into();
    }
    let user_unit = get("_SYSTEMD_USER_UNIT");
    if !user_unit.is_empty() && !is_volatile_unit(&user_unit) {
        let uid = jnum(entry.get("_UID")).unwrap_or(-1);
        return format!("user@{uid}/{}", strip_instance(&user_unit));
    }
    let unit = get("_SYSTEMD_UNIT");
    if !unit.is_empty() && !is_volatile_unit(&unit) && !unit.starts_with("user@") {
        return strip_instance(&unit);
    }
    let ident = get("SYSLOG_IDENTIFIER");
    if !ident.is_empty() {
        return ident;
    }
    let comm = get("_COMM");
    if !comm.is_empty() {
        return comm;
    }
    "unknown".into()
}

fn is_volatile_unit(unit: &str) -> bool {
    unit.ends_with(".scope") || unit.starts_with("session-") || unit.starts_with("app-")
}

/// `systemd-coredump@1-4097-1166032_1180050-0.service` → `systemd-coredump@#.service`.
pub fn strip_instance(unit: &str) -> String {
    match (unit.find('@'), unit.rfind('.')) {
        (Some(at), Some(dot)) if dot > at + 1 => format!("{}@#{}", &unit[..at], &unit[dot..]),
        _ => unit.to_string(),
    }
}

pub fn fingerprint(entry: &Value, home: &str) -> (String, String, String) {
    let src = source(entry);
    let msg_id = jtext(entry.get("MESSAGE_ID"));
    let message = jtext(entry.get("MESSAGE"));
    let tpl = if msg_id.is_empty() { template(&message, home) } else { msg_id };
    (format!("{src}|{tpl}"), src, tpl)
}

/// The message with everything occurrence-specific replaced by `#`.
pub fn template(message: &str, home: &str) -> String {
    let first_line = message.lines().next().unwrap_or("");
    let s = replace_home_paths(first_line, home);
    let s = replace_structured(&s);
    let s = replace_hex_words(&s);
    let s = replace_digits(&s);
    let collapsed = s.split_whitespace().collect::<Vec<_>>().join(" ");
    collapsed.chars().take(160).collect()
}

fn is_path_end(c: char) -> bool {
    c.is_whitespace() || matches!(c, ':' | '"' | '\'' | ',' | ')' | '(' | ';' | '[' | ']' | '>' | '<')
}

fn replace_home_paths(s: &str, home: &str) -> String {
    if home.len() < 2 || home == "/" {
        return s.to_string();
    }
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(pos) = rest.find(home) {
        out.push_str(&rest[..pos]);
        let after = &rest[pos + home.len()..];
        if after.starts_with('/') || after.is_empty() || after.starts_with(is_path_end) {
            out.push_str("~/#path");
            let end = after.find(is_path_end).unwrap_or(after.len());
            rest = &after[end..];
        } else {
            out.push_str(home);
            rest = after;
        }
    }
    out.push_str(rest);
    out
}

fn is_hex(c: u8) -> bool {
    c.is_ascii_hexdigit()
}

/// PCI addresses, MACs, UUIDs and IPv4 addresses, each as one placeholder.
fn replace_structured(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = String::with_capacity(s.len());
    let mut i = 0;
    let boundary_before = |i: usize| i == 0 || !(b[i - 1].is_ascii_alphanumeric());
    while i < b.len() {
        if boundary_before(i) {
            if let Some(n) = match_pci(&b[i..]) {
                out.push_str("#:#:#.#");
                i += n;
                continue;
            }
            if let Some(n) = match_mac(&b[i..]) {
                out.push('#');
                i += n;
                continue;
            }
            if let Some(n) = match_uuid(&b[i..]) {
                out.push('#');
                i += n;
                continue;
            }
            if let Some(n) = match_ipv4(&b[i..]) {
                out.push('#');
                i += n;
                continue;
            }
        }
        let ch = s[i..].chars().next().unwrap();
        out.push(ch);
        i += ch.len_utf8();
    }
    out
}

fn hex_run(b: &[u8], n: usize) -> bool {
    b.len() >= n && b[..n].iter().all(|c| is_hex(*c))
}

fn ends_word(b: &[u8], n: usize) -> bool {
    b.len() == n || !b[n].is_ascii_alphanumeric()
}

/// `0000:00:05.0`
fn match_pci(b: &[u8]) -> Option<usize> {
    if hex_run(b, 4) && b.get(4) == Some(&b':') && hex_run(&b[5..], 2) && b.get(7) == Some(&b':')
        && hex_run(&b[8..], 2) && b.get(10) == Some(&b'.') && b.get(11).is_some_and(|c| is_hex(*c))
        && ends_word(b, 12)
    {
        return Some(12);
    }
    None
}

/// `AA:BB:CC:DD:EE:FF`
fn match_mac(b: &[u8]) -> Option<usize> {
    if b.len() < 17 {
        return None;
    }
    for k in 0..6 {
        if !hex_run(&b[k * 3..], 2) {
            return None;
        }
        if k < 5 && b[k * 3 + 2] != b':' {
            return None;
        }
    }
    if ends_word(b, 17) { Some(17) } else { None }
}

/// `8-4-4-4-12` hex.
fn match_uuid(b: &[u8]) -> Option<usize> {
    let groups = [8, 4, 4, 4, 12];
    let mut i = 0;
    for (k, g) in groups.iter().enumerate() {
        if !hex_run(&b[i.min(b.len())..], *g) {
            return None;
        }
        i += g;
        if k < 4 {
            if b.get(i) != Some(&b'-') {
                return None;
            }
            i += 1;
        }
    }
    if ends_word(b, i) { Some(i) } else { None }
}

/// `192.168.1.10`, with an optional `:port`.
fn match_ipv4(b: &[u8]) -> Option<usize> {
    let mut i = 0;
    for k in 0..4 {
        let start = i;
        while i < b.len() && b[i].is_ascii_digit() && i - start < 3 {
            i += 1;
        }
        if i == start {
            return None;
        }
        if k < 3 {
            if b.get(i) != Some(&b'.') {
                return None;
            }
            i += 1;
        }
    }
    if b.get(i) == Some(&b':') && b.get(i + 1).is_some_and(|c| c.is_ascii_digit()) {
        i += 1;
        while i < b.len() && b[i].is_ascii_digit() {
            i += 1;
        }
    }
    if ends_word(b, i) && !(b.get(i) == Some(&b'.') && b.get(i + 1).is_some_and(|c| c.is_ascii_digit())) {
        Some(i)
    } else {
        None
    }
}

/// `0x…` runs, and standalone hex words of six or more characters with a digit.
fn replace_hex_words(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = String::with_capacity(s.len());
    let mut i = 0;
    while i < b.len() {
        let at_boundary = i == 0 || !b[i - 1].is_ascii_alphanumeric();
        if at_boundary && b[i] == b'0' && matches!(b.get(i + 1), Some(b'x') | Some(b'X'))
            && b.get(i + 2).is_some_and(|c| is_hex(*c))
        {
            let mut j = i + 2;
            while j < b.len() && is_hex(b[j]) {
                j += 1;
            }
            out.push('#');
            i = j;
            continue;
        }
        if at_boundary && is_hex(b[i]) {
            let mut j = i;
            while j < b.len() && is_hex(b[j]) {
                j += 1;
            }
            let word = &b[i..j];
            if word.len() >= 6 && word.iter().any(|c| c.is_ascii_digit()) && ends_word(b, j) {
                out.push('#');
                i = j;
                continue;
            }
        }
        let ch = s[i..].chars().next().unwrap();
        out.push(ch);
        i += ch.len_utf8();
    }
    out
}

/// Digit runs that are not part of a name: `ipu7` and `x86` keep their digits,
/// `[1452]`, `-5` and `:00` lose them.
fn replace_digits(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = String::with_capacity(s.len());
    let mut i = 0;
    while i < b.len() {
        if b[i].is_ascii_digit() {
            let mut j = i;
            while j < b.len() && b[j].is_ascii_digit() {
                j += 1;
            }
            if i > 0 && b[i - 1].is_ascii_alphabetic() {
                out.push_str(&s[i..j]);
            } else {
                out.push('#');
            }
            i = j;
            continue;
        }
        let ch = s[i..].chars().next().unwrap();
        out.push(ch);
        i += ch.len_utf8();
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn acpi_fan_line() {
        let t = template("acpi-fan PNP0C0B:00: Error retrieving current fan status: -5", "/home/scrimas");
        assert_eq!(t, "acpi-fan PNP0C0B:#: Error retrieving current fan status: -#");
        let t2 = template("acpi-fan PNP0C0B:03: Error retrieving current fan status: -22", "/home/scrimas");
        assert_eq!(t, t2);
    }

    #[test]
    fn ipu7_line() {
        let t = template("intel-ipu7 0000:00:05.0: Failed to get runtime PM", "/home/scrimas");
        assert_eq!(t, "intel-ipu7 #:#:#.#: Failed to get runtime PM");
    }

    #[test]
    fn zeron_exec_line() {
        let t = template(
            "zeron.service: Failed at step EXEC spawning /home/scrimas/.zeron/app/current/zeron: No such file or directory",
            "/home/scrimas",
        );
        assert_eq!(t, "zeron.service: Failed at step EXEC spawning ~/#path: No such file or directory");
    }

    #[test]
    fn mac_uuid_ip_hex() {
        let t = template(
            "connect to 3C:E0:FB:12:9C:AC failed id 5b924082-07d8-4f04-8359-3ad27220a8aa from 192.168.1.20:443 at 0x7ffd1234 ref deadbeef42",
            "/home/x",
        );
        assert_eq!(t, "connect to # failed id # from # at # ref #");
    }

    #[test]
    fn pids_and_names() {
        let t = template("spa.alsa: hw:0,0p: snd_pcm_drop: No such device [1452] x86_64", "/h");
        assert_eq!(t, "spa.alsa: hw:#,#p: snd_pcm_drop: No such device [#] x86_#");
    }

    #[test]
    fn sources() {
        let k = json!({"_TRANSPORT": "kernel", "MESSAGE": "x"});
        assert_eq!(source(&k), "kernel");
        let scope = json!({"_SYSTEMD_UNIT": "session-3.scope", "SYSLOG_IDENTIFIER": "qs", "MESSAGE": "x"});
        assert_eq!(source(&scope), "qs");
        let inst = json!({"_SYSTEMD_UNIT": "systemd-coredump@1-4097-1166032_1180050-0.service"});
        assert_eq!(source(&inst), "systemd-coredump@#.service");
        let user = json!({"_SYSTEMD_UNIT": "user@1000.service", "_SYSTEMD_USER_UNIT": "pipewire.service", "_UID": "1000"});
        assert_eq!(source(&user), "user@1000/pipewire.service");
        let mgr = json!({"_SYSTEMD_UNIT": "user@1000.service", "SYSLOG_IDENTIFIER": "systemd"});
        assert_eq!(source(&mgr), "systemd");
    }
}
