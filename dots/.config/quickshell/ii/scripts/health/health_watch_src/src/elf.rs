//! Just enough ELF to tell whether a program still links: the libraries it
//! needs (DT_NEEDED), where it looks for them (RPATH/RUNPATH), and the symbol
//! versions it asks of them (.gnu.version_r), which is where Qt's private API
//! shows up as `Qt_6_PRIVATE_API`. 64-bit little-endian only, headers and those
//! three tables only: nothing else of the file is read.

use std::fs::File;
use std::os::unix::fs::FileExt;
use std::path::Path;

#[derive(Default, Debug, PartialEq)]
pub struct Info {
    pub needed: Vec<String>,
    pub runpath: Vec<String>,
    /// Symbol version names required from other objects, e.g. "GLIBC_2.34".
    pub versions: Vec<String>,
    /// e_machine: 62 for x86-64, 183 for aarch64.
    pub machine: u16,
    /// The program interpreter (PT_INTERP) of an executable; None for a library.
    pub interp: Option<String>,
}

const PT_INTERP: u32 = 3;

const SHT_DYNAMIC: u32 = 6;
const SHT_GNU_VERNEED: u32 = 0x6fff_fffe;
const DT_NEEDED: u64 = 1;
const DT_RPATH: u64 = 15;
const DT_RUNPATH: u64 = 29;
/// No table read here is legitimately larger.
const MAX_TABLE: u64 = 8 << 20;

struct Section {
    kind: u32,
    offset: u64,
    size: u64,
    link: u32,
    info: u32,
}

fn u16_at(b: &[u8], o: usize) -> u16 {
    u16::from_le_bytes([b[o], b[o + 1]])
}
fn u32_at(b: &[u8], o: usize) -> u32 {
    u32::from_le_bytes(b[o..o + 4].try_into().unwrap())
}
fn u64_at(b: &[u8], o: usize) -> u64 {
    u64::from_le_bytes(b[o..o + 8].try_into().unwrap())
}

fn read(f: &File, offset: u64, size: u64) -> Option<Vec<u8>> {
    if size > MAX_TABLE {
        return None;
    }
    let mut buf = vec![0u8; size as usize];
    f.read_exact_at(&mut buf, offset).ok()?;
    Some(buf)
}

fn cstr(table: &[u8], at: usize) -> Option<String> {
    let rest = table.get(at..)?;
    let end = rest.iter().position(|&c| c == 0)?;
    Some(String::from_utf8_lossy(&rest[..end]).into_owned())
}

/// Whether `path` starts like an ELF file; cheap enough to ask of every file.
pub fn is_elf(path: &Path) -> bool {
    let Ok(f) = File::open(path) else { return false };
    let mut magic = [0u8; 4];
    f.read_exact_at(&mut magic, 0).is_ok() && magic == *b"\x7fELF"
}

pub fn read_info(path: &Path) -> Option<Info> {
    let f = File::open(path).ok()?;
    let head = read(&f, 0, 64)?;
    // Magic, 64-bit, little-endian.
    if head[0..4] != *b"\x7fELF" || head[4] != 2 || head[5] != 1 {
        return None;
    }
    let shoff = u64_at(&head, 0x28);
    let shentsize = u16_at(&head, 0x3a) as u64;
    let shnum = u16_at(&head, 0x3c) as u64;
    if shoff == 0 || shentsize < 64 || shnum == 0 || shnum > 4096 {
        return None;
    }
    let table = read(&f, shoff, shentsize * shnum)?;
    let sections: Vec<Section> = (0..shnum as usize)
        .map(|i| {
            let o = i * shentsize as usize;
            Section {
                kind: u32_at(&table, o + 4),
                offset: u64_at(&table, o + 0x18),
                size: u64_at(&table, o + 0x20),
                link: u32_at(&table, o + 0x28),
                info: u32_at(&table, o + 0x2c),
            }
        })
        .collect();
    let strings = |s: &Section| sections.get(s.link as usize).and_then(|t| read(&f, t.offset, t.size));

    let mut info = Info { machine: u16_at(&head, 0x12), ..Default::default() };
    let phoff = u64_at(&head, 0x20);
    let phentsize = u16_at(&head, 0x36) as u64;
    let phnum = u16_at(&head, 0x38) as u64;
    if phoff != 0 && phentsize >= 56 && phnum > 0 && phnum <= 256 {
        if let Some(ph) = read(&f, phoff, phentsize * phnum) {
            for i in 0..phnum as usize {
                let o = i * phentsize as usize;
                if u32_at(&ph, o) == PT_INTERP {
                    let size = u64_at(&ph, o + 0x20).min(4096);
                    if let Some(raw) = read(&f, u64_at(&ph, o + 8), size) {
                        info.interp = cstr(&raw, 0);
                    }
                    break;
                }
            }
        }
    }
    if let Some(dynamic) = sections.iter().find(|s| s.kind == SHT_DYNAMIC) {
        if let (Some(entries), Some(strtab)) = (read(&f, dynamic.offset, dynamic.size), strings(dynamic)) {
            for e in entries.chunks_exact(16) {
                let tag = u64_at(e, 0);
                let val = u64_at(e, 8) as usize;
                match tag {
                    0 => break,
                    DT_NEEDED => info.needed.extend(cstr(&strtab, val)),
                    DT_RPATH | DT_RUNPATH => {
                        if let Some(p) = cstr(&strtab, val) {
                            info.runpath.extend(p.split(':').filter(|s| !s.is_empty()).map(str::to_string));
                        }
                    }
                    _ => {}
                }
            }
        }
    }
    if let Some(verneed) = sections.iter().find(|s| s.kind == SHT_GNU_VERNEED) {
        if let (Some(data), Some(strtab)) = (read(&f, verneed.offset, verneed.size), strings(verneed)) {
            // Verneed records, each with a chain of Vernaux; sh_info counts the records.
            let mut at = 0usize;
            for _ in 0..verneed.info.min(1024) {
                if at + 16 > data.len() {
                    break;
                }
                let cnt = u16_at(&data, at + 2);
                let mut aux = at + u32_at(&data, at + 8) as usize;
                for _ in 0..cnt.min(1024) {
                    if aux + 16 > data.len() {
                        break;
                    }
                    if let Some(name) = cstr(&strtab, u32_at(&data, aux + 8) as usize) {
                        if !info.versions.contains(&name) {
                            info.versions.push(name);
                        }
                    }
                    let next = u32_at(&data, aux + 12) as usize;
                    if next == 0 {
                        break;
                    }
                    aux += next;
                }
                let next = u32_at(&data, at + 12) as usize;
                if next == 0 {
                    break;
                }
                at += next;
            }
        }
    }
    Some(info)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_a_system_binary() {
        // Every system this builds on has a dynamically linked `ls`.
        let p = Path::new("/usr/bin/ls");
        if !p.exists() {
            return;
        }
        assert!(is_elf(p));
        let i = read_info(p).expect("ls parses");
        assert!(i.needed.iter().any(|n| n.starts_with("libc.so")), "{:?}", i.needed);
        assert!(i.versions.iter().any(|v| v.starts_with("GLIBC_")), "{:?}", i.versions);
        assert!(i.interp.as_deref().is_some_and(|p| p.contains("ld-linux")), "{:?}", i.interp);
        assert!(i.machine > 0);
        // A library has no interpreter (libc does: it can be run; zlib cannot).
        let libz = Path::new("/usr/lib/libz.so.1");
        if libz.exists() {
            assert_eq!(read_info(libz).and_then(|i| i.interp), None);
        }
    }

    #[test]
    fn rejects_non_elf() {
        let p = std::env::temp_dir().join(format!("health_elf_{}", std::process::id()));
        std::fs::write(&p, b"#!/bin/sh\necho hi\n").unwrap();
        assert!(!is_elf(&p));
        assert!(read_info(&p).is_none());
        let _ = std::fs::remove_file(&p);
    }
}
