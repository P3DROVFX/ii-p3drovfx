import qs.modules.common.widgets
import qs.modules.common
import qs.services
import QtQuick

QuickToggleButton {
    id: root
    toggled: KeyboardBacklight.available && KeyboardBacklight.currentValue > 0
    buttonIcon: {
        if (!KeyboardBacklight.available) return "keyboard_hide"
        if (KeyboardBacklight.currentValue === 0) return "backlight_high_off"
        if (KeyboardBacklight.maxValue <= 2) {
            return KeyboardBacklight.currentValue === 1 ? "backlight_high" : "brightness_6"
        }
        return "brightness_6"
    }
    onClicked: {
        KeyboardBacklight.cycleNext()
    }
    StyledToolTip {
        text: Translation.tr("Keyboard Light") + ": " + KeyboardBacklight.levelText
    }
}
