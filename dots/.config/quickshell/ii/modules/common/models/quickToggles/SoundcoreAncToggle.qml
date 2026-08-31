import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions

QuickToggleModel {
    name: Translation.tr("ANC Mode")

    readonly property var activeDevice: EarbudsControlService.activeDevice
    readonly property var noiseData: EarbudsControlService.noiseControl(activeDevice)
    readonly property bool isAvailable: activeDevice !== null && noiseData.available

    // Consider toggled on when not in "off" mode
    toggled: isAvailable && noiseData.currentMode !== "off"

    icon: isAvailable ? noiseData.currentModeIcon : "hearing"

    statusText: isAvailable ? noiseData.currentModeLabel : Translation.tr("Off")

    mainAction: () => {
        if (!activeDevice) return;
        EarbudsControlService.cycleNoiseMode(activeDevice);
    }

    tooltipText: Translation.tr("Cycle ANC Mode")
}
