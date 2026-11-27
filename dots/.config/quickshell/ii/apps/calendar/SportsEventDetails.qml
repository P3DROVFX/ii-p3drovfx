import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import "SportsDetailsHelpers.js" as SportsDetailsH

/**
 * Read-only ESPN projection used by both timetable views.
 *
 * Scoreboard data paints immediately from SportsService's weekly cache. The
 * heavier summary payload is requested only when this panel opens and adds
 * line-ups, box score, leaders, key events, officials and ESPN links when the
 * selected sport exposes them.
 */
Item {
    id: root

    property var game: null
    property var details: null
    property bool loading: false
    property string error: ""

    implicitHeight: content.implicitHeight

    readonly property var headerCompetition: {
        const values = root.details?.header?.competitions;
        return Array.isArray(values) && values.length > 0 ? values[0] : null;
    }
    readonly property var gameInfo: root.details?.gameInfo ?? null
    readonly property var keyEvents: Array.isArray(root.details?.keyEvents)
        ? root.details.keyEvents
        : (Array.isArray(root.headerCompetition?.details) ? root.headerCompetition.details : [])
    readonly property var lineupRows: SportsDetailsH.lineupRows(root.details?.rosters ?? [])
    readonly property var statisticsRows: SportsDetailsH.statisticsRows(root.details?.boxscore?.teams ?? [])
    readonly property var leaderRows: SportsDetailsH.leaderRows(root.details?.leaders ?? [])
    readonly property var keyEventRows: SportsDetailsH.keyEventRows(root.keyEvents)
    readonly property var externalLinks: root.collectLinks()

    function text(value): string {
        return String(value ?? "").trim();
    }

    function collectLinks(): var {
        const result = [];
        const seen = ({});
        function append(values, depth = 0) {
            if (!values || depth > 4)
                return;
            const list = Array.isArray(values) ? values : (typeof values === "object" ? Object.values(values) : []);
            for (let i = 0; i < list.length; i++) {
                const item = list[i] ?? ({});
                const href = root.text(item.href);
                if (href.length === 0) {
                    append(item, depth + 1);
                    continue;
                }
                if (!/^https?:\/\//.test(href) || seen[href])
                    continue;
                seen[href] = true;
                result.push({
                    href: href,
                    label: root.text(item.text || item.shortText || item.label || Translation.tr("Open in ESPN"))
                });
            }
        }
        append(root.game?.links);
        append(root.details?.header?.links);
        append(root.details?.header?.linksv4);
        append(root.details?.links);

        const newsValue = root.details?.news ?? null;
        const news = Array.isArray(newsValue) ? newsValue : (Array.isArray(newsValue?.articles) ? newsValue.articles : []);
        for (let i = 0; i < news.length; i++)
            append(news[i]?.links?.web ? [news[i].links.web] : news[i]?.links);
        const videos = Array.isArray(root.details?.videos) ? root.details.videos : [];
        for (let i = 0; i < videos.length; i++)
            append(videos[i]?.links?.web ? [videos[i].links.web] : videos[i]?.links);
        return result;
    }

    function venueName(): string {
        return root.text(root.gameInfo?.venue?.fullName || root.game?.venue?.name || root.game?.location);
    }

    function venueAddress(): string {
        const address = root.gameInfo?.venue?.address ?? ({});
        const values = [address.city, address.state, address.country].map(root.text).filter(value => value.length > 0);
        return values.length > 0 ? values.join(", ") : root.text(root.game?.venue?.address);
    }

    function broadcastsText(): string {
        const values = [];
        const cached = Array.isArray(root.game?.broadcasts) ? root.game.broadcasts : [];
        for (let i = 0; i < cached.length; i++) {
            const name = root.text(cached[i]);
            if (name.length > 0 && !values.includes(name))
                values.push(name);
        }
        const groups = Array.isArray(root.details?.broadcasts) ? root.details.broadcasts : [];
        for (let i = 0; i < groups.length; i++) {
            const names = Array.isArray(groups[i]?.names) ? groups[i].names : [];
            for (let j = 0; j < names.length; j++) {
                const name = root.text(names[j]);
                if (name.length > 0 && !values.includes(name))
                    values.push(name);
            }
        }
        return values.join(", ");
    }

    function officialsText(): string {
        const officials = Array.isArray(root.gameInfo?.officials) ? root.gameInfo.officials : [];
        return officials.map(item => {
            const role = root.text(item?.position?.displayName || item?.position?.name);
            const name = root.text(item?.displayName || item?.fullName);
            return role.length > 0 ? `${role}: ${name}` : name;
        }).filter(value => value.length > 0).join("\n");
    }

    function oddsText(): string {
        const values = Array.isArray(root.details?.odds) ? root.details.odds : [];
        const lines = [];
        for (let i = 0; i < values.length; i++) {
            const item = values[i];
            if (!item)
                continue;
            const provider = root.text(item.provider?.name || item.provider?.displayName);
            const detail = root.text(item.details || item.overUnder || item.spread);
            const home = root.text(item.homeTeamOdds?.moneyLine || item.homeTeamOdds?.odds);
            const away = root.text(item.awayTeamOdds?.moneyLine || item.awayTeamOdds?.odds);
            lines.push([provider, detail, home.length > 0 ? `Home ${home}` : "", away.length > 0 ? `Away ${away}` : ""].filter(value => value.length > 0).join(" · "));
        }
        return lines.join("\n");
    }

    function seasonText(): string {
        const season = root.details?.header?.season ?? root.game?.season ?? null;
        if (!season)
            return "";
        return root.text(season.name || season.displayName || season.year);
    }

    function weatherText(): string {
        const weather = root.gameInfo?.weather ?? root.headerCompetition?.weather ?? null;
        if (!weather)
            return "";
        const temperature = root.text(weather.temperature?.displayValue || weather.temperature);
        const condition = root.text(weather.displayValue || weather.conditionId || weather.type);
        return [temperature, condition].filter(value => value.length > 0).join(" · ");
    }

    function formatText(): string {
        const regulation = root.details?.format?.regulation ?? null;
        if (!regulation)
            return "";
        const periods = Number(regulation.periods ?? 0);
        const periodName = root.text(regulation.displayName || regulation.name);
        const clockSeconds = Number(regulation.clock ?? 0);
        const clock = clockSeconds > 0 ? `${Math.round(clockSeconds / 60)} min` : "";
        return [periods > 0 ? `${periods} × ${periodName}` : periodName, clock].filter(value => value.length > 0).join(" · ");
    }

    function commentaryText(): string {
        const values = Array.isArray(root.details?.commentary) ? root.details.commentary : [];
        return values.slice(Math.max(0, values.length - 12)).reverse().map(item => {
            const clock = root.text(item?.time?.displayValue || item?.clock?.displayValue);
            const body = root.text(item?.text || item?.description);
            return clock.length > 0 ? `${clock} · ${body}` : body;
        }).filter(value => value.length > 0).join("\n");
    }

    function recentFormText(): string {
        const groups = Array.isArray(root.details?.lastFiveGames) ? root.details.lastFiveGames : [];
        const lines = [];
        for (let i = 0; i < groups.length; i++) {
            const group = groups[i] ?? ({});
            const team = root.text(group.team?.displayName || group.team?.name);
            const events = Array.isArray(group.events) ? group.events : [];
            const matches = events.map(item => {
                const opponent = root.text(item?.opponent?.displayName || item?.opponent?.name || item?.name);
                const score = root.text(item?.score || item?.result || item?.scoreValue);
                return [opponent, score].filter(value => value.length > 0).join(" ");
            }).filter(value => value.length > 0);
            if (team.length > 0 && matches.length > 0)
                lines.push(`${team}: ${matches.join(" · ")}`);
        }
        return lines.join("\n");
    }

    function seasonSeriesText(): string {
        const groups = Array.isArray(root.details?.seasonseries) ? root.details.seasonseries : [];
        const lines = [];
        for (let i = 0; i < groups.length; i++) {
            const events = Array.isArray(groups[i]?.events) ? groups[i].events : [];
            for (let j = 0; j < Math.min(5, events.length); j++) {
                const item = events[j] ?? ({});
                const date = item.date ? Qt.formatDate(new Date(item.date), "d MMM yyyy") : "";
                const competitors = Array.isArray(item.competitors) ? item.competitors : [];
                const matchup = competitors.map(value => {
                    const name = root.text(value?.team?.displayName || value?.team?.name);
                    const score = root.text(value?.score || value?.displayValue);
                    return [name, score].filter(part => part.length > 0).join(" ");
                }).filter(value => value.length > 0).join(" × ");
                const label = root.text(item.name || item.shortName || item.summary) || matchup;
                const line = [date, label].filter(value => value.length > 0).join(" · ");
                if (line.length > 0)
                    lines.push(line);
            }
        }
        return lines.join("\n");
    }

    function newsText(): string {
        const news = root.details?.news ?? null;
        const articles = Array.isArray(news) ? news : (Array.isArray(news?.articles) ? news.articles : []);
        return articles.slice(0, 6).map(item => {
            const headline = root.text(item?.headline || item?.title);
            const byline = root.text(item?.byline);
            return byline.length > 0 ? `${headline} · ${byline}` : headline;
        }).filter(value => value.length > 0).join("\n");
    }

    function videosText(): string {
        const videos = Array.isArray(root.details?.videos) ? root.details.videos : [];
        return videos.slice(0, 6).map(item => root.text(item?.headline || item?.title || item?.description)).filter(value => value.length > 0).join("\n");
    }

    function injuriesText(): string {
        const groups = Array.isArray(root.details?.injuries) ? root.details.injuries : [];
        const lines = [];
        for (let i = 0; i < groups.length; i++) {
            const group = groups[i] ?? ({});
            const team = root.text(group.team?.displayName || group.team?.name);
            const injuries = Array.isArray(group.injuries) ? group.injuries : (Array.isArray(group.items) ? group.items : []);
            for (let j = 0; j < injuries.length; j++) {
                const item = injuries[j] ?? ({});
                const athlete = root.text(item.athlete?.displayName || item.athlete?.fullName || item.displayName || item.name);
                const status = root.text(item.status || item.type?.description || item.details?.detail || item.description);
                const value = [team, athlete, status].filter(part => part.length > 0).join(" · ");
                if (value.length > 0)
                    lines.push(value);
            }
        }
        return lines.join("\n");
    }

    function standingsText(): string {
        const collected = [];
        function visit(value, depth = 0) {
            if (!value || depth > 6)
                return;
            if (Array.isArray(value)) {
                for (let i = 0; i < value.length; i++)
                    visit(value[i], depth + 1);
                return;
            }
            if (typeof value !== "object")
                return;
            if (Array.isArray(value.entries)) {
                for (let i = 0; i < value.entries.length; i++)
                    collected.push(value.entries[i]);
            }
            if (Array.isArray(value.groups))
                visit(value.groups, depth + 1);
        }
        visit(root.details?.standings);
        const teamNames = [root.text(root.game?.home?.name), root.text(root.game?.away?.name)].map(value => value.toLowerCase()).filter(value => value.length > 0);
        const selected = collected.filter(item => {
            const name = root.text(typeof item?.team === "string" ? item.team : (item?.team?.displayName || item?.team?.name)).toLowerCase();
            return teamNames.some(team => name.includes(team) || team.includes(name));
        });
        return selected.map(item => {
            const name = root.text(typeof item?.team === "string" ? item.team : (item?.team?.displayName || item?.team?.name));
            const stats = Array.isArray(item?.stats) ? item.stats : [];
            const wanted = ["rank", "points", "overall", "wins", "ties", "losses"];
            const values = [];
            for (let i = 0; i < wanted.length; i++) {
                const stat = stats.find(entry => root.text(entry?.name || entry?.type).toLowerCase() === wanted[i]);
                if (!stat)
                    continue;
                const label = root.text(stat.abbreviation || stat.shortDisplayName || stat.displayName || stat.name);
                const value = root.text(stat.displayValue || stat.summary || stat.value);
                if (label.length > 0 && value.length > 0)
                    values.push(`${label} ${value}`);
            }
            return [name, values.join(" · ")].filter(value => value.length > 0).join(": ");
        }).filter(value => value.length > 0).join("\n");
    }

    function availableSectionsText(): string {
        if (!root.details)
            return "";
        return Object.keys(root.details).filter(key => root.details[key] !== null && root.details[key] !== undefined).sort().join(", ");
    }

    ColumnLayout {
        id: content
        width: parent.width
        spacing: 12

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 176
            radius: Appearance.rounding.large
            color: Appearance.colors.colTertiaryContainer

            Item {
                anchors.fill: parent
                anchors.margins: 14

                TeamSummary {
                    id: homeSummary
                    // The team columns are bounded by the fixed center
                    // column, rather than participating in its size
                    // negotiation. A long club name can therefore only wrap
                    // inside its own side and never move the score or rival.
                    anchors {
                        left: parent.left
                        right: scoreSection.left
                        rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    teamData: root.game?.home ?? null
                }

                ColumnLayout {
                    id: scoreSection
                    anchors.centerIn: parent
                    width: 82
                    spacing: 4

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.game?.state === "pre"
                            ? Qt.formatTime(root.game?.startDate ?? new Date(), Config.options.time.format)
                            : `${root.text(root.game?.home?.score || "0")} – ${root.text(root.game?.away?.score || "0")}`
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnTertiaryContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.text(root.game?.status)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnTertiaryContainer
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }

                TeamSummary {
                    id: awaySummary
                    anchors {
                        left: scoreSection.right
                        leftMargin: 10
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    teamData: root.game?.away ?? null
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 6

            InfoChip { symbol: "trophy"; label: root.text(root.game?.league) }
            InfoChip { symbol: "calendar_month"; label: Qt.formatDate(root.game?.startDate ?? new Date(), "ddd, d MMM yyyy") }
            InfoChip { symbol: "schedule"; label: Qt.formatTime(root.game?.startDate ?? new Date(), Config.options.time.format) }
            InfoChip { visible: root.game?.state === "in"; symbol: "sensors"; label: Translation.tr("Live") }
        }

        DetailRow {
            visible: root.venueName().length > 0
            symbol: "stadium"
            caption: Translation.tr("Venue")
            value: root.venueName()
        }

        DetailRow {
            visible: root.venueAddress().length > 0
            symbol: "location_on"
            caption: Translation.tr("Location")
            value: root.venueAddress()
        }

        DetailRow {
            visible: root.broadcastsText().length > 0
            symbol: "live_tv"
            caption: Translation.tr("Broadcast")
            value: root.broadcastsText()
        }

        DetailRow {
            visible: Number(root.gameInfo?.attendance ?? root.game?.attendance ?? 0) > 0
            symbol: "groups"
            caption: Translation.tr("Attendance")
            value: Number(root.gameInfo?.attendance ?? root.game?.attendance ?? 0).toLocaleString()
        }

        DetailRow {
            visible: root.seasonText().length > 0
            symbol: "workspace_premium"
            caption: Translation.tr("Season")
            value: root.seasonText()
        }

        DetailRow {
            visible: root.officialsText().length > 0
            symbol: "sports"
            caption: Translation.tr("Officials")
            value: root.officialsText()
            multiline: true
        }

        DetailRow {
            visible: root.weatherText().length > 0
            symbol: "partly_cloudy_day"
            caption: Translation.tr("Conditions")
            value: root.weatherText()
        }

        DetailRow {
            visible: root.formatText().length > 0
            symbol: "timer"
            caption: Translation.tr("Match format")
            value: root.formatText()
        }

        SectionTitle {
            visible: root.externalLinks.length > 0
            symbol: "link"
            label: Translation.tr("ESPN links")
        }

        Flow {
            Layout.fillWidth: true
            visible: root.externalLinks.length > 0
            spacing: 6

            Repeater {
                model: root.externalLinks

                delegate: RippleButtonWithIcon {
                    required property var modelData
                    implicitWidth: contentImplicitWidth + 26
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.full
                    centerContent: true
                    materialIcon: "open_in_new"
                    mainText: modelData.label
                    textPixelSize: Appearance.font.pixelSize.smallest
                    colText: Appearance.colors.colOnSecondaryContainer
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    onClicked: Qt.openUrlExternally(modelData.href)
                }
            }
        }

        DetailRow {
            visible: root.game?.lastPlay?.length > 0
            symbol: "update"
            caption: Translation.tr("Latest update")
            value: root.text(root.game?.lastPlay)
            multiline: true
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 54
            visible: root.loading && root.details === null
            radius: Appearance.rounding.small
            color: Appearance.colors.colSurfaceContainerHighest

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                MaterialSymbol {
                    text: "sync"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Loading match details…")
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                }
            }
        }

        DetailRow {
            visible: root.error.length > 0 && root.details === null
            symbol: "cloud_off"
            caption: Translation.tr("Details unavailable")
            value: root.error
            multiline: true
        }

        SectionTitle {
            visible: root.details !== null
            symbol: "groups"
            label: Translation.tr("Line-ups")
        }

        EmptySection {
            Layout.fillWidth: true
            visible: root.details !== null && root.lineupRows.length === 0
            symbol: "group_off"
        }

        Repeater {
            model: root.lineupRows

            delegate: DetailRow {
                required property var modelData
                Layout.fillWidth: true
                symbol: modelData.group === "starters" ? "apparel" : "person_add"
                caption: (modelData.team || Translation.tr("Team")) + " · " + (modelData.group === "starters" ? Translation.tr("Starters") : Translation.tr("Substitutes"))
                value: modelData.value
                multiline: true
            }
        }

        SectionTitle {
            visible: root.details !== null
            symbol: "query_stats"
            label: Translation.tr("Team statistics")
        }

        EmptySection {
            Layout.fillWidth: true
            visible: root.details !== null && root.statisticsRows.length === 0
            symbol: "monitoring"
        }

        Repeater {
            model: root.statisticsRows

            delegate: DetailRow {
                required property var modelData
                Layout.fillWidth: true
                symbol: "analytics"
                caption: modelData.team || Translation.tr("Team statistics")
                value: modelData.value
                multiline: true
            }
        }

        SectionTitle {
            visible: root.details !== null
            symbol: "military_tech"
            label: Translation.tr("Leaders")
        }

        EmptySection {
            Layout.fillWidth: true
            visible: root.details !== null && root.leaderRows.length === 0
            symbol: "leaderboard"
        }

        Repeater {
            model: root.leaderRows

            delegate: DetailRow {
                required property var modelData
                Layout.fillWidth: true
                symbol: "star"
                caption: modelData.team || Translation.tr("Leaders")
                value: modelData.value
                multiline: true
            }
        }

        SectionTitle {
            visible: root.keyEventRows.length > 0
            symbol: "timeline"
            label: Translation.tr("Key events")
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.keyEventRows.length > 0
            spacing: 10

            Repeater {
                model: root.keyEventRows

                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                            id: eventTimePill
                            visible: modelData.time.length > 0
                            Layout.alignment: Qt.AlignTop
                            implicitWidth: eventTimeLabel.implicitWidth + 18
                            implicitHeight: 28
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colTertiaryContainer

                            StyledText {
                                id: eventTimeLabel
                                anchors.centerIn: parent
                                text: modelData.time
                                font.family: Appearance.font.family.numbers
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnTertiaryContainer
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                visible: modelData.kind.length > 0 && modelData.kind !== modelData.text
                                text: modelData.kind
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Bold
                                color: Appearance.colors.colPrimary
                                wrapMode: Text.Wrap
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.text
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnSurface
                                wrapMode: Text.Wrap
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        visible: index < root.keyEventRows.length - 1
                        color: Appearance.colors.colOutlineVariant
                    }
                }
            }
        }

        DetailRow {
            Layout.fillWidth: true
            visible: root.oddsText().length > 0
            symbol: "casino"
            caption: Translation.tr("Odds")
            value: root.oddsText()
            multiline: true
        }

        DetailRow {
            Layout.fillWidth: true
            visible: root.commentaryText().length > 0
            symbol: "forum"
            caption: Translation.tr("Latest commentary")
            value: root.commentaryText()
            multiline: true
        }

        DetailRow {
            Layout.fillWidth: true
            visible: root.recentFormText().length > 0
            symbol: "history"
            caption: Translation.tr("Recent form")
            value: root.recentFormText()
            multiline: true
        }

        DetailRow {
            Layout.fillWidth: true
            visible: root.seasonSeriesText().length > 0
            symbol: "compare_arrows"
            caption: Translation.tr("Season series")
            value: root.seasonSeriesText()
            multiline: true
        }

        DetailRow {
            Layout.fillWidth: true
            visible: root.newsText().length > 0
            symbol: "newspaper"
            caption: Translation.tr("Related news")
            value: root.newsText()
            multiline: true
        }

        DetailRow {
            Layout.fillWidth: true
            visible: root.videosText().length > 0
            symbol: "smart_display"
            caption: Translation.tr("Videos")
            value: root.videosText()
            multiline: true
        }

        DetailRow {
            Layout.fillWidth: true
            visible: root.injuriesText().length > 0
            symbol: "health_and_safety"
            caption: Translation.tr("Injuries")
            value: root.injuriesText()
            multiline: true
        }

        DetailRow {
            Layout.fillWidth: true
            visible: root.standingsText().length > 0
            symbol: "leaderboard"
            caption: Translation.tr("Standings")
            value: root.standingsText()
            multiline: true
        }

        DetailRow {
            Layout.fillWidth: true
            visible: root.availableSectionsText().length > 0
            symbol: "database"
            caption: Translation.tr("ESPN data retained in cache")
            value: root.availableSectionsText()
            multiline: true
        }
    }

    component TeamSummary: ColumnLayout {
        id: teamSummary
        property var teamData: null
        spacing: 5

        Image {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 58
            Layout.preferredHeight: 58
            source: String(teamSummary.teamData?.logo ?? "")
            sourceSize: Qt.size(58, 58)
            fillMode: Image.PreserveAspectFit
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.text(teamSummary.teamData?.name || Translation.tr("TBD"))
            font.pixelSize: Appearance.font.pixelSize.smallie
            font.weight: Font.Bold
            color: Appearance.colors.colOnTertiaryContainer
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.text(teamSummary.teamData?.record).length > 0
            horizontalAlignment: Text.AlignHCenter
            text: root.text(teamSummary.teamData?.record)
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnTertiaryContainer
        }
    }

    component SectionTitle: RowLayout {
        id: sectionTitle
        property string symbol: ""
        property string label: ""
        Layout.fillWidth: true
        spacing: 8

        MaterialSymbol {
            text: sectionTitle.symbol
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colPrimary
        }

        StyledText {
            Layout.fillWidth: true
            text: sectionTitle.label
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.Bold
            color: Appearance.colors.colOnSurface
        }
    }

    component InfoChip: Rectangle {
        id: infoChip
        property string symbol: ""
        property string label: ""
        implicitWidth: chipRow.implicitWidth + 22
        implicitHeight: 32
        radius: Appearance.rounding.full
        color: Appearance.colors.colSurfaceContainerHighest

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: infoChip.symbol
                iconSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colPrimary
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: infoChip.label
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurface
            }
        }
    }

    component EmptySection: Rectangle {
        id: emptySection
        property string symbol: "info"

        implicitHeight: 46
        radius: Appearance.rounding.small
        color: Appearance.colors.colSurfaceContainerHighest

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 9

            MaterialSymbol {
                text: emptySection.symbol
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Unavailable")
                font.pixelSize: Appearance.font.pixelSize.smallie
                font.weight: Font.Medium
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }

    component DetailRow: Rectangle {
        id: detailRow
        property string symbol: ""
        property string caption: ""
        property string value: ""
        property bool multiline: false

        Layout.fillWidth: true
        implicitHeight: detailLayout.implicitHeight + 20
        radius: Appearance.rounding.small
        color: Appearance.colors.colSurfaceContainerHighest

        RowLayout {
            id: detailLayout
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            MaterialShapeWrappedMaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: detailRow.symbol
                iconSize: Appearance.font.pixelSize.normal
                padding: 8
                shape: MaterialShape.Shape.Cookie6Sided
                color: Appearance.colors.colPrimaryContainer
                colSymbol: Appearance.colors.colOnPrimaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: detailRow.caption
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    Layout.fillWidth: true
                    text: detailRow.value
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnSurface
                    wrapMode: detailRow.multiline ? Text.Wrap : Text.NoWrap
                    elide: Text.ElideRight
                    maximumLineCount: detailRow.multiline ? 100 : 1
                }
            }
        }
    }
}
