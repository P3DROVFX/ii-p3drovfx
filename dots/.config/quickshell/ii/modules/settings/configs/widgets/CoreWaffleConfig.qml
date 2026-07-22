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
            text: Translation.tr("Waffle Tweaks (Optional)")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }
    ContentSection {
        icon: "build"
        title: Translation.tr("Waffle Tweaks (Optional)")

        ConfigSwitch {
            buttonIcon: "align_horizontal_center"
            text: Translation.tr("Fix switch handle position")
            checked: Config.options.waffles.tweaks.switchHandlePositionFix
            onCheckedChanged: {
                Config.options.waffles.tweaks.switchHandlePositionFix = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "animation"
            text: Translation.tr("Smoother menu animations")
            checked: Config.options.waffles.tweaks.smootherMenuAnimations
            onCheckedChanged: {
                Config.options.waffles.tweaks.smootherMenuAnimations = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "search"
            text: Translation.tr("Smoother search bar")
            checked: Config.options.waffles.tweaks.smootherSearchBar
            onCheckedChanged: {
                Config.options.waffles.tweaks.smootherSearchBar = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "calendar_today"
            text: Translation.tr("Force 2-character day of week on calendar")
            checked: Config.options.waffles.calendar.force2CharDayOfWeek
            onCheckedChanged: {
                Config.options.waffles.calendar.force2CharDayOfWeek = checked;
            }
        }
    }
}
