pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Render screen for the Video Editor.
 * Follows Google Material 3 Expressive guidelines:
 * - Pure tonal containers without redundant wireframe borders
 * - Generous corner rounding (Appearance.rounding.large / full)
 * - Centered icons and text for toggles/stat tiles
 * - Rounded, masked 16:9 media preview
 * - Zero duplicated information, clean top path pill
 */
Item {
    id: root

    property string renderState: "rendering" // "rendering", "done", "error"
    property real renderProgress: 0.0
    property real renderElapsed: 0.0
    property real renderDuration: 0.0
    property string renderFormat: "mp4" // "mp4", "mp3", "gif"
    property string renderOutputPath: ""
    property int renderOutputSize: 0
    property string renderErrorMessage: ""
    property string previewSource: ""
    property string videoPath: ""
    property int videoWidth: 0
    property int videoHeight: 0
    property string videoFps: ""
    property string videoBitrate: ""
    property int originalSize: 0
    property bool muteAudio: false

    property bool copiedFeedback: false

    signal closeRequested()
    signal backRequested()
    signal cancelRequested()
    signal openFileRequested()
    signal openFolderRequested()
    signal copyPathRequested()

    Timer {
        id: copiedTimer
        interval: 2200
        repeat: false
        onTriggered: root.copiedFeedback = false
    }

    function formatFileSize(bytes) {
        if (!bytes || bytes <= 0) return "—";
        const units = ["B", "KB", "MB", "GB"];
        let i = 0;
        let b = Number(bytes);
        while (b >= 1024 && i < units.length - 1) {
            b /= 1024;
            i++;
        }
        return `${b.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
    }

    function formatTime(seconds) {
        const s = Math.max(0, Math.floor(seconds || 0));
        const m = Math.floor(s / 60);
        const sec = s % 60;
        return `${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`;
    }

    readonly property string displayDestination: {
        if (root.renderOutputPath && root.renderOutputPath.length > 0) {
            return root.renderOutputPath;
        }
        const parentDir = FileUtils.parentDirectory(root.videoPath) || (Config.options.screenRecord.savePath || Directories.videos);
        const name = FileUtils.fileNameForPath(root.videoPath) || "render";
        return `${parentDir}/${name}.${root.renderFormat}`;
    }

    readonly property string statusText: {
        if (root.renderFormat === "mp3") return Translation.tr("Extracting Audio (MP3)…");
        if (root.renderFormat === "gif") return Translation.tr("Generating GIF Animation…");
        return Translation.tr("Rendering Video (MP4)…");
    }

    // ==========================================
    // TOP HEADER ROW (Material 3 Expressive)
    // ==========================================
    Item {
        id: topHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 52

        RowLayout {
            anchors.fill: parent
            spacing: 12

            // Back to Editor button
            RippleButton {
                id: backBtn
                Layout.preferredWidth: 52
                Layout.preferredHeight: 52
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSurfaceContainerHighest
                contentItem: Item {
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "arrow_back"
                        iconSize: 24
                        color: Appearance.colors.colOnSurface
                    }
                }
                onClicked: root.backRequested()

                Accessible.name: Translation.tr("Back to Editor")
            }

            // Clean Title (No redundant checkmark)
            StyledText {
                text: root.renderState === "done"
                    ? Translation.tr("Export Complete")
                    : (root.renderState === "error" ? Translation.tr("Export Failed") : Translation.tr("Export & Render"))
                font.pixelSize: 24
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurface
            }

            // Live State Pill Chip
            Rectangle {
                radius: Appearance.rounding.full
                Layout.preferredHeight: 32
                Layout.preferredWidth: stateChipLayout.implicitWidth + 24
                color: {
                    if (root.renderState === "error") return Appearance.colors.colErrorContainer;
                    if (root.renderState === "done") return Appearance.colors.colPrimaryContainer;
                    return Appearance.colors.colSecondaryContainer;
                }

                RowLayout {
                    id: stateChipLayout
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        text: {
                            if (root.renderState === "error") return "error";
                            if (root.renderState === "done") return "done_all";
                            if (root.renderFormat === "mp3") return "music_note";
                            if (root.renderFormat === "gif") return "gif";
                            return "hourglass_top";
                        }
                        iconSize: 16
                        color: {
                            if (root.renderState === "error") return Appearance.colors.colOnErrorContainer;
                            if (root.renderState === "done") return Appearance.colors.colOnPrimaryContainer;
                            return Appearance.colors.colOnSecondaryContainer;
                        }
                    }

                    StyledText {
                        text: {
                            if (root.renderState === "error") return Translation.tr("Failed");
                            if (root.renderState === "done") return Translation.tr("Finished");
                            return root.renderFormat === "mp3"
                                ? Translation.tr("Audio MP3")
                                : (root.renderFormat === "gif" ? Translation.tr("GIF") : Translation.tr("Video MP4"));
                        }
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: {
                            if (root.renderState === "error") return Appearance.colors.colOnErrorContainer;
                            if (root.renderState === "done") return Appearance.colors.colOnPrimaryContainer;
                            return Appearance.colors.colOnSecondaryContainer;
                        }
                    }
                }
            }

            // Destination Path Pill in the Top Bar (Non-redundant, clean)
            Rectangle {
                Layout.fillWidth: true
                Layout.maximumWidth: 540
                Layout.preferredHeight: 34
                radius: Appearance.rounding.full
                color: Appearance.colors.colSurfaceContainerHighest
                clip: true

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    MaterialSymbol {
                        text: "folder"
                        iconSize: 16
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.displayDestination
                        font.pixelSize: 12
                        color: Appearance.colors.colOnSurfaceVariant
                        elide: Text.ElideMiddle
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Close Video Editor button
            RippleButton {
                id: closeBtn
                Layout.preferredWidth: 52
                Layout.preferredHeight: 52
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSurfaceContainerHighest
                contentItem: Item {
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 24
                        color: Appearance.colors.colOnSurface
                    }
                }
                onClicked: root.closeRequested()

                Accessible.name: Translation.tr("Close video editor")
            }
        }
    }

    // ==========================================
    // TWO-COLUMN MAIN CONTENT AREA
    // ==========================================
    Item {
        id: contentArea
        anchors.top: topHeader.bottom
        anchors.topMargin: 20
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        // ==========================================
        // LEFT COLUMN: Video Preview & Source Info (46% width)
        // ==========================================
        Item {
            id: leftPane
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.round((parent.width - 24) * 0.46)

            // 16:9 Media Preview Card (Rounded with OpacityMask, high quality)
            Rectangle {
                id: previewCard
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: Math.round(width * 9 / 16)
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerLow

                StyledRectangularShadow {
                    target: previewCard
                }

                // Masked container ensuring rounded corners on the thumbnail image
                Item {
                    id: maskedThumbnail
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: maskedThumbnail.width
                            height: maskedThumbnail.height
                            radius: Appearance.rounding.large
                        }
                    }

                    // MP3 Expressive Audio Presentation
                    Rectangle {
                        anchors.fill: parent
                        visible: root.renderFormat === "mp3"
                        color: Appearance.colors.colSurfaceContainerLowest

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 10

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: 64
                                height: 64
                                radius: 32
                                color: Appearance.colors.colPrimaryContainer

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "music_note"
                                    iconSize: 34
                                    color: Appearance.colors.colOnPrimaryContainer
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Translation.tr("Audio Track")
                                font.pixelSize: 17
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnSurface
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: "192 kbps • Stereo MP3"
                                font.pixelSize: 13
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }

                    // High Quality Video Thumbnail / Image Preview
                    Image {
                        id: previewImg
                        anchors.fill: parent
                        visible: root.renderFormat !== "mp3" && source != ""
                        source: root.previewSource ? ("file://" + encodeURI(root.previewSource)) : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: false
                        smooth: true
                        mipmap: true
                    }

                    // Fallback placeholder when no thumbnail exists
                    Rectangle {
                        anchors.fill: parent
                        visible: root.renderFormat !== "mp3" && !previewImg.visible
                        color: Appearance.colors.colSurfaceContainerLowest

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.renderFormat === "gif" ? "gif" : "movie"
                            iconSize: 64
                            color: Appearance.colors.colOutline
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                // Top-Left Format Pill Badge
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 12
                    radius: Appearance.rounding.full
                    height: 28
                    width: tagRow.implicitWidth + 20
                    color: Appearance.colors.colPrimaryContainer

                    RowLayout {
                        id: tagRow
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: root.renderFormat === "mp3" ? "music_note" : (root.renderFormat === "gif" ? "gif" : "movie")
                            iconSize: 15
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        StyledText {
                            text: root.renderFormat.toUpperCase()
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }

                // Bottom-Right Duration Badge
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.margins: 12
                    radius: Appearance.rounding.full
                    height: 26
                    width: dimText.implicitWidth + 20
                    color: ColorUtils.transparentize(Appearance.colors.colSurface, 0.25)

                    StyledText {
                        id: dimText
                        anchors.centerIn: parent
                        text: root.formatTime(root.renderDuration)
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurface
                    }
                }
            }

            // Slim, non-redundant Source & Trim Strip (No repeated metadata)
            Rectangle {
                anchors.top: previewCard.bottom
                anchors.topMargin: 14
                anchors.left: parent.left
                anchors.right: parent.right
                height: 64
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerLow

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 16

                    // Source Filename & Size
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            width: 34
                            height: 34
                            radius: 17
                            color: Appearance.colors.colSurfaceContainerHighest

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "video_file"
                                iconSize: 18
                                color: Appearance.colors.colPrimary
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                text: FileUtils.fileNameForPath(root.videoPath) || "source_video"
                                font.pixelSize: 13
                                font.weight: Font.SemiBold
                                color: Appearance.colors.colOnSurface
                                elide: Text.ElideMiddle
                            }

                            StyledText {
                                text: root.originalSize > 0 ? `${Translation.tr("Original Size:")} ${root.formatFileSize(root.originalSize)}` : ""
                                font.pixelSize: 11
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }

                    // Trim Range Pill
                    Rectangle {
                        radius: Appearance.rounding.full
                        Layout.preferredHeight: 30
                        Layout.preferredWidth: trimRow.implicitWidth + 20
                        color: Appearance.colors.colSurfaceContainerHighest

                        RowLayout {
                            id: trimRow
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: "content_cut"
                                iconSize: 14
                                color: Appearance.colors.colOnSurfaceVariant
                            }

                            StyledText {
                                text: `00:00 ➔ ${root.formatTime(root.renderDuration)}`
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }
                }
            }
        }

        // ==========================================
        // RIGHT COLUMN: Hero State & Compact Toggles (54% width)
        // ==========================================
        Item {
            id: rightPane
            anchors.left: leftPane.right
            anchors.leftMargin: 24
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            // ==============================
            // DYNAMIC STATE HERO CARD
            // ==============================
            Rectangle {
                id: stateCard
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: {
                    if (root.renderState === "done") return doneCol.implicitHeight + 36;
                    if (root.renderState === "error") return errorCol.implicitHeight + 36;
                    return renderingCol.implicitHeight + 36;
                }
                radius: Appearance.rounding.large
                color: root.renderState === "error" ? Appearance.colors.colErrorContainer : Appearance.colors.colSurfaceContainerHigh

                StyledRectangularShadow { target: stateCard }

                // --- FINISHED (DONE) HERO VIEW ---
                ColumnLayout {
                    id: doneCol
                    visible: root.renderState === "done"
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        Rectangle {
                            width: 52
                            height: 52
                            radius: 26
                            color: Appearance.colors.colPrimary

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "check"
                                iconSize: 28
                                color: Appearance.colors.colOnPrimary
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            StyledText {
                                text: Translation.tr("Export Complete!")
                                font.pixelSize: 22
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnSurface
                            }

                            StyledText {
                                text: Translation.tr("Your media is ready to view and share.")
                                font.pixelSize: 13
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }

                        // Output Size Pill
                        Rectangle {
                            radius: Appearance.rounding.full
                            Layout.preferredHeight: 30
                            Layout.preferredWidth: sizeText.implicitWidth + 20
                            color: Appearance.colors.colPrimaryContainer

                            StyledText {
                                id: sizeText
                                anchors.centerIn: parent
                                text: root.formatFileSize(root.renderOutputSize)
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }
                    }

                    // Action Buttons: 2x2 Grid of equal-sized buttons with centered icon & text
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 10
                        columnSpacing: 12

                        // Button 1: Open Video / Audio / GIF
                        RippleButton {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 46
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colPrimary
                            contentItem: Item {
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.renderFormat === "mp3" ? "audiotrack" : (root.renderFormat === "gif" ? "visibility" : "play_arrow")
                                        iconSize: 20
                                        color: Appearance.colors.colOnPrimary
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.renderFormat === "mp3"
                                            ? Translation.tr("Open Audio")
                                            : (root.renderFormat === "gif" ? Translation.tr("Open GIF") : Translation.tr("Open Video"))
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnPrimary
                                    }
                                }
                            }
                            onClicked: root.openFileRequested()
                        }

                        // Button 2: Open Folder
                        RippleButton {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 46
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colSurfaceContainerHighest
                            contentItem: Item {
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "folder_open"
                                        iconSize: 20
                                        color: Appearance.colors.colOnSurface
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Translation.tr("Open Folder")
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnSurface
                                    }
                                }
                            }
                            onClicked: root.openFolderRequested()
                        }

                        // Button 3: Copy File Path
                        RippleButton {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 46
                            buttonRadius: Appearance.rounding.full
                            colBackground: root.copiedFeedback ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest
                            contentItem: Item {
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.copiedFeedback ? "check" : "content_copy"
                                        iconSize: 18
                                        color: root.copiedFeedback ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.copiedFeedback ? Translation.tr("Copied!") : Translation.tr("Copy Path")
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        color: root.copiedFeedback ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                                    }
                                }
                            }
                            onClicked: {
                                root.copiedFeedback = true;
                                copiedTimer.restart();
                                root.copyPathRequested();
                            }
                        }

                        // Button 4: Back to Editor
                        RippleButton {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 46
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colSurfaceContainerHighest
                            contentItem: Item {
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "edit"
                                        iconSize: 18
                                        color: Appearance.colors.colOnSurface
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Translation.tr("Back to Editor")
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnSurface
                                    }
                                }
                            }
                            onClicked: root.backRequested()
                        }
                    }
                }

                // --- RENDERING (IN-PROGRESS) VIEW ---
                ColumnLayout {
                    id: renderingCol
                    visible: root.renderState === "rendering"
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        StyledText {
                            Layout.fillWidth: true
                            text: root.statusText
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                        }

                        StyledText {
                            visible: root.renderProgress > 0
                            text: `${Math.round(root.renderProgress * 100)}%`
                            font.pixelSize: 30
                            font.weight: Font.Black
                            color: Appearance.colors.colPrimary
                        }
                    }

                    // Progress Bar
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        StyledProgressBar {
                            Layout.fillWidth: true
                            value: root.renderProgress
                            valueBarHeight: 10
                            highlightColor: Appearance.colors.colPrimary
                            trackColor: Appearance.colors.colSurfaceContainerHighest
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            StyledText {
                                text: root.renderElapsed > 0
                                    ? `${Translation.tr("Elapsed:")} ${root.formatTime(root.renderElapsed)}`
                                    : Translation.tr("Starting…")
                                font.pixelSize: 12
                                color: Appearance.colors.colOnSurfaceVariant
                            }

                            Item { Layout.fillWidth: true }

                            StyledText {
                                text: root.renderDuration > 0
                                    ? `${Translation.tr("Total:")} ${root.formatTime(root.renderDuration)}`
                                    : ""
                                font.pixelSize: 12
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }

                    // Cancel Button (Centered icon & text)
                    RippleButton {
                        Layout.preferredHeight: 42
                        Layout.preferredWidth: 140
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSurfaceContainerHighest
                        contentItem: Item {
                            Row {
                                anchors.centerIn: parent
                                spacing: 8
                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "close"
                                    iconSize: 18
                                    color: Appearance.colors.colOnSurface
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Translation.tr("Cancel")
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnSurface
                                }
                            }
                        }
                        onClicked: root.cancelRequested()
                    }
                }

                // --- ERROR STATE VIEW ---
                ColumnLayout {
                    id: errorCol
                    visible: root.renderState === "error"
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 16

                    RowLayout {
                        spacing: 14

                        Rectangle {
                            width: 52
                            height: 52
                            radius: 26
                            color: Appearance.colors.colError

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "error"
                                iconSize: 28
                                color: Appearance.colors.colOnError
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            StyledText {
                                text: Translation.tr("Export Failed")
                                font.pixelSize: 22
                                font.weight: Font.Bold
                                color: Appearance.colors.colError
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.renderErrorMessage || Translation.tr("An unexpected error occurred during rendering.")
                                font.pixelSize: 13
                                color: Appearance.colors.colOnSurfaceVariant
                                wrapMode: Text.Wrap
                            }
                        }
                    }

                    RippleButton {
                        Layout.preferredHeight: 44
                        Layout.preferredWidth: 160
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colPrimary
                        contentItem: Item {
                            Row {
                                anchors.centerIn: parent
                                spacing: 8
                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "arrow_back"
                                    iconSize: 18
                                    color: Appearance.colors.colOnPrimary
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Translation.tr("Back to Editor")
                                    font.pixelSize: 14
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }
                        onClicked: root.backRequested()
                    }
                }
            }

            // ==============================
            // COMPACT TOGGLE / STAT TILES (Centered Icons & Centered Text, Compact Sizing)
            // ==============================
            GridLayout {
                id: bentoArea
                anchors.top: stateCard.bottom
                anchors.topMargin: 14
                anchors.left: parent.left
                anchors.right: parent.right
                columns: 2
                rowSpacing: 10
                columnSpacing: 10

                // Tile 1: Duration (Centered Icon & Centered Text)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 92
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colSurfaceContainerLow

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 36
                            height: 36
                            radius: 18
                            color: Appearance.colors.colPrimaryContainer

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "timer"
                                iconSize: 20
                                color: Appearance.colors.colOnPrimaryContainer
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Duration")
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurfaceVariant
                            horizontalAlignment: Text.AlignHCenter
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.formatTime(root.renderDuration)
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                // Tile 2: Resolution (Centered Icon & Centered Text)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 92
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colSurfaceContainerLow

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 36
                            height: 36
                            radius: 18
                            color: Appearance.colors.colPrimaryContainer

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "aspect_ratio"
                                iconSize: 20
                                color: Appearance.colors.colOnPrimaryContainer
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Resolution")
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurfaceVariant
                            horizontalAlignment: Text.AlignHCenter
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.videoWidth > 0 && root.videoHeight > 0 ? `${root.videoWidth} × ${root.videoHeight}` : "—"
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                // Tile 3: FPS (Centered Icon & Centered Text)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 92
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colSurfaceContainerLow

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 36
                            height: 36
                            radius: 18
                            color: Appearance.colors.colPrimaryContainer

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "speed"
                                iconSize: 20
                                color: Appearance.colors.colOnPrimaryContainer
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("FPS")
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurfaceVariant
                            horizontalAlignment: Text.AlignHCenter
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.videoFps || "—"
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                // Tile 4: Audio Track (Centered Icon & Centered Text)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 92
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colSurfaceContainerLow

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 36
                            height: 36
                            radius: 18
                            color: Appearance.colors.colPrimaryContainer

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "volume_up"
                                iconSize: 20
                                color: Appearance.colors.colOnPrimaryContainer
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Audio")
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurfaceVariant
                            horizontalAlignment: Text.AlignHCenter
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.muteAudio ? Translation.tr("Muted") : (root.renderFormat === "mp3" ? "MP3 192k" : "AAC")
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }
    }
}
