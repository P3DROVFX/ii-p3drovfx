import QtQuick
import Quickshell

import qs.modules.common
import qs.modules.common.panels.shellSwitcher
import qs.modules.common.panels.windowSwitcher
import qs.modules.waffle.actionCenter
import qs.modules.waffle.background
import qs.modules.waffle.bar
import qs.modules.waffle.lock
import qs.modules.waffle.notificationCenter
import qs.modules.waffle.notificationPopup
import qs.modules.waffle.onScreenDisplay
// import qs.modules.waffle.overlay
import qs.modules.waffle.polkit
import qs.modules.waffle.screenSnip
import qs.modules.waffle.startMenu
import qs.modules.waffle.sessionScreen
import qs.modules.waffle.taskView

// Fallbacks
import qs.modules.ii.bluetoothPairing
import qs.modules.ii.cheatsheet
import qs.modules.ii.oledSaver
import qs.modules.ii.keypressDisplay
import qs.modules.common.onScreenKeyboard
import qs.modules.ii.overlay
import qs.modules.ii.screenTranslator
import qs.modules.ii.usage
import qs.modules.ii.modes
import qs.modules.ii.easyEffects
import qs.modules.ii.modeFlashPopup
import qs.modules.ii.wallpaperSelector
import qs.modules.ii.recordingToolbar
import qs.modules.ii.reminderAlertPopup
import qs.services

Scope {
    PanelLoader { component: RecordingToolbar {} }
    PanelLoader { component: WaffleActionCenter {} }
    PanelLoader { component: WaffleBar {} }
    PanelLoader { component: WaffleBackground {} }
    PanelLoader { component: WaffleLock {} }
    PanelLoader { component: WaffleNotificationCenter {} }
    PanelLoader { component: WaffleNotificationPopup {} }
    PanelLoader { component: WaffleOSD {} }
    // PanelLoader { component: WaffleOverlay {} }
    PanelLoader { component: WafflePolkit {} }
    PanelLoader { component: WScreenSnip {} }
    PanelLoader { component: WaffleStartMenu {} }
    PanelLoader { component: WaffleSessionScreen {} }
    // See TabletFamily: the chooser is loaded by every family on purpose.
    PanelLoader { component: ShellSwitcher {} }
    // Alt+Tab; always loaded so its binds can be taken away when the setting goes off.
    PanelLoader { component: WindowSwitcherPanel {} }
    PanelLoader { component: WaffleTaskView {} }

    PanelLoader { component: BluetoothPairing {} }
    PanelLoader { component: Cheatsheet {} }
    PanelLoader { component: OledSaver {} }
    PanelLoader { component: KeypressDisplay {} }
    PanelLoader { component: OnScreenKeyboard {} }
    PanelLoader { component: Overlay {} }
    PanelLoader { component: ScreenTranslator {} }
    PanelLoader {
        extraCondition: Config.options.appStats.overlayEnabled
        component: UsageApp {}
    }
    PanelLoader {
        extraCondition: Config.options.modes.overlayEnabled
        component: ModesApp {}
    }
    PanelLoader { component: EasyEffectsApp {} }
    PanelLoader {
        extraCondition: Config.ready
        component: ModeFlashPopup {}
    }
    PanelLoader { component: WallpaperSelector {} }
    PanelLoader {
        extraCondition: RemindersService.ringingId.length > 0
        component: ReminderAlertPopup {}
    }
}
