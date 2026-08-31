pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Read-only Outlook → khal bridge for every Timetable view.
 *
 * The Python side rewrites only its own local ICS collection. CalendarSubscriptions
 * registers that collection as readonly, so a local edit can never be mistaken
 * for a write back to Microsoft Graph.
 */
Singleton {
    id: root

    readonly property var options: Config.options.calendar.timetable.imports.outlook
    readonly property bool enabled: Config.ready
        && (Config.options.calendar.timetable.imports.enable ?? false)
        && (root.options.enable ?? false)
    readonly property int syncIntervalMinutes: Math.max(15, Number(root.options.syncIntervalMinutes ?? 60))
    readonly property string collectionRoot: FileUtils.trimFileProtocol(Directories.state) + "/calendar/timetable-outlook"
    readonly property bool syncing: syncProcess.running || root.waitingForToken || root.waitingForCalendarConfig

    property bool waitingForToken: false
    property bool waitingForCalendarConfig: false
    property bool syncQueued: false
    property string lastError: ""
    property string lastStatus: ""
    property real lastSyncAt: 0

    function syncNow() {
        root.requestSync();
    }

    function requestSync() {
        if (!root.enabled)
            return;
        if (!CalendarService.khalAvailable) {
            root.lastError = Translation.tr("Calendar service unavailable.");
            return;
        }
        if (!OutlookService.authenticated) {
            root.lastError = Translation.tr("Connect Outlook before synchronizing its calendar.");
            return;
        }
        if (root.syncing) {
            root.syncQueued = true;
            return;
        }
        root.lastError = "";
        root.lastStatus = Translation.tr("Preparing Outlook calendar…");
        root.waitingForCalendarConfig = true;
        CalendarSubscriptions.requestApply();
        calendarConfigTimer.restart();
    }

    function beginAfterCalendarConfig() {
        if (!root.enabled) {
            root.waitingForCalendarConfig = false;
            return;
        }
        if (CalendarSubscriptions.applying) {
            calendarConfigTimer.restart();
            return;
        }
        root.waitingForCalendarConfig = false;
        if (CalendarSubscriptions.lastError.length > 0) {
            root.lastError = CalendarSubscriptions.lastError;
            root.finishSync();
            return;
        }
        root.waitingForToken = true;
        OutlookService.withAccessToken(token => {
            root.waitingForToken = false;
            if (!token) {
                root.lastError = OutlookService.lastError || Translation.tr("Microsoft authorization is unavailable.");
                root.finishSync();
                return;
            }
            root.beginSync(token);
        });
    }

    function beginSync(token) {
        if (!root.enabled)
            return;
        root.lastStatus = Translation.tr("Synchronizing Outlook calendar…");
        syncProcess.responseText = "";
        syncProcess.accessToken = String(token);
        syncProcess.stdinEnabled = true;
        syncProcess.running = true;
    }

    function finishSync() {
        root.lastSyncAt = Date.now();
        if (!root.syncQueued)
            return;
        root.syncQueued = false;
        Qt.callLater(root.requestSync);
    }

    Timer {
        id: calendarConfigTimer

        interval: 150
        repeat: false
        onTriggered: root.beginAfterCalendarConfig()
    }

    Timer {
        interval: root.syncIntervalMinutes * 60 * 1000
        running: root.enabled
        repeat: true
        triggeredOnStart: true
        onTriggered: root.requestSync()
    }

    Connections {
        target: Config.options.calendar.timetable.imports

        function onEnableChanged() {
            if (root.enabled)
                root.requestSync();
        }
    }

    Connections {
        target: Config.options.calendar.timetable.imports.outlook

        function onEnableChanged() {
            if (root.enabled)
                root.requestSync();
        }
    }

    Connections {
        target: OutlookService

        function onRefreshTokenChanged() {
            if (root.enabled && OutlookService.authenticated)
                root.requestSync();
        }
    }

    Connections {
        target: CalendarService

        function onRangeStartChanged() {
            if (root.enabled)
                root.requestSync();
        }

        function onRangeEndChanged() {
            if (root.enabled)
                root.requestSync();
        }
    }

    Process {
        id: syncProcess

        command: ["python3", Directories.scriptPath + "/outlook/calendar_sync.py"]
        stdinEnabled: true
        property string accessToken: ""
        property string responseText: ""

        onRunningChanged: {
            if (!running)
                return;
            write(JSON.stringify({
                accessToken: syncProcess.accessToken,
                destination: root.collectionRoot,
                start: CalendarService.rangeStart.toISOString(),
                end: CalendarService.rangeEnd.toISOString()
            }) + "\n");
            stdinEnabled = false;
        }

        stdout: StdioCollector {
            onStreamFinished: syncProcess.responseText = text.trim()
        }

        onExited: exitCode => {
            let reply;
            try {
                reply = JSON.parse(syncProcess.responseText);
            } catch (error) {
                reply = { ok: false, error: Translation.tr("Outlook calendar sync returned an unreadable response.") };
            }
            if (exitCode !== 0 || !reply?.ok) {
                root.lastError = String(reply?.error ?? Translation.tr("Could not synchronize the Outlook calendar."));
                root.lastStatus = "";
                root.finishSync();
                return;
            }
            OutlookService.updateAccountEmail(reply.account ?? "");
            root.lastStatus = Translation.tr("Synchronized %1 Outlook event(s).").arg(String(reply.events ?? 0));
            CalendarService.loadCalendarList();
            CalendarService.loadEvents();
            root.finishSync();
        }
    }
}
