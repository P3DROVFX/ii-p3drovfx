import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell

QuickToggleButton {
    id: root
    buttonIcon: root.toggled ? "keyboard_off" : "keyboard"
    toggled: LaptopKeyboardService.disabled

    onClicked: LaptopKeyboardService.toggle()

    StyledToolTip {
        text: root.toggled ? Translation.tr("Built-in keyboard disabled | Click to enable") : Translation.tr(
                                 "Disable built-in laptop keyboard")
    }
}
