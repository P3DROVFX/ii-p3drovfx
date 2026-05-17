pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Tracks application launch frequency for "frecency" search ranking.
 * Persists data to ~/.local/state/quickshell/user/app_usage.json
 */
Singleton {
    id: root

    property var launchCounts: ({})
    property real maxCount: 1
    property bool ready: false

    /**
     * Record an app launch - increments the count for the given app ID
     */
    function recordLaunch(appId) {
        if (!appId || appId.length === 0) return;
        
        let currentData = root.launchCounts[appId];
        let currentCount = 0;
        if (typeof currentData === "number") {
            currentCount = currentData;
        } else if (currentData && typeof currentData === "object") {
            currentCount = currentData.count || 0;
        }

        const newCount = currentCount + 1;
        const now = new Date().getTime();
        
        // Update the counts object (need to reassign for change detection)
        let updated = Object.assign({}, root.launchCounts);
        updated[appId] = {
            count: newCount,
            lastLaunchTime: now
        };
        root.launchCounts = updated;
        
        // Update max for normalization
        if (newCount > root.maxCount) {
            root.maxCount = newCount;
        }
    }

    /**
     * Get normalized score (0-1) for an app based on launch frequency
     */
    function getScore(appId) {
        if (!appId || appId.length === 0) return 0;
        let data = root.launchCounts[appId];
        if (!data) return 0;
        
        let count = 0;
        let lastLaunchTime = 0;
        if (typeof data === "number") {
            count = data;
        } else {
            count = data.count || 0;
            lastLaunchTime = data.lastLaunchTime || 0;
        }

        if (count === 0 || root.maxCount === 0) return 0;
        
        let score = count / root.maxCount;
        
        if (lastLaunchTime > 0) {
            const now = new Date().getTime();
            const daysSinceLaunch = (now - lastLaunchTime) / (1000 * 60 * 60 * 24);
            // Decay curve: exponential decay with half-life of roughly 20 days.
            const decay = Math.exp(-Math.max(0, daysSinceLaunch) / 30);
            score = score * (0.3 + 0.7 * decay); // Floor at 30% of original score
        }
        
        return score;
    }

    /**
     * Get raw launch count for an app
     */
    function getCount(appId) {
        if (!appId || appId.length === 0) return 0;
        let data = root.launchCounts[appId];
        if (typeof data === "number") return data;
        if (data && typeof data === "object") return data.count || 0;
        return 0;
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
        interval: 500 // Slightly longer delay to batch rapid launches
        repeat: false
        onTriggered: usageFileView.writeAdapter()
    }

    // Trigger save when counts change
    onLaunchCountsChanged: {
        if (root.ready) {
            fileWriteTimer.restart();
        }
    }

    FileView {
        id: usageFileView
        path: Directories.appUsagePath

        watchChanges: true
        onFileChanged: fileReloadTimer.restart()
        onLoaded: {
            root.ready = true;
            // Recalculate maxCount from loaded data
            let max = 1;
            for (const appId in usageAdapter.counts) {
                let data = usageAdapter.counts[appId];
                let c = typeof data === "number" ? data : (data.count || 0);
                if (c > max) {
                    max = c;
                }
            }
            root.maxCount = max;
            root.launchCounts = usageAdapter.counts;
        }
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) {
                root.ready = true;
                fileWriteTimer.restart();
            }
        }

        adapter: JsonAdapter {
            id: usageAdapter
            property var counts: root.launchCounts
        }
    }
}