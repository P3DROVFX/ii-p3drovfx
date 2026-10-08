import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.colors

/** The Dock style's own parts as chips, with the way into its full page. */
Rectangle {
    id: root

    readonly property var cfg: Config.options.bar.workspaces
    readonly property real padding: 20

    signal moreRequested()

    implicitHeight: column.implicitHeight + root.padding * 2
    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colSecondaryContainer

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.padding
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            MaterialShapeWrappedMaterialSymbol {
                text: "dock_to_left"
                iconSize: 20
                padding: 9
                fill: 1
                shape: MaterialShape.Shape.Square
                color: Appearance.colors.colOnSecondaryContainer
                colSymbol: Appearance.colors.colSecondaryContainer
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Dock Workspace Style")
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSecondaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("What each workspace button carries")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSecondaryContainer
                    opacity: 0.75
                }
            }
            RippleButton {
                implicitHeight: 36
                implicitWidth: moreRow.implicitWidth + 28
                buttonRadius: height / 2
                buttonRadiusPressed: Appearance.rounding.small
                colBackground: Appearance.colors.colOnSecondaryContainer
                colBackgroundHover: ColorUtils.mix(Appearance.colors.colOnSecondaryContainer, Appearance.colors.colSecondaryContainer, 0.88)
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.moreRequested()
                contentItem: Item {
                    RowLayout {
                        id: moreRow
                        anchors.centerIn: parent
                        spacing: 6
                        StyledText {
                            text: Translation.tr("More")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSecondaryContainer
                        }
                        MaterialSymbol {
                            text: "arrow_forward"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colSecondaryContainer
                        }
                    }
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8

            ColorsChip {
                symbol: "radio_button_checked"
                label: Translation.tr("Active indicator")
                chosen: root.cfg.dockShowActiveIndicator
                colContent: Appearance.colors.colOnSecondaryContainer
                colChosen: Appearance.colors.colPrimary
                colOnChosen: Appearance.colors.colOnPrimary
                onClicked: root.cfg.dockShowActiveIndicator = !root.cfg.dockShowActiveIndicator
            }
            ColorsChip {
                symbol: "more_horiz"
                label: Translation.tr("Window dots")
                chosen: root.cfg.dockShowWindowDots
                colContent: Appearance.colors.colOnSecondaryContainer
                colChosen: Appearance.colors.colPrimary
                colOnChosen: Appearance.colors.colOnPrimary
                onClicked: root.cfg.dockShowWindowDots = !root.cfg.dockShowWindowDots
            }
            ColorsChip {
                symbol: "apps"
                label: Translation.tr("App icons")
                chosen: root.cfg.dockShowAppIcons
                colContent: Appearance.colors.colOnSecondaryContainer
                colChosen: Appearance.colors.colPrimary
                colOnChosen: Appearance.colors.colOnPrimary
                onClicked: root.cfg.dockShowAppIcons = !root.cfg.dockShowAppIcons
            }
            ColorsChip {
                symbol: "ads_click"
                label: Translation.tr("Hover effect")
                chosen: root.cfg.dockHoverEffect
                colContent: Appearance.colors.colOnSecondaryContainer
                colChosen: Appearance.colors.colPrimary
                colOnChosen: Appearance.colors.colOnPrimary
                onClicked: root.cfg.dockHoverEffect = !root.cfg.dockHoverEffect
            }
        }
    }
}
