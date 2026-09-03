import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * How a floated window opens, and how big the handles that move it are.
 *
 * The main page keeps the two decisions — float or not, handles or not. Everything here is
 * a number that only matters once those are made.
 */
Item {
    id: root
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin

            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Windows")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("Where a floated window opens")
            icon: "open_with"

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "space_bar"
                text: Translation.tr("Sizes are a share of the screen minus whatever the bar and the dock have reserved, so a window never opens underneath either of them.")
            }

            ConfigSpinBox {
                icon: "width_normal"
                text: Translation.tr("Width (% of the usable area)")
                value: Config.options.tablet.windows.floatWidthPercent
                from: 20
                to: 100
                stepSize: 2
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.windows.floatWidthPercent)
                        Config.options.tablet.windows.floatWidthPercent = value;
                }
            }

            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Height (% of the usable area)")
                value: Config.options.tablet.windows.floatHeightPercent
                from: 20
                to: 100
                stepSize: 2
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.windows.floatHeightPercent)
                        Config.options.tablet.windows.floatHeightPercent = value;
                }
            }

            ConfigSwitch {
                buttonIcon: "stacks"
                text: Translation.tr("Cascade each new window")
                checked: Config.options.tablet.windows.cascade
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.windows.cascade)
                        Config.options.tablet.windows.cascade = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Steps each window down and to the right of the last. Without it a second window lands exactly on the first, which on a touchscreen is the difference between two windows and one that will not come to the front.")
                }
            }
        }

        ContentSection {
            title: Translation.tr("Touch handles")
            icon: "drag_pan"

            ConfigSwitch {
                buttonIcon: "drag_pan"
                text: Translation.tr("Show handles on the focused window")
                checked: Config.options.tablet.windows.touchControls
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.tablet.windows.touchControls)
                        Config.options.tablet.windows.touchControls = checked;
                }
            }

            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Title strip height (px)")
                visible: Config.options.tablet.windows.touchControls
                value: Config.options.tablet.windows.touchControlsHeight
                from: 32
                to: 72
                stepSize: 2
                onValueChanged: {
                    if (Config.ready && value !== Config.options.tablet.windows.touchControlsHeight)
                        Config.options.tablet.windows.touchControlsHeight = value;
                }
                StyledToolTip {
                    text: Translation.tr("Never smaller than the shell's minimum touch target, whatever this says — a handle you cannot hit is not a handle.")
                }
            }
        }
    }
}
