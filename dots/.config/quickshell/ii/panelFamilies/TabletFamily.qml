import QtQuick
import Quickshell
import qs
import qs.services

import qs.modules.common

// ── Tablet-owned surfaces ───────────────────────────────────────────────────
import qs.modules.tablet.appDrawer
import qs.modules.tablet.dock
import qs.modules.tablet.sidebarDashboard

// ── Borrowed from ii, pending a tablet replacement ──────────────────────────
// This import block is the family's debt list. Every entry is a surface the tablet
// still renders with the desktop shell's implementation; each one either gets a
// tablet-native replacement or is dropped. Nothing under modules/tablet/ may import
// qs.modules.ii.* — only this file, so the coupling stays countable in one place.
import qs.modules.ii.alarmRingingPopup
import qs.modules.ii.background
import qs.modules.ii.bar
import qs.modules.ii.bluetoothConnectionPopup
import qs.modules.ii.bluetoothPairing
import qs.modules.ii.localSendPopup
import qs.modules.ii.lock
import qs.modules.ii.mediaControls
import qs.modules.ii.notificationPopup
import qs.modules.ii.oledSaver
import qs.modules.ii.onScreenDisplay
import qs.modules.ii.onScreenDisplay.minimalist
import qs.modules.ii.onScreenKeyboard
import qs.modules.ii.overview
import qs.modules.ii.polkit
import qs.modules.ii.regionSelector
import qs.modules.ii.screenshotOverlay
import qs.modules.ii.screenTranslator
import qs.modules.ii.sessionScreen
import qs.modules.ii.sidebarPolicies
import qs.modules.ii.touchGestures
import qs.modules.ii.wallpaperSelector

/**
 * The tablet panel family: a touch-only shell for tablets and touchscreens.
 *
 * This is deliberately NOT built on the ii family's composition root. Sharing one meant
 * every panel added to the desktop shell appeared on the tablet too, sight unseen, and
 * every panel the tablet did not want had to be switched back off from inside ii. The two
 * shells want different surfaces, so they get one composition root each and the list below
 * is a decision, not an inheritance.
 *
 * What the tablet deliberately does NOT load, and why:
 *
 *   Dock                  — replaced by an Android-style dock built into the home screen.
 *   DynamicIsland         — the bar is a fixed status bar; a notch has no role here.
 *   ScreenCorners         — a corner hot-zone is a pointer affordance. Edges are gestures.
 *   VerticalBar           — the bar is pinned to the top (BarPlacement.familyPinsBarToTop).
 *   WrappedFrame          — desktop chrome around a pointer-driven shell.
 *   TopLayer / Connect    — Connect is a desktop shell mode.
 *   Tiling assistant      — dragging windows into a tiling grid needs a pointer.
 *   ScratchpadOverlay     — desktop window management.
 *   Cheatsheet            — a keyboard-shortcut reference, on a device without a keyboard.
 *   KeypressDisplay       — a screencast helper for keyboards.
 *   KeyboardLayoutPopup   — layout switching belongs to the on-screen keyboard.
 *   Usage overlay         — a desktop diagnostic surface.
 *   Modes / ModeFlash     — desktop automation; revisit once the tablet UI has a home for it.
 *   Overlay               — the game/widget overlay is a desktop surface.
 *   ColorPickerPopup      — a desktop utility.
 *   VideoEditor           — a desktop application.
 */
Scope {
    id: root

    // ── Shell surfaces ──────────────────────────────────────────────────────

    // Always horizontal and always at the top: BarPlacement pins it for the whole family,
    // so there is no vertical counterpart and no placement condition to test.
    //
    // `forceTop` is the only tablet-specific thing about it. An earlier attempt also scaled
    // the bar window up, but every widget inside kept sizing itself off the unscaled
    // Appearance.sizes.barHeight — group backgrounds, hit targets and popup anchors all
    // measured against a bar 22% taller than they thought, and widgets lost their background
    // or vanished. Bar geometry has to be changed in Appearance, not per-window.
    PanelLoader { component: Bar { forceTop: true } }

    PanelLoader {
        extraCondition: Config.options.background.enable
        component: Background {}
    }

    // Still the desktop overview, used as "recents" until the tablet's own lands (Fase 3e).
    // It already scales workspace previews from the available geometry, so it is usable with
    // a finger.
    PanelLoader { component: Overview {} }

    // Every installed app in one searchable grid, and the tablet's replacement for the ii
    // launcher. Swipe up from the bottom edge, or `qs -c ii ipc call appDrawer toggle`.
    //
    // The tool host is injected rather than imported: the panels it hosts (clipboard, emoji,
    // translator, …) live in the ii family, and modules/tablet may not reach across. This
    // file is the one place allowed to, so the borrow happens here and the drawer itself
    // stays family-clean. Without it the drawer is still a complete app drawer, minus tools.
    PanelLoader {
        component: TabletAppDrawer {
            toolHostComponent: searchPanelHostComponent
        }
    }

    Component {
        id: searchPanelHostComponent
        SearchPanelHost {}
    }

    // Pinned apps, what is open, and a door to the drawer — the Pixel Tablet's taskbar.
    // Not the ii dock: see the note in TabletDockWindow on why none of it is reused.
    PanelLoader { component: TabletDock {} }

    // GNOME-like window scale-out during overview. Follows GlobalStates, owns no UI.
    OverviewWindowTransition {}

    PanelLoader { component: TabletSidebarDashboard {} }

    PanelLoader { component: SidebarPolicies {} }

    // ── System surfaces ─────────────────────────────────────────────────────
    PanelLoader { component: Lock {} }
    PanelLoader { component: SessionScreen {} }
    PanelLoader { component: Polkit {} }
    // Kept loaded rather than gated: the Scope decides on its own whether BlueZ
    // is asking anything, and nothing is built until it is.
    PanelLoader { component: BluetoothPairing {} }
    PanelLoader { component: OledSaver {} }

    // ── Feedback ────────────────────────────────────────────────────────────
    PanelLoader { component: NotificationPopup {} }
    PanelLoader {
        extraCondition: !(Config.ready && (Config.options.osd.style === "minimalist" || Config.options.osd.style === "material"))
        component: OnScreenDisplay {}
    }
    PanelLoader {
        extraCondition: Config.ready && (Config.options.osd.style === "minimalist" || Config.options.osd.style === "material")
        component: MinimalistOsd {}
    }
    PanelLoader {
        // Keep the Scope alive so the device-connected trigger can open the popup.
        extraCondition: Config.ready
        component: BluetoothConnectionPopup {}
    }
    PanelLoader {
        extraCondition: AlarmService.ringingAlarmIndex !== -1 && Config.options.time.alarms.useFullscreenPopup
        component: AlarmRingingPopup {}
    }

    // ── Input ───────────────────────────────────────────────────────────────
    // The on-screen keyboard is the only keyboard this family assumes exists.
    PanelLoader { component: OnScreenKeyboard {} }

    readonly property var _touchGestureService: TouchGestureService

    PanelLoader {
        extraCondition: Config.ready && Boolean(Config.options?.interactions?.touchGestures?.enable)
        component: TouchGestures {}
    }

    // Claims the top edge for the shade pull-down. Registering here rather than from
    // inside the service keeps qs.services free of any panel-family dependency; the
    // handler unregisters itself when the family unloads.
    TabletShadeDragHandler {}

    // ── Tools ───────────────────────────────────────────────────────────────
    PanelLoader { component: MediaControls {} }
    PanelLoader { component: RegionSelector {} }
    PanelLoader {
        extraCondition: GlobalStates.screenshotOverlayOpen
        component: ScreenshotOverlay {}
    }
    PanelLoader { component: ScreenTranslator {} }
    PanelLoader { component: WallpaperSelector {} }
    PanelLoader {
        extraCondition: Config.ready && GlobalStates.localSendPopupOpen
        component: LocalSendPopup {}
    }
}
