pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property string searchQuery: ""
    property int selectedIndex: 0
    property bool subscribed: false
    property string noticeText: ""

    readonly property var rows: root.filteredGames()
    readonly property var selectedGame: root.selectedIndex >= 0 && root.selectedIndex < root.rows.length ? root.rows[root.selectedIndex] : null
    readonly property string statusText: root.noticeText.length > 0
        ? root.noticeText
        : (SportsService.searchLoading
            ? Translation.tr("Loading today’s games…")
            : (SportsService.searchError.length > 0
                ? SportsService.searchError
                : Translation.tr("%1 games today").arg(String(root.rows.length))))

    implicitWidth: Config.options.search.appearance.panelWidth
    implicitHeight: scaffold.implicitHeight

    function filteredGames() {
        const query = root.searchQuery.trim().toLocaleLowerCase();
        const today = SportsService.dayKey(DateTime.clock.date);
        const leagues = Array.from(Config.options.search.modules.sports.leagues ?? []);
        return Array.from(SportsService.searchGames ?? []).filter(game => {
            if (SportsService.dayKey(game?.date) !== today)
                return false;
            if (leagues.length > 0 && !leagues.includes(String(game?.leagueId ?? game?.league ?? "")))
                return false;
            if (query.length === 0)
                return true;
            return [game?.name, game?.league, game?.home?.name, game?.away?.name, game?.status]
                .join(" ").toLocaleLowerCase().includes(query);
        }).sort((left, right) => new Date(left?.date) - new Date(right?.date));
    }

    function clampSelection() {
        root.selectedIndex = root.rows.length === 0 ? -1 : Math.max(0, Math.min(root.selectedIndex, root.rows.length - 1));
    }
    function navigateUp(): bool {
        if (root.selectedIndex > 0)
            root.selectedIndex--;
        gamesList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        return true;
    }
    function navigateDown(): bool {
        if (root.selectedIndex >= 0 && root.selectedIndex < root.rows.length - 1)
            root.selectedIndex++;
        gamesList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        return true;
    }
    function activateSelected(): bool {
        if (!root.selectedGame)
            return false;
        const index = Array.from(SportsService.allGames ?? []).findIndex(game => String(game?.id ?? "") === String(root.selectedGame.id ?? ""));
        if (index >= 0) {
            SportsService.currentGameIndex = index;
            SportsService.currentGame = SportsService.allGames[index];
        } else {
            SportsService.currentGame = root.selectedGame;
        }
        root.showNotice(Translation.tr("Selected %1").arg(String(root.selectedGame.name ?? Translation.tr("game"))));
        return true;
    }
    function createFromQuery(): bool {
        if (!root.selectedGame?.date)
            return false;
        const seconds = Math.floor((new Date(root.selectedGame.date).getTime() - Date.now()) / 1000) - 600;
        if (seconds <= 0) {
            root.showNotice(Translation.tr("This game has already started"));
            return false;
        }
        const minutes = Math.max(1, Math.ceil(seconds / 60));
        const countdown = TimerService.addCountdown(minutes, String(root.selectedGame.name ?? Translation.tr("Game")));
        if (!countdown)
            return false;
        root.showNotice(Translation.tr("Reminder set for 10 minutes before kickoff"));
        return true;
    }
    function focusInput(): bool { return false; }
    function showNotice(message) {
        root.noticeText = String(message ?? "");
        noticeTimer.restart();
    }

    onRowsChanged: root.clampSelection()
    onSearchQueryChanged: root.selectedIndex = 0
    Component.onCompleted: { SportsService.acquireSearchSubscriber(); root.subscribed = true; }
    Component.onDestruction: if (root.subscribed) SportsService.releaseSearchSubscriber()

    Timer { id: noticeTimer; interval: 3200; onTriggered: root.noticeText = "" }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        title: Translation.tr("Today’s games")
        icon: "sports_soccer"
        accent: true
        statusText: root.statusText
        showStatus: true
        primaryHint: ({ label: Translation.tr("Select"), actionId: "activate", keys: ["↵"] })
        hints: [{ label: Translation.tr("Remind"), actionId: "create", keys: ["Ctrl", "N"] }]

        ListView {
            id: gamesList
            width: parent.width
            height: parent.height
            visible: root.rows.length > 0
            clip: true
            spacing: Appearance.sizes.elevationMargin / 2
            model: root.rows

            delegate: RippleButton {
                required property int index
                required property var modelData
                width: gamesList.width
                implicitHeight: gameContent.implicitHeight + Appearance.sizes.elevationMargin * 2
                buttonRadius: root.selectedIndex === index ? Appearance.rounding.large : Appearance.rounding.normal
                colBackground: root.selectedIndex === index ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
                colBackgroundHover: root.selectedIndex === index ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                colRipple: root.selectedIndex === index ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                onClicked: root.selectedIndex = index
                onDoubleClicked: root.activateSelected()

                RowLayout {
                    id: gameContent
                    anchors.fill: parent
                    anchors.margins: Appearance.sizes.elevationMargin
                    spacing: Appearance.sizes.elevationMargin
                    readonly property real columnWidth: Math.max(0, (width - spacing * 2) / 3)

                    ColumnLayout {
                        Layout.minimumWidth: gameContent.columnWidth
                        Layout.preferredWidth: gameContent.columnWidth
                        Layout.maximumWidth: gameContent.columnWidth
                        spacing: Appearance.sizes.elevationMargin / 2
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: Appearance.sizes.elevationMargin * 4
                            implicitHeight: implicitWidth
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colSurfaceContainerHighest
                            StyledImage {
                                anchors.centerIn: parent
                                width: parent.width - Appearance.sizes.elevationMargin
                                height: width
                                source: String(modelData.home?.logo ?? "")
                                fillMode: Image.PreserveAspectFit
                            }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: String(modelData.home?.logo ?? "").length === 0
                                text: "shield"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colPrimary
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: String(modelData.home?.name ?? Translation.tr("Home"))
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            font.weight: Font.DemiBold
                            color: root.selectedIndex === index ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                        }
                    }

                    ColumnLayout {
                        Layout.minimumWidth: gameContent.columnWidth
                        Layout.preferredWidth: gameContent.columnWidth
                        Layout.maximumWidth: gameContent.columnWidth
                        spacing: Appearance.sizes.elevationMargin / 2
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: scoreText.implicitWidth + Appearance.sizes.elevationMargin * 2
                            implicitHeight: scoreText.implicitHeight + Appearance.sizes.elevationMargin
                            radius: Appearance.rounding.full
                            color: modelData.state === "in" ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
                            StyledText {
                                id: scoreText
                                anchors.centerIn: parent
                                text: modelData.state === "pre"
                                    ? Qt.formatTime(new Date(modelData.date), Config.options.time.format)
                                    : String(modelData.home?.score ?? "0") + "  ×  " + String(modelData.away?.score ?? "0")
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.large
                                font.weight: Font.DemiBold
                                color: modelData.state === "in" ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: String(modelData.status ?? "")
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: root.selectedIndex === index ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: String(modelData.league ?? "")
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: root.selectedIndex === index ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        }

                        ConfiguredKeyHint {
                            Layout.alignment: Qt.AlignHCenter
                            visible: root.selectedIndex === index && Config.options.search.appearance.showKeyHints
                            actionId: "activate"
                            fallbackKeys: ["↵"]
                            surface: Appearance.colors.colPrimaryContainer
                            onSurface: Appearance.colors.colOnPrimaryContainer
                        }
                    }

                    ColumnLayout {
                        Layout.minimumWidth: gameContent.columnWidth
                        Layout.preferredWidth: gameContent.columnWidth
                        Layout.maximumWidth: gameContent.columnWidth
                        spacing: Appearance.sizes.elevationMargin / 2
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: Appearance.sizes.elevationMargin * 4
                            implicitHeight: implicitWidth
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colSurfaceContainerHighest
                            StyledImage {
                                anchors.centerIn: parent
                                width: parent.width - Appearance.sizes.elevationMargin
                                height: width
                                source: String(modelData.away?.logo ?? "")
                                fillMode: Image.PreserveAspectFit
                            }
                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: String(modelData.away?.logo ?? "").length === 0
                                text: "shield"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colTertiary
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: String(modelData.away?.name ?? Translation.tr("Away"))
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            font.weight: Font.DemiBold
                            color: root.selectedIndex === index ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                        }
                    }
                }
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            visible: root.rows.length === 0
            spacing: Appearance.sizes.elevationMargin
            MaterialLoadingIndicator {
                Layout.alignment: Qt.AlignHCenter
                visible: SportsService.searchLoading
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
            }
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                visible: !SportsService.searchLoading
                implicitWidth: Appearance.sizes.elevationMargin * 6
                implicitHeight: implicitWidth
                radius: Appearance.rounding.full
                color: SportsService.searchError.length > 0 ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: SportsService.searchError.length > 0 ? "cloud_off" : "sports_score"
                    iconSize: Appearance.font.pixelSize.huge
                    color: SportsService.searchError.length > 0 ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: SportsService.searchLoading
                    ? Translation.tr("Checking today’s scoreboards…")
                    : (SportsService.searchError.length > 0 ? SportsService.searchError : Translation.tr("No games today"))
                horizontalAlignment: Text.AlignHCenter
                color: Appearance.colors.colOnSurface
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: !SportsService.searchLoading && SportsService.searchError.length === 0
                text: Translation.tr("There are no scheduled games in your selected leagues")
                color: Appearance.colors.colSubtext
            }
            RippleButton {
                Layout.alignment: Qt.AlignHCenter
                visible: !SportsService.searchLoading && SportsService.searchError.length > 0
                implicitWidth: retryLabel.implicitWidth + Appearance.sizes.elevationMargin * 2
                implicitHeight: Appearance.sizes.elevationMargin * 3
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colErrorContainer
                colBackgroundHover: Appearance.colors.colErrorContainerHover
                colRipple: Appearance.colors.colErrorContainerActive
                onClicked: SportsService.fetchSearchGamesForToday()
                StyledText { id: retryLabel; anchors.centerIn: parent; text: Translation.tr("Try again"); color: Appearance.colors.colOnErrorContainer }
            }
        }
    }
}
