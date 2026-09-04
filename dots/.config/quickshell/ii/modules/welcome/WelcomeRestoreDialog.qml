import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * "I already have a desktop" — the first thing a phone asks, on the first page
 * of the Welcome.
 *
 * Someone reinstalling has a zip from the old machine and no reason to answer
 * ten questions before using it, so this reads the archive, says what is in it
 * and puts it back. Restoring here is the same script the Settings page calls;
 * what is different is that a fresh machine has no backup folder yet, so no
 * safety copy is taken - there is nothing worth keeping.
 */
WindowDialog {
    id: root

    backgroundWidth: 480

    // "" idle · a path once one is chosen
    property string archive: ""
    property var manifest: null
    property string failure: ""
    property bool done: false

    readonly property bool inspecting: ShellBackup.busy && ShellBackup.busyAction === "inspect"
    readonly property bool restoring: ShellBackup.busy && ShellBackup.busyAction === "restore"

    function reset() {
        root.archive = "";
        root.manifest = null;
        root.failure = "";
        root.done = false;
    }

    onShowChanged: {
        if (show)
            root.reset();
    }

    Connections {
        target: ShellBackup

        function onInspectFinished(ok, manifest, error) {
            if (root.archive === "")
                return;
            root.manifest = ok ? manifest : null;
            root.failure = ok ? "" : error;
            if (!ok)
                root.archive = "";
        }

        function onRestoreFinished(ok, error) {
            root.done = ok;
            root.failure = ok ? "" : error;
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        spacing: 10

        MaterialSymbol {
            text: root.done ? "check_circle" : "settings_backup_restore"
            iconSize: 26
            color: root.done ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
        }

        StyledText {
            Layout.fillWidth: true
            text: root.done
                ? Translation.tr("Your settings are back")
                : Translation.tr("Restore a backup")
            font.pixelSize: Appearance.font.pixelSize.larger
            font.family: Appearance.font.family.title
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer1
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
        text: root.done
            ? Translation.tr("The shell picked them up already. Carry on with the setup, or close it — everything is where you left it.")
            : root.archive === ""
                ? Translation.tr("Pick the zip you saved from your other install. It carries your settings, presets, notes, keybinds and the rest.")
                : Translation.tr("This replaces the settings on this machine with the ones in the backup.")
    }

    // ── What was chosen ──────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 6
        visible: root.archive !== "" && !root.done
        implicitHeight: chosenColumn.implicitHeight + 24
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2

        ColumnLayout {
            id: chosenColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 14
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: root.archive.split("/").pop()
                elide: Text.ElideMiddle
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.manifest !== null
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: root.manifest
                    ? Translation.tr("%1 files, from %2")
                        .arg(String(root.manifest.fileCount ?? 0))
                        .arg(String(root.manifest.host ?? "?"))
                    : ""
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.inspecting
                text: Translation.tr("Reading the backup…")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    StyledIndeterminateProgressBar {
        Layout.fillWidth: true
        Layout.topMargin: 6
        visible: root.restoring
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 6
        visible: root.failure !== ""
        implicitHeight: failureText.implicitHeight + 24
        radius: Appearance.rounding.normal
        color: Appearance.colors.colErrorContainer

        StyledText {
            id: failureText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 14
            text: root.failure
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnErrorContainer
        }
    }

    // ── Actions ──────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 10
        spacing: 10

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: root.done ? Translation.tr("Done") : Translation.tr("Cancel")
            enabled: !root.restoring
            onClicked: root.dismiss()
        }

        DialogButton {
            visible: !root.done && root.archive === ""
            buttonText: Translation.tr("Choose a file…")
            enabled: !picker.running && !ShellBackup.busy
            onClicked: {
                root.failure = "";
                picker.running = false;
                picker.running = true;
            }
        }

        DialogButton {
            visible: !root.done && root.archive !== ""
            buttonText: Translation.tr("Restore")
            enabled: root.manifest !== null && !ShellBackup.busy
            onClicked: {
                root.failure = "";
                ShellBackup.restoreArchive(root.archive);
            }
        }
    }

    Process {
        id: picker
        command: ["bash", "-c", "if command -v zenity >/dev/null 2>&1; then zenity --file-selection --file-filter=\"Backups | *.zip\"; elif command -v kdialog >/dev/null 2>&1; then kdialog --getopenfilename \"$HOME\" \"*.zip\"; else exit 127; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const picked = text.trim();
                if (picked === "")
                    return;
                root.archive = picked;
                root.manifest = null;
                ShellBackup.inspectArchive(picked);
            }
        }
        onExited: exitCode => {
            if (exitCode === 127)
                root.failure = Translation.tr("Install zenity or kdialog to choose a file.");
        }
    }
}
