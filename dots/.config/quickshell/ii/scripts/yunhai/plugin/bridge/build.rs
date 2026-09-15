use cxx_qt_build::{CxxQtBuilder, PluginType, QmlModule};

const PLUGIN_SYMBOLS: &[&str] = &["qt_plugin_instance", "qt_plugin_query_metadata_v2"];

fn main() {
    let out_dir = std::env::var("OUT_DIR").expect("OUT_DIR");
    let version_script = std::path::Path::new(&out_dir).join("plugin.map");
    let globals: String = PLUGIN_SYMBOLS
        .iter()
        .map(|symbol| format!("    {symbol};\n"))
        .collect();
    std::fs::write(&version_script, format!("{{\n  global:\n{globals}}};\n"))
        .expect("write version script");

    for symbol in PLUGIN_SYMBOLS {
        println!("cargo:rustc-cdylib-link-arg=-Wl,--undefined={symbol}");
    }
    println!(
        "cargo:rustc-cdylib-link-arg=-Wl,--version-script={}",
        version_script.display()
    );

    CxxQtBuilder::new_qml_module(
        QmlModule::new("Yunhai.Sys")
            .version(1, 0)
            .plugin_type(PluginType::Dynamic),
    )
    .files(["src/monitor.rs", "src/process.rs"])
    .build();
}
