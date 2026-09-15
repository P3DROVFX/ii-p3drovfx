pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import qs.modules.akebono.desktop.widgets

WidgetCard {
    id: root
    minSize: 170
    padding: 0

    readonly property var player: MprisController.activePlayer
    readonly property var track: MprisController.activeTrack
    readonly property string artUrl: root.track?.artUrl ?? ""
    readonly property bool hasArt: root.artUrl.length > 0 && cover.status === Image.Ready
    readonly property color foreground: root.hasArt ? "white" : Appearance.colors.colOnLayer1
    readonly property real progress: (root.player?.length ?? 0) > 0 ? (root.player.position / root.player.length) : 0
    readonly property int buttonSize: Math.max(28, Math.min(44, Math.round(root.width * 0.17)))
    readonly property bool controlsShown: cardHover.hovered && !root.editMode

    HoverHandler {
        id: cardHover
    }

    function seek(fraction: real): void {
        const length = root.player?.length ?? 0;
        if (length > 0)
            root.player.position = Math.max(0, Math.min(1, fraction)) * length;
    }

    Timer {
        running: root.player?.isPlaying ?? false
        interval: 500
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: !root.hasArt
        text: "music_note"
        iconSize: Math.round(Math.min(root.width, root.height) * 0.35)
        color: Appearance.colors.colSubtext
        opacity: 0.35
    }

    Item {
        id: artLayer
        anchors.fill: parent
        visible: root.hasArt
        layer.enabled: artLayer.visible
        layer.effect: OpacityMask {
            maskSource: Squircle {
                width: artLayer.width
                height: artLayer.height
                radius: root.cardRadius
                smoothing: AkebonoAppearance.squircleSmoothing
                color: "white"
            }
        }

        Image {
            id: cover
            anchors.fill: parent
            source: root.artUrl
            fillMode: Image.PreserveAspectCrop
            cache: false
            asynchronous: true
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.75) }
                GradientStop { position: 0.4; color: "transparent" }
                GradientStop { position: 0.6; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.8) }
            }
        }
    }

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 14
        spacing: 2

        StyledText {
            Layout.fillWidth: true
            text: root.track?.title ?? Translation.tr("Nothing playing")
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
            color: root.foreground
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.track?.artist ?? ""
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.foreground
            opacity: 0.75
            elide: Text.ElideRight
        }
    }

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 14
        spacing: 2

        Item {
            Layout.fillWidth: true
            implicitHeight: root.controlsShown ? controls.implicitHeight : 0
            opacity: root.controlsShown ? 1 : 0
            clip: true

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            RowLayout {
                id: controls
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                spacing: 2

                MediaControlButton {
                    icon: "skip_previous"
                    size: root.buttonSize
                    foreground: root.foreground
                    enabled: MprisController.canGoPrevious
                    onActivated: MprisController.previous()
                }
                MediaControlButton {
                    icon: (root.player?.isPlaying ?? false) ? "pause" : "play_arrow"
                    size: Math.round(root.buttonSize * 1.15)
                    foreground: root.foreground
                    enabled: MprisController.canTogglePlaying
                    onActivated: MprisController.togglePlaying()
                }
                MediaControlButton {
                    icon: "skip_next"
                    size: root.buttonSize
                    foreground: root.foreground
                    enabled: MprisController.canGoNext
                    onActivated: MprisController.next()
                }
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 14

            Rectangle {
                id: progressTrack
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 3
                radius: height / 2
                color: Qt.alpha(root.foreground, 0.25)

                Rectangle {
                    width: parent.width * root.progress
                    height: parent.height
                    radius: parent.radius
                    color: root.foreground
                }
            }

            MouseArea {
                id: seekArea
                anchors.fill: parent
                enabled: (root.player?.length ?? 0) > 0
                cursorShape: seekArea.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: mouse => root.seek(mouse.x / seekArea.width)
                onPositionChanged: mouse => {
                    if (seekArea.pressed)
                        root.seek(mouse.x / seekArea.width);
                }
            }
        }
    }
}
