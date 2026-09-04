import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings backup: one zip of everything the shell knows about this user, and
 * the way back from it.
 *
 * The two folders it carries - `~/.config/illogical-impulse` and
 * `~/.local/state/quickshell` - are not reproducible from the repository, so a
 * reinstall without one of these is a new desktop rather than the same one.
 *
 * Restoring is the only action on this page that cannot be undone by hand, so
 * it asks twice: a row arms itself before it will run, and the script writes a
 * copy of the current settings beside the archive first.
 */
ContentPage {
    id: root
    forceWidth: false

    property bool showBackButton: false
    signal goBack

    property string pickerError: ""
    property string armedArchive: ""
    property string notice: ""

    readonly property var options: Persistent.states.shellBackup
    readonly property bool driveOn: Persistent.states.googleDrive?.enabled ?? false

    function setOption(key, value) {
        if (root.options)
            root.options[key] = value;
    }

    Component.onCompleted: ShellBackup.refresh()

    Connections {
        target: ShellBackup
        function onCreateFinished(ok, path, error) {
            root.notice = ok
                ? Translation.tr("Saved %1").arg(path.split("/").pop())
                : "";
        }
        function onRestoreFinished(ok, error) {
            root.armedArchive = "";
            root.notice = ok
                ? Translation.tr("Restored. Your settings are back.")
                : "";
        }
    }

    RowLayout {
        spacing: 12

        RippleButton {
            visible: root.showBackButton
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
            text: Translation.tr("Settings Backup")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── What a backup is ─────────────────────────────────────────────────────
    ContentSection {
        icon: "backup"
        title: Translation.tr("Backup")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "inventory_2"
            text: Translation.tr("A backup holds your settings, presets, profile pictures, extensions, to-do list, notes, clipboard pins, keybinds and usage history — everything a reinstall would not bring back. Downloaded preset repositories and the Python environment are left out; both come back on their own.")
        }

        ConfigSwitch {
            buttonIcon: "backup"
            text: Translation.tr("Back up my settings")
            checked: ShellBackup.enabled
            onCheckedChanged: {
                if (checked !== ShellBackup.enabled)
                    root.setOption("enabled", checked);
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: ShellBackup.enabled

            ContentSubsectionLabel {
                text: Translation.tr("Where backups are kept")
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: folderRow.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2

                RowLayout {
                    id: folderRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 14
                    spacing: 12

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: ShellBackup.folder === "" ? "folder_off" : "folder"
                        iconSize: 22
                        color: ShellBackup.folder === ""
                            ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer2
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: ShellBackup.folder === ""
                                ? Translation.tr("No folder chosen yet")
                                : ShellBackup.folder
                            elide: Text.ElideMiddle
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: root.pickerError !== ""
                            text: root.pickerError
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.m3colors.m3error
                        }
                    }

                    RippleButtonWithIcon {
                        Layout.alignment: Qt.AlignVCenter
                        materialIcon: "folder_open"
                        mainText: ShellBackup.folder === ""
                            ? Translation.tr("Choose folder") : Translation.tr("Change")
                        buttonRadius: Appearance.rounding.full
                        enabled: !folderPicker.running
                        onClicked: {
                            root.pickerError = "";
                            folderPicker.running = false;
                            folderPicker.running = true;
                        }
                    }
                }
            }

            ConfigSpinBox {
                icon: "layers"
                text: Translation.tr("Keep the newest backups")
                value: ShellBackup.keepCount
                from: 1
                to: 30
                stepSize: 1
                onValueChanged: {
                    if (value !== ShellBackup.keepCount)
                        root.setOption("keepCount", value);
                }
            }

            ConfigSpinBox {
                icon: "schedule"
                text: Translation.tr("Back up automatically every (days)")
                value: ShellBackup.intervalDays
                from: 1
                to: 60
                stepSize: 1
                onValueChanged: {
                    if (value !== ShellBackup.intervalDays)
                        root.setOption("intervalDays", value);
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Google Drive")
            }

            ConfigSwitch {
                buttonIcon: "cloud_upload"
                text: Translation.tr("Keep a copy in Google Drive")
                enabled: ShellBackup.folder !== ""
                checked: ShellBackup.autoDrive
                onCheckedChanged: {
                    if (checked !== ShellBackup.autoDrive)
                        root.setOption("autoDrive", checked);
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: ShellBackup.autoDrive && !root.driveOn
                materialIcon: "cloud_off"
                text: Translation.tr("Google Drive backups are switched off, so nothing is being uploaded yet. Turn them on in Accounts & Backup and the backup folder rides along with the sync that already runs.")
            }

            // Not a second uploader: the folder simply joins the set the
            // existing rclone sync already carries, on its own schedule.
            NoticeBox {
                Layout.fillWidth: true
                visible: ShellBackup.autoDrive && root.driveOn
                materialIcon: "cloud_sync"
                text: Translation.tr("The backup folder was added to what Google Drive syncs. Backups upload with the next scheduled sync.")
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: 8
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                RippleButtonWithIcon {
                    materialIcon: "backup"
                    mainText: Translation.tr("Back up now")
                    buttonRadius: Appearance.rounding.full
                    enabled: ShellBackup.configured && !ShellBackup.busy
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    colText: Appearance.colors.colOnPrimary
                    onClicked: {
                        root.notice = "";
                        ShellBackup.createBackup();
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: {
                        if (ShellBackup.busy)
                            return ShellBackup.busyAction === "restore"
                                ? Translation.tr("Restoring…") : Translation.tr("Packing everything up…");
                        if (root.notice !== "")
                            return root.notice;
                        if (ShellBackup.lastBackupTime === "")
                            return Translation.tr("No backup yet.");
                        return Translation.tr("Last backup: %1")
                            .arg(new Date(ShellBackup.lastBackupTime).toLocaleString(Qt.locale()));
                    }
                }
            }

            StyledIndeterminateProgressBar {
                Layout.fillWidth: true
                visible: ShellBackup.busy
            }

            WarningBox {
                Layout.fillWidth: true
                visible: ShellBackup.lastError !== ""
                text: ShellBackup.lastError
            }
        }
    }

    // ── The way back ─────────────────────────────────────────────────────────
    ContentSection {
        icon: "settings_backup_restore"
        title: Translation.tr("Restore")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "warning"
            text: Translation.tr("Restoring writes the backup's settings over the ones you have now. The current settings are saved beside the archive first, as a backup of their own, so a restore can itself be undone.")
        }

        RippleButtonWithIcon {
            Layout.alignment: Qt.AlignLeft
            materialIcon: "folder_zip"
            mainText: Translation.tr("Restore from a zip file…")
            buttonRadius: Appearance.rounding.full
            enabled: !ShellBackup.busy && !archivePicker.running
            onClicked: {
                root.pickerError = "";
                archivePicker.running = false;
                archivePicker.running = true;
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: ShellBackup.folder !== "" && ShellBackup.backups.length === 0
            text: Translation.tr("No backups in that folder yet.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        Repeater {
            model: ShellBackup.backups

            delegate: Rectangle {
                id: backupItem
                required property var modelData
                readonly property bool armed: root.armedArchive === backupItem.modelData.path

                Layout.fillWidth: true
                implicitHeight: backupRow.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: armed ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer2

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                RowLayout {
                    id: backupRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 14
                    spacing: 12

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: backupItem.modelData.valid ? "folder_zip" : "broken_image"
                        iconSize: 22
                        color: backupItem.armed
                            ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: backupItem.modelData.name
                            elide: Text.ElideMiddle
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: backupItem.armed
                                ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: backupItem.modelData.valid
                                ? Translation.tr("%1 · %2 files")
                                    .arg(ShellBackup.humanSize(backupItem.modelData.sizeBytes))
                                    .arg(String(backupItem.modelData.fileCount))
                                : Translation.tr("Not a settings backup, or damaged")
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: backupItem.armed
                                ? Appearance.colors.colOnErrorContainer : Appearance.colors.colSubtext
                        }
                    }

                    RippleButtonWithIcon {
                        Layout.alignment: Qt.AlignVCenter
                        visible: backupItem.armed
                        materialIcon: "close"
                        mainText: Translation.tr("Cancel")
                        buttonRadius: Appearance.rounding.full
                        onClicked: root.armedArchive = ""
                    }

                    // Two presses, because there is no third one that undoes it
                    // by itself. The second says what it will do.
                    RippleButtonWithIcon {
                        Layout.alignment: Qt.AlignVCenter
                        enabled: backupItem.modelData.valid && !ShellBackup.busy
                        materialIcon: backupItem.armed ? "restart_alt" : "settings_backup_restore"
                        mainText: backupItem.armed
                            ? Translation.tr("Overwrite my settings") : Translation.tr("Restore")
                        buttonRadius: Appearance.rounding.full
                        colBackground: backupItem.armed
                            ? Appearance.m3colors.m3error : Appearance.colors.colLayer3
                        colText: backupItem.armed
                            ? Appearance.m3colors.m3onError : Appearance.colors.colOnLayer3
                        onClicked: {
                            if (!backupItem.armed) {
                                root.armedArchive = backupItem.modelData.path;
                                return;
                            }
                            root.notice = "";
                            ShellBackup.restoreArchive(backupItem.modelData.path);
                        }
                    }
                }
            }
        }
    }

    // ── Pickers ──────────────────────────────────────────────────────────────

    Process {
        id: folderPicker
        command: ["bash", "-c", "if command -v zenity >/dev/null 2>&1; then zenity --file-selection --directory; elif command -v kdialog >/dev/null 2>&1; then kdialog --getexistingdirectory \"$HOME\"; else exit 127; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const picked = text.trim();
                if (picked !== "")
                    root.setOption("folder", picked);
            }
        }
        onExited: exitCode => {
            if (exitCode === 127)
                root.pickerError = Translation.tr("Install zenity or kdialog to choose a folder.");
        }
    }

    Process {
        id: archivePicker
        command: ["bash", "-c", "if command -v zenity >/dev/null 2>&1; then zenity --file-selection --file-filter=\"Backups | *.zip\"; elif command -v kdialog >/dev/null 2>&1; then kdialog --getopenfilename \"$HOME\" \"*.zip\"; else exit 127; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const picked = text.trim();
                if (picked !== "")
                    root.armedArchive = picked;
            }
        }
        onExited: exitCode => {
            if (exitCode === 127)
                root.pickerError = Translation.tr("Install zenity or kdialog to choose a file.");
        }
    }

    // A zip chosen from outside the backup folder has no row to arm, so it
    // gets its own confirmation strip.
    ContentSection {
        icon: "folder_zip"
        title: Translation.tr("Chosen file")
        visible: root.armedArchive !== ""
            && !ShellBackup.backups.some(entry => entry.path === root.armedArchive)

        StyledText {
            Layout.fillWidth: true
            text: root.armedArchive
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer1
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            RippleButtonWithIcon {
                materialIcon: "restart_alt"
                mainText: Translation.tr("Overwrite my settings")
                buttonRadius: Appearance.rounding.full
                enabled: !ShellBackup.busy
                colBackground: Appearance.m3colors.m3error
                colText: Appearance.m3colors.m3onError
                onClicked: {
                    root.notice = "";
                    ShellBackup.restoreArchive(root.armedArchive);
                }
            }

            RippleButtonWithIcon {
                materialIcon: "close"
                mainText: Translation.tr("Cancel")
                buttonRadius: Appearance.rounding.full
                onClicked: root.armedArchive = ""
            }
        }
    }
}
