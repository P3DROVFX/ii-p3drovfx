import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "../../../ii/bar/widgets/keyboard"

ContentPage {
    id: root

    signal goBack()

    forceWidth: false
    readonly property string style: Config.options.bar.styles.keyboard ?? "default"

    RowLayout {
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
            onClicked: root.goBack()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

        }

        StyledText {
            text: Translation.tr("Keyboard Layout")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }

    }

    ContentSection {
        icon: "preview"
        title: Translation.tr("Live preview")

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Appearance.sizes.baseBarHeight + 28
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1

                Loader {
                    anchors.centerIn: parent
                    sourceComponent: {
                        if (root.style === "expressive")
                            return expressiveHorizontalPreview;
                        return defaultHorizontalPreview;
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: Appearance.sizes.verticalBarWidth + 28
                Layout.fillHeight: true
                implicitHeight: Appearance.sizes.baseBarHeight + 28
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1

                Loader {
                    anchors.centerIn: parent
                    sourceComponent: {
                        if (root.style === "expressive")
                            return expressiveVerticalPreview;
                        return defaultVerticalPreview;
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "style"
        title: Translation.tr("Style & Layout")

        ContentSubsection {
            title: Translation.tr("Keyboard layout style")
            icon: "keyboard"
            ConfigSelectionArray {
                currentValue: Config.options.bar.styles.keyboard
                onSelected: newValue => {
                    Config.options.bar.styles.keyboard = String(newValue);
                }
                options: [
                    { displayName: Translation.tr("Default"),    icon: "style",     value: "default" },
                    { displayName: Translation.tr("Material 3"), icon: "interests", value: "material" },
                    { displayName: Translation.tr("Expressive"), icon: "fluid_med", value: "expressive" }
                ]
            }
        }

        ExpressiveColorModeSubsection {
            visible: Config.options.bar.styles.keyboard === "expressive"
            currentValue: Config.options.bar.keyboardLayout.colorMode
            onSelected: newValue => Config.options.bar.keyboardLayout.colorMode = String(newValue)
        }
    }

    ContentSection {
        icon: "keyboard"
        title: Translation.tr("Keyboard Layout")

        ConfigSwitch {
            buttonIcon: "uppercase"
            text: Translation.tr("Uppercase layout abbreviation")
            checked: Config.options.bar.keyboardLayout.uppercaseLayout
            onCheckedChanged: {
                Config.options.bar.keyboardLayout.uppercaseLayout = checked;
            }
        }

    }

    MaterialWidgetLayoutSection {
        enabled: Config.options.bar.styles.keyboard === "material"
        config: Config.options.bar.keyboardLayout
    }

    Component {
        id: expressiveHorizontalPreview
        ExpressiveKeyboardLayout {
            vertical: false
        }
    }

    Component {
        id: expressiveVerticalPreview
        ExpressiveKeyboardLayout {
            vertical: true
        }
    }

    Component {
        id: defaultHorizontalPreview
        KeyboardLayoutWidget {
            vertical: false
        }
    }

    Component {
        id: defaultVerticalPreview
        KeyboardLayoutWidget {
            vertical: true
        }
    }
}
