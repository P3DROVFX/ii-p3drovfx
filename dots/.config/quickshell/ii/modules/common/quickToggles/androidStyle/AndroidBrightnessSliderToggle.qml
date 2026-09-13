import QtQuick
import Quickshell
import qs.services

AndroidSliderWidgetBase {
    id: root

    property var screen: Brightness.targetScreen
    property var brightnessMonitor: Brightness.getTargetMonitor()

    tooltipText: Translation.tr("Brightness")
    materialSymbol: {
        const val = root.sliderValue;
        if (val <= 0.33) return "brightness_low";
        if (val <= 0.66) return "brightness_medium";
        return "brightness_high";
    }
    sliderValue: brightnessMonitor?.brightness ?? 0
    onMoved: function(value) {
        brightnessMonitor?.setBrightness(value);
    }
}
