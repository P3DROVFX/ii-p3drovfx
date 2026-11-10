pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.services

/**
 * Throughput of the active network interface, sampled once a second from
 * /proc/net/dev (one FileView reload, no child process).
 *
 * Two kinds of consumer share the sampler:
 *  - the Wi-Fi dialog, through start()/stop();
 *  - the bar widget, through setHolder(), which is reference-counted by name so
 *    that closing the dialog never stops the bar's readout and vice versa.
 *
 * `downloadSpeed`/`uploadSpeed` are in Mbps (what the dialog shows); the bar
 * widget reads bytes per second and the short history used by its graph.
 */
Singleton {
    id: root

    property real downloadSpeed: 0
    property real uploadSpeed: 0
    property real maxSpeed: 100
    property real downloadBps: 0
    property real uploadBps: 0
    property string activeInterface: ""
    property bool monitoring: false

    // Newest sample last. Replaced, never mutated, so bindings re-evaluate.
    readonly property int historyLength: 24
    property var downloadHistory: []
    property var uploadHistory: []

    property var _holders: ({})
    property int holderCount: 0
    readonly property bool polling: root.monitoring || root.holderCount > 0

    property real _prevRxBytes: 0
    property real _prevTxBytes: 0
    property real _prevStamp: 0
    property bool _hasBaseline: false

    function start(): void {
        root.monitoring = true;
    }

    function stop(): void {
        root.monitoring = false;
    }

    function setHolder(name: string, held: bool): void {
        const next = Object.assign({}, root._holders);
        if (held)
            next[name] = true;
        else
            delete next[name];
        root._holders = next;
        root.holderCount = Object.keys(next).length;
    }

    function _resetSamples(): void {
        root.downloadSpeed = 0;
        root.uploadSpeed = 0;
        root.downloadBps = 0;
        root.uploadBps = 0;
        root.downloadHistory = [];
        root.uploadHistory = [];
        root._hasBaseline = false;
    }

    onPollingChanged: {
        if (root.polling) {
            root.selectInterface();
        } else {
            root.activeInterface = "";
            root._resetSamples();
        }
    }

    function selectInterface(): void {
        if (!root.polling)
            return;
        const nextInterface = Network.activeInterface ?? "";
        if (root.activeInterface === nextInterface)
            return;
        root.activeInterface = nextInterface;
        root._resetSamples();
        root.readCurrentStats();
    }

    function readCurrentStats(): void {
        if (!root.polling || root.activeInterface.length === 0)
            return;
        netDev.reload();
    }

    function _push(history: var, value: real): var {
        const next = history.length >= root.historyLength ? history.slice(1) : history.slice();
        next.push(value);
        return next;
    }

    // `iface: rx_bytes packets errs drop fifo frame compressed multicast tx_bytes …`
    function _consume(text: string): void {
        const lines = text.split("\n");
        const prefix = root.activeInterface + ":";
        for (let i = 2; i < lines.length; i++) {
            const line = lines[i].trim();
            if (!line.startsWith(prefix))
                continue;
            const fields = line.slice(prefix.length).trim().split(/\s+/);
            const rxBytes = parseFloat(fields[0]) || 0;
            const txBytes = parseFloat(fields[8]) || 0;
            const now = Date.now();

            if (root._hasBaseline) {
                const seconds = Math.max(0.2, (now - root._prevStamp) / 1000);
                const rx = Math.max(0, (rxBytes - root._prevRxBytes) / seconds);
                const tx = Math.max(0, (txBytes - root._prevTxBytes) / seconds);
                root.downloadBps = rx;
                root.uploadBps = tx;
                root.downloadSpeed = rx * 8 / 1000000;
                root.uploadSpeed = tx * 8 / 1000000;
                root.maxSpeed = Math.max(root.maxSpeed, root.downloadSpeed, root.uploadSpeed);
                root.downloadHistory = root._push(root.downloadHistory, rx);
                root.uploadHistory = root._push(root.uploadHistory, tx);
            }
            root._prevRxBytes = rxBytes;
            root._prevTxBytes = txBytes;
            root._prevStamp = now;
            root._hasBaseline = true;
            return;
        }
    }

    Connections {
        target: Network

        function onActiveInterfaceChanged(): void {
            root.selectInterface();
        }
    }

    Timer {
        id: pollTimer
        interval: 1000
        repeat: true
        running: root.polling && root.activeInterface.length > 0
        onTriggered: root.readCurrentStats()
    }

    // reload() completes asynchronously — the sample is taken in onLoaded, not
    // right after the call, which would return the previous second's text.
    FileView {
        id: netDev
        path: "/proc/net/dev"
        onLoaded: root._consume(netDev.text())
    }

    Component.onCompleted: root.selectInterface()
}
