pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

StyledPopup {
    id: root
    contentPadding: Appearance.spacing.space200

    function beginAuthorization() {
        root.pinnedOpen = false;
        DiscordVoice.authorizeAfterFocusRelease();
    }

    onActiveChanged: if (active) {
        panel.opacity = 0;
        panel.scale = 0.94;
        enter.restart();
    }

    ColumnLayout {
        id: panel
        implicitWidth: 384
        spacing: Appearance.spacing.space200
        transformOrigin: Item.Top

        ParallelAnimation {
            id: enter
            NumberAnimation { target: panel; property: "opacity"; to: 1; duration: Appearance.animation.elementMoveEnter.duration; easing.type: Easing.OutCubic }
            NumberAnimation { target: panel; property: "scale"; to: 1; duration: Appearance.animation.elementMoveEnter.duration; easing.type: Easing.OutBack }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100
            DiscordGlyph {
                shape: MaterialShape.Shape.Cookie7Sided
                implicitSize: 44
                iconSize: 23
                color: Appearance.colors.colPrimaryContainer
                iconColor: Appearance.colors.colOnPrimaryContainer
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: DiscordVoice.channel?.name || "Discord Voice"
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    readonly property string backendSuffix:
                        DiscordVoice.backendLabel ? ` · ${DiscordVoice.backendLabel}` : ""
                    text: DiscordVoice.inVoice
                        ? `${DiscordVoice.participantCount} connected${backendSuffix}`
                        : (DiscordVoice.errorMessage || `Not connected to voice${backendSuffix}`)
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }
            RippleButton {
                implicitWidth: 36; implicitHeight: 36
                buttonRadius: Appearance.rounding.full
                onClicked: root.pinnedOpen = false
                MaterialSymbol { anchors.centerIn: parent; text: "close"; color: Appearance.colors.colOnLayer1 }
            }
        }

        Flow {
            visible: DiscordVoice.participantCount > 0
            Layout.fillWidth: true
            spacing: Appearance.spacing.space150
            Repeater {
                model: DiscordVoice.participantModel
                ParticipantAvatar { avatarSize: 52; showName: true; maxNameWidth: 64 }
            }
        }

        Rectangle {
            visible: DiscordVoice.participantCount === 0
            Layout.fillWidth: true
            implicitHeight: 92
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer2
            Column {
                anchors.centerIn: parent
                spacing: Appearance.spacing.space25
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: DiscordVoice.status === "auth_required" ? "Discord authorization required" : "Join a Discord voice channel"
                    color: Appearance.colors.colOnLayer2
                    font.weight: Font.DemiBold
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: DiscordVoice.status === "unavailable" ? "Start Discord, then reconnect" : "Participants will appear here"
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Appearance.spacing.space50
            spacing: Appearance.spacing.space150
            Item { visible: DiscordVoice.inVoice; Layout.fillWidth: true }
            RippleButton {
                visible: DiscordVoice.status === "auth_required" || DiscordVoice.status === "authorizing"
                enabled: DiscordVoice.status !== "authorizing"
                Layout.fillWidth: true
                implicitHeight: 44
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                onClicked: root.beginAuthorization()
                StyledText {
                    anchors.centerIn: parent
                    text: DiscordVoice.status === "authorizing" ? "Waiting for Discord…" : "Authorize Discord"
                    color: Appearance.colors.colOnPrimary
                    font.weight: Font.DemiBold
                }
            }
            RippleButton {
                visible: DiscordVoice.status !== "auth_required" && !DiscordVoice.inVoice
                Layout.fillWidth: true
                implicitHeight: 44
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                onClicked: DiscordVoice.connect()
                StyledText { anchors.centerIn: parent; text: "Reconnect"; color: Appearance.colors.colOnSecondaryContainer; font.weight: Font.DemiBold }
            }
            RippleButton {
                visible: DiscordVoice.inVoice
                implicitWidth: 64
                implicitHeight: 64
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                onClicked: DiscordVoice.setMuted(!DiscordVoice.muted)
                contentItem: MaterialShapeWrappedMaterialSymbol {
                        text: DiscordVoice.muted ? "mic_off" : "mic"
                        shape: DiscordVoice.muted ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Cookie4Sided
                        implicitSize: 56
                        iconSize: 24
                        fill: DiscordVoice.muted ? 1 : 0
                        color: DiscordVoice.muted ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
                        colSymbol: DiscordVoice.muted ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                }
                StyledToolTip { text: DiscordVoice.muted ? "Unmute" : "Mute" }
            }
            RippleButton {
                visible: DiscordVoice.inVoice
                implicitWidth: 64
                implicitHeight: 64
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                onClicked: DiscordVoice.setDeafened(!DiscordVoice.deafened)
                contentItem: MaterialShapeWrappedMaterialSymbol {
                        text: DiscordVoice.deafened ? "headset_off" : "headphones"
                        shape: DiscordVoice.deafened ? MaterialShape.Shape.Boom : MaterialShape.Shape.Clover4Leaf
                        implicitSize: 56
                        iconSize: 24
                        fill: DiscordVoice.deafened ? 1 : 0
                        color: DiscordVoice.deafened ? Appearance.colors.colErrorContainer : Appearance.colors.colTertiaryContainer
                        colSymbol: DiscordVoice.deafened ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnTertiaryContainer
                }
                StyledToolTip { text: DiscordVoice.deafened ? "Undeafen" : "Deafen" }
            }
            Item { visible: DiscordVoice.inVoice; Layout.fillWidth: true }
        }
    }
}
