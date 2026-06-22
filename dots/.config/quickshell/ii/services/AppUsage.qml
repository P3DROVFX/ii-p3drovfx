pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Tracks application launch frequency for "frecency" search ranking.
 * Uses time-window bucketed scoring: launches in recent time windows
 * contribute more to the score than older ones.
 * Persists data to ~/.local/state/quickshell/user/app_usage.json
 */
Singleton {
    id: root

    property var launchData: ({})
    property bool ready: false
    // See Config.qml for the rationale. Same protection: don't clobber the
    // on-disk app_usage.json with the empty in-memory default during transient
    // file inaccessibility, and write atomically.
    property real initTimestamp: Date.now()
    property int missingFileGracePeriod: 2000
    property int missingFileRetryInterval: 1500

    // Time window weights for frecency calculation
    readonly property var timeWindows: [
        { maxAge: 1 * 60 * 60 * 1000, weight: 16 },        // Last hour
        { maxAge: 24 * 60 * 60 * 1000, weight: 8 },         // Last day
        { maxAge: 7 * 24 * 60 * 60 * 1000, weight: 4 },     // Last week
        { maxAge: 30 * 24 * 60 * 60 * 1000, weight: 2 },    // Last month
        { maxAge: Infinity, weight: 1 }                       // Older
    ]

    /**
     * Record an app launch - stores timestamp for frecency calculation
     */
    function recordLaunch(appId) {
        if (!appId || appId.length === 0) return;

        const now = new Date().getTime();
        let updated = Object.assign({}, root.launchData);

        if (!updated[appId]) {
            updated[appId] = { timestamps: [], count: 0 };
        }

        // Keep last 100 timestamps per app to avoid unbounded growth
        let timestamps = Array.from(updated[appId].timestamps || []);
        timestamps.push(now);
        if (timestamps.length > 100) {
            timestamps = timestamps.slice(-100);
        }

        updated[appId] = {
            timestamps: timestamps,
            count: (updated[appId].count || 0) + 1
        };

        root.launchData = updated;
    }

    /**
     * Get frecency score for an app based on time-windowed launch history
     */
    function getScore(appId) {
        if (!appId || appId.length === 0) return 0;
        let data = root.launchData[appId];
        if (!data) return 0;

        // Handle legacy format (plain number)
        if (typeof data === "number") {
            return data > 0 ? 1 : 0;
        }
        // Handle legacy format with count + lastLaunchTime
        if (data.count !== undefined && !data.timestamps) {
            const count = data.count || 0;
            if (count === 0) return 0;
            const lastLaunch = data.lastLaunchTime || 0;
            if (lastLaunch === 0) return count > 0 ? 1 : 0;
            const now = new Date().getTime();
            const age = now - lastLaunch;
            for (const tw of root.timeWindows) {
                if (age <= tw.maxAge) return count * tw.weight;
            }
            return count;
        }

        const timestamps = data.timestamps || [];
        if (timestamps.length === 0) return 0;

        const now = new Date().getTime();
        let score = 0;
        for (const ts of timestamps) {
            const age = now - ts;
            for (const tw of root.timeWindows) {
                if (age <= tw.maxAge) {
                    score += tw.weight;
                    break;
                }
            }
        }
        return score;
    }

    /**
     * Get raw launch count for an app
     */
    function getCount(appId) {
        if (!appId || appId.length === 0) return 0;
        let data = root.launchData[appId];
        if (typeof data === "number") return data;
        if (data && typeof data === "object") return data.count || (data.timestamps || []).length;
        return 0;
    }

    /**
     * Reset ranking for a specific app
     */
    function resetRanking(appId) {
        if (!appId || appId.length === 0) return;
        let updated = Object.assign({}, root.launchData);
        delete updated[appId];
        root.launchData = updated;
    }

    // Persistence
    Timer {
        id: fileReloadTimer
        interval: 100
        repeat: false
        onTriggered: usageFileView.reload()
    }

    Timer {
        id: fileWriteTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (!root.ready) {
                fileWriteTimer.restart();
                return;
            }
            usageFileView.writeAdapter()
        }
    }

    Timer {
        id: missingFileRetryTimer
        interval: root.missingFileRetryInterval
        repeat: false
        onTriggered: usageFileView.reload()
    }

    onLaunchDataChanged: {
        if (root.ready) {
            fileWriteTimer.restart();
        }
    }

    FileView {
        id: usageFileView
        path: Directories.appUsagePath

        watchChanges: true
        atomicWrites: true
        onFileChanged: fileReloadTimer.restart()
        onLoaded: {
            root.ready = true;
            root.launchData = usageAdapter.data;
        }
        onLoadFailed: error => {
            if (error != FileViewError.FileNotFound) {
                return;
            }
            const elapsed = Date.now() - root.initTimestamp;
            if (elapsed > root.missingFileGracePeriod) {
                root.ready = true;
                fileWriteTimer.restart();
            } else {
                missingFileRetryTimer.restart();
            }
        }

        adapter: JsonAdapter {
            id: usageAdapter
            property var data: root.launchData
        }
    }
}