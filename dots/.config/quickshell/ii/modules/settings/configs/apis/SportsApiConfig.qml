import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.colors
import qs.modules.settings.configs.apis
import qs.modules.settings.configs.widgets

/**
 * APIs → Sports. What you follow is the hero; the main pane picks competitions
 * by sport with their real names and crests; teams narrow them down; the
 * surfaces that show scores are tiles; timing is the fine print.
 */
ContentPage {
    id: root
    forceWidth: false
    property bool showBackButton: false
    signal goBack()

    readonly property bool apiOn: Config.options.bar.sports.apiEnabled ?? true

    SportsCatalog {
        id: catalog
    }
    SportsFollowModel {
        id: follow
    }

    ConfigSubPageHeader {
        visible: root.showBackButton
        title: Translation.tr("Sports")
        onBack: root.goBack()
    }

    // Master switch: off means no ESPN request anywhere in the shell.
    RippleButton {
        id: master
        Layout.fillWidth: true
        implicitHeight: masterRow.implicitHeight + 40
        buttonRadius: Appearance.rounding.verylarge
        buttonRadiusPressed: Appearance.rounding.large
        colBackground: root.apiOn ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
        colBackgroundHover: root.apiOn ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer1Hover
        colRipple: ColorUtils.applyAlpha(root.apiOn ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1, 0.16)
        onClicked: Config.options.bar.sports.apiEnabled = !root.apiOn

        readonly property color colContent: root.apiOn ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1

        contentItem: Item {
            RowLayout {
                id: masterRow
                x: 20
                y: 20
                width: parent.width - 40
                spacing: 16
                MaterialShapeWrappedMaterialSymbol {
                    text: root.apiOn ? "scoreboard" : "sports_score"
                    iconSize: 26
                    padding: 14
                    shape: root.apiOn ? MaterialShape.Shape.Cookie12Sided : MaterialShape.Shape.Circle
                    color: root.apiOn ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                    colSymbol: root.apiOn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        text: Translation.tr("Sports data").toUpperCase()
                        font.pixelSize: 24
                        font.variableAxes: ({ "wght": 850, "wdth": 75, "slnt": -10, "ROND": 0 })
                        color: master.colContent
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: root.apiOn
                            ? Translation.tr("On. Scores from ESPN reach the bar, dock, lock screen, island, timetable, search, the AI and the football page.")
                            : Translation.tr("Off. The shell never contacts ESPN and hides every sports surface. Nothing you follow is lost.")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: master.colContent
                        opacity: 0.85
                    }
                }
                StyledSwitch {
                    checked: root.apiOn
                    onClicked: Config.options.bar.sports.apiEnabled = checked
                }
            }
        }
    }

    SportsHero {
        Layout.fillWidth: true
        visible: root.apiOn
        model: follow
        catalog: catalog
    }

    SportsLeaguePane {
        Layout.fillWidth: true
        visible: root.apiOn
        model: follow
        catalog: catalog
    }

    SportsTeamsPane {
        Layout.fillWidth: true
        visible: root.apiOn
        model: follow
        catalog: catalog
    }

    // ── Your competitions ────────────────────────────────────────────────────
    AppSettingsSection {
        Layout.topMargin: 12
        visible: root.apiOn && follow.leagues.length > 0
        title: Translation.tr("Your competitions")
        symbol: "emoji_events"
        description: Translation.tr("Pause a competition to keep it here without fetching it.")

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Repeater {
                model: follow.leagues
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool active: row.modelData?.enabled === true
                    readonly property int count: follow.leagues.length
                    Layout.fillWidth: true
                    implicitHeight: 64
                    topLeftRadius: row.index === 0 ? Appearance.rounding.large : Appearance.rounding.verysmall
                    topRightRadius: topLeftRadius
                    bottomLeftRadius: row.index === row.count - 1 ? Appearance.rounding.large : Appearance.rounding.verysmall
                    bottomRightRadius: bottomLeftRadius
                    color: Appearance.colors.colLayer1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        Rectangle {
                            implicitWidth: 42
                            implicitHeight: 42
                            radius: 21
                            color: Appearance.m3colors.m3surfaceContainerHighest
                            opacity: row.active ? 1 : 0.5
                            CrestImage {
                                anchors.centerIn: parent
                                width: 28
                                height: 28
                                visible: (row.modelData?.logo ?? "") !== ""
                                url: row.modelData?.logo
                                fillMode: Image.PreserveAspectFit
                                mipmap: true
                            }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: (row.modelData?.logo ?? "") === ""
                                text: catalog.sportById(row.modelData?.sport ?? "").icon
                                iconSize: 22
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: row.modelData?.name || row.modelData?.league || ""
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                                opacity: row.active ? 1 : 0.6
                            }
                            StyledText {
                                text: row.active ? catalog.sportById(row.modelData?.sport ?? "").label
                                    : Translation.tr("%1 · paused").arg(catalog.sportById(row.modelData?.sport ?? "").label)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                        StyledSwitch {
                            checked: row.active
                            onClicked: follow.setEnabled(row.modelData.sport, row.modelData.league, checked)
                            StyledToolTip {
                                text: row.active ? Translation.tr("Pause") : Translation.tr("Resume")
                            }
                        }
                        RippleButton {
                            implicitWidth: 36
                            implicitHeight: 36
                            buttonRadius: 18
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colErrorContainer
                            onClicked: follow.unfollow(row.modelData.sport, row.modelData.league)
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "delete"
                                iconSize: 20
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledToolTip {
                                text: Translation.tr("Stop following")
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Where scores show ────────────────────────────────────────────────────
    AppSettingsSection {
        Layout.topMargin: 12
        visible: root.apiOn
        title: Translation.tr("Where scores show")
        symbol: "visibility"

        Grid {
            id: tiles
            Layout.fillWidth: true
            readonly property int tileHeight: 200
            readonly property int count: 4
            readonly property int maxCols: Math.max(1, Math.floor((width + spacing) / (300 + spacing)))
            columns: tiles.maxCols >= tiles.count ? tiles.count : (tiles.maxCols >= 2 ? 2 : 1)
            spacing: 12
            readonly property real tileWidth: (width - spacing * (columns - 1)) / columns

            ColorsFeatureTile {
                id: barTile
                width: tiles.tileWidth
                height: tiles.tileHeight
                symbol: "space_bar"
                shapeOn: MaterialShape.Shape.Cookie12Sided
                title: Translation.tr("Bar")
                checked: Config.options.bar.sports.enable
                summary: checked ? (Config.options.bar.styles.sports === "expressive" ? Translation.tr("Expressive scoreboard; the popup lists every match.")
                                                                                    : Translation.tr("Compact scoreboard; the popup lists every match."))
                                 : Translation.tr("Off. The bar shows no scores.")
                onToggled: value => Config.options.bar.sports.enable = value
                ColorsChip {
                    label: Translation.tr("Default")
                    chosen: Config.options.bar.styles.sports !== "expressive"
                    enabled: barTile.checked
                    colContent: barTile.colContent
                    colChosen: Appearance.colors.colPrimary
                    colOnChosen: Appearance.colors.colOnPrimary
                    onClicked: Config.options.bar.styles.sports = "default"
                }
                ColorsChip {
                    label: Translation.tr("Expressive")
                    chosen: Config.options.bar.styles.sports === "expressive"
                    enabled: barTile.checked
                    colContent: barTile.colContent
                    colChosen: Appearance.colors.colPrimary
                    colOnChosen: Appearance.colors.colOnPrimary
                    onClicked: Config.options.bar.styles.sports = "expressive"
                }
            }

            ColorsFeatureTile {
                width: tiles.tileWidth
                height: tiles.tileHeight
                symbol: "dock_to_bottom"
                shapeOn: MaterialShape.Shape.Flower
                title: Translation.tr("Dock")
                checked: Config.options.dock.enableSportsWidget ?? false
                summary: checked ? Translation.tr("A scoreboard beside your apps; click it to switch matches.")
                                 : Translation.tr("Off. The dock shows no scores.")
                onToggled: value => Config.options.dock.enableSportsWidget = value
            }

            ColorsFeatureTile {
                width: tiles.tileWidth
                height: tiles.tileHeight
                symbol: "lock"
                shapeOn: MaterialShape.Shape.SoftBurst
                title: Translation.tr("Lock screen")
                checked: Config.options.lock.sports ?? true
                summary: checked ? Translation.tr("The current match in a toolbar at the top of the lock screen.")
                                 : Translation.tr("Off. The lock screen shows no scores.")
                onToggled: value => Config.options.lock.sports = value
            }

            ColorsFeatureTile {
                id: alertsTile
                width: tiles.tileWidth
                height: tiles.tileHeight
                symbol: "campaign"
                shapeOn: MaterialShape.Shape.Clover4Leaf
                title: Translation.tr("Match alerts")
                checked: Config.options.bar.sports.goalAnimation || Config.options.bar.sports.cardAnimation
                summary: !checked ? Translation.tr("Off. Goals and cards pass by quietly.")
                    : Config.options.bar.sports.goalAnimation && Config.options.bar.sports.cardAnimation ? Translation.tr("The bar widget celebrates goals and flags yellow and red cards.")
                    : Config.options.bar.sports.goalAnimation ? Translation.tr("The bar widget celebrates goals.")
                    : Translation.tr("The bar widget flags yellow and red cards.")
                onToggled: value => {
                    Config.options.bar.sports.goalAnimation = value;
                    Config.options.bar.sports.cardAnimation = value;
                }
                ColorsChip {
                    label: Translation.tr("Goals")
                    chosen: Config.options.bar.sports.goalAnimation
                    enabled: alertsTile.checked
                    colContent: alertsTile.colContent
                    colChosen: Appearance.colors.colPrimary
                    colOnChosen: Appearance.colors.colOnPrimary
                    onClicked: Config.options.bar.sports.goalAnimation = !Config.options.bar.sports.goalAnimation
                }
                ColorsChip {
                    label: Translation.tr("Cards")
                    chosen: Config.options.bar.sports.cardAnimation
                    enabled: alertsTile.checked
                    colContent: alertsTile.colContent
                    colChosen: Appearance.colors.colPrimary
                    colOnChosen: Appearance.colors.colOnPrimary
                    onClicked: Config.options.bar.sports.cardAnimation = !Config.options.bar.sports.cardAnimation
                }
            }
        }
    }

    ContentSection {
        visible: root.apiOn && Config.options.bar.sports.enable && Config.options.bar.styles.sports === "expressive"
        icon: "palette"
        title: Translation.tr("Bar scoreboard colours")

        ExpressiveColorModeSubsection {
            currentValue: Config.options.bar.sports.colorMode
            onSelected: newValue => Config.options.bar.sports.colorMode = String(newValue)
        }
    }

    // ── Timing ───────────────────────────────────────────────────────────────
    AppSettingsSection {
        Layout.topMargin: 12
        visible: root.apiOn
        title: Translation.tr("Timing")
        symbol: "schedule"

        AppStepperRow {
            symbol: "event_upcoming"
            title: Translation.tr("Show matches starting within")
            description: Translation.tr("Hours before kickoff a match appears")
            value: Config.options.bar.sports.showBeforeHours
            from: 1
            to: 72
            onMoved: value => Config.options.bar.sports.showBeforeHours = value
        }
        AppStepperRow {
            symbol: "history"
            title: Translation.tr("Keep finished matches for")
            description: Translation.tr("Minutes a final score stays after the whistle")
            value: Config.options.bar.sports.showAfterMinutes
            from: 0
            to: 1440
            stepSize: 15
            onMoved: value => Config.options.bar.sports.showAfterMinutes = value
        }
        AppStepperRow {
            symbol: "autorenew"
            title: Translation.tr("Refresh scores every")
            description: Translation.tr("Seconds between updates while a widget is on")
            value: Config.options.bar.sports.updateInterval
            from: 15
            to: 600
            stepSize: 15
            onMoved: value => Config.options.bar.sports.updateInterval = value
        }
        AppStepperRow {
            symbol: "view_agenda"
            title: Translation.tr("Matches in the bar popup")
            description: Translation.tr("Cards visible before the list scrolls")
            value: Config.options.bar.sports.maxCardsPopup
            from: 1
            to: 15
            onMoved: value => Config.options.bar.sports.maxCardsPopup = value
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
                label: Translation.tr("Bar widgets")
                sectionHighlight: Translation.tr("Widgets")
            }
            RelatedChip {
                pageId: "lockScreen"
                label: Translation.tr("Lock screen settings")
            }
            RelatedChip {
                pageId: "cheatSheet"
                label: Translation.tr("Football overview")
            }
        }
    }
}
