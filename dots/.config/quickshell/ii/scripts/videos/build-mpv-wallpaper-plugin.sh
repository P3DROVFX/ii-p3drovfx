#!/usr/bin/env bash
# Builds and installs the MpvWallpaper QML plugin (plugins/mpv-wallpaper), which
# lets the shell play video wallpapers itself with libmpv.
#
#   build-mpv-wallpaper-plugin.sh                 build, install for this user (~/.local/lib/qt6/qml)
#   build-mpv-wallpaper-plugin.sh --system        build, install for every user (sudo, Qt's qml dir)
#   build-mpv-wallpaper-plugin.sh --status        JSON for Settings: distro, missing build
#                                                 dependencies, this distro's install command,
#                                                 where the plugin is installed
#   build-mpv-wallpaper-plugin.sh --install-deps  install the missing build dependencies (sudo)
#   build-mpv-wallpaper-plugin.sh --restart-shell reload Hyprland's env and restart the shell from it
#
# The user install is found through QML_IMPORT_PATH, which the Hyprland env
# config exports (hypr/hyprland/env.lua). Rebuild after a Qt upgrade.
set -euo pipefail
unset LD_LIBRARY_PATH LD_PRELOAD

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/../../plugins/mpv-wallpaper" && pwd)"
# Outside the shell config: Quickshell scans that tree, a build dir would slow it down.
BUILD_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell-ii/mpv-wallpaper-build"
USER_QML_DIR="$HOME/.local/lib/qt6/qml"

find_qtpaths() {
    local candidate
    for candidate in qtpaths6 qtpaths-qt6 /usr/lib/qt6/bin/qtpaths /usr/lib64/qt6/bin/qtpaths qtpaths; do
        if command -v "$candidate" >/dev/null 2>&1; then
            # A Qt 5 qtpaths would point the build at the wrong Qt.
            if [[ "$("$candidate" --query QT_VERSION 2>/dev/null)" == 6.* ]]; then
                command -v "$candidate"
                return 0
            fi
        fi
    done
    return 1
}
QTPATHS="$(find_qtpaths || true)"

# Distro family, grouped like the setup script: arch, fedora, fedora-atomic,
# debian, opensuse, gentoo, or other.
distro_family() {
    local id="" like=""
    if [[ -r /etc/os-release ]]; then
        id="$(. /etc/os-release; echo "${ID:-}")"
        like="$(. /etc/os-release; echo "${ID_LIKE:-}")"
    fi
    local ids=" ${id,,} ${like,,} "
    if [[ -e /run/ostree-booted ]]; then echo fedora-atomic
    elif [[ "$ids" == *" arch "* || -e /etc/arch-release ]]; then echo arch
    elif [[ "$ids" == *" fedora "* ]]; then echo fedora
    elif [[ "$ids" == *" debian "* || "$ids" == *" ubuntu "* ]]; then echo debian
    elif [[ "$ids" == *opensuse* || "$ids" == *" suse "* ]]; then echo opensuse
    elif [[ "$ids" == *" gentoo "* ]]; then echo gentoo
    else echo other
    fi
}
DISTRO="$(distro_family)"

# The package that provides build dependency `key` on distro `family`.
dep_package() {
    local key="$1" family="$2"
    case "$family" in
        fedora|fedora-atomic)
            case "$key" in
                cmake) echo cmake ;; cxx) echo gcc-c++ ;; pkgconfig) echo pkgconf-pkg-config ;;
                mpv) echo mpv-devel ;; qtbase) echo qt6-qtbase-devel ;; qtquick) echo qt6-qtdeclarative-devel ;;
            esac ;;
        opensuse)
            case "$key" in
                cmake) echo cmake ;; cxx) echo gcc-c++ ;; pkgconfig) echo pkgconf-pkg-config ;;
                mpv) echo mpv-devel ;; qtbase) echo qt6-base-devel ;; qtquick) echo qt6-declarative-devel ;;
            esac ;;
        arch)
            case "$key" in
                cmake) echo cmake ;; cxx) echo gcc ;; pkgconfig) echo pkgconf ;;
                mpv) echo mpv ;; qtbase) echo qt6-base ;; qtquick) echo qt6-declarative ;;
            esac ;;
        debian)
            case "$key" in
                cmake) echo cmake ;; cxx) echo g++ ;; pkgconfig) echo pkg-config ;;
                mpv) echo libmpv-dev ;; qtbase) echo qt6-base-dev ;; qtquick) echo qt6-declarative-dev ;;
            esac ;;
        gentoo)
            case "$key" in
                cmake) echo dev-build/cmake ;; cxx) echo sys-devel/gcc ;; pkgconfig) echo dev-util/pkgconf ;;
                mpv) echo media-video/mpv ;; qtbase) echo dev-qt/qtbase ;; qtquick) echo dev-qt/qtdeclarative ;;
            esac ;;
    esac
}
dep_label() {
    case "$1" in
        cmake) echo "CMake" ;; cxx) echo "C++ compiler" ;; pkgconfig) echo "pkg-config" ;;
        mpv) echo "libmpv headers" ;; qtbase) echo "Qt 6 base development files" ;;
        qtquick) echo "Qt 6 Quick development files" ;;
    esac
}

dep_present() {
    case "$1" in
        cmake) command -v cmake >/dev/null ;;
        cxx) command -v c++ >/dev/null || command -v g++ >/dev/null || command -v clang++ >/dev/null ;;
        pkgconfig) command -v pkg-config >/dev/null ;;
        mpv) command -v pkg-config >/dev/null && pkg-config --exists mpv ;;
        qtbase) [[ -n "$QTPATHS" ]] && [[ -f "$("$QTPATHS" --query QT_INSTALL_LIBS)/cmake/Qt6Gui/Qt6GuiConfig.cmake" ]] ;;
        qtquick) [[ -n "$QTPATHS" ]] && [[ -f "$("$QTPATHS" --query QT_INSTALL_LIBS)/cmake/Qt6Quick/Qt6QuickConfig.cmake" ]] ;;
    esac
}

DEP_KEYS=(cmake cxx pkgconfig mpv qtbase qtquick)
missing_keys() {
    local key
    for key in "${DEP_KEYS[@]}"; do
        dep_present "$key" || echo "$key"
    done
}

# The command that installs `keys` on this distro, or nothing when unknown.
install_command() {
    local packages=() key
    for key in "$@"; do
        packages+=("$(dep_package "$key" "$DISTRO")")
    done
    (( ${#packages[@]} )) || return 0
    case "$DISTRO" in
        arch) echo "sudo pacman -S --needed ${packages[*]}" ;;
        fedora) echo "sudo dnf install ${packages[*]}" ;;
        fedora-atomic) echo "rpm-ostree install ${packages[*]}" ;;
        debian) echo "sudo apt install ${packages[*]}" ;;
        opensuse) echo "sudo zypper install ${packages[*]}" ;;
        gentoo) echo "sudo emerge --ask --noreplace ${packages[*]}" ;;
    esac
}

installed_dir() {
    if [[ -f "$USER_QML_DIR/MpvWallpaper/qmldir" ]]; then
        echo "$USER_QML_DIR/MpvWallpaper"
    elif [[ -n "$QTPATHS" && -f "$("$QTPATHS" --query QT_INSTALL_QML)/MpvWallpaper/qmldir" ]]; then
        echo "$("$QTPATHS" --query QT_INSTALL_QML)/MpvWallpaper"
    fi
}

json_string() {
    local s="${1//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '"%s"' "$s"
}

if [[ "${1:-}" == "--status" ]]; then
    mapfile -t missing < <(missing_keys)
    labels=()
    for key in "${missing[@]}"; do labels+=("$(json_string "$(dep_label "$key")")"); done
    printf '{"distro":%s,"missing":[%s],"installCommand":%s,"installedDir":%s,"userQmlDir":%s,"buildScript":%s}\n' \
        "$(json_string "$DISTRO")" \
        "$(IFS=,; echo "${labels[*]}")" \
        "$(json_string "$(install_command "${missing[@]}")")" \
        "$(json_string "$(installed_dir)")" \
        "$(json_string "$USER_QML_DIR")" \
        "$(json_string "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")")"
    exit 0
fi

if [[ "${1:-}" == "--restart-shell" ]]; then
    # The new shell must inherit Hyprland's environment (where env.lua puts
    # QML_IMPORT_PATH), not the old shell's: reload Hyprland so the variable is
    # there, then start the shell from Hyprland itself.
    config="${qsConfig:-ii}"
    restart="qs kill -c $config; sleep 0.5; MALLOC_CONF=narenas:1 qs -c $config"
    hyprctl reload >/dev/null 2>&1 || true
    sleep 0.5
    if ! hyprctl eval "hl.dispatch(hl.dsp.exec_cmd('$restart'))" 2>/dev/null | grep -q '^ok'; then
        hyprctl dispatch exec "$restart" >/dev/null # hyprlang configs
    fi
    exit 0
fi

if [[ "${1:-}" == "--install-deps" ]]; then
    mapfile -t missing < <(missing_keys)
    if (( ! ${#missing[@]} )); then
        echo "All build dependencies are already installed."
        exit 0
    fi
    cmd="$(install_command "${missing[@]}")"
    if [[ -z "$cmd" ]]; then
        echo "Unknown distro: install these yourself, then build again:"
        for key in "${missing[@]}"; do echo "  - $(dep_label "$key")"; done
        exit 1
    fi
    echo "\$ $cmd"
    eval "$cmd"
    exit $?
fi

system_install=0
[[ "${1:-}" == "--system" ]] && system_install=1

mapfile -t missing < <(missing_keys)
if (( ${#missing[@]} )); then
    echo "Missing build dependencies:"
    for key in "${missing[@]}"; do echo "  - $(dep_label "$key")"; done
    cmd="$(install_command "${missing[@]}")"
    [[ -n "$cmd" ]] && echo && echo "Install them with: $cmd"
    exit 1
fi

echo "==> Configuring ($BUILD_DIR)"
generator=()
command -v ninja >/dev/null && generator=(-G Ninja)
cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" "${generator[@]}" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$("$QTPATHS" --query QT_INSTALL_PREFIX)" >/dev/null

echo "==> Building"
cmake --build "$BUILD_DIR" -j"$(nproc)"

module_dir="$BUILD_DIR/qml/MpvWallpaper"
if (( system_install )); then
    dest="$("$QTPATHS" --query QT_INSTALL_QML)"
    echo "==> Installing to $dest/MpvWallpaper (sudo)"
    sudo rm -rf "$dest/MpvWallpaper"
    sudo cp -r "$module_dir" "$dest/MpvWallpaper"
else
    dest="$USER_QML_DIR"
    echo "==> Installing to $dest/MpvWallpaper"
    mkdir -p "$dest"
    # Replace, never overwrite in place: a running shell has the old library mapped.
    rm -rf "$dest/MpvWallpaper"
    cp -r "$module_dir" "$dest/MpvWallpaper"
fi
# Only the module is needed at runtime; keep the build tree for fast rebuilds.
find "$dest/MpvWallpaper" -name '*.qrc' -delete 2>/dev/null || true

echo "==> Done: MpvWallpaper installed in $dest"
if (( ! system_install )) && [[ ":${QML_IMPORT_PATH:-}:" != *":$USER_QML_DIR:"* ]]; then
    echo "QML_IMPORT_PATH does not include $USER_QML_DIR in this session yet:"
    echo "reload Hyprland (hyprctl reload) and restart the shell, or log out and back in."
else
    echo "Restart the shell to load it."
fi
