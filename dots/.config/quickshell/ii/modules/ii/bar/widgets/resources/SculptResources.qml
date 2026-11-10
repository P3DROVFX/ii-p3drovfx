pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.ii.bar.popups.resources
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Sculpt system monitor — three type-led readings of the machine's load,
 * chosen in the widget's page (`bar.resources.sculptVariant`):
 *
 *   pressure   every number is set under the load it reports: an idle metric
 *              light and wide, a busy one black and condensed — the type
 *              itself looks pressed. A caption in spaced capitals names it.
 *   bars       a tiny week-chart: one rounded bar per metric, the highest one in
 *              the vivid tone with a burst on top, and that metric's number
 *              read out beside the chart
 *   trace      a card per metric with its recent history drawn behind the
 *              number, cropped by the card, like a ticker
 *
 * Which metrics show comes from the widget's page (CPU, RAM, temperature,
 * disk, swap). Over a metric's warning threshold it turns to the error colour.
 */
Item {
    id: root

    property bool vertical: false

    readonly property string variant: Config.options.bar.resources.sculptVariant ?? "pressure"
    readonly property real thickness: root.vertical
        ? Appearance.sizes.verticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8
    readonly property int contentRotation: root.vertical
        ? (Config.options.bar.bottom ? 90 : -90)
        : 0
    property bool popupActive: false

    BarWidgetPalette {
        id: monitorTones
        colorMode: Config.options.bar.resources.colorMode ?? "primary"
    }

    // ── Optional metrics are only sampled while something shows them ─────────
    property bool _temperatureMetricRequested: false
    property bool _diskMetricRequested: false
    property bool _swapMetricRequested: false
    function syncMetricRequests() {
        const resources = Config.options.bar.resources;
        const wantTemperature = !!resources.alwaysShowCpuTemp;
        const wantDisk = !!resources.alwaysShowDisk;
        const wantSwap = !!resources.alwaysShowSwap;
        if (root._temperatureMetricRequested !== wantTemperature) {
            ResourceUsage.requestMetric("temperature", wantTemperature);
            root._temperatureMetricRequested = wantTemperature;
        }
        if (root._diskMetricRequested !== wantDisk) {
            ResourceUsage.requestMetric("disk", wantDisk);
            root._diskMetricRequested = wantDisk;
        }
        if (root._swapMetricRequested !== wantSwap) {
            ResourceUsage.requestMetric("swap", wantSwap);
            root._swapMetricRequested = wantSwap;
        }
    }
    Component.onCompleted: root.syncMetricRequests()
    Component.onDestruction: {
        if (root._temperatureMetricRequested)
            ResourceUsage.requestMetric("temperature", false);
        if (root._diskMetricRequested)
            ResourceUsage.requestMetric("disk", false);
        if (root._swapMetricRequested)
            ResourceUsage.requestMetric("swap", false);
    }
    Connections {
        target: Config.options.bar.resources
        function onAlwaysShowCpuTempChanged() { root.syncMetricRequests(); }
        function onAlwaysShowDiskChanged() { root.syncMetricRequests(); }
        function onAlwaysShowSwapChanged() { root.syncMetricRequests(); }
    }

    // ── The metrics ──────────────────────────────────────────────────────────
    // `keys` changes only with the page's switches; values are read per metric
    // through `metricFor`, so the cells are not rebuilt on every sample.
    // Plain rather than readonly so a preview can hand in metrics.
    property var keys: {
        const resources = Config.options.bar.resources;
        const list = [];
        if (resources.alwaysShowCpu)
            list.push("cpu");
        if (resources.alwaysShowRam)
            list.push("ram");
        if (resources.alwaysShowCpuTemp)
            list.push("temp");
        if (resources.alwaysShowDisk)
            list.push("disk");
        if (resources.alwaysShowSwap)
            list.push("swap");
        return list;
    }

    property var metricFor: function (key) {
        const resources = Config.options.bar.resources;
        const percent = (value, threshold, label, icon, history) => ({
            label: label,
            icon: icon,
            value: Math.max(0, Math.min(1, value)),
            text: String(Math.round(value * 100)),
            unit: "%",
            warn: value * 100 >= threshold,
            history: history
        });
        if (key === "cpu")
            return percent(ResourceUsage.cpuUsage, resources.cpuWarningThreshold, Translation.tr("CPU"), "memory", ResourceUsage.cpuUsageHistory);
        if (key === "ram")
            return percent(ResourceUsage.memoryUsedPercentage, resources.memoryWarningThreshold, Translation.tr("RAM"), "memory_alt", ResourceUsage.memoryUsageHistory);
        if (key === "disk")
            return percent(ResourceUsage.diskUsedPercentage, 90, Translation.tr("Disk"), "hard_drive", []);
        if (key === "swap")
            return percent(ResourceUsage.swapUsedPercentage, resources.swapWarningThreshold, Translation.tr("Swap"), "swap_horiz", ResourceUsage.swapUsageHistory);
        const celsius = Number(ResourceUsage.cpuTemp) || 0;
        return {
            label: Translation.tr("Temp"),
            icon: "thermostat",
            value: Math.max(0, Math.min(1, celsius / 100)),
            text: String(Math.round(celsius)),
            unit: "°",
            warn: celsius >= 80,
            history: []
        };
    }

    // `bars` is drawn horizontally and turned on a vertical bar; the other two
    // stack their cells instead.
    readonly property bool turned: root.vertical && root.variant === "bars"
    readonly property real flatWidth: variantLoader.item?.implicitWidth ?? 0
    readonly property real flatHeight: variantLoader.item?.implicitHeight ?? 0

    visible: root.keys.length > 0
    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : root.flatWidth
    implicitHeight: root.vertical ? (root.turned ? root.flatWidth : root.flatHeight) : Appearance.sizes.baseBarHeight

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }
    Behavior on implicitHeight {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: !BarInteraction.clickToShow
    }

    Loader {
        id: variantLoader
        anchors.centerIn: parent
        rotation: root.turned ? root.contentRotation : 0
        sourceComponent: root.variant === "bars"
            ? barsVariant
            : root.variant === "trace" ? traceVariant : pressureVariant
    }

    Component {
        id: pressureVariant
        SculptResourcesPressure {
            vertical: root.vertical
            thickness: root.thickness
            tones: monitorTones
            hovered: hoverArea.containsMouse
            keys: root.keys
            metricFor: root.metricFor
        }
    }

    Component {
        id: barsVariant
        SculptResourcesBars {
            thickness: root.thickness
            tones: monitorTones
            hovered: hoverArea.containsMouse
            keys: root.keys
            metricFor: root.metricFor
        }
    }

    Component {
        id: traceVariant
        SculptResourcesTrace {
            vertical: root.vertical
            thickness: root.thickness
            tones: monitorTones
            hovered: hoverArea.containsMouse
            keys: root.keys
            metricFor: root.metricFor
        }
    }

    // Lazy: popup controller is only built on approach (same as ExpressiveSports).
    Loader {
        active: BarInteraction.enablePopups
            && (BarInteraction.clickToShow || hoverArea.containsMouse || root.popupActive)
        sourceComponent: ExpressiveResourcesPopup {
            hoverTarget: hoverArea
            onActiveChanged: root.popupActive = active
            Component.onDestruction: root.popupActive = false
        }
    }
}
