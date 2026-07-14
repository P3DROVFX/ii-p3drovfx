import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models
import qs.modules.common.utils
import "./widgets"

Item {
    id: root

    property bool isVertical: false
    property var dockContent: null
    property int delegateIndex: -1

    readonly property real buttonSize: Appearance.sizes.dockButtonSize
    readonly property real dotMargin: (Config.options?.dock.height ?? 60) * 0.2
    readonly property real slotSize: buttonSize + dotMargin * 2
    readonly property real fixedSlots: isVertical ? 2.5 : 3
    readonly property real fixedLength: fixedSlots * slotSize

    implicitWidth: root.isVertical ? root.slotSize : root.fixedLength
    implicitHeight: root.isVertical ? root.slotSize : root.slotSize

    readonly property MprisPlayer currentPlayer: MprisController.activePlayer
    readonly property bool isPlaying: currentPlayer?.isPlaying ?? false
    readonly property string title: StringUtils.cleanMusicTitle(currentPlayer?.trackTitle) || Translation.tr("Unknown Title")
    readonly property string artist: currentPlayer?.trackArtist || Translation.tr("Unknown Artist")
    readonly property string artUrl: MprisController.artUrl || ""
    readonly property string identity: currentPlayer ? (currentPlayer.identity ?? "") : ""
    readonly property var activeTrackRef: MprisController.activeTrack

    property string displayTitle: ""
    property string displayArtist: ""
    property real titleOpacity: 1.0
    property real titleYOffset: 0.0

    property string currentArtUrl: ""
    property string previousArtUrl: ""
    property string pendingArtUrl: ""
    property bool awaitingImageLoad: false
    property bool artTransitioning: false
    property int artCacheBuster: 0
    property bool _initialized: false

    property real artOutgoingBlur: 0
    property real artOutgoingScale: 1.0
    property real artIncomingBlur: 0
    property real artIncomingScale: 1.0
    property real artVignetteBlur: root.isPlaying ? 50 : 90

    property bool isLocalArt: root.artUrl.startsWith("file://")
    property string artFileName: Qt.md5(root.artUrl)
    property string artFilePath: `${Directories.coverArt}/${root.artFileName}`
    property bool artDownloaded: false

    readonly property string localArtFilePath: {
        if (!root.artUrl || root.artUrl === "") return "";
        if (root.isLocalArt) return FileUtils.trimFileProtocol(root.artUrl);
        return root.artDownloaded ? root.artFilePath : "";
    }

    readonly property string resolvedArtPath: root.localArtFilePath !== "" ? Qt.resolvedUrl(root.localArtFilePath) : ""
    readonly property bool useDynamicColors: Config.options.media.dynamicAlbumColors && root.localArtFilePath !== ""

    ColorQuantizer {
        id: colorQuantizer
        source: root.resolvedArtPath
        depth: 0
        rescaleSize: 1
    }

    property color artDominantColor: ColorUtils.mix(
        (colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary),
        Appearance.colors.colPrimaryContainer, 0.8
    ) || Appearance.m3colors.m3secondaryContainer

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: root.artDominantColor
    }

    readonly property color artTextColor: root.useDynamicColors
        ? root.blendedColors.colOnPrimary
        : (root.currentArtUrl !== "" ? Appearance.colors.colOnSurfaceVariant : Appearance.colors.colOnSurface)
    readonly property color artSubtextColor: root.useDynamicColors
        ? root.blendedColors.colOnPrimary
        : Appearance.colors.colOnSurfaceVariant

    readonly property int elementHeight: Math.max(20, Math.min(42, root.height - 10))
    readonly property int barWidth: Math.max(4, Math.min(8, root.elementHeight / 5))
    property var visualizerPoints: []

    readonly property real bar0Val: visualizerPoints.length > 5 ? visualizerPoints[3] / 1000.0 : 0
    readonly property real bar1Val: visualizerPoints.length > 11 ? visualizerPoints[9] / 1000.0 : 0
    readonly property real bar2Val: visualizerPoints.length > 18 ? visualizerPoints[16] / 1000.0 : 0
    readonly property real bar3Val: visualizerPoints.length > 28 ? visualizerPoints[25] / 1000.0 : 0

    function getBarHeight(index) {
        let minH = root.barWidth;
        if (!root.isPlaying) return minH;
        let val = 0;
        if (index === 0) val = root.bar0Val;
        else if (index === 1) val = root.bar1Val;
        else if (index === 2) val = root.bar2Val;
        else if (index === 3) val = root.bar3Val;
        let norm = Math.min(1.0, Math.max(0.0, val * 2.0));
        let maxH = root.elementHeight - 10;
        return minH + norm * (maxH - minH);
    }

    function effectiveSource(url) {
        if (!url || url === "") return "";
        return url + "?v=" + root.artCacheBuster;
    }

    function snapToArt(newUrl) {
        root.previousArtUrl = "";
        root.currentArtUrl = newUrl;
        root.pendingArtUrl = "";
        root.awaitingImageLoad = false;
        root.artTransitioning = false;
        if (preloadFallbackTimer) preloadFallbackTimer.stop();
        root.artOutgoingBlur = 0;
        root.artOutgoingScale = 1.0;
        root.artIncomingBlur = 0;
        root.artIncomingScale = 1.0;
    }

    function requestArtChange(newUrl) {
        if (newUrl === root.currentArtUrl && root.artCacheBuster > 0 && !root.artTransitioning && !root.awaitingImageLoad && root.currentArtUrl !== "") {
            root.pendingArtUrl = newUrl;
            root.artCacheBuster++;
            root.awaitingImageLoad = true;
            if (preloadFallbackTimer) preloadFallbackTimer.restart();
            return;
        }
        if (newUrl === "" || root.currentArtUrl === "") {
            root.snapToArt(newUrl);
            return;
        }
        if (root.artTransitioning || root.awaitingImageLoad) {
            if (root.pendingArtUrl !== newUrl) root.pendingArtUrl = newUrl;
            return;
        }
        root.pendingArtUrl = newUrl;
        root.artCacheBuster++;
        root.awaitingImageLoad = true;
        if (preloadFallbackTimer) preloadFallbackTimer.restart();
    }

    function startOutgoingPhase() {
        if (root.pendingArtUrl === "") return;
        root.awaitingImageLoad = false;
        if (preloadFallbackTimer) preloadFallbackTimer.stop();
        root.previousArtUrl = root.currentArtUrl;
        root.currentArtUrl = root.pendingArtUrl;
        root.pendingArtUrl = "";
        root.artOutgoingBlur = 0;
        root.artOutgoingScale = 1.0;
        if (artOutgoingAnimation) artOutgoingAnimation.restart();
    }

    function imageLoadFailed() {
        if (!root.awaitingImageLoad) return;
        root.awaitingImageLoad = false;
        if (preloadFallbackTimer) preloadFallbackTimer.stop();
        root.snapToArt(root.pendingArtUrl);
    }

    Process {
        id: artDownloader
        property string targetFile: ""
        property string filePath: ""
        property string tempPath: ""
        command: ["bash", "-c", `[ -f '${filePath}' ] || (curl -4 -sSL '${targetFile}' -o '${tempPath}' && mv '${tempPath}' '${filePath}')`]
        onExited: { root.artDownloaded = true; }
    }

    onArtUrlChanged: {
        if (!root.artUrl || root.artUrl === "") {
            root.artDownloaded = false;
        } else if (root.isLocalArt) {
            root.artDownloaded = true;
        } else {
            artDownloader.targetFile = root.artUrl;
            artDownloader.filePath = root.artFilePath;
            artDownloader.tempPath = root.artFilePath + ".tmp";
            root.artDownloaded = false;
            artDownloader.running = true;
        }
        if (!root._initialized) return;
        if (root.artUrl === root.currentArtUrl && root.currentArtUrl !== "") return;
        root.requestArtChange(root.artUrl);
    }

    onActiveTrackRefChanged: {
        if (!root._initialized) return;
        if (root.activeTrackRef === null || root.activeTrackRef === undefined) return;
        root.requestArtChange(root.artUrl);
    }

    Connections {
        target: MprisController
        function onTrackChanged(reverse) {
            root.displayTitle = root.title;
            root.displayArtist = root.artist;
            if (!root._initialized) return;
            Qt.callLater(function() { root.requestArtChange(root.artUrl); });
        }
    }

    onTitleChanged: {
        if (root.displayTitle === "") {
            root.displayTitle = root.title;
            root.displayArtist = root.artist;
        } else if (songSwitchAnimation) {
            songSwitchAnimation.stop();
            songSwitchAnimation.start();
        }
    }

    onIdentityChanged: {
        if (root.displayTitle !== "" && songSwitchAnimation) {
            songSwitchAnimation.stop();
            songSwitchAnimation.start();
        }
    }

    Behavior on artVignetteBlur {
        NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
    }

    onIsPlayingChanged: {
        root.artVignetteBlur = root.isPlaying ? 50 : 90;
    }

    Image {
        id: artPreload
        source: root.awaitingImageLoad ? root.effectiveSource(root.pendingArtUrl) : ""
        visible: false
        asynchronous: true
        width: 16; height: 16
        smooth: false; mipmap: false
        onStatusChanged: {
            if (status === Image.Ready && root.awaitingImageLoad) root.startOutgoingPhase();
            else if (status === Image.Error && root.awaitingImageLoad) root.imageLoadFailed();
        }
    }

    Timer {
        id: preloadFallbackTimer
        interval: 200; repeat: false
        onTriggered: { if (root.awaitingImageLoad) root.startOutgoingPhase(); }
    }

    SequentialAnimation {
        id: artOutgoingAnimation
        onFinished: {
            root.previousArtUrl = "";
            root.artIncomingBlur = 30;
            root.artIncomingScale = 0.95;
            root.artTransitioning = true;
            artIncomingAnimation.restart();
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "artOutgoingBlur"; to: 30; duration: 300; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "artOutgoingScale"; to: 1.05; duration: 300; easing.type: Easing.OutQuad }
        }
    }

    SequentialAnimation {
        id: artIncomingAnimation
        onFinished: {
            root.artTransitioning = false;
            if (root.pendingArtUrl !== "" && root.pendingArtUrl !== root.currentArtUrl) {
                const next = root.pendingArtUrl;
                root.pendingArtUrl = "";
                root.requestArtChange(next);
            }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "artIncomingBlur"; to: 0; duration: 400; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "artIncomingScale"; to: 1.0; duration: 400; easing.type: Easing.OutExpo }
        }
    }

    SequentialAnimation {
        id: songSwitchAnimation
        ParallelAnimation {
            NumberAnimation { target: root; property: "titleOpacity"; to: 0.0; duration: 150; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "titleYOffset"; to: -24; duration: 150; easing.type: Easing.OutQuad }
        }
        PropertyAction { target: root; property: "displayTitle"; value: root.title }
        PropertyAction { target: root; property: "displayArtist"; value: root.artist }
        PropertyAction { target: root; property: "titleYOffset"; value: 24 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "titleOpacity"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "titleYOffset"; to: 0.0; duration: 220; easing.type: Easing.OutCubic }
        }
    }

    Process {
        id: cavaProc
        running: root.isPlaying
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                let points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
                root.visualizerPoints = points;
            }
        }
    }

    Component.onCompleted: {
        root.displayTitle = root.title;
        root.displayArtist = root.artist;
        if (root.artUrl !== "" && root.currentArtUrl === "") root.snapToArt(root.artUrl);
        root._initialized = true;
    }

    Item {
        id: contentRoot
        anchors.fill: parent
        anchors.margins: root.dotMargin

        Rectangle {
            id: maskRect
            anchors.fill: parent
            radius: Appearance.rounding.windowRounding
            visible: false
        }

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: maskRect
        }

        Item {
            id: vignetteMask
            anchors.fill: parent
            visible: true

            Rectangle {
                id: hMask
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.15; color: "transparent" }
                    GradientStop { position: 0.35; color: "white" }
                    GradientStop { position: 0.65; color: "white" }
                    GradientStop { position: 0.85; color: "transparent" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: "white" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: hMask
                }
            }
        }

        Item {
            anchors.fill: parent

            Item {
                anchors.fill: parent
                visible: root.previousArtUrl !== ""

                Image {
                    anchors.fill: parent
                    source: root.previousArtUrl !== "" ? root.effectiveSource(root.previousArtUrl) : ""
                    fillMode: Image.PreserveAspectCrop
                    smooth: true; asynchronous: true
                    layer.enabled: root.artVignetteBlur > 0
                    layer.effect: MultiEffect {
                        blurEnabled: root.artVignetteBlur > 0
                        blurMax: 128
                        blur: root.artVignetteBlur / 128
                    }
                }

                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: OpacityMask { maskSource: vignetteMask }

                    Image {
                        id: artOutgoing
                        anchors.centerIn: parent
                        width: parent.width * root.artOutgoingScale
                        height: parent.height * root.artOutgoingScale
                        source: root.previousArtUrl !== "" ? root.effectiveSource(root.previousArtUrl) : ""
                        fillMode: Image.PreserveAspectCrop
                        smooth: true; asynchronous: true
                        layer.enabled: root.artOutgoingBlur > 0
                        layer.effect: MultiEffect {
                            blurEnabled: root.artOutgoingBlur > 0
                            blurMax: 128
                            blur: root.artOutgoingBlur / 128
                        }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: root.currentArtUrl !== ""

                Image {
                    anchors.fill: parent
                    source: root.currentArtUrl !== "" ? root.effectiveSource(root.currentArtUrl) : ""
                    fillMode: Image.PreserveAspectCrop
                    smooth: true; asynchronous: true
                    layer.enabled: root.artVignetteBlur > 0
                    layer.effect: MultiEffect {
                        blurEnabled: root.artVignetteBlur > 0
                        blurMax: 128
                        blur: root.artVignetteBlur / 128
                    }
                }

                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: OpacityMask { maskSource: vignetteMask }

                    Image {
                        id: artIncoming
                        anchors.centerIn: parent
                        width: parent.width * root.artIncomingScale
                        height: parent.height * root.artIncomingScale
                        source: root.currentArtUrl !== "" ? root.effectiveSource(root.currentArtUrl) : ""
                        fillMode: Image.PreserveAspectCrop
                        smooth: true; asynchronous: true
                        layer.enabled: root.artIncomingBlur > 0
                        layer.effect: MultiEffect {
                            blurEnabled: root.artIncomingBlur > 0
                            blurMax: 128
                            blur: root.artIncomingBlur / 128
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: root.currentArtUrl === ""
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Appearance.colors.colSurfaceContainerHighest }
                GradientStop { position: 1.0; color: Appearance.colors.colSurfaceContainer }
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            visible: root.currentArtUrl === ""
            text: "music_note"
            iconSize: Appearance.font.pixelSize.large
            color: root.useDynamicColors ? root.blendedColors.colOnLayer0 : Appearance.colors.colOnSurfaceVariant
            opacity: 0.5
        }

        Item {
            anchors.fill: parent
            opacity: root.isPlaying ? 0.7 : 0.85
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutQuad } }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.0) }
                    GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.05) }
                    GradientStop { position: 0.8; color: Qt.rgba(0, 0, 0, 0.25) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.3)
                opacity: root.isPlaying ? 0.0 : 0.5
                Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
            }
        }

        Loader {
            active: !root.isVertical
            anchors.fill: parent
            sourceComponent: Item {
                anchors.fill: parent

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 1

                        StyledText {
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Black
                            font.styleName: "Rounded"
                            font.hintingPreference: Font.PreferNoHinting
                            color: root.artTextColor
                            text: root.displayTitle
                            maximumLineCount: 1
                            elide: Text.ElideRight
                            opacity: root.titleOpacity
                            transform: Translate { y: root.titleYOffset }
                            verticalAlignment: Text.AlignVCenter
                        }

                        StyledText {
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: root.artSubtextColor
                            text: root.displayArtist
                            maximumLineCount: 1
                            elide: Text.ElideRight
                            opacity: root.titleOpacity
                            transform: Translate { y: root.titleYOffset }
                        }
                    }

                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: root.barWidth * 4 + 2 * 3
                        implicitHeight: root.elementHeight

                        Row {
                            anchors.centerIn: parent
                            height: parent.height
                            spacing: 2

                            Repeater {
                                model: 4
                                Rectangle {
                                    required property int index
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.barWidth
                                    height: root.getBarHeight(index)
                                    radius: root.barWidth / 2
                                    color: root.artTextColor
                                    Behavior on height { NumberAnimation { duration: 85; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }
                }
            }
        }

        Loader {
            active: root.isVertical
            anchors.fill: parent
            sourceComponent: Item {
                anchors.fill: parent

                ColumnLayout {
                    anchors.fill: parent
                    anchors.topMargin: 6
                    anchors.bottomMargin: 6
                    spacing: 4

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.alignment: Qt.AlignHCenter

                        Row {
                            anchors.centerIn: parent
                            height: root.elementHeight
                            spacing: 2

                            Repeater {
                                model: 4
                                Rectangle {
                                    required property int index
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: root.barWidth
                                    height: root.getBarHeight(index)
                                    radius: root.barWidth / 2
                                    color: root.artTextColor
                                    Behavior on height { NumberAnimation { duration: 85; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Black
                        font.styleName: "Rounded"
                        font.hintingPreference: Font.PreferNoHinting
                        color: root.artTextColor
                        text: root.displayTitle
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        opacity: root.titleOpacity
                        transform: Translate { y: root.titleYOffset }
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: root.artSubtextColor
                        text: root.displayArtist
                        maximumLineCount: 1
                        elide: Text.ElideRight
                        opacity: root.titleOpacity
                        transform: Translate { y: root.titleYOffset }
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }

    MouseArea {
        id: dragOverlay
        anchors.fill: parent
        z: 10
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        property real pressCoord: 0
        property bool dragActive: false
        property bool mediaHovered: false

        onEntered: mediaHovered = true
        onExited: mediaHovered = false

        onPressed: (event) => {
            if (event.button === Qt.LeftButton) {
                pressCoord = root.isVertical ? event.y : event.x
            }
        }
        onPositionChanged: (event) => {
            if (!pressed) return
            var cur = root.isVertical ? event.y : event.x
            var dist = Math.abs(cur - pressCoord)
            if (!dragActive && dist > 5 && root.delegateIndex >= 0) {
                dragActive = true
                if (root.dockContent) root.dockContent.startItemDrag(root.delegateIndex, dragOverlay, event.x, event.y)
            }
            if (dragActive) {
                if (root.dockContent) root.dockContent.moveItemDrag(dragOverlay, event.x, event.y)
            }
        }
        onReleased: (event) => {
            if (dragActive) {
                dragActive = false
                if (root.dockContent) root.dockContent.endItemDrag()
                return
            }
            if (event.button === Qt.LeftButton || event.button === Qt.MiddleButton) {
                MprisController.togglePlaying()
            } else if (event.button === Qt.RightButton || event.button === Qt.ForwardButton) {
                MprisController.next()
            } else if (event.button === Qt.BackButton) {
                MprisController.previous()
            }
        }
        onCanceled: {
            if (dragActive) {
                dragActive = false
                if (root.dockContent) root.dockContent.cancelDrag()
            }
        }
    }

    DockTooltip {
        id: mediaTooltip
        parentItem: root
        text: root.displayTitle + " - " + root.displayArtist
        showTooltip: dragOverlay.mediaHovered
        tooltipOffset: -root.dotMargin * 0.5
    }
}
