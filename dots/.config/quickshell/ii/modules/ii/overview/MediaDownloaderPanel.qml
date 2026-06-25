pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    property string searchQuery: ""

    readonly property int panelWidth: Config.options.search.clipboard.panelWidth ?? 860
    implicitWidth: panelWidth
    implicitHeight: 560

    // ── Format definitions ───────────────────────────────────────────────────
    readonly property var formatOptions: [
        { id: "best",      label: "Best",      icon: "star" },
        { id: "video-mp4", label: "MP4",       icon: "videocam" },
        { id: "audio-mp3", label: "MP3",       icon: "audiotrack" },
        { id: "audio-ogg", label: "OGG",       icon: "music_note" },
        { id: "audio-opus",label: "OPUS",      icon: "graphic_eq" }
    ]

    readonly property var typeOptions: [
        { id: "basic",    label: "Basic Downloader",    icon: "download" },
        { id: "batch",    label: "Batch Downloader",    icon: "queue" },
        { id: "playlist", label: "Playlist Downloader", icon: "playlist_play" }
    ]

    property string selectedFormat: Config.options.mediaDownloader.lastUsedFormat || "best"
    property string selectedType: "basic"
    property string extraArgsText: ""

    // Keyboard navigation focus index
    // -1 = SearchBar (default)
    // 0-2 = Type chips (basic, batch, playlist)
    // 3-7 = Format chips (best, video-mp4, audio-mp3, audio-ogg, audio-opus)
    // 8 = Download button
    property int focusedControlIndex: -1

    function focusInput() {
        focusedControlIndex = 0;
    }

    function navigateDown() {
        if (focusedControlIndex === -1) {
            focusedControlIndex = 0;
        } else if (focusedControlIndex >= 0 && focusedControlIndex <= 2) {
            focusedControlIndex = 3;
        } else if (focusedControlIndex >= 3 && focusedControlIndex <= 7) {
            focusedControlIndex = 8;
        }
    }

    function navigateUp() {
        if (focusedControlIndex === 8) {
            focusedControlIndex = 3;
        } else if (focusedControlIndex >= 3 && focusedControlIndex <= 7) {
            focusedControlIndex = 0;
        } else if (focusedControlIndex >= 0 && focusedControlIndex <= 2) {
            focusedControlIndex = -1;
        }
    }

    function navigateLeft() {
        if (focusedControlIndex > 0 && focusedControlIndex <= 2) {
            focusedControlIndex--;
        } else if (focusedControlIndex > 3 && focusedControlIndex <= 7) {
            focusedControlIndex--;
        }
    }

    function navigateRight() {
        if (focusedControlIndex >= 0 && focusedControlIndex < 2) {
            focusedControlIndex++;
        } else if (focusedControlIndex >= 3 && focusedControlIndex < 7) {
            focusedControlIndex++;
        }
    }

    function activateSelected() {
        if (focusedControlIndex >= 0 && focusedControlIndex <= 2) {
            root.selectedType = root.typeOptions[focusedControlIndex].id;
        } else if (focusedControlIndex >= 3 && focusedControlIndex <= 7) {
            root.selectedFormat = root.formatOptions[focusedControlIndex - 3].id;
            Config.options.mediaDownloader.lastUsedFormat = root.selectedFormat;
        } else if (focusedControlIndex === 8) {
            if (MediaDownloaderService.isDownloading) {
                MediaDownloaderService.cancelDownload();
            } else {
                MediaDownloaderService.startDownload(
                    urlField.text,
                    root.selectedFormat,
                    root.selectedType,
                    root.extraArgsText
                );
            }
        }
    }

    // Sync search query → url display, and reset panel focus on query changes
    onSearchQueryChanged: {
        if (urlField.text !== searchQuery)
            urlField.text = searchQuery;
        focusedControlIndex = -1;
    }


    // ── Main layout ──────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        // ── Row 1: URL input bar ─────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 48
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 10
                spacing: 8

                MaterialSymbol {
                    text: "link"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSurface
                    opacity: 0.7
                }

                TextInput {
                    id: urlField
                    Layout.fillWidth: true
                    text: root.searchQuery
                    color: Appearance.colors.colOnSurface
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family.main
                    clip: true
                    selectByMouse: true
                    verticalAlignment: TextInput.AlignVCenter

                    Text {
                        anchors.fill: parent
                        text: "Enter URL here..."
                        color: Appearance.colors.colSubtext
                        font: parent.font
                        visible: parent.text === ""
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                // Clear URL button
                RippleButton {
                    visible: urlField.text !== ""
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                    colRipple: Appearance.colors.colPrimary

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 18
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    onClicked: urlField.text = ""
                }
            }
        }

        // ── Row 2: Two-column bento grid ─────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            // ── Left column ──────────────────────────────────────────────────
            ColumnLayout {
                Layout.preferredWidth: Math.round(root.panelWidth * 0.44)
                Layout.fillHeight: true
                spacing: 10

                // Download Args card
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 88
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 6

                        StyledText {
                            text: "Download Args"
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            font.family: Appearance.font.family.main
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2

                            TextInput {
                                id: argsField
                                anchors.fill: parent
                                anchors.margins: 8
                                text: root.extraArgsText
                                color: Appearance.colors.colOnSurface
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.family: Appearance.font.family.monospace || Appearance.font.family.main
                                clip: true
                                selectByMouse: true
                                onTextChanged: root.extraArgsText = text

                                Text {
                                    anchors.fill: parent
                                    text: "--cookies-from-browser firefox..."
                                    color: Appearance.colors.colSubtext
                                    font: parent.font
                                    visible: parent.text === ""
                                }
                            }
                        }
                    }
                }

                // Download Type card
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 112
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        StyledText {
                            text: "Download Type"
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }

                        Repeater {
                            model: root.typeOptions
                            delegate: Rectangle {
                                id: typeChip
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: 28
                                radius: Appearance.rounding.full
                                color: root.selectedType === typeChip.modelData.id
                                    ? Appearance.colors.colPrimaryContainer
                                    : "transparent"

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Appearance.animation.elementMoveFast.duration
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    MaterialSymbol {
                                        text: typeChip.modelData.icon
                                        iconSize: 14
                                        color: root.selectedType === typeChip.modelData.id
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : Appearance.colors.colOnSurface
                                    }

                                    StyledText {
                                        text: typeChip.modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: root.selectedType === typeChip.modelData.id
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : Appearance.colors.colOnSurface
                                        Layout.fillWidth: true
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.focusedControlIndex = typeChip.index;
                                        root.selectedType = typeChip.modelData.id;
                                    }
                                }

                                // Keyboard focus highlight ring
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: -2
                                    color: "transparent"
                                    border.color: root.focusedControlIndex === typeChip.index ? Appearance.colors.colPrimary : "transparent"
                                    border.width: 2
                                    radius: parent.radius + 2
                                }
                            }
                        }
                    }
                }

                // Formats card
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        StyledText {
                            text: "Format"
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: root.formatOptions
                                delegate: Rectangle {
                                    id: formatChip
                                    required property var modelData
                                    required property int index
                                    implicitWidth: formatChipRow.implicitWidth + 18
                                    implicitHeight: 30
                                    radius: Appearance.rounding.full
                                    color: root.selectedFormat === formatChip.modelData.id
                                        ? Appearance.colors.colSecondaryContainer
                                        : Appearance.colors.colLayer2

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Appearance.animation.elementMoveFast.duration
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                                        }
                                    }

                                    RowLayout {
                                        id: formatChipRow
                                        anchors.centerIn: parent
                                        spacing: 5

                                        MaterialSymbol {
                                            text: formatChip.modelData.icon
                                            iconSize: 13
                                            color: root.selectedFormat === formatChip.modelData.id
                                                ? Appearance.colors.colOnSecondaryContainer
                                                : Appearance.colors.colOnSurface
                                        }

                                        StyledText {
                                            text: formatChip.modelData.label
                                            font.pixelSize: 12
                                            color: root.selectedFormat === formatChip.modelData.id
                                                ? Appearance.colors.colOnSecondaryContainer
                                                : Appearance.colors.colOnSurface
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.focusedControlIndex = 3 + formatChip.index;
                                            root.selectedFormat = formatChip.modelData.id;
                                            Config.options.mediaDownloader.lastUsedFormat = root.selectedFormat;
                                        }
                                    }

                                    // Keyboard focus highlight ring
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: -2
                                        color: "transparent"
                                        border.color: root.focusedControlIndex === (3 + formatChip.index) ? Appearance.colors.colPrimary : "transparent"
                                        border.width: 2
                                        radius: parent.radius + 2
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Right column: Log Panel ──────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: "terminal"
                            iconSize: 14
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: "Log"
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                            Layout.fillWidth: true
                        }
                        // Status indicator
                        Rectangle {
                            visible: MediaDownloaderService.currentStatus !== "idle"
                            implicitWidth: statusText.implicitWidth + 12
                            implicitHeight: 18
                            radius: Appearance.rounding.full
                            color: {
                                switch (MediaDownloaderService.currentStatus) {
                                case "downloading": return Appearance.colors.colPrimaryContainer;
                                case "error": return Appearance.colors.colErrorContainer;
                                case "checking": return Appearance.colors.colTertiaryContainer;
                                case "cancelling": return Appearance.colors.colSecondaryContainer;
                                default: return "transparent";
                                }
                            }

                            StyledText {
                                id: statusText
                                anchors.centerIn: parent
                                text: MediaDownloaderService.currentStatus
                                font.pixelSize: 10
                                color: {
                                    switch (MediaDownloaderService.currentStatus) {
                                    case "downloading": return Appearance.colors.colOnPrimaryContainer;
                                    case "error": return Appearance.colors.colOnErrorContainer;
                                    case "checking": return Appearance.colors.colOnTertiaryContainer;
                                    default: return Appearance.colors.colOnSecondaryContainer;
                                    }
                                }
                            }
                        }
                        // Clear log button
                        RippleButton {
                            implicitWidth: 26
                            implicitHeight: 26
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                            colRipple: Appearance.colors.colPrimary
                            onClicked: MediaDownloaderService.clearLog()

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "delete_sweep"
                                iconSize: 14
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }

                    // Log text area
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2

                        Flickable {
                            id: logFlickable
                            anchors.fill: parent
                            anchors.margins: 8
                            contentWidth: width
                            contentHeight: logText.implicitHeight
                            clip: true

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                            }

                            Text {
                                id: logText
                                width: logFlickable.width
                                text: MediaDownloaderService.logOutput
                                color: Appearance.colors.colOnSurface
                                font.pixelSize: 11
                                font.family: Appearance.font.family.monospace || "monospace"
                                wrapMode: Text.Wrap

                                onImplicitHeightChanged: {
                                    logFlickable.contentY = Math.max(0, logText.implicitHeight - logFlickable.height);
                                }
                            }
                        }
                    }

                    // Progress bar
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: progressBarVisible ? 20 : 0
                        visible: progressBarVisible
                        opacity: progressBarVisible ? 1.0 : 0.0
                        clip: true

                        readonly property bool progressBarVisible: MediaDownloaderService.isDownloading || MediaDownloaderService.downloadProgress > 0

                        Behavior on implicitHeight {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                            }
                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                StyledText {
                                    text: "Downloading..."
                                    font.pixelSize: 10
                                    color: Appearance.colors.colSubtext
                                    Layout.fillWidth: true
                                }
                                StyledText {
                                    text: Math.round(MediaDownloaderService.downloadProgress * 100) + "%"
                                    font.pixelSize: 10
                                    color: Appearance.colors.colPrimary
                                }
                            }

                            StyledProgressBar {
                                Layout.fillWidth: true
                                value: MediaDownloaderService.downloadProgress
                            }
                        }
                    }
                }
            }
        }

        // ── Row 3: Download button ────────────────────────────────────────────
        RippleButton {
            id: downloadBtn
            Layout.fillWidth: true
            implicitHeight: 44
            buttonRadius: Appearance.rounding.normal
            colBackground: MediaDownloaderService.isDownloading
                ? Appearance.colors.colErrorContainer
                : Appearance.colors.colPrimaryContainer
            colBackgroundHover: MediaDownloaderService.isDownloading
                ? Appearance.colors.colErrorContainerHover
                : Appearance.colors.colPrimaryContainerHover
            colRipple: MediaDownloaderService.isDownloading
                ? Appearance.colors.colOnErrorContainer
                : Appearance.colors.colOnPrimaryContainer

            Behavior on colBackground {
                ColorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                }
            }

            onClicked: {
                root.focusedControlIndex = 8;
                if (MediaDownloaderService.isDownloading) {
                    MediaDownloaderService.cancelDownload();
                } else {
                    MediaDownloaderService.startDownload(
                        urlField.text,
                        root.selectedFormat,
                        root.selectedType,
                        root.extraArgsText
                    );
                }
            }

            // Keyboard focus highlight ring
            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                color: "transparent"
                border.color: root.focusedControlIndex === 8 ? Appearance.colors.colPrimary : "transparent"
                border.width: 2
                radius: parent.buttonRadius + 3
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 8

                MaterialSymbol {
                    text: MediaDownloaderService.isDownloading ? "cancel" : "download"
                    iconSize: Appearance.font.pixelSize.normal
                    color: MediaDownloaderService.isDownloading
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnPrimaryContainer
                }

                StyledText {
                    text: {
                        if (MediaDownloaderService.currentStatus === "checking") return "Checking dependencies...";
                        if (MediaDownloaderService.isDownloading) return "Cancel Download";
                        if (!MediaDownloaderService.ready) return "Not Ready";
                        return "Download";
                    }
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: MediaDownloaderService.isDownloading
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnPrimaryContainer
                }
            }
        }
    }
}
