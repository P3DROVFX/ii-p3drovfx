//! Client for `app_stats_net`, the eBPF helper that counts every packet per socket in
//! the kernel and tags each socket with the process that used it.
//!
//! It is optional: it needs a one-time privileged install (`install-net-helper.sh`),
//! and without it the sampler falls back on the socket counters in `net.rs`, which
//! miss UDP and connections shorter than one sample. Started once per sampler run and
//! asked for a dump on every tick; it exits when this process closes its stdin, and
//! its BPF programs detach with it.

use std::io::{BufRead, BufReader, Write};
use std::path::Path;
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};

pub const DEFAULT_PATH: &str = "/usr/local/lib/ii/app_stats_net";

/// Bytes one process moved since the previous dump, with what is needed to place it
/// once it has exited: its parent, and its own name.
pub struct ProcBytes {
    pub tgid: u32,
    pub ppid: u32,
    pub comm: String,
    pub rx: u64,
    pub tx: u64,
}

pub struct Helper {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
}

pub enum Start {
    Ready(Helper),
    /// Not installed: the normal state until the user opts in.
    Absent,
    /// Installed but unusable — capabilities lost to a copy, not in wheel, a kernel
    /// without BTF. The message goes to the overlay.
    Failed(String),
}

impl Helper {
    pub fn start(path: &str) -> Start {
        if !Path::new(path).exists() {
            return Start::Absent;
        }
        let mut child = match Command::new(path)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            // libbpf's own diagnostics; the outcome arrives as JSON either way.
            .stderr(Stdio::null())
            .spawn()
        {
            Ok(c) => c,
            Err(e) => return Start::Failed(format!("cannot run {path}: {e}")),
        };
        let (Some(stdin), Some(stdout)) = (child.stdin.take(), child.stdout.take()) else {
            let _ = child.kill();
            let _ = child.wait();
            return Start::Failed("no pipes to the helper".into());
        };
        let mut helper = Helper {
            child,
            stdin,
            stdout: BufReader::new(stdout),
        };
        match helper.read_json() {
            Some(v) if v.get("t").and_then(|t| t.as_str()) == Some("ready") => Start::Ready(helper),
            Some(v) => Start::Failed(
                v.get("msg")
                    .and_then(|m| m.as_str())
                    .unwrap_or("the helper refused to start")
                    .to_string(),
            ),
            None => Start::Failed("the helper exited before it was ready".into()),
        }
    }

    fn read_json(&mut self) -> Option<serde_json::Value> {
        let mut line = String::new();
        match self.stdout.read_line(&mut line) {
            Ok(n) if n > 0 => serde_json::from_str(&line).ok(),
            _ => None,
        }
    }

    /// Bytes per process since the last dump. None once the helper is gone, which
    /// the caller takes as the signal to fall back.
    pub fn dump(&mut self) -> Option<Vec<ProcBytes>> {
        writeln!(self.stdin, "d").ok()?;
        self.stdin.flush().ok()?;
        let v = self.read_json()?;
        if v.get("t").and_then(|t| t.as_str()) != Some("dump") {
            return None;
        }
        let mut out = Vec::new();
        for p in v.get("p")?.as_array()? {
            let a = p.as_array()?;
            let num = |i: usize| a.get(i).and_then(|x| x.as_u64()).unwrap_or(0);
            out.push(ProcBytes {
                tgid: num(0) as u32,
                ppid: num(1) as u32,
                comm: a.get(2).and_then(|x| x.as_str()).unwrap_or("").to_string(),
                rx: num(3),
                tx: num(4),
            });
        }
        Some(out)
    }
}

impl Drop for Helper {
    fn drop(&mut self) {
        let _ = writeln!(self.stdin, "q");
        let _ = self.stdin.flush();
        let _ = self.child.wait();
    }
}
