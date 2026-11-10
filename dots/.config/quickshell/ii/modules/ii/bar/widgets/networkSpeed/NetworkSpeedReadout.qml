import QtQuick
import qs.modules.common
import qs.services

/**
 * What the network speed widgets show, resolved once.
 *
 * Every design (default, capsule, split, graph) reads the same readout so the
 * options — direction, unit, hide-when-offline — behave identically in all of
 * them. It also holds the sampler on `NetworkSpeed` for as long as any widget
 * is alive, by name, so the Wi-Fi dialog closing never stops the bar.
 *
 * A rate is `{ number, unit, compactUnit, active }`. Number and
 * unit stay separate on purpose: `StyledText` picks the numbers font from a
 * regex over its whole text, so "1.2 MB/s" in one label would flip fonts.
 */
QtObject {
    id: root

    readonly property var options: Config.options?.bar?.networkSpeed

    readonly property string mode: root.options?.mode === "download" || root.options?.mode === "upload"
        ? root.options?.mode : "both"
    readonly property bool showDown: root.mode !== "upload"
    readonly property bool showUp: root.mode !== "download"
    readonly property bool showBoth: root.showDown && root.showUp
    readonly property bool bits: root.options?.unit === "bits"
    readonly property bool showUnit: root.options?.showUnit ?? true
    // Tighter margins and gaps in every design. `tight(roomy, snug)` picks one.
    readonly property bool compact: root.options?.compact ?? false

    readonly property bool online: NetworkSpeed.activeInterface.length > 0
    readonly property string interfaceName: NetworkSpeed.activeInterface
    readonly property bool shown: root.online || !(root.options?.hideWhenOffline ?? false)

    readonly property var down: root.rate(NetworkSpeed.downloadBps)
    readonly property var up: root.rate(NetworkSpeed.uploadBps)

    // Bytes per second, newest last — the graph design draws these.
    readonly property var downHistory: NetworkSpeed.downloadHistory
    readonly property var upHistory: NetworkSpeed.uploadHistory

    // Widest strings the layouts reserve room for, so the pill never breathes
    // as the digits change.
    // Compact reserves two digits only: the pill grows when a rate reaches
    // three, instead of always paying for the slot.
    readonly property string numberReference: root.compact ? "99" : "999"
    readonly property string unitReference: root.bits ? "Mbps" : "MB/s"

    readonly property string tooltipText: {
        if (!root.online)
            return Translation.tr("No active network connection");
        let lines = [root.interfaceName];
        if (root.showDown)
            lines.push(Translation.tr("Download %1 %2").arg(root.down.number).arg(root.down.unit));
        if (root.showUp)
            lines.push(Translation.tr("Upload %1 %2").arg(root.up.number).arg(root.up.unit));
        return lines.join("\n");
    }

    function tight(roomy: real, snug: real): real {
        return root.compact ? snug : roomy;
    }

    function rate(bytesPerSecond: real): var {
        const names = root.bits ? ["bps", "Kbps", "Mbps", "Gbps", "Tbps"] : ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"];
        const letters = root.bits ? ["b", "K", "M", "G", "T"] : ["B", "K", "M", "G", "T"];
        const base = root.bits ? 1000 : 1024;
        let value = root.bits ? bytesPerSecond * 8 : bytesPerSecond;
        const active = value >= (root.bits ? 8000 : 1024);
        let step = 0;
        while (value >= 1000 && step < names.length - 1) {
            value /= base;
            step++;
        }
        return {
            number: step === 0 || value >= 10 ? String(Math.round(value)) : value.toFixed(1),
            unit: names[step],
            compactUnit: letters[step],
            active: active
        };
    }

    // Held by name: unique per readout, released with it.
    readonly property string holderName: "bar-widget:" + root

    Component.onCompleted: NetworkSpeed.setHolder(root.holderName, true)
    Component.onDestruction: NetworkSpeed.setHolder(root.holderName, false)
}
