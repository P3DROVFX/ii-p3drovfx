// Full game mode: the entry point scripts/gameMode/swap.sh starts in place of shell.qml.
// Only the game overlay, the polkit agent and a hyprlock fallback for locking run here;
// see services/FullGameMode.qml. Leaving goes back through the overlay or a shell restart.
//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
// Qt allocates a depth-stencil renderbuffer per window (and per layer) for 2D opaque batching. The rendered
// output is identical without it; it only trades a little GPU time on heavy overdraw for ~20 MB per
// fullscreen window on HiDPI.
//@ pragma Env QSG_NO_DEPTH_BUFFER=1
// Qt sizes each window's texture atlas to the next power of two over the window, so every
// full-screen layer (background, desktop widgets, island, overview transition) got a
// 2048x2048 RGBA atlas (16 MB of VRAM) the moment it showed its first small image. The atlas
// only batches small images; 1024x1024 holds everything up to 512 px and costs 4 MB.
//@ pragma Env QSG_ATLAS_WIDTH=1024
//@ pragma Env QSG_ATLAS_HEIGHT=1024
//@ pragma Env MALLOC_CONF=dirty_decay_ms:1000,muzzy_decay_ms:1000,background_thread:true
// FFmpeg's hardware decoders on NVIDIA create a CUDA context on the first sound of a session
// (~40 MB that is never released). The shell only plays short sounds and two optional videos
// (lock screen wallpaper, video editor preview), so software decoding is enough.
//@ pragma Env QT_FFMPEG_DECODING_HW_DEVICE_TYPES=
//@ pragma Env QT_FFMPEG_ENCODING_HW_DEVICE_TYPES=
// Qt falls back to the basic render loop on NVIDIA's Wayland EGL, which renders every window in
// turn on the GUI thread. When the GPU has clocked down after a while idle, the driver spin-waits
// there for 50-200 ms and every GUI-driven animation (the overview's opening zoom first) jumps.
// Threaded gives each window its own render thread and keeps the GUI thread's clock at 120 Hz.
//@ pragma Env QSG_RENDER_LOOP=threaded

import "modules/common"
import "services"
import qs.modules.ii.overlay
import qs.modules.ii.polkit

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

ShellRoot {
    id: root

    Component.onCompleted: {
        FullGameMode.running = true;
        MaterialThemeLoader.reapplyTheme();
    }

    LazyLoader {
        active: Config.ready
        component: Overlay {}
    }

    LazyLoader {
        active: Config.ready
        component: Polkit {}
    }

    // The shell's lock screen is gone, but hypridle (lock_cmd) and Super+L still end in
    // this global shortcut while any qs runs.
    GlobalShortcut {
        name: "lock"
        description: "Locks the screen with hyprlock while in game mode"
        onPressed: Quickshell.execDetached(["sh", "-c", "pidof hyprlock || hyprlock"])
    }

    IpcHandler {
        target: "gameMode"

        function exit(): void {
            FullGameMode.exit();
        }
    }
}
