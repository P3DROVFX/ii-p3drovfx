import qs.services
import QtQuick
import Quickshell
import qs.modules.ii.topLayer.osd
import qs.modules.common.widgets

OsdConnectValueIndicator {
    id: kbdBrightnessOsd

    icon: "keyboard"
    rotateIcon: false
    scaleIcon: true
    name: Translation.tr("Keyboard Backlight")
    value: KeyboardBacklight.percentage / 100
    shape: MaterialShape.Shape.Hexagon
    useProgressBar: true
    stepCount: KeyboardBacklight.levels

    onValueUpdateRequested: (newValue) => {
        if (KeyboardBacklight.available && KeyboardBacklight.ready) {
            const step = Math.round(newValue * KeyboardBacklight.maxValue);
            KeyboardBacklight.setValue(step);
        }
    }
}
