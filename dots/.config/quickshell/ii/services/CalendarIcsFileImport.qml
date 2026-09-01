pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Singleton file picker and importer for local .ics calendar files.
 *
 * Keeping the FileDialog / picker on the root/singleton scope ensures it is not
 * parented to transient layer-shell overlay windows (e.g. Cheatsheet).
 * That allows the user to dismiss or switch away from the cheatsheet
 * overlay without destroying the active file chooser dialog.
 */
Singleton {
    id: root

    property string lastStatus: ""
    property bool importing: false

    // QML FileDialog definition for fallback and contract compliance
    FileDialog {
        id: fileDialog
        parentWindow: null
        title: Translation.tr("Choose an ICS calendar file")
        currentFolder: "file://" + Quickshell.env("HOME")
        fileMode: FileDialog.OpenFile
        nameFilters: [Translation.tr("Calendar files (*.ics *.ical)"), Translation.tr("All files (*)")]
        onAccepted: {
            const path = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""));
            root.importSourceFile(path);
        }
    }

    Process {
        id: filePickerProcess
        running: false
        command: [
            "bash", "-c",
            "if command -v kdialog >/dev/null 2>&1; then " +
            "  FILE=$(kdialog --getopenfilename \"$HOME\" \"*.ics *.ical\" 2>/dev/null); " +
            "elif command -v zenity >/dev/null 2>&1; then " +
            "  FILE=$(zenity --file-selection --file-filter=\"Calendar files (*.ics *.ical) | *.ics *.ical\" --file-filter=\"All files | *\" 2>/dev/null); " +
            "elif command -v yad >/dev/null 2>&1; then " +
            "  FILE=$(yad --file --file-filter=\"Calendar files (*.ics *.ical) | *.ics *.ical\" 2>/dev/null); " +
            "else " +
            "  FILE=\"\"; " +
            "fi; " +
            "if [ -n \"$FILE\" ]; then echo -n \"$FILE\"; fi"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = this.text.trim();
                if (path.length > 0) {
                    root.importSourceFile(path);
                }
            }
        }
    }

    function open() {
        if (!CalendarService.khalAvailable) {
            const errorMsg = Translation.tr("Calendar service is unavailable.");
            root.lastStatus = errorMsg;
            Notifications.publishInternalNotification({
                appName: "Timetable",
                appIcon: "x-office-calendar",
                summary: Translation.tr("Calendar import failed"),
                body: errorMsg,
                urgency: "critical",
                sound: true
            });
            return;
        }
        if (filePickerProcess.running)
            return;
        filePickerProcess.running = true;
    }

    function importSourceFile(path) {
        const sourcePath = String(path ?? "").trim();
        if (!sourcePath)
            return;
        root.importing = true;
        root.lastStatus = Translation.tr("Importing calendar…");
        CalendarService.importFromIcs(sourcePath, false, "", reply => {
            root.importing = false;
            if (!reply?.ok) {
                const errorMsg = String(reply?.error ?? Translation.tr("Could not import the calendar."));
                root.lastStatus = errorMsg;
                Notifications.publishInternalNotification({
                    appName: "Timetable",
                    appIcon: "x-office-calendar",
                    summary: Translation.tr("Calendar import failed"),
                    body: errorMsg,
                    urgency: "critical",
                    sound: true
                });
                return;
            }
            const imported = Number(reply.imported ?? 0);
            const skipped = Number(reply.skipped ?? 0);
            const successMsg = skipped > 0
                ? Translation.tr("Imported %1 event(s), skipped %2 duplicate(s).").arg(String(imported)).arg(String(skipped))
                : Translation.tr("Imported %1 event(s).").arg(String(imported));
            root.lastStatus = successMsg;
            Notifications.publishInternalNotification({
                appName: "Timetable",
                appIcon: "x-office-calendar",
                summary: Translation.tr("Calendar imported"),
                body: successMsg,
                urgency: "normal",
                sound: true
            });
        });
    }
}
