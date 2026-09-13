pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common

/**
 * Cloud backup and synchronization bridge for the Notes app.
 *
 * Implements "Reusar, não reimplementar":
 * - Does not create a second uploader or background timer.
 * - Manages the inclusion of Directories.notesDir inside the existing Google Drive
 *   backupFolders list (walked on schedule by GoogleDriveService/rclone).
 * - Triggers manual backup via IPC call googleDriveBackup sync.
 * - Dispatches notes_export.py and keep_import.py jobs.
 */
Singleton {
    id: root

    readonly property string notesFolder: Directories.notesDir
    readonly property bool driveEnabled: (Persistent.ready ? Persistent.states.googleDrive?.enabled : null) ?? Config.options.googleDrive.enabled
    property bool autoDrive: Persistent.ready ? (Persistent.states.notes?.driveBackup ?? false) : false

    function syncDriveFolder(): void {
        const drive = Persistent.ready ? Persistent.states.googleDrive : null;
        if (!drive)
            return;
        const current = Array.from(drive.backupFolders ?? []);
        const wanted = root.notesFolder;
        const has = wanted !== "" && current.indexOf(wanted) !== -1;

        if (root.autoDrive && wanted !== "" && !has) {
            drive.backupFolders = current.concat([wanted]);
            if (Config.options.googleDrive)
                Config.options.googleDrive.backupFolders = drive.backupFolders;
            return;
        }
        if (!root.autoDrive && has) {
            drive.backupFolders = current.filter(entry => entry !== wanted);
            if (Config.options.googleDrive)
                Config.options.googleDrive.backupFolders = drive.backupFolders;
        }
    }

    onAutoDriveChanged: root.syncDriveFolder()

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready) {
                root.autoDrive = Persistent.states.notes?.driveBackup ?? false;
                root.syncDriveFolder();
            }
        }
    }

    function toggleDriveBackup(): void {
        if (!Persistent.ready || !Persistent.states.notes)
            return;
        Persistent.states.notes.driveBackup = !Persistent.states.notes.driveBackup;
        root.autoDrive = Persistent.states.notes.driveBackup;
        root.syncDriveFolder();
    }

    function syncDriveNow(): void {
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "googleDriveBackup", "sync"]);
    }

    // ── Export Dispatcher ─────────────────────────────────────────────────

    signal exportFinished(bool success, string message, string outputPath)

    function exportNotes(format, destPath, noteId = "", isAll = false): void {
        const script = `${Directories.scriptPath}/notes/notes_export.py`;
        const args = ["python3", script, "--store", root.notesFolder, "--format", format, "--output", destPath];
        if (noteId && !isAll) {
            args.push("--note-id", noteId);
        } else if (isAll) {
            args.push("--all");
        }
        exportProcess.command = args;
        exportProcess.running = true;
    }

    Process {
        id: exportProcess
        stdout: StdioCollector {
            id: exportOutput
            onStreamFinished: {
                try {
                    const res = JSON.parse(exportOutput.text.trim());
                    root.exportFinished(res.ok === true, res.message || "", res.output || "");
                } catch (e) {
                    root.exportFinished(false, `The exporter answered with something unreadable: ${exportOutput.text}`, "");
                }
            }
        }
        stderr: StdioCollector {
            id: exportErr
        }
    }

    // ── Takeout Import Dispatcher ─────────────────────────────────────────

    signal importFinished(bool success, string message, int importedCount)

    function importTakeout(takeoutPath): void {
        const script = `${Directories.scriptPath}/notes/keep_import.py`;
        importProcess.command = ["python3", script, "--takeout", takeoutPath, "--store", root.notesFolder];
        importProcess.running = true;
    }

    Process {
        id: importProcess
        stdout: StdioCollector {
            id: importOutput
            onStreamFinished: {
                try {
                    const res = JSON.parse(importOutput.text.trim());
                    if (res.ok) {
                        NotesService.reload();
                        root.importFinished(true, `Importadas com sucesso: ${res.imported} notas (${res.updated} atualizadas).`, res.imported);
                    } else {
                        root.importFinished(false, res.message || Translation.tr("The import failed."), 0);
                    }
                } catch (e) {
                    root.importFinished(false, `The importer answered with something unreadable: ${importOutput.text}`, 0);
                }
            }
        }
    }

    Component.onCompleted: {
        if (Persistent.ready)
            root.syncDriveFolder();
    }
}
