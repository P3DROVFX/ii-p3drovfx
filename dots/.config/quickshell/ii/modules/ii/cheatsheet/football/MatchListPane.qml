import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.services
import "FootballFormat.js" as Format

/**
 * Matches of a day: a five-day strip around the chosen date, filter chips
 * (all, live, favourites) and the list grouped by competition, favourites on
 * top. Rows are written by position into a ListModel, so a live refresh only
 * updates what changed instead of rebuilding the list.
 */
Rectangle {
    id: root

    property date selectedDate: new Date()
    property string filter: "all"
    property string selectedMatchId: ""

    signal matchActivated(var match)
    signal dateChosen(date value)
    signal filterChosen(string value)

    readonly property string dayKey: FootballService.dayKey(root.selectedDate)
    readonly property var dayEntry: FootballService.dayCache[root.dayKey] ?? null
    readonly property var matches: root.dayEntry?.matches ?? []
    readonly property bool loading: root.dayEntry?.pending === true && root.matches.length === 0
    readonly property int liveCount: root.matches.filter(match => match.state === "in").length
    readonly property var locale: Qt.locale(Translation.languageCode)

    property var matchById: ({})

    color: FootballStyle.colPane
    radius: FootballStyle.radiusCard

    // Deferred: requesting writes the cache this pane's bindings read, which
    // inside a binding evaluation is a loop.
    function load() {
        FootballService.requestDay(root.dayKey);
        root.rebuild();
    }
    Component.onCompleted: Qt.callLater(root.load)

    Connections {
        target: FootballService
        function onDayCacheChanged() {
            root.rebuild();
        }
        function onFavoriteTeamsChanged() {
            root.rebuild();
        }
    }
    onFilterChanged: root.rebuild()
    onDayKeyChanged: Qt.callLater(root.load)

    ListModel {
        id: rows
    }

    function rebuild() {
        const favorites = FootballService.favoriteIds();
        const isFavorite = match => favorites.indexOf(match.home.id) !== -1 || favorites.indexOf(match.away.id) !== -1;
        let list = root.matches;
        if (root.filter === "live")
            list = list.filter(match => match.state === "in");
        else if (root.filter === "favorites")
            list = list.filter(isFavorite);

        const groups = [];
        const favoriteMatches = root.filter === "all" ? list.filter(isFavorite) : [];
        if (favoriteMatches.length > 0)
            groups.push({ key: "favorites", title: Translation.tr("Your teams"), logo: "", symbol: "star", matches: favoriteMatches });
        const order = FootballService.enabledLeagues;
        const byLeague = ({});
        list.forEach(match => {
            if (favoriteMatches.indexOf(match) !== -1)
                return;
            const slug = match.league?.slug ?? "";
            if (!byLeague[slug])
                byLeague[slug] = { key: slug, title: match.league?.name ?? "", logo: match.league?.logo ?? "", symbol: "", matches: [] };
            byLeague[slug].matches.push(match);
        });
        Object.keys(byLeague).sort((left, right) => order.indexOf(left) - order.indexOf(right))
            .forEach(slug => groups.push(byLeague[slug]));

        const map = ({});
        const flat = [];
        groups.forEach(group => {
            flat.push({ kind: "header", key: `h:${group.key}`, title: group.title, logo: group.logo, symbol: group.symbol, first: false, last: false, count: group.matches.length });
            group.matches.forEach((match, index) => {
                map[match.id] = match;
                flat.push({ kind: "match", key: match.id, title: "", logo: "", symbol: "", first: index === 0, last: index === group.matches.length - 1, count: 0 });
            });
        });
        root.matchById = map;
        for (let i = 0; i < flat.length; i++) {
            if (i < rows.count)
                rows.set(i, flat[i]);
            else
                rows.append(flat[i]);
        }
        if (rows.count > flat.length)
            rows.remove(flat.length, rows.count - flat.length);
    }

    // Next-row lookups for the grouped selection notch.
    function keyAt(index) {
        return index >= 0 && index < rows.count ? rows.get(index).key : "";
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: FootballStyle.panePadding
        spacing: FootballStyle.gap

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: FootballStyle.gapSmall

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: Translation.tr("Games")
                    font.pixelSize: FootballStyle.textHuge + 8
                    font.variableAxes: FootballStyle.axesPaneTitle
                    color: FootballStyle.colOnPane
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Format.longDate(root.selectedDate, root.locale)
                    elide: Text.ElideRight
                    font.pixelSize: FootballStyle.textSmall
                    color: FootballStyle.colSubtext
                }
            }
            ClockIconButton {
                symbol: "today"
                tooltip: Translation.tr("Today")
                visible: Format.dayOffset(root.selectedDate) !== 0
                onClicked: root.dateChosen(new Date())
            }
            ClockIconButton {
                symbol: "refresh"
                tooltip: Translation.tr("Refresh")
                onClicked: FootballService.requestDay(root.dayKey, true)
            }
        }

        // Day strip
        RowLayout {
            Layout.fillWidth: true
            spacing: FootballStyle.gapTiny

            ClockIconButton {
                symbol: "chevron_left"
                tooltip: Translation.tr("Previous day")
                onClicked: root.dateChosen(Format.addDays(root.selectedDate, -1))
            }

            Repeater {
                model: 5
                delegate: RippleButton {
                    id: dayButton
                    required property int index
                    readonly property date day: Format.addDays(root.selectedDate, index - 2)
                    readonly property int offset: Format.dayOffset(day)
                    readonly property bool current: index === 2

                    Layout.fillWidth: true
                    implicitHeight: 56
                    toggled: dayButton.current
                    buttonRadius: dayButton.current ? FootballStyle.radiusNormal : 28
                    buttonRadiusPressed: FootballStyle.radiusSmall
                    colBackground: dayButton.offset === 0 ? FootballStyle.colSecondaryContainer : FootballStyle.colRow
                    colBackgroundHover: dayButton.offset === 0 ? FootballStyle.colSecondaryContainerHover : FootballStyle.colRowHover
                    colBackgroundToggled: FootballStyle.colPrimary
                    colBackgroundToggledHover: FootballStyle.colPrimaryHover
                    colRippleToggled: FootballStyle.colPrimaryActive
                    onClicked: root.dateChosen(dayButton.day)

                    readonly property color colContent: dayButton.current ? FootballStyle.colOnPrimary
                        : dayButton.offset === 0 ? FootballStyle.colOnSecondaryContainer : FootballStyle.colOnSurfaceVariant

                    contentItem: Column {
                        anchors.centerIn: parent
                        spacing: 0
                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: dayButton.offset === 0 ? Translation.tr("Today")
                                : dayButton.offset === -1 ? Translation.tr("Yest.")
                                : dayButton.offset === 1 ? Translation.tr("Tom.")
                                : dayButton.day.toLocaleDateString(root.locale, "ddd")
                            font.pixelSize: FootballStyle.textSmallest
                            font.weight: Font.Bold
                            color: dayButton.colContent
                        }
                        StyledText {
                            shouldUseNumberFont: false
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: dayButton.day.getDate()
                            font.pixelSize: FootballStyle.textLarger
                            font.variableAxes: dayButton.current ? FootballStyle.axesScoreHeavy : FootballStyle.axesScoreIdle
                            color: dayButton.colContent
                        }
                    }
                }
            }

            ClockIconButton {
                symbol: "chevron_right"
                tooltip: Translation.tr("Next day")
                onClicked: root.dateChosen(Format.addDays(root.selectedDate, 1))
            }
        }

        // Filters
        Flow {
            Layout.fillWidth: true
            spacing: FootballStyle.gapSmall

            ClockChip {
                symbol: "sports_soccer"
                label: Translation.tr("All")
                selected: root.filter === "all"
                onClicked: root.filterChosen("all")
            }
            ClockChip {
                symbol: "radio_button_checked"
                label: root.liveCount > 0 ? `${Translation.tr("Live")} · ${root.liveCount}` : Translation.tr("Live")
                selected: root.filter === "live"
                onClicked: root.filterChosen("live")
            }
            ClockChip {
                symbol: "star"
                label: Translation.tr("Favorites")
                selected: root.filter === "favorites"
                onClicked: root.filterChosen("favorites")
            }
        }

        // List
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                spacing: 2
                model: rows
                boundsBehavior: Flickable.StopAtBounds
                visible: rows.count > 0

                delegate: Loader {
                    id: rowLoader
                    required property int index
                    required property string kind
                    required property string key
                    required property string title
                    required property string logo
                    required property string symbol
                    required property bool first
                    required property bool last
                    required property int count

                    width: ListView.view.width
                    sourceComponent: rowLoader.kind === "header" ? headerComponent : matchComponent

                    Component {
                        id: headerComponent
                        RowLayout {
                            height: 40
                            spacing: FootballStyle.gapSmall
                            Item { implicitWidth: 2 }
                            TeamCrest {
                                visible: rowLoader.symbol === ""
                                size: 24
                                source: rowLoader.logo
                                plate: "transparent"
                            }
                            MaterialSymbol {
                                visible: rowLoader.symbol !== ""
                                text: rowLoader.symbol
                                fill: 1
                                iconSize: 20
                                color: FootballStyle.colPrimary
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: rowLoader.title.toUpperCase()
                                elide: Text.ElideRight
                                font.pixelSize: FootballStyle.textSmaller
                                font.variableAxes: FootballStyle.axesCaps
                                font.letterSpacing: 1.2
                                color: FootballStyle.colOnSurfaceVariant
                            }
                            StyledText {
                                text: rowLoader.count
                                font.pixelSize: FootballStyle.textSmaller
                                font.weight: Font.Bold
                                color: FootballStyle.colSubtext
                            }
                            Item { implicitWidth: 4 }
                        }
                    }

                    Component {
                        id: matchComponent
                        MatchRow {
                            match: root.matchById[rowLoader.key] ?? null
                            selected: rowLoader.key === root.selectedMatchId
                            isFirst: rowLoader.first
                            isLast: rowLoader.last
                            prevSelected: !rowLoader.first && root.keyAt(rowLoader.index - 1) === root.selectedMatchId
                            nextSelected: !rowLoader.last && root.keyAt(rowLoader.index + 1) === root.selectedMatchId
                            onClicked: if (match) root.matchActivated(match)
                        }
                    }
                }
            }

            ScrollEdgeFade {
                target: list
                color: FootballStyle.colPane
            }

            StyledIndeterminateProgressBar {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                visible: root.dayEntry?.pending === true
            }

            ClockEmptyState {
                anchors.centerIn: parent
                width: parent.width
                visible: rows.count === 0 && !root.loading
                symbol: FootballService.enabledLeagues.length === 0 ? "emoji_events"
                    : root.filter === "favorites" ? "star" : root.filter === "live" ? "radio_button_checked" : "sports_soccer"
                shape: "Cookie12Sided"
                title: FootballService.enabledLeagues.length === 0 ? Translation.tr("No competitions followed")
                    : root.dayEntry?.error ? root.dayEntry.error
                    : root.filter === "live" ? Translation.tr("Nothing live right now")
                    : root.filter === "favorites" ? Translation.tr("Your teams don't play this day")
                    : Translation.tr("No matches this day")
                subtitle: FootballService.enabledLeagues.length === 0 ? Translation.tr("Follow competitions in the Competitions tab")
                    : root.filter === "favorites" && FootballService.favoriteTeams.length === 0 ? Translation.tr("Star teams in the Teams tab to see them here")
                    : Translation.tr("Try another day or filter")
            }
        }
    }
}
