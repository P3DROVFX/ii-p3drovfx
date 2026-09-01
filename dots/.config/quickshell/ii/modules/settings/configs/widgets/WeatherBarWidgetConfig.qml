pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "../../../ii/bar/widgets/weather"

ContentPage {
    id: root

    signal goBack()
    forceWidth: false

    readonly property string style: Config.options.bar.styles.weather ?? "default"
    readonly property bool customStyle: root.style === "horizon" || root.style === "tessera"

    RowLayout {
        spacing: Appearance.rounding.small

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
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
            text: Translation.tr("Weather widget")
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
            spacing: Appearance.sizes.elevationMargin

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Appearance.sizes.baseBarHeight * 4
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1

                Loader {
                    anchors.centerIn: parent
                    sourceComponent: {
                        if (root.style === "horizon")
                            return horizonHorizontalPreview;
                        if (root.style === "tessera")
                            return tesseraHorizontalPreview;
                        return null;
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: !root.customStyle
                    text: Translation.tr("Choose Horizon or Tessera to preview the new designs")
                    width: parent.width - Appearance.sizes.elevationMargin * 3
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    opacity: 0.65
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }
            }

            Rectangle {
                Layout.preferredWidth: Appearance.sizes.verticalBarWidth + Appearance.sizes.elevationMargin * 3
                implicitHeight: Appearance.sizes.baseBarHeight * 4
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1

                Loader {
                    anchors.centerIn: parent
                    sourceComponent: {
                        if (root.style === "horizon")
                            return horizonVerticalPreview;
                        if (root.style === "tessera")
                            return tesseraVerticalPreview;
                        return null;
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: root.style === "tessera" ? "view_module" : "landscape"
            text: root.style === "tessera"
                ? Translation.tr("Tessera separates the weather icon and temperature into two compact Material pieces, with no outer pill.")
                : Translation.tr("Horizon is an open rail composition: weather shape, bare temperature, and a short accent line — no outer pill.")
        }
    }

    ContentSection {
        icon: "palette"
        title: Translation.tr("Design")

        ContentSubsection {
            title: Translation.tr("Visual style")

            ConfigSelectionArray {
                currentValue: Config.options.bar.styles.weather
                onSelected: newValue => Config.options.bar.styles.weather = String(newValue)
                options: [
                    { displayName: Translation.tr("Default"), icon: "style", value: "default" },
                    { displayName: Translation.tr("Expressive"), icon: "fluid_med", value: "expressive" },
                    { displayName: Translation.tr("Horizon"), icon: "landscape", value: "horizon" },
                    { displayName: Translation.tr("Tessera"), icon: "view_module", value: "tessera" }
                ]
            }
        }

        ContentSubsection {
            visible: root.style === "horizon"
            title: Translation.tr("Horizon variant")

            ConfigSelectionArray {
                currentValue: Config.options.bar.weatherWidget.horizonVariant
                onSelected: newValue => Config.options.bar.weatherWidget.horizonVariant = String(newValue)
                options: [
                    { displayName: Translation.tr("Balanced"), icon: "balance", value: "balanced" },
                    { displayName: Translation.tr("Inverted"), icon: "invert_colors", value: "inverted" },
                    { displayName: Translation.tr("Minimal"), icon: "compress", value: "minimal" }
                ]
            }
        }

        ContentSubsection {
            visible: root.style === "tessera"
            title: Translation.tr("Tessera variant")

            ConfigSelectionArray {
                currentValue: Config.options.bar.weatherWidget.tesseraVariant
                onSelected: newValue => Config.options.bar.weatherWidget.tesseraVariant = String(newValue)
                options: [
                    { displayName: Translation.tr("Paired"), icon: "view_week", value: "paired" },
                    { displayName: Translation.tr("Contrast"), icon: "contrast", value: "contrast" },
                    { displayName: Translation.tr("Bare"), icon: "texture", value: "bare" }
                ]
            }
        }

        ContentSubsection {
            visible: root.customStyle
            title: Translation.tr("Colour treatment")

            ConfigSelectionArray {
                currentValue: Config.options.bar.weatherWidget.colorMode
                onSelected: newValue => Config.options.bar.weatherWidget.colorMode = String(newValue)
                options: [
                    { displayName: Translation.tr("Tonal"), icon: "colors", value: "tonal" },
                    { displayName: Translation.tr("Vibrant"), icon: "auto_awesome", value: "vibrant" },
                    { displayName: Translation.tr("Neutral"), icon: "contrast", value: "neutral" }
                ]
            }
        }
    }

    ContentSection {
        icon: "cloud"
        title: Translation.tr("Weather data")

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Location, GPS, temperature units, and refresh interval remain shared by every Weather design.")
            color: Appearance.colors.colOnLayer1
            opacity: 0.75
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }

        RelatedChip {
            pageId: "weather"
            label: Translation.tr("Open Weather service")
            sectionHighlight: Translation.tr("Weather Service")
        }
    }

    Component {
        id: horizonHorizontalPreview
        HorizonWeatherWidget { vertical: false }
    }

    Component {
        id: horizonVerticalPreview
        HorizonWeatherWidget { vertical: true }
    }

    Component {
        id: tesseraHorizontalPreview
        TesseraWeatherWidget { vertical: false }
    }

    Component {
        id: tesseraVerticalPreview
        TesseraWeatherWidget { vertical: true }
    }
}
