pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Render screen for the Video Editor.
 * Displays live export progress (or MaterialLoadingIndicator fallback),
 * video preview on the left, destination path, and completion action buttons.
 */
Item {
    id: root

    property string renderState: "rendering" // "rendering", "done", "error"
    property real renderProgress: 0.0
    property real renderElapsed: 0.0
    property real renderDuration: 0.0
    property string renderFormat: "mp4"
    property string renderOutputPath: ""
    property int renderOutputSize: 0
    property string renderErrorMessage: ""
    property string previewSource: ""
    property string videoPath: ""
    property int videoWidth: 0
    property int videoHeight: 0

    signal openFileRequested()
    signal openFolderRequested()
    signal copyPathRequested()
    signal cancelRequested()

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

    readonly property string displayTitle: {
        if (root.renderOutputPath && root.renderOutputPath.length > 0) {
            return FileUtils.fileNameForPath(root.renderOutputPath);
        }
        return FileUtils.fileNameForPath(root.videoPath) || Translation.tr("Video");
    }

    readonly property string displayDestination: {
        if (root.renderOutputPath && root.renderOutputPath.length > 0) {
            return root.renderOutputPath;
        }
        return FileUtils.parentDirectory(root.videoPath) || Directories.recordingsPath;
    }

    readonly property string statusText: {
        if (root.renderFormat === "mp3") return Translation.tr("Extracting Audio (MP3)…");
        if (root.renderFormat === "gif") return Translation.tr("Generating GIF Animation…");
        return Translation.tr("Rendering Video (MP4)…");
    }

    opacity: 0
    scale: 0.96
    Component.onCompleted: {
        opacity = 1;
        scale = 1.0;
    }
    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.standardDecel
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.standardDecel
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 36

        // ==========================================
        // LEFT COLUMN: Centered Video Preview Card
        // ==========================================
        Item {
            Layout.preferredWidth: parent.width * 0.44
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                id: previewCard
                anchors.centerIn: parent
                width: parent.width
                height: Math.min(parent.height - 20, width * 0.72)
                radius: Appearance.rounding.large
                color: Config.options.appearance.transparency.enable
                    ? Appearance.colors.colLayer0
                    : Appearance.m3colors.m3surfaceContainerHigh
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                clip: true

                StyledRectangularShadow {
                    target: previewCard
                }

                // Video Thumbnail / Image Preview
                Image {
                    id: previewImg
                    anchors.fill: parent
                    anchors.margins: 4
                    source: root.previewSource ? ("file://" + encodeURI(root.previewSource)) : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    visible: source != ""
                }

                // Fallback when no thumbnail image exists
                Rectangle {
                    anchors.fill: parent
                    visible: !previewImg.visible
                    color: Appearance.colors.colSurfaceContainerLowest

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.renderFormat === "mp3" ? "audiotrack" : (root.renderFormat === "gif" ? "gif" : "movie")
                        iconSize: 72
                        color: Appearance.colors.colOutline
                    }
                }

                // Audio MP3 decorative overlay
                Rectangle {
                    anchors.fill: parent
                    visible: root.renderFormat === "mp3"
                    color: ColorUtils.transparentize(Appearance.colors.colSurface, 0.45)

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 12

                        MaterialShapeWrappedMaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: "music_note"
                            iconSize: 44
                            implicitSize: 84
                            shape: MaterialShape.Shape.Cookie9Sided
                            color: Appearance.colors.colPrimaryContainer
                            colSymbol: Appearance.colors.colOnPrimaryContainer
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Audio Track")
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                        }
                    }
                }

                // Top-left format tag badge
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 14
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
                            iconSize: 16
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        StyledText {
                            text: root.renderFormat.toUpperCase()
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }

                // Bottom resolution / duration badge
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.margins: 14
                    visible: root.videoWidth > 0 && root.videoHeight > 0
                    radius: Appearance.rounding.small
                    height: 24
                    width: dimText.implicitWidth + 16
                    color: ColorUtils.transparentize(Appearance.colors.colSurface, 0.3)

                    StyledText {
                        id: dimText
                        anchors.centerIn: parent
                        text: `${root.videoWidth} × ${root.videoHeight}`
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurface
                    }
                }
            }
        }

        // ==========================================
        // RIGHT COLUMN: Progress, Info & Action Bar
        // ==========================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignVCenter

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 24

                // Target Filename and Path
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        MaterialSymbol {
                            text: root.renderFormat === "mp3" ? "audio_file" : (root.renderFormat === "gif" ? "gif_box" : "video_file")
                            iconSize: 28
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.displayTitle
                            font.pixelSize: 22
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideMiddle
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colSurfaceContainerLow

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
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
                }

                // ==============================
                // STATE 1: RENDERING / LOADING
                // ==============================
                ColumnLayout {
                    visible: root.renderState === "rendering"
                    Layout.fillWidth: true
                    spacing: 20

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        StyledText {
                            Layout.fillWidth: true
                            text: root.statusText
                            font.pixelSize: 17
                            font.weight: Font.SemiBold
                            color: Appearance.colors.colOnSurface
                        }

                        StyledText {
                            visible: root.renderProgress > 0
                            text: `${Math.round(root.renderProgress * 100)}%`
                            font.pixelSize: 28
                            font.weight: Font.Black
                            color: Appearance.colors.colPrimary
                        }
                    }

                    // Progress Bar (when FFmpeg returns progress)
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.renderProgress > 0
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
                                text: root.renderElapsed > 0 ? `${Translation.tr("Elapsed:")} ${root.formatTime(root.renderElapsed)}` : ""
                                font.pixelSize: 12
                                color: Appearance.colors.colOnSurfaceVariant
                            }

                            Item { Layout.fillWidth: true }

                            StyledText {
                                text: root.renderDuration > 0 ? `${Translation.tr("Total:")} ${root.formatTime(root.renderDuration)}` : ""
                                font.pixelSize: 12
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }

                    // Material Loading Indicator Fallback (when progress is indeterminate / starting)
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.renderProgress <= 0
                        spacing: 16

                        MaterialLoadingIndicator {
                            implicitSize: 44
                            loading: true
                            color: Appearance.colors.colPrimaryContainer
                            shapeColor: Appearance.colors.colOnPrimaryContainer
                        }

                        ColumnLayout {
                            spacing: 2
                            StyledText {
                                text: Translation.tr("Encoding media…")
                                font.pixelSize: 15
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnSurface
                            }
                            StyledText {
                                text: Translation.tr("Applying filters and optimizing output…")
                                font.pixelSize: 12
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }

                    // Cancel button
                    RippleButton {
                        Layout.preferredHeight: 44
                        Layout.preferredWidth: 130
                        buttonRadius: 22
                        colBackground: Appearance.colors.colSurfaceContainerHighest
                        contentItem: RowLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            MaterialSymbol { text: "close"; iconSize: 18; color: Appearance.colors.colOnSurface }
                            StyledText { text: Translation.tr("Cancel"); font.pixelSize: 14; font.weight: Font.Medium; color: Appearance.colors.colOnSurface }
                        }
                        onClicked: root.cancelRequested()
                    }
                }

                // ==============================
                // STATE 2: DONE / COMPLETE
                // ==============================
                ColumnLayout {
                    visible: root.renderState === "done"
                    Layout.fillWidth: true
                    spacing: 24

                    RowLayout {
                        spacing: 20

                        // Primary Checkmark with Material Shape in background
                        MaterialShapeWrappedMaterialSymbol {
                            text: "check"
                            iconSize: 42
                            implicitSize: 80
                            shape: MaterialShape.Shape.Cookie4Sided
                            color: Appearance.colors.colPrimary
                            colSymbol: Appearance.colors.colOnPrimary
                        }

                        ColumnLayout {
                            spacing: 4

                            StyledText {
                                text: Translation.tr("Export Complete!")
                                font.pixelSize: 26
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnSurface
                            }

                            StyledText {
                                text: Translation.tr("Your media is ready to view and share.")
                                font.pixelSize: 14
                                color: Appearance.colors.colOnSurfaceVariant
                            }

                            RowLayout {
                                spacing: 8
                                Rectangle {
                                    radius: 12
                                    height: 24
                                    width: sizeText.implicitWidth + 16
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

                                Rectangle {
                                    radius: 12
                                    height: 24
                                    width: fmtText.implicitWidth + 16
                                    color: Appearance.colors.colSecondaryContainer

                                    StyledText {
                                        id: fmtText
                                        anchors.centerIn: parent
                                        text: root.renderFormat.toUpperCase()
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                }
                            }
                        }
                    }

                    // Action buttons (Open video, Open folder, Copy path)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        // 1. Open Video / Media Button
                        RippleButton {
                            Layout.preferredHeight: 52
                            Layout.preferredWidth: 160
                            buttonRadius: 26
                            colBackground: Appearance.colors.colPrimary
                            contentItem: RowLayout {
                                anchors.centerIn: parent
                                spacing: 10
                                MaterialSymbol {
                                    text: root.renderFormat === "mp3" ? "audiotrack" : (root.renderFormat === "gif" ? "visibility" : "play_arrow")
                                    iconSize: 22
                                    color: Appearance.colors.colOnPrimary
                                }
                                StyledText {
                                    text: root.renderFormat === "mp3" ? Translation.tr("Open Audio") : (root.renderFormat === "gif" ? Translation.tr("Open GIF") : Translation.tr("Open Video"))
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                            onClicked: root.openFileRequested()
                        }

                        // 2. Open Folder Button
                        RippleButton {
                            Layout.preferredHeight: 52
                            Layout.preferredWidth: 150
                            buttonRadius: 26
                            colBackground: Appearance.colors.colSurfaceContainerHighest
                            contentItem: RowLayout {
                                anchors.centerIn: parent
                                spacing: 10
                                MaterialSymbol { text: "folder_open"; iconSize: 22; color: Appearance.colors.colOnSurface }
                                StyledText {
                                    text: Translation.tr("Open folder")
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnSurface
                                }
                            }
                            onClicked: root.openFolderRequested()
                        }

                        // 3. Copy Path Button
                        RippleButton {
                            Layout.preferredHeight: 52
                            Layout.preferredWidth: 140
                            buttonRadius: 26
                            colBackground: Appearance.colors.colSurfaceContainerHighest
                            contentItem: RowLayout {
                                anchors.centerIn: parent
                                spacing: 10
                                MaterialSymbol { text: "content_copy"; iconSize: 20; color: Appearance.colors.colOnSurface }
                                StyledText {
                                    text: Translation.tr("Copy path")
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnSurface
                                }
                            }
                            onClicked: root.copyPathRequested()
                        }
                    }
                }

                // ==============================
                // STATE 3: ERROR
                // ==============================
                ColumnLayout {
                    visible: root.renderState === "error"
                    Layout.fillWidth: true
                    spacing: 16

                    RowLayout {
                        spacing: 16
                        MaterialSymbol {
                            text: "error"
                            iconSize: 48
                            color: Appearance.colors.colError
                        }
                        ColumnLayout {
                            spacing: 4
                            StyledText {
                                text: Translation.tr("Export Failed")
                                font.pixelSize: 20
                                font.weight: Font.Bold
                                color: Appearance.colors.colError
                            }
                            StyledText {
                                text: root.renderErrorMessage || Translation.tr("An error occurred during rendering.")
                                font.pixelSize: 13
                                color: Appearance.colors.colOnSurfaceVariant
                                wrapMode: Text.Wrap
                            }
                        }
                    }

                    RippleButton {
                        Layout.preferredHeight: 44
                        Layout.preferredWidth: 160
                        buttonRadius: 22
                        colBackground: Appearance.colors.colPrimary
                        contentItem: RowLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            MaterialSymbol { text: "arrow_back"; iconSize: 18; color: Appearance.colors.colOnPrimary }
                            StyledText { text: Translation.tr("Back to Editor"); font.pixelSize: 14; font.weight: Font.Bold; color: Appearance.colors.colOnPrimary }
                        }
                        onClicked: root.cancelRequested()
                    }
                }
            }
        }
    }
}
