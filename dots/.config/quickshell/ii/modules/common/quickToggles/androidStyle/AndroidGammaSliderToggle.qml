import QtQuick
import Quickshell
import qs.services
import Quickshell.Hyprland

AndroidSliderWidgetBase {
    id: root

    property var screen: Brightness.targetScreen
    property var brightnessMonitor: Brightness.getTargetMonitor()

    property bool gammaDimming: Brightness.gammaDimming

    tooltipText: root.gammaDimming ? Translation.tr("Gamma / Brightness") : Translation.tr("Brightness")
    materialSymbol: "light_mode"
    secondaryMaterialSymbol: root.gammaDimming ? "wb_twilight" : ""

    sliderValue: {
        if (!root.gammaDimming)
            return root.brightnessMonitor?.brightness ?? 0;
        return Hyprsunset.gamma === 100 ? 0.3 + (root.brightnessMonitor?.brightness ?? 0) * 0.7 : (Hyprsunset.gamma - Hyprsunset.gammaLowerLimit) / (100 - Hyprsunset.gammaLowerLimit) * 0.3;
    }
    onMoved: function (v) {
        if (!root.gammaDimming) {
            root.brightnessMonitor?.setBrightness(v);
            return;
        }
        if (v >= 0.3) {
            // 0.3 - 1.0 brightness
            root.brightnessMonitor?.setBrightness((v - 0.3) / 0.7);
            if (Hyprsunset.gamma !== 100) {
                Hyprsunset.setGamma(100);
            }
        } else {
            // 0 - 0.3 gamma
            if (root.brightnessMonitor && root.brightnessMonitor.brightness !== 0) {
                root.brightnessMonitor.setBrightness(0);
            }
            Hyprsunset.setGamma((v / 0.3 * (100 - Hyprsunset.gammaLowerLimit) + Hyprsunset.gammaLowerLimit));
        }
    }
}
