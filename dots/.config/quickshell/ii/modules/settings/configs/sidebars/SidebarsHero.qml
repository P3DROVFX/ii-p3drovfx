pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The page's subject without a mock-up: how many tabs the policies sidebar opens with, as
 * the one big number, and the button that opens that sidebar so the choices below can be
 * tried against the real thing. The placement sits beside it as a quiet pill.
 */
Rectangle {
    id: root

    readonly property real padding: 24
    readonly property real compactBreak: 560
    readonly property real digitsSize: 96
    readonly property real totalSize: 40
    readonly property real buttonHeight: 48
    readonly property real pillHeight: 32
    readonly property real columnGap: 20
    readonly property real digitGap: 6
    readonly property var axesDigitsBold: ({ "wght": 760, "wdth": 40, "ROND": 100 })
    readonly property var axesDigits: ({ "wght": 460, "wdth": 30, "ROND": 100 })

    property int visibleCount: 0
    property int total: 0
    property string placement: ""

    readonly property bool compact: root.width < root.compactBreak
    readonly property bool sidebarOpen: GlobalStates.sidebarLeftOpen

    implicitHeight: layout.implicitHeight + root.padding * 2
    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer1

    GridLayout {
        id: layout
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            margins: root.padding
        }
        columns: root.compact ? 1 : 2
        columnSpacing: root.columnGap
        rowSpacing: root.columnGap

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: Translation.tr("Policies sidebar")
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurfaceVariant
            }

            Item {
                implicitWidth: countText.implicitWidth + root.digitGap + totalText.implicitWidth
                implicitHeight: countText.implicitHeight

                StyledText {
                    id: countText
                    text: String(root.visibleCount)
                    font.family: Appearance.font.family.main
                    font.pixelSize: Math.round(root.digitsSize)
                    font.variableAxes: root.axesDigitsBold
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    id: totalText
                    anchors {
                        left: countText.right
                        leftMargin: root.digitGap
                        baseline: countText.baseline
                    }
                    text: "/" + root.total
                    font.family: Appearance.font.family.main
                    font.pixelSize: Math.round(root.totalSize)
                    font.variableAxes: root.axesDigits
                    color: Appearance.colors.colSubtext
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("tabs open with it")
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }
        }

        ColumnLayout {
            Layout.alignment: root.compact ? Qt.AlignLeft : Qt.AlignRight | Qt.AlignVCenter
            Layout.fillWidth: root.compact
            spacing: 12

            RippleButton {
                id: openButton
                Layout.fillWidth: root.compact
                implicitHeight: root.buttonHeight
                implicitWidth: openRow.implicitWidth + 40
                buttonRadius: height / 2
                buttonRadiusPressed: Appearance.rounding.small
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: GlobalStates.toggleLeftSidebar()

                contentItem: Item {
                    RowLayout {
                        id: openRow
                        anchors.centerIn: parent
                        spacing: 8

                        MaterialSymbol {
                            text: root.sidebarOpen ? "left_panel_close" : "left_panel_open"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            text: root.sidebarOpen ? Translation.tr("Close sidebar policies") : Translation.tr("Open sidebar policies")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }

            Rectangle {
                Layout.alignment: root.compact ? Qt.AlignLeft : Qt.AlignRight
                implicitHeight: root.pillHeight
                implicitWidth: pillRow.implicitWidth + 24
                radius: height / 2
                color: Appearance.colors.colSecondaryContainer

                RowLayout {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        text: "side_navigation"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledText {
                        text: root.placement
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
            }
        }
    }
}
