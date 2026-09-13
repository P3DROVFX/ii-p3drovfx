import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell

QuickToggleButton {
    id: root
    buttonIcon: root.toggled ? "keyboard" : "keyboard_off"
    toggled: KeypressService.manualEnabled

    onClicked: KeypressService.toggleManual()

    StyledToolTip {
        text: Translation.tr("Show keystrokes on screen")
    }
}
