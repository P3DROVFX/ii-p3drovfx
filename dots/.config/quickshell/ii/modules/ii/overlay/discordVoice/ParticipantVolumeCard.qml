pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Your local volume for one participant, on Discord's own scale: 0-200 %,
 * 100 % = as they send it. Muting here only silences them for you.
 */
Rectangle {
    id: root
    property var participant: null
    readonly property string userId: String(participant?.id ?? "")
    readonly property real volume: participant?.volume ?? 100
    readonly property bool localMuted: participant?.localMute === true
    readonly property bool sliderPressed: slider.pressed
    signal closeRequested()

    implicitHeight: column.implicitHeight + 16
    radius: Appearance.rounding.large
    color: Appearance.colors.colLayer2

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 12
            rightMargin: 6
        }
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            StyledText {
                Layout.fillWidth: true
                text: root.participant?.nick || root.participant?.username || ""
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
                elide: Text.ElideRight
            }
            StyledText {
                text: root.localMuted ? Translation.tr("Muted for you") : `${Math.round(root.volume)}%`
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: root.closeRequested()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
                StyledToolTip { text: Translation.tr("Close") }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            RippleButton {
                implicitWidth: 36
                implicitHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: DiscordVoice.setUserLocalMute(root.userId, !root.localMuted)
                contentItem: MaterialShapeWrappedMaterialSymbol {
                    anchors.centerIn: parent
                    text: root.localMuted ? "volume_off" : "volume_up"
                    shape: root.localMuted ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Cookie4Sided
                    implicitSize: 34
                    iconSize: 18
                    fill: root.localMuted ? 1 : 0
                    color: root.localMuted ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
                    colSymbol: root.localMuted ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                }
                StyledToolTip { text: root.localMuted ? Translation.tr("Unmute for you") : Translation.tr("Mute for you") }
            }

            StyledSlider {
                id: slider
                Layout.fillWidth: true
                enabled: !root.localMuted
                opacity: enabled ? 1 : 0.5
                from: 0
                to: 200
                stepSize: 1
                stopIndicatorValues: [100, 200]
                usePercentTooltip: false
                tooltipContent: `${Math.round(value)}%`
                configuration: StyledSlider.Configuration.S
                value: root.volume
                onMoved: DiscordVoice.setUserVolume(root.userId, value)
            }

            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                enabled: Math.round(root.volume) !== 100
                opacity: enabled ? 1 : 0.4
                onClicked: DiscordVoice.setUserVolume(root.userId, 100)
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "restart_alt"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
                StyledToolTip { text: Translation.tr("Reset to 100%") }
            }
        }
    }
}
