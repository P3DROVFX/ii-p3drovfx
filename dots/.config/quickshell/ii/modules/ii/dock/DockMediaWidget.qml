import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.utils
import qs.modules.common.functions
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

    readonly property real controlSize: Math.round(buttonSize * 0.68)

    readonly property int textSizeL: Math.round(buttonSize * (isVertical ? 0.24 : 0.26))
    readonly property int textSizeS: Math.round(buttonSize * (isVertical ? 0.20 : 0.22))
    readonly property int marqueeRunningThreshold: isVertical ? 10 : 14

    implicitWidth: root.isVertical ? root.slotSize : root.fixedLength
    implicitHeight: root.isVertical ? root.slotSize : root.slotSize

    readonly property MprisPlayer currentPlayer: MprisController.activePlayer
    readonly property bool isPlaying: currentPlayer?.isPlaying ?? false

    readonly property string finalTitle: StringUtils.cleanMusicTitle(currentPlayer?.trackTitle) || Translation.tr("Unknown Title")
    readonly property string finalArtist: currentPlayer?.trackArtist || Translation.tr("Unknown Artist")
    readonly property string finalArtUrl: MprisController.artUrl || ""
    readonly property bool isLocalArt: finalArtUrl.startsWith("file://")

    readonly property string localFilePath: {
        if (!finalArtUrl) return "";
        if (isLocalArt) return finalArtUrl.replace("file://", "");
        return `${Directories.coverArt}/${Qt.md5(finalArtUrl)}`;
    }

    property bool downloaded: false
    readonly property string displayedArtFilePath: {
        if (!finalArtUrl) return "";
        if (isLocalArt) return finalArtUrl;
        return downloaded ? `file://${localFilePath}` : "";
    }

    Process {
        id: coverDownloader
        property string targetFile: root.finalArtUrl
        property string localFilePath: root.localFilePath
        property string tempFilePath: root.localFilePath + ".tmp"
        command: ["bash", "-c", `[ -f '${localFilePath}' ] || (curl -4 -sSL '${targetFile}' -o '${tempFilePath}' && mv '${tempFilePath}' '${localFilePath}')`]
        onExited: (exitCode, exitStatus) => {
            root.downloaded = true;
        }
    }

    onFinalArtUrlChanged: {
        if (!root.finalArtUrl || root.finalArtUrl.length === 0) {
            root.downloaded = false;
            return;
        }
        if (root.isLocalArt) {
            root.downloaded = true;
            return;
        }
        // Binding does not work in Process - must start explicitly
        coverDownloader.targetFile = root.finalArtUrl;
        coverDownloader.localFilePath = root.localFilePath;
        coverDownloader.tempFilePath = root.localFilePath + ".tmp";
        root.downloaded = false;
        coverDownloader.running = true;
    }

    Component.onCompleted: {
        // Handle initial state when widget is created with music already playing
        if (root.finalArtUrl && root.finalArtUrl.length > 0 && !root.isLocalArt) {
            Qt.callLater(() => {
                coverDownloader.targetFile = root.finalArtUrl;
                coverDownloader.localFilePath = root.localFilePath;
                coverDownloader.tempFilePath = root.localFilePath + ".tmp";
                coverDownloader.running = true;
            });
        }
    }

    property bool mediaHovered: false

    Rectangle {
        id: bgRect
        anchors.fill: parent
        anchors.margins: root.dotMargin
        color: Appearance.colors.colSurfaceContainerHighest
        radius: Appearance.rounding.normal
        clip: true

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: bgRect.width
                height: bgRect.height
                radius: bgRect.radius
            }
        }

        StyledImage {
            id: blurredBg
            anchors.fill: parent
            source: root.displayedArtFilePath
            fillMode: Image.PreserveAspectCrop
            cache: false
            asynchronous: true
            opacity: 0.8
            visible: root.displayedArtFilePath !== ""

            layer.enabled: true
            layer.effect: StyledBlurEffect {
                source: blurredBg
                blurMax: 32
            }

            Rectangle {
                anchors.fill: parent
                color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.6)
            }
        }

        Loader {
            active: !root.isVertical
            anchors.fill: parent
            sourceComponent: Item {
                anchors.fill: parent

                RowLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: root.dotMargin + 6
                    anchors.rightMargin: root.dotMargin + 6
                    spacing: 12

                    Item {
                        implicitWidth: root.buttonSize * 0.65
                        implicitHeight: root.buttonSize * 0.65
                        Layout.alignment: Qt.AlignVCenter
                        
                        RippleButton {
                            id: playButton
                            anchors.centerIn: parent
                            implicitWidth: parent.implicitWidth
                            implicitHeight: parent.implicitHeight
                            z: 100 // High z-index
                            buttonRadius: root.isPlaying ? Appearance.rounding.small : implicitWidth / 2
                            colBackground: Appearance.colors.colPrimary
                            colRipple: Appearance.colors.colPrimaryActive
                            pointingHandCursor: true
                            onClicked: MprisController.togglePlaying()
                            contentItem: MaterialSymbol {
                                text: root.isPlaying ? "pause" : "play_arrow"
                                color: Appearance.colors.colOnPrimary
                                fill: 1
                                iconSize: parent.height * 0.55
                                horizontalAlignment: Text.AlignHCenter
                            }
                            
                            Behavior on buttonRadius { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2

                        MarqueeText {
                            Layout.fillWidth: true
                            text: root.finalTitle
                            fontSize: root.textSizeL
                            fontWeight: Font.DemiBold
                            textColor: root.displayedArtFilePath !== "" ? "white" : Appearance.colors.colOnLayer0
                            running: root.mediaHovered && text.length > root.marqueeRunningThreshold
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.finalArtist
                            font.pixelSize: root.textSizeS
                            color: root.displayedArtFilePath !== "" ? "#b3ffffff" : Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        Loader {
            active: root.isVertical
            anchors.fill: parent
            z: 50 // On top of mediaMouseArea
            sourceComponent: Item {
                anchors.fill: parent

                RippleButton {
                    anchors.centerIn: parent
                    implicitWidth: root.buttonSize * 0.65
                    implicitHeight: root.buttonSize * 0.65
                    buttonRadius: root.isPlaying ? Appearance.rounding.small : implicitWidth / 2
                    colBackground: Appearance.colors.colPrimary
                    colRipple: Appearance.colors.colPrimaryActive
                    pointingHandCursor: true
                    contentItem: MaterialSymbol {
                        text: root.isPlaying ? "pause" : "play_arrow"
                        color: Appearance.colors.colOnPrimary
                        fill: 1
                        iconSize: parent.height * 0.55
                        horizontalAlignment: Text.AlignHCenter
                    }
                    onClicked: MprisController.togglePlaying()

                    Behavior on buttonRadius { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
            }
        }
    }

    // ── Drag overlay (reorder support + click forwarding) ─────────────────
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

        onEntered: root.mediaHovered = true
        onExited: root.mediaHovered = false

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
                if (root.dockContent) {
                    root.dockContent.startItemDrag(root.delegateIndex, dragOverlay, event.x, event.y)
                }
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
            // Forward click to media actions
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
        text: root.finalTitle + " - " + root.finalArtist
        showTooltip: root.mediaHovered
        tooltipOffset: -root.dotMargin * 0.5
    }
}