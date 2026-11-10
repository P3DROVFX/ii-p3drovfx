import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.services

/**
 * A club: header with its standing and the favourite star, the next matches
 * and the latest results (with win/draw/loss), and its league table with the
 * club highlighted.
 */
Item {
    id: root

    property var baseTeam: null
    property real layoutWidth: width
    signal teamActivated(var team)
    signal matchActivated(var match)
    signal leagueActivated(string slug)

    readonly property string teamId: String(root.baseTeam?.id ?? "")
    readonly property string leagueSlug: root.baseTeam?.league || (root.entry?.results?.[0]?.league?.slug ?? "") || (root.entry?.fixtures?.[0]?.league?.slug ?? "")
    readonly property var entry: FootballService.teamCache[root.teamId] ?? null
    readonly property var info: root.entry?.team ?? null
    readonly property var table: FootballService.standingsCache[root.leagueSlug] ?? null
    readonly property bool wide: root.layoutWidth >= 1000
    readonly property bool favorite: FootballService.isFavorite(root.teamId)

    readonly property var tableGroups: (root.table?.groups ?? []).map(group => ({
        name: group.name,
        entries: group.entries.map(item => Object.assign({}, item, { highlight: item.id === root.teamId }))
    })).filter(group => group.entries.some(item => item.id === root.teamId))

    function load() {
        FootballService.requestTeam(root.teamId, root.baseTeam?.league ?? "");
        FootballService.watchedTeam = root.teamId;
        FootballService.watchedTeamLeague = root.baseTeam?.league ?? "";
    }
    function loadTable() {
        if (root.leagueSlug !== "")
            FootballService.requestStandings(root.leagueSlug);
    }
    onTeamIdChanged: {
        flick.contentY = 0;
        Qt.callLater(root.load);
    }
    onLeagueSlugChanged: Qt.callLater(root.loadTable)
    Component.onCompleted: {
        Qt.callLater(root.load);
        Qt.callLater(root.loadTable);
    }
    Component.onDestruction: {
        if (FootballService.watchedTeam === root.teamId)
            FootballService.watchedTeam = "";
    }

    component MatchList: SectionSlab {
        id: list
        property var matches: []
        property string emptyText: ""
        Repeater {
            model: list.matches
            delegate: MatchRow {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                match: modelData
                showDate: true
                showCompetition: true
                perspectiveTeamId: root.teamId
                isFirst: index === 0
                isLast: index === list.matches.length - 1
                onClicked: root.matchActivated(modelData)
            }
        }
        StyledIndeterminateProgressBar {
            Layout.fillWidth: true
            visible: !root.entry
        }
        StyledText {
            visible: root.entry !== null && list.matches.length === 0
            text: list.emptyText
            font.pixelSize: FootballStyle.textSmall
            color: FootballStyle.colSubtext
        }
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
                logo: root.info?.logo || root.baseTeam?.logo || ""
                overline: FootballService.leagueBySlug(root.leagueSlug)?.name ?? ""
                title: root.info?.name || root.baseTeam?.name || ""
                subtitle: [root.info?.standing ?? "", (root.info?.record ?? "") !== "" ? Translation.tr("Record %1").arg(root.info.record) : ""].filter(part => part !== "").join(" · ")
                crestShape: MaterialShape.Shape.Cookie12Sided
                ornamentShape: MaterialShape.Shape.SoftBurst

                ClockButton {
                    variant: root.favorite ? "filled" : "tonal"
                    symbol: "star"
                    label: root.favorite ? Translation.tr("Favorite") : Translation.tr("Add to favorites")
                    onClicked: FootballService.toggleFavorite({
                        id: root.teamId,
                        name: root.info?.name || root.baseTeam?.name || "",
                        logo: root.info?.logo || root.baseTeam?.logo || "",
                        league: root.leagueSlug
                    })
                }
                ClockIconButton {
                    visible: root.leagueSlug !== "" && FootballService.leagueBySlug(root.leagueSlug) !== null
                    symbol: "emoji_events"
                    tooltip: Translation.tr("Open competition")
                    colIcon: FootballStyle.colOnPrimaryContainer
                    onClicked: root.leagueActivated(root.leagueSlug)
                }
                ClockIconButton {
                    symbol: "refresh"
                    tooltip: Translation.tr("Refresh")
                    colIcon: FootballStyle.colOnPrimaryContainer
                    onClicked: FootballService.requestTeam(root.teamId, root.baseTeam?.league ?? "", true)
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.wide ? 2 : 1
                columnSpacing: FootballStyle.gap
                rowSpacing: FootballStyle.gap

                MatchList {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: 1
                    title: Translation.tr("Upcoming")
                    symbol: "event_upcoming"
                    shape: MaterialShape.Shape.Cookie7Sided
                    matches: (root.entry?.fixtures ?? []).slice(0, 8)
                    emptyText: Translation.tr("No upcoming matches")
                }
                MatchList {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: 1
                    title: Translation.tr("Results")
                    symbol: "history"
                    shape: MaterialShape.Shape.Flower
                    matches: (root.entry?.results ?? []).slice(0, 8)
                    emptyText: Translation.tr("No recent results")
                }
            }

            SectionSlab {
                Layout.fillWidth: true
                visible: root.tableGroups.length > 0
                title: FootballService.leagueBySlug(root.leagueSlug)?.name ?? Translation.tr("Table")
                symbol: "format_list_numbered"
                StandingsTable {
                    Layout.fillWidth: true
                    groups: root.tableGroups
                    league: root.leagueSlug
                    onTeamActivated: team => root.teamActivated(team)
                }
            }
        }
    }

    ScrollEdgeFade {
        target: flick
        color: FootballStyle.colPane
    }
}
