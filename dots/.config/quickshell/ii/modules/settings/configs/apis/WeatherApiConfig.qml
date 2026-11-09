import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.colors
import qs.modules.settings.configs.widgets

/**
 * APIs → Weather. The live reading is the hero; location and units come from
 * the shared location card; the surfaces that show the weather are tiles;
 * polling is the fine print. Data comes from Open-Meteo.
 */
ContentPage {
    id: root
    forceWidth: false
    property bool showBackButton: false
    signal goBack()

    readonly property var reading: Weather.data ?? ({})
    readonly property bool hasReading: (root.reading.city ?? "City") !== "City" && String(root.reading.wDesc ?? "") !== ""
    readonly property var digitAxes: ({ "wght": 1000, "wdth": 50, "ROND": 100 })

    ConfigSubPageHeader {
        visible: root.showBackButton
        title: Translation.tr("Weather")
        onBack: root.goBack()
    }

    // ── Live reading ─────────────────────────────────────────────────────────
    Rectangle {
        id: hero
        Layout.fillWidth: true
        implicitHeight: heroColumn.implicitHeight + 40
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colPrimaryContainer

        readonly property color colContent: Appearance.colors.colOnPrimaryContainer

        ColumnLayout {
            id: heroColumn
            x: 20
            y: 20
            width: parent.width - 40
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                MaterialShapeWrappedMaterialSymbol {
                    text: Icons.getWeatherIcon(root.reading.wCode ?? 113) ?? "cloud"
                    iconSize: 26
                    padding: 14
                    shape: MaterialShape.Shape.Cookie9Sided
                    color: Appearance.colors.colPrimary
                    colSymbol: Appearance.colors.colOnPrimary
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: "Open-Meteo".toUpperCase()
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.variableAxes: ({ "wght": 800, "wdth": 120, "ROND": 0 })
                        font.letterSpacing: 1.8
                        color: hero.colContent
                        opacity: 0.75
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: (root.hasReading ? String(root.reading.city) : Translation.tr("Weather")).toUpperCase()
                        elide: Text.ElideRight
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 16
                        font.pixelSize: 24
                        font.variableAxes: ({ "wght": 850, "wdth": 75, "slnt": -10, "ROND": 0 })
                        color: hero.colContent
                    }
                }
                RippleButton {
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: 20
                    enabled: !Weather.manualRefreshPending
                    colBackground: ColorUtils.applyAlpha(hero.colContent, 0.1)
                    colBackgroundHover: ColorUtils.applyAlpha(hero.colContent, 0.18)
                    colRipple: ColorUtils.applyAlpha(hero.colContent, 0.24)
                    onClicked: Weather.refreshManually()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "refresh"
                        iconSize: 20
                        color: hero.colContent
                        opacity: Weather.manualRefreshPending ? 0.5 : 1
                    }
                    StyledToolTip {
                        text: Translation.tr("Refresh now")
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.hasReading
                    ? Translation.tr("%1 · feels like %2").arg(root.reading.wDesc).arg(root.reading.tempFeelsLike)
                    : Translation.tr("No reading yet. The forecast arrives once the location is known.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: hero.colContent
                opacity: 0.85
            }

            // Figures
            Flow {
                Layout.fillWidth: true
                visible: root.hasReading
                spacing: 24
                Repeater {
                    model: [
                        { value: root.reading.temp ?? "", label: Translation.tr("Now") },
                        { value: root.reading.humidity ?? "", label: Translation.tr("Humidity") },
                        { value: String(root.reading.wind ?? "").split(" ")[0], label: Translation.tr("Wind %1").arg(String(root.reading.wind ?? "").split(" ")[1] ?? "") },
                        { value: Math.round(root.reading.uv ?? 0), label: Translation.tr("UV index") }
                    ]
                    delegate: ColumnLayout {
                        required property var modelData
                        spacing: -4
                        StyledText {
                            shouldUseNumberFont: false
                            text: modelData.value
                            font.pixelSize: 44
                            font.variableAxes: root.digitAxes
                            color: hero.colContent
                        }
                        StyledText {
                            text: String(modelData.label).toUpperCase()
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.variableAxes: ({ "wght": 800, "wdth": 120, "ROND": 0 })
                            font.letterSpacing: 1.2
                            color: hero.colContent
                            opacity: 0.75
                        }
                    }
                }
            }

            StyledText {
                visible: root.hasReading
                text: Translation.tr("Sunrise %1 · Sunset %2 · Updated %3").arg(root.reading.sunrise).arg(root.reading.sunset).arg(root.reading.lastRefresh)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: hero.colContent
                opacity: 0.75
            }
        }
    }

    // ── Location & units ─────────────────────────────────────────────────────
    AppSettingsSection {
        Layout.topMargin: 12
        title: Translation.tr("Location & units")
        symbol: "location_on"

        WeatherLocationCard {
            Layout.fillWidth: true
        }
    }

    // ── Where weather shows ──────────────────────────────────────────────────
    AppSettingsSection {
        Layout.topMargin: 12
        title: Translation.tr("Where weather shows")
        symbol: "visibility"
        description: Translation.tr("The bar widget is placed from the bar layout.")

        Grid {
            id: tiles
            Layout.fillWidth: true
            readonly property int tileHeight: 180
            readonly property int maxCols: Math.max(1, Math.floor((width + spacing) / (300 + spacing)))
            columns: tiles.maxCols >= 2 ? 2 : 1
            spacing: 12
            readonly property real tileWidth: (width - spacing * (columns - 1)) / columns

            ColorsFeatureTile {
                width: tiles.tileWidth
                height: tiles.tileHeight
                symbol: "dock_to_bottom"
                shapeOn: MaterialShape.Shape.Flower
                title: Translation.tr("Dock")
                checked: Config.options.dock.enableWeatherWidget ?? false
                summary: checked ? Translation.tr("The current weather beside your apps.")
                                 : Translation.tr("Off. The dock shows no weather.")
                onToggled: value => Config.options.dock.enableWeatherWidget = value
            }

            ColorsFeatureTile {
                width: tiles.tileWidth
                height: tiles.tileHeight
                symbol: "lock"
                shapeOn: MaterialShape.Shape.SoftBurst
                title: Translation.tr("Lock screen")
                checked: Config.options.lock.showWeather ?? true
                summary: checked ? Translation.tr("Temperature and sky on the lock screen.")
                                 : Translation.tr("Off. The lock screen shows no weather.")
                onToggled: value => Config.options.lock.showWeather = value
            }
        }
    }

    // ── Timing ───────────────────────────────────────────────────────────────
    AppSettingsSection {
        Layout.topMargin: 12
        title: Translation.tr("Timing")
        symbol: "schedule"

        AppStepperRow {
            symbol: "autorenew"
            title: Translation.tr("Refresh weather every")
            description: Translation.tr("Minutes between automatic updates")
            value: Config.options.bar.weather.fetchInterval
            from: 5
            to: 50
            stepSize: 5
            onMoved: value => Config.options.bar.weather.fetchInterval = value
        }
    }

    ContentSection {
        icon: "link"
        title: Translation.tr("Related settings")

        Flow {
            Layout.fillWidth: true
            spacing: 8
            RelatedChip {
                pageId: "bar"
                label: Translation.tr("Weather bar widget")
                sectionHighlight: Translation.tr("Widgets")
            }
            RelatedChip {
                pageId: "widgets"
                label: Translation.tr("Desktop weather widget")
            }
            RelatedChip {
                pageId: "lockScreen"
                label: Translation.tr("Lock screen settings")
            }
        }
    }
}
