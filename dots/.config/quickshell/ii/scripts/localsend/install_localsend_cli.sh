#!/usr/bin/env bash
# Installs the official localsend-cli (localsend/localsend monorepo, cli/,
# Rust, protocol v2.2 — the same networking/file-I/O code as the LocalSend
# app) from the project's own prebuilt GitHub release binaries. No Rust
# toolchain needed on the vast majority of machines (x86_64/aarch64 Linux
# or macOS): this only falls back to printing `cargo build` instructions
# when no prebuilt asset matches the current OS/architecture.
#
# Used by services/LocalSend.qml's "Install" button (modules/settings/
# configs/DevicesPhoneConfig.qml) and safe to run standalone.
set -euo pipefail

REPO="localsend/localsend"
BIN_DIR="$HOME/.local/bin"
DEST="$BIN_DIR/localsend-cli"

os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
    Linux) os_tag="linux" ;;
    Darwin) os_tag="macos" ;;
    *)
        echo "Unsupported OS for a prebuilt binary: $os" >&2
        exit 1
        ;;
esac

case "$arch" in
    x86_64 | amd64) arch_tag="x86-64" ;;
    aarch64 | arm64) arch_tag="arm-64" ;;
    *)
        echo "Unsupported architecture for a prebuilt binary: $arch" >&2
        exit 1
        ;;
esac

asset_suffix="${os_tag}-${arch_tag}.tar.gz"

# A now-unaffiliated pip package named `localsend-cli` (0.1.1) used to ship
# to this exact path via its own console_scripts entry point. If it is
# still installed, `pip uninstall` would delete the freshly-installed
# official binary the next time the user (or a system upgrade) touches
# that package, because pip only remembers the path, not what currently
# lives there. Clear it out first, unconditionally.
if command -v pip >/dev/null 2>&1 && pip show localsend-cli >/dev/null 2>&1; then
    echo "Removing the deprecated 'localsend-cli' pip package (unaffiliated with the LocalSend project, corrupted received files on protocol v2.2)..." >&2
    pip uninstall -y localsend-cli >/dev/null 2>&1 || true
fi
rm -f "$HOME/.config/localsend-cli/cert.pem" "$HOME/.config/localsend-cli/key.pem" 2>/dev/null || true

echo "Looking for the latest localsend-cli release for ${asset_suffix}..." >&2

# The CLI ships inside the same GitHub releases as the app, but not every
# release rebuilds it (e.g. Android/iOS-only hotfixes). Walk back through
# releases until one carries a matching asset.
download_url=""
version=""
for page in 1 2 3; do
    releases_json=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases?per_page=30&page=${page}")
    [ "$releases_json" = "[]" ] && break
    match=$(echo "$releases_json" | jq -r --arg suffix "$asset_suffix" '
        [.[] | select(.assets != null) | . as $r
         | $r.assets[] | select(.name | startswith("LocalSend-CLI-") and endswith($suffix))
         | {url: .browser_download_url, tag: $r.tag_name}
        ] | .[0] // empty
        | if . == {} then empty else (.url + "\n" + .tag) end
    ')
    if [ -n "$match" ]; then
        download_url=$(echo "$match" | sed -n '1p')
        version=$(echo "$match" | sed -n '2p')
        break
    fi
done

if [ -z "$download_url" ]; then
    cat >&2 <<EOF
No prebuilt localsend-cli binary is published yet for ${asset_suffix}.
Build it from source instead (needs a Rust toolchain: cargo/rustc):

  git clone --filter=blob:none --no-checkout https://github.com/${REPO}.git ~/.local/share/localsend-cli-src
  cd ~/.local/share/localsend-cli-src
  git sparse-checkout init --cone
  git sparse-checkout set cli packages/core packages/localsend_isolates/rust server
  git checkout main
  cd cli && cargo build --release
  install -m 755 ../target/release/localsend-cli "$DEST"
EOF
    exit 2
fi

echo "Downloading localsend-cli (${version}) from ${download_url}..." >&2
mkdir -p "$BIN_DIR"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
curl -fsSL -o "$tmp_dir/localsend-cli.tar.gz" "$download_url"
tar -xzf "$tmp_dir/localsend-cli.tar.gz" -C "$tmp_dir"

if [ ! -f "$tmp_dir/localsend-cli" ]; then
    echo "Unexpected archive layout: localsend-cli binary not found after extracting ${download_url}." >&2
    exit 3
fi

install -m 755 "$tmp_dir/localsend-cli" "$DEST"
installed_version="$("$DEST" --version 2>/dev/null || echo unknown)"
echo "Installed ${installed_version} to ${DEST}" >&2
