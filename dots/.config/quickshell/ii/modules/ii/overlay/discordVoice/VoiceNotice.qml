pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One join/leave toast from DiscordVoice.noticeModel. It grows in when created
 * and shrinks away once the service flags it `leaving`; the service removes the
 * row after its exit duration, so the delegate never has to outlive its model row.
 */
Item {
    id: root
    required property string kind
    required property string name
    required property string avatar
    required property bool leaving
    required property string context
    required property string text
    readonly property bool joined: kind === "join"
    readonly property bool isMessage: kind === "dm" || kind === "mention" || kind === "message"
    readonly property color fillColor: kind === "mention" ? Appearance.colors.colTertiaryContainer
        : (kind === "dm" ? Appearance.colors.colPrimaryContainer
        : (joined || kind === "message" ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2))
    readonly property color inkColor: kind === "mention" ? Appearance.colors.colOnTertiaryContainer
        : (kind === "dm" ? Appearance.colors.colOnPrimaryContainer
        : (joined || kind === "message" ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2))

    property real reveal: 0
    implicitHeight: row.implicitHeight * reveal
    clip: true
    opacity: reveal

    Component.onCompleted: reveal = Qt.binding(() => root.leaving ? 0 : 1)
    Behavior on reveal {
        NumberAnimation {
            duration: root.leaving ? DiscordVoice.noticeExitDuration : Appearance.animation.elementMoveFast.duration
            easing.type: root.leaving ? Easing.InCubic : Easing.OutCubic
        }
    }

    Rectangle {
        id: row
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        implicitHeight: content.implicitHeight + (root.isMessage && root.text !== "" ? 14 : 8)
        radius: root.isMessage && root.text !== "" ? Appearance.rounding.large : Appearance.rounding.full
        color: root.fillColor

        RowLayout {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 4
                rightMargin: 12
            }
            spacing: 8

            Item {
                implicitWidth: 28
                implicitHeight: 28
                Image {
                    id: avatarImage
                    anchors.fill: parent
                    source: root.avatar
                    sourceSize: Qt.size(56, 56)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: false
                }
                Rectangle {
                    id: avatarMask
                    anchors.fill: parent
                    radius: width / 2
                    visible: false
                }
                OpacityMask {
                    anchors.fill: parent
                    source: avatarImage
                    maskSource: avatarMask
                    visible: avatarImage.status === Image.Ready
                }
                MaterialShapeWrappedMaterialSymbol {
                    anchors.fill: parent
                    visible: avatarImage.status !== Image.Ready
                    shape: MaterialShape.Shape.Circle
                    implicitSize: 28
                    iconSize: 16
                    text: "person"
                    color: Appearance.colors.colLayer1
                    colSymbol: Appearance.colors.colOnLayer1
                }
            }

            MaterialSymbol {
                Layout.alignment: root.isMessage && root.text !== "" ? Qt.AlignTop : Qt.AlignVCenter
                Layout.topMargin: root.isMessage && root.text !== "" ? 1 : 0
                text: root.kind === "dm" ? "chat"
                    : (root.kind === "mention" ? "alternate_email"
                    : (root.kind === "message" ? "forum" : (root.joined ? "login" : "logout")))
                iconSize: Appearance.font.pixelSize.normal
                color: root.kind === "leave" ? Appearance.colors.colSubtext : root.inkColor
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    StyledText {
                        Layout.fillWidth: !root.isMessage || (root.context === "" && root.kind !== "dm")
                        // Only hug the name when the channel label shares the row.
                        Layout.maximumWidth: root.isMessage && root.context !== "" || root.kind === "dm"
                            ? implicitWidth : Number.POSITIVE_INFINITY
                        text: root.isMessage ? root.name
                            : (root.joined ? Translation.tr("%1 joined").arg(root.name) : Translation.tr("%1 left").arg(root.name))
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: root.isMessage ? Font.DemiBold : Font.Normal
                        color: root.inkColor
                        elide: Text.ElideRight
                    }
                    StyledText {
                        visible: root.isMessage && (root.context !== "" || root.kind === "dm")
                        Layout.fillWidth: true
                        text: root.context !== "" ? root.context : Translation.tr("Direct message")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.inkColor
                        opacity: 0.72
                        elide: Text.ElideRight
                    }
                }
                StyledText {
                    visible: root.isMessage && root.text !== ""
                    Layout.fillWidth: true
                    text: root.text
                    textFormat: Text.PlainText
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.inkColor
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }
    }
}
