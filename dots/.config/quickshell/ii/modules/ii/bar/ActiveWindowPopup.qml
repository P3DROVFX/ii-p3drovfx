import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

StyledPopup {
    id: popupRoot
    property Item targetItem
    property string appClassText
    property string appTitleText
    property string activeWindowAddress
    property var monitor
    property int popupWidth: 350
    property int maxPopupWidth: 600

    hoverTarget: targetItem
    stickyHover: true
    active: (stickyHover ? _stickyActive : (hoverTarget && hoverTarget.containsMouse)) && appTitleText !== ""

    Rectangle {
        implicitWidth: Math.max(popupRoot.popupWidth, Math.min(popupRoot.maxPopupWidth, popupText.implicitWidth + 32))
        implicitHeight: contentCol.implicitHeight + 32
        radius: Appearance.rounding.normal
        color: Appearance.colors.colSurfaceContainerHigh

        ColumnLayout {
            id: contentCol
            anchors {
                fill: parent
                margins: 16
            }
            spacing: 12

            RowLayout {
                spacing: 8

                Rectangle {
                    color: Appearance.colors.colPrimaryContainer
                    radius: Appearance.rounding.verysmall
                    implicitWidth: appNameText.implicitWidth + 16
                    implicitHeight: appNameText.implicitHeight + 8

                    StyledText {
                        id: appNameText
                        anchors.centerIn: parent
                        text: popupRoot.appClassText
                        font.weight: Font.Bold
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                Item { Layout.fillWidth: true }


                StyledText {
                    text: popupRoot.activeWindowAddress
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.numbers
                    color: Appearance.colors.colSubtext
                    visible: popupRoot.activeWindowAddress !== "0xundefined"
                }
            }

            StyledText {
                id: popupText
                Layout.fillWidth: true
                text: popupRoot.appTitleText
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnSurface
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Appearance.colors.colLayer0Border
            }

            RowLayout {
                spacing: 6

                MaterialSymbol {
                    text: "computer"
                    iconSize: 14
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    text: popupRoot.monitor?.name ?? "Unknown"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    text: "•"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                MaterialSymbol {
                    text: "grid_view"
                    iconSize: 14
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    text: `${Translation.tr("Workspace")} ${popupRoot.monitor?.activeWorkspace?.id ?? 1}`
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
