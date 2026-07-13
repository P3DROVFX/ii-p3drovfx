import qs.services
import QtQuick
import Quickshell
import qs.modules.ii.onScreenDisplay
import qs.modules.common.widgets

OsdValueIndicator {
    id: kbdBrightnessOsd
    
    icon: "keyboard"
    rotateIcon: false
    scaleIcon: true
    name: Translation.tr("Keyboard Backlight")
    value: KeyboardBacklight.percentage / 100
    shape: MaterialShape.Shape.Hexagon
}
