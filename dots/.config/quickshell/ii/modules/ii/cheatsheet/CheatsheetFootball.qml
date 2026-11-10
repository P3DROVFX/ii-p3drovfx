pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.services
import "./football"

/**
 * Football overview: a match centre in the cheatsheet.
 *
 * App frame from the design reference: a rail (Matches, Competitions, Teams),
 * the destination's list pane and a detail pane on the right that shows a
 * match, a competition or a club. Details link into each other (a crest opens
 * the club, a table row its club, a fixture its match) with a back history.
 *
 * Data comes from FootballService, held only while this tab is the visible one,
 * so the live refresh never runs behind a closed cheatsheet.
 */
Item {
    id: root

    focus: true
    implicitWidth: 1600
    implicitHeight: 780

    property Item keyNavTarget: null
    readonly property bool isCurrentTab: {
        try {
            return swipeView.currentIndex === index;
        } catch (error) {
            return true;
        }
    }
    readonly property bool isTabActive: (GlobalStates?.cheatsheetOpen ?? true) && root.visible && root.isCurrentTab

    // ── Session state (scalars only; the tree is rebuilt with the tab) ──────
    property string destination: "matches"
    property date selectedDate: new Date()
    property string filter: "all"
    // { kind: "match" | "league" | "team", match, slug, team }
    property var detail: ({ kind: "" })
    property var history: []
    property bool autoSelected: false

    readonly property bool compact: root.width < 980
    readonly property real listWidth: root.width >= 1500 ? FootballStyle.listPaneWidthWide : FootballStyle.listPaneWidth
    readonly property real detailLayoutWidth: root.compact ? root.width - FootballStyle.railWidth - FootballStyle.gap
        : root.width - FootballStyle.railWidth - root.listWidth - FootballStyle.gap * 2 - FootballStyle.panePadding * 2

    property bool subscribed: false
    function syncSubscription() {
        if (root.isTabActive && !root.subscribed) {
            FootballService.acquire();
            root.subscribed = true;
        } else if (!root.isTabActive && root.subscribed) {
            FootballService.release();
            root.subscribed = false;
        }
    }
    onIsTabActiveChanged: root.syncSubscription()
    Component.onCompleted: {
        root.syncSubscription();
        FootballService.watchedDay = FootballService.dayKey(root.selectedDate);
        Qt.callLater(root.autoSelect);
    }
    Component.onDestruction: {
        if (root.subscribed)
            FootballService.release();
    }
    onSelectedDateChanged: {
        FootballService.watchedDay = FootballService.dayKey(root.selectedDate);
        root.autoSelected = false;
    }

    // ── Navigation ───────────────────────────────────────────────────────────
    function show(next, remember) {
        if (remember && root.detail.kind !== "")
            root.history = root.history.concat([root.detail]).slice(-20);
        root.detail = next;
    }
    function openMatch(match, remember = true) {
        if (!match?.id)
            return;
        if (root.detail.kind === "match" && root.detail.match?.id === match.id)
            return;
        root.show({ kind: "match", match: match }, remember);
    }
    function openLeague(slug, remember = true) {
        root.show({ kind: "league", slug: slug }, remember);
    }
    function openTeam(team, remember = true) {
        if (!team?.id)
            return;
        root.show({ kind: "team", team: team }, remember);
    }
    function back() {
        if (root.history.length === 0) {
            if (root.compact && root.detail.kind !== "") {
                root.detail = { kind: "" };
                return true;
            }
            return false;
        }
        const previous = root.history[root.history.length - 1];
        root.history = root.history.slice(0, -1);
        root.detail = previous;
        return true;
    }

    // The first time a day's matches arrive, open the most interesting one
    // (live, else the next to start, else the latest) so the page never
    // opens on an empty detail pane.
    Connections {
        target: FootballService
        function onDayCacheChanged() {
            root.autoSelect();
        }
    }
    function autoSelect() {
        if (root.autoSelected || root.destination !== "matches" || root.detail.kind !== "" || root.compact)
            return;
        const matches = FootballService.dayCache[FootballService.dayKey(root.selectedDate)]?.matches ?? [];
        if (matches.length === 0)
            return;
        const favorites = FootballService.favoriteIds();
        const pick = matches.find(match => match.state === "in" && (favorites.indexOf(match.home.id) !== -1 || favorites.indexOf(match.away.id) !== -1))
            ?? matches.find(match => match.state === "in")
            ?? matches.find(match => match.state === "pre")
            ?? matches[matches.length - 1];
        root.autoSelected = true;
        root.openMatch(pick, false);
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && root.back())
            event.accepted = true;
        else if (event.key === Qt.Key_Backspace && (event.modifiers & Qt.AltModifier) && root.back())
            event.accepted = true;
    }

    RowLayout {
        anchors.fill: parent
        spacing: FootballStyle.gap

        // ── Rail ─────────────────────────────────────────────────────────────
        ColumnLayout {
            // A nested layout fills width by default and would swallow the row.
            Layout.fillWidth: false
            Layout.preferredWidth: FootballStyle.railWidth
            Layout.maximumWidth: FootballStyle.railWidth
            Layout.fillHeight: true
            spacing: 2

            Repeater {
                id: railRepeater
                model: [
                    { id: "matches", symbol: "sports_soccer", label: Translation.tr("Games") },
                    { id: "leagues", symbol: "emoji_events", label: Translation.tr("Competitions") },
                    { id: "teams", symbol: "shield", label: Translation.tr("Teams") }
                ]
                delegate: ClockRailItem {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    expanded: false
                    rowHeight: 64
                    symbol: modelData.symbol
                    label: modelData.label
                    current: root.destination === modelData.id
                    isFirst: index === 0
                    isLast: index === 2
                    prevIsCurrent: index > 0 && root.destination === ["matches", "leagues", "teams"][index - 1]
                    nextIsCurrent: index < 2 && root.destination === ["matches", "leagues", "teams"][index + 1]
                    badge: modelData.id === "teams" && FootballService.favoriteTeams.length > 0 ? String(FootballService.favoriteTeams.length) : ""
                    onTriggered: root.destination = modelData.id
                }
            }
            Item {
                Layout.fillHeight: true
            }
        }

        // ── List pane ────────────────────────────────────────────────────────
        Loader {
            id: listLoader
            Layout.preferredWidth: root.compact ? -1 : root.listWidth
            Layout.fillWidth: root.compact
            Layout.fillHeight: true
            visible: !root.compact || root.detail.kind === ""
            sourceComponent: root.destination === "leagues" ? leagueList
                : root.destination === "teams" ? teamList : matchList
        }

        // ── Detail pane ──────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.compact || root.detail.kind !== ""
            radius: FootballStyle.radiusCard
            color: FootballStyle.colPane

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: FootballStyle.panePadding
                spacing: FootballStyle.gapSmall

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.history.length > 0 || (root.compact && root.detail.kind !== "")
                    spacing: FootballStyle.gapSmall
                    ClockIconButton {
                        symbol: "arrow_back"
                        tooltip: Translation.tr("Back")
                        onClicked: root.back()
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            const previous = root.history[root.history.length - 1];
                            if (!previous)
                                return "";
                            if (previous.kind === "match")
                                return `${previous.match?.home?.name ?? ""} – ${previous.match?.away?.name ?? ""}`;
                            if (previous.kind === "team")
                                return previous.team?.name ?? "";
                            return FootballService.leagueBySlug(previous.slug)?.name ?? "";
                        }
                        elide: Text.ElideRight
                        font.pixelSize: FootballStyle.textSmall
                        color: FootballStyle.colSubtext
                    }
                }

                Loader {
                    id: detailLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    sourceComponent: root.detail.kind === "match" ? matchDetail
                        : root.detail.kind === "league" ? leagueDetail
                        : root.detail.kind === "team" ? teamDetail : emptyDetail

                    // Tab-switch motion: fade in while rising 24 px.
                    onLoaded: {
                        if (FootballStyle.reducedMotion)
                            return;
                        item.opacity = 0;
                        enterAnimation.restart();
                    }
                    ParallelAnimation {
                        id: enterAnimation
                        NumberAnimation { target: detailLoader.item; property: "opacity"; from: 0; to: 1; duration: FootballStyle.motionEnter.duration; easing.type: Easing.OutCubic }
                        NumberAnimation { target: detailTranslate; property: "y"; from: 24; to: 0; duration: FootballStyle.motionEnter.duration; easing.type: Easing.OutCubic }
                    }
                    transform: Translate { id: detailTranslate }
                }
            }
        }
    }

    // ── Components ───────────────────────────────────────────────────────────

    Component {
        id: matchList
        MatchListPane {
            selectedDate: root.selectedDate
            filter: root.filter
            selectedMatchId: root.detail.kind === "match" ? (root.detail.match?.id ?? "") : ""
            onDateChosen: value => root.selectedDate = value
            onFilterChosen: value => root.filter = value
            onMatchActivated: match => {
                root.history = [];
                root.openMatch(match, false);
            }
        }
    }

    Component {
        id: leagueList
        LeagueListPane {
            selectedSlug: root.detail.kind === "league" ? root.detail.slug : ""
            onLeagueActivated: slug => {
                root.history = [];
                root.openLeague(slug, false);
            }
        }
    }

    Component {
        id: teamList
        TeamListPane {
            selectedTeamId: root.detail.kind === "team" ? String(root.detail.team?.id ?? "") : ""
            onTeamActivated: team => {
                root.history = [];
                root.openTeam(team, false);
            }
        }
    }

    Component {
        id: matchDetail
        MatchDetailView {
            baseMatch: root.detail.match ?? null
            layoutWidth: root.detailLayoutWidth
            onTeamActivated: team => root.openTeam(team)
            onMatchActivated: match => root.openMatch(match)
        }
    }

    Component {
        id: leagueDetail
        LeagueDetailView {
            slug: root.detail.slug ?? ""
            layoutWidth: root.detailLayoutWidth
            onTeamActivated: team => root.openTeam(team)
            onMatchActivated: match => root.openMatch(match)
        }
    }

    Component {
        id: teamDetail
        TeamDetailView {
            baseTeam: root.detail.team ?? null
            layoutWidth: root.detailLayoutWidth
            onTeamActivated: team => root.openTeam(team)
            onMatchActivated: match => root.openMatch(match)
            onLeagueActivated: slug => root.openLeague(slug)
        }
    }

    Component {
        id: emptyDetail
        Item {
            ClockEmptyState {
                anchors.centerIn: parent
                width: Math.min(parent.width, 420)
                symbol: root.destination === "leagues" ? "emoji_events" : root.destination === "teams" ? "shield" : "sports_soccer"
                shape: root.destination === "leagues" ? "Sunny" : root.destination === "teams" ? "Clover4Leaf" : "Cookie12Sided"
                title: root.destination === "leagues" ? Translation.tr("Pick a competition")
                    : root.destination === "teams" ? Translation.tr("Pick a team") : Translation.tr("Pick a match")
                subtitle: root.destination === "leagues" ? Translation.tr("Its table and current round open here")
                    : root.destination === "teams" ? Translation.tr("Fixtures, results and its table open here")
                    : Translation.tr("Lineups, timeline, statistics and more open here")
            }
        }
    }
}
