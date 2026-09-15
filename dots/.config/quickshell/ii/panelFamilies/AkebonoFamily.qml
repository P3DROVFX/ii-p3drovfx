import QtQuick
import QtQuick.Window
import Quickshell

import qs
import qs.services
import qs.modules.common

import qs.modules.akebono.dock
import qs.modules.akebono.overview
import qs.modules.ii.background
import qs.modules.ii.cheatsheet
import qs.modules.akebono.shelf
import qs.modules.akebono.lock
import qs.modules.ii.mediaControls
import qs.modules.ii.notificationPopup
import qs.modules.ii.modes
import qs.modules.akebono.onScreenDisplay
import qs.modules.common.onScreenKeyboard
import qs.modules.ii.polkit
import qs.modules.lunae.screenSnip
import qs.modules.akebono.runner
import qs.modules.ii.screenTranslator
import qs.modules.ii.screenCorners
import qs.modules.ii.sessionScreen
import qs.modules.ii.sidebarLeft
import qs.modules.ii.overlay
import qs.modules.ii.wallpaperSelector
import qs.modules.ii.wrappedFrame
import qs.modules.akebono.setup

Scope {
    PanelLoader { component: Background {} }
    PanelLoader { component: Cheatsheet {} }
    PanelLoader { component: Dock {} }
    PanelLoader { component: Overview {} }
    PanelLoader { component: Shelf {} }
    PanelLoader { component: Lock {} }
    PanelLoader { component: MediaControls {} }
    PanelLoader { component: NotificationPopup {} }
    PanelLoader { component: OnScreenDisplay {} }
    PanelLoader { component: OnScreenKeyboard {} }
    PanelLoader { component: Overlay {} }
    PanelLoader { component: Polkit {} }
    // The Modes & Routines manager behind the mode chip's "Manage" button
    // (GlobalStates.modesOpen), same gating as the bar families.
    PanelLoader {
        extraCondition: Config.options.modes.overlayEnabled
        component: ModesOverlay {}
    }
    PanelLoader { component: LScreenSnip { activeFamily: "akebono" } }
    PanelLoader { component: GlyphPicker {} }
    PanelLoader { component: Runner {} }
    PanelLoader { component: SheetRunner {} }
    PanelLoader { component: ScreenCorners {} }
    PanelLoader { component: ScreenTranslator {} }
    PanelLoader { component: SessionScreen {} }
    PanelLoader { component: SidebarLeft {} }
    PanelLoader { component: WallpaperSelector {} }
    PanelLoader { component: WrappedFrame {} }

    // The Akebono family's native plugin: see modules/akebono/system for what this
    // builds, and why the task-manager surface needs it.
    PanelLoader { component: AkebonoPluginSetup {} }
}