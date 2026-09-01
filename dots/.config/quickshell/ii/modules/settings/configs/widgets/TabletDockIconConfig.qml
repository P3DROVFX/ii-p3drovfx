import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The tablet consumes the same DockIcon as ii, so these appearance choices intentionally use
 * the shared dock keys. A favourite keeps its adaptive shape while the user changes families.
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
                text: Translation.tr("Tablet app icons")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("Adaptive app icons")
            icon: "interests"

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "devices"
                text: Translation.tr("These options are shared with the desktop dock so your favourite apps keep one consistent Material treatment.")
            }

            ConfigSwitch {
                buttonIcon: "interests"
                text: Translation.tr("Use adaptive Material shape")
                checked: Config.options.dock.enableShapeMask
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.dock.enableShapeMask)
                        Config.options.dock.enableShapeMask = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "contrast"
                text: Translation.tr("Dim inactive icons")
                checked: Config.options.dock.dimInactiveIcons
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.dock.dimInactiveIcons)
                        Config.options.dock.dimInactiveIcons = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "filter_b_and_w"
                text: Translation.tr("Use monochrome icons")
                checked: Config.options.dock.monochromeIcons
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.dock.monochromeIcons)
                        Config.options.dock.monochromeIcons = checked;
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                title: Translation.tr("Material shape")
                icon: "category"
                visible: Config.options.dock.enableShapeMask

                ConfigSelectionArray {
                    currentValue: Config.options.dock.shapeMask
                    onSelected: newValue => {
                        if (Config.ready)
                            Config.options.dock.shapeMask = newValue;
                    }
                    options: ["Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill", "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower", "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"].map(shape => ({
                        displayName: "",
                        shape: shape,
                        value: shape
                    }))
                }
            }
        }
    }
}
