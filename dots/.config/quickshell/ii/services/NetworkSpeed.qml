pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common

Singleton {
    id: root

    // Global network throughput aggregated over every interface except the
    // loopback device, sampled from /proc/net/dev.
    property real downloadBytesPerSecond: 0
    property real uploadBytesPerSecond: 0
    // Session totals. Backed by Persistent so they survive shell reloads and
    // restarts; the stored boot id resets them when the machine reboots.
    property real downloadedBytes: 0
    property real uploadedBytes: 0
    // Human readable list of the interfaces included in the sample, like "wlan0, enp3s0"
    property string activeInterfaces: ""
    property bool monitoring: false

    property real _previousReceivedBytes: -1
    property real _previousTransmittedBytes: -1
    property double _previousSampleTime: 0
    // Totals are flushed to Persistent at most this often to avoid a states.json
    // write on every poll tick.
    property int _persistIntervalMs: 5000
    property bool _restored: false

    // Refcounting so polling only runs while a surface actually displays the data
    property int _subscribers: 0

    Component.onCompleted: {
        // Restore session totals collected by earlier shell generations in
        // this boot. Done lazily here because Persistent.ready gates its own
        // file load; reading before it lands would clobber stored values.
        Qt.callLater(restoreTotals);
    }

    function restoreTotals(): void {
        if (_restored)
            return;
        _restored = true;
        if (!Persistent.ready) {
            Qt.callLater(restoreTotals);
            return;
        }
        const stored = Persistent.states.networkUsage;
        if (stored.bootId === _bootId) {
            downloadedBytes = stored.downloadedBytes ?? 0;
            uploadedBytes = stored.uploadedBytes ?? 0;
        } else {
            // New boot: start fresh and stamp it so later reloads keep going
            stored.downloadedBytes = 0;
            stored.uploadedBytes = 0;
            stored.bootId = _bootId;
        }
    }

    function persistTotals(): void {
        if (!_restored)
            return;
        const stored = Persistent.states.networkUsage;
        if (stored.bootId !== _bootId)
            stored.bootId = _bootId;
        stored.downloadedBytes = downloadedBytes;
        stored.uploadedBytes = uploadedBytes;
    }

    function register(): void {
        _subscribers++;
        updateMonitoring();
    }

    function unregister(): void {
        _subscribers = Math.max(0, _subscribers - 1);
        updateMonitoring();
    }

    function updateMonitoring(): void {
        const shouldMonitor = _subscribers > 0;
        if (monitoring === shouldMonitor)
            return;
        monitoring = shouldMonitor;
        pollTimer.running = monitoring;
        if (!monitoring) {
            downloadBytesPerSecond = 0;
            uploadBytesPerSecond = 0;
            _previousReceivedBytes = -1;
            _previousTransmittedBytes = -1;
            _previousSampleTime = 0;
            persistTotals();
        }
    }

    function formatInterfaceList(line) {
        return line.replace(/:$/, "").trim();
    }

    function updateRate(contents) {
        let receivedBytes = 0
        let transmittedBytes = 0
        const interfaces = []
        const lines = contents.split("\n")

        for (const line of lines) {
            const separator = line.indexOf(":")
            if (separator < 0)
                continue

            const interfaceName = line.slice(0, separator).trim()
            if (!interfaceName || interfaceName === "lo")
                continue

            const fields = line.slice(separator + 1).trim().split(/\s+/)
            if (fields.length < 9)
                continue

            const received = Number(fields[0])
            const transmitted = Number(fields[8])
            if (!Number.isFinite(received) || !Number.isFinite(transmitted))
                continue

            receivedBytes += received
            transmittedBytes += transmitted
            interfaces.push(formatInterfaceList(interfaceName))
        }

        activeInterfaces = interfaces.join(", ")

        const sampleTime = Date.now()
        let totalsChanged = false
        if (_previousSampleTime > 0 && sampleTime > _previousSampleTime) {
            const elapsedMilliseconds = sampleTime - _previousSampleTime
            const receivedDelta = receivedBytes >= _previousReceivedBytes ? receivedBytes - _previousReceivedBytes : 0
            const transmittedDelta = transmittedBytes >= _previousTransmittedBytes ? transmittedBytes - _previousTransmittedBytes : 0

            downloadBytesPerSecond = receivedDelta * 1000 / elapsedMilliseconds
            uploadBytesPerSecond = transmittedDelta * 1000 / elapsedMilliseconds
            downloadedBytes += receivedDelta
            uploadedBytes += transmittedDelta
            totalsChanged = receivedDelta > 0 || transmittedDelta > 0
        }

        _previousReceivedBytes = receivedBytes
        _previousTransmittedBytes = transmittedBytes
        _previousSampleTime = sampleTime

        // Throttled flush so reloads/restarts resume where we left off
        if (totalsChanged && sampleTime - (_lastPersistTime ?? 0) >= _persistIntervalMs) {
            _lastPersistTime = sampleTime
            persistTotals()
        }
    }

    property double _lastPersistTime: 0

    FileView {
        id: networkStats
        path: "/proc/net/dev"
        printErrors: false
        onLoaded: root.updateRate(text())
    }

    FileView {
        id: bootIdFile
        path: "/proc/sys/kernel/random/boot_id"
        printErrors: false
        onLoaded: {
            root._bootId = text().trim()
            root.restoreTotals()
        }
    }

    property string _bootId: ""

    Timer {
        id: pollTimer
        interval: Config?.options.bar.networkSpeed?.pollingInterval ?? 1000
        repeat: true
        running: root.monitoring
        onTriggered: networkStats.reload()
    }

    // Final flush when the shell goes down cleanly
    Component.onDestruction: persistTotals()
}
