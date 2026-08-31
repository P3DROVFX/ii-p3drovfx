import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    signal goBack

    property string selectedSport: "soccer"
    property int selectedLeagueIndex: 0

    readonly property var espnData: {
        "baseball": ["college-baseball", "college-softball", "mlb", "world-baseball-classic", "llb", "caribbean-series", "dominican-winter-league", "venezuelan-winter-league", "mexican-winter-league", "puerto-rican-winter-league", "olympics-baseball"],
        "basketball": ["mens-college-basketball", "nba", "nba-summer-las-vegas", "nba-summer-utah", "nba-summer-orlando", "nba-summer-sacramento", "nba-development", "wnba", "womens-college-basketball", "mens-olympics-basketball", "womens-olympics-basketball", "fiba"],
        "football": ["college-football", "nfl", "xfl", "cfl"],
        "golf": ["eur", "lpga", "ntw", "pga", "champions-tour", "mens-olympics-golf", "womens-olympics-golf"],
        "hockey": ["mens-college-hockey", "nhl", "womens-college-hockey", "hockey-world-cup", "mens-olympic-hockey", "womens-olympic-hockey"],
        "lacrosse": ["mens-college-lacrosse", "womens-college-lacrosse"],
        "mma": ["pfl", "ifc", "ksw", "cage-warriors", "xfc", "ofc", "rfa", "rizin", "lfa", "vfc", "ces", "absolute", "bellator", "strikeforce", "ufc", "lfc", "tfc", "roc", "proelite", "dream", "bamma", "wec", "pancrase", "affliction", "ifl"],
        "racing": ["f1", "irl", "nascar-secondary", "nhra", "nascar-premier", "nascar-truck"],
        "rugby": ["268565", "289234", "164205", "180659", "244293", "271937", "272073", "267979", "270559", "270557", "242041", "289271", "289272", "289277", "289279", "270561", "270555", "270563", "236461", "264129", "282877", "262827", "256447", "268561", "283371"],
        "rugby-league": ["3"],
        "soccer": ["concacaf.gold", "uefa.euro", "conmebol.america", "fifa.friendly", "fifa.world", "fifa.wwc", "usa.1", "usa.nwsl", "mex.1", "uefa.champions_qual", "uefa.champions", "uefa.europa", "eng.1", "ita.1", "ger.1", "esp.1", "fra.1", "eng.2", "eng.league_cup", "eng.fa", "esp.copa_del_rey", "ita.coppa_italia", "ger.dfb_pokal", "fra.coupe_de_france", "mex.copa_mx", "concacaf.champions", "ned.1"],
        "volleyball": ["mens-college-volleyball", "womens-college-volleyball"],
        "australian-football": ["afl"],
        "tennis": ["atp", "wta"],
        "water-polo": ["mens-college-water-polo", "womens-college-water-polo"],
        "field-hockey": ["womens-college-field-hockey"]
    }

    readonly property var availableSports: Object.keys(espnData)

    onSelectedSportChanged: {
        selectedLeagueIndex = 0;
    }

    // ── Helpers ───────────────────────────────────────────────────────────
    function formatLeagueName(slug) {
        if (!slug)
            return "";
        let parts = slug.split(/[-.]/);
        return parts.map(p => p.charAt(0).toUpperCase() + p.slice(1)).join(" ");
    }

    function isLeagueTracked(sportName, leagueName) {
        let list = Config.options.bar.sports.monitoredLeagues || [];
        return list.some(l => l.sport === sportName && l.league === leagueName);
    }

    function addLeague(sportName, leagueName) {
        if (isLeagueTracked(sportName, leagueName))
            return;
        let list = JSON.parse(JSON.stringify(Config.options.bar.sports.monitoredLeagues || []));
        list.push({
            sport: sportName,
            league: leagueName,
            name: formatLeagueName(leagueName),
            enabled: true
        });
        Config.options.bar.sports.monitoredLeagues = list;
    }

    function removeLeague(sportName, leagueName) {
        let list = JSON.parse(JSON.stringify(Config.options.bar.sports.monitoredLeagues || []));
        let idx = list.findIndex(l => l.sport === sportName && l.league === leagueName);
        if (idx !== -1) {
            list.splice(idx, 1);
            Config.options.bar.sports.monitoredLeagues = list;
        }
    }

    function toggleLeagueEnabled(sportName, leagueName, enabled) {
        let list = JSON.parse(JSON.stringify(Config.options.bar.sports.monitoredLeagues || []));
        let match = list.find(l => l.sport === sportName && l.league === leagueName);
        if (match) {
            match.enabled = enabled;
            Config.options.bar.sports.monitoredLeagues = list;
        }
    }

    function getTrackedLeagues() {
        return Config.options.bar.sports.monitoredLeagues || [];
    }

    // ── Back button row ───────────────────────────────────────────────────
    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Sports Tracker")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── Settings ──────────────────────────────────────────────────────────
    ContentSection {
        icon: "sports_soccer"
        title: Translation.tr("Sports Tracker")

        HelperLinkBox {
            Layout.fillWidth: true
            title: Translation.tr("ESPN API")
            text: Translation.tr("The Sports widget uses the ESPN API to fetch data. Some leagues might not be available or may have different slugs. Check the API docs for more details.")
            isFirst: true
            isLast: true

            RippleButtonWithIcon {
                mainText: Translation.tr("Open API Docs")
                materialIcon: "open_in_new"
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                colBackground: Appearance.colors.colLayer0
                colBackgroundHover: Appearance.colors.colLayer0Hover
                colRipple: Appearance.colors.colLayer0Active
                downAction: () => {
                    Qt.openUrlExternally("https://gist.github.com/nntrn/ee26cb2a0716de0947a0a4e9a157bc1c/b99b9e0d2df72470fa622e2f76cecb0362111e9a#file-extending-espn-api-md");
                }
            }
        }

        Item {
            Layout.preferredHeight: 16
        }

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable sports tracker")
            checked: Config.options.bar.sports.enable
            isFirst: true
            isLast: true
            onCheckedChanged: {
                Config.options.bar.sports.enable = checked;
            }
        }

        Item {
            Layout.preferredHeight: 16
        }

        ContentSubsection {
            title: Translation.tr("Add new league")
            icon: "add_circle"
            visible: Config.options.bar.sports.enable
            isFirst: true

            // Sport Selection Group
            Flow {
                Layout.fillWidth: true
                spacing: 8
                topPadding: 4
                bottomPadding: 8

                Repeater {
                    model: root.availableSports
                    delegate: Rectangle {
                        required property string modelData
                        property bool isSelected: root.selectedSport === modelData

                        width: sportText.implicitWidth + 24
                        height: 32
                        radius: Appearance.rounding.full

                        color: isSelected ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHigh
                        border.width: isSelected ? 0 : 1
                        border.color: Appearance.colors.colOutlineVariant

                        HoverHandler {
                            id: sportHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        StyledText {
                            id: sportText
                            anchors.centerIn: parent
                            text: parent.modelData.charAt(0).toUpperCase() + parent.modelData.slice(1).replace(/-/g, " ")
                            color: parent.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: parent.isSelected ? Font.Bold : Font.Medium
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.selectedSport = parent.modelData
                            cursorShape: Qt.PointingHandCursor
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }
                }
            }

            // League Selection Dropdown
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                StyledComboBox {
                    Layout.fillWidth: true
                    model: {
                        let leagues = root.espnData[root.selectedSport] || [];
                        return leagues.map(l => ({
                                    display: root.formatLeagueName(l),
                                    value: l
                                }));
                    }
                    textRole: "display"
                    currentIndex: root.selectedLeagueIndex
                    onActivated: index => {
                        root.selectedLeagueIndex = index;
                    }
                }

                RippleButton {
                    implicitWidth: 120
                    implicitHeight: 36
                    topLeftRadius: Appearance.rounding.full
                    topRightRadius: Appearance.rounding.full
                    bottomLeftRadius: Appearance.rounding.full
                    bottomRightRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Qt.lighter(Appearance.colors.colPrimary, 1.15)
                    colRipple: Appearance.colors.colPrimaryContainer

                    property string targetLeague: {
                        let leagues = root.espnData[root.selectedSport] || [];
                        if (leagues.length > root.selectedLeagueIndex) {
                            return leagues[root.selectedLeagueIndex];
                        }
                        return "";
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            text: "add"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            text: Translation.tr("Add")
                            color: Appearance.colors.colOnPrimary
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                        }
                    }

                    onClicked: {
                        if (targetLeague !== "") {
                            root.addLeague(root.selectedSport, targetLeague);
                        }
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Monitored leagues")
            icon: "playlist_add_check"
            visible: Config.options.bar.sports.enable && root.getTrackedLeagues().length > 0
            isLast: true

            Flow {
                Layout.fillWidth: true
                spacing: 8
                topPadding: 4
                bottomPadding: 4

                Repeater {
                    model: root.getTrackedLeagues()
                    delegate: LeagueChip {
                        required property var modelData
                        text: modelData.name + " (" + modelData.sport + ")"
                        checked: modelData.enabled
                        onToggled: c => root.toggleLeagueEnabled(modelData.sport, modelData.league, c)
                        onRemoved: root.removeLeague(modelData.sport, modelData.league)
                    }
                }
            }
        }

        Item {
            Layout.preferredHeight: 16
        }

        ContentSubsection {
            title: Translation.tr("Preferences filter")
            icon: "filter_list"
            tooltip: Translation.tr("Comma-separated list of teams to show (e.g. Real Madrid, Arsenal)")
            visible: Config.options.bar.sports.enable
            isFirst: true

            NoticeBox {
                Layout.fillWidth: true
                text: Translation.tr("Comma-separated, exact names only: Real Madrid, Arsenal")
            }

            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Filter by team name...")
                text: Config.options.bar.sports.teamFilter
                onTextChanged: Config.options.bar.sports.teamFilter = text
            }
        }

        ConfigSpinBox {
            enabled: Config.options.bar.sports.enable
            icon: "layers"
            text: Translation.tr("Max cards in popup")
            value: Config.options.bar.sports.maxCardsPopup
            from: 1
            to: 15
            stepSize: 1
            onValueChanged: {
                Config.options.bar.sports.maxCardsPopup = value;
            }
        }

        ConfigSpinBox {
            enabled: Config.options.bar.sports.enable
            icon: "history"
            text: Translation.tr("Keep ended matches for (mins)")
            value: Config.options.bar.sports.showAfterMinutes
            from: 0
            to: 1440
            stepSize: 30
            onValueChanged: {
                Config.options.bar.sports.showAfterMinutes = value;
            }
        }

        ConfigSpinBox {
            enabled: Config.options.bar.sports.enable
            icon: "schedule"
            text: Translation.tr("Show matches before (hours)")
            value: Config.options.bar.sports.showBeforeHours
            from: 1
            to: 72
            stepSize: 1
            onValueChanged: {
                Config.options.bar.sports.showBeforeHours = value;
            }
        }

        ConfigSpinBox {
            enabled: Config.options.bar.sports.enable
            icon: "av_timer"
            text: Translation.tr("Update Interval (s)")
            value: Config.options.bar.sports.updateInterval
            from: 10
            to: 600
            stepSize: 10
            onValueChanged: {
                Config.options.bar.sports.updateInterval = value;
            }
        }
    }

    ContentSection {
        icon: "link"
        title: Translation.tr("Related settings")

        Flow {
            Layout.fillWidth: true
            spacing: 8

            RelatedChip {
                pageId: "lockScreen"
                label: Translation.tr("Lock screen settings")
                sectionHighlight: Translation.tr("Widgets & Layout")
            }
        }
    }

    // ── LeagueChip component ──────────────────────────────────────────────
    component LeagueChip: Rectangle {
        property string text
        property bool checked: false
        signal toggled(bool checked)
        signal removed

        width: chipLayout.implicitWidth + 24
        height: 36
        radius: Appearance.rounding.full

        HoverHandler {
            id: chipHover
            cursorShape: Qt.PointingHandCursor
        }

        color: checked ? (chipHover.hovered ? Qt.lighter(Appearance.colors.colPrimary, 1.15) : Appearance.colors.colPrimary) : (chipHover.hovered ? Appearance.colors.colSurfaceContainerHigh : Appearance.colors.colSurfaceContainer)

        opacity: checked ? 1.0 : 0.6

        RowLayout {
            id: chipLayout
            anchors.centerIn: parent
            spacing: 8

            MouseArea {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: chipText.implicitWidth
                implicitHeight: 36
                onClicked: parent.parent.toggled(!parent.parent.checked)
                cursorShape: Qt.PointingHandCursor

                StyledText {
                    id: chipText
                    anchors.centerIn: parent
                    text: parent.parent.parent.text
                    color: parent.parent.parent.checked ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                }
            }

            RippleButton {
                implicitWidth: 24
                implicitHeight: 24
                topLeftRadius: Appearance.rounding.full
                topRightRadius: Appearance.rounding.full
                bottomLeftRadius: Appearance.rounding.full
                bottomRightRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: "transparent"
                colRipple: Appearance.colors.colErrorContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: Appearance.font.pixelSize.normal
                    color: parent.parent.parent.checked ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                }

                onClicked: parent.parent.removed()
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }
    }
}
