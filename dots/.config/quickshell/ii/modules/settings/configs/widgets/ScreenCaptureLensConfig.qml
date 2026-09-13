import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

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
                text: Translation.tr("Google Lens & Visual Search")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("Google Lens & Selection Mode")
            icon: "search"
            tooltip: Translation.tr("Configure shape selection and search parameters for Google Lens.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ContentSubsection {
                    title: Translation.tr("Selection mode")
                    icon: "highlight_alt"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: Config.options.search.imageSearch.useCircleSelection ? "circle" : "rectangles"
                        onSelected: (newValue) => {
                            Config.options.search.imageSearch.useCircleSelection = (newValue === "circle");
                        }
                        options: [{
                            "displayName": Translation.tr("Rectangular selection"),
                            "value": "rectangles",
                            "icon": "activity_zone"
                        }, {
                            "displayName": Translation.tr("Circle to Search"),
                            "value": "circle",
                            "icon": "gesture"
                        }]
                    }
                }

                ContentSubsectionLabel {
                    text: Translation.tr("Rectangular selection")
                    visible: !Config.options.search.imageSearch.useCircleSelection
                }

                ConfigSwitch {
                    visible: !Config.options.search.imageSearch.useCircleSelection
                    buttonIcon: "border_inner"
                    text: Translation.tr("Show aim lines")
                    checked: Config.options.regionSelector.rect.showAimLines
                    onCheckedChanged: {
                        Config.options.regionSelector.rect.showAimLines = checked;
                    }
                }

                ContentSubsectionLabel {
                    text: Translation.tr("Circle selection")
                    visible: Config.options.search.imageSearch.useCircleSelection
                }

                ConfigSpinBox {
                    visible: Config.options.search.imageSearch.useCircleSelection
                    icon: "line_weight"
                    text: Translation.tr("Stroke width")
                    value: Config.options.regionSelector.circle.strokeWidth
                    from: 1
                    to: 20
                    stepSize: 1
                    onValueChanged: {
                        Config.options.regionSelector.circle.strokeWidth = value;
                    }
                }

                ConfigSpinBox {
                    visible: Config.options.search.imageSearch.useCircleSelection
                    icon: "padding"
                    text: Translation.tr("Padding")
                    value: Config.options.regionSelector.circle.padding
                    from: 0
                    to: 100
                    stepSize: 1
                    onValueChanged: {
                        Config.options.regionSelector.circle.padding = value;
                    }
                }
            }
        }
    }
}
