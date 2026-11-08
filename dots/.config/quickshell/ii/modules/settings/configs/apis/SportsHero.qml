import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The subject of the Sports page: what you follow and what it is doing now.
 * Left, the count of competitions in tall heavy digits with their crests in a
 * row; right, the live board (matches in play, or the next kickoff). Stacked
 * below 620 px. A scalloped ornament is clipped by the card.
 */
Item {
    id: root

    property var model: null
    property var catalog: null

    readonly property bool wide: width >= 620
    readonly property var games: SportsService.allGames ?? []
    readonly property var liveGames: root.games.filter(game => game.state === "in")
    readonly property var nextGame: root.games.find(game => game.state === "pre") ?? null
    readonly property bool sportsOn: SportsService.enabled
    readonly property var followedLeagues: (root.model?.leagues ?? []).filter(item => item?.enabled)
    readonly property var digitAxes: ({ "wght": 1000, "wdth": 50, "ROND": 100 })
    readonly property var capsAxes: ({ "wght": 800, "wdth": 120, "ROND": 0 })
    readonly property var headlineAxes: ({ "wght": 850, "wdth": 75, "slnt": -10, "ROND": 0 })

    implicitHeight: (root.wide ? Math.max(summary.implicitHeight, board.implicitHeight) : summary.implicitHeight + board.implicitHeight + 16) + 48

    Rectangle {
        id: mask
        width: surface.width
        height: surface.height
        radius: Appearance.rounding.verylarge
        visible: false
        layer.enabled: true
    }

    Item {
        id: surface
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colPrimaryContainer
        }
        MaterialShape {
            implicitSize: root.height * 1.8
            x: root.wide ? root.width * 0.45 - implicitSize / 2 : root.width - implicitSize * 0.45
            y: root.height - implicitSize * 0.62
            shape: MaterialShape.Shape.SoftBurst
            color: Appearance.colors.colOnPrimaryContainer
            opacity: 0.07
        }
    }

    // ── What you follow ─────────────────────────────────────────────────────
    ColumnLayout {
        id: summary
        x: 24
        y: 24
        width: root.wide ? root.width * 0.52 - 36 : root.width - 48
        spacing: 6

        StyledText {
            text: Translation.tr("You follow").toUpperCase()
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.variableAxes: root.capsAxes
            font.letterSpacing: 2
            color: Appearance.colors.colOnPrimaryContainer
            opacity: 0.8
        }

        RowLayout {
            spacing: 14
            StyledText {
                shouldUseNumberFont: false
                text: root.followedLeagues.length
                font.pixelSize: 84
                font.variableAxes: root.digitAxes
                color: Appearance.colors.colOnPrimaryContainer
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                StyledText {
                    text: (root.followedLeagues.length === 1 ? Translation.tr("competition") : Translation.tr("competitions")).toUpperCase()
                    font.pixelSize: 22
                    font.variableAxes: root.headlineAxes
                    color: Appearance.colors.colOnPrimaryContainer
                }
                StyledText {
                    text: (root.model?.teamTerms.length ?? 0) === 0 ? Translation.tr("Every team")
                        : (root.model.teamTerms.length === 1 ? Translation.tr("1 team only") : Translation.tr("%1 teams only").arg(root.model.teamTerms.length))
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.85
                }
            }
        }

        // Crests of the followed competitions, overlapping like a hand of cards.
        Row {
            Layout.topMargin: 4
            spacing: -10
            visible: root.followedLeagues.length > 0
            Repeater {
                model: root.followedLeagues.slice(0, 9)
                delegate: Rectangle {
                    required property var modelData
                    width: 44
                    height: 44
                    radius: 22
                    color: Appearance.m3colors.m3surfaceContainerHighest
                    CrestImage {
                        anchors.centerIn: parent
                        width: 28
                        height: 28
                        url: modelData.logo
                        fillMode: Image.PreserveAspectFit
                        mipmap: true
                        visible: (modelData.logo ?? "") !== ""
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: (modelData.logo ?? "") === ""
                        text: root.catalog?.sportById(modelData.sport)?.icon ?? "sports"
                        iconSize: 22
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }
            Rectangle {
                visible: root.followedLeagues.length > 9
                width: 44
                height: 44
                radius: 22
                color: Appearance.colors.colPrimary
                StyledText {
                    anchors.centerIn: parent
                    text: `+${root.followedLeagues.length - 9}`
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Black
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
        StyledText {
            visible: root.followedLeagues.length === 0
            Layout.fillWidth: true
            text: Translation.tr("Pick a sport below and tap the competitions you care about.")
            wrapMode: Text.WordWrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnPrimaryContainer
        }
    }

    // ── Live board ──────────────────────────────────────────────────────────
    Rectangle {
        id: board
        x: root.wide ? root.width * 0.52 : 24
        y: root.wide ? 24 : summary.y + summary.implicitHeight + 16
        width: root.wide ? root.width * 0.48 - 24 : root.width - 48
        implicitHeight: boardColumn.implicitHeight + 32
        height: root.wide ? root.height - 48 : implicitHeight
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer1

        ColumnLayout {
            id: boardColumn
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 10

            RowLayout {
                spacing: 8
                Rectangle {
                    implicitWidth: 10
                    implicitHeight: 10
                    radius: 5
                    color: root.liveGames.length > 0 ? Appearance.colors.colTertiary : Appearance.colors.colOutline
                }
                StyledText {
                    text: !root.sportsOn ? Translation.tr("Sports is off").toUpperCase()
                        : root.liveGames.length > 0 ? Translation.tr("Live now · %1").arg(root.liveGames.length).toUpperCase()
                        : Translation.tr("Nothing live").toUpperCase()
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.variableAxes: root.capsAxes
                    font.letterSpacing: 1.5
                    color: Appearance.colors.colOnLayer1
                }
            }

            Repeater {
                model: root.liveGames.slice(0, 3)
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    CrestImage {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        url: modelData.home?.logo
                        fillMode: Image.PreserveAspectFit
                        mipmap: true
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: modelData.home?.name ?? ""
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        shouldUseNumberFont: false
                        text: `${modelData.home?.score ?? ""}  ${modelData.away?.score ?? ""}`
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.variableAxes: root.digitAxes
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: modelData.away?.name ?? ""
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                    CrestImage {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        url: modelData.away?.logo
                        fillMode: Image.PreserveAspectFit
                        mipmap: true
                    }
                    Rectangle {
                        implicitHeight: 22
                        implicitWidth: minuteText.implicitWidth + 14
                        radius: 11
                        color: Appearance.colors.colTertiaryContainer
                        StyledText {
                            id: minuteText
                            anchors.centerIn: parent
                            text: modelData.status ?? ""
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnTertiaryContainer
                        }
                    }
                }
            }

            StyledText {
                visible: root.liveGames.length === 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: !root.sportsOn ? Translation.tr("Turn on the bar, dock or lock screen widget below to start fetching scores.")
                    : root.nextGame ? Translation.tr("Next: %1 · %2").arg(root.nextGame.name ?? "").arg(root.nextGame.status ?? "")
                    : Translation.tr("No matches from your competitions in the next hours.")
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Scores from ESPN, refreshed every %1 s").arg(Config.options.bar.sports.updateInterval)
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }
}
