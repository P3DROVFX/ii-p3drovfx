pragma Singleton
pragma ComponentBehavior: Bound

import qs
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Owns the system pickers used by Media Mode before a local-player session
 * exists. QtQuick.Dialogs has no visible parent window in this layer-shell
 * context on some portal setups, so the picker process is independent from
 * MediaMode's transient Overlay PanelWindow.
 *
 * The selection is always handed to the transactional scanner. Its purpose
 * tells LocalMediaService whether a completed manifest replaces the current
 * session or appends to its local playlist; the dialog never starts audio.
 */
Singleton {
    id: root

    property string lastSelectionDescription: ""
    property string selectionPurpose: "open"
    property string pickerKind: ""
    property bool reopenMediaModeAfterPicker: false
    signal musicFilesSelected(paths: var, purpose: string)
    signal musicFolderSelected(path: string, purpose: string)

    function selectedPaths(raw: string): var {
        // Picker output is newline-terminated; do not trim selected paths, as
        // spaces are valid filename characters.
        const text = String(raw ?? "").replace(/\r?\n$/, "");
        if (text.length === 0 || text === "__no_picker__")
            return [];
        return text.split(/\u001f|\r?\n/)
            .filter(path => path.length > 0);
    }

    function chooseMusicFiles(purpose = "open"): void {
        queueSystemPicker("files", purpose);
    }

    function chooseMusicFolder(purpose = "open"): void {
        queueSystemPicker("folder", purpose);
    }

    function queueSystemPicker(kind: string, purpose: string): void {
        if (filePickerProcess.running || folderPickerProcess.running)
            return;
        selectionPurpose = purpose;
        pickerKind = kind;
        reopenMediaModeAfterPicker = true;
        pickerReceivedValidOutput = false;
        console.info("[LocalMediaSelection] requested", kind, "picker");
        // A system picker is a normal desktop window. It cannot appear above
        // the Media Mode's layer-shell Overlay, so let the focused Media Mode
        // destroy itself before launching the picker.
        GlobalStates.mediaModeCloseAllTrigger++;
        pickerLaunchTimer.restart();
    }

    readonly property var filePickerCommand: [
        "bash", "-c",
        "if command -v kdialog >/dev/null 2>&1; then "
        + "kdialog --title \"Open File\" --getopenfilename \"$HOME\" \"Music files (*.mp3 *.flac *.opus *.ogg *.m4a *.aac *.wav *.wma *.aiff)\" --multiple --separate-output 2>/dev/null; "
        + "elif command -v zenity >/dev/null 2>&1; then "
        + "zenity --title=\"Open File\" --file-selection --multiple --separator=$'\\037' --file-filter=\"Music files | *.mp3 *.flac *.opus *.ogg *.m4a *.aac *.wav *.wma *.aiff\" --file-filter=\"All files | *\" 2>/dev/null; "
        + "elif command -v yad >/dev/null 2>&1; then "
        + "yad --title=\"Open File\" --file --multiple --separator=$'\\037' --file-filter=\"Music files | *.mp3 *.flac *.opus *.ogg *.m4a *.aac *.wav *.wma *.aiff\" --file-filter=\"All files | *\" 2>/dev/null; "
        + "else printf '__no_picker__'; fi"
    ]

    readonly property var folderPickerCommand: [
        "bash", "-c",
        "if command -v kdialog >/dev/null 2>&1; then "
        + "kdialog --title \"Open Folder\" --getexistingdirectory \"$HOME\" 2>/dev/null; "
        + "elif command -v zenity >/dev/null 2>&1; then "
        + "zenity --title=\"Open Folder\" --file-selection --directory 2>/dev/null; "
        + "elif command -v yad >/dev/null 2>&1; then "
        + "yad --title=\"Open Folder\" --file --directory 2>/dev/null; "
        + "else printf '__no_picker__'; fi"
    ]

    Timer {
        id: pickerLaunchTimer
        // BackgroundRoot returns keyboard focus and destroys its Overlay after
        // 60ms.  250 ms gives the compositor enough time to fully unmap the
        // layer-shell surface so the system picker never appears behind it.
        interval: 250
        onTriggered: {
            console.info("[LocalMediaSelection] launching", root.pickerKind, "picker");
            if (root.pickerKind === "folder")
                folderPickerProcess.running = true;
            else
                filePickerProcess.running = true;
        }
    }

    Process {
        id: filePickerProcess
        running: false
        // Keep the command declarative. The existing global pickers in Ai.qml
        // and the settings pages work this way; assigning `command` after an
        // overlay teardown can leave QProcess without a program to launch.
        command: root.filePickerCommand

        stdout: StdioCollector {
            id: pickerOutput
            onStreamFinished: {
                root.handlePickerOutput(pickerOutput.text, "files");
            }
        }

        onExited: (exitCode, exitStatus) => root.finishPicker(exitCode, exitStatus, "files")
    }

    Process {
        id: folderPickerProcess
        running: false
        command: root.folderPickerCommand

        stdout: StdioCollector {
            id: folderPickerOutput
            onStreamFinished: root.handlePickerOutput(folderPickerOutput.text, "folder")
        }

        onExited: (exitCode, exitStatus) => root.finishPicker(exitCode, exitStatus, "folder")
    }

    // Whether handlePickerOutput received at least one usable path for this
    // picker session.  finishPicker checks this before reopening Media Mode.
    property bool pickerReceivedValidOutput: false

    function handlePickerOutput(output: string, kind: string): void {
        const raw = String(output ?? "").replace(/\r?\n$/, "");
        if (raw === "__no_picker__") {
            lastSelectionDescription = Translation.tr("Install kdialog, zenity, or yad to choose music.");
            return;
        }
        const paths = selectedPaths(raw);
        if (paths.length === 0)
            return;
        pickerReceivedValidOutput = true;
        if (kind === "folder") {
            lastSelectionDescription = Translation.tr("Music folder selected");
            musicFolderSelected(paths[0], selectionPurpose);
            return;
        }
        lastSelectionDescription = paths.length === 1
            ? Translation.tr("1 music file selected")
            : String(paths.length) + Translation.tr(" music files selected");
        musicFilesSelected(paths, selectionPurpose);
    }

    function finishPicker(exitCode: int, exitStatus: var, kind: string): void {
        console.info("[LocalMediaSelection]", kind, "picker exited", exitCode, exitStatus);
        const shouldReopen = reopenMediaModeAfterPicker;
        reopenMediaModeAfterPicker = false;
        // Only reopen Media Mode when the picker completed successfully and
        // actually produced valid paths.  A cancelled dialog (exit code != 0)
        // or an empty selection must not trigger a reopen.
        if (!shouldReopen || exitCode !== 0 || !pickerReceivedValidOutput)
            return;
        pickerReceivedValidOutput = false;
        // Let the accepted signal start the transactional scan first; the
        // reopened window can then show its real import status.
        Qt.callLater(() => GlobalStates.requestMediaMode("open"));
    }

    IpcHandler {
        target: "localMediaSelection"

        function chooseFiles(purpose: string) {
            root.chooseMusicFiles(purpose && purpose.length > 0 ? purpose : "open");
        }

        function chooseFolder(purpose: string) {
            root.chooseMusicFolder(purpose && purpose.length > 0 ? purpose : "open");
        }
    }
}
