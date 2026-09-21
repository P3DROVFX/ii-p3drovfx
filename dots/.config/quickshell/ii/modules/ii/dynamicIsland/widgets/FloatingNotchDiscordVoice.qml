pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A Discord voice call.
 *
 * Contracted, it is only ever on screen for the join (see DiscordVoiceSource): the
 * channel's name and how many are in it. The rest of the call is a glance beside the
 * clock or in a bubble, drawn by the resting face and AuxiliaryBubbleContent; this file's
 * expanded face is that bubble's card - who is in the call, and Mute and Deafen.
 *
 * Only loaded while a call is on, which is also the only time DiscordVoice is running.
 */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property color discordColor: "#5865F2"
    readonly property var channel: DiscordVoice.channel
    readonly property var participants: DiscordVoice.participants ?? []
    readonly property int maxRows: 5
    readonly property var shownRows: root.participants.slice(0, root.maxRows)
    readonly property int hiddenCount: Math.max(0, root.participants.length - root.maxRows)
    readonly property real rowHeight: 32
    readonly property real preferredExpandedHeight: 14 + 30 + 6 + root.shownRows.length * root.rowHeight
        + (root.hiddenCount > 0 ? 20 : 0) + 10 + 40 + 14

    function countText(count) {
        return count === 1 ? Translation.tr("1 in call") : Translation.tr("%1 in call").arg(count);
    }

    // ── Contracted: the join ─────────────────────────────────────────────────
    RowLayout {
        visible: !root.isExpanded
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 16
        spacing: 10

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Math.max(22, Math.min(30, root.height - 10))
            implicitHeight: implicitWidth
            radius: width / 2
            color: root.discordColor

            MaterialSymbol {
                anchors.centerIn: parent
                text: "headset_mic"
                fill: 1
                iconSize: Math.round(parent.width * 0.58)
                color: "#FFFFFF"
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: Translation.tr("%1 · %2").arg(root.channel?.name ?? Translation.tr("Voice channel"))
                .arg(root.countText(root.participants.length))
            elide: Text.ElideRight
            maximumLineCount: 1
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── Expanded, in the bubble's card: who is here ──────────────────────────
    // One mask for every avatar in the list: they are all the same circle.
    Rectangle {
        id: avatarMask
        width: 24
        height: 24
        radius: 12
        visible: false
        layer.enabled: root.isExpanded
    }

    ColumnLayout {
        visible: root.isExpanded
        anchors.fill: parent
        anchors.margins: 14
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            spacing: 8

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: "headset_mic"
                fill: 1
                iconSize: 20
                color: root.discordColor
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.channel?.name ?? Translation.tr("Voice channel")
                elide: Text.ElideRight
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer0
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: root.countText(root.participants.length)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        Item {
            Layout.preferredHeight: 6
        }

        Repeater {
            model: root.shownRows

            RowLayout {
                id: row
                required property var modelData
                readonly property bool speaking: row.modelData?.speaking === true
                Layout.fillWidth: true
                Layout.preferredHeight: root.rowHeight
                spacing: 10

                // The avatar, in a ring that lights while they talk.
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: 14
                    color: "transparent"
                    border.width: 2
                    border.color: row.speaking ? Appearance.colors.colPrimary : "transparent"

                    Rectangle {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        radius: 12
                        color: Appearance.colors.colLayer2
                        visible: avatarImage.status !== Image.Ready

                        StyledText {
                            anchors.centerIn: parent
                            text: String(row.modelData?.nick ?? "?").charAt(0).toUpperCase()
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnLayer2
                        }
                    }

                    Image {
                        id: avatarImage
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        source: DiscordVoice.avatarUrl(row.modelData, 64)
                        sourceSize: Qt.size(48, 48)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: false
                    }

                    MultiEffect {
                        anchors.fill: avatarImage
                        source: avatarImage
                        visible: avatarImage.status === Image.Ready
                        maskEnabled: true
                        maskSource: avatarMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: String(row.modelData?.nick ?? "")
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: row.speaking ? Font.Bold : Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    visible: row.modelData?.deaf === true || row.modelData?.mute === true
                    text: row.modelData?.deaf === true ? "headset_off" : "mic_off"
                    iconSize: 16
                    color: Appearance.colors.colError
                }
            }
        }

        StyledText {
            visible: root.hiddenCount > 0
            Layout.preferredHeight: 20
            text: Translation.tr("+%1 more").arg(root.hiddenCount)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        Item {
            Layout.fillHeight: true
            Layout.minimumHeight: 10
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            CallToggle {
                Layout.fillWidth: true
                glyph: DiscordVoice.muted ? "mic_off" : "mic"
                label: DiscordVoice.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
                engaged: DiscordVoice.muted
                onClicked: DiscordVoice.setMuted(!DiscordVoice.muted)
            }

            CallToggle {
                Layout.fillWidth: true
                glyph: DiscordVoice.deafened ? "headset_off" : "headphones"
                label: DiscordVoice.deafened ? Translation.tr("Undeafen") : Translation.tr("Deafen")
                engaged: DiscordVoice.deafened
                onClicked: DiscordVoice.setDeafened(!DiscordVoice.deafened)
            }
        }
    }

    /** A pill that turns red while its thing is switched off, like Discord's own. */
    component CallToggle: RippleButton {
        id: toggle
        property string glyph: ""
        property string label: ""
        property bool engaged: false
        readonly property color foreground: toggle.engaged ? Appearance.colors.colOnErrorContainer
            : Appearance.colors.colOnLayer2

        implicitHeight: 40
        buttonRadius: Appearance.rounding.full
        colBackground: toggle.engaged ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer2
        colBackgroundHover: toggle.engaged ? Appearance.colors.colErrorContainerHover
            : Appearance.colors.colLayer2Hover
        colRipple: toggle.engaged ? Appearance.colors.colErrorContainerActive : Appearance.colors.colLayer2Active

        contentItem: Item {
            implicitWidth: toggleRow.implicitWidth
            implicitHeight: toggleRow.implicitHeight

            Row {
                id: toggleRow
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: toggle.glyph
                    fill: 1
                    iconSize: 18
                    color: toggle.foreground
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: toggle.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: toggle.foreground
                }
            }
        }
    }
}
