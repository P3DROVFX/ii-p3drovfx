pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/** Reviewed task creation preview with the complete destination DTO. */
Rectangle {
    id: root

    required property var messageData
    required property var card
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
                text: "add_task"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.m3colors.m3onSecondaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.rounding.unsharpenmore / 2

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Create this task?")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSecondaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: String(root.preview.title ?? "")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.m3colors.m3onSecondaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: [String(root.preview.provider?.name ?? root.preview.providerId ?? ""),
                        String(root.preview.accountId ?? ""),
                        String(root.preview.listName ?? root.preview.listId ?? "")]
                        .filter(value => value.length > 0).join(" · ")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSecondaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: String(root.preview.notes ?? "").length > 0
                    text: String(root.preview.notes ?? "")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSecondaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Due: %1").arg(String(root.preview.dueDateDisplay ?? Translation.tr("No due date")))
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
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
                onClicked: Ai.rejectTask(root.messageData)

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
                onClicked: Ai.approveTask(root.messageData)

                contentItem: StyledText {
                    text: Translation.tr("Create task")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }
}
