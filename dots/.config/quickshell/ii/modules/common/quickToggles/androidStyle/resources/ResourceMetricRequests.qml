pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Holds ResourceUsage's demand-driven monitoring requests for a tile.
 *
 * CPU and RAM are always sampled; temperature, disk, swap, the hardware identity and the
 * GPU are only polled while somebody asks for them (see services/ResourceUsage.qml). A
 * a quick toggle is built and destroyed every time the island expands and collapses, and
 * it is also built in the tray, so the requests have to follow the tile's life exactly:
 * taken while it is live on a grid, released when it is destroyed or drawn in the tray.
 * The island dashboard, however, is built once and kept - so placement alone is not
 * presence, and the gate is the tile's *effective* visibility (`shownOnScreen`).
 *
 *     ResourceMetricRequests {
 *         active: root.shownOnScreen
 *         metrics: ({ temperature: true, disk: root.showsDisk })
 *         gpu: root.showsGpu
 *     }
 */
Item {
    id: root

    /** Nothing is requested while this is false. */
    property bool active: false
    /** Which ResourceUsage.requestMetric() metrics this tile needs, by name. */
    property var metrics: ({})
    /** GPU sampling (its own refcount in the service). */
    property bool gpu: false

    readonly property var metricNames: ["temperature", "disk", "swap", "hardwareIdentity", "history"]

    // What is currently held, so a change only ever moves the refcount by one.
    property var heldMetrics: ({})
    property bool heldGpu: false

    visible: false
    width: 0
    height: 0

    function sync(): void {
        for (let i = 0; i < root.metricNames.length; i++) {
            const name = root.metricNames[i];
            const want = root.active && !!(root.metrics?.[name] ?? false);
            if (!!root.heldMetrics[name] === want)
                continue;
            ResourceUsage.requestMetric(name, want);
            root.heldMetrics[name] = want;
        }

        const wantGpu = root.active && root.gpu;
        if (wantGpu !== root.heldGpu) {
            ResourceUsage.requestGpuMonitoring(wantGpu);
            root.heldGpu = wantGpu;
        }
    }

    function release(): void {
        for (let i = 0; i < root.metricNames.length; i++) {
            const name = root.metricNames[i];
            if (!root.heldMetrics[name])
                continue;
            ResourceUsage.requestMetric(name, false);
            root.heldMetrics[name] = false;
        }
        if (root.heldGpu) {
            ResourceUsage.requestGpuMonitoring(false);
            root.heldGpu = false;
        }
    }

    onActiveChanged: root.sync()
    onMetricsChanged: root.sync()
    onGpuChanged: root.sync()

    Component.onCompleted: root.sync()
    Component.onDestruction: root.release()
}
