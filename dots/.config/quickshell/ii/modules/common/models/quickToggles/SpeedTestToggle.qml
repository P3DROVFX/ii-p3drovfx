import QtQuick
import qs
import qs.services
import qs.modules.common

/**
 * Runs a speed test from the dashboard: tap to start or cancel. While it runs, the
 * island's background-jobs activity follows it; afterwards the tile keeps the result.
 */
QuickToggleModel {
    id: root

    readonly property var result: SpeedTestService.lastResult

    name: Translation.tr("Speed test")
    toggled: SpeedTestService.running
    icon: "speed"
    statusText: {
        if (SpeedTestService.running)
            return Translation.tr("Testing… %1%").arg(Math.round(SpeedTestService.progress * 100));
        if (SpeedTestService.phase === "error")
            return Translation.tr("Failed");
        if (root.result)
            return "↓ " + SpeedTestService.formatSpeed(root.result.downloadAvg);
        return Translation.tr("Tap to test");
    }
    tooltipText: Translation.tr("Test the connection's speed")

    mainAction: () => {
        if (SpeedTestService.running)
            SpeedTestService.cancelTest();
        else
            SpeedTestService.startTest();
    }
}
