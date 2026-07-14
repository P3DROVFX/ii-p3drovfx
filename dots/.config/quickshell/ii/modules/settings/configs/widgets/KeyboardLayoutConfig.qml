import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    signal goBack()

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

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Keyboard Layout")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
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

    ContentSection {
        enabled: Config.options.bar.styles.keyboard === "material"
        icon: "interests"
        title: Translation.tr("Material 3 Design")

        ConfigSwitch {
            buttonIcon: "flip"
            text: Translation.tr("Move secondary component to the opposite")
            checked: Config.options.bar.keyboardLayout.secondaryOpposite
            onCheckedChanged: {
                Config.options.bar.keyboardLayout.secondaryOpposite = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "radio_button_checked"
            text: Translation.tr("Show primary component")
            checked: Config.options.bar.keyboardLayout.showPrimary
            onCheckedChanged: {
                Config.options.bar.keyboardLayout.showPrimary = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "radio_button_unchecked"
            text: Translation.tr("Show secondary component")
            checked: Config.options.bar.keyboardLayout.showSecondary
            onCheckedChanged: {
                Config.options.bar.keyboardLayout.showSecondary = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "sync"
            text: Translation.tr("Swap secondary component with the primary")
            checked: Config.options.bar.keyboardLayout.swapPrimaryWithSecondary
            onCheckedChanged: {
                Config.options.bar.keyboardLayout.swapPrimaryWithSecondary = checked;
            }
        }
    }
}
