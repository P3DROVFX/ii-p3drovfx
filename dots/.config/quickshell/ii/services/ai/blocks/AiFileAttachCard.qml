import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/** One file, asking to be read into the turn. */
Rectangle {
    id: root

    property var messageData: null
    property var card: null
    readonly property string path: String(root.card?.data?.path ?? "")
    readonly property string name: String(root.card?.data?.name ?? root.path)

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
                text: "attach_file"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.m3colors.m3onSecondaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Read this file into the conversation?")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSecondaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.name
                    elide: Text.ElideMiddle
                    wrapMode: Text.NoWrap
                    font.family: Appearance.font.family.monospace
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
                onClicked: Ai.rejectFileAttach(root.messageData)

                contentItem: StyledText {
                    text: Translation.tr("Don't read")
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
                onClicked: Ai.approveFileAttach(root.messageData)

                contentItem: StyledText {
                    text: Translation.tr("Read it")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }
}
