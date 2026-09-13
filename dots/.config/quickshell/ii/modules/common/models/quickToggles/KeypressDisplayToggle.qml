import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Keystrokes")
    toggled: KeypressService.manualEnabled
    icon: toggled ? "keyboard" : "keyboard_off"

    mainAction: () => {
        KeypressService.toggleManual()
    }

    tooltipText: Translation.tr("Show the keys you press on screen")
}
