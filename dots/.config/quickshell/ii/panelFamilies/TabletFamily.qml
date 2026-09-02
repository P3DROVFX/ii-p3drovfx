import QtQuick
import Quickshell
import qs
import qs.services

import qs.modules.common

// ── Tablet-owned surfaces ───────────────────────────────────────────────────
import qs.modules.tablet.appDrawer
import qs.modules.tablet.appWindow
import qs.modules.tablet.dock
import qs.modules.tablet.homeScreen
import qs.modules.tablet.navigation
import qs.modules.tablet.recents
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
import qs.modules.ii.modes
import qs.modules.ii.usage
import qs.modules.ii.notificationPopup
import qs.modules.ii.oledSaver
import qs.modules.ii.onScreenDisplay
import qs.modules.ii.onScreenDisplay.minimalist
import qs.modules.common.onScreenKeyboard
import qs.modules.ii.overview
import qs.modules.ii.polkit
import qs.modules.ii.regionSelector
import qs.modules.ii.screenshotOverlay
import qs.modules.ii.screenTranslator
import qs.modules.ii.cheatsheet
import qs.modules.ii.cheatsheet.commands
import qs.modules.ii.scratchpadOverlay
import qs.modules.ii.sessionScreen
import qs.modules.ii.videoEditor
import qs.modules.ii.sidebarPolicies
import qs.modules.ii.sidebarPolicies.phone
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
 *   ii Dock               — replaced by modules/tablet/dock, an Android-style taskbar.
 *   SidebarPolicies       — the window, not the content: each policy is a normal tablet app
 *                           window on its own workspace instead of a 460px sidebar.
 *   ii Overview           — replaced by modules/tablet/recents. The overview is a grid of
 *                           workspaces answering "where is everything"; recents is a flat
 *                           most-recent-first list answering "what was I just doing".
 *                           Android keeps the two apart, and here the workspaces ARE the
 *                           home screens, so only the second surface is needed.
 *                           OverviewWindowTransition goes with it: nothing drives
 *                           GlobalStates.overviewOpen in this family any more.
 *                           The module is still imported for SearchPanelHost, which the
 *                           app drawer borrows to host tool panels.
 *   DynamicIsland         — the bar is a fixed status bar; a notch has no role here.
 *   ScreenCorners         — a corner hot-zone is a pointer affordance. Edges are gestures.
 *   VerticalBar           — the bar is pinned to the top (BarPlacement.familyPinsBarToTop).
 *   WrappedFrame          — desktop chrome around a pointer-driven shell.
 *   TopLayer / Connect    — Connect is a desktop shell mode.
 *   Tiling assistant      — dragging windows into a tiling grid needs a pointer.
 *   KeypressDisplay       — a screencast helper for keyboards.
 *   KeyboardLayoutPopup   — layout switching belongs to the on-screen keyboard.
 *   ModeFlashPopup        — the mode banner; the island drew it and there is no island.
 *   Overlay               — the game/widget overlay is a desktop surface.
 *   ColorPickerPopup      — a desktop utility.
 */
Scope {
    id: root

    // Owns stable Hyprland IPC target names whose actions differ from ii. In particular,
    // Super opens the app drawer rather than the desktop Overview.
    TabletSystemKeybinds {}

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

    // The wallpaper, the desktop widgets, and — injected onto the same canvas — this
    // family's home-screen app icons.
    //
    // The icons ride the widget canvas rather than a surface of their own. That surface
    // owns the whole screen's input region on the Bottom layer, so anything underneath it
    // renders but can never be touched; sharing the canvas also puts icons and widgets on
    // one grid, which is what D4 asked for.
    PanelLoader {
        extraCondition: Config.options.background.enable
        component: Background {
            widgetCanvasOverlay: tabletHomeIconsComponent
        }
    }

    Component {
        id: tabletHomeIconsComponent
        TabletHomeIconsLayer {}
    }

    // The swipe that moves between workspaces. The workspaces are this family's home screens.
    PanelLoader { component: TabletHomeScreen {} }

    // What was I just doing: every open window as a card, most recent first. Distinct from
    // the workspaces, which are this family's home screens.
    PanelLoader { component: TabletRecents {} }

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
            // Long-pressing an app in the drawer puts it on the current home screen. The
            // drawer raises the event and the home screen owns the store; neither knows
            // about the other, so the wiring lives here.
            onAppHeld: appId => {
                // Not necessarily the workspace in front of you: the drawer opens from
                // anywhere here, and an icon dropped behind a full workspace is invisible.
                const workspace = TabletHomeIcons.addTargetWorkspace;
                const slot = TabletHomeIcons.nextFreeSlot(workspace, 8);
                TabletHomeIcons.add(workspace, appId, slot.x, slot.y);
            }
        }
    }

    Component {
        id: searchPanelHostComponent
        SearchPanelHost {}
    }

    // ── Shell surfaces presented as apps (D6) ───────────────────────────────
    // Listed in the drawer next to real applications. All standalone ii content is injected
    // into TabletAppWindow, which is a normal Hyprland client rather than an overlay.
    //
    // The content components are ii's, so the borrow happens here rather than inside
    // modules/tablet, exactly like the drawer's tool host.
    PanelLoader { component: TabletAppWindows {} }

    Component {
        id: usageAppContent
        UsageContent {}
    }

    Component {
        id: modesAppContent
        ModesContent {}
    }

    // Cheatsheet entries are application pages, not tabs in a legacy overlay. Keeping each
    // source component here preserves the one-way family dependency: `modules/tablet` never
    // imports ii; its composition root owns this deliberate borrow.
    Component { id: timetableAppContent; CheatsheetTimetable {} }
    Component { id: keybindsAppContent; CheatsheetKeybinds {} }
    Component { id: elementsAppContent; CheatsheetPeriodicTable {} }
    Component { id: aminoAcidsAppContent; CheatsheetAminoAcids {} }
    Component { id: commandsAppContent; CheatsheetCommands {} }
    Component { id: workspacesAppContent; CheatsheetWorkspaces {} }
    Component { id: emailAppContent; CheatsheetEmail {} }
    Component { id: typingTestAppContent; CheatsheetTypingTest {} }

    // The policies tabs, each as its own app. They are plain standalone types in ii — the
    // tab bar around them was only there because they shared one narrow sidebar — so with a
    // whole screen each they need no wrapper at all.
    Component { id: policiesIntelligence; AiChat {} }
    Component { id: policiesTranslator; Translator {} }
    Component { id: policiesMedia; SidebarPlayerControl {} }
    Component { id: policiesWallpapers; WallpaperBrowserUI {} }
    Component { id: policiesAnime; Anime {} }
    Component { id: policiesPhone; Phone {} }

    Component.onCompleted: TabletSystemApps.hostedContent = {
        "usage": usageAppContent,
        "modes": modesAppContent,
        "timetable": timetableAppContent,
        "keybinds": keybindsAppContent,
        "elements": elementsAppContent,
        "aminoAcids": aminoAcidsAppContent,
        "commands": commandsAppContent,
        "workspaces": workspacesAppContent,
        "email": emailAppContent,
        "typingTest": typingTestAppContent,
        "policies.intelligence": policiesIntelligence,
        "policies.translator": policiesTranslator,
        "policies.media": policiesMedia,
        "policies.wallpapers": policiesWallpapers,
        "policies.anime": policiesAnime,
        "policies.phone": policiesPhone
    }

    // The left edge opens policies as an app rather than as a sidebar, so it has to claim
    // the drag — otherwise the same swipe would also fire the user's leftEdge binding.
    TabletPoliciesDragHandler {}

    PanelLoader {
        extraCondition: GlobalStates.videoEditorOpen
        component: VideoEditor {}
    }
    PanelLoader { component: ScratchpadOverlay {} }

    // Pinned apps, what is open, and a door to the drawer — the Pixel Tablet's taskbar.
    // Not the ii dock: see the note in TabletDockWindow on why none of it is reused.
    PanelLoader { component: TabletDock {} }

    PanelLoader { component: TabletSidebarDashboard {} }



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
