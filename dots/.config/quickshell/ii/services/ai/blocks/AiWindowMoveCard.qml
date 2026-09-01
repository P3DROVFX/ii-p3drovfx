import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/** Shows a one-line window movement preview before dispatching it. */
Rectangle {
    id: root

    property var messageData: null
    property var card: null
    readonly property var preview: root.card?.data?.preview ?? ({})

    implicitHeight: content.implicitHeight + Appearance.rounding.normal
    radius: Appearance.rounding.normal
    color: Appearance.colors.colSecondaryContainer

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Appearance.rounding.unsharpenmore
        spacing: Appearance.rounding.unsharpenmore

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.rounding.unsharpenmore

            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: "move_down"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.m3colors.m3onSecondaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Move this window?")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSecondaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: String(root.preview.summary ?? "")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.rounding.unsharpenmore

            Item { Layout.fillWidth: true }

            RippleButton {
                leftPadding: Appearance.rounding.small
                rightPadding: Appearance.rounding.small
                topPadding: Appearance.rounding.unsharpenmore / 2
                bottomPadding: Appearance.rounding.unsharpenmore / 2
                buttonRadius: Appearance.rounding.full
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: Ai.rejectWindowMove(root.messageData)
                contentItem: StyledText {
                    text: Translation.tr("Discard")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }

            RippleButton {
                leftPadding: Appearance.rounding.small
                rightPadding: Appearance.rounding.small
                topPadding: Appearance.rounding.unsharpenmore / 2
                bottomPadding: Appearance.rounding.unsharpenmore / 2
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: Ai.approveWindowMove(root.messageData)
                contentItem: StyledText {
                    text: Translation.tr("Move")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onPrimary
                }
            }
        }
    }
}
