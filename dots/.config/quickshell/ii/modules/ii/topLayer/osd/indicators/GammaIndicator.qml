import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.modules.ii.topLayer.osd

OsdConnectValueIndicator {
    id: rotateIcon

    icon: "wb_twilight"
    name: Translation.tr("Gamma")
    from: Hyprsunset.gammaLowerLimit / 100
    value: Hyprsunset.gamma / 100 ?? 0.5

    onValueUpdateRequested: (newValue) => {
        Hyprsunset.setGamma(Math.round(newValue * 100));
    }
}
