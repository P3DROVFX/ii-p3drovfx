import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.dock
import qs.services

/**
 * Dock → Magnification. The hero is a tray of the dock's own app buttons to run
 * the pointer over, magnified by the dock's own lens arithmetic with the values
 * below; the intensity stands on it in condensed digits. Options stay original.
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                topLeftRadius: Appearance.rounding.full
                topRightRadius: Appearance.rounding.full
                bottomLeftRadius: Appearance.rounding.full
                bottomRightRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Magnification")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        // ── Hero: the lens, to try ───────────────────────────────────────
        DockLensPreview {
            id: lens
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(220, Math.min(280, width / 3.4))

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 11
                height: tagRow.implicitHeight + 14
                width: tagRow.implicitWidth + 36
                radius: Math.min(height / 2, Appearance.rounding.large)
                color: Appearance.colors.colSurfaceContainerHigh

                Row {
                    id: tagRow
                    anchors.centerIn: parent
                    spacing: 12
                    // The one number this page is about, tall and condensed.
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Number(Config.options.dock.magnificationScale ?? 1.5).toFixed(2).replace(/\.?0+$/, "") + "×"
                        font.family: Appearance.font.family.main
                        font.variableAxes: ({ "wght": 760, "wdth": 40, "ROND": 100 })
                        font.pixelSize: 38
                        color: (Config.options.dock.enableMagnification ?? false) ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        StyledText {
                            text: (Config.options.dock.enableMagnification ?? false) ? Translation.tr("Magnification") : Translation.tr("Magnification · off")
                            font.family: Appearance.font.family.title
                            font.variableAxes: Appearance.font.variableAxes.titleRounded
                            font.pixelSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnSurface
                        }
                        StyledText {
                            text: Translation.tr("Run the pointer along the dock to try it")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }

        ContentSection {
            Layout.topMargin: 12
            title: Translation.tr("macOS Icon Magnification")
            icon: "zoom_in"

            ConfigSwitch {
                buttonIcon: "zoom_in"
                text: Translation.tr("Enable macOS icon magnification")
                checked: Config.options.dock.enableMagnification ?? false
                onCheckedChanged: {
                    Config.options.dock.enableMagnification = checked;
                }
            }

            ConfigSlider {
                enabled: Config.options.dock.enableMagnification ?? false
                Layout.fillWidth: true
                buttonIcon: "zoom_in"
                text: Translation.tr("Magnification intensity")
                value: Math.round((Config.options.dock.magnificationScale ?? 1.5) * 100)
                from: 120
                to: 220
                stepSize: 5
                onValueChanged: {
                    Config.options.dock.magnificationScale = value / 100.0;
                }
            }

            ConfigSlider {
                enabled: Config.options.dock.enableMagnification ?? false
                Layout.fillWidth: true
                buttonIcon: "radar"
                text: Translation.tr("Influence radius (icons)")
                value: Config.options.dock.magnificationInfluenceRadius ?? 2.35
                from: 1.2
                to: 4.0
                stepSize: 0.1
                usePercentTooltip: false
                tooltipContent: Number(value).toFixed(1)
                onValueChanged: {
                    Config.options.dock.magnificationInfluenceRadius = value;
                }
            }

            ContentSubsection {
                visible: Config.options.dock.enableMagnification ?? false
                title: Translation.tr("Magnification motion")
                icon: "animation"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.dock.magnificationMotion ?? "balanced"
                    onSelected: newValue => {
                        Config.options.dock.magnificationMotion = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Fast"), icon: "fast_forward", value: "fast" },
                        { displayName: Translation.tr("Balanced"), icon: "animation", value: "balanced" },
                        { displayName: Translation.tr("Smooth"), icon: "slow_motion_video", value: "smooth" }
                    ]
                }
            }

            ConfigSwitch {
                visible: Config.options.dock.enableMagnification ?? false
                buttonIcon: "open_in_full"
                text: Translation.tr("Dynamic icon spacing")
                checked: Config.options.dock.magnificationDynamicSpacing ?? true
                onCheckedChanged: {
                    Config.options.dock.magnificationDynamicSpacing = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Reserve local layout space as icons magnify so their visual gaps stay stable")
                }
            }
        }
    }
}
