//! Packages built on this machine that no longer fit what is installed: the
//! `rebuild` finding. Arch only (pacman); repository packages are rebuilt by
//! the distribution, so only foreign ones (`pacman -Qm`, AUR or hand-built) are
//! looked at, plus Quickshell whatever its origin, since the shell depends on it.
//!
//! - Quickshell: `quickshell --private-check-compat` decides; it compares the Qt
//!   it was built against with the one installed, exactly.
//! - A library a program needs (DT_NEEDED) that no longer exists anywhere it is
//!   looked for: the system library dirs, ld.so.conf.d, its RPATH/RUNPATH, and
//!   the package's own library dirs.
//! - Qt's private API (`Qt_6_PRIVATE_API`) used by a package installed before
//!   the last qt6-base minor-version change: it breaks across minors.
//! - Python modules under a `python3.N` that is not the installed one.
//!
//! The ELF tables are read once per package version and install and cached;
//! whether their libraries still exist is checked again on every scan.

use crate::{elf, packages, proto};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

const LOCAL_DB: &str = "/var/lib/pacman/local";
/// Files read per package at most: a huge package is not worth a long scan.
const MAX_FILES: usize = 4000;

#[derive(Clone, Default)]
struct Object {
    path: PathBuf,
    needed: Vec<String>,
    runpath: Vec<String>,
    /// Where a check starts: a program this machine can run (its machine type,
    /// an interpreter that exists), or a library straight in /usr/lib that other
    /// packages link. Plugins, bundled prebuilds for other platforms and other
    /// libc's are only checked when a root reaches them.
    root: bool,
}

#[derive(Clone, Default)]
pub struct Facts {
    objects: Vec<Object>,
    /// Directories holding the package's own shared libraries.
    lib_dirs: Vec<PathBuf>,
    qt_private: bool,
    /// "python3.N" directories the package installs into.
    python: Vec<String>,
}

/// "name-version" → what its files need.
pub type Cache = HashMap<String, Facts>;

fn in_scope(path: &str) -> bool {
    (path.starts_with("usr/bin/") || path.starts_with("usr/lib/") || path.starts_with("usr/lib64/")
        || path.starts_with("usr/libexec/") || path.starts_with("opt/"))
        && !path.starts_with("usr/lib/debug/")
        && !path.ends_with('/')
}

fn inspect(key: &str) -> Facts {
    let mut facts = Facts::default();
    let files = std::fs::read_to_string(Path::new(LOCAL_DB).join(key).join("files")).unwrap_or_default();
    let mut python: HashSet<String> = HashSet::new();
    let mut lib_dirs: HashSet<PathBuf> = HashSet::new();
    let mut n = 0usize;
    for rel in files.lines().skip_while(|l| *l != "%FILES%").skip(1) {
        if rel.is_empty() || rel.starts_with('%') {
            break;
        }
        if let Some(rest) = rel.strip_prefix("usr/lib/python3.") {
            if let Some((minor, _)) = rest.split_once('/') {
                python.insert(format!("python3.{minor}"));
            }
            continue;
        }
        if !in_scope(rel) || n >= MAX_FILES {
            continue;
        }
        let path = Path::new("/").join(rel);
        // Symlinks name the same object as their target; the target is listed too.
        let Ok(meta) = std::fs::symlink_metadata(&path) else { continue };
        if !meta.file_type().is_file() || meta.len() < 64 {
            continue;
        }
        n += 1;
        if !elf::is_elf(&path) {
            continue;
        }
        let Some(info) = elf::read_info(&path) else { continue };
        let dir = path.parent().map(Path::to_path_buf).unwrap_or_default();
        if rel.contains(".so") {
            lib_dirs.insert(dir.clone());
        }
        facts.qt_private |= info.versions.iter().any(|v| v == "Qt_6_PRIVATE_API");
        let native = info.machine == host_machine();
        let root = native
            && match &info.interp {
                Some(interp) => Path::new(interp).exists(),
                None => dir == Path::new("/usr/lib") && rel.contains(".so"),
            };
        facts.objects.push(Object { path, needed: info.needed, runpath: info.runpath, root });
    }
    facts.python = python.into_iter().collect();
    facts.lib_dirs = lib_dirs.into_iter().collect();
    facts
}

/// Where the dynamic loader looks by default.
fn system_lib_dirs() -> Vec<PathBuf> {
    let mut dirs: Vec<PathBuf> = ["/usr/lib", "/usr/lib64", "/lib", "/lib64"].iter().map(PathBuf::from).collect();
    if let Ok(rd) = std::fs::read_dir("/etc/ld.so.conf.d") {
        for e in rd.flatten() {
            for line in std::fs::read_to_string(e.path()).unwrap_or_default().lines() {
                let l = line.trim();
                if l.starts_with('/') {
                    dirs.push(PathBuf::from(l));
                }
            }
        }
    }
    dirs
}

/// This machine's ELF type, from the helper's own binary.
fn host_machine() -> u16 {
    static HOST: std::sync::OnceLock<u16> = std::sync::OnceLock::new();
    *HOST.get_or_init(|| elf::read_info(Path::new("/proc/self/exe")).map(|i| i.machine).unwrap_or(62))
}

/// Libraries the package's roots need, directly or through the package's own
/// libraries, that the loader would not find.
fn missing_libs(facts: &Facts, system: &[PathBuf]) -> Vec<String> {
    let by_path: HashMap<&Path, &Object> = facts.objects.iter().map(|o| (o.path.as_path(), o)).collect();
    let mut queue: Vec<&Object> = facts.objects.iter().filter(|o| o.root).collect();
    let mut seen: HashSet<&Path> = queue.iter().map(|o| o.path.as_path()).collect();
    let mut missing: Vec<String> = Vec::new();
    while let Some(obj) = queue.pop() {
        let dir = obj.path.parent().map(Path::to_path_buf).unwrap_or_default();
        let search: Vec<PathBuf> = obj
            .runpath
            .iter()
            .map(|p| PathBuf::from(p.replace("${ORIGIN}", &dir.to_string_lossy()).replace("$ORIGIN", &dir.to_string_lossy())))
            .chain(facts.lib_dirs.iter().cloned())
            .chain(std::iter::once(dir.clone()))
            .chain(system.iter().cloned())
            .collect();
        for lib in &obj.needed {
            let found = if lib.contains('/') {
                Some(PathBuf::from(lib)).filter(|p| p.exists())
            } else {
                search.iter().map(|d| d.join(lib)).find(|p| p.exists())
            };
            match found {
                None => {
                    if !missing.contains(lib) {
                        missing.push(lib.clone());
                    }
                }
                // One of the package's own libraries: what it needs counts too.
                Some(p) => {
                    if let Some((key, next)) = by_path.get_key_value(p.as_path()) {
                        if seen.insert(*key) {
                            queue.push(next);
                        }
                    }
                }
            }
        }
    }
    missing
}

/// Whether the package ships ready-made programs, so a rebuild only downloads the
/// same files again: its PKGBUILD in the AUR helper's cache has no build(), or,
/// with no PKGBUILD at hand, its name ends in -bin.
fn prebuilt(name: &str, key: &str) -> bool {
    let desc = std::fs::read_to_string(Path::new(LOCAL_DB).join(key).join("desc")).unwrap_or_default();
    let base = desc.lines().skip_while(|l| *l != "%BASE%").nth(1).unwrap_or(name).to_string();
    let home = crate::proto::home_dir();
    for dir in [format!("{home}/.cache/yay/{base}"), format!("{home}/.cache/paru/clone/{base}")] {
        if let Ok(pkgbuild) = std::fs::read_to_string(Path::new(&dir).join("PKGBUILD")) {
            return !has_build_step(&pkgbuild);
        }
    }
    name.ends_with("-bin")
}

fn has_build_step(pkgbuild: &str) -> bool {
    pkgbuild.lines().any(|l| {
        let t = l.trim_start();
        t.starts_with("build()") || t.starts_with("build ()") || t.starts_with("function build")
    })
}

fn install_ms(key: &str) -> u64 {
    let desc = std::fs::read_to_string(Path::new(LOCAL_DB).join(key).join("desc")).unwrap_or_default();
    let mut lines = desc.lines();
    while let Some(l) = lines.next() {
        if l == "%INSTALLDATE%" {
            return lines.next().and_then(|v| v.trim().parse::<u64>().ok()).unwrap_or(0) * 1000;
        }
    }
    0
}

/// "6.12" of "6.12.0-2", "1:6.12.0-2" → "6.12".
fn minor(version: &str) -> String {
    let v = version.split_once(':').map(|(_, r)| r).unwrap_or(version);
    v.split('.').take(2).collect::<Vec<_>>().join(".")
}

/// When qt6-base last changed minor version, and to what: (ms, "6.12").
fn qt_minor_bump() -> (u64, String) {
    let (events, _) = packages::read_log(packages::Manager::Pacman, 0);
    events
        .iter()
        .filter(|e| e.name == "qt6-base" && !e.from.is_empty() && minor(&e.from) != minor(&e.to))
        .map(|e| (e.time, minor(&e.to)))
        .last()
        .unwrap_or((0, String::new()))
}

/// "python3.13", from the directory that holds the standard library.
fn current_python() -> Option<String> {
    let mut found: Vec<String> = std::fs::read_dir("/usr/lib")
        .ok()?
        .flatten()
        .filter_map(|e| {
            let name = e.file_name().to_string_lossy().into_owned();
            (name.starts_with("python3.") && e.path().join("os.py").exists()).then_some(name)
        })
        .collect();
    found.sort_by_key(|n| n.trim_start_matches("python3.").parse::<u32>().unwrap_or(0));
    found.pop()
}

/// Parses Quickshell's warning: ("6.11.2", "6.12.0").
pub fn qt_versions(text: &str) -> (String, String) {
    let grab = |marker: &str| {
        text.split_once(marker)
            .map(|(_, r)| r.chars().take_while(|c| c.is_ascii_digit() || *c == '.').collect::<String>())
            .unwrap_or_default()
            .trim_end_matches('.')
            .to_string()
    };
    (grab("built against Qt "), grab("updated to Qt "))
}

fn quickshell() -> Option<Value> {
    if !proto::which("quickshell") {
        return None;
    }
    let (ok, out) = proto::run_ok("quickshell", &["--private-check-compat"])?;
    if ok {
        return None;
    }
    let (built, installed) = qt_versions(&out);
    let (name, _) = packages::owner(packages::Manager::Pacman, "/usr/bin/quickshell").unwrap_or(("quickshell".into(), String::new()));
    let foreign = proto::run_ok("pacman", &["-Qqm", &name]).map(|(ok, _)| ok).unwrap_or(false);
    Some(json!({"name": name, "reason": "quickshell", "foreign": foreign, "built": built, "installed": installed}))
}

/// Every package that needs a rebuild, as `rebuild` finding entries:
/// { name, reason: "quickshell"|"lib"|"qt"|"python", foreign, … }.
pub fn scan(cache: &mut Cache) -> Vec<Value> {
    let mut out: Vec<Value> = quickshell().into_iter().collect();
    let foreign = proto::run("pacman", &["-Qm"]).unwrap_or_default();
    let system = system_lib_dirs();
    let python = current_python();
    let mut bump: Option<(u64, String)> = None;
    let mut present: HashSet<String> = HashSet::new();
    for line in foreign.lines() {
        let mut parts = line.split_whitespace();
        let (Some(name), Some(version)) = (parts.next(), parts.next()) else { continue };
        if name.ends_with("-debug") || out.iter().any(|v| v["name"] == name) {
            continue;
        }
        let key = format!("{name}-{version}");
        // A rebuild often keeps the version (a -git package with no new commit):
        // the install date tells the new files from the ones cached.
        let cache_key = format!("{key}@{}", install_ms(&key));
        present.insert(cache_key.clone());
        let facts = cache.entry(cache_key).or_insert_with(|| inspect(&key));
        let missing = missing_libs(facts, &system);
        if !missing.is_empty() {
            out.push(json!({"name": name, "reason": "lib", "foreign": true, "prebuilt": prebuilt(name, &key), "libs": missing}));
            continue;
        }
        if facts.qt_private {
            let (at, to) = bump.get_or_insert_with(qt_minor_bump).clone();
            if at > 0 && install_ms(&key) < at {
                out.push(json!({"name": name, "reason": "qt", "foreign": true, "prebuilt": prebuilt(name, &key), "qt": to}));
                continue;
            }
        }
        if let Some(py) = &python {
            let stale: Vec<&String> = facts.python.iter().filter(|p| *p != py).collect();
            if !stale.is_empty() {
                out.push(json!({"name": name, "reason": "python", "foreign": true, "prebuilt": prebuilt(name, &key), "python": stale, "current": py}));
            }
        }
    }
    cache.retain(|k, _| present.contains(k));
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions_from_the_warning() {
        let w = "\u{1b}[31mCOMPATIBILITY WARNING: Quickshell was built against Qt 6.11.2 but the system has updated to Qt 6.12.0 without rebuilding the package.";
        assert_eq!(qt_versions(w), ("6.11.2".to_string(), "6.12.0".to_string()));
        assert_eq!(qt_versions("nothing"), (String::new(), String::new()));
    }

    #[test]
    fn minor_versions() {
        assert_eq!(minor("6.12.0-2"), "6.12");
        assert_eq!(minor("1:6.12.0-2.1"), "6.12");
        assert_eq!(minor("6.11.2-1"), "6.11");
    }

    #[test]
    fn missing_library_found_and_not() {
        let obj = |path: &str, needed: &[&str], root: bool| Object {
            path: PathBuf::from(path),
            needed: needed.iter().map(|s| s.to_string()).collect(),
            runpath: vec![],
            root,
        };
        // A program needing libc (there) and a library that is gone.
        let facts = Facts { objects: vec![obj("/usr/bin/x", &["libc.so.6", "libdoesnotexist-ii.so.9"], true)], ..Default::default() };
        assert_eq!(missing_libs(&facts, &system_lib_dirs()), vec!["libdoesnotexist-ii.so.9".to_string()]);
        // A plugin nobody runs is not checked.
        let facts = Facts { objects: vec![obj("/usr/lib/x/plugin.so", &["libgone-ii.so.1"], false)], ..Default::default() };
        assert!(missing_libs(&facts, &system_lib_dirs()).is_empty());
        // But one a program links (here by absolute path) is.
        let tmp = std::env::temp_dir().join(format!("health_rebuild_{}", std::process::id()));
        std::fs::create_dir_all(&tmp).unwrap();
        let lib = tmp.join("libown-ii.so");
        std::fs::write(&lib, b"x").unwrap();
        let facts = Facts {
            objects: vec![
                obj("/usr/bin/y", &[lib.to_str().unwrap()], true),
                obj(lib.to_str().unwrap(), &["libgone-ii.so.1"], false),
            ],
            ..Default::default()
        };
        assert_eq!(missing_libs(&facts, &system_lib_dirs()), vec!["libgone-ii.so.1".to_string()]);
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn build_step_tells_prebuilt_from_source() {
        assert!(has_build_step("pkgname=x\nbuild() {\n  make\n}\npackage() {\n}\n"));
        assert!(has_build_step("build () {\n}"));
        assert!(!has_build_step("pkgname=x-bin\nsource=(x.deb)\npackage() {\n  bsdtar -xf data.tar.zst\n}\n"));
        // A name with no PKGBUILD in any cache falls back to the -bin convention.
        assert!(prebuilt("nonexistent-ii-test-bin", "nonexistent-ii-test-bin-1-1"));
        assert!(!prebuilt("nonexistent-ii-test", "nonexistent-ii-test-1-1"));
    }

    #[test]
    fn scope_of_files() {
        assert!(in_scope("usr/bin/foo"));
        assert!(in_scope("opt/app/lib/libx.so"));
        assert!(!in_scope("usr/share/doc/foo"));
        assert!(!in_scope("usr/lib/debug/x.debug"));
        assert!(!in_scope("usr/lib/"));
    }
}
