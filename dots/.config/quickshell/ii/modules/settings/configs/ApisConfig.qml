import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.apis

/**
 * APIs: the live data sources the shell talks to, each as a card that says
 * what it brings in right now and opens its own page. Sports leads (ESPN
 * scores for the bar, dock and lock screen; the cheatsheet's Football
 * overview uses the same feed), then Weather (Open-Meteo).
 */
Item {
    id: apisRoot
    anchors.fill: parent

    property alias contentY: root.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    function open(page) {
        apisRoot.activeSubPage = Qt.resolvedUrl(page);
    }

    readonly property var sportsLeagues: Array.from(Config.options.bar.sports.monitoredLeagues ?? []).filter(item => item?.enabled)
    readonly property int sportsTeams: String(Config.options.bar.sports.teamFilter ?? "").split(",").filter(term => term.trim().length > 0).length
    readonly property int liveCount: (SportsService.allGames ?? []).filter(game => game.state === "in").length
    readonly property bool apiOn: Config.options.bar.sports.apiEnabled ?? true
    readonly property var weather: Weather.data ?? ({})
    readonly property bool weatherReady: (weather.city ?? "City") !== "City" && String(weather.wDesc ?? "") !== ""
    readonly property bool sportsOn: apiOn && (Config.options.bar.sports.enable || (Config.options.dock.enableSportsWidget ?? false) || (Config.options.lock.sports ?? true))

    ContentPage {
        id: root
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        // ── Hero ─────────────────────────────────────────────────────────────
        Item {
            id: hero
            Layout.fillWidth: true
            implicitHeight: heroColumn.implicitHeight + 56

            Rectangle {
                id: heroMask
                width: heroSurface.width
                height: heroSurface.height
                radius: Appearance.rounding.verylarge
                visible: false
                layer.enabled: true
            }
            Item {
                id: heroSurface
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: heroMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }
                Rectangle {
                    anchors.fill: parent
                    color: Appearance.colors.colLayer1
                }
                MaterialShape {
                    implicitSize: hero.height * 2
                    x: hero.width - implicitSize * 0.4
                    y: (hero.height - implicitSize) / 2
                    shape: MaterialShape.Shape.Cookie12Sided
                    color: Appearance.colors.colPrimary
                    opacity: 0.1
                }
                MaterialShape {
                    implicitSize: hero.height * 0.9
                    x: hero.width - implicitSize * 1.6
                    y: hero.height - implicitSize * 0.55
                    shape: MaterialShape.Shape.Flower
                    color: Appearance.colors.colTertiary
                    opacity: 0.1
                }
            }

            ColumnLayout {
                id: heroColumn
                x: 28
                y: 28
                width: hero.width - 56
                spacing: 6
                StyledText {
                    text: Translation.tr("Services & Integrations").toUpperCase()
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.variableAxes: ({ "wght": 800, "wdth": 120, "ROND": 0 })
                    font.letterSpacing: 2
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    text: Translation.tr("APIs")
                    font.pixelSize: 56
                    font.variableAxes: ({ "wght": 900, "wdth": 60, "slnt": -8, "ROND": 0 })
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 560
                    wrapMode: Text.WordWrap
                    text: Translation.tr("Live data the shell fetches for you. Pick what each source follows and where it shows up.")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 8
                    Repeater {
                        model: [
                            { on: apisRoot.apiOn, label: !apisRoot.apiOn ? Translation.tr("Sports data off") : apisRoot.sportsOn ? Translation.tr("Scores on") : Translation.tr("Scores off"), icon: "scoreboard" },
                            { on: apisRoot.liveCount > 0, label: apisRoot.liveCount > 0 ? Translation.tr("%1 live now").arg(apisRoot.liveCount) : Translation.tr("Nothing live"), icon: "radio_button_checked" },
                            { on: apisRoot.weatherReady, label: apisRoot.weatherReady ? `${apisRoot.weather.city} · ${apisRoot.weather.temp}` : Translation.tr("No weather yet"), icon: "partly_cloudy_day" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            implicitHeight: 32
                            implicitWidth: pill.implicitWidth + 24
                            radius: 16
                            color: modelData.on ? Appearance.colors.colTertiaryContainer : Appearance.colors.colLayer2
                            RowLayout {
                                id: pill
                                anchors.centerIn: parent
                                spacing: 6
                                MaterialSymbol {
                                    text: modelData.icon
                                    iconSize: 16
                                    fill: modelData.on ? 1 : 0
                                    color: modelData.on ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnSurfaceVariant
                                }
                                StyledText {
                                    text: modelData.label
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Bold
                                    color: modelData.on ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnSurfaceVariant
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Sources ──────────────────────────────────────────────────────────
        AppSettingsSection {
            Layout.topMargin: 12
            title: Translation.tr("Sports data")
            symbol: "sports"

            Grid {
                id: cards
                Layout.fillWidth: true
                readonly property int maxCols: Math.max(1, Math.floor((width + spacing) / (340 + spacing)))
                columns: 1
                spacing: 12
                readonly property real cardWidth: (width - spacing * (columns - 1)) / columns

                ApiCard {
                    width: cards.cardWidth
                    symbol: "scoreboard"
                    shapeOn: MaterialShape.Shape.Cookie12Sided
                    provider: "ESPN"
                    title: Translation.tr("Sports")
                    hasSwitch: true
                    isOn: apisRoot.apiOn
                    onSwitchToggled: value => Config.options.bar.sports.apiEnabled = value
                    summary: !apisRoot.apiOn ? Translation.tr("Off. The shell never contacts ESPN and every sports surface stays hidden.")
                        : apisRoot.sportsLeagues.length === 0
                        ? Translation.tr("Follow competitions and teams for scores in the bar, dock and lock screen.")
                        : Translation.tr("Scores, goals and cards from the competitions you follow, in the bar, dock and lock screen.")
                    stats: !apisRoot.apiOn ? [] : [
                        { value: apisRoot.sportsLeagues.length, label: Translation.tr("Competitions") },
                        { value: apisRoot.sportsTeams === 0 ? "∞" : apisRoot.sportsTeams, label: Translation.tr("Teams") },
                        { value: apisRoot.liveCount, label: Translation.tr("Live now") }
                    ]
                    logos: !apisRoot.apiOn ? [] : apisRoot.sportsLeagues.map(item => item.logo ?? "").filter(url => url !== "")
                    actionLabel: Translation.tr("Follow sports")
                    onOpened: apisRoot.open("apis/SportsApiConfig.qml")
                }
            }
        }

        AppSettingsSection {
            Layout.topMargin: 12
            title: Translation.tr("Weather data")
            symbol: "partly_cloudy_day"

            ApiCard {
                Layout.fillWidth: true
                symbol: Icons.getWeatherIcon(apisRoot.weather.wCode ?? 113) ?? "cloud"
                shapeOn: MaterialShape.Shape.Cookie9Sided
                provider: "Open-Meteo"
                title: Translation.tr("Weather")
                summary: !apisRoot.weatherReady ? Translation.tr("Forecast for your city or live location, in the bar, dock, lock screen and desktop widgets.")
                    : Translation.tr("%1 in %2. Forecast for the bar, dock, lock screen and desktop widgets.").arg(apisRoot.weather.wDesc).arg(apisRoot.weather.city)
                stats: !apisRoot.weatherReady ? [] : [
                    { value: apisRoot.weather.temp, label: Translation.tr("Now") },
                    { value: apisRoot.weather.humidity, label: Translation.tr("Humidity") },
                    { value: Config.options.bar.weather.fetchInterval + "m", label: Translation.tr("Refresh") }
                ]
                actionLabel: Translation.tr("Weather settings")
                onOpened: apisRoot.open("apis/WeatherApiConfig.qml")
            }
        }

        ContentSection {
            icon: "link"
            title: Translation.tr("Other services")

            Flow {
                Layout.fillWidth: true
                spacing: 8
                RelatedChip {
                    pageId: "aiAssistant"
                    label: Translation.tr("AI models & keys")
                }
                RelatedChip {
                    pageId: "tasksAccounts"
                    label: Translation.tr("Google & TickTick accounts")
                }
                RelatedChip {
                    pageId: "mediaMusic"
                    label: Translation.tr("Lyrics & music recognition")
                }
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
