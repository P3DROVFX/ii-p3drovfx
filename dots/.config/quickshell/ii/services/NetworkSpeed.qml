pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.services

Singleton {
    id: root

    property real downloadSpeed: 0
    property real uploadSpeed: 0
    property real maxSpeed: 100
    property string activeInterface: ""
    property bool monitoring: false

    property real _prevRxBytes: 0
    property real _prevTxBytes: 0
    property bool _hasBaseline: false

    function start(): void {
        root.monitoring = true;
        root.selectInterface();
    }

    function stop(): void {
        root.monitoring = false;
        root.activeInterface = "";
        root.downloadSpeed = 0;
        root.uploadSpeed = 0;
        root._hasBaseline = false;
    }

    function selectInterface(): void {
        const nextInterface = Network.activeInterface ?? "";
        if (root.activeInterface === nextInterface)
            return;
        root.activeInterface = nextInterface;
        root.downloadSpeed = 0;
        root.uploadSpeed = 0;
        root._hasBaseline = false;
        root.readCurrentStats();
    }

    function readCurrentStats(): void {
        if (!root.monitoring || root.activeInterface.length === 0 || readStats.running)
            return;
        readStats.command = [
            "cat",
            "/sys/class/net/" + root.activeInterface + "/statistics/rx_bytes",
            "/sys/class/net/" + root.activeInterface + "/statistics/tx_bytes"
        ];
        readStats.running = true;
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
        running: root.monitoring && root.activeInterface.length > 0
        onTriggered: root.readCurrentStats()
    }

    // read bytes from /sys/class/net/<iface>/statistics/
    Process {
        id: readStats
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split('\n')
                if (lines.length < 2) return
                const rxBytes = parseFloat(lines[0]) || 0
                const txBytes = parseFloat(lines[1]) || 0

                if (root._hasBaseline) {
                    const deltaRx = rxBytes - root._prevRxBytes
                    const deltaTx = txBytes - root._prevTxBytes
                    // Convert bytes/second to Mbps
                    root.downloadSpeed = Math.max(0, (deltaRx * 8) / 1000000)
                    root.uploadSpeed = Math.max(0, (deltaTx * 8) / 1000000)
                    // Adjust max
                    root.maxSpeed = Math.max(root.maxSpeed, root.downloadSpeed, root.uploadSpeed)
                }
                root._prevRxBytes = rxBytes
                root._prevTxBytes = txBytes
                root._hasBaseline = true
            }
        }
    }

    Component.onCompleted: root.selectInterface()
}
