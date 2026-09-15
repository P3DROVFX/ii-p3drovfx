import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "../overview/filebrowser"

/**
 * In-player local file and folder explorer for Media Mode.
 * Powered by FileBrowserBackend (python3 file_browser_helper.py).
 * Supports browsing all storage devices, mounted partitions (/mnt),
 * hidden folders, audio filtering, single-track play, and folder queueing.
 */
Item {
    id: root

    signal closeRequested()
    signal trackPlayed()
    signal folderPlayed()

    property color accentColor: Appearance.colors.colPrimary
    property color accentContainerColor: Appearance.colors.colPrimaryContainer
    property color onAccentContainerColor: Appearance.colors.colOnPrimaryContainer

    property bool audioOnly: true
    property bool showHidden: false

    readonly property string initialDirectory: {
        if (Directories.music && Directories.music.length > 0)
            return FileUtils.trimFileProtocol(Directories.music);
        return FileUtils.trimFileProtocol(Directories.home);
    }

    readonly property string currentDirectoryPath: backend.currentPath.length > 0
        ? backend.currentPath
        : initialDirectory

    readonly property var filteredEntries: {
        const list = backend.entries;
        if (!list || list.length === 0)
            return [];
        if (!root.audioOnly)
            return list;
        // Never filter out directories, so user can navigate anywhere
        return list.filter(entry => entry.isDir || entry.isAudio);
    }

    visible: opacity > 0
    opacity: 0

    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    function open(): void {
        root.opacity = 1;
        dialogCard.forceActiveFocus();
        if (backend.currentPath.length === 0)
            navigateTo(initialDirectory);
    }

    function close(): void {
        root.opacity = 0;
        root.closeRequested();
    }

    function navigateTo(path: string): void {
        if (!path || path.length === 0)
            return;
        const clean = FileUtils.trimFileProtocol(path).trim();
        const target = clean.length === 0 ? "/" : clean;
        backend.listDirectory(target, root.showHidden);
    }

    function toggleShowHidden(): void {
        root.showHidden = !root.showHidden;
        backend.listDirectory(root.currentDirectoryPath, root.showHidden);
    }

    Component.onCompleted: {
        navigateTo(initialDirectory);
    }

    // Backend process for directory listing and metadata inspection
    FileBrowserBackend {
        id: backend
    }

    // Semi-transparent backdrop
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.65)

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    // Centered Modal Dialog Card
    Rectangle {
        id: dialogCard
        anchors.centerIn: parent
        width: Math.min(1080, parent.width - 48)
        height: Math.min(740, parent.height - 48)
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh
        border.color: Appearance.colors.colOutlineVariant
        border.width: 1
        clip: true
        focus: true

        scale: 0.94 + 0.06 * root.opacity
        Behavior on scale {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        // Keyboard shortcut ESC to close
        Keys.onEscapePressed: event => {
            event.accepted = true;
            root.close();
        }

        // Prevent clicks inside the dialog from closing the modal
        MouseArea {
            anchors.fill: parent
            preventStealing: true
            onClicked: {}
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            // ── Top Header ──────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    width: 40
                    height: 40
                    radius: Appearance.rounding.full
                    color: root.accentContainerColor

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "library_music"
                        iconSize: 20
                        color: root.onAccentContainerColor
                    }
                }

                ColumnLayout {
                    spacing: 2

                    StyledText {
                        text: Translation.tr("Local Music Explorer")
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSurface
                    }

                    StyledText {
                        text: Translation.tr("Browse local disks, folders and music tracks")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                // Toggle: Show Hidden Folders / Files
                RippleButton {
                    implicitHeight: 36
                    implicitWidth: hiddenRow.implicitWidth + 20
                    buttonRadius: Appearance.rounding.full
                    colBackground: root.showHidden ? root.accentContainerColor : Appearance.colors.colLayer2Base
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: root.toggleShowHidden()

                    RowLayout {
                        id: hiddenRow
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            iconSize: 16
                            color: root.showHidden ? root.onAccentContainerColor : Appearance.colors.colOnSurfaceVariant
                            text: root.showHidden ? "visibility" : "visibility_off"
                        }

                        StyledText {
                            text: root.showHidden ? Translation.tr("Hidden: ON") : Translation.tr("Hidden: OFF")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: root.showHidden ? Font.DemiBold : Font.Normal
                            color: root.showHidden ? root.onAccentContainerColor : Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    StyledToolTip {
                        text: root.showHidden
                            ? Translation.tr("Showing hidden folders and files. Click to hide.")
                            : Translation.tr("Hidden folders are hidden. Click to show them.")
                    }
                }

                // Toggle: Audio only vs All files
                RippleButton {
                    implicitHeight: 36
                    implicitWidth: filterRow.implicitWidth + 24
                    buttonRadius: Appearance.rounding.full
                    colBackground: root.audioOnly ? root.accentContainerColor : Appearance.colors.colLayer2Base
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: root.audioOnly = !root.audioOnly

                    RowLayout {
                        id: filterRow
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            iconSize: 16
                            color: root.audioOnly ? root.onAccentContainerColor : Appearance.colors.colOnSurfaceVariant
                            text: root.audioOnly ? "audio_file" : "folder"
                        }

                        StyledText {
                            text: root.audioOnly ? Translation.tr("Audio only") : Translation.tr("All files")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: root.audioOnly ? Font.DemiBold : Font.Normal
                            color: root.audioOnly ? root.onAccentContainerColor : Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    StyledToolTip {
                        text: root.audioOnly
                            ? Translation.tr("Showing audio files and folders. Click to show all file formats.")
                            : Translation.tr("Showing all file formats. Click to filter only audio files.")
                    }
                }

                // Close Button (X)
                RippleButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer4Base
                    colBackgroundHover: Appearance.colors.colLayer4Hover
                    colRipple: Appearance.colors.colLayer4Active
                    onClicked: root.close()

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 18
                        color: Appearance.colors.colOnSurface
                    }

                    StyledToolTip {
                        text: Translation.tr("Close explorer")
                    }
                }
            }

            // ── Quick Access Shortcuts (Includes Disks and Mounts) ─
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: [
                        {
                            icon: "library_music",
                            label: Translation.tr("Music"),
                            path: Directories.music && Directories.music.length > 0 ? Directories.music : Directories.home
                        },
                        {
                            icon: "storage",
                            label: Translation.tr("SSD (01DA34...)"),
                            path: "/mnt/01DA34356F1F3C40"
                        },
                        {
                            icon: "hard_drive",
                            label: Translation.tr("Disks (/mnt)"),
                            path: "/mnt"
                        },
                        {
                            icon: "folder_special",
                            label: Translation.tr("Root (/)"),
                            path: "/"
                        },
                        {
                            icon: "home",
                            label: Translation.tr("Home"),
                            path: Directories.home
                        },
                        {
                            icon: "download",
                            label: Translation.tr("Downloads"),
                            path: Directories.downloads
                        }
                    ]

                    delegate: RippleButton {
                        id: quickBtn
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full

                        readonly property bool isCurrent: {
                            const cur = FileUtils.trimFileProtocol(root.currentDirectoryPath);
                            const target = FileUtils.trimFileProtocol(quickBtn.modelData.path);
                            return cur === target;
                        }

                        colBackground: quickBtn.isCurrent
                            ? root.accentContainerColor
                            : Appearance.colors.colLayer2Base
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active

                        onClicked: {
                            root.navigateTo(quickBtn.modelData.path);
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: quickBtn.modelData.icon
                                iconSize: 15
                                color: quickBtn.isCurrent ? root.onAccentContainerColor : Appearance.colors.colOnSurfaceVariant
                            }

                            StyledText {
                                text: quickBtn.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: quickBtn.isCurrent ? Font.DemiBold : Font.Normal
                                color: quickBtn.isCurrent ? root.onAccentContainerColor : Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }
                }
            }

            // ── Address Bar ─────────────────────────────────────────
            AddressBar {
                id: pickerAddressBar
                Layout.fillWidth: true
                directory: root.currentDirectoryPath
                radius: Appearance.rounding.normal
                onNavigateToDirectory: path => {
                    root.navigateTo(path);
                }
            }

            // ── File & Folder List ──────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                clip: true

                // Loading State
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: backend.loading
                    spacing: 10

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "hourglass_top"
                        iconSize: 32
                        color: root.accentColor
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Reading directory…")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }
                }

                // Empty State
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: !backend.loading && root.filteredEntries.length === 0
                    spacing: 8

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.audioOnly ? "music_off" : "folder_open"
                        iconSize: 36
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: {
                            if (backend.entries && backend.entries.length > 0 && root.audioOnly)
                                return Translation.tr("No audio files here (%1 other items hidden)").arg(backend.entries.length);
                            return Translation.tr("This folder is empty");
                        }
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colSubtext
                    }

                    RippleButton {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.audioOnly && backend.entries && backend.entries.length > 0
                        implicitHeight: 32
                        implicitWidth: showAllText.implicitWidth + 20
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2Base
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: root.audioOnly = false

                        StyledText {
                            id: showAllText
                            anchors.centerIn: parent
                            text: Translation.tr("Show all files")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colPrimary
                        }
                    }
                }

                ListView {
                    id: fileListView
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    spacing: 2
                    interactive: contentHeight > height
                    visible: !backend.loading

                    model: root.filteredEntries

                    delegate: MouseArea {
                        id: fileDelegate
                        width: fileListView.width
                        height: 48
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        required property var modelData
                        required property int index

                        readonly property bool isDir: Boolean(fileDelegate.modelData?.isDir)
                        readonly property string path: String(fileDelegate.modelData?.path ?? "")
                        readonly property string name: String(fileDelegate.modelData?.name ?? "")
                        readonly property var size: fileDelegate.modelData?.size
                        readonly property bool isAudio: Boolean(fileDelegate.modelData?.isAudio)
                        readonly property bool isHidden: Boolean(fileDelegate.modelData?.hidden)

                        onClicked: {
                            if (fileDelegate.isDir) {
                                root.navigateTo(fileDelegate.path);
                            } else {
                                LocalMediaService.startFilesImport([fileDelegate.path], "open");
                                root.trackPlayed();
                                root.close();
                            }
                        }

                        // Background
                        Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.small
                            color: fileDelegate.pressed
                                ? Appearance.colors.colLayer2Active
                                : fileDelegate.containsMouse
                                    ? Appearance.colors.colLayer2Hover
                                    : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 12

                            // Type icon
                            Rectangle {
                                width: 34
                                height: 34
                                radius: Appearance.rounding.small
                                color: fileDelegate.isDir
                                    ? Appearance.colors.colSecondaryContainer
                                    : (fileDelegate.isAudio ? root.accentContainerColor : Appearance.colors.colLayer2Base)

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: {
                                        if (fileDelegate.isDir)
                                            return fileDelegate.isHidden ? "folder_managed" : "folder";
                                        if (fileDelegate.isAudio)
                                            return "audio_file";
                                        const ext = fileDelegate.name.split('.').pop().toLowerCase();
                                        if (["jpg", "jpeg", "png", "webp", "gif"].includes(ext))
                                            return "image";
                                        if (["mp4", "mkv", "avi", "webm"].includes(ext))
                                            return "movie";
                                        return "description";
                                    }
                                    iconSize: 18
                                    color: fileDelegate.isDir
                                        ? Appearance.colors.colOnSecondaryContainer
                                        : (fileDelegate.isAudio ? root.onAccentContainerColor : Appearance.colors.colOnSurfaceVariant)
                                }
                            }

                            // Name and subtitle
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    Layout.fillWidth: true
                                    text: fileDelegate.name
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: fileDelegate.isDir ? Font.DemiBold : Font.Normal
                                    color: fileDelegate.isHidden ? Appearance.colors.colSubtext : Appearance.colors.colOnSurface
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: {
                                        if (fileDelegate.isDir)
                                            return fileDelegate.isHidden ? Translation.tr("Hidden folder") : Translation.tr("Folder");
                                        const sz = Number(fileDelegate.size ?? 0);
                                        if (sz < 1024) return sz + " B";
                                        if (sz < 1048576) return (sz / 1024).toFixed(1) + " KB";
                                        if (sz < 1073741824) return (sz / 1048576).toFixed(1) + " MB";
                                        return (sz / 1073741824).toFixed(1) + " GB";
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                            }

                            // Quick Action Buttons
                            RowLayout {
                                spacing: 4

                                // Play button (for file or folder)
                                RippleButton {
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colLayer3Base
                                    colBackgroundHover: root.accentContainerColor
                                    colRipple: root.accentColor
                                    onClicked: {
                                        if (fileDelegate.isDir) {
                                            LocalMediaService.startFolderImport(fileDelegate.path, "open");
                                            root.folderPlayed();
                                        } else {
                                            LocalMediaService.startFilesImport([fileDelegate.path], "open");
                                            root.trackPlayed();
                                        }
                                        root.close();
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "play_arrow"
                                        iconSize: 18
                                        color: Appearance.colors.colOnSurface
                                    }

                                    StyledToolTip {
                                        text: fileDelegate.isDir
                                            ? Translation.tr("Play entire folder")
                                            : Translation.tr("Play this track")
                                    }
                                }

                                // Add to queue button
                                RippleButton {
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colLayer3Base
                                    colBackgroundHover: Appearance.colors.colLayer3Hover
                                    colRipple: Appearance.colors.colLayer3Active
                                    onClicked: {
                                        if (fileDelegate.isDir) {
                                            LocalMediaService.startFolderImport(fileDelegate.path, "append");
                                        } else {
                                            LocalMediaService.startFilesImport([fileDelegate.path], "append");
                                        }
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "playlist_add"
                                        iconSize: 18
                                        color: Appearance.colors.colOnSurfaceVariant
                                    }

                                    StyledToolTip {
                                        text: fileDelegate.isDir
                                            ? Translation.tr("Add folder to queue")
                                            : Translation.tr("Add track to queue")
                                    }
                                }

                                // Directory chevron
                                MaterialSymbol {
                                    visible: fileDelegate.isDir
                                    text: "chevron_right"
                                    iconSize: 18
                                    color: Appearance.colors.colSubtext
                                }
                            }
                        }
                    }

                    ScrollBar.vertical: StyledScrollBar {}
                }
            }

            // ── Bottom Action Bar ───────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                MaterialSymbol {
                    text: "folder"
                    iconSize: 16
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.currentDirectoryPath
                    elide: Text.ElideMiddle
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                // Play this entire folder button
                RippleButton {
                    implicitHeight: 40
                    implicitWidth: playFolderContent.implicitWidth + 24
                    buttonRadius: Appearance.rounding.full
                    colBackground: root.accentColor
                    colBackgroundHover: ColorUtils.mix(root.accentColor, Appearance.colors.colLayer1Hover, 0.85)
                    colRipple: Appearance.colors.colLayer1Active
                    onClicked: {
                        LocalMediaService.startFolderImport(root.currentDirectoryPath, "open");
                        root.folderPlayed();
                        root.close();
                    }

                    RowLayout {
                        id: playFolderContent
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: "play_circle"
                            iconSize: 18
                            color: Appearance.colors.colOnPrimary
                        }

                        StyledText {
                            text: Translation.tr("Play this folder")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimary
                        }
                    }

                    StyledToolTip {
                        text: Translation.tr("Start playing all music tracks in this folder")
                    }
                }

                // Add entire folder to queue button
                RippleButton {
                    implicitHeight: 40
                    implicitWidth: addFolderContent.implicitWidth + 24
                    buttonRadius: Appearance.rounding.full
                    colBackground: root.accentContainerColor
                    colBackgroundHover: ColorUtils.mix(root.accentContainerColor, Appearance.colors.colLayer1Hover, 0.85)
                    colRipple: Appearance.colors.colLayer1Active
                    onClicked: {
                        LocalMediaService.startFolderImport(root.currentDirectoryPath, "append");
                    }

                    RowLayout {
                        id: addFolderContent
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: "playlist_add"
                            iconSize: 18
                            color: root.onAccentContainerColor
                        }

                        StyledText {
                            text: Translation.tr("Add folder to queue")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: root.onAccentContainerColor
                        }
                    }

                    StyledToolTip {
                        text: Translation.tr("Append all tracks in this folder to current queue")
                    }
                }
            }
        }
    }
}
