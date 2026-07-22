#!/usr/bin/env bash
# install_droidcam.sh — Detects distro and installs DroidCam + deps.
#
# Supports:
#   • Arch Linux (AUR: droidcam package includes everything)
#   • Fedora (RPMFusion for v4l2loopback + official DroidCam client installer)
#   • Debian/Ubuntu (official DroidCam installer zip)
#
# Installs: droidcam-cli, v4l2loopback (kernel module), pactl (audio routing),
#           libappindicator-gtk3, adb (android-tools), ffmpeg, alsa-lib.

set -u
IFS=$'\n\t'

echo "╔═══════════════════════════════════════════════╗"
echo "║     DroidCam Installer for ii Phone Panel     ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""

# ─── Distro detection ─────────────────────────────────
detect_distro() {
    if [ -f /etc/arch-release ]; then
        echo "arch"
    elif [ -f /etc/fedora-release ]; then
        echo "fedora"
    elif [ -f /etc/debian_version ] || grep -qiE "ubuntu|debian" /etc/os-release 2>/dev/null; then
        echo "debian"
    else
        echo "unknown"
    fi
}

DISTRO=$(detect_distro)

# Common pause helper
press_enter_to_close() {
    echo ""
    echo "Press Enter to close..."
    read -r
}

# URL of the official DroidCam Linux client zip.
# Changed from .com to .net — the .com host stopped resolving in 2025-2026.
# And switched from droidcam_latest.zip to versioned droidcam_2.1.5.zip.
DROIDCAM_URL="https://files.dev47apps.net/linux/droidcam_2.1.5.zip"
DROIDCAM_SHA1="ce44abefbadec0a2183837605df23643ca13fb02"

download_droidcam() {
    local outpath="$1"
    echo "▸ Downloading DroidCam client from $DROIDCAM_URL"
    if command -v curl >/dev/null 2>&1; then
        if curl -fSL --connect-timeout 15 --retry 3 --retry-delay 2 \
                -o "$outpath" "$DROIDCAM_URL"; then
            echo "  ✓ Downloaded successfully."
            return 0
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q --tries=3 --timeout=15 \
                -O "$outpath" "$DROIDCAM_URL"; then
            echo "  ✓ Downloaded successfully."
            return 0
        fi
    else
        echo "✗ Neither curl nor wget is installed."
        return 1
    fi
    echo "✗ Failed to download. The DroidCam site may be unreachable."
    echo "  Try manually from: https://www.dev47apps.com/droidcam/linux/"
    return 1
}

verify_droidcam() {
    local outpath="$1"
    if ! command -v sha1sum >/dev/null 2>&1; then
        echo "  ! sha1sum not available — skipping verification."
        return 0
    fi
    local actual
    actual="$(sha1sum "$outpath" | awk '{print $1}')"
    if [ "$actual" = "$DROIDCAM_SHA1" ]; then
        echo "  ✓ SHA1 verified."
        return 0
    fi
    echo "  ✗ SHA1 mismatch (got $actual, expected $DROIDCAM_SHA1)"
    echo "  The downloaded file may be corrupt. Aborting."
    return 1
}

install_from_official_zip() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local zpath="$tmpdir/droidcam.zip"

    download_droidcam "$zpath" || { rm -rf "$tmpdir"; return 1; }
    verify_droidcam "$zpath" || { rm -rf "$tmpdir"; return 1; }

    echo "▸ Extracting..."
    unzip -q -o "$zpath" -d "$tmpdir/droidcam"

    echo "▸ Running install-client (sudo required)..."
    cd "$tmpdir/droidcam"
    sudo ./install-client || {
        echo "✗ install-client failed."
        rm -rf "$tmpdir"
        return 1
    }

    echo ""
    echo "▸ Compiling video module (v4l2loopback-dc) ..."
    sudo ./install-video || {
        echo "  ! install-video failed (this may be expected if you already have v4l2loopback from your distro)."
    }

    echo ""
    echo "▸ Loading audio loopback module ..."
    sudo ./install-sound || {
        echo "  ! install-sound failed (optional — you may already have pipe wire/PulseAudio working)."
    }

    rm -rf "$tmpdir"
    echo ""
    echo "✓ DroidCam installed (official installer)."
    return 0
}

case "$DISTRO" in
    arch)
        echo "▸ Detected: Arch Linux"
        echo ""

        # Find AUR helper
        AUR_HELPER=""
        for helper in yay paru; do
            if command -v "$helper" >/dev/null 2>&1; then
                AUR_HELPER="$helper"
                break
            fi
        done

        if [ -z "$AUR_HELPER" ]; then
            echo "✗ No AUR helper (yay/paru) found."
            echo "  Install one first:"
            echo "    sudo pacman -S --needed base-devel git"
            echo "    git clone https://aur.archlinux.org/yay.git /tmp/yay"
            echo "    cd /tmp/yay && makepkg -si"
            press_enter_to_close
            exit 1
        fi

        echo "▸ Using AUR helper: $AUR_HELPER"
        echo ""
        # The 'droidcam' AUR package bundles the client AND the v4l2loopback-dc
        # kernel module, so this single command covers everything.
        $AUR_HELPER -S --needed droidcam

        # Also install pactl (in pulseaudio-utils) for microphone routing.
        if ! command -v pactl >/dev/null 2>&1; then
            echo ""
            echo "▸ Installing pactl (for microphone routing)..."
            sudo pacman -S --needed --noconfirm pulseaudio-utils || \
                sudo pacman -S --needed --noconfirm pipewire-pulse
        fi

        echo ""
        echo "✓ DroidCam installed (Arch/AUR)."
        ;;

    fedora)
        echo "▸ Detected: Fedora"
        echo ""

        # Enable RPM Fusion free repo (provides akmod-v4l2loopback and
        # other multimedia packages we need).
        if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
            fedora_ver="$(rpm -E %fedora 2>/dev/null || echo '')"
            if [ -n "$fedora_ver" ]; then
                echo "▸ Enabling RPM Fusion free repo (Fedora $fedora_ver)..."
                sudo dnf install -y \
                    "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm" || {
                    echo "  ! Could not enable RPM Fusion. Continuing anyway..."
                }
            fi
        else
            echo "▸ RPM Fusion already enabled."
        fi
        echo ""

        # Install build/runtime deps.
        #   • v4l2loopback-dkms does NOT exist on Fedora — use akmod-v4l2loopback
        #     from RPM Fusion (auto-builds for any kernel).
        #   • android-tools = adb
        #   • libappindicator-gtk3 = systray icon (Ubuntu 21+/Fedora 33+ removed it pre-installed)
        echo "▸ Installing runtime dependencies..."
        sudo dnf install -y --skip-broken \
            akmod-v4l2loopback \
            v4l-utils \
            pulseaudio-utils \
            android-tools \
            ffmpeg \
            alsa-lib \
            libappindicator-gtk3 \
            kernel-devel \
            kernel-headers \
            gcc \
            make \
            curl \
            unzip \
            2>&1 || echo "  ! Some deps failed to install (continuing)."
        echo ""

        # Load the v4l2loopback kernel module now (akmod should have built it
        # against the running kernel during the dnf install above).
        echo "▸ Loading v4l2loopback kernel module..."
        sudo modprobe v4l2loopback || echo "  ! modprobe v4l2loopback failed — you may need to reboot."
        echo "v4l2loopback" | sudo tee /etc/modules-load.d/v4l2loopback.conf >/dev/null 2>&1 || true
        echo ""

        # Install the DroidCam client binary from official zip
        # (it's not packaged in Fedora's repositories; only the kernel module is).
        install_from_official_zip || {
            echo ""
            echo "✗ Installation failed."
            press_enter_to_close
            exit 1
        }
        ;;

    debian)
        echo "▸ Detected: Debian/Ubuntu"
        echo ""

        echo "▸ Installing build deps and pactl..."
        sudo apt update
        sudo apt install -y \
            v4l2loopback-dkms \
            v4l-utils \
            pulseaudio-utils \
            adb \
            ffmpeg \
            libappindicator3-1 \
            libappindicator-gtk3-1 \
            linux-headers-"$(uname -r)" \
            build-essential \
            curl \
            unzip \
            2>&1 || echo "  ! Some deps failed to install (continuing)."
        echo ""

        echo "▸ Loading v4l2loopback kernel module..."
        sudo modprobe v4l2loopback || echo "  ! modprobe failed — you may need to reboot."
        echo ""

        install_from_official_zip || {
            echo ""
            echo "✗ Installation failed."
            press_enter_to_close
            exit 1
        }
        ;;

    *)
        echo "✗ Unsupported distribution."
        echo ""
        echo "Install manually following the docs below:"
        echo "  Arch:    yay -S droidcam v4l2loopback-dkms pulseaudio-utils"
        echo "  Fedora:  sudo dnf install akmod-v4l2loopback v4l-utils pulseaudio-utils"
        echo "           Enable RPM Fusion free, then:"
        echo "           Download from https://www.dev47apps.com/droidcam/linux/"
        echo "  Debian:  sudo apt install v4l2loopback-dkms v4l-utils pulseaudio-utils"
        echo "           Download from https://www.dev47apps.com/droidcam/linux/"
        press_enter_to_close
        exit 1
        ;;
esac

echo ""
echo "═══════════════════════════════════════════════"
echo " Next steps:"
echo "   1. Install DroidCam app on your Android phone"
echo "   2. Open DroidCam on phone, enter IP, connect"
echo "   3. Re-open the Phone panel in ii — cards should"
echo "      now show 'Ready' instead of 'Install'"
echo "═══════════════════════════════════════════════"
press_enter_to_close
