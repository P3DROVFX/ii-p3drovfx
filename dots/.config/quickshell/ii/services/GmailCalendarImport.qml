pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Opt-in bridge from Gmail ICS attachments into the local Timetable calendar.
 * The scanner returns only bounded attachment bytes; CalendarService owns the
 * actual khal mutation queue and Persistent stores a compact replay guard.
 */
Singleton {
    id: root

    readonly property var options: Config.options.calendar.timetable.imports.gmailIcs
    readonly property bool enabled: Config.ready
        && Persistent.ready
        && Config.options.calendar.timetable.imports.enable
        && (root.options.enable ?? false)
    readonly property int maxMessages: Math.max(1, Math.min(50, Number(root.options.maxMessages ?? 25)))
    readonly property int scanIntervalMinutes: Math.max(5, Number(root.options.scanIntervalMinutes ?? 60))
    readonly property bool scanning: gmailIcsScanner.running || root.importing

    property bool importing: false
    property bool scanQueued: false
    property var importQueue: []
    property int importedEvents: 0
    property int skippedEvents: 0
    property string lastError: ""
    property string lastStatus: ""
    property real lastScanAt: 0

    readonly property string accountKey: String(EmailService.userEmail ?? "").trim().toLowerCase()

    function knownKeys() {
        return Array.from(Persistent.states.cheatsheet.timetableGmailIcsImports ?? []);
    }

    function persistentKey(candidate) {
        return root.accountKey + "|" + String(candidate?.key ?? "");
    }

    function remember(candidate) {
        const key = root.persistentKey(candidate);
        if (!key || root.knownKeys().includes(key))
            return;
        const next = root.knownKeys().concat([key]);
        Persistent.states.cheatsheet.timetableGmailIcsImports = next.slice(-400);
    }

    function scanNow() {
        root.requestScan();
    }

    function requestScan() {
        if (!root.enabled)
            return;
        if (!EmailService.authenticated || !CalendarService.khalAvailable) {
            root.lastError = !EmailService.authenticated
                ? Translation.tr("Connect Gmail before checking calendar attachments.")
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
        if (!root.enabled || !EmailService.authenticated || !CalendarService.khalAvailable || root.scanning)
            return;
        const token = EmailService.calendarImportToken();
        if (!token) {
            root.lastError = Translation.tr("Gmail authorization is unavailable.");
            return;
        }
        root.lastError = "";
        root.lastStatus = Translation.tr("Checking Gmail calendar attachments…");
        gmailIcsScanner.responseText = "";
        gmailIcsScanner.command = [
            "python3", Directories.scriptPath + "/email/list_ics_attachments.py",
            token, String(root.maxMessages)
        ];
        gmailIcsScanner.running = true;
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
            root.lastStatus = Translation.tr("No new Gmail calendar attachments.");
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
                root.lastStatus = Translation.tr("Imported %1 event(s), skipped %2 duplicate(s) from Gmail.")
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
                root.lastError = String(reply?.error ?? Translation.tr("Could not import a Gmail calendar attachment."));
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
        target: Config.options.calendar.timetable.imports

        function onEnableChanged() {
            if (root.enabled)
                root.requestScan();
        }
    }

    Connections {
        target: Config.options.calendar.timetable.imports.gmailIcs

        function onEnableChanged() {
            if (root.enabled)
                root.requestScan();
        }
    }

    Connections {
        target: EmailService

        function onAuthenticatedChanged() {
            if (EmailService.authenticated)
                root.requestScan();
        }

        function onUserEmailChanged() {
            if (EmailService.authenticated)
                root.requestScan();
        }
    }

    Process {
        id: gmailIcsScanner
        command: ["echo", "{}"]
        property string responseText: ""

        stdout: StdioCollector {
            onStreamFinished: gmailIcsScanner.responseText = text.trim()
        }

        onExited: exitCode => {
            let reply = null;
            try {
                reply = JSON.parse(gmailIcsScanner.responseText);
            } catch (error) {
                reply = { ok: false, error: Translation.tr("Gmail calendar scan returned an unreadable response.") };
            }
            if (exitCode !== 0 || !reply?.ok) {
                root.lastError = String(reply?.error ?? Translation.tr("Could not check Gmail calendar attachments."));
                root.lastStatus = "";
                root.finishScanCycle();
                return;
            }
            root.queueImports(reply.candidates ?? []);
        }
    }
}
