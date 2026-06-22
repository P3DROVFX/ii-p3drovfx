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
            text: Translation.tr("Weather Widget Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Weather Settings")
        icon: "cloud"

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !Config.options.background.widgets.weather.enable

            PagePlaceholder {
                anchors.fill: parent
                icon: "cloud_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Weather widget disabled")
                description: Translation.tr("Enable the desktop weather widget in Desktop Widgets settings to use this page.")
            }
        }

        ConfigSelectionArray {
            currentValue: Config.options.background.widgets.weather.placementStrategy
            onSelected: newValue => {
                Config.options.background.widgets.weather.placementStrategy = newValue;
            }
            options: [
                { displayName: Translation.tr("Draggable"), icon: "pan_tool", value: "draggable" },
                { displayName: Translation.tr("Least busy"), icon: "low_priority", value: "least_busy" },
                { displayName: Translation.tr("Most busy"), icon: "priority_high", value: "most_busy" }
            ]
        }
    }
}
