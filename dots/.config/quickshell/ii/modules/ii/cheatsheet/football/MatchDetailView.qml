import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.services
import "FootballFormat.js" as Format

/**
 * Everything about one match, like a sports site's match centre: the
 * scoreboard hero with highlights/ESPN actions, then tabs for the summary,
 * lineups, play-by-play, statistics, table, head-to-head and news. Only the
 * current tab is built; tabs without data are not offered.
 */
Item {
    id: root

    property var baseMatch: null
    property real layoutWidth: width
    signal teamActivated(var team)
    signal matchActivated(var match)

    readonly property string matchId: root.baseMatch?.id ?? ""
    readonly property var detail: FootballService.detailCache[root.matchId] ?? null
    // The list's match draws the hero at once; the summary refines it.
    readonly property var match: root.detail ?? root.baseMatch
    readonly property bool wide: root.layoutWidth >= 980
    readonly property var locale: Qt.locale(Translation.languageCode)

    property string tab: "summary"

    readonly property var tabs: {
        const d = root.detail;
        const list = [{ id: "summary", label: Translation.tr("Summary"), symbol: "dashboard" }];
        if (d?.lineups?.length > 0)
            list.push({ id: "lineups", label: Translation.tr("Lineups"), symbol: "groups" });
        if (d?.commentary?.length > 0)
            list.push({ id: "commentary", label: Translation.tr("Play-by-play"), symbol: "forum" });
        if (d?.stats?.length > 0)
            list.push({ id: "stats", label: Translation.tr("Statistics"), symbol: "bar_chart" });
        if (d?.standings?.length > 0)
            list.push({ id: "table", label: Translation.tr("Table"), symbol: "format_list_numbered" });
        if ((d?.headToHead?.games?.length ?? 0) > 0 || (d?.form?.length ?? 0) > 0)
            list.push({ id: "h2h", label: Translation.tr("Head-to-head"), symbol: "compare_arrows" });
        if (d?.news?.length > 0)
            list.push({ id: "news", label: Translation.tr("News"), symbol: "newspaper" });
        return list;
    }

    function load() {
        FootballService.watchedMatch = root.matchId;
        FootballService.requestDetails(root.matchId);
    }
    onMatchIdChanged: {
        root.tab = "summary";
        flick.contentY = 0;
        Qt.callLater(root.load);
    }
    Component.onCompleted: Qt.callLater(root.load)
    Component.onDestruction: {
        if (FootballService.watchedMatch === root.matchId)
            FootballService.watchedMatch = "";
    }
    onTabChanged: {
        if (root.tab === "lineups")
            Qt.callLater(() => FootballService.requestPositions(root.matchId));
    }

    function lineup(side) {
        return (root.detail?.lineups ?? []).find(item => item.side === side) ?? null;
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

            MatchHero {
                Layout.fillWidth: true
                match: root.match
                keyEvents: root.detail?.keyEvents ?? []
                stats: root.detail?.stats ?? []
                layoutWidth: root.layoutWidth
                onTeamActivated: team => root.teamActivated(team)
            }

            // Actions and tabs
            Flow {
                Layout.fillWidth: true
                spacing: FootballStyle.gapSmall

                ClockButton {
                    variant: "filled"
                    symbol: "smart_display"
                    label: root.match?.state === "pre" ? Translation.tr("Preview on YouTube") : Translation.tr("Highlights")
                    onClicked: Qt.openUrlExternally(FootballService.highlightsUrl(root.match))
                }
                ClockButton {
                    variant: "tonal"
                    symbol: "open_in_new"
                    label: "ESPN"
                    onClicked: Qt.openUrlExternally(FootballService.espnUrl(root.match))
                }
                ClockIconButton {
                    symbol: "refresh"
                    tooltip: Translation.tr("Refresh")
                    onClicked: FootballService.requestDetails(root.matchId, true)
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: FootballStyle.gapSmall
                Repeater {
                    model: root.tabs
                    delegate: ClockChip {
                        required property var modelData
                        symbol: modelData.symbol
                        label: modelData.label
                        selected: root.tab === modelData.id
                        onClicked: root.tab = modelData.id
                    }
                }
            }

            StyledIndeterminateProgressBar {
                Layout.fillWidth: true
                visible: !root.detail && FootballService.isLoading(`detail:${root.matchId}`)
            }

            Loader {
                id: tabLoader
                Layout.fillWidth: true
                active: root.matchId !== ""
                sourceComponent: root.tab === "lineups" ? lineupsTab
                    : root.tab === "commentary" ? commentaryTab
                    : root.tab === "stats" ? statsTab
                    : root.tab === "table" ? tableTab
                    : root.tab === "h2h" ? h2hTab
                    : root.tab === "news" ? newsTab : summaryTab
            }
        }
    }

    ScrollEdgeFade {
        target: flick
        color: FootballStyle.colPane
    }

    // ── Shared pieces ────────────────────────────────────────────────────────

    component InfoRow: RowLayout {
        id: info
        property string symbol: ""
        property string caption: ""
        property string value: ""
        property int shape: MaterialShape.Shape.Cookie9Sided
        Layout.fillWidth: true
        visible: info.value !== ""
        spacing: FootballStyle.gap
        MaterialShapeWrappedMaterialSymbol {
            text: info.symbol
            iconSize: 18
            padding: 9
            shape: info.shape
            color: FootballStyle.colPrimaryContainer
            colSymbol: FootballStyle.colOnPrimaryContainer
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                text: info.caption
                font.pixelSize: FootballStyle.textSmallest
                font.weight: Font.Bold
                color: FootballStyle.colOnSurfaceVariant
            }
            StyledText {
                Layout.fillWidth: true
                text: info.value
                elide: Text.ElideRight
                font.pixelSize: FootballStyle.textSmall
                font.weight: Font.Bold
                color: FootballStyle.colOnSurface
            }
        }
    }

    component FormColumn: ColumnLayout {
        id: form
        property var entry: null
        Layout.fillWidth: true
        spacing: FootballStyle.gapSmall
        RowLayout {
            spacing: FootballStyle.gapSmall
            TeamCrest { size: 28; source: form.entry?.logo ?? ""; plate: "transparent" }
            StyledText {
                Layout.fillWidth: true
                text: form.entry?.name ?? ""
                elide: Text.ElideRight
                font.pixelSize: FootballStyle.textNormal
                font.weight: Font.DemiBold
                color: FootballStyle.colOnSurface
            }
            Row {
                spacing: 4
                Repeater {
                    model: form.entry?.games ?? []
                    delegate: Rectangle {
                        required property var modelData
                        width: 24
                        height: 24
                        radius: modelData.result === "W" ? 7 : 12
                        color: modelData.result === "W" ? FootballStyle.colPrimary
                            : modelData.result === "D" ? FootballStyle.colSecondaryContainer : FootballStyle.colField
                        StyledText {
                            anchors.centerIn: parent
                            text: modelData.result === "W" ? FootballService.resultLetter("W") : modelData.result === "D" ? FootballService.resultLetter("D") : FootballService.resultLetter("L")
                            font.pixelSize: FootballStyle.textSmallest
                            font.weight: Font.Black
                            color: modelData.result === "W" ? FootballStyle.colOnPrimary
                                : modelData.result === "D" ? FootballStyle.colOnSecondaryContainer : FootballStyle.colOnSurface
                        }
                    }
                }
            }
        }
        Repeater {
            model: (form.entry?.games ?? []).slice().reverse()
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: FootballStyle.gapSmall
                StyledText {
                    Layout.preferredWidth: 52
                    text: Format.shortDate(modelData.date, root.locale)
                    font.pixelSize: FootballStyle.textSmaller
                    color: FootballStyle.colSubtext
                }
                TeamCrest { size: 20; source: modelData.opponentLogo; plate: "transparent" }
                StyledText {
                    Layout.fillWidth: true
                    text: `${modelData.atVs} ${modelData.opponent}`
                    elide: Text.ElideRight
                    font.pixelSize: FootballStyle.textSmall
                    color: FootballStyle.colOnSurface
                }
                StyledText {
                    text: modelData.score
                    font.pixelSize: FootballStyle.textSmall
                    font.weight: Font.Bold
                    color: modelData.result === "W" ? FootballStyle.colPrimary : FootballStyle.colOnSurface
                }
            }
        }
    }

    component PlayerLine: RowLayout {
        id: line
        property var player: null
        property string side: "home"
        property var subMinutes: ({})
        readonly property var sub: line.subMinutes[line.player?.name] ?? null
        Layout.fillWidth: true
        spacing: FootballStyle.gapSmall
        Rectangle {
            implicitWidth: 28
            implicitHeight: 28
            radius: 14
            color: line.side === "home" ? FootballStyle.colPrimary : FootballStyle.colTertiary
            opacity: line.player?.starter ? 1 : 0.55
            StyledText {
                anchors.centerIn: parent
                text: line.player?.jersey ?? ""
                font.pixelSize: FootballStyle.textSmaller
                font.weight: Font.Bold
                color: line.side === "home" ? FootballStyle.colOnPrimary : FootballStyle.colOnTertiary
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: line.player?.name ?? ""
            elide: Text.ElideRight
            font.pixelSize: FootballStyle.textSmall
            font.weight: line.player?.starter ? Font.DemiBold : Font.Normal
            color: FootballStyle.colOnSurface
        }
        Row {
            spacing: 4
            Repeater {
                model: line.player?.goals ?? 0
                delegate: MaterialSymbol { text: "sports_soccer"; iconSize: 15; fill: 1; color: FootballStyle.colOnSurface }
            }
            CardGlyph {
                visible: (line.player?.yellow ?? 0) > 0 || (line.player?.red ?? 0) > 0
                red: (line.player?.red ?? 0) > 0
                cardHeight: 13
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        StyledText {
            visible: line.sub !== null
            text: line.sub ? `${line.sub.dir === "in" ? "↑" : "↓"} ${line.sub.minute}` : ""
            font.pixelSize: FootballStyle.textSmaller
            font.weight: Font.Bold
            color: line.sub?.dir === "in" ? FootballStyle.colPrimary : FootballStyle.colSubtext
        }
        StyledText {
            Layout.preferredWidth: 36
            horizontalAlignment: Text.AlignRight
            text: line.player?.pos ?? ""
            font.pixelSize: FootballStyle.textSmallest
            font.weight: Font.Bold
            color: FootballStyle.colSubtext
        }
    }

    // ── Tabs ─────────────────────────────────────────────────────────────────

    Component {
        id: summaryTab
        GridLayout {
            columns: root.wide ? 2 : 1
            columnSpacing: FootballStyle.gap
            rowSpacing: FootballStyle.gap

            SectionSlab {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 3
                title: Translation.tr("Key moments")
                symbol: "timeline"
                shape: MaterialShape.Shape.Cookie12Sided
                KeyMoments {
                    Layout.fillWidth: true
                    visible: (root.detail?.keyEvents ?? []).length > 0
                    events: root.detail?.keyEvents ?? []
                    newestFirst: root.match?.state === "in"
                }
                StyledText {
                    visible: (root.detail?.keyEvents ?? []).length === 0
                    Layout.fillWidth: true
                    text: root.match?.state === "pre" ? Translation.tr("The match hasn't started yet") : Translation.tr("No key moments yet")
                    font.pixelSize: FootballStyle.textSmall
                    color: FootballStyle.colSubtext
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 2
                spacing: FootballStyle.gap

                SectionSlab {
                    Layout.fillWidth: true
                    visible: (root.detail?.stats ?? []).length > 0
                    title: Translation.tr("Statistics")
                    symbol: "bar_chart"
                    shape: MaterialShape.Shape.Clover4Leaf
                    Repeater {
                        model: (root.detail?.stats ?? []).slice(0, 6)
                        delegate: StatBar {
                            required property var modelData
                            Layout.fillWidth: true
                            stat: modelData
                        }
                    }
                    ClockButton {
                        Layout.alignment: Qt.AlignHCenter
                        visible: (root.detail?.stats ?? []).length > 6
                        variant: "text"
                        label: Translation.tr("All statistics")
                        onClicked: root.tab = "stats"
                    }
                }

                SectionSlab {
                    Layout.fillWidth: true
                    title: Translation.tr("Match info")
                    symbol: "info"
                    shape: MaterialShape.Shape.Sunny
                    InfoRow { symbol: "event"; caption: Translation.tr("Date"); value: Format.longDate(root.match?.date, root.locale) + (root.match?.date ? " · " + Format.kickoffTime(root.match.date) : ""); shape: MaterialShape.Shape.Cookie12Sided }
                    InfoRow { symbol: "emoji_events"; caption: Translation.tr("Competition"); value: [root.match?.league?.name ?? "", root.detail?.season ?? ""].filter(part => part !== "" && part !== undefined).join(" · "); shape: MaterialShape.Shape.Sunny }
                    InfoRow { symbol: "stadium"; caption: Translation.tr("Stadium"); value: [root.detail?.venue || root.baseMatch?.venue || "", root.detail?.city || root.baseMatch?.city || ""].filter(part => part !== "").join(" · "); shape: MaterialShape.Shape.Clover4Leaf }
                    InfoRow { symbol: "groups"; caption: Translation.tr("Attendance"); value: (root.detail?.attendance ?? 0) > 0 ? root.detail.attendance.toLocaleString(root.locale, "f", 0) : ""; shape: MaterialShape.Shape.Cookie6Sided }
                    InfoRow { symbol: "sports"; caption: Translation.tr("Referee"); value: (root.detail?.officials ?? []).join(", "); shape: MaterialShape.Shape.SoftBurst }
                    InfoRow { symbol: "live_tv"; caption: Translation.tr("Broadcast"); value: root.baseMatch?.broadcasts ?? ""; shape: MaterialShape.Shape.Cookie7Sided }
                    InfoRow { symbol: "sticky_note_2"; caption: Translation.tr("Note"); value: root.baseMatch?.note ?? ""; shape: MaterialShape.Shape.Flower }
                }

                SectionSlab {
                    Layout.fillWidth: true
                    visible: (root.detail?.form ?? []).length > 0
                    title: Translation.tr("Form")
                    symbol: "trending_up"
                    shape: MaterialShape.Shape.Cookie6Sided
                    Repeater {
                        model: root.detail?.form ?? []
                        delegate: FormColumn {
                            required property var modelData
                            entry: modelData
                        }
                    }
                }
            }
        }
    }

    Component {
        id: lineupsTab
        ColumnLayout {
            spacing: FootballStyle.gap

            LineupPitch {
                Layout.fillWidth: true
                homeLineup: root.lineup("home")
                awayLineup: root.lineup("away")
                positions: FootballService.positionsCache[root.matchId] ?? null
                homeName: root.match?.home?.short ?? ""
                awayName: root.match?.away?.short ?? ""
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.wide ? 2 : 1
                columnSpacing: FootballStyle.gap
                rowSpacing: FootballStyle.gap

                Repeater {
                    model: ["home", "away"]
                    delegate: SectionSlab {
                        id: bench
                        required property string modelData
                        readonly property var lineup: root.lineup(bench.modelData)
                        readonly property var team: bench.modelData === "home" ? root.match?.home : root.match?.away
                        // Substitution minutes from the key moments: players[0] came on for players[1].
                        readonly property var subMinutes: {
                            const map = ({});
                            (root.detail?.keyEvents ?? []).filter(event => event.kind === "sub" && event.side === bench.modelData)
                                .forEach(event => {
                                    if (event.players[0]) map[event.players[0]] = { dir: "in", minute: event.minute, other: event.players[1] ?? "" };
                                    if (event.players[1]) map[event.players[1]] = { dir: "out", minute: event.minute, other: event.players[0] ?? "" };
                                });
                            return map;
                        }
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        title: `${bench.team?.name ?? ""} · ${Translation.tr("Squad")}`
                        symbol: "groups"
                        shape: MaterialShape.Shape.Puffy

                        StyledText {
                            text: Translation.tr("Starting XI") + (bench.lineup?.formation ? ` · ${bench.lineup.formation}` : "")
                            font.pixelSize: FootballStyle.textSmallest
                            font.weight: Font.Bold
                            color: FootballStyle.colOnSurfaceVariant
                        }
                        Repeater {
                            model: bench.lineup?.starters ?? []
                            delegate: PlayerLine { required property var modelData; player: modelData; side: bench.modelData; subMinutes: bench.subMinutes }
                        }
                        StyledText {
                            Layout.topMargin: FootballStyle.gapSmall
                            visible: (bench.lineup?.subs ?? []).length > 0
                            text: Translation.tr("Substitutes")
                            font.pixelSize: FootballStyle.textSmallest
                            font.weight: Font.Bold
                            color: FootballStyle.colOnSurfaceVariant
                        }
                        Repeater {
                            model: bench.lineup?.subs ?? []
                            delegate: PlayerLine { required property var modelData; player: modelData; side: bench.modelData; subMinutes: bench.subMinutes }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: commentaryTab
        SectionSlab {
            id: commentarySlab
            title: Translation.tr("Play-by-play")
            symbol: "forum"
            shape: MaterialShape.Shape.Flower
            readonly property var keyTexts: {
                const map = ({});
                (root.detail?.keyEvents ?? []).forEach(event => { if (event.text) map[event.text] = event.kind; });
                return map;
            }
            Repeater {
                // A long match carries a few hundred entries; the newest 150 are plenty.
                model: (root.detail?.commentary ?? []).slice(0, 150)
                delegate: Rectangle {
                    id: entry
                    required property var modelData
                    readonly property string kind: commentarySlab.keyTexts[entry.modelData.text] ?? ""
                    readonly property bool goal: entry.kind === "goal" || entry.kind === "own"
                    Layout.fillWidth: true
                    implicitHeight: entryRow.implicitHeight + 16
                    radius: FootballStyle.radiusSmall
                    color: entry.goal ? FootballStyle.colPrimaryContainer
                        : entry.kind !== "" && entry.kind !== "phase" ? FootballStyle.colField : "transparent"
                    RowLayout {
                        id: entryRow
                        x: 10
                        y: 8
                        width: parent.width - 20
                        spacing: FootballStyle.gap
                        StyledText {
                            shouldUseNumberFont: false
                            Layout.preferredWidth: 46
                            Layout.alignment: Qt.AlignTop
                            text: entry.modelData.minute
                            font.pixelSize: FootballStyle.textNormal
                            font.variableAxes: FootballStyle.axesCondensed
                            color: entry.goal ? FootballStyle.colOnPrimaryContainer : FootballStyle.colPrimary
                        }
                        Item {
                            Layout.alignment: Qt.AlignTop
                            implicitWidth: 20
                            implicitHeight: 20
                            visible: entry.kind !== "" && entry.kind !== "phase"
                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: entry.kind !== "yellow" && entry.kind !== "red"
                                text: entry.goal ? "sports_soccer" : entry.kind === "sub" ? "swap_vert" : "info"
                                iconSize: 18
                                fill: 1
                                color: entry.goal ? FootballStyle.colOnPrimaryContainer : FootballStyle.colOnSurfaceVariant
                            }
                            CardGlyph {
                                anchors.centerIn: parent
                                visible: entry.kind === "yellow" || entry.kind === "red"
                                red: entry.kind === "red"
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: entry.modelData.text
                            wrapMode: Text.WordWrap
                            font.pixelSize: FootballStyle.textSmall
                            font.weight: entry.goal ? Font.DemiBold : Font.Normal
                            color: entry.goal ? FootballStyle.colOnPrimaryContainer : FootballStyle.colOnSurface
                        }
                    }
                }
            }
        }
    }

    Component {
        id: statsTab
        SectionSlab {
            title: Translation.tr("Statistics")
            symbol: "bar_chart"
            shape: MaterialShape.Shape.Clover4Leaf
            RowLayout {
                Layout.fillWidth: true
                TeamCrest { size: 28; source: root.match?.home?.logo ?? ""; plate: "transparent" }
                StyledText {
                    Layout.fillWidth: true
                    text: root.match?.home?.name ?? ""
                    font.pixelSize: FootballStyle.textNormal
                    font.weight: Font.Bold
                    color: FootballStyle.colPrimary
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: root.match?.away?.name ?? ""
                    font.pixelSize: FootballStyle.textNormal
                    font.weight: Font.Bold
                    color: FootballStyle.colTertiary
                    elide: Text.ElideRight
                }
                TeamCrest { size: 28; source: root.match?.away?.logo ?? ""; plate: "transparent" }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: root.wide ? 2 : 1
                columnSpacing: FootballStyle.gapHuge * 2
                rowSpacing: FootballStyle.gapLarge
                Repeater {
                    model: root.detail?.stats ?? []
                    delegate: StatBar {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        stat: modelData
                    }
                }
            }
        }
    }

    Component {
        id: tableTab
        SectionSlab {
            title: root.detail?.standingsTitle || Translation.tr("Table")
            symbol: "format_list_numbered"
            shape: MaterialShape.Shape.SoftBurst
            StandingsTable {
                Layout.fillWidth: true
                groups: root.detail?.standings ?? []
                league: root.match?.league?.slug ?? ""
                onTeamActivated: team => root.teamActivated(team)
            }
        }
    }

    Component {
        id: h2hTab
        GridLayout {
            columns: root.wide ? 2 : 1
            columnSpacing: FootballStyle.gap
            rowSpacing: FootballStyle.gap

            SectionSlab {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 1
                visible: (root.detail?.headToHead?.games ?? []).length > 0
                title: Translation.tr("Head-to-head")
                symbol: "compare_arrows"
                shape: MaterialShape.Shape.Cookie7Sided
                StyledText {
                    visible: (root.detail?.headToHead?.summary ?? "") !== ""
                    text: root.detail?.headToHead?.summary ?? ""
                    font.pixelSize: FootballStyle.textNormal
                    font.weight: Font.Bold
                    color: FootballStyle.colOnSurface
                }
                Repeater {
                    model: root.detail?.headToHead?.games ?? []
                    delegate: MatchRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        match: Object.assign({ state: modelData.completed ? "post" : "pre", statusDetail: modelData.status, league: { name: "" } }, modelData)
                        showDate: true
                        isFirst: index === 0
                        isLast: index === (root.detail?.headToHead?.games ?? []).length - 1
                        onClicked: root.matchActivated(match)
                    }
                }
            }

            SectionSlab {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 1
                visible: (root.detail?.form ?? []).length > 0
                title: Translation.tr("Last five matches")
                symbol: "trending_up"
                shape: MaterialShape.Shape.Cookie6Sided
                Repeater {
                    model: root.detail?.form ?? []
                    delegate: FormColumn {
                        required property var modelData
                        entry: modelData
                    }
                }
            }
        }
    }

    Component {
        id: newsTab
        Flow {
            id: newsFlow
            spacing: FootballStyle.gap
            readonly property int columns: Math.max(1, Math.floor((width + FootballStyle.gap) / (280 + FootballStyle.gap)))
            readonly property real cardWidth: Math.floor((width - FootballStyle.gap * (columns - 1)) / columns)
            Repeater {
                model: root.detail?.news ?? []
                delegate: RippleButton {
                    id: card
                    required property var modelData
                    width: newsFlow.cardWidth
                    implicitHeight: cardColumn.implicitHeight + FootballStyle.gap
                    padding: 0
                    buttonRadius: FootballStyle.radiusLarge
                    buttonRadiusPressed: FootballStyle.radiusNormal
                    colBackground: FootballStyle.colRow
                    colBackgroundHover: FootballStyle.colRowHover
                    onClicked: Qt.openUrlExternally(card.modelData.link)
                    contentItem: ColumnLayout {
                        id: cardColumn
                        spacing: FootballStyle.gapSmall
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: Math.round(card.width * 9 / 16)
                            visible: card.modelData.image !== ""
                            StyledImage {
                                id: thumb
                                anchors.fill: parent
                                anchors.margins: 6
                                source: card.modelData.image
                                fillMode: Image.PreserveAspectCrop
                                cache: true
                                visible: false
                            }
                            Rectangle {
                                id: thumbMask
                                anchors.fill: thumb
                                radius: FootballStyle.radiusNormal
                                visible: false
                                layer.enabled: true
                            }
                            MaskMultiEffect {
                                anchors.fill: thumb
                                source: thumb
                                maskSource: thumbMask
                            }
                            Rectangle {
                                visible: card.modelData.video
                                anchors.left: thumb.left
                                anchors.bottom: thumb.bottom
                                anchors.margins: 8
                                width: 32
                                height: 32
                                radius: 16
                                color: FootballStyle.colPrimary
                                MaterialSymbol { anchors.centerIn: parent; text: "play_arrow"; fill: 1; iconSize: 20; color: FootballStyle.colOnPrimary }
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: FootballStyle.gap
                            Layout.rightMargin: FootballStyle.gap
                            text: card.modelData.headline
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.pixelSize: FootballStyle.textNormal
                            font.weight: Font.DemiBold
                            color: FootballStyle.colOnSurface
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: FootballStyle.gap
                            Layout.rightMargin: FootballStyle.gap
                            visible: card.modelData.description !== ""
                            text: card.modelData.description
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.pixelSize: FootballStyle.textSmaller
                            color: FootballStyle.colSubtext
                        }
                        StyledText {
                            Layout.leftMargin: FootballStyle.gap
                            text: Format.shortDate(card.modelData.published, root.locale)
                            font.pixelSize: FootballStyle.textSmallest
                            font.weight: Font.Bold
                            color: FootballStyle.colOnSurfaceVariant
                        }
                    }
                }
            }
        }
    }
}
