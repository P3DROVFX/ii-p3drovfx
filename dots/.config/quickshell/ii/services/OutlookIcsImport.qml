pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/** Opt-in Outlook mail attachment scanner, sharing OutlookService's Mail.Read grant. */
Singleton {
    id: root

    readonly property var options: Config.options.calendar.timetable.imports.outlook.icsAttachments
    readonly property bool enabled: Config.ready
        && Persistent.ready
        && (Config.options.calendar.timetable.imports.enable ?? false)
        && (Config.options.calendar.timetable.imports.outlook.enable ?? false)
        && (root.options.enable ?? false)
    readonly property int maxMessages: Math.max(1, Math.min(50, Number(root.options.maxMessages ?? 25)))
    readonly property int scanIntervalMinutes: Math.max(5, Number(root.options.scanIntervalMinutes ?? 60))
    readonly property bool scanning: scanner.running || root.importing || root.waitingForToken

    property bool waitingForToken: false
    property bool importing: false
    property bool scanQueued: false
    property var importQueue: []
    property int importedEvents: 0
    property int skippedEvents: 0
    property string lastError: ""
    property string lastStatus: ""
    property real lastScanAt: 0

    readonly property string accountKey: String(OutlookService.activeAccountEmail ?? "").trim().toLowerCase()

    function knownKeys() {
        return Array.from(Persistent.states.cheatsheet.timetableOutlookIcsImports ?? []);
    }

    function persistentKey(candidate) {
        return root.accountKey + "|" + String(candidate?.key ?? "");
    }

    function remember(candidate) {
        const key = root.persistentKey(candidate);
        if (!key || root.knownKeys().includes(key))
            return;
        Persistent.states.cheatsheet.timetableOutlookIcsImports = root.knownKeys().concat([key]).slice(-400);
    }

    function scanNow() {
        root.requestScan();
    }

    function requestScan() {
        if (!root.enabled)
            return;
        if (!OutlookService.authenticated || !CalendarService.khalAvailable) {
            root.lastError = !OutlookService.authenticated
                ? Translation.tr("Connect Outlook before checking calendar attachments.")
                : Translation.tr("Calendar service unavailable.");
            return;
        }
        if (root.scanning) {
            root.scanQueued = true;
            return;
        }
        scanDebounce.restart();
    }

    function beginScan() {
        if (!root.enabled || root.scanning)
            return;
        root.lastError = "";
        root.lastStatus = Translation.tr("Checking Outlook calendar attachments…");
        root.waitingForToken = true;
        OutlookService.withAccessToken(token => {
            root.waitingForToken = false;
            if (!token) {
                root.lastError = OutlookService.lastError || Translation.tr("Microsoft authorization is unavailable.");
                root.finishScanCycle();
                return;
            }
            scanner.responseText = "";
            scanner.accessToken = String(token);
            scanner.stdinEnabled = true;
            scanner.running = true;
        });
    }

    function queueImports(candidates) {
        const known = new Set(root.knownKeys());
        root.importQueue = (candidates ?? []).filter(candidate => {
            const key = root.persistentKey(candidate);
            return key.length > 0 && !known.has(key) && String(candidate?.icsBase64 ?? "").length > 0;
        });
        root.importedEvents = 0;
        root.skippedEvents = 0;
        if (root.importQueue.length === 0) {
            root.lastStatus = Translation.tr("No new Outlook calendar attachments.");
            root.lastScanAt = Date.now();
            root.finishScanCycle();
            return;
        }
        root.importing = true;
        root.importNext();
    }

    function importNext() {
        if (!root.enabled || root.importQueue.length === 0) {
            root.importing = false;
            root.lastScanAt = Date.now();
            if (root.importedEvents > 0 || root.skippedEvents > 0) {
                root.lastStatus = Translation.tr("Imported %1 event(s), skipped %2 duplicate(s) from Outlook.")
                    .arg(String(root.importedEvents)).arg(String(root.skippedEvents));
            }
            root.finishScanCycle();
            return;
        }
        const candidate = root.importQueue[0];
        CalendarService.importIcsBase64(candidate.icsBase64, "", reply => {
            if (reply?.ok) {
                root.remember(candidate);
                root.importedEvents += Number(reply.imported ?? 0);
                root.skippedEvents += Number(reply.skipped ?? 0);
            } else {
                root.lastError = String(reply?.error ?? Translation.tr("Could not import an Outlook calendar attachment."));
            }
            root.importQueue = root.importQueue.slice(1);
            Qt.callLater(root.importNext);
        });
    }

    function finishScanCycle() {
        if (!root.scanQueued)
            return;
        root.scanQueued = false;
        Qt.callLater(root.requestScan);
    }

    Timer {
        id: scanDebounce

        interval: 100
        repeat: false
        onTriggered: root.beginScan()
    }

    Timer {
        interval: root.scanIntervalMinutes * 60 * 1000
        running: root.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: root.requestScan()
    }

    Connections {
        target: Config.options.calendar.timetable.imports.outlook.icsAttachments

        function onEnableChanged() {
            if (root.enabled)
                root.requestScan();
        }
    }

    Connections {
        target: OutlookService

        function onRefreshTokenChanged() {
            if (root.enabled && OutlookService.authenticated)
                root.requestScan();
        }

        function onActiveAccountEmailChanged() {
            if (root.enabled && OutlookService.authenticated)
                root.requestScan();
        }
    }

    Process {
        id: scanner

        command: ["python3", Directories.scriptPath + "/outlook/list_ics_attachments.py"]
        stdinEnabled: true
        property string accessToken: ""
        property string responseText: ""

        onRunningChanged: {
            if (!running)
                return;
            write(JSON.stringify({ accessToken: scanner.accessToken, maxMessages: root.maxMessages }) + "\n");
            stdinEnabled = false;
        }

        stdout: StdioCollector {
            onStreamFinished: scanner.responseText = text.trim()
        }

        onExited: exitCode => {
            let reply;
            try {
                reply = JSON.parse(scanner.responseText);
            } catch (error) {
                reply = { ok: false, error: Translation.tr("Outlook calendar scan returned an unreadable response.") };
            }
            if (exitCode !== 0 || !reply?.ok) {
                root.lastError = String(reply?.error ?? Translation.tr("Could not check Outlook calendar attachments."));
                root.lastStatus = "";
                root.finishScanCycle();
                return;
            }
            root.queueImports(reply.candidates ?? []);
        }
    }
}
