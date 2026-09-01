import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.widgets
import qs.modules.ii.usage

Item {
    id: root

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage
    property bool driveSubPageMode: false
    property bool showBackButton: false
    signal goBack()

    readonly property string selectedProvider: {
        const configured = Config.options.todo ? Config.options.todo.provider : "local";
        if (configured === "ticktick" || configured === "googleTasks" || configured === "local")
            return configured;
        return "local";
    }

    // Temp state before saving
    property string tempClientId: ""
    property string tempClientSecret: ""
    property string tempAccessToken: ""

    // Auth process state
    property bool authRunning: false
    property string authErrorMsg: ""
    property string driveUiError: ""
    property string excludePatternDraft: ""
    property string excludePatternError: ""
    property int activityGranularityIndex: 0
    property int activityMetricIndex: 0
    property int performanceViewIndex: 0

    readonly property var driveOptions: (Persistent.ready ? Persistent.states.googleDrive : null) || Config.options.googleDrive
    readonly property var activityGranularities: [
        { key: "day", value: "day", displayName: Translation.tr("Last 7 days"), selectorName: Translation.tr("7 days"), icon: "today" },
        { key: "week", value: "week", displayName: Translation.tr("Last 8 weeks"), selectorName: Translation.tr("8 weeks"), icon: "date_range" },
        { key: "month", value: "month", displayName: Translation.tr("Last 12 months"), selectorName: Translation.tr("12 months"), icon: "calendar_month" }
    ]
    readonly property var activityMetrics: [
        { key: "data", value: "data", displayName: Translation.tr("Data transferred"), icon: "data_usage" },
        { key: "transfers", value: "transfers", displayName: Translation.tr("Backups completed"), icon: "cloud_done" }
    ]
    readonly property string activityGranularity: root.activityGranularities[root.activityGranularityIndex].key
    readonly property var activityBuckets: root.buildActivityBuckets(root.activityGranularity)
    readonly property var activityDataValues: root.activityBuckets.map(bucket => bucket.dataMb)
    readonly property var activityTransferValues: root.activityBuckets.map(bucket => bucket.runs)
    readonly property var activityLabels: root.activityBuckets.map(bucket => bucket.label)
    readonly property var activityTooltipLabels: root.activityBuckets.map(bucket => bucket.tooltip)
    readonly property var activityVisibleLabelIndices: {
        const indices = [];
        const lastIndex = Math.max(0, root.activityLabels.length - 1);
        for (let index = 0; index < root.activityLabels.length; ++index) {
            if (root.activityLabels.length <= 5
                    || index === 0
                    || index === Math.floor(lastIndex / 2)
                    || index === lastIndex)
                indices.push(index);
        }
        return indices;
    }
    readonly property bool hasActivity: {
        const entries = GoogleDriveService.syncHistory || [];
        for (const entry of entries) {
            if (entry && entry.time)
                return true;
        }
        return false;
    }
    readonly property real storageBackupMb: Math.max(0, Number(GoogleDriveService.driveBackupUsageMb || 0))
    readonly property real storageUsedMb: Math.max(0, Number(GoogleDriveService.driveUsedMb || 0))
    readonly property real storageQuotaMb: Math.max(0, Number(GoogleDriveService.driveQuotaMb || 0))
    readonly property real storageOtherMb: Math.max(0, root.storageUsedMb - root.storageBackupMb)
    readonly property real storageFreeMb: Math.max(0, root.storageQuotaMb - root.storageUsedMb)
    readonly property real storageUsedRatio: root.storageQuotaMb > 0
        ? Math.min(1, root.storageUsedMb / root.storageQuotaMb)
        : 0
    readonly property real backupFootprintRatio: root.storageQuotaMb > 0
        ? Math.min(1, root.storageBackupMb / root.storageQuotaMb)
        : 0
    readonly property var storageSegments: [root.storageBackupMb, root.storageOtherMb, root.storageFreeMb]
    readonly property real heatmapCellSpacing: 4
    readonly property int heatmapWeekCount: root.currentMonthWeekCount()
    readonly property var heatmapCells: root.buildHeatmapCells(root.heatmapWeekCount)
    readonly property var heatmapWeekLabels: root.buildHeatmapWeekLabels(root.heatmapWeekCount)
    readonly property var heatmapDayLabels: [
        Translation.tr("Mon"), Translation.tr("Tue"), Translation.tr("Wed"),
        Translation.tr("Thu"), Translation.tr("Fri"), Translation.tr("Sat"), Translation.tr("Sun")
    ]
    readonly property string heatmapMonthLabel: new Date().toLocaleDateString(Qt.locale(), "MMMM yyyy")
    readonly property int heatmapActiveDays: root.heatmapCells.filter(cell => Number((cell && cell.value) || 0) > 0).length
    readonly property string heatmapActiveDaysLabel: String(root.heatmapActiveDays) + " "
        + (root.heatmapActiveDays === 1
            ? Translation.tr("active day")
            : Translation.tr("active days"))
    readonly property real heatmapTotal: root.heatmapCells.reduce((total, cell) => total + Number((cell && cell.value) || 0), 0)
    readonly property real heatmapMaxValue: root.heatmapCells.reduce((maximum, cell) => Math.max(maximum, Number((cell && cell.value) || 0)), 0)
    readonly property var recentSyncRows: root.buildRecentSyncRows()
    readonly property int successfulSyncCount: (GoogleDriveService.syncHistory || [])
        .filter(entry => entry && entry.status === "success").length
    readonly property int failedSyncCount: (GoogleDriveService.syncHistory || [])
        .filter(entry => entry && entry.status === "error").length
    readonly property real syncSuccessRatio: root.successfulSyncCount + root.failedSyncCount > 0
        ? root.successfulSyncCount / (root.successfulSyncCount + root.failedSyncCount)
        : 0
    readonly property var recentPerformanceRows: root.recentSyncRows.filter(entry => entry && entry.status === "success")
    readonly property bool hasDetailedPerformanceData: root.recentPerformanceRows.some(entry => root.entryDurationSeconds(entry) > 0 || root.entrySpeedBytesPerSecond(entry) > 0)
    readonly property real averageDurationSeconds: root.performanceAverage("durationSeconds")
    readonly property real averageSpeedBytesPerSecond: root.performanceAverage("averageBytesPerSecond")
    readonly property var largestTransfer: root.findLargestTransfer()
    readonly property bool hasPerformanceData: root.largestTransfer !== null || root.hasDetailedPerformanceData
    readonly property var performanceTransferValues: root.recentPerformanceRows.slice().reverse()
        .map(entry => Math.max(0, Number((entry && entry.sizeMb) || 0)))
    readonly property real averageTransferMb: root.performanceTransferValues.length > 0
        ? root.performanceTransferValues.reduce((sum, value) => sum + value, 0) / root.performanceTransferValues.length
        : 0
    readonly property real recentTransferTotalMb: root.performanceTransferValues.reduce((sum, value) => sum + value, 0)
    readonly property int timedPerformanceCount: root.recentPerformanceRows
        .filter(entry => root.entryDurationSeconds(entry) > 0).length
    readonly property var performanceViews: [
        { name: Translation.tr("Transfers"), icon: "data_usage" },
        { name: Translation.tr("Timing"), icon: "schedule" }
    ]

    function rcloneInstallFamilyFor(value) {
        const distro = String(value || "").toLowerCase();
        if (["fedora", "rhel", "centos", "rocky", "almalinux"].indexOf(distro) >= 0)
            return "Fedora / RHEL";
        if (["arch", "artix", "manjaro", "endeavouros", "cachyos"].indexOf(distro) >= 0)
            return "Arch Linux";
        if (["debian", "ubuntu", "linuxmint", "pop", "popos", "zorin", "elementary", "kali", "raspbian"].indexOf(distro) >= 0)
            return "Debian / Ubuntu";
        if (distro === "nixos")
            return "NixOS";
        if (["opensuse", "opensuse-leap", "opensuse-tumbleweed", "sles"].indexOf(distro) >= 0)
            return "openSUSE";
        if (distro === "alpine")
            return "Alpine Linux";
        if (["gentoo", "funtoo"].indexOf(distro) >= 0)
            return "Gentoo";
        if (distro === "void")
            return "Void Linux";
        if (distro === "solus")
            return "Solus";
        return SystemInfo.distroName && SystemInfo.distroName !== "Unknown"
            ? SystemInfo.distroName
            : "Linux";
    }

    function rcloneInstallCommandFor(value) {
        const distro = String(value || "").toLowerCase();
        if (["fedora", "rhel", "centos", "rocky", "almalinux"].indexOf(distro) >= 0)
            return "sudo dnf install -y rclone";
        if (["arch", "artix", "manjaro", "endeavouros", "cachyos"].indexOf(distro) >= 0)
            return "sudo pacman -S --needed rclone";
        if (["debian", "ubuntu", "linuxmint", "pop", "popos", "zorin", "elementary", "kali", "raspbian"].indexOf(distro) >= 0)
            return "sudo apt update && sudo apt install -y rclone";
        if (distro === "nixos")
            return "nix profile install nixpkgs#rclone";
        if (["opensuse", "opensuse-leap", "opensuse-tumbleweed", "sles"].indexOf(distro) >= 0)
            return "sudo zypper install rclone";
        if (distro === "alpine")
            return "sudo apk add rclone";
        if (["gentoo", "funtoo"].indexOf(distro) >= 0)
            return "sudo emerge --ask app-portage/rclone";
        if (distro === "void")
            return "sudo xbps-install -S rclone";
        if (distro === "solus")
            return "sudo eopkg install rclone";
        return "curl https://rclone.org/install.sh | sudo bash";
    }

    readonly property string rcloneInstallFamily: root.rcloneInstallFamilyFor(SystemInfo.distroId)
    readonly property string rcloneInstallCommand: root.rcloneInstallCommandFor(SystemInfo.distroId)

    function updateDriveOption(key, value) {
        if (Persistent.ready && Persistent.states.googleDrive) {
            Persistent.states.googleDrive[key] = value;
        }
        if (Config.ready && Config.options.googleDrive) {
            Config.options.googleDrive[key] = value;
        }
    }

    function updateDriveList(key, transform) {
        const current = Array.from(root.driveOptions[key] || []);
        transform(current);
        root.updateDriveOption(key, current);
    }

    function addBackupFolder(path) {
        const cleanPath = String(path || "").trim();
        if (!cleanPath || (root.driveOptions.backupFolders && root.driveOptions.backupFolders.indexOf(cleanPath) >= 0))
            return;
        root.updateDriveList("backupFolders", values => values.push(cleanPath));
    }

    function removeBackupFolder(index) {
        root.updateDriveList("backupFolders", values => values.splice(index, 1));
    }

    function removeExcludePattern(index) {
        root.updateDriveList("excludePatterns", values => values.splice(index, 1));
    }

    function addExcludePattern(pattern: string) {
        const cleanPattern = String(pattern || "").trim();
        root.excludePatternError = "";
        if (!cleanPattern) {
            root.excludePatternError = Translation.tr("Enter a pattern before adding it.");
            return;
        }
        if (cleanPattern.length > 256 || /[\r\n]/.test(cleanPattern) || cleanPattern.startsWith("--")) {
            root.excludePatternError = Translation.tr("Use one rclone glob pattern (up to 256 characters) without line breaks.");
            return;
        }
        if (root.driveOptions.excludePatterns && root.driveOptions.excludePatterns.indexOf(cleanPattern) >= 0) {
            root.excludePatternError = Translation.tr("That pattern is already excluded.");
            return;
        }
        root.updateDriveList("excludePatterns", values => values.push(cleanPattern));
        root.excludePatternDraft = "";
    }

    function dateKey(date) {
        return String(date.getFullYear()) + "-"
            + String(date.getMonth() + 1).padStart(2, "0") + "-"
            + String(date.getDate()).padStart(2, "0");
    }

    function activityBucketKey(value, granularity) {
        const date = new Date(value || "");
        if (!isFinite(date.getTime()))
            return "";
        if (granularity === "month")
            return String(date.getFullYear()) + "-" + String(date.getMonth() + 1).padStart(2, "0");
        if (granularity === "week") {
            const monday = new Date(date.getFullYear(), date.getMonth(), date.getDate());
            const offset = (monday.getDay() + 6) % 7;
            monday.setDate(monday.getDate() - offset);
            return root.dateKey(monday);
        }
        return root.dateKey(date);
    }

    function activityBucketLabel(key, granularity) {
        if (granularity === "month") {
            const parts = key.split("-");
            return parts[1] + "/" + parts[0];
        }
        const parts = key.split("-");
        return parts[2] + "/" + parts[1];
    }

    function activityBucketTooltip(date, granularity) {
        if (granularity === "month")
            return date.toLocaleDateString(Qt.locale(), "MMMM yyyy");
        if (granularity === "week") {
            const end = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 6);
            return date.toLocaleDateString(Qt.locale(), "dd MMM")
                + " – " + end.toLocaleDateString(Qt.locale(), "dd MMM yyyy");
        }
        return date.toLocaleDateString(Qt.locale(), "dd MMM yyyy");
    }

    function buildActivityBuckets(granularity) {
        if (granularity === "day") {
            const bucketCount = 7;
            const dayMilliseconds = 24 * 60 * 60 * 1000;
            const today = new Date();
            const firstDay = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 6, 12);
            const buckets = [];

            for (let index = 0; index < bucketCount; ++index) {
                const start = new Date(firstDay.getTime() + index * dayMilliseconds);
                buckets.push({
                    key: "day-" + String(index),
                    runs: 0,
                    files: 0,
                    dataMb: 0,
                    errors: 0,
                    label: start.toLocaleDateString(Qt.locale(), "dd"),
                    start: start,
                    end: start
                });
            }

            for (const entry of GoogleDriveService.syncHistory || []) {
                if (!entry || !entry.time)
                    continue;
                const date = new Date(String(entry.time));
                if (!isFinite(date.getTime()))
                    continue;
                const localDate = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 12);
                const offset = Math.floor((localDate.getTime() - firstDay.getTime()) / dayMilliseconds);
                if (offset < 0 || offset >= 7)
                    continue;
                const bucket = buckets[offset];
                bucket.runs += Math.max(1, Number(entry.transferCount || 1));
                bucket.files += Math.max(0, Number(entry.fileCount || 0));
                bucket.dataMb += Math.max(0, Number(entry.sizeMb || 0));
                if (entry.status === "error")
                    bucket.errors += 1;
            }

            return buckets.map(bucket => {
                const rangeLabel = bucket.start.getTime() === bucket.end.getTime()
                    ? root.activityBucketTooltip(bucket.start, "day")
                    : root.activityBucketTooltip(bucket.start, "day") + " – "
                        + root.activityBucketTooltip(bucket.end, "day");
                bucket.tooltip = root.activityMetricIndex === 0
                    ? rangeLabel + " · " + root.formatMegabytes(bucket.dataMb)
                    : rangeLabel + " · " + String(Math.round(bucket.runs)) + " " + Translation.tr("backups");
                return bucket;
            });
        }

        const grouped = ({ });
        const orderedKeys = [];
        const now = new Date();
        const bucketCount = granularity === "day" ? 7 : granularity === "week" ? 8 : 12;

        for (let offset = bucketCount - 1; offset >= 0; --offset) {
            let bucketDate;
            if (granularity === "month") {
                bucketDate = new Date(now.getFullYear(), now.getMonth() - offset, 1, 12);
            } else if (granularity === "week") {
                bucketDate = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 12);
                const weekdayOffset = (bucketDate.getDay() + 6) % 7;
                bucketDate.setDate(bucketDate.getDate() - weekdayOffset - offset * 7);
            } else {
                bucketDate = new Date(now.getFullYear(), now.getMonth(), now.getDate() - offset, 12);
            }

            const key = root.activityBucketKey(bucketDate.toISOString(), granularity);
            orderedKeys.push(key);
            grouped[key] = {
                key: key,
                runs: 0,
                files: 0,
                dataMb: 0,
                errors: 0,
                label: root.activityBucketLabel(key, granularity),
                tooltip: root.activityBucketTooltip(bucketDate, granularity)
            };
        }

        const entries = GoogleDriveService.syncHistory || [];
        for (const entry of entries) {
            if (!entry || !entry.time)
                continue;
            const key = root.activityBucketKey(String(entry.time), granularity);
            if (!key)
                continue;
            if (!grouped[key])
                continue;
            const bucket = grouped[key];
            bucket.runs += Math.max(1, Number(entry.transferCount || 1));
            bucket.files += Math.max(0, Number(entry.fileCount || 0));
            bucket.dataMb += Math.max(0, Number(entry.sizeMb || 0));
            if (entry.status === "error")
                bucket.errors += 1;
        }
        return orderedKeys.map(key => grouped[key]);
    }

    function currentMonthGridStart() {
        const today = new Date();
        const firstDay = new Date(today.getFullYear(), today.getMonth(), 1, 12);
        firstDay.setDate(firstDay.getDate() - ((firstDay.getDay() + 6) % 7));
        return firstDay;
    }

    function currentMonthWeekCount() {
        const today = new Date();
        const gridStart = root.currentMonthGridStart();
        const lastDay = new Date(today.getFullYear(), today.getMonth() + 1, 0, 12);
        lastDay.setDate(lastDay.getDate() + (7 - ((lastDay.getDay() + 6) % 7) - 1));
        return Math.max(4, Math.floor((lastDay.getTime() - gridStart.getTime()) / 604800000) + 1);
    }

    function buildHeatmapCells(weekCount) {
        const grouped = ({ });
        const today = new Date();
        const current = root.currentMonthGridStart();
        const totalWeeks = Math.max(1, Number(weekCount || 5));

        for (const entry of GoogleDriveService.syncHistory || []) {
            if (!entry || !entry.time)
                continue;
            const date = new Date(String(entry.time));
            if (!isFinite(date.getTime()))
                continue;
            const key = root.dateKey(date);
            if (!grouped[key])
                grouped[key] = { runs: 0, dataMb: 0, files: 0, errors: 0 };
            grouped[key].runs += Math.max(1, Number(entry.transferCount || 1));
            grouped[key].dataMb += Math.max(0, Number(entry.sizeMb || 0));
            grouped[key].files += Math.max(0, Number(entry.fileCount || 0));
            if (entry.status === "error")
                grouped[key].errors += 1;
        }

        const cells = [];
        for (let week = 0; week < totalWeeks; ++week) {
            for (let day = 0; day < 7; ++day) {
                const date = new Date(current.getFullYear(), current.getMonth(), current.getDate() + week * 7 + day, 12);
                const key = root.dateKey(date);
                const inRange = date.getFullYear() === today.getFullYear()
                    && date.getMonth() === today.getMonth();
                const bucket = inRange && grouped[key]
                    ? grouped[key]
                    : { runs: 0, dataMb: 0, files: 0, errors: 0 };
                const value = root.activityMetricIndex === 0 ? bucket.dataMb : bucket.runs;
                cells.push({
                    inRange: inRange,
                    value: value,
                    tooltip: root.activityMetricIndex === 0
                        ? root.activityBucketTooltip(date, "day") + " · " + root.formatMegabytes(value)
                        : root.activityBucketTooltip(date, "day") + " · " + String(Math.round(value)) + " " + Translation.tr("backups")
                });
            }
        }
        return cells;
    }

    function buildHeatmapWeekLabels(weekCount) {
        const labels = [];
        const today = new Date();
        const current = root.currentMonthGridStart();
        const totalWeeks = Math.max(1, Number(weekCount || 5));
        for (let week = 0; week < totalWeeks; ++week) {
            labels.push(week === 0
                ? today.toLocaleDateString(Qt.locale(), "MMM")
                : "");
        }
        return labels;
    }

    function buildRecentSyncRows() {
        const rows = (GoogleDriveService.syncHistory || []).filter(entry => entry && entry.time).slice();
        rows.sort((left, right) => Date.parse(String(right.time)) - Date.parse(String(left.time)));
        return rows.slice(0, 4);
    }

    function entryDurationSeconds(entry) {
        return Math.max(0, Number((entry && entry.durationSeconds) || 0));
    }

    function entrySpeedBytesPerSecond(entry) {
        const storedSpeed = Math.max(0, Number((entry && entry.averageBytesPerSecond) || 0));
        if (storedSpeed > 0)
            return storedSpeed;
        const duration = root.entryDurationSeconds(entry);
        const bytes = Math.max(0, Number((entry && entry.sizeMb) || 0)) * 1024 * 1024;
        return duration > 0 ? bytes / duration : 0;
    }

    function performanceAverage(field) {
        const values = root.recentPerformanceRows
            .map(entry => field === "durationSeconds"
                ? root.entryDurationSeconds(entry)
                : root.entrySpeedBytesPerSecond(entry))
            .filter(value => value > 0);
        if (values.length === 0)
            return 0;
        return values.reduce((sum, value) => sum + value, 0) / values.length;
    }

    function findLargestTransfer() {
        let largest = null;
        for (const entry of GoogleDriveService.syncHistory || []) {
            if (!entry || entry.status !== "success" || Number(entry.sizeMb || 0) <= 0)
                continue;
            if (!largest || Number(entry.sizeMb) > Number(largest.sizeMb || 0))
                largest = entry;
        }
        return largest;
    }

    function scheduleIntervalLabel(value) {
        const labels = ({
            "1h": Translation.tr("Every hour"),
            "4h": Translation.tr("Every 4 hours"),
            "1d": Translation.tr("Every day"),
            "2d": Translation.tr("Every 2 days"),
            "3d": Translation.tr("Every 3 days")
        });
        return labels[value] || Translation.tr("Scheduled");
    }

    function nextRunDate() {
        if (!driveOptions.enabled || !GoogleDriveService.configured || !driveOptions.lastSyncTime)
            return null;
        const last = Date.parse(String(driveOptions.lastSyncTime));
        if (!isFinite(last))
            return null;
        return new Date(last + GoogleDriveService.intervalFor(String(driveOptions.syncInterval || "3d")));
    }

    function nextRunLabel() {
        const next = root.nextRunDate();
        if (!next)
            return driveOptions.enabled ? Translation.tr("Waiting for first sync") : Translation.tr("Backup is disabled");
        return next.toLocaleDateString(Qt.locale(), "dd MMM") + " · " + next.toLocaleTimeString(Qt.locale(), "HH:mm");
    }

    function syncStatusLabel(entry) {
        return entry && entry.status === "success" ? Translation.tr("Completed") : Translation.tr("Failed");
    }

    function syncStatusIcon(entry) {
        if (!entry)
            return "cloud_queue";
        return entry.status === "success" ? "cloud_done" : "cloud_off";
    }

    function syncStatusColor(entry) {
        return entry && entry.status === "success"
            ? Appearance.colors.colPrimary
            : Appearance.colors.colError;
    }

    function entryDurationText(entry) {
        const seconds = root.entryDurationSeconds(entry);
        return seconds > 0 ? root.formatDuration(seconds) : "—";
    }

    function entryTimeText(entry) {
        const date = new Date(String((entry && entry.time) || ""));
        if (!isFinite(date.getTime()))
            return Translation.tr("Unknown time");
        return date.toLocaleDateString(Qt.locale(), "dd MMM") + " · " + date.toLocaleTimeString(Qt.locale(), "HH:mm");
    }

    function formatMegabytes(value) {
        const amount = Number(value || 0);
        if (amount >= 1024 * 1024)
            return (amount / (1024 * 1024)).toFixed(1) + " TB";
        if (amount >= 1024)
            return (amount / 1024).toFixed(1) + " GB";
        return amount.toFixed(1) + " MB";
    }

    function storagePercentageLabel(value) {
        if (root.storageQuotaMb <= 0)
            return "—";
        const percentage = Math.max(0, Number(value || 0)) / root.storageQuotaMb * 100;
        if (percentage > 0 && percentage < 0.1)
            return "<0.1%";
        return percentage < 10
            ? percentage.toFixed(1) + "%"
            : percentage.toFixed(0) + "%";
    }

    function heatmapLegendLabel(weight) {
        const value = root.heatmapMaxValue * Math.max(0, Number(weight || 0));
        if (root.heatmapMaxValue <= 0)
            return "0";
        return root.activityMetricIndex === 0
            ? root.formatMegabytes(value)
            : String(Math.max(1, Math.round(value)));
    }

    function formatTransferSize(value) {
        const bytes = Math.max(0, Number(value || 0));
        if (bytes < 1024)
            return Math.round(bytes) + " B";
        if (bytes < 1024 * 1024)
            return (bytes / 1024).toFixed(1) + " KiB";
        if (bytes < 1024 * 1024 * 1024)
            return (bytes / (1024 * 1024)).toFixed(1) + " MiB";
        return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GiB";
    }

    function syncProgressSummary() {
        const details = [];
        if (GoogleDriveService.currentFolderTotalFiles > 0)
            details.push(String(GoogleDriveService.currentFolderFiles) + " / " + String(GoogleDriveService.currentFolderTotalFiles) + " files");
        if (GoogleDriveService.currentFolderTotalBytes > 0)
            details.push(root.formatTransferSize(GoogleDriveService.currentFolderBytes) + " / " + root.formatTransferSize(GoogleDriveService.currentFolderTotalBytes));
        if (details.length === 0)
            return Translation.tr("Preparing transfer…");
        return details.join(" · ");
    }

    function lastSyncSummary() {
        if (GoogleDriveService.syncing)
            return Translation.tr("Sync in progress…");
        if (driveOptions.lastSyncStatus === "running")
            return Translation.tr("Previous sync interrupted · run again");
        if (driveOptions.lastSyncStatus === "success"
                && Number(driveOptions.lastSyncFileCount || 0) === 0
                && Number(driveOptions.lastSyncSizeMb || 0) === 0)
            return Translation.tr("Last sync: Up to date · no new files");
        return Translation.tr("Last sync: %1 · %2 files · %3")
            .arg(root.relativeTime(driveOptions.lastSyncTime))
            .arg(String(driveOptions.lastSyncFileCount || 0))
            .arg(root.formatMegabytes(driveOptions.lastSyncSizeMb));
    }

    function formatDuration(seconds) {
        const elapsed = Math.max(0, Number(seconds || 0));
        const minutes = Math.floor(elapsed / 60);
        const remainingSeconds = elapsed % 60;
        return String(minutes).padStart(2, "0") + ":" + String(remainingSeconds).padStart(2, "0");
    }

    function relativeTime(value) {
        if (!value)
            return Translation.tr("Never");
        const timestamp = new Date(value).getTime();
        if (!isFinite(timestamp))
            return Translation.tr("Never");
        const elapsed = Math.max(0, Date.now() - timestamp);
        if (elapsed < 60000)
            return Translation.tr("Just now");
        if (elapsed < 3600000)
            return Math.floor(elapsed / 60000) + "m ago";
        if (elapsed < 86400000)
            return Math.floor(elapsed / 3600000) + "h ago";
        return Math.floor(elapsed / 86400000) + "d ago";
    }

    function openFolderPicker() {
        root.driveUiError = "";
        folderPickerProc.running = false;
        folderPickerProc.running = true;
    }

    Component.onCompleted: {
        loadTempData();
    }

    function loadTempData() {
        tempClientId = TickTickService.clientId;
        tempClientSecret = TickTickService.clientSecret;
        tempAccessToken = TickTickService.accessToken;
    }


    ContentPage {
        id: page

        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

        RowLayout {
            visible: root.showBackButton
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                topLeftRadius: Appearance.rounding.full
                topRightRadius: Appearance.rounding.full
                bottomLeftRadius: Appearance.rounding.full
                bottomRightRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Google Drive Backup")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

    WarningBox {
        Layout.fillWidth: true
        visible: !root.driveSubPageMode && root.selectedProvider === "ticktick" && authErrorMsg !== ""
        text: authErrorMsg
    }

    // ── To-Do Provider Selector ─────────────────────────────────
    ContentSection {
        icon: "checklist"
        title: Translation.tr("To-Do Provider")
        visible: !root.driveSubPageMode

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: [
                    { id: "local", name: Translation.tr("Local Storage"), icon: "save" },
                    { id: "ticktick", name: "TickTick", icon: "cloud_sync" },
                    { id: "googleTasks", name: "Google Tasks", icon: "checklist" }
                ]

                delegate: RippleButton {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    implicitHeight: 44
                    buttonRadius: Appearance.rounding.normal
                    colBackground: root.selectedProvider === modelData.id
                        ? Appearance.colors.colPrimaryContainer
                        : Appearance.colors.colLayer0
                    colBackgroundHover: root.selectedProvider === modelData.id
                        ? Appearance.colors.colPrimaryContainerHover
                        : Appearance.colors.colLayer0Hover
                    colRipple: root.selectedProvider === modelData.id
                        ? Appearance.colors.colPrimaryContainerActive
                        : Appearance.colors.colLayer0Active

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        MaterialSymbol {
                            text: modelData.icon
                            iconSize: Appearance.font.pixelSize.normal
                            color: root.selectedProvider === modelData.id
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colOnLayer0
                        }

                        StyledText {
                            text: modelData.name
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.bold: root.selectedProvider === modelData.id
                            color: root.selectedProvider === modelData.id
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colOnLayer0
                        }
                    }

                    onClicked: {
                        if (Config.options.todo) {
                            Config.options.todo.provider = modelData.id;
                        }
                    }
                }
            }
        }
    }

    // ── Local Storage Info ──────────────────────────────────────
    ContentSection {
        icon: "save"
        title: Translation.tr("Local Storage")
        visible: !root.driveSubPageMode && root.selectedProvider === "local"

        HelperLinkBox {
            Layout.fillWidth: true
            title: Translation.tr("Offline File Storage")
            text: Translation.tr("Tasks are stored locally on disk in your profile (~/.config/quickshell/ii/todo.json). No network connection or account is required.")
            isFirst: true
        }
    }

    // ── Google Tasks Configuration ──────────────────────────────
    CoreGoogleTasksConfig {
        Layout.fillWidth: true
        visible: !root.driveSubPageMode && root.selectedProvider === "googleTasks"
    }

    // ── TickTick Configuration ──────────────────────────────────
    ContentSection {
        icon: "cloud_sync"
        title: Translation.tr("TickTick Credentials")
        visible: !root.driveSubPageMode && root.selectedProvider === "ticktick"

        HelperLinkBox {
            Layout.fillWidth: true
            title: Translation.tr("TickTick Developer Center")
            text: Translation.tr("Register your application to get Client ID and Client Secret. Redirect URL: http://localhost:18321")
            isFirst: true

            RippleButtonWithIcon {
                mainText: Translation.tr("Open Website")
                materialIcon: "open_in_new"
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                colBackground: Appearance.colors.colLayer0
                colBackgroundHover: Appearance.colors.colLayer0Hover
                colRipple: Appearance.colors.colLayer0Active
                downAction: () => {
                    Qt.openUrlExternally("https://developer.ticktick.com/manage")
                }
            }
        }

        ConfigTextField {
            text: Translation.tr("Client ID")
            icon: "key"
            placeholderText: Translation.tr("Enter your TickTick Client ID")
            inputText: root.tempClientId
            textField.onTextChanged: root.tempClientId = textField.text.trim()
        }

        ConfigTextField {
            text: Translation.tr("Client Secret")
            icon: "vpn_key"
            placeholderText: Translation.tr("Enter your TickTick Client Secret")
            inputText: root.tempClientSecret
            textField.echoMode: TextInput.Password
            textField.onTextChanged: root.tempClientSecret = textField.text.trim()
        }

        ConfigTextField {
            text: Translation.tr("Access Token")
            icon: "token"
            placeholderText: Translation.tr("Enter or generate an Access Token")
            inputText: root.tempAccessToken
            textField.echoMode: TextInput.Password
            textField.onTextChanged: root.tempAccessToken = textField.text.trim()
        }
    }

    ContentSection {
        icon: "sync_saved_locally"
        title: Translation.tr("Actions")
        visible: !root.driveSubPageMode && root.selectedProvider === "ticktick"

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 48
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                enabled: !root.authRunning && root.tempClientId.length > 0 && root.tempClientSecret.length > 0

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 12
                    MaterialSymbol {
                        id: authIcon
                        text: "vpn_key"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnPrimaryContainer

                        RotationAnimation on rotation {
                            running: root.authRunning
                            from: 0
                            to: 360
                            duration: 1000
                            loops: Animation.Infinite
                        }
                    }
                    StyledText {
                        text: root.authRunning ? Translation.tr("Authorizing in browser...") : Translation.tr("Authorize & Generate Token")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.bold: true
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                onClicked: {
                    root.authRunning = true;
                    root.authErrorMsg = "";
                    authTokenProc.command = ["python3", Quickshell.shellPath("scripts/ticktick/get_token.py"), root.tempClientId, root.tempClientSecret];
                    authTokenProc.running = false;
                    authTokenProc.running = true;
                }
            }

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 48
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 12
                    MaterialSymbol {
                        text: "save"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledText {
                        text: Translation.tr("Save Credentials")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.bold: true
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }

                onClicked: {
                    saveCredentials();
                }
            }
        }
    }

    function saveCredentials() {
        // Save to Gnome Keyring via KeyringStorage in a single batch write
        KeyringStorage.setNestedFields([
            { path: ["apiKeys", "ticktick_client_id"], value: root.tempClientId },
            { path: ["apiKeys", "ticktick_client_secret"], value: root.tempClientSecret },
            { path: ["apiKeys", "ticktick_access_token"], value: root.tempAccessToken }
        ]);

        // Backup to .env
        backupEnvProc.command = ["python3", Quickshell.shellPath("scripts/ticktick/backup_env.py"), root.tempClientId, root.tempClientSecret, root.tempAccessToken];
        backupEnvProc.running = false;
        backupEnvProc.running = true;

        // Apply changes immediately to the service
        TickTickService.clientId = root.tempClientId;
        TickTickService.clientSecret = root.tempClientSecret;
        TickTickService.accessToken = root.tempAccessToken;
        TickTickService.refresh();

        console.log("[TickTickConfig] Credentials saved and applied.");
    }

    Process {
        id: authTokenProc
        stdout: StdioCollector {
            onStreamFinished: {
                let token = text.trim();
                if (token.length > 0 && !token.startsWith("ERROR")) {
                    root.tempAccessToken = token;
                    root.authRunning = false;
                    // Auto save credentials after successful authorization
                    Qt.callLater(() => {
                        saveCredentials();
                    });
                } else {
                    root.authErrorMsg = Translation.tr("Failed to get token: ") + token;
                    root.authRunning = false;
                }
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.authRunning = false;
                if (root.authErrorMsg === "") {
                    root.authErrorMsg = Translation.tr("Authorization process exited with code ") + code;
                }
            }
        }
    }

    Process {
        id: backupEnvProc
    }

    NoticeBox {
        Layout.fillWidth: true
        Layout.bottomMargin: 8
        topLeftRadius: Appearance.rounding.large
        topRightRadius: Appearance.rounding.large
        bottomLeftRadius: Appearance.rounding.large
        bottomRightRadius: Appearance.rounding.large
        visible: !root.driveSubPageMode
        text: Translation.tr("Google credentials (for Gmail, Google Tasks, and Google Drive) are set in ii/.env (GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET). Sports (ESPN) options live in the Sports bar widget page.")
    }

    ContentSection {
        Layout.fillWidth: true
        visible: !root.driveSubPageMode
        icon: "cloud_sync"
        title: Translation.tr("Google Drive Backup")

        ConfigSwitch {
            buttonIcon: "cloud_done"
            text: Translation.tr("Enable Google Drive backups")
            checked: Config.options.googleDrive.enabled
            configPage: Qt.resolvedUrl("widgets/GoogleDriveBackupConfig.qml")
            onCheckedChanged: {
                if (checked !== Config.options.googleDrive.enabled)
                    root.updateDriveOption("enabled", checked);
            }
        }
    }

    WarningBox {
        Layout.fillWidth: true
        Layout.topMargin: 8
        topLeftRadius: Appearance.rounding.large
        topRightRadius: Appearance.rounding.large
        bottomLeftRadius: Appearance.rounding.large
        bottomRightRadius: Appearance.rounding.large
        visible: root.driveSubPageMode && (root.driveUiError !== "" || GoogleDriveService.errorMessage !== "" || GoogleDriveService.warningMessage !== "")
        text: root.driveUiError !== ""
            ? root.driveUiError
            : GoogleDriveService.errorMessage !== ""
                ? GoogleDriveService.errorMessage
                : GoogleDriveService.warningMessage
    }

    HelperCodeBox {
        Layout.fillWidth: true
        Layout.topMargin: 8
        visible: root.driveSubPageMode && !GoogleDriveService.checking && !GoogleDriveService.rcloneInstalled
        topLeftRadius: Appearance.rounding.large
        topRightRadius: Appearance.rounding.large
        bottomLeftRadius: Appearance.rounding.large
        bottomRightRadius: Appearance.rounding.large
        icon: "terminal"
        title: Translation.tr("Install rclone · %1").arg(root.rcloneInstallFamily)
        text: Translation.tr("rclone is required for Google Drive backups. Copy the command for your system, run it in a terminal, then return here to authorize Google Drive.")
        codeSnippet: root.rcloneInstallCommand
        snippetWrapMode: Text.Wrap
    }

    // ── Google Drive — status hero ──────────────────────────────────────────
    ContentSection {
        Layout.fillWidth: true
        visible: root.driveSubPageMode
        icon: "cloud_sync"
        title: Translation.tr("Google Drive Backup")

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: heroLayout.implicitHeight + 32
            radius: Appearance.rounding.large
            color: Appearance.colors.colSecondaryContainer

            ColumnLayout {
                id: heroLayout
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 52
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colPrimary

                        Image {
                            anchors.centerIn: parent
                            width: 34
                            height: 34
                            source: "file://" + Quickshell.shellPath("assets/icons/google_drive.png")
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Google Drive Backup")
                            color: Appearance.colors.colOnSecondaryContainer
                            font.pixelSize: Appearance.font.pixelSize.huge
                            font.bold: true
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.lastSyncSummary()
                            color: Appearance.colors.colOnSecondaryContainer
                            opacity: 0.82
                            wrapMode: Text.WordWrap
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        implicitWidth: statusText.implicitWidth + 24
                        implicitHeight: statusText.implicitHeight + 12
                        radius: Appearance.rounding.full
                        color: GoogleDriveService.errorMessage !== ""
                            ? Appearance.colors.colErrorContainer
                            : GoogleDriveService.syncing
                                ? Appearance.colors.colPrimaryContainer
                                : GoogleDriveService.configured
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colTertiaryContainer

                        StyledText {
                            id: statusText
                            anchors.centerIn: parent
                            text: GoogleDriveService.errorMessage !== ""
                                ? Translation.tr("Action required")
                                : GoogleDriveService.syncing
                                    ? Translation.tr("Syncing")
                                    : GoogleDriveService.configured
                                        ? Translation.tr("Connected")
                                        : Translation.tr("Setup required")
                            color: GoogleDriveService.errorMessage !== ""
                                ? Appearance.colors.colOnErrorContainer
                                : GoogleDriveService.syncing
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : GoogleDriveService.configured
                                        ? Appearance.colors.colOnPrimary
                                        : Appearance.colors.colOnTertiaryContainer
                            font.bold: true
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    StyledProgressBar {
                        Layout.fillWidth: true
                        valueBarHeight: 8
                        value: GoogleDriveService.driveQuotaMb > 0
                            ? GoogleDriveService.driveUsedMb / GoogleDriveService.driveQuotaMb
                            : 0
                        highlightColor: Appearance.colors.colPrimary
                        trackColor: Appearance.colors.colLayer3
                    }

                    StyledText {
                        text: GoogleDriveService.driveQuotaMb > 0
                            ? root.formatMegabytes(GoogleDriveService.driveUsedMb) + " / " + root.formatMegabytes(GoogleDriveService.driveQuotaMb)
                            : GoogleDriveService.driveBackupUsageMb > 0
                                ? Translation.tr("Backup: %1").arg(root.formatMegabytes(GoogleDriveService.driveBackupUsageMb))
                                : Translation.tr("Drive usage unavailable")
                        color: Appearance.colors.colOnSecondaryContainer
                        font.bold: true
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: GoogleDriveService.syncing
                    implicitHeight: syncProgressLayout.implicitHeight + 24
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2

                    ColumnLayout {
                        id: syncProgressLayout
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            MaterialShapeWrappedMaterialSymbol {
                                text: "sync"
                                iconSize: Appearance.font.pixelSize.large
                                padding: 8
                                color: Appearance.colors.colPrimaryContainer
                                colSymbol: Appearance.colors.colOnPrimaryContainer
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    Layout.fillWidth: true
                                    text: GoogleDriveService.finalizing
                                        ? Translation.tr("Finalizing backup")
                                        : GoogleDriveService.currentFolder !== ""
                                            ? Translation.tr("Backing up %1").arg(GoogleDriveService.currentFolder)
                                            : Translation.tr("Preparing backup…")
                                    color: Appearance.colors.colOnLayer1
                                    font.bold: true
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: GoogleDriveService.finalizing
                                        ? GoogleDriveService.statsLine
                                        : GoogleDriveService.currentFile !== ""
                                            ? GoogleDriveService.currentFile
                                            : GoogleDriveService.statsLine !== ""
                                                ? GoogleDriveService.statsLine
                                                : Translation.tr("Scanning folders…")
                                    color: Appearance.colors.colOnLayer2
                                    elide: Text.ElideMiddle
                                    maximumLineCount: 1
                                }
                            }

                            StyledText {
                                text: GoogleDriveService.progress > 0
                                    ? Math.round(GoogleDriveService.progress * 100) + "%"
                                    : "—"
                                color: Appearance.colors.colOnLayer1
                                font.bold: true
                            }
                        }

                        StyledProgressBar {
                            Layout.fillWidth: true
                            valueBarHeight: 8
                            value: GoogleDriveService.progress > 0 ? GoogleDriveService.progress : 0.04
                            wavy: GoogleDriveService.progress <= 0
                            highlightColor: Appearance.colors.colPrimary
                            trackColor: Appearance.colors.colLayer3
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            StyledText {
                                Layout.fillWidth: true
                                text: root.syncProgressSummary()
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                text: root.formatDuration(GoogleDriveService.syncElapsedSeconds)
                                color: Appearance.colors.colOnLayer2
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 54
                        implicitHeight: 54
                        buttonRadius: Appearance.rounding.large
                        mainText: GoogleDriveService.syncing ? Translation.tr("Syncing…") : Translation.tr("Sync now")
                        materialIcon: GoogleDriveService.syncing ? "sync" : "cloud_upload"
                        colText: Appearance.colors.colOnPrimary
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        enabled: GoogleDriveService.configured
                        onClicked: GoogleDriveService.syncing ? GoogleDriveService.cancelSync() : GoogleDriveService.startSync()

                        StyledToolTip {
                            text: GoogleDriveService.syncing ? Translation.tr("Cancel sync") : Translation.tr("Sync now")
                        }
                    }

                    RippleButtonWithIcon {
                        id: heroRefreshButton
                        Layout.preferredWidth: 54
                        Layout.preferredHeight: 54
                        implicitWidth: 54
                        implicitHeight: 54
                        buttonRadius: Appearance.rounding.full
                        mainText: ""
                        materialIcon: "refresh"
                        colText: Appearance.colors.colOnSecondaryContainer
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        enabled: GoogleDriveService.configured && !GoogleDriveService.setupRunning
                        onClicked: GoogleDriveService.fetchDriveInfo()

                        StyledToolTip {
                            text: Translation.tr("Refresh Drive usage")
                        }
                    }
                }
            }
        }

    }

    // ── Google Drive — authorization ────────────────────────────────────────
    ContentSection {
        Layout.fillWidth: true
        visible: root.driveSubPageMode
        icon: "vpn_key"
        title: Translation.tr("Google Drive Authorization")

        HelperLinkBox {
            Layout.fillWidth: true
            title: Translation.tr("Google Cloud Console")
            text: Translation.tr("Enable the Google Drive API in the same Google Cloud project used by Gmail.")

            RippleButtonWithIcon {
                Layout.preferredHeight: 44
                implicitHeight: 44
                buttonRadius: Appearance.rounding.large
                mainText: Translation.tr("Open Console")
                materialIcon: "open_in_new"
                colText: Appearance.colors.colOnSecondaryContainer
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: Qt.openUrlExternally("https://console.cloud.google.com/apis/library/drive.googleapis.com")
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "security"
            text: Translation.tr("OAuth uses the existing Gmail client credentials from ii/.env. The access token is stored by rclone in its normal user configuration.")
        }
    }

    // This is a page-level action, intentionally kept outside the authorization section.
    RippleButtonWithIcon {
        Layout.fillWidth: true
        Layout.preferredHeight: 54
        implicitHeight: 54
        buttonRadius: Appearance.rounding.large
        mainText: GoogleDriveService.checking
            ? Translation.tr("Checking rclone…")
            : GoogleDriveService.setupRunning
                ? Translation.tr("Opening browser…")
                : GoogleDriveService.configured
                    ? Translation.tr("Re-authorize Google Drive")
                    : Translation.tr("Authorize Google Drive")
        materialIcon: GoogleDriveService.checking || GoogleDriveService.setupRunning ? "sync" : "vpn_key"
        colText: GoogleDriveService.configured ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimary
        colBackground: GoogleDriveService.configured ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimary
        colBackgroundHover: GoogleDriveService.configured ? Appearance.colors.colErrorContainerHover : Appearance.colors.colPrimaryHover
        colRipple: GoogleDriveService.configured ? Appearance.colors.colErrorContainerActive : Appearance.colors.colPrimaryActive
        enabled: !GoogleDriveService.checking && !GoogleDriveService.setupRunning && !GoogleDriveService.setupPendingCheck
        onClicked: GoogleDriveService.setupRclone()
    }

    // ── Google Drive — bento dashboard ──────────────────────────────────────
    ContentSection {
        Layout.fillWidth: true
        visible: root.driveSubPageMode
        icon: "monitoring"
        title: Translation.tr("Backup overview")
        customBackgroundColor: Appearance.colors.colLayer0

        GridLayout {
            id: backupBentoGrid
            readonly property bool compactLayout: width < 760
            Layout.fillWidth: true
            // 24 logical columns allow the bento spans to move in smaller
            // increments instead of jumping between visibly different 5/7
            // and 6/6 layouts.
            columns: compactLayout ? 1 : 24
            uniformCellWidths: true
            columnSpacing: 12
            rowSpacing: 12

            // Give every logical column the same zero-based stretch constraint.
            // Keep the constraints in a dedicated zero-height row: overlapping
            // them with the top cards makes Qt merge incompatible cell hints and
            // collapses whole column groups despite uniformCellWidths.
            Repeater {
                model: backupBentoGrid.compactLayout ? 1 : 24

                delegate: Item {
                    required property int index
                    Layout.row: backupBentoGrid.compactLayout ? 7 : 4
                    Layout.column: backupBentoGrid.compactLayout ? 0 : index
                    Layout.preferredWidth: 0
                    Layout.minimumWidth: 0
                    Layout.fillWidth: true
                    Layout.horizontalStretchFactor: 1
                    Layout.preferredHeight: 0
                    Layout.minimumHeight: 0
                    Layout.maximumHeight: 0
                    implicitHeight: 0
                }
            }

            StyledRectangle {
                id: periodSummaryCard
                Layout.column: 0
                Layout.row: 0
                Layout.columnSpan: backupBentoGrid.compactLayout ? 1 : 14
                Layout.rowSpan: 1
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                implicitHeight: 230
                radius: Appearance.rounding.large
                contentLayer: StyledRectangle.ContentLayer.Group
                color: Appearance.colors.colPrimaryContainer
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Transfer trend")
                            color: Appearance.colors.colOnPrimaryContainer
                            font.bold: true
                            font.pixelSize: Appearance.font.pixelSize.large
                            elide: Text.ElideRight
                        }

                        StyledComboBox {
                            id: activityMetricSelector
                            Layout.preferredWidth: 48
                            Layout.minimumWidth: 48
                            Layout.maximumWidth: 48
                            popupWidth: 184
                            iconOnly: true
                            textRole: "displayName"
                            model: root.activityMetrics
                            currentIndex: root.activityMetricIndex
                            onActivated: index => root.activityMetricIndex = index

                            StyledToolTip {
                                text: root.activityMetrics[root.activityMetricIndex].displayName
                                extraVisibleCondition: activityMetricSelector.hovered
                            }
                        }

                        StyledComboBox {
                            id: periodRangeSelector
                            Layout.preferredWidth: 104
                            Layout.minimumWidth: 96
                            Layout.maximumWidth: 108
                            popupWidth: 176
                            buttonIcon: "calendar_month"
                            textRole: "selectorName"
                            model: root.activityGranularities
                            currentIndex: root.activityGranularityIndex
                            onActivated: index => root.activityGranularityIndex = index

                            StyledToolTip {
                                text: root.activityGranularities[root.activityGranularityIndex].displayName
                                extraVisibleCondition: periodRangeSelector.hovered
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        UsageColumnChart {
                            anchors.fill: parent
                            visible: root.hasActivity
                            values: root.activityMetricIndex === 0 ? root.activityDataValues : root.activityTransferValues
                            labels: root.activityLabels
                            tooltipLabels: root.activityTooltipLabels
                            barColor: root.activityMetricIndex === 0 ? Appearance.colors.colPrimary : Appearance.colors.colTertiary
                            emptyColor: ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.84)
                            axisColor: ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.28)
                            gridLineColor: Appearance.colors.colOnPrimaryContainer
                            gridLineOpacity: 0.14
                            textureColor: Appearance.colors.colOnPrimaryContainer
                            textureOpacity: 0.30
                            barWidth: 30
                            labelStride: Math.max(1, Math.ceil(root.activityLabels.length / 6))
                            labelIndices: root.activityVisibleLabelIndices
                            formatValue: value => root.activityMetricIndex === 0
                                ? root.formatMegabytes(value)
                                : String(Math.round(value)) + " " + Translation.tr("backups")
                        }

                        PagePlaceholder {
                            anchors.fill: parent
                            anchors.margins: 8
                            visible: !root.hasActivity
                            shown: visible
                            icon: "monitoring"
                            title: Translation.tr("No sync activity yet")
                            description: Translation.tr("Completed backups will appear here.")
                            shape: MaterialShape.Shape.Cookie9Sided
                        }
                    }
                }
            }

            StyledRectangle {
                id: healthCard
                property var latestSync: root.recentSyncRows.length > 0 ? root.recentSyncRows[0] : null
                Layout.column: backupBentoGrid.compactLayout ? 0 : 13
                Layout.row: backupBentoGrid.compactLayout ? 3 : 1
                Layout.columnSpan: backupBentoGrid.compactLayout ? 1 : 11
                Layout.rowSpan: 1
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                implicitHeight: 220
                radius: Appearance.rounding.large
                contentLayer: StyledRectangle.ContentLayer.Group
                color: Appearance.colors.colSecondaryContainer

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Sync health")
                            color: Appearance.colors.colOnSecondaryContainer
                            font.bold: true
                            font.pixelSize: Appearance.font.pixelSize.large
                        }

                        MaterialShapeWrappedMaterialSymbol {
                            iconSize: Appearance.font.pixelSize.large
                            padding: 7
                            shape: MaterialShape.Shape.Circle
                            fill: 1
                            color: healthCard.latestSync && healthCard.latestSync.status !== "success"
                                ? Appearance.colors.colErrorContainer
                                : Appearance.colors.colSecondary
                            colSymbol: healthCard.latestSync && healthCard.latestSync.status !== "success"
                                ? Appearance.colors.colOnErrorContainer
                                : Appearance.colors.colOnSecondary
                            text: root.syncStatusIcon(healthCard.latestSync)
                        }
                    }

                    StyledText {
                        text: healthCard.latestSync
                            ? root.syncStatusLabel(healthCard.latestSync)
                            : Translation.tr("Waiting for first sync")
                        color: !healthCard.latestSync || healthCard.latestSync.status === "success"
                            ? Appearance.colors.colOnSecondaryContainer
                            : Appearance.colors.colError
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.bold: true
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: healthCard.latestSync
                            ? Translation.tr("Last sync · ") + root.entryTimeText(healthCard.latestSync)
                            : Translation.tr("No completed backup recorded yet")
                        color: ColorUtils.transparentize(Appearance.colors.colOnSecondaryContainer, 0.26)
                        wrapMode: Text.WordWrap
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        RowLayout {
                            Layout.fillWidth: true

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Success rate")
                                color: ColorUtils.transparentize(Appearance.colors.colOnSecondaryContainer, 0.26)
                            }

                            StyledText {
                                text: root.successfulSyncCount + root.failedSyncCount > 0
                                    ? Math.round(root.syncSuccessRatio * 100) + "%"
                                    : "—"
                                color: Appearance.colors.colOnSecondaryContainer
                                font.bold: true
                            }
                        }

                        StyledProgressBar {
                            Layout.fillWidth: true
                            valueBarHeight: 8
                            value: root.syncSuccessRatio
                            highlightColor: Appearance.colors.colSecondary
                            trackColor: ColorUtils.transparentize(Appearance.colors.colOnSecondaryContainer, 0.86)
                        }
                    }

                    Item { Layout.fillHeight: true }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                text: Translation.tr("Next run") + " · "
                                    + root.scheduleIntervalLabel(String(Config.options.googleDrive.syncInterval || "3d"))
                                color: ColorUtils.transparentize(Appearance.colors.colOnSecondaryContainer, 0.26)
                            }

                            StyledText {
                                text: root.nextRunLabel()
                                color: Appearance.colors.colOnSecondaryContainer
                                font.bold: true
                            }
                        }
                    }
                }
            }

            StyledRectangle {
                id: storageCard
                Layout.column: backupBentoGrid.compactLayout ? 0 : 14
                Layout.row: backupBentoGrid.compactLayout ? 1 : 0
                Layout.columnSpan: backupBentoGrid.compactLayout ? 1 : 10
                Layout.rowSpan: 1
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                implicitHeight: 230
                radius: Appearance.rounding.large
                contentLayer: StyledRectangle.ContentLayer.Group
                color: Appearance.colors.colLayer2
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Storage breakdown")
                            color: Appearance.colors.colOnLayer2
                            font.bold: true
                            font.pixelSize: Appearance.font.pixelSize.large
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        implicitHeight: 126

                        UsageSemiDonut {
                            id: storageDonut
                            width: Math.min(parent.width, 280)
                            height: Math.min(parent.height, 118)
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            values: root.storageSegments
                            segmentColors: [
                                Appearance.colors.colPrimary,
                                Appearance.colors.colSecondaryContainer,
                                Appearance.colors.colTertiary
                            ]
                            // The reference uses separated color segments on the
                            // card surface, without a competing full-track ring.
                            trackColor: ColorUtils.transparentize(Appearance.colors.colLayer3, 1)
                            // The band is intentionally thicker than the corner
                            // token so the ends read as small-radius corners, not
                            // as fully rounded pills.
                            thickness: Math.max(Appearance.font.pixelSize.huge,
                                Appearance.rounding.normal * 2)
                            segmentCornerRadius: Appearance.rounding.small
                            gapRadians: 0.045
                            // Restore the broad reference arc without changing
                            // the token-driven trace thickness.
                            radiusScale: 1.0
                            minimumSegmentRadians: 0.30
                        }

                        ColumnLayout {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: storageDonut.verticalCenter
                            anchors.verticalCenterOffset: storageDonut.height * 0.18
                            spacing: 0

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.storageQuotaMb > 0
                                    ? root.formatMegabytes(root.storageUsedMb)
                                    : root.storageBackupMb > 0
                                        ? root.formatMegabytes(root.storageBackupMb)
                                        : "—"
                                color: Appearance.colors.colOnLayer2
                                font.pixelSize: Appearance.font.pixelSize.huge
                                font.bold: true
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Translation.tr("Used storage")
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 3
                        columnSpacing: 8

                        Repeater {
                            model: [
                                { label: Translation.tr("Backups"), value: root.formatMegabytes(root.storageBackupMb) + " (" + root.storagePercentageLabel(root.storageBackupMb) + ")", color: Appearance.colors.colPrimary },
                                { label: Translation.tr("Other files"), value: root.formatMegabytes(root.storageOtherMb) + " (" + root.storagePercentageLabel(root.storageOtherMb) + ")", color: Appearance.colors.colSecondaryContainer },
                                { label: Translation.tr("Free space"), value: root.formatMegabytes(root.storageFreeMb) + " (" + root.storagePercentageLabel(root.storageFreeMb) + ")", color: Appearance.colors.colTertiary }
                            ]

                            delegate: ColumnLayout {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: 2
                                opacity: storageDonut.hoveredIndex < 0 || storageDonut.hoveredIndex === index ? 1.0 : 0.42

                                Behavior on opacity {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }

                                HoverHandler {
                                    id: storageLegendHover
                                    onHoveredChanged: {
                                        if (hovered)
                                            storageDonut.hoveredIndex = index;
                                        else if (storageDonut.hoveredIndex === index)
                                            storageDonut.hoveredIndex = -1;
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    MaterialShape {
                                        implicitSize: 9
                                        shape: MaterialShape.Shape.Circle
                                        color: modelData.color
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        elide: Text.ElideRight
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.value
                                    color: Appearance.colors.colOnLayer2
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.bold: true
                                    maximumLineCount: 1
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }

            StyledRectangle {
                id: heatmapCard
                Layout.column: 0
                Layout.row: backupBentoGrid.compactLayout ? 2 : 1
                Layout.columnSpan: backupBentoGrid.compactLayout ? 1 : 13
                Layout.rowSpan: backupBentoGrid.compactLayout ? 1 : 2
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                implicitHeight: backupBentoGrid.compactLayout ? 380 : 452
                radius: Appearance.rounding.large
                contentLayer: StyledRectangle.ContentLayer.Group
                clip: true
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true

                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 1

                            StyledText {
                                text: Translation.tr("Activity heatmap")
                                color: Appearance.colors.colOnLayer2
                                font.bold: true
                                font.pixelSize: Appearance.font.pixelSize.large
                            }

                            StyledText {
                                text: root.heatmapMonthLabel + " · " + root.heatmapActiveDaysLabel
                                color: Appearance.colors.colSubtext
                            }
                        }

                        Item { Layout.fillWidth: true }

                        RowLayout {
                            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                            spacing: 6

                            Repeater {
                                model: [
                                    { weight: 0.12, label: root.heatmapLegendLabel(0.12), texture: true },
                                    { weight: 0.42, label: root.heatmapLegendLabel(0.42), texture: true },
                                    { weight: 0.72, label: root.heatmapLegendLabel(0.72), texture: false },
                                    { weight: 1.0, label: root.heatmapLegendLabel(1.0), texture: false }
                                ]
                                delegate: RowLayout {
                                    required property var modelData
                                    spacing: 4

                                    MaterialShape {
                                        implicitSize: 9
                                        shape: MaterialShape.Shape.Square
                                        color: ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colLayer3, 1 - modelData.weight)
                                        opacity: modelData.texture ? 0.76 : 1.0
                                    }

                                    StyledText {
                                        text: modelData.label
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }
                                }
                            }
                        }

                    }

                    UsageActivityHeatmap {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: 0
                        cells: root.heatmapCells
                        weekLabels: root.heatmapWeekLabels
                        dayLabels: root.heatmapDayLabels
                        weekCount: root.heatmapWeekCount
                        cellSize: 0
                        cellSpacing: root.heatmapCellSpacing
                        activeColor: Appearance.colors.colPrimary
                        midColor: Appearance.colors.colTertiary
                        emptyColor: Appearance.colors.colLayer3
                    }

                }
            }

            StyledRectangle {
                id: timelineCard
                Layout.column: 0
                Layout.row: backupBentoGrid.compactLayout ? 5 : 3
                Layout.columnSpan: backupBentoGrid.compactLayout ? 1 : 12
                Layout.rowSpan: 1
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                implicitHeight: 210
                radius: Appearance.rounding.large
                contentLayer: StyledRectangle.ContentLayer.Group
                clip: true
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Recent syncs")
                            color: Appearance.colors.colOnLayer2
                            font.bold: true
                            font.pixelSize: Appearance.font.pixelSize.large
                        }

                        StyledText {
                            text: String(root.recentSyncRows.length)
                            color: Appearance.colors.colSubtext
                        }

                        MaterialShapeWrappedMaterialSymbol {
                            iconSize: Appearance.font.pixelSize.large
                            padding: 6
                            shape: MaterialShape.Shape.Circle
                            fill: 1
                            color: Appearance.colors.colSecondaryContainer
                            colSymbol: Appearance.colors.colOnSecondaryContainer
                            text: "history"
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        PagePlaceholder {
                            anchors.fill: parent
                            visible: !root.hasActivity
                            shown: visible
                            icon: "history"
                            title: Translation.tr("No sync history")
                            description: Translation.tr("Completed backups will appear here.")
                            shape: MaterialShape.Shape.Cookie9Sided
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            visible: root.hasActivity
                            spacing: 2

                        Repeater {
                            model: root.recentSyncRows.slice(0, 3)

                            delegate: Item {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 40
                                opacity: syncRowHover.hovered ? 1.0 : 0.86

                                Behavior on opacity {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }

                                HoverHandler { id: syncRowHover }

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 8

                                    MaterialShapeWrappedMaterialSymbol {
                                        iconSize: Appearance.font.pixelSize.normal
                                        padding: 6
                                        shape: MaterialShape.Shape.SoftBurst
                                        fill: 1
                                        color: ColorUtils.transparentize(root.syncStatusColor(modelData), 0.78)
                                        colSymbol: root.syncStatusColor(modelData)
                                        text: root.syncStatusIcon(modelData)
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.entryTimeText(modelData)
                                            color: Appearance.colors.colOnLayer2
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: String(modelData.fileCount || 0) + " " + Translation.tr("files")
                                                + " · " + root.formatMegabytes(modelData.sizeMb || 0)
                                            color: Appearance.colors.colSubtext
                                            elide: Text.ElideRight
                                        }
                                    }

                                    StyledText {
                                        text: root.entryDurationText(modelData)
                                        color: Appearance.colors.colSubtext
                                        visible: root.entryDurationSeconds(modelData) > 0
                                    }
                                }
                            }
                        }
                        }
                    }
                }
            }

            StyledRectangle {
                id: performanceCard
                Layout.column: backupBentoGrid.compactLayout ? 0 : 13
                Layout.row: backupBentoGrid.compactLayout ? 4 : 2
                Layout.columnSpan: backupBentoGrid.compactLayout ? 1 : 11
                Layout.rowSpan: 1
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                implicitHeight: 220
                radius: Appearance.rounding.large
                contentLayer: StyledRectangle.ContentLayer.Group
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: Translation.tr("Performance")
                            color: Appearance.colors.colOnLayer2
                            font.bold: true
                            font.pixelSize: Appearance.font.pixelSize.large
                            elide: Text.ElideRight
                        }

                        StyledRectangle {
                            implicitWidth: performanceTabRow.implicitWidth + 4
                            implicitHeight: 38
                            radius: Appearance.rounding.full
                            color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.90)
                            contentLayer: StyledRectangle.ContentLayer.Group

                            RowLayout {
                                id: performanceTabRow
                                anchors.fill: parent
                                anchors.margins: 2
                                spacing: 2

                                Repeater {
                                    model: root.performanceViews

                                    delegate: RippleButton {
                                        id: performanceViewButton
                                        required property var modelData
                                        required property int index
                                        implicitHeight: 34
                                        horizontalPadding: 11
                                        buttonRadius: Appearance.rounding.full
                                        buttonText: modelData.name
                                        toggled: root.performanceViewIndex === index
                                        colBackground: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 1)
                                        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.88)
                                        colBackgroundActive: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.82)
                                        colBackgroundToggled: Appearance.colors.colPrimaryContainer
                                        colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
                                        colBackgroundToggledActive: Appearance.colors.colPrimaryContainerActive
                                        colRipple: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.78)
                                        colRippleToggled: Appearance.colors.colPrimaryContainerActive
                                        onClicked: root.performanceViewIndex = index

                                        contentItem: StyledText {
                                            text: performanceViewButton.modelData.name
                                            color: root.performanceViewIndex === performanceViewButton.index
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer2
                                            font.bold: root.performanceViewIndex === performanceViewButton.index
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        PagePlaceholder {
                            anchors.fill: parent
                            visible: !root.hasPerformanceData
                            shown: visible
                            icon: "speed"
                            title: Translation.tr("Performance data pending")
                            description: Translation.tr("Future sync history will include speed and duration metrics.")
                            shape: MaterialShape.Shape.Cookie9Sided
                        }

                        StackLayout {
                            anchors.fill: parent
                            visible: root.hasPerformanceData
                            currentIndex: root.performanceViewIndex

                            Item {
                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        spacing: 18

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            MaterialShapeWrappedMaterialSymbol {
                                                iconSize: Appearance.font.pixelSize.large
                                                padding: 6
                                                shape: MaterialShape.Shape.SemiCircle
                                                fill: 1
                                                color: Appearance.colors.colSecondaryContainer
                                                colSymbol: Appearance.colors.colOnSecondaryContainer
                                                text: "data_usage"
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: Translation.tr("Largest transfer")
                                                color: Appearance.colors.colSubtext
                                                elide: Text.ElideRight
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: root.largestTransfer
                                                    ? root.formatMegabytes(root.largestTransfer.sizeMb || 0)
                                                    : "—"
                                                color: Appearance.colors.colOnLayer2
                                                font.pixelSize: Appearance.font.pixelSize.huge
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            MaterialShapeWrappedMaterialSymbol {
                                                iconSize: Appearance.font.pixelSize.large
                                                padding: 6
                                                shape: MaterialShape.Shape.Circle
                                                fill: 1
                                                color: Appearance.colors.colSecondaryContainer
                                                colSymbol: Appearance.colors.colOnSecondaryContainer
                                                text: "moving"
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: Translation.tr("Average transfer")
                                                color: Appearance.colors.colSubtext
                                                elide: Text.ElideRight
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: root.formatMegabytes(root.averageTransferMb)
                                                color: Appearance.colors.colOnLayer2
                                                font.pixelSize: Appearance.font.pixelSize.huge
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: Translation.tr("Recent volume") + " · " + root.formatMegabytes(root.recentTransferTotalMb)
                                            color: Appearance.colors.colSubtext
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            text: String(root.recentPerformanceRows.length) + " " + Translation.tr("recent runs")
                                            color: Appearance.colors.colOnLayer2
                                            font.bold: true
                                        }
                                    }
                                }
                            }

                            Item {
                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        spacing: 18

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            MaterialShapeWrappedMaterialSymbol {
                                                iconSize: Appearance.font.pixelSize.large
                                                padding: 6
                                                shape: MaterialShape.Shape.Circle
                                                fill: 1
                                                color: Appearance.colors.colSecondaryContainer
                                                colSymbol: Appearance.colors.colOnSecondaryContainer
                                                text: "speed"
                                            }

                                            StyledText {
                                                text: Translation.tr("Average speed")
                                                color: Appearance.colors.colSubtext
                                            }

                                            StyledText {
                                                text: root.hasDetailedPerformanceData
                                                    ? root.formatTransferSize(root.averageSpeedBytesPerSecond) + "/s"
                                                    : "—"
                                                color: Appearance.colors.colOnLayer2
                                                font.pixelSize: Appearance.font.pixelSize.huge
                                                font.bold: true
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            MaterialShapeWrappedMaterialSymbol {
                                                iconSize: Appearance.font.pixelSize.large
                                                padding: 6
                                                shape: MaterialShape.Shape.Square
                                                fill: 1
                                                color: Appearance.colors.colSecondaryContainer
                                                colSymbol: Appearance.colors.colOnSecondaryContainer
                                                text: "timer"
                                            }

                                            StyledText {
                                                text: Translation.tr("Average duration")
                                                color: Appearance.colors.colSubtext
                                            }

                                            StyledText {
                                                text: root.hasDetailedPerformanceData
                                                    ? root.formatDuration(root.averageDurationSeconds)
                                                    : "—"
                                                color: Appearance.colors.colOnLayer2
                                                font.pixelSize: Appearance.font.pixelSize.huge
                                                font.bold: true
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.hasDetailedPerformanceData
                                                ? Translation.tr("Measured during completed syncs")
                                                : Translation.tr("Timing telemetry pending")
                                            color: Appearance.colors.colSubtext
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            text: String(root.timedPerformanceCount) + " " + Translation.tr("timed runs")
                                            color: Appearance.colors.colOnLayer2
                                            font.bold: true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            StyledRectangle {
                id: versionsCard
                Layout.column: backupBentoGrid.compactLayout ? 0 : 12
                Layout.row: backupBentoGrid.compactLayout ? 6 : 3
                Layout.columnSpan: backupBentoGrid.compactLayout ? 1 : 12
                Layout.rowSpan: 1
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
                implicitHeight: 210
                radius: Appearance.rounding.large
                contentLayer: StyledRectangle.ContentLayer.Group
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: Translation.tr("Retention policy")
                            color: Appearance.colors.colOnLayer2
                            font.bold: true
                            font.pixelSize: Appearance.font.pixelSize.large
                            elide: Text.ElideRight
                        }

                        MaterialShapeWrappedMaterialSymbol {
                            iconSize: Appearance.font.pixelSize.large
                            padding: 6
                            shape: MaterialShape.Shape.Circle
                            fill: 1
                            color: Appearance.colors.colSecondaryContainer
                            colSymbol: Appearance.colors.colOnSecondaryContainer
                            text: "history"
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 0

                            StyledText {
                                text: String(Config.options.googleDrive.keepVersions || 0) + " " + Translation.tr("versions")
                                color: Appearance.colors.colOnLayer2
                                font.pixelSize: Appearance.font.pixelSize.huge
                                font.bold: true
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Historical copies kept on Drive")
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                        }

                        ColumnLayout {
                            Layout.minimumWidth: 0
                            spacing: 0

                            StyledText {
                                Layout.alignment: Qt.AlignRight
                                text: root.storageQuotaMb > 0
                                    ? root.formatMegabytes(root.storageBackupMb)
                                    : "—"
                                color: Appearance.colors.colOnLayer2
                                font.bold: true
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignRight
                                text: Translation.tr("Backup footprint")
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    StyledProgressBar {
                        Layout.fillWidth: true
                        visible: root.storageQuotaMb > 0
                        valueBarHeight: 8
                        value: root.backupFootprintRatio
                        highlightColor: Appearance.colors.colTertiary
                        trackColor: Appearance.colors.colLayer3
                    }

                    Item { Layout.fillHeight: true }

                    RowLayout {
                        Layout.fillWidth: true

                        StyledText {
                            Layout.fillWidth: true
                            text: Config.options.googleDrive.deleteRemoteOrphans
                                ? Translation.tr("Remote orphans are removed")
                                : Translation.tr("Remote orphans are preserved")
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }

                        StyledText {
                            visible: root.storageQuotaMb > 0
                            text: (root.backupFootprintRatio * 100).toFixed(2) + "%"
                            color: Appearance.colors.colOnLayer2
                            font.bold: true
                        }
                    }
                }
            }
        }
    }

    // ── Google Drive — folders ──────────────────────────────────────────────
    ContentSection {
        Layout.fillWidth: true
        visible: root.driveSubPageMode
        icon: "folder_copy"
        title: Translation.tr("Backup Folders")

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Choose the local folders that should be copied to Drive.")
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }

            RippleButtonWithIcon {
                mainText: Translation.tr("Add folder")
                materialIcon: "create_new_folder"
                colText: Appearance.colors.colOnPrimaryContainer
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                onClicked: root.openFolderPicker()
            }
        }

        Item {
            Layout.fillWidth: true
            visible: Config.options.googleDrive.backupFolders.length === 0
            implicitHeight: visible ? 140 : 0

            PagePlaceholder {
                anchors.fill: parent
                shown: parent.visible
                icon: "folder_off"
                title: Translation.tr("No folders configured")
                description: Translation.tr("Add a folder to start backing up.")
                shape: MaterialShape.Shape.Cookie9Sided
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: Config.options.googleDrive.backupFolders

                delegate: Rectangle {
                    id: folderRow
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: 56
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2

                    RowLayout {
                        id: folderRowLayout
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: folderRow.modelData.toLowerCase().includes("picture") ? "image" : folderRow.modelData.includes(".config") ? "settings" : "folder"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: folderRow.modelData
                            color: Appearance.colors.colOnLayer2
                            elide: Text.ElideMiddle
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: Translation.tr("Local")
                            color: Appearance.colors.colSubtext
                        }

                        RippleButtonWithIcon {
                            mainText: ""
                            materialIcon: "close"
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            implicitHeight: 36
                            buttonRadius: Appearance.rounding.full
                            colText: Appearance.colors.colOnLayer2
                            colBackground: Appearance.colors.colLayer3
                            colBackgroundHover: Appearance.colors.colLayer3Hover
                            colRipple: Appearance.colors.colLayer3Active
                            onClicked: root.removeBackupFolder(folderRow.index)
                        }
                    }
                }
            }
        }
    }

    // ── Google Drive — schedule ─────────────────────────────────────────────
    ContentSection {
        Layout.fillWidth: true
        visible: root.driveSubPageMode
        icon: "schedule"
        title: Translation.tr("Sync Schedule")

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Choose how often the backup service should run.")
            color: Appearance.colors.colSubtext
        }

        ConfigSwitch {
            buttonIcon: "cloud_done"
            text: Translation.tr("Enable Google Drive backups")
            checked: Config.options.googleDrive.enabled
            onCheckedChanged: {
                if (checked !== Config.options.googleDrive.enabled)
                    root.updateDriveOption("enabled", checked);
            }
        }

        ConfigSelectionArray {
            Layout.fillWidth: true
            currentValue: Config.options.googleDrive.syncInterval
            options: [
                { displayName: Translation.tr("1 hour"), value: "1h", icon: "hourglass_top" },
                { displayName: Translation.tr("4 hours"), value: "4h", icon: "schedule" },
                { displayName: Translation.tr("1 day"), value: "1d", icon: "today" },
                { displayName: Translation.tr("2 days"), value: "2d", icon: "date_range" },
                { displayName: Translation.tr("3 days"), value: "3d", icon: "calendar_month" }
            ]
            onSelected: value => root.updateDriveOption("syncInterval", value)
        }

        ConfigSwitch {
            buttonIcon: "power_settings_new"
            text: Translation.tr("Sync on boot")
            checked: Config.options.googleDrive.syncOnBoot
            onCheckedChanged: {
                if (checked !== Config.options.googleDrive.syncOnBoot)
                    root.updateDriveOption("syncOnBoot", checked);
            }
        }
    }

    // ── Google Drive — advanced settings entry ──────────────────────────────
    ContentSection {
        Layout.fillWidth: true
        visible: root.driveSubPageMode
        icon: "tune"
        title: Translation.tr("Advanced Drive Settings")
        tooltip: Translation.tr("Transfer limits, retention, network triggers and notifications.")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Appearance.sizes.elevationMargin / 2

            ConfigSubpageRow {
                buttonIcon: "tune"
                title: Translation.tr("Advanced Drive Settings")
                description: Translation.tr("Transfer limits, retention, network triggers and notifications")
                onClicked: root.activeSubPage = Qt.resolvedUrl("widgets/AdvancedDriveConfig.qml")
            }
        }
    }

    // ── Google Drive — exclusion patterns ───────────────────────────────────
    ContentSection {
        Layout.fillWidth: true
        visible: root.driveSubPageMode
        icon: "block"
        title: Translation.tr("Exclude Patterns")

        ConfigTextField {
            Layout.fillWidth: true
            text: Translation.tr("New pattern")
            icon: "filter_alt"
            tooltip: Translation.tr("Use rclone globs such as *.tmp, cache/ or **/*.log. A trailing / targets a directory; one pattern is added per entry.")
            placeholderText: Translation.tr("e.g. *.cache or build/")
            inputText: root.excludePatternDraft
            textField.onTextChanged: root.excludePatternDraft = textField.text
        }

        WarningBox {
            Layout.fillWidth: true
            visible: root.excludePatternError !== ""
            text: root.excludePatternError
        }

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Glob patterns ignored by rclone during each backup.")
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }

            RippleButtonWithIcon {
                mainText: Translation.tr("Add pattern")
                materialIcon: "add"
                colText: Appearance.colors.colOnPrimaryContainer
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                onClicked: root.addExcludePattern(root.excludePatternDraft)
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "help"
            text: Translation.tr("Examples: *.cache matches files with that suffix, .git/ excludes a directory, and **/*.log matches logs in any subfolder. Patterns are passed directly to rclone.")
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: excludeFlow.height

            Flow {
                id: excludeFlow
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 6

                Repeater {
                    model: Config.options.googleDrive.excludePatterns

                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        width: patternContent.implicitWidth + 24
                        height: 36
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colSecondaryContainer

                        RowLayout {
                            id: patternContent
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            spacing: 5

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "filter_alt"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSecondaryContainer
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                text: modelData
                                color: Appearance.colors.colOnSecondaryContainer
                                font.pixelSize: Appearance.font.pixelSize.small
                            }

                            Item {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24

                                RippleButton {
                                    anchors.fill: parent
                                    padding: 0
                                    leftPadding: 0
                                    rightPadding: 0
                                    topPadding: 0
                                    bottomPadding: 0
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colSecondaryContainer
                                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                    colRipple: Appearance.colors.colSecondaryContainerActive
                                    onClicked: root.removeExcludePattern(index)

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "close"
                                        iconSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Process {
        id: folderPickerProc
        command: ["bash", "-c", "if command -v zenity >/dev/null 2>&1; then zenity --file-selection --directory; elif command -v kdialog >/dev/null 2>&1; then kdialog --getexistingdirectory \"$PWD\"; else exit 127; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const selectedPath = text.trim();
                if (selectedPath)
                    root.addBackupFolder(selectedPath);
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 127)
                root.driveUiError = Translation.tr("Install zenity or kdialog to choose a backup folder.");
        }
    }
    }

    ConfigSubPageHost {
        id: subPageOverlay

        anchors.fill: parent
        z: 10
    }
}
