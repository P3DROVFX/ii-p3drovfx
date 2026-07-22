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

    readonly property int panelWidth: Config.options.search.clipboard.panelWidth ?? 900
    implicitWidth: panelWidth
    implicitHeight: mainColumn.implicitHeight + 32

    // ── Format definitions ───────────────────────────────────────────────────
    readonly property var formatOptions: [
        { id: "best",       label: "Best",  icon: "star" },
        { id: "video-mp4",  label: "MP4",   icon: "videocam" },
        { id: "audio-mp3",  label: "MP3",   icon: "audiotrack" },
        { id: "audio-ogg",  label: "OGG",   icon: "music_note" },
        { id: "audio-opus", label: "OPUS",  icon: "graphic_eq" },
        { id: "audio-m4a",  label: "M4A",   icon: "album" }
    ]

    readonly property var typeOptions: [
        { id: "basic",    label: "Single",   icon: "download" },
        { id: "batch",    label: "Batch",    icon: "queue" },
        { id: "playlist", label: "Playlist", icon: "playlist_play" }
    ]

    property string selectedFormat: Config.options.mediaDownloader.lastUsedFormat || "best"
    property string selectedType: "basic"
    property string extraArgsText: ""
    property bool showAdvancedArgs: Config.options.mediaDownloader.showAdvancedArgs

    // Keyboard navigation
    property int focusedControlIndex: -1
    readonly property int qualityChipStartIndex: 9
    readonly property int qualityChipCount: {
        if (root.selectedFormat === "best" || root.selectedFormat.startsWith("video-")) {
            return MediaDownloaderService.videoResolutionOptions.length;
        } else if (root.selectedFormat.startsWith("audio-")) {
            return MediaDownloaderService.audioBitrateOptions.length;
        }
        return 0;
    }
    readonly property int downloadButtonIndex: qualityChipStartIndex + qualityChipCount
    readonly property int cancelButtonIndex: downloadButtonIndex + 1

    // URL state
    property bool urlInvalid: false
    property string urlInvalidReason: ""
    property bool showErrorTooltip: false

    // ── Computed visual state ────────────────────────────────────────────────
    readonly property bool isAudio: root.selectedFormat.startsWith("audio-")
    readonly property bool isVideo: root.selectedFormat.startsWith("video-") || root.selectedFormat === "best"
    readonly property string statusColor: {
        switch (MediaDownloaderService.currentStatus) {
        case "downloading": return "primary"
        case "preparing":   return "tertiary"
        case "converting":  return "secondary"
        case "error":       return "error"
        case "checking":    return "tertiary"
        case "cancelling":  return "secondary"
        default:            return "surface"
        }
    }

    function focusInput() { focusedControlIndex = 0 }

    function navigateDown() {
        if (focusedControlIndex === -1) {
            focusedControlIndex = 0;
        } else if (focusedControlIndex >= 0 && focusedControlIndex <= 2) {
            focusedControlIndex = 3;
        } else if (focusedControlIndex >= 3 && focusedControlIndex <= 8) {
            if (root.qualityChipCount > 0) {
                focusedControlIndex = root.qualityChipStartIndex;
            } else {
                focusedControlIndex = root.downloadButtonIndex;
            }
        } else if (focusedControlIndex >= root.qualityChipStartIndex &&
                   focusedControlIndex < root.qualityChipStartIndex + root.qualityChipCount) {
            focusedControlIndex = root.downloadButtonIndex;
        }
    }

    function navigateUp() {
        if (focusedControlIndex === root.downloadButtonIndex || focusedControlIndex === root.cancelButtonIndex) {
            if (root.qualityChipCount > 0) {
                focusedControlIndex = root.qualityChipStartIndex + root.qualityChipCount - 1;
            } else {
                focusedControlIndex = 8;
            }
        } else if (focusedControlIndex >= root.qualityChipStartIndex &&
                   focusedControlIndex < root.qualityChipStartIndex + root.qualityChipCount) {
            focusedControlIndex = 3;
        } else if (focusedControlIndex >= 3 && focusedControlIndex <= 8) {
            focusedControlIndex = 0;
        } else if (focusedControlIndex >= 0 && focusedControlIndex <= 2) {
            focusedControlIndex = -1;
        }
    }

    function navigateLeft() {
        if (focusedControlIndex > 0 && focusedControlIndex <= 2) {
            focusedControlIndex--;
        } else if (focusedControlIndex > 3 && focusedControlIndex <= 8) {
            focusedControlIndex--;
        } else if (focusedControlIndex > root.qualityChipStartIndex &&
                   focusedControlIndex < root.qualityChipStartIndex + root.qualityChipCount) {
            focusedControlIndex--;
        }
    }

    function navigateRight() {
        if (focusedControlIndex >= 0 && focusedControlIndex < 2) {
            focusedControlIndex++;
        } else if (focusedControlIndex >= 3 && focusedControlIndex < 8) {
            focusedControlIndex++;
        } else if (focusedControlIndex >= root.qualityChipStartIndex &&
                   focusedControlIndex < root.qualityChipStartIndex + root.qualityChipCount - 1) {
            focusedControlIndex++;
        }
    }

    function activateSelected() {
        if (focusedControlIndex >= 0 && focusedControlIndex <= 2) {
            root.selectedType = root.typeOptions[focusedControlIndex].id;
        } else if (focusedControlIndex >= 3 && focusedControlIndex <= 8) {
            root.selectedFormat = root.formatOptions[focusedControlIndex - 3].id;
            Config.options.mediaDownloader.lastUsedFormat = root.selectedFormat;
        } else if (focusedControlIndex >= root.qualityChipStartIndex &&
                   focusedControlIndex < root.qualityChipStartIndex + root.qualityChipCount) {
            const chipIndex = focusedControlIndex - root.qualityChipStartIndex;
            if (root.selectedFormat === "best" || root.selectedFormat.startsWith("video-")) {
                Config.options.mediaDownloader.videoResolution = MediaDownloaderService.videoResolutionOptions[chipIndex].value;
            } else if (root.selectedFormat.startsWith("audio-")) {
                Config.options.mediaDownloader.audioBitrate = MediaDownloaderService.audioBitrateOptions[chipIndex].value;
            }
        } else if (focusedControlIndex === root.downloadButtonIndex) {
            startDownloadAction();
        } else if (focusedControlIndex === root.cancelButtonIndex) {
            MediaDownloaderService.cancelDownload();
        }
    }

    function startDownloadAction() {
        const validation = MediaDownloaderService.validateUrl(root.searchQuery);
        if (!validation.ok) {
            root.urlInvalid = true;
            root.urlInvalidReason = validation.reason;
            root.showErrorTooltip = true;
            errorTooltipTimer.restart();
            urlShakeAnim.restart();
            return;
        }
        root.urlInvalid = false;
        root.urlInvalidReason = "";

        const result = MediaDownloaderService.addToQueue(
            root.searchQuery,
            root.selectedFormat,
            root.selectedType,
            root.extraArgsText
        );
        if (!result.ok) {
            root.urlInvalid = true;
            root.urlInvalidReason = result.reason;
            root.showErrorTooltip = true;
            errorTooltipTimer.restart();
            urlShakeAnim.restart();
        }
    }

    function pasteFromClipboard() {
        const clipboardText = Quickshell.clipboardText;
        if (clipboardText) {
            root.searchQuery = clipboardText;
        }
    }

    onSearchQueryChanged: {
        root.urlInvalid = false;
        root.urlInvalidReason = "";
        root.showErrorTooltip = false;
        errorTooltipTimer.stop();
        focusedControlIndex = -1;
        if (root.searchQuery && root.searchQuery.match(/^https?:\/\/[^\s]/i)) {
            thumbnailFetchTimer.restart();
            const detectedFormat = MediaDownloaderService.detectFormatFromUrl(root.searchQuery);
            if (detectedFormat && detectedFormat !== root.selectedFormat) {
                root.selectedFormat = detectedFormat;
                Config.options.mediaDownloader.lastUsedFormat = detectedFormat;
            }
        } else {
            MediaDownloaderService.thumbnailUrl = "";
            MediaDownloaderService.thumbnailTitle = "";
        }
    }

    Timer {
        id: thumbnailFetchTimer
        interval: 800
        repeat: false
        onTriggered: {
            if (root.searchQuery && root.searchQuery.match(/^https?:\/\/[^\s]/i)) {
                MediaDownloaderService.fetchThumbnail(root.searchQuery);
            }
        }
    }

    Timer {
        id: errorTooltipTimer
        interval: 3000
        repeat: false
        onTriggered: root.showErrorTooltip = false
    }

    // ── Error shake ──────────────────────────────────────────────────────────
    SequentialAnimation {
        id: urlShakeAnim
        loops: 3
        NumberAnimation {
            target: urlZone
            property: "x"
            from: 0; to: -8
            duration: 45
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: urlZone
            property: "x"
            from: -8; to: 8
            duration: 90
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: urlZone
            property: "x"
            from: 8; to: 0
            duration: 45
            easing.type: Easing.InQuad
        }
    }

    // ── Layout root ──────────────────────────────────────────────────────────
    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // ── HERO — URL zone + status badge ───────────────────────────────────
        Item {
            id: urlZone
            Layout.fillWidth: true
            implicitHeight: 56

            // Thumbnail-aware hero background when thumb available
            Rectangle {
                id: heroBg
                anchors.fill: parent
                radius: Appearance.rounding.large
                color: root.urlInvalid
                       ? Appearance.colors.colErrorContainer
                       : Appearance.colors.colSurfaceContainerHigh
                clip: true

                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.OutCubic
                    }
                }

                // Thumbnail ambient blur strip (decorative)
                Image {
                    anchors.fill: parent
                    source: MediaDownloaderService.thumbnailUrl
                    fillMode: Image.PreserveAspectCrop
                    opacity: MediaDownloaderService.thumbnailUrl !== "" ? 0.18 : 0.0
                    asynchronous: true
                    visible: !root.urlInvalid

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveEnter.duration
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 8
                    spacing: 10

                    // Status dot
                    Rectangle {
                        id: statusDot
                        implicitWidth: 8
                        implicitHeight: 8
                        radius: Appearance.rounding.full
                        color: {
                            switch (MediaDownloaderService.currentStatus) {
                            case "downloading": return Appearance.colors.colPrimary
                            case "preparing":   return Appearance.colors.colTertiary
                            case "converting":  return Appearance.colors.colSecondary
                            case "error":       return Appearance.colors.colError
                            case "checking":    return Appearance.colors.colTertiary
                            default:
                                return MediaDownloaderService.ready
                                       ? Appearance.colors.colPrimary
                                       : Appearance.colors.colOnSurfaceVariant
                            }
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Easing.OutCubic
                            }
                        }

                        // Pulse animation when active
                        SequentialAnimation {
                            running: MediaDownloaderService.currentStatus !== "idle"
                            loops: Animation.Infinite
                            NumberAnimation {
                                target: statusDot
                                property: "opacity"
                                from: 1.0; to: 0.3
                                duration: 700
                                easing.type: Easing.InOutSine
                            }
                            NumberAnimation {
                                target: statusDot
                                property: "opacity"
                                from: 0.3; to: 1.0
                                duration: 700
                                easing.type: Easing.InOutSine
                            }
                        }
                    }

                    // Link icon
                    MaterialSymbol {
                        text: root.urlInvalid ? "error" : (root.searchQuery ? "link" : "link")
                        iconSize: 18
                        fill: root.urlInvalid ? 1.0 : 0.0
                        color: root.urlInvalid
                               ? Appearance.colors.colOnErrorContainer
                               : Appearance.colors.colOnSurfaceVariant

                        Behavior on fill {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    // URL text — fills width
                    StyledText {
                        Layout.fillWidth: true
                        text: root.searchQuery || "Paste a URL to download…"
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: root.searchQuery ? Appearance.font.family.monospace : Appearance.font.family.main
                        color: root.urlInvalid
                               ? Appearance.colors.colOnErrorContainer
                               : (root.searchQuery
                                  ? Appearance.colors.colOnSurface
                                  : Appearance.colors.colOnSurfaceVariant)
                        elide: Text.ElideMiddle
                        maximumLineCount: 1

                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                            }
                        }
                    }

                    // Clear button
                    RippleButton {
                        visible: root.searchQuery !== ""
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                        colRipple: Appearance.colors.colPrimary

                        HoverHandler { cursorShape: Qt.PointingHandCursor }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 16
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        onClicked: root.searchQuery = ""
                    }

                    // Paste button — pill shape, vibrant
                    RippleButton {
                        implicitWidth: pasteRow.implicitWidth + 20
                        implicitHeight: 38
                        buttonRadius: Appearance.rounding.large
                        colBackground: Appearance.colors.colPrimaryContainer
                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                        colRipple: Appearance.colors.colOnPrimaryContainer

                        HoverHandler { cursorShape: Qt.PointingHandCursor }

                        RowLayout {
                            id: pasteRow
                            anchors.centerIn: parent
                            spacing: 6

                            MaterialSymbol {
                                text: "content_paste"
                                iconSize: 16
                                color: Appearance.colors.colOnPrimaryContainer
                            }

                            StyledText {
                                text: "Paste"
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }

                        onClicked: root.pasteFromClipboard()

                        StyledToolTip { text: "Paste from clipboard" }
                    }
                }

                StyledToolTip {
                    text: root.urlInvalidReason
                    visible: root.showErrorTooltip && root.urlInvalid
                    parent: heroBg
                }
            }
        }

        // ── BODY — left controls + right log ────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // ── LEFT COLUMN ─────────────────────────────────────────────────
            ColumnLayout {
                Layout.maximumWidth: Math.round(root.panelWidth * 0.42)
                Layout.minimumWidth: Math.round(root.panelWidth * 0.30)
                Layout.fillHeight: true
                spacing: 8

                // ── TYPE — expressive segmented group ────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        spacing: 6
                        MaterialSymbol {
                            text: "category"
                            iconSize: 15
                            fill: 1.0
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            text: "Download type"
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    // Three type chips — use GroupButton bounce
                    RowLayout {
                        id: typeChipRow
                        Layout.fillWidth: true
                        spacing: 4
                        property int clickIndex: -1

                        Repeater {
                            model: root.typeOptions
                            delegate: GroupButton {
                                required property var modelData
                                required property int index

                                Layout.fillWidth: true
                                bounce: true
                                buttonText: modelData.label
                                toggled: root.selectedType === modelData.id
                                parentGroup: typeChipRow
                                horizontalPadding: 10
                                verticalPadding: 8
                                buttonRadius: Appearance.rounding.large
                                buttonRadiusPressed: Appearance.rounding.normal

                                colBackground: root.focusedControlIndex === index
                                               ? Appearance.colors.colTertiaryContainer
                                               : (root.selectedType === modelData.id
                                                  ? Appearance.colors.colPrimaryContainer
                                                  : Appearance.colors.colSurfaceContainerHigh)
                                colBackgroundHover: root.selectedType === modelData.id
                                                    ? Appearance.colors.colPrimaryContainerHover
                                                    : Appearance.colors.colTertiaryContainerHover
                                colBackgroundToggled: Appearance.colors.colPrimaryContainer
                                colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover

                                contentItem: RowLayout {
                                    spacing: 6
                                    anchors.centerIn: parent

                                    MaterialSymbol {
                                        text: modelData.icon
                                        iconSize: 16
                                        fill: root.selectedType === modelData.id ? 1.0 : 0.0
                                        color: root.focusedControlIndex === index
                                               ? Appearance.colors.colOnTertiaryContainer
                                               : (root.selectedType === modelData.id
                                                  ? Appearance.colors.colOnPrimaryContainer
                                                  : Appearance.colors.colOnSurfaceVariant)

                                        Behavior on fill {
                                            NumberAnimation {
                                                duration: Appearance.animation.elementMoveFast.duration
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                    }

                                    StyledText {
                                        text: modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: root.focusedControlIndex === index
                                               ? Appearance.colors.colOnTertiaryContainer
                                               : (root.selectedType === modelData.id
                                                  ? Appearance.colors.colOnPrimaryContainer
                                                  : Appearance.colors.colOnSurface)
                                    }
                                }

                                onClicked: {
                                    root.focusedControlIndex = index;
                                    root.selectedType = modelData.id;
                                }
                            }
                        }
                    }
                }

                // ── FORMAT — expressive flow chips ───────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        spacing: 6
                        MaterialSymbol {
                            text: "description"
                            iconSize: 15
                            fill: 1.0
                            color: Appearance.colors.colSecondary
                        }
                        StyledText {
                            text: "Format"
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: root.formatOptions
                            delegate: RippleButton {
                                required property var modelData
                                required property int index

                                readonly property bool isSelected: root.selectedFormat === modelData.id
                                readonly property bool isFocused: root.focusedControlIndex === (3 + index)

                                implicitWidth: fmtChip.implicitWidth + 24
                                implicitHeight: 36
                                buttonRadius: Appearance.rounding.full
                                colBackground: isFocused
                                               ? Appearance.colors.colTertiaryContainer
                                               : (isSelected
                                                  ? Appearance.colors.colSecondaryContainer
                                                  : Appearance.colors.colSurfaceContainerHigh)
                                colBackgroundHover: isSelected
                                                    ? Appearance.colors.colSecondaryContainerHover
                                                    : Appearance.colors.colTertiaryContainerHover
                                colRipple: Appearance.colors.colPrimary

                                Behavior on colBackground {
                                    ColorAnimation {
                                        duration: Appearance.animation.elementMoveFast.duration
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                // Scale spring on select
                                scale: isSelected ? 1.05 : 1.0
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 220
                                        easing.type: Easing.OutBack
                                        easing.overshoot: 2.0
                                    }
                                }

                                HoverHandler { cursorShape: Qt.PointingHandCursor }

                                RowLayout {
                                    id: fmtChip
                                    anchors.centerIn: parent
                                    spacing: 6

                                    MaterialSymbol {
                                        text: modelData.icon
                                        iconSize: 15
                                        fill: isSelected ? 1.0 : 0.0
                                        color: isFocused
                                               ? Appearance.colors.colOnTertiaryContainer
                                               : (isSelected
                                                  ? Appearance.colors.colOnSecondaryContainer
                                                  : Appearance.colors.colOnSurface)

                                        Behavior on fill {
                                            NumberAnimation {
                                                duration: Appearance.animation.elementMoveFast.duration
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                    }

                                    StyledText {
                                        text: modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: isSelected ? Font.Medium : Font.Normal
                                        color: isFocused
                                               ? Appearance.colors.colOnTertiaryContainer
                                               : (isSelected
                                                  ? Appearance.colors.colOnSecondaryContainer
                                                  : Appearance.colors.colOnSurface)
                                    }
                                }

                                onClicked: {
                                    root.focusedControlIndex = 3 + index;
                                    root.selectedFormat = modelData.id;
                                    Config.options.mediaDownloader.lastUsedFormat = modelData.id;
                                }
                            }
                        }
                    }
                }

                // ── QUALITY ── animated reveal ───────────────────────────────
                Item {
                    Layout.fillWidth: true
                    implicitHeight: qualityReveal.implicitHeight
                    visible: root.selectedFormat !== "best"
                    clip: true

                    Behavior on implicitHeight {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveEnter.duration
                            easing.type: Easing.OutCubic
                        }
                    }

                    ColumnLayout {
                        id: qualityReveal
                        width: parent.width
                        spacing: 6

                        RowLayout {
                            spacing: 6
                            MaterialSymbol {
                                text: "tune"
                                iconSize: 15
                                fill: 1.0
                                color: Appearance.colors.colTertiary
                            }
                            StyledText {
                                text: root.isAudio ? "Bitrate" : "Resolution"
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }

                        // Video resolution chips
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: root.isVideo

                            Repeater {
                                model: MediaDownloaderService.videoResolutionOptions
                                delegate: RippleButton {
                                    required property var modelData
                                    required property int index

                                    readonly property bool isSelected: Config.options.mediaDownloader.videoResolution === modelData.value
                                    readonly property bool isFocused: root.focusedControlIndex === (root.qualityChipStartIndex + index)

                                    implicitWidth: resLbl.implicitWidth + 20
                                    implicitHeight: 32
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: (isFocused || isSelected)
                                                   ? Appearance.colors.colTertiaryContainer
                                                   : Appearance.colors.colSurfaceContainerHigh
                                    colBackgroundHover: Appearance.colors.colTertiaryContainerHover
                                    colRipple: Appearance.colors.colTertiary

                                    scale: isSelected ? 1.05 : 1.0
                                    Behavior on scale {
                                        NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                                    }

                                    HoverHandler { cursorShape: Qt.PointingHandCursor }

                                    StyledText {
                                        id: resLbl
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: isSelected ? Font.SemiBold : Font.Normal
                                        color: isSelected
                                               ? Appearance.colors.colOnTertiaryContainer
                                               : Appearance.colors.colOnSurface
                                    }

                                    onClicked: Config.options.mediaDownloader.videoResolution = modelData.value
                                }
                            }
                        }

                        // Audio bitrate chips
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: root.isAudio

                            Repeater {
                                model: MediaDownloaderService.audioBitrateOptions
                                delegate: RippleButton {
                                    required property var modelData
                                    required property int index

                                    readonly property bool isSelected: Config.options.mediaDownloader.audioBitrate === modelData.value
                                    readonly property bool isFocused: root.focusedControlIndex === (root.qualityChipStartIndex + index)

                                    implicitWidth: bitLbl.implicitWidth + 20
                                    implicitHeight: 32
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: (isFocused || isSelected)
                                                   ? Appearance.colors.colTertiaryContainer
                                                   : Appearance.colors.colSurfaceContainerHigh
                                    colBackgroundHover: Appearance.colors.colTertiaryContainerHover
                                    colRipple: Appearance.colors.colTertiary

                                    scale: isSelected ? 1.05 : 1.0
                                    Behavior on scale {
                                        NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                                    }

                                    HoverHandler { cursorShape: Qt.PointingHandCursor }

                                    StyledText {
                                        id: bitLbl
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: isSelected ? Font.SemiBold : Font.Normal
                                        color: isSelected
                                               ? Appearance.colors.colOnTertiaryContainer
                                               : Appearance.colors.colOnSurface
                                    }

                                    onClicked: Config.options.mediaDownloader.audioBitrate = modelData.value
                                }
                            }
                        }
                    }
                }

                // ── ADVANCED ARGS ─────────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    // Header toggle
                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        buttonRadius: root.showAdvancedArgs ? Appearance.rounding.large : Appearance.rounding.large
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHigh
                        colRipple: Appearance.colors.colPrimary

                        HoverHandler { cursorShape: Qt.PointingHandCursor }

                        contentItem: RowLayout {
                            spacing: 6
                            anchors.fill: parent
                            anchors.leftMargin: 2

                            MaterialSymbol {
                                text: "terminal"
                                iconSize: 15
                                fill: root.showAdvancedArgs ? 1.0 : 0.0
                                color: root.showAdvancedArgs
                                       ? Appearance.colors.colPrimary
                                       : Appearance.colors.colOnSurfaceVariant

                                Behavior on fill {
                                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                }
                            }

                            StyledText {
                                text: "Extra args"
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnSurfaceVariant
                                Layout.fillWidth: true
                            }

                            MaterialSymbol {
                                text: root.showAdvancedArgs ? "expand_less" : "expand_more"
                                iconSize: 16
                                color: Appearance.colors.colOnSurfaceVariant

                                Behavior on rotation {
                                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        onClicked: {
                            root.showAdvancedArgs = !root.showAdvancedArgs;
                            Config.options.mediaDownloader.showAdvancedArgs = root.showAdvancedArgs;
                        }
                    }

                    // Collapsible text area
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: root.showAdvancedArgs ? argsAreaContainer.implicitHeight : 0
                        clip: true

                        Behavior on implicitHeight {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveEnter.duration
                                easing.type: Easing.OutCubic
                            }
                        }

                        opacity: root.showAdvancedArgs ? 1.0 : 0.0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Easing.OutCubic
                            }
                        }

                        MaterialTextArea {
                            id: argsAreaContainer
                            width: parent.width
                            placeholderText: "--cookies-from-browser firefox…"
                            text: root.extraArgsText
                            onTextChanged: root.extraArgsText = text
                        }
                    }
                }

                // ── ERROR STATES ─────────────────────────────────────────────
                Rectangle {
                    visible: !MediaDownloaderService.ytdlpFound && MediaDownloaderService.ready
                    Layout.fillWidth: true
                    implicitHeight: ytdlpErrRow.implicitHeight + 20
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colErrorContainer

                    RowLayout {
                        id: ytdlpErrRow
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        MaterialSymbol {
                            text: "error"
                            iconSize: 18
                            fill: 1.0
                            color: Appearance.colors.colOnErrorContainer
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: "yt-dlp not found — install: sudo pacman -S yt-dlp"
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnErrorContainer
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                WarningBox {
                    visible: !MediaDownloaderService.ffmpegFound &&
                             root.isAudio &&
                             MediaDownloaderService.ready
                    Layout.fillWidth: true
                    text: "ffmpeg missing — audio conversion unavailable"
                }

                // ── QUEUE ─────────────────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: MediaDownloaderService.downloadQueue.length > 0

                    RowLayout {
                        spacing: 6

                        MaterialSymbol {
                            text: "queue"
                            iconSize: 15
                            fill: 1.0
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            text: "Queue · " + MediaDownloaderService.downloadQueue.length
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurface
                            Layout.fillWidth: true
                        }

                        RippleButton {
                            visible: MediaDownloaderService.downloadQueue.some(item => item.status === "queued")
                            implicitWidth: 28
                            implicitHeight: 28
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colErrorContainer
                            colRipple: Appearance.colors.colError

                            HoverHandler { cursorShape: Qt.PointingHandCursor }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "clear_all"
                                iconSize: 15
                                color: Appearance.colors.colOnSurfaceVariant
                            }

                            onClicked: MediaDownloaderService.clearQueue()

                            StyledToolTip { text: "Clear queue" }
                        }
                    }

                    Repeater {
                        model: MediaDownloaderService.downloadQueue.slice(0, 5)
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: queueItemRow.implicitHeight + 14
                            radius: Appearance.rounding.normal
                            color: {
                                switch (modelData.status) {
                                case "downloading": return Appearance.colors.colPrimaryContainer
                                case "complete":    return Appearance.colors.colSecondaryContainer
                                case "error":       return Appearance.colors.colErrorContainer
                                default:            return Appearance.colors.colSurfaceContainerHigh
                                }
                            }

                            Behavior on color {
                                ColorAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            RowLayout {
                                id: queueItemRow
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 8

                                MaterialLoadingIndicator {
                                    visible: modelData.status === "downloading"
                                    implicitSize: 14
                                }

                                MaterialSymbol {
                                    visible: modelData.status !== "downloading"
                                    text: {
                                        switch (modelData.status) {
                                        case "complete": return "check_circle"
                                        case "error":    return "error"
                                        default:         return "schedule"
                                        }
                                    }
                                    iconSize: 14
                                    fill: modelData.status === "complete" ? 1.0 : 0.0
                                    color: {
                                        switch (modelData.status) {
                                        case "complete": return Appearance.colors.colOnSecondaryContainer
                                        case "error":    return Appearance.colors.colOnErrorContainer
                                        default:         return Appearance.colors.colOnSurfaceVariant
                                        }
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.url.length > 45
                                          ? modelData.url.substring(0, 45) + "…"
                                          : modelData.url
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.family: Appearance.font.family.monospace
                                    elide: Text.ElideRight
                                    color: {
                                        switch (modelData.status) {
                                        case "downloading": return Appearance.colors.colOnPrimaryContainer
                                        case "complete":    return Appearance.colors.colOnSecondaryContainer
                                        case "error":       return Appearance.colors.colOnErrorContainer
                                        default:            return Appearance.colors.colOnSurfaceVariant
                                        }
                                    }
                                }

                                RippleButton {
                                    visible: modelData.status === "queued"
                                    implicitWidth: 22
                                    implicitHeight: 22
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: "transparent"
                                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighest

                                    HoverHandler { cursorShape: Qt.PointingHandCursor }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "close"
                                        iconSize: 12
                                        color: Appearance.colors.colOnSurfaceVariant
                                    }

                                    onClicked: MediaDownloaderService.removeFromQueue(modelData.id)
                                }
                            }
                        }
                    }

                    StyledText {
                        visible: MediaDownloaderService.downloadQueue.length > 5
                        text: "+ " + (MediaDownloaderService.downloadQueue.length - 5) + " more"
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnSurfaceVariant
                        opacity: 0.7
                    }
                }

                Item { Layout.fillHeight: true }
            }

            // ── RIGHT COLUMN — Thumbnail + Log ───────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 200
                spacing: 8

                // ── THUMBNAIL HERO ──────────────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: thumbnailVisible ? Math.min(190, parent.width * 0.5625) : 0
                    clip: true

                    readonly property bool thumbnailVisible: MediaDownloaderService.thumbnailUrl !== "" ||
                                                             MediaDownloaderService.thumbnailLoading

                    Behavior on Layout.preferredHeight {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveEnter.duration
                            easing.type: Easing.OutCubic
                        }
                    }

                    // Thumbnail card
                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colSurfaceContainerLow
                        clip: true
                        visible: parent.thumbnailVisible

                        Image {
                            anchors.fill: parent
                            source: MediaDownloaderService.thumbnailUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true

                            opacity: status === Image.Ready ? 1.0 : 0.0
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveEnter.duration
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        // Gradient overlay for title
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: thumbTitle.implicitHeight + 28
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.72) }
                            }
                            visible: MediaDownloaderService.thumbnailTitle !== ""
                        }

                        StyledText {
                            id: thumbTitle
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.bottomMargin: 10
                            text: MediaDownloaderService.thumbnailTitle
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Medium
                            color: "white"
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                            visible: text !== ""
                        }

                        // Loading spinner
                        MaterialLoadingIndicator {
                            anchors.centerIn: parent
                            implicitSize: 28
                            visible: MediaDownloaderService.thumbnailLoading
                        }
                    }
                }

                // ── LOG PANEL ────────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colSurfaceContainer
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        // Log header bar
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            // Animated status badge
                            Rectangle {
                                implicitWidth: statusBadgeRow.implicitWidth + 16
                                implicitHeight: 26
                                radius: Appearance.rounding.full
                                color: {
                                    switch (MediaDownloaderService.currentStatus) {
                                    case "downloading": return Appearance.colors.colPrimaryContainer
                                    case "preparing":   return Appearance.colors.colTertiaryContainer
                                    case "converting":  return Appearance.colors.colSecondaryContainer
                                    case "error":       return Appearance.colors.colErrorContainer
                                    case "checking":    return Appearance.colors.colTertiaryContainer
                                    case "cancelling":  return Appearance.colors.colSecondaryContainer
                                    default:            return Appearance.colors.colSurfaceContainerHigh
                                    }
                                }

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Appearance.animation.elementMoveFast.duration
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                RowLayout {
                                    id: statusBadgeRow
                                    anchors.centerIn: parent
                                    spacing: 5

                                    MaterialLoadingIndicator {
                                        visible: MediaDownloaderService.currentStatus === "checking" ||
                                                 MediaDownloaderService.currentStatus === "preparing" ||
                                                 MediaDownloaderService.currentStatus === "converting"
                                        implicitSize: 14
                                    }

                                    MaterialSymbol {
                                        visible: !statusBadgeRow.children[0].visible
                                        text: {
                                            switch (MediaDownloaderService.currentStatus) {
                                            case "downloading": return "downloading"
                                            case "error":       return "error"
                                            case "idle":        return "check_circle"
                                            default:            return "hourglass_empty"
                                            }
                                        }
                                        iconSize: 13
                                        fill: MediaDownloaderService.currentStatus === "idle" ? 1.0 : 0.0
                                        color: {
                                            switch (MediaDownloaderService.currentStatus) {
                                            case "downloading": return Appearance.colors.colOnPrimaryContainer
                                            case "error":       return Appearance.colors.colOnErrorContainer
                                            case "checking":
                                            case "preparing":
                                            case "converting":  return Appearance.colors.colOnTertiaryContainer
                                            default:            return Appearance.colors.colOnSurfaceVariant
                                            }
                                        }
                                    }

                                    StyledText {
                                        text: {
                                            switch (MediaDownloaderService.currentStatus) {
                                            case "downloading": return Math.round(MediaDownloaderService.downloadProgress * 100) + "%"
                                            case "preparing":   return "Preparing"
                                            case "converting":  return "Converting"
                                            case "error":       return "Error"
                                            case "checking":    return "Checking"
                                            case "cancelling":  return "Cancelling"
                                            case "idle":        return MediaDownloaderService.ready ? "Ready" : "Not ready"
                                            default:            return ""
                                            }
                                        }
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Medium
                                        color: {
                                            switch (MediaDownloaderService.currentStatus) {
                                            case "downloading": return Appearance.colors.colOnPrimaryContainer
                                            case "error":       return Appearance.colors.colOnErrorContainer
                                            case "checking":
                                            case "preparing":
                                            case "converting":  return Appearance.colors.colOnTertiaryContainer
                                            default:            return Appearance.colors.colOnSurfaceVariant
                                            }
                                        }
                                    }
                                }
                            }

                            // Speed / ETA stats (when downloading)
                            StyledText {
                                visible: MediaDownloaderService.parsedStats.phase === "downloading"
                                text: {
                                    const stats = MediaDownloaderService.parsedStats;
                                    if (stats.size && stats.speed && stats.eta) {
                                        return stats.size + " · " + stats.speed + " · ETA " + stats.eta;
                                    }
                                    return "";
                                }
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.family: Appearance.font.family.monospace
                                color: Appearance.colors.colPrimary
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Item { Layout.fillWidth: true; visible: !MediaDownloaderService.isDownloading }

                            // Log label
                            MaterialSymbol {
                                text: "terminal"
                                iconSize: 14
                                color: Appearance.colors.colOnSurfaceVariant
                            }

                            // Clear log button
                            RippleButton {
                                implicitWidth: 26
                                implicitHeight: 26
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                                colRipple: Appearance.colors.colPrimary

                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                onClicked: MediaDownloaderService.clearLog()

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "delete_sweep"
                                    iconSize: 14
                                    color: Appearance.colors.colOnSurfaceVariant
                                }

                                StyledToolTip { text: "Clear log" }
                            }
                        }

                        // Progress bar (animated)
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: progressVisible ? 28 : 0
                            clip: true

                            readonly property bool progressVisible: MediaDownloaderService.isDownloading ||
                                                                    MediaDownloaderService.currentStatus === "preparing" ||
                                                                    MediaDownloaderService.currentStatus === "converting"

                            Behavior on implicitHeight {
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            opacity: parent.progressVisible ? 1.0 : 0.0
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Loader {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                readonly property bool useIndeterminate: MediaDownloaderService.currentStatus === "preparing" ||
                                                                         MediaDownloaderService.currentStatus === "converting"
                                sourceComponent: useIndeterminate ? indeterminateProg : determinateProg

                                Component {
                                    id: determinateProg
                                    StyledProgressBar {
                                        value: MediaDownloaderService.downloadProgress
                                        valueBarHeight: 6
                                        wavy: true
                                    }
                                }

                                Component {
                                    id: indeterminateProg
                                    StyledIndeterminateProgressBar {}
                                }
                            }
                        }

                        // Log text scroll area
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colSurfaceContainerLow
                            clip: true

                            StyledFlickable {
                                id: logFlickable
                                anchors.fill: parent
                                anchors.margins: 8
                                contentWidth: width
                                contentHeight: logText.implicitHeight
                                clip: true

                                Text {
                                    id: logText
                                    width: logFlickable.width
                                    text: MediaDownloaderService.logOutput
                                    color: Appearance.colors.colOnSurface
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.family: Appearance.font.family.monospace
                                    wrapMode: Text.Wrap

                                    onImplicitHeightChanged: {
                                        if (logFlickable.atYEnd ||
                                            logFlickable.contentY > logFlickable.contentHeight - logFlickable.height - 50) {
                                            logFlickable.contentY = Math.max(0, logText.implicitHeight - logFlickable.height);
                                        }
                                    }
                                }

                                // Scroll bar
                                StyledScrollBar {
                                    id: logScrollBar
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    orientation: Qt.Vertical
                                    size: logFlickable.height / (logFlickable.contentHeight || 1)
                                    position: logFlickable.contentY / (logFlickable.contentHeight - logFlickable.height || 1)
                                    onPositionChanged: {
                                        if (pressed) {
                                            logFlickable.contentY = position * (logFlickable.contentHeight - logFlickable.height);
                                        }
                                    }
                                }
                            }

                            // Empty state
                            ColumnLayout {
                                anchors.centerIn: parent
                                visible: MediaDownloaderService.logOutput === ""
                                spacing: 10

                                MaterialLoadingIndicator {
                                    visible: MediaDownloaderService.currentStatus === "checking"
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitWidth: 22
                                    implicitHeight: 22
                                }

                                MaterialSymbol {
                                    visible: MediaDownloaderService.currentStatus !== "checking"
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "terminal"
                                    iconSize: 28
                                    color: Appearance.colors.colOnSurfaceVariant
                                    opacity: 0.35
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: MediaDownloaderService.currentStatus === "checking"
                                          ? "Checking dependencies…"
                                          : "Output will appear here"
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnSurfaceVariant
                                    opacity: 0.6
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── ACTION ROW — FAB-style download + cancel ─────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Download button (fills width when not downloading)
            RippleButton {
                id: downloadBtn
                visible: !MediaDownloaderService.isDownloading &&
                         MediaDownloaderService.currentStatus !== "cancelling"
                Layout.fillWidth: true
                implicitHeight: 48
                buttonRadius: Appearance.rounding.large
                colBackground: root.focusedControlIndex === root.downloadButtonIndex
                               ? Appearance.colors.colPrimaryContainerHover
                               : Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                enabled: MediaDownloaderService.ready && MediaDownloaderService.ytdlpFound

                opacity: visible ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.OutCubic
                    }
                }

                HoverHandler { cursorShape: Qt.PointingHandCursor }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialSymbol {
                        text: "download"
                        iconSize: 20
                        color: Appearance.colors.colOnPrimaryContainer
                    }

                    StyledText {
                        text: "Download"
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                onClicked: {
                    root.focusedControlIndex = root.downloadButtonIndex;
                    root.startDownloadAction();
                }
            }

            // Cancel button (slide in when downloading)
            RippleButton {
                id: cancelBtn
                visible: MediaDownloaderService.isDownloading ||
                         MediaDownloaderService.currentStatus === "cancelling"
                Layout.fillWidth: true
                implicitHeight: 48
                buttonRadius: Appearance.rounding.large
                colBackground: root.focusedControlIndex === root.cancelButtonIndex
                               ? Appearance.colors.colErrorContainerHover
                               : Appearance.colors.colErrorContainer
                colBackgroundHover: Appearance.colors.colErrorContainerHover
                colRipple: Appearance.colors.colOnErrorContainer

                opacity: visible ? 1.0 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.OutCubic
                    }
                }

                HoverHandler { cursorShape: Qt.PointingHandCursor }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialSymbol {
                        text: "cancel"
                        iconSize: 20
                        color: Appearance.colors.colOnErrorContainer
                    }

                    StyledText {
                        text: MediaDownloaderService.currentStatus === "cancelling"
                              ? "Cancelling…"
                              : "Cancel"
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnErrorContainer
                    }
                }

                onClicked: {
                    root.focusedControlIndex = root.cancelButtonIndex;
                    MediaDownloaderService.cancelDownload();
                }
            }

            // Open folder button
            RippleButton {
                implicitWidth: 48
                implicitHeight: 48
                buttonRadius: Appearance.rounding.large
                colBackground: Appearance.colors.colSurfaceContainerHigh
                colBackgroundHover: Appearance.colors.colSurfaceContainerHighHover
                colRipple: Appearance.colors.colPrimary

                HoverHandler { cursorShape: Qt.PointingHandCursor }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "folder_open"
                    iconSize: 20
                    color: Appearance.colors.colOnSurfaceVariant
                }

                onClicked: {
                    Quickshell.execDetached(["xdg-open", Config.options.mediaDownloader.downloadPath])
                    GlobalStates.overviewOpen = false
                }

                StyledToolTip { text: "Open download folder" }
            }
        }

        // ── KEYBOARD HINTS ───────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: [
                    { key: "↑↓", desc: "Navigate" },
                    { key: "←→", desc: "Switch" },
                    { key: "Enter", desc: "Select" }
                ]

                delegate: RowLayout {
                    required property var modelData
                    spacing: 4

                    Rectangle {
                        implicitWidth: keyLbl.implicitWidth + 10
                        implicitHeight: 18
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colSurfaceContainerHighest

                        StyledText {
                            id: keyLbl
                            anchors.centerIn: parent
                            text: modelData.key
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    StyledText {
                        text: modelData.desc
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnSurfaceVariant
                        opacity: 0.6
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }
    }
}
