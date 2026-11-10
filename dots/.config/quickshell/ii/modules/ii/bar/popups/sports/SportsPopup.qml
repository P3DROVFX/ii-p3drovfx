import qs.modules.ii.bar.shared
import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

StyledPopup {
    id: root
    popupId: "sports"
    stickyHover: true

    // Design Tokens
    readonly property color colBg: Appearance.colors.colLayer1
    readonly property color colCard: Appearance.colors.colSurfaceContainerHigh
    readonly property color colPill: Appearance.colors.colSecondaryContainer
    readonly property color colOnPill: Appearance.colors.colOnSecondaryContainer
    readonly property color colText: Appearance.colors.colOnLayer2
    readonly property color colSubtext: Appearance.colors.colOnLayer1
    readonly property int radMain: Appearance.rounding.verylarge
    readonly property int radFull: Appearance.rounding.full

    readonly property int cardWidth: 485
    readonly property int cardHeight: 140
    readonly property int cardHeightWithPlay: 190
    readonly property int cardSpacing: 8

    popupRadius: radMain

    // `StyledPopup` only defers its PanelWindow. The body lives in a Loader so
    // the cards (and their image decodes) exist only while the popup is shown.
    contentItem: Loader {
        active: root.active
        sourceComponent: root.popupContent
    }

    property Component popupContent: Component {
        Item {
            id: content

            readonly property int maxCards: Math.max(1, Config.options.bar.sports.maxCardsPopup)
            property var cardHeights: []

            implicitWidth: root.cardWidth
            implicitHeight: {
                const count = Math.min(cardHeights.length, maxCards);
                if (count === 0)
                    return root.cardHeight;
                let total = 0;
                for (let i = 0; i < count; i++)
                    total += cardHeights[i];
                return total + (count - 1) * root.cardSpacing;
            }

            // Rows are written by position: a poll that changes a score only
            // updates the roles that changed, so delegates are never rebuilt
            // (no re-decoded crests, no replayed entrance animation).
            ListModel {
                id: gamesModel
            }

            function sync() {
                const games = SportsService.allGames ?? [];
                const heights = [];
                for (let i = 0; i < games.length; i++) {
                    const game = games[i] ?? ({});
                    const matchState = String(game.state ?? "");
                    const lastPlay = String(game.lastPlay ?? "");
                    const row = {
                        gameId: String(game.id ?? ""),
                        link: String(game.link ?? ""),
                        league: String(game.league ?? ""),
                        matchState: matchState,
                        statusText: SportsService.compactMatchStatus(game.status ?? "", matchState),
                        lastPlay: lastPlay,
                        homeName: String(game.home?.name ?? ""),
                        homeScore: String(game.home?.score ?? "0"),
                        homeLogo: String(game.home?.logo ?? ""),
                        awayName: String(game.away?.name ?? ""),
                        awayScore: String(game.away?.score ?? "0"),
                        awayLogo: String(game.away?.logo ?? "")
                    };
                    if (i < gamesModel.count)
                        gamesModel.set(i, row);
                    else
                        gamesModel.append(row);
                    heights.push(lastPlay !== "" ? root.cardHeightWithPlay : root.cardHeight);
                }
                if (gamesModel.count > games.length)
                    gamesModel.remove(games.length, gamesModel.count - games.length);
                content.cardHeights = heights;
            }

            Component.onCompleted: sync()

            Connections {
                target: SportsService
                function onAllGamesChanged() {
                    content.sync();
                }
            }

            StyledFlickable {
                id: flickable
                anchors.fill: parent
                contentHeight: gamesColumn.height
                clip: true
                interactive: contentHeight > height

                Column {
                    id: gamesColumn
                    width: root.cardWidth
                    spacing: root.cardSpacing

                    Repeater {
                        model: gamesModel
                        delegate: Rectangle {
                            id: card

                            required property int index
                            required property var model

                            readonly property bool isCurrent: (SportsService.currentGame?.id ?? "") !== "" && String(SportsService.currentGame.id) === card.model.gameId
                            readonly property bool hasLastPlay: card.model.lastPlay !== ""
                            readonly property bool showScores: card.model.matchState !== "pre"
                            readonly property int delayBase: 40 + card.index * 100

                            // Entrance plays once per delegate: rows are updated in place, so a
                            // refresh or a click never replays it.
                            readonly property bool revealReady: root.opened && root.popupOpenProgress > 0.6
                            property bool revealed: false

                            function reveal() {
                                if (card.revealed)
                                    return;
                                card.revealed = true;
                                entrance.start();
                            }

                            onRevealReadyChanged: if (revealReady) reveal()
                            Component.onCompleted: if (revealReady) reveal()

                            width: root.cardWidth
                            height: hasLastPlay ? root.cardHeightWithPlay : root.cardHeight
                            radius: root.radMain
                            color: root.colCard
                            opacity: 0
                            scale: 0.85
                            transform: Translate {
                                id: cardTranslate
                                y: 25
                            }

                            ParallelAnimation {
                                id: entrance
                                SequentialAnimation {
                                    PauseAnimation { duration: card.delayBase }
                                    ParallelAnimation {
                                        NumberAnimation { target: card; property: "opacity"; to: 1.0; duration: 300 }
                                        NumberAnimation { target: card; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                                        NumberAnimation { target: cardTranslate; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                                    }
                                }
                                SequentialAnimation {
                                    PauseAnimation { duration: card.delayBase + 60 }
                                    ParallelAnimation {
                                        NumberAnimation { target: homeLogoCont; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                                        NumberAnimation { target: awayLogoCont; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                                    }
                                }
                                SequentialAnimation {
                                    PauseAnimation { duration: card.delayBase + 100 }
                                    ParallelAnimation {
                                        NumberAnimation { target: statusPill; property: "opacity"; to: 1.0; duration: 250 }
                                        NumberAnimation { target: statusPill; property: "scale"; to: 1.0; duration: 250; easing.type: Easing.OutBack }
                                    }
                                }
                                SequentialAnimation {
                                    PauseAnimation { duration: card.delayBase + 120 }
                                    ParallelAnimation {
                                        NumberAnimation { target: homeTeamName; property: "opacity"; to: 1.0; duration: 250 }
                                        NumberAnimation { target: awayTeamName; property: "opacity"; to: 1.0; duration: 250 }
                                    }
                                }
                                SequentialAnimation {
                                    PauseAnimation { duration: card.delayBase + 140 }
                                    NumberAnimation { target: leagueText; property: "opacity"; to: 1.0; duration: 250 }
                                }
                                SequentialAnimation {
                                    PauseAnimation { duration: card.delayBase + 180 }
                                    ParallelAnimation {
                                        NumberAnimation { target: homeScore; property: "opacity"; to: 1.0; duration: 250 }
                                        NumberAnimation { target: homeScore; property: "scale"; to: 1.0; duration: 250; easing.type: Easing.OutBack }
                                        NumberAnimation { target: awayScore; property: "opacity"; to: 1.0; duration: 250 }
                                        NumberAnimation { target: awayScore; property: "scale"; to: 1.0; duration: 250; easing.type: Easing.OutBack }
                                    }
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: Appearance.colors.colPrimaryContainer
                                opacity: card.isCurrent ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: card.model.link !== ""
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Qt.openUrlExternally(card.model.link);
                                    root.close();
                                }
                            }

                            Item {
                                width: parent.width
                                height: root.cardHeight
                                anchors.top: parent.top

                                Item {
                                    anchors.fill: parent
                                    anchors.margins: 20

                                    // Home Team
                                    Item {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 140
                                        height: 100

                                        Rectangle {
                                            id: homeLogoCont
                                            width: 72
                                            height: 72
                                            radius: root.radFull
                                            color: card.isCurrent ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                            anchors.top: parent.top
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            scale: 0.8

                                            StyledImage {
                                                anchors.fill: parent
                                                anchors.margins: 10
                                                source: card.model.homeLogo
                                                fillMode: Image.PreserveAspectFit
                                                mipmap: true
                                                smooth: true
                                                cache: false
                                            }
                                        }

                                        StyledText {
                                            id: homeTeamName
                                            anchors.top: homeLogoCont.bottom
                                            anchors.topMargin: 8
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: card.model.homeName
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            color: card.isCurrent ? Appearance.colors.colOnPrimaryContainer : root.colText
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                            elide: Text.ElideRight
                                            width: 130
                                            horizontalAlignment: Text.AlignHCenter
                                            opacity: 0
                                        }

                                        StyledText {
                                            id: homeScore
                                            anchors.left: homeLogoCont.right
                                            anchors.leftMargin: (text.length > 3) ? 4 : 12
                                            anchors.verticalCenter: homeLogoCont.verticalCenter
                                            text: card.model.homeScore
                                            font.pixelSize: (text.length > 3) ? 16 : 32
                                            font.weight: Font.DemiBold
                                            color: card.isCurrent ? Appearance.colors.colOnPrimaryContainer : root.colText
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                            visible: card.showScores
                                            opacity: 0
                                            scale: 0.9
                                        }
                                    }

                                    // Center Info
                                    Column {
                                        anchors.centerIn: parent
                                        width: 140
                                        spacing: 12

                                        Rectangle {
                                            id: statusPill
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            height: 32
                                            radius: root.radFull
                                            color: card.isCurrent ? Appearance.colors.colPrimary : root.colPill
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                            readonly property int dynamicPadding: card.model.matchState === "in" ? 20 : 6
                                            width: statusLabel.implicitWidth + (dynamicPadding * 2)
                                            opacity: 0
                                            scale: 0.9

                                            StyledText {
                                                id: statusLabel
                                                anchors.centerIn: parent
                                                text: card.model.statusText
                                                font.pixelSize: 14
                                                font.weight: Font.Bold
                                                color: card.isCurrent ? Appearance.colors.colOnPrimary : root.colOnPill
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                            }
                                        }

                                        StyledText {
                                            id: leagueText
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: card.model.league
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: Font.Light
                                            color: card.isCurrent ? Appearance.colors.colOnPrimaryContainer : root.colSubtext
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                            elide: Text.ElideRight
                                            width: 120
                                            horizontalAlignment: Text.AlignHCenter
                                            opacity: 0
                                        }
                                    }

                                    // Away Team
                                    Item {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 140
                                        height: 100

                                        Rectangle {
                                            id: awayLogoCont
                                            width: 72
                                            height: 72
                                            radius: root.radFull
                                            color: card.isCurrent ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                            anchors.top: parent.top
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            scale: 0.8

                                            StyledImage {
                                                anchors.fill: parent
                                                anchors.margins: 10
                                                source: card.model.awayLogo
                                                fillMode: Image.PreserveAspectFit
                                                mipmap: true
                                                smooth: true
                                                cache: false
                                            }
                                        }

                                        StyledText {
                                            id: awayTeamName
                                            anchors.top: awayLogoCont.bottom
                                            anchors.topMargin: 8
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: card.model.awayName
                                            font.pixelSize: Appearance.font.pixelSize.normal
                                            color: card.isCurrent ? Appearance.colors.colOnPrimaryContainer : root.colText
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                            elide: Text.ElideRight
                                            width: 130
                                            horizontalAlignment: Text.AlignHCenter
                                            opacity: 0
                                        }

                                        StyledText {
                                            id: awayScore
                                            anchors.right: awayLogoCont.left
                                            anchors.rightMargin: (text.length > 3) ? 4 : 12
                                            anchors.verticalCenter: awayLogoCont.verticalCenter
                                            text: card.model.awayScore
                                            font.pixelSize: (text.length > 3) ? 16 : 32
                                            font.weight: Font.DemiBold
                                            color: card.isCurrent ? Appearance.colors.colOnPrimaryContainer : root.colText
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                            visible: card.showScores
                                            opacity: 0
                                            scale: 0.9
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                width: parent.width - 40
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: root.cardHeight
                                height: 1
                                color: Appearance.colors.colOutline
                                opacity: 0.3
                                visible: card.hasLastPlay
                            }

                            StyledText {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 20
                                anchors.rightMargin: 20
                                height: 50
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                                text: card.model.lastPlay
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: card.isCurrent ? Appearance.colors.colOnPrimaryContainer : root.colSubtext
                                Behavior on color { ColorAnimation { duration: 200 } }
                                visible: card.hasLastPlay
                            }
                        }
                    }

                    StyledText {
                        visible: gamesModel.count === 0
                        width: root.cardWidth
                        height: root.cardHeight
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: Translation.tr("No matches found.")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }

            ScrollEdgeFade {
                target: flickable
                color: root.colBg
            }
        }
    }
}
