#!/usr/bin/env bash
# qs-build.sh — build Quickshell with ii's startup patches and install it as
# a native package (quickshell-ii-git) in place of the distribution's.
#
# Why: the stock Quickshell takes ~5-7 s to scan this config before any QML runs
# (its scanner re-resolves every directory's real path on each import line) and
# never uses Qt's QML disk cache (the config is served through a qs: URL scheme),
# so everything is recompiled on every start. ./patches fixes both; the bar shows
# ~1.9 s after launch instead of ~5 s or more. See README.md.
#
# Usage: qs-build.sh <command> [-y|--yes] [--force]
#   install   Build and install quickshell-ii-git (replaces quickshell / quickshell-git)
#   rebuild   The same, even when the installed build is current (e.g. after a Qt update)
#   build     Only build the package and print its path (nothing is installed)
#   restore   Put the distribution's quickshell-git back
#   status    Show which Quickshell is installed and whether it is patched
#
# Supported: Arch and its derivatives (makepkg + pacman), Fedora (rpmbuild + dnf).
# Exit status: 0 done, 1 failed or declined, 3 unsupported distribution.

set -euo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=revision
source "$HERE/revision"

PKG="quickshell-ii-git"
UPSTREAM_URL="https://github.com/quickshell-mirror/quickshell"
DISTRIBUTOR="ii-p3drovfx ($PKG)"

YES=false
FORCE=false
CMD=""
WORK=""

say() { printf '  %s\n' "$*"; }
step() { printf '\n:: %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die() {
    warn "$*"
    exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }
ask() {
    [[ "$YES" == true ]] && return 0
    local a
    # read -p writes the question to stderr: send it to the terminal too (it used to
    # go to /dev/null with the errors, so the script sat waiting on a question
    # nobody could see). Without a terminal the redirection fails and we say no.
    if ! { read -r -p "  $1 [Y/n] " a </dev/tty 2>/dev/tty; } 2>/dev/null; then
        return 1
    fi
    [[ -z "$a" || "$a" == [Yy]* ]]
}
KEEP_WORK=false
cleanup() {
    if [[ "$KEEP_WORK" != true && -n "$WORK" && -d "$WORK" ]]; then rm -rf "$WORK"; fi
    return 0
}
trap cleanup EXIT

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; }

while (($#)); do
    case "$1" in
        install | rebuild | build | restore | status) CMD="$1" ;;
        -y | --yes) YES=true ;;
        --force) FORCE=true ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
    shift
done
[[ -n "$CMD" ]] || {
    usage >&2
    exit 1
}

# ── Distribution ─────────────────────────────────────────────────────────────

family() {
    local id="" like=""
    if [[ -r /etc/os-release ]]; then
        id="$(. /etc/os-release && printf '%s' "${ID:-}")"
        like="$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")"
    fi
    if have pacman && { [[ -f /etc/arch-release ]] || [[ " $id $like " == *" arch "* ]]; }; then
        printf 'arch'
    elif have dnf && { [[ -f /etc/fedora-release ]] || [[ " $id $like " == *" fedora "* ]]; }; then
        printf 'fedora'
    else
        printf 'unsupported'
    fi
}
FAMILY="$(family)"

owner_pkg() {
    [[ -e /usr/bin/quickshell ]] || return 1
    case "$FAMILY" in
        arch) pacman -Qqo /usr/bin/quickshell 2>/dev/null ;;
        fedora) rpm -qf --qf '%{NAME}\n' /usr/bin/quickshell 2>/dev/null ;;
        *) return 1 ;;
    esac
}

installed_version() {
    case "$FAMILY" in
        arch) pacman -Q "$PKG" 2>/dev/null | awk '{print $2}' ;;
        fedora) rpm -q --qf '%{VERSION}-%{RELEASE}\n' "$PKG" 2>/dev/null ;;
    esac
}

# Built for the Qt that is installed now (quickshell refuses to start otherwise).
qt_compatible() {
    [[ -x /usr/bin/quickshell ]] || return 1
    /usr/bin/quickshell --private-check-compat >/dev/null 2>&1
}

# A Quickshell built by hand into ~/.local (cmake --install, or an older
# patched build) comes first on PATH and hides the package's.
shadowing_binaries() {
    local name p
    for name in qs quickshell; do
        p="$(type -P "$name" 2>/dev/null)" || continue
        [[ "$(readlink -f "$p")" == /usr/bin/* ]] && continue
        printf '%s\n' "$p"
        [[ -L "$p" ]] && printf '%s\n' "$(readlink -f "$p")"
    done | awk '!seen[$0]++'
}

move_shadowing_aside() {
    local -a hand=()
    mapfile -t hand < <(shadowing_binaries)
    ((${#hand[@]} > 0)) || return 0
    step "Another Quickshell comes first on PATH"
    say "$(type -P qs || type -P quickshell) would run instead of the package's /usr/bin/qs."
    say "Moving these aside lets the new build run (nothing is deleted):"
    local f
    for f in "${hand[@]}"; do say "  $f -> $f.hand-built"; done
    if ! ask "Move them?"; then
        warn "Left in place: the shell keeps running the old binary until you move them."
        return 0
    fi
    for f in "${hand[@]}"; do
        [[ -e "$f" || -L "$f" ]] || continue
        mv -n -- "$f" "$f.hand-built" || warn "could not move $f"
    done
    hash -r
}

status() {
    step "Quickshell"
    say "distribution  $FAMILY"
    local owner ver
    owner="$(owner_pkg || true)"
    say "package       ${owner:-none (/usr/bin/quickshell missing or unowned)}"
    if [[ -x /usr/bin/quickshell ]]; then
        ver="$(/usr/bin/quickshell --version 2>/dev/null | head -1 || true)"
        say "version       ${ver:-unknown}"
        if [[ "$ver" == *"$PKG"* ]]; then
            say "patched       yes ($(installed_version))"
        else
            say "patched       no"
        fi
        if qt_compatible; then say "qt            matches the installed Qt"; else say "qt            MISMATCH — run: $0 rebuild"; fi
    fi
    say "pinned        ${QS_COMMIT:0:7} ($QS_VERSION-$QS_RELEASE)"
    local -a hand=()
    mapfile -t hand < <(shadowing_binaries)
    ((${#hand[@]} > 0)) && say "shadowed by   ${hand[*]}"
    return 0
}

# ── Arch ─────────────────────────────────────────────────────────────────────

write_pkgbuild() {
    local dir="$1" crash="$2" patches="" sums="" p
    for p in "$HERE"/patches/*.patch; do
        cp "$p" "$dir/"
        patches+=" '$(basename "$p")'"
        sums+=" 'SKIP'"
    done
    local crashdep=""
    [[ "$crash" == ON ]] && crashdep="'cpptrace'"
    cat >"$dir/PKGBUILD" <<EOF
# Generated by ii's scripts/quickshell-build/qs-build.sh — do not edit.
pkgname=$PKG
pkgver=$QS_VERSION
pkgrel=$QS_RELEASE
pkgdesc='Quickshell with the ii-p3drovfx startup patches (fast QML scan, QML disk cache)'
arch=(x86_64 aarch64)
url='$UPSTREAM_URL'
license=('LGPL-3.0-only')
options=(!strip !debug)
depends=('qt6-declarative' 'qt6-base' 'qt6-svg' 'qt6-wayland' 'jemalloc' 'libpipewire' 'libxcb'
         'wayland' 'libdrm' 'mesa' 'polkit' 'pam' 'glib2' $crashdep)
makedepends=('vulkan-headers' 'spirv-tools' 'qt6-shadertools' 'wayland-protocols' 'cli11'
             'ninja' 'cmake' 'git')
provides=("quickshell=\$pkgver" "quickshell-git=\$pkgver")
conflicts=('quickshell' 'quickshell-git')
source=("quickshell::git+$UPSTREAM_URL.git#commit=$QS_COMMIT"$patches)
sha256sums=('SKIP'$sums)

prepare() {
  cd quickshell
  local p
  for p in "\$srcdir"/*.patch; do
    patch -Np1 -i "\$p"
  done
}

build() {
  cd quickshell
  cmake -GNinja -B build \\
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \\
    -DCMAKE_INSTALL_PREFIX=/usr \\
    -DINSTALL_QML_PREFIX=lib/qt6/qml \\
    -DCRASH_HANDLER=$crash \\
    -DDISTRIBUTOR="$DISTRIBUTOR" \\
    -DGIT_REVISION=$QS_COMMIT
  cmake --build build
}

package() {
  cd quickshell
  DESTDIR="\$pkgdir" cmake --install build
  install -Dm644 LICENSE -t "\$pkgdir/usr/share/licenses/\$pkgname"
}
EOF
}

build_arch() {
    have makepkg || die "makepkg not found (pacman's base-devel)."
    ((EUID != 0)) || die "Run this as your user, not root: makepkg refuses to build as root."
    have git || sudo pacman -S --needed --noconfirm git
    pacman -Qq base-devel >/dev/null 2>&1 || sudo pacman -S --needed --noconfirm base-devel

    # cpptrace (crash handler: Quickshell restarts itself after a crash) is in
    # extra; without it the build still works, only that handler is off.
    local crash=OFF
    if pacman -Si cpptrace >/dev/null 2>&1 || pacman -Qq cpptrace >/dev/null 2>&1; then crash=ON; fi

    WORK="$(mktemp -d "${TMPDIR:-/tmp}/$PKG-XXXXXX")"
    write_pkgbuild "$WORK" "$crash"

    step "Building $PKG $QS_VERSION-$QS_RELEASE (a few minutes)"
    local -a mflags=(-s -f --needed)
    [[ "$YES" == true ]] && mflags+=(--noconfirm)
    (cd "$WORK" && makepkg "${mflags[@]}") || die "makepkg failed."
    local pkgfile
    pkgfile="$(cd "$WORK" && makepkg --packagelist | grep -v -- '-debug-' | head -1)"
    [[ -f "$pkgfile" ]] || die "makepkg did not produce a package."
    if [[ "$CMD" == build ]]; then
        KEEP_WORK=true
        BUILT="$pkgfile"
        return 0
    fi

    # Swapping the package orphans every Qt module a meta-package (the base
    # install's illogical-impulse-quickshell-git) pulled in as a dependency, and
    # a later `pacman -Rns $(pacman -Qdtq)` would sweep away half of what the
    # shell needs. Diff the orphans around the swap and keep the stranded ones.
    local before after
    before="$(pacman -Qdtq 2>/dev/null | sort || true)"

    step "Installing $(basename "$pkgfile")"
    local -a pflags=(-U)
    # --ask=4 answers "remove the conflicting package?" with yes under --noconfirm.
    [[ "$YES" == true ]] && pflags+=(--noconfirm --ask=4)
    sudo pacman "${pflags[@]}" "$pkgfile" || die "pacman -U failed."

    after="$(pacman -Qdtq 2>/dev/null | sort || true)"
    local -a stranded=()
    mapfile -t stranded < <(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep -v '^$' || true)
    if ((${#stranded[@]} > 0)); then
        sudo pacman -D -q --asexplicit "${stranded[@]}" >/dev/null &&
            say "Kept ${#stranded[@]} Qt packages the old quickshell package had pulled in."
    fi
}

restore_arch() {
    local helper="" h
    for h in yay paru; do
        have "$h" && {
            helper="$h"
            break
        }
    done
    [[ -n "$helper" ]] || die "No AUR helper (yay or paru): install aur/quickshell-git yourself."
    step "Installing aur/quickshell-git (pacman will offer to replace $PKG)"
    local -a flags=(-S --rebuild)
    [[ "$YES" == true ]] && flags+=(--noconfirm --ask=4)
    "$helper" "${flags[@]}" aur/quickshell-git
}

# ── Fedora ───────────────────────────────────────────────────────────────────

write_spec() {
    local spec="$1" crash="$2" i=0 p patchlines="" brs=""
    for p in "$HERE"/patches/*.patch; do
        cp "$p" "$WORK/SOURCES/"
        patchlines+="Patch$i:             $(basename "$p")"$'\n'
        i=$((i + 1))
    done
    [[ "$crash" == ON ]] && brs=$'BuildRequires:      cpptrace-devel\nBuildRequires:      libdwarf-devel\nBuildRequires:      pkgconfig(libzstd)'
    cat >"$spec" <<EOF
# Generated by ii's scripts/quickshell-build/qs-build.sh — do not edit.
%global debug_package %{nil}
%global commit $QS_COMMIT

Name:               $PKG
Version:            $QS_VERSION
Release:            $QS_RELEASE%{?dist}
Summary:            Quickshell with the ii-p3drovfx startup patches
License:            LGPL-3.0-only AND GPL-3.0-only
URL:                $UPSTREAM_URL
Source0:            quickshell-%{commit}.tar.gz
$patchlines
BuildRequires:      cmake
BuildRequires:      cmake(Qt6Core)
BuildRequires:      cmake(Qt6Qml)
BuildRequires:      cmake(Qt6ShaderTools)
BuildRequires:      cmake(Qt6WaylandClient)
BuildRequires:      gcc-c++
BuildRequires:      ninja-build
BuildRequires:      pkgconfig(CLI11)
BuildRequires:      pkgconfig(gbm)
BuildRequires:      pkgconfig(glib-2.0)
BuildRequires:      pkgconfig(polkit-agent-1)
BuildRequires:      pkgconfig(jemalloc)
BuildRequires:      pkgconfig(libdrm)
BuildRequires:      pkgconfig(libpipewire-0.3)
BuildRequires:      pkgconfig(pam)
BuildRequires:      pkgconfig(wayland-client)
BuildRequires:      pkgconfig(wayland-protocols)
BuildRequires:      qt6-qtbase-private-devel
BuildRequires:      spirv-tools
$brs

Provides:           quickshell = %{version}-%{release}
Provides:           quickshell-git = %{version}-%{release}
Provides:           desktop-notification-daemon
Conflicts:          quickshell
Conflicts:          quickshell-git

%description
Quickshell built from upstream commit %{commit} with five startup patches:
the QML scanner resolves each directory once instead of once per import,
the config is served from a file:// mirror so Qt's QML disk cache works,
the URL interceptor resolves the config root once, the synthesized
qs.* modules are registered so Qt skips a quadratic qmldir check per import,
and each QML document only gets the composite singletons it names.
Set QS_NO_SINGLETON_FILTER=1 to turn that last one off.
Set QS_NO_FILE_VFS=1 to turn the mirror off.

%prep
%autosetup -n quickshell-%{commit} -p1

%build
%cmake -GNinja \\
        -DBUILD_SHARED_LIBS=OFF \\
        -DCRASH_HANDLER=$crash \\
        -DUSE_JEMALLOC=ON \\
        -DCMAKE_BUILD_TYPE=Release \\
        -DDISTRIBUTOR="$DISTRIBUTOR" \\
        -DGIT_REVISION=%{commit} \\
        -DINSTALL_QML_PREFIX=%{_lib}/qt6/qml
%cmake_build

%install
%cmake_install

%files
%license LICENSE
%license LICENSE-GPL
%{_bindir}/qs
%{_bindir}/quickshell
%{_datadir}/applications/org.quickshell.desktop
%{_datadir}/icons/hicolor/scalable/apps/org.quickshell.svg
%{_libdir}/qt6/qml/Quickshell
EOF
}

# The capabilities in "$@" that no installed package provides.
rpm_missing() {
    local d
    for d in "$@"; do
        rpm -q --whatprovides "$d" >/dev/null 2>&1 || printf '%s\n' "$d"
    done
}

# Whether the installed cpptrace can unwind from a signal handler: the same check
# Quickshell's CMake makes before enabling the crash handler, which aborts the
# whole build when it fails. Fedora's own cpptrace (rawhide, 2026-11) is built
# without libunwind and fails it; the Quickshell COPR builds pass.
cpptrace_unwinds() {
    local d ok=1
    d="$(mktemp -d)" || return 1
    printf '#include <cpptrace/cpptrace.hpp>\nint main() { return cpptrace::can_signal_safe_unwind() ? 0 : 1; }\n' >"$d/t.cpp"
    if g++ -std=c++20 "$d/t.cpp" -o "$d/t" -lcpptrace >/dev/null 2>&1 && "$d/t"; then ok=0; fi
    rm -rf "$d"
    return "$ok"
}

build_fedora() {
    step "Build dependencies"
    local -a deps=(rpm-build cmake gcc-c++ ninja-build curl
        'cmake(Qt6Core)' 'cmake(Qt6Qml)' 'cmake(Qt6ShaderTools)' 'cmake(Qt6WaylandClient)'
        'pkgconfig(CLI11)' 'pkgconfig(gbm)' 'pkgconfig(glib-2.0)' 'pkgconfig(polkit-agent-1)'
        'pkgconfig(jemalloc)' 'pkgconfig(libdrm)' 'pkgconfig(libpipewire-0.3)' 'pkgconfig(pam)'
        'pkgconfig(wayland-client)' 'pkgconfig(wayland-protocols)' qt6-qtbase-private-devel spirv-tools)
    local -a missing=()
    mapfile -t missing < <(rpm_missing "${deps[@]}")
    if ((${#missing[@]} > 0)); then
        sudo dnf install -y "${missing[@]}" || die "Could not install the build dependencies."
    else
        say "all installed"
    fi
    # cpptrace (the crash handler: Quickshell restarts itself after a crash) is
    # not in Fedora's repositories, only in the Quickshell COPRs the base
    # install enables. Without it the build still works, only that handler is off.
    local crash=OFF
    local -a crashdeps=(cpptrace-devel libdwarf-devel 'pkgconfig(libzstd)')
    mapfile -t missing < <(rpm_missing "${crashdeps[@]}")
    if ((${#missing[@]} == 0)) || sudo dnf install -y "${missing[@]}" >/dev/null 2>&1; then
        if cpptrace_unwinds; then
            crash=ON
        else
            say "cpptrace has no signal-safe unwinding (built without libunwind): building without the crash handler."
        fi
    else
        say "cpptrace-devel is not available: building without the crash handler."
    fi

    WORK="$(mktemp -d "${TMPDIR:-/tmp}/$PKG-XXXXXX")"
    mkdir -p "$WORK"/{SOURCES,SPECS,BUILD,RPMS,SRPMS}
    step "Fetching quickshell ${QS_COMMIT:0:7}"
    curl -fsSL --retry 3 -o "$WORK/SOURCES/quickshell-$QS_COMMIT.tar.gz" \
        "$UPSTREAM_URL/archive/$QS_COMMIT/quickshell-$QS_COMMIT.tar.gz" || die "Download failed."
    write_spec "$WORK/SPECS/$PKG.spec" "$crash"

    step "Building $PKG $QS_VERSION-$QS_RELEASE (a few minutes)"
    rpmbuild -bb --define "_topdir $WORK" "$WORK/SPECS/$PKG.spec" >"$WORK/rpmbuild.log" 2>&1 || {
        tail -30 "$WORK/rpmbuild.log" >&2
        die "rpmbuild failed."
    }
    local rpm
    rpm="$(find "$WORK/RPMS" -name "$PKG-*.rpm" | head -1)"
    [[ -f "$rpm" ]] || die "rpmbuild did not produce a package."
    if [[ "$CMD" == build ]]; then
        KEEP_WORK=true
        BUILT="$rpm"
        return 0
    fi

    # The base install builds quickshell-git itself and pins it with versionlock;
    # the lock would keep dnf from replacing it.
    if sudo dnf versionlock list 2>/dev/null | grep -q '^quickshell-git'; then
        sudo dnf versionlock delete quickshell-git >/dev/null 2>&1 || true
    fi
    step "Installing $(basename "$rpm")"
    # `rebuild` (after a Qt update, or new patches under the same release) makes an
    # rpm with the NEVRA that is already installed, and `dnf install` then says
    # "Nothing to do" and keeps the old binary. Reinstall in that case.
    local -a flags=(install --allowerasing)
    local nevra
    nevra="$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$rpm" 2>/dev/null)"
    if [[ -n "$nevra" ]] && rpm -q "$nevra" >/dev/null 2>&1; then
        flags=(reinstall)
    fi
    [[ "$YES" == true ]] && flags+=(-y)
    sudo dnf "${flags[@]}" "$rpm" || die "dnf ${flags[0]} failed."
}

restore_fedora() {
    if ! dnf repoquery -q quickshell-git 2>/dev/null | grep -q .; then
        say "No enabled repository provides quickshell-git."
        ask "Enable the errornointernet/quickshell COPR for it?" || die "Enable a repository with quickshell-git, then run restore again."
        sudo dnf copr enable -y errornointernet/quickshell || die "Could not enable the COPR."
    fi
    step "Swapping $PKG for quickshell-git"
    local -a flags=(swap --allowerasing "$PKG" quickshell-git)
    [[ "$YES" == true ]] && flags+=(-y)
    sudo dnf "${flags[@]}"
}

# ── Commands ─────────────────────────────────────────────────────────────────

if [[ "$CMD" == status ]]; then
    status
    exit 0
fi

if [[ "$FAMILY" == unsupported ]]; then
    warn "Patched Quickshell packages are built for Arch (and derivatives) and Fedora only."
    warn "Elsewhere, apply ./patches to Quickshell $QS_COMMIT and build it yourself (see README.md)."
    exit 3
fi

case "$CMD" in
    build)
        BUILT=""
        case "$FAMILY" in
            arch) build_arch ;;
            fedora) build_fedora ;;
        esac
        step "Built: $BUILT"
        case "$FAMILY" in
            arch) say "Install it with: sudo pacman -U '$BUILT'" ;;
            fedora) say "Install it with: sudo dnf install --allowerasing '$BUILT'" ;;
        esac
        ;;
    install | rebuild)
        current="$(installed_version || true)"
        if [[ "$CMD" == install && "$FORCE" != true && "$current" == "$QS_VERSION-$QS_RELEASE"* ]] && qt_compatible; then
            say "$PKG $current is already installed and matches the installed Qt."
            move_shadowing_aside
            exit 0
        fi
        step "Quickshell with ii's startup patches"
        say "Replaces: $(owner_pkg || printf 'nothing (no Quickshell installed)')"
        say "Builds:   $PKG $QS_VERSION-$QS_RELEASE from ${QS_COMMIT:0:7}"
        ask "Build and install it now?" || {
            say "Left as is."
            exit 1
        }
        sudo -v || die "sudo is needed to install the package."
        case "$FAMILY" in
            arch) build_arch ;;
            fedora) build_fedora ;;
        esac
        move_shadowing_aside
        if ! qt_compatible; then
            die "The new build does not start against the installed Qt (quickshell --private-check-compat)."
        fi
        step "Installed: $(/usr/bin/quickshell --version | head -1)"
        say "Restart Quickshell (or log out and back in) to run it."
        ;;
    restore)
        owner="$(owner_pkg || true)"
        if [[ "$owner" != "$PKG" ]]; then
            say "$PKG is not installed (/usr/bin/quickshell belongs to ${owner:-nothing})."
            exit 0
        fi
        ask "Replace $PKG with your distribution's quickshell-git?" || exit 1
        case "$FAMILY" in
            arch) restore_arch ;;
            fedora) restore_fedora ;;
        esac
        say "Restart Quickshell (or log out and back in) to run it."
        ;;
esac
