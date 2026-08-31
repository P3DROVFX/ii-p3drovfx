pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property var engine: null
    signal restart()
    signal repeat()

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width, 640)
        spacing: Appearance.sizes.elevationMargin

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.sizes.elevationMargin * 2

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: qsTr("wpm")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    text: Math.round(root.engine?.wpm ?? 0)
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.hugeass
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colPrimary
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 0
                StyledText {
                    text: qsTr("accuracy")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                    visible: root.engine?.mode !== "zen"
                }
                StyledText {
                    text: root.engine?.mode === "zen" ? "—" : Math.round(root.engine?.accuracy ?? 0) + "%"
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.sizes.elevationMargin
            StyledText {
                text: qsTr("raw %1").arg(String(Math.round(root.engine?.rawWpm ?? 0)))
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                text: qsTr("time %1s").arg(String(Math.round(root.engine?.elapsedSeconds ?? 0)))
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                visible: root.engine?.mode !== "zen"
                text: qsTr("chars %1/%2/%3/%4")
                    .arg(String(root.engine?.characterBreakdown?.correct ?? 0))
                    .arg(String(root.engine?.characterBreakdown?.incorrect ?? 0))
                    .arg(String(root.engine?.characterBreakdown?.extra ?? 0))
                    .arg(String(root.engine?.characterBreakdown?.missed ?? 0))
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
            }
            Item { Layout.fillWidth: true }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Appearance.sizes.elevationMargin

            RippleButton {
                implicitWidth: restartContent.implicitWidth + Appearance.sizes.elevationMargin * 2
                implicitHeight: Appearance.sizes.elevationMargin * 3
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                onClicked: root.restart()
                RowLayout {
                    id: restartContent
                    anchors.centerIn: parent
                    spacing: Appearance.sizes.elevationMargin / 3
                    MaterialSymbol { text: "restart_alt"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnPrimaryContainer }
                    StyledText { text: qsTr("Restart"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnPrimaryContainer }
                }
            }

            RippleButton {
                implicitWidth: repeatContent.implicitWidth + Appearance.sizes.elevationMargin * 2
                implicitHeight: Appearance.sizes.elevationMargin * 3
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSurfaceContainerHigh
                colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                colRipple: Appearance.colors.colSurfaceContainerHighestActive
                onClicked: root.repeat()
                RowLayout {
                    id: repeatContent
                    anchors.centerIn: parent
                    spacing: Appearance.sizes.elevationMargin / 3
                    MaterialSymbol { text: "replay"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnSurface }
                    StyledText { text: qsTr("Repeat"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnSurface }
                }
            }
        }
    }
}
