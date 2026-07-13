pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var jobs: []
    readonly property bool hasActiveJobs: jobs.length > 0

    // Central formatting helpers
    function formatBytes(bytes) {
        if (bytes <= 0) return "0 B";
        const k = 1024;
        const dm = 1;
        const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
    }

    function formatSpeed(bytesPerSec) {
        if (bytesPerSec <= 0) return "";
        return formatBytes(bytesPerSec) + "/s";
    }

    function formatEta(seconds) {
        if (seconds <= 0 || !isFinite(seconds)) return "";
        if (seconds < 60) return Math.ceil(seconds) + "s restantes";
        let mins = Math.floor(seconds / 60);
        let secs = Math.ceil(seconds % 60);
        if (mins < 60) {
            return mins + "m " + secs + "s restantes";
        }
        let hours = Math.floor(mins / 60);
        let remMins = mins % 60;
        return hours + "h " + remMins + "m restantes";
    }

    // Monitor for the org.kde.JobViewServer session DBus process
    Process {
        id: monitorProc
        running: Config.ready && !Config.options.bar.floatingNotch.disableProgress
        command: ["python3", Quickshell.shellPath("services/jobview_monitor.py")]
        
        stdout: SplitParser {
            onRead: line => {
                if (!line || line.length === 0) return;
                try {
                    let ev = JSON.parse(line);
                    root.handleEvent(ev);
                } catch(e) {
                    console.warn("[ProgressService] Bad JSON:", e.message);
                }
            }
        }
    }

    // Monitor Notifications list for GTK/Nautilus progress hints
    Connections {
        target: Notifications
        function onListChanged() {
            root.scanNotificationsForProgress();
        }
    }

    // Periodically clean up finished jobs
    Timer {
        id: cleanupTimer
        interval: 1000
        repeat: true
        running: root.jobs.some(j => j.state === "completed" || j.state === "failed" || j.state === "cleared")
        onTriggered: {
            let now = Date.now();
            let newJobs = [];
            let changed = false;
            for (let i = 0; i < root.jobs.length; i++) {
                let job = root.jobs[i];
                if (job.state === "completed" || job.state === "failed" || job.state === "cleared") {
                    if (!job.completedTime) {
                        job.completedTime = now;
                        changed = true;
                    }
                    if (now - job.completedTime > 3000) { // Keep complete visible for 3 seconds
                        changed = true;
                        continue;
                    }
                }
                newJobs.push(job);
            }
            if (changed) {
                root.jobs = newJobs;
            }
        }
    }

    function handleEvent(ev) {
        if (ev.event === "update") {
            let idx = -1;
            for (let i = 0; i < root.jobs.length; i++) {
                if (root.jobs[i].id === ev.id && root.jobs[i].source === "dbus") {
                    idx = i;
                    break;
                }
            }
            let job = {
                id: ev.id,
                appName: ev.appName || "Dolphin",
                appIcon: ev.appIcon || "system-file-manager",
                percent: ev.percent !== undefined ? ev.percent : 0,
                message: ev.message || "",
                speed: ev.speed || 0,
                processed: ev.processed || 0,
                total: ev.total || 0,
                unit: ev.unit || "",
                state: ev.state || "running",
                source: "dbus"
            };

            // Format speed & sizes
            job.speedText = job.speed > 0 ? formatSpeed(job.speed) : "";
            if (job.total > 0) {
                job.progressText = formatBytes(job.processed) + " / " + formatBytes(job.total);
                if (job.speed > 0 && job.total > job.processed) {
                    let remainingBytes = job.total - job.processed;
                    job.etaText = formatEta(remainingBytes / job.speed);
                } else {
                    job.etaText = "";
                }
            } else if (job.processed > 0) {
                job.progressText = formatBytes(job.processed);
                job.etaText = "";
            } else {
                job.progressText = "";
                job.etaText = "";
            }

            let newJobs = root.jobs.slice();
            if (idx !== -1) {
                newJobs[idx] = job;
            } else {
                newJobs.push(job);
            }
            root.jobs = newJobs;
        } else if (ev.event === "terminate" || ev.event === "clear") {
            let idx = -1;
            for (let i = 0; i < root.jobs.length; i++) {
                if (root.jobs[i].id === ev.id && root.jobs[i].source === "dbus") {
                    idx = i;
                    break;
                }
            }
            if (idx !== -1) {
                let newJobs = root.jobs.slice();
                newJobs[idx].percent = 100;
                newJobs[idx].state = "completed";
                newJobs[idx].completedTime = Date.now();
                root.jobs = newJobs;
            }
        }
    }

    function scanNotificationsForProgress() {
        let now = Date.now();
        let nextJobs = root.jobs.filter(j => j.source !== "notification");
        let changed = false;

        for (let i = 0; i < Notifications.list.length; i++) {
            let notif = Notifications.list[i];
            let hasProgress = notif.notification && notif.notification.hints && notif.notification.hints.value !== undefined;
            if (hasProgress) {
                let val = parseInt(notif.notification.hints.value);
                let job = {
                    id: "notif_" + notif.notificationId,
                    appName: notif.appName || "Notification",
                    appIcon: notif.appIcon || "system-file-manager",
                    percent: val,
                    message: notif.summary || notif.body || "",
                    speed: 0,
                    processed: 0,
                    total: 0,
                    unit: "",
                    state: val >= 100 ? "completed" : "running",
                    source: "notification",
                    speedText: "",
                    progressText: notif.body || ""
                };
                if (job.state === "completed") {
                    job.completedTime = now;
                }
                nextJobs.push(job);
                changed = true;
            }
        }

        if (changed || root.jobs.some(j => j.source === "notification")) {
            root.jobs = nextJobs;
        }
    }
}
