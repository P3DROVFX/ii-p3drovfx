import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
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
            text: Translation.tr("Audio Controls")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }
    ContentSection {
        icon: "volume_up"
        title: Translation.tr("Audio Controls")

        ConfigSwitch {
            buttonIcon: "hearing"
            text: Translation.tr("Earbang protection")
            checked: Config.options.audio.protection.enable
            onCheckedChanged: {
                Config.options.audio.protection.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Prevents abrupt increments and restricts volume limit")
            }
        }

        ConfigSpinBox {
            enabled: Config.options.audio.protection.enable
            icon: "arrow_warm_up"
            text: Translation.tr("Max allowed volume increase")
            value: Config.options.audio.protection.maxAllowedIncrease
            from: 0
            to: 100
            stepSize: 2
            onValueChanged: {
                Config.options.audio.protection.maxAllowedIncrease = value;
            }
        }

        ConfigSpinBox {
            enabled: Config.options.audio.protection.enable
            icon: "vertical_align_top"
            text: Translation.tr("Volume limit")
            value: Config.options.audio.protection.maxAllowed
            from: 0
            to: 154
            stepSize: 2
            onValueChanged: {
                Config.options.audio.protection.maxAllowed = value;
            }
        }
    }
}
