import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.modules.ii.topLayer.osd
import qs.modules.common.widgets

OsdConnectValueIndicator {
    id: brightnessOsd
    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
    property var brightnessMonitor: Brightness.getMonitorForScreen(focusedScreen)

    icon: {
        if (Hyprsunset.temperatureActive)
            return "routine";
        const val = brightnessOsd.value;
        if (val <= 0.33)
            return "brightness_low";
        if (val <= 0.66)
            return "brightness_medium";
        return "brightness_high";
    }
    rotateIcon: true
    scaleIcon: true
    name: Translation.tr("Brightness")
    value: brightnessOsd.brightnessMonitor?.brightness ?? 0.5
    shape: MaterialShape.Shape.Cookie12Sided

    onValueUpdateRequested: (newValue) => {
        if (brightnessMonitor) {
            brightnessMonitor.setBrightness(newValue);
        }
    }
}
