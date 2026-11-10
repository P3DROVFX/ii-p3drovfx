import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.services

/**
 * A competition: its header (follow switch), the current round and the full
 * table side by side on wide panes, stacked otherwise.
 */
Item {
    id: root

    property string slug: ""
    property real layoutWidth: width
    signal teamActivated(var team)
    signal matchActivated(var match)

    readonly property var league: FootballService.leagueBySlug(root.slug)
    readonly property var table: FootballService.standingsCache[root.slug] ?? null
    readonly property var round: FootballService.leagueRoundCache[root.slug] ?? null
    readonly property bool wide: root.layoutWidth >= 1000

    function load() {
        FootballService.requestStandings(root.slug);
        FootballService.requestLeagueRound(root.slug);
        FootballService.watchedLeague = root.slug;
    }
    onSlugChanged: {
        flick.contentY = 0;
        Qt.callLater(root.load);
    }
    Component.onCompleted: Qt.callLater(root.load)
    Component.onDestruction: {
        if (FootballService.watchedLeague === root.slug)
            FootballService.watchedLeague = "";
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentHeight: column.implicitHeight + FootballStyle.gapHuge
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: column
            width: flick.width
            spacing: FootballStyle.gap

            EntityHero {
                Layout.fillWidth: true
                logo: root.league?.logo ?? ""
                overline: [root.league?.country ?? "", root.table?.season ?? ""].filter(part => part !== "").join(" · ")
                title: root.league?.name || root.table?.name || ""
                subtitle: (root.round?.round ?? "") !== "" ? Translation.tr("Round %1").arg(root.round.round) : ""
                crestShape: MaterialShape.Shape.Sunny
                ornamentShape: MaterialShape.Shape.Cookie12Sided

                ColumnLayout {
                    spacing: 4
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Follow").toUpperCase()
                        font.pixelSize: FootballStyle.textSmallest
                        font.variableAxes: FootballStyle.axesCaps
                        font.letterSpacing: 1.5
                        color: FootballStyle.colOnPrimaryContainer
                    }
                    StyledSwitch {
                        Layout.alignment: Qt.AlignHCenter
                        checked: FootballService.isLeagueEnabled(root.slug)
                        onClicked: FootballService.setLeagueEnabled(root.slug, checked)
                    }
                }
                ClockIconButton {
                    symbol: "refresh"
                    tooltip: Translation.tr("Refresh")
                    colIcon: FootballStyle.colOnPrimaryContainer
                    onClicked: {
                        FootballService.requestStandings(root.slug, true);
                        FootballService.requestLeagueRound(root.slug, true);
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.wide ? 2 : 1
                columnSpacing: FootballStyle.gap
                rowSpacing: FootballStyle.gap

                SectionSlab {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: 3
                    title: Translation.tr("Table")
                    symbol: "format_list_numbered"
                    StandingsTable {
                        Layout.fillWidth: true
                        visible: (root.table?.groups ?? []).length > 0
                        groups: root.table?.groups ?? []
                        league: root.slug
                        onTeamActivated: team => root.teamActivated(team)
                    }
                    StyledIndeterminateProgressBar {
                        Layout.fillWidth: true
                        visible: !root.table
                    }
                    StyledText {
                        visible: root.table !== null && (root.table?.groups ?? []).length === 0
                        text: root.table?.error || Translation.tr("This competition has no table")
                        font.pixelSize: FootballStyle.textSmall
                        color: FootballStyle.colSubtext
                    }
                }

                SectionSlab {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: 2
                    title: (root.round?.round ?? "") !== "" ? Translation.tr("Round %1").arg(root.round.round) : Translation.tr("Current round")
                    symbol: "event"
                    shape: MaterialShape.Shape.Cookie7Sided
                    Repeater {
                        model: root.round?.matches ?? []
                        delegate: MatchRow {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            match: modelData
                            showDate: true
                            isFirst: index === 0
                            isLast: index === (root.round?.matches ?? []).length - 1
                            onClicked: root.matchActivated(modelData)
                        }
                    }
                    StyledIndeterminateProgressBar {
                        Layout.fillWidth: true
                        visible: !root.round
                    }
                    StyledText {
                        visible: root.round !== null && (root.round?.matches ?? []).length === 0
                        text: root.round?.error || Translation.tr("No matches scheduled")
                        font.pixelSize: FootballStyle.textSmall
                        color: FootballStyle.colSubtext
                    }
                }
            }
        }
    }

    ScrollEdgeFade {
        target: flick
        color: FootballStyle.colPane
    }
}
