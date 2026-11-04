//! Compiles `src/bpf/net.bpf.c` with clang and generates its Rust skeleton.

use std::env;
use std::path::PathBuf;

use libbpf_cargo::SkeletonBuilder;

const SRC: &str = "src/bpf/net.bpf.c";

fn main() {
    let out =
        PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR is set by cargo")).join("net.skel.rs");
    let arch = env::var("CARGO_CFG_TARGET_ARCH").expect("CARGO_CFG_TARGET_ARCH is set by cargo");
    let target_arch = match arch.as_str() {
        "x86_64" => "x86",
        "aarch64" => "arm64",
        other => other,
    };
    SkeletonBuilder::new()
        .source(SRC)
        .clang_args(["-O2", "-g", &format!("-D__TARGET_ARCH_{target_arch}")])
        .build_and_generate(&out)
        .expect("compiling the BPF program (needs clang and the libbpf headers)");
    println!("cargo:rerun-if-changed={SRC}");
}
