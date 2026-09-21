pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * Material 3 Sports Quick Toggle for Dynamic Island dashboard.
 *
 * Displays live scores, match status, and team logos.
 * Tapping outside edit mode cycles through today's matches.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Sports")

    readonly property var game: SportsService.currentGame
    readonly property bool hasGame: game !== null && game !== undefined
    readonly property bool isLive: hasGame && (game.state === "in")
    readonly property string matchStatus: hasGame
        ? SportsService.compactMatchStatus(game.status ?? "", game.state ?? "")
        : Translation.tr("No live games")

    readonly property bool isCompactH: root.surface.height < 76
    readonly property bool isSquare: Math.abs(root.surface.width - root.surface.height) < 40 && root.surface.width < 140
    readonly property bool isCard: !root.isCompactH && !root.isSquare

    // Poll ESPN only while this tile is actually on screen. The dashboard is
    // built once and kept, so a placement-keyed subscription never released and
    // the fetch loop ran forever behind a closed grid. `subscribed` keeps the
    // refcount balanced across show/hide cycles; the destruction release covers
    // the tile being removed while visible.
    property bool subscribed: false
    function syncSubscriber() {
        if (root.shownOnScreen && !root.subscribed) {
            SportsService.acquireWidgetSubscriber();
            root.subscribed = true;
        } else if (!root.shownOnScreen && root.subscribed) {
            SportsService.releaseWidgetSubscriber();
            root.subscribed = false;
        }
    }
    onShownOnScreenChanged: root.syncSubscriber()
    Component.onCompleted: root.syncSubscriber()
    Component.onDestruction: {
        if (root.subscribed)
            SportsService.releaseWidgetSubscriber();
    }

    // Interactive game switcher
    MouseArea {
        anchors.fill: parent
        enabled: !root.editMode
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (SportsService.allGames.length > 1)
                SportsService.nextGame();
        }
    }

    // ── 0. NO GAMES STANDBY STATE ────────────────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.margins: 8
        visible: !root.hasGame

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4

            MaterialShape {
                Layout.alignment: Qt.AlignHCenter
                implicitSize: Math.min(root.surface.width * 0.45, root.surface.height * 0.45, 42)
                shape: MaterialShape.Shape.Cookie9Sided
                color: Appearance.colors.colPrimaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "sports_soccer"
                    iconSize: Math.round(parent.implicitSize * 0.58)
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("Sports")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer2
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("No live games")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnLayer3
                visible: root.surface.height >= 70
            }
        }
    }

    // ── 1. COMPACT HORIZONTAL SCOREBOARD (2x1, 3x1, 4x1) ─────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: Math.max(6, Math.round(root.surface.height * 0.10))
        spacing: Math.max(4, Math.round(root.surface.width * 0.02))
        visible: root.hasGame && root.isCompactH

        // Home team logo
        StyledImage {
            Layout.preferredWidth: Math.min(parent.height - 4, 36)
            Layout.preferredHeight: Layout.preferredWidth
            Layout.alignment: Qt.AlignVCenter
            source: root.game?.home?.logo ?? ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }

        // Home score
        StyledText {
            Layout.alignment: Qt.AlignVCenter
            visible: root.game?.state !== "pre"
            text: root.game?.home?.score ?? "0"
            font.weight: Font.Black
            font.pixelSize: Appearance.font.pixelSize.normal
            color: root.isLive ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
        }

        Item { Layout.fillWidth: true }

        // Status pill
        Rectangle {
            Layout.preferredHeight: 22
            Layout.preferredWidth: Math.max(48, statusPillText.implicitWidth + (root.isLive ? 22 : 14))
            Layout.alignment: Qt.AlignVCenter
            radius: Appearance.rounding.full
            color: root.isLive ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest

            RowLayout {
                anchors.centerIn: parent
                spacing: 4

                // Pulsing dot for live games
                Rectangle {
                    visible: root.isLive
                    width: 6
                    height: 6
                    radius: 3
                    color: Appearance.colors.colOnPrimary

                    SequentialAnimation on opacity {
                        running: root.isLive && !root.isUnused
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 600 }
                        NumberAnimation { to: 1.0; duration: 600 }
                    }
                }

                StyledText {
                    id: statusPillText
                    text: root.matchStatus
                    font.weight: Font.Bold
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: root.isLive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                }
            }
        }

        Item { Layout.fillWidth: true }

        // Away score
        StyledText {
            Layout.alignment: Qt.AlignVCenter
            visible: root.game?.state !== "pre"
            text: root.game?.away?.score ?? "0"
            font.weight: Font.Black
            font.pixelSize: Appearance.font.pixelSize.normal
            color: root.isLive ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
        }

        // Away team logo
        StyledImage {
            Layout.preferredWidth: Math.min(parent.height - 4, 36)
            Layout.preferredHeight: Layout.preferredWidth
            Layout.alignment: Qt.AlignVCenter
            source: root.game?.away?.logo ?? ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }
    }

    // ── 2. 1x1 SQUARE MATCH ICON ─────────────────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.margins: 6
        visible: root.hasGame && root.isSquare

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4

                StyledImage {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    source: root.game?.home?.logo ?? ""
                    fillMode: Image.PreserveAspectFit
                }

                StyledImage {
                    Layout.preferredWidth: 26
                    Layout.preferredHeight: 26
                    source: root.game?.away?.logo ?? ""
                    fillMode: Image.PreserveAspectFit
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: root.game?.state !== "pre"
                text: `${root.game?.home?.score ?? "0"} - ${root.game?.away?.score ?? "0"}`
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Black
                color: root.isLive ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.matchStatus
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.isLive ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer3
            }
        }
    }

    // ── 3. RICH MATCH CARD (2x2, 3x2, 4x2, etc.) ─────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Math.max(8, Math.round(Math.min(root.surface.width, root.surface.height) * 0.06))
        spacing: 8
        visible: root.hasGame && root.isCard

        // Header: League name & Live / Status Badge
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                text: "sports_soccer"
                iconSize: 18
                color: Appearance.colors.colPrimary
            }

            StyledText {
                text: root.game?.league ?? Translation.tr("Sports")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer2
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            StyledText {
                visible: SportsService.allGames.length > 1
                text: `${SportsService.currentGameIndex + 1}/${SportsService.allGames.length}`
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnLayer3
            }

            Rectangle {
                Layout.preferredHeight: 20
                Layout.preferredWidth: cardStatusText.implicitWidth + (root.isLive ? 18 : 12)
                radius: Appearance.rounding.full
                color: root.isLive ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    Rectangle {
                        visible: root.isLive
                        width: 5
                        height: 5
                        radius: 2.5
                        color: Appearance.colors.colOnPrimary

                        SequentialAnimation on opacity {
                            running: root.isLive && !root.isUnused
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 600 }
                            NumberAnimation { to: 1.0; duration: 600 }
                        }
                    }

                    StyledText {
                        id: cardStatusText
                        text: root.matchStatus
                        font.weight: Font.Bold
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: root.isLive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        // Center: Teams, Logos and Scores
        Item {
            Layout.fillWidth: true
            implicitHeight: Math.max(
                Math.min(root.surface.height * 0.30, 48) + 26,
                scoreContent.implicitHeight
            )

            // 1. Dead center: Scores / VS badge
            Item {
                id: scoreCenterContainer
                anchors.centerIn: parent
                width: scoreContent.width
                height: scoreContent.height

                Column {
                    id: scoreContent
                    anchors.centerIn: parent
                    spacing: 2

                    Row {
                        visible: root.game?.state !== "pre"
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8

                        StyledText {
                            text: root.game?.home?.score ?? "0"
                            font.pixelSize: Math.max(22, Math.min(root.surface.height * 0.25, 36))
                            font.weight: Font.Black
                            color: root.isLive ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            text: "-"
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnLayer3
                        }

                        StyledText {
                            text: root.game?.away?.score ?? "0"
                            font.pixelSize: Math.max(22, Math.min(root.surface.height * 0.25, 36))
                            font.weight: Font.Black
                            color: root.isLive ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                        }
                    }

                    Rectangle {
                        visible: root.game?.state === "pre"
                        width: 32
                        height: 32
                        radius: 16
                        color: Appearance.colors.colSurfaceContainerHighest
                        anchors.horizontalCenter: parent.horizontalCenter

                        StyledText {
                            anchors.centerIn: parent
                            text: "VS"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnLayer3
                        }
                    }
                }
            }

            // 2. Home team (left half, perfectly mirrored)
            Item {
                anchors.left: parent.left
                anchors.right: scoreCenterContainer.left
                anchors.rightMargin: 6
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 4

                    StyledImage {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(root.surface.height * 0.30, 48)
                        height: width
                        source: root.game?.home?.logo ?? ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                    }

                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.game?.home?.name ?? root.game?.home?.abbreviation ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                        elide: Text.ElideRight
                    }
                }
            }

            // 3. Away team (right half, perfectly mirrored)
            Item {
                anchors.left: scoreCenterContainer.right
                anchors.leftMargin: 6
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 4

                    StyledImage {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(root.surface.height * 0.30, 48)
                        height: width
                        source: root.game?.away?.logo ?? ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                    }

                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.game?.away?.name ?? root.game?.away?.abbreviation ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        // Bottom: cycle games hint
        RowLayout {
            visible: SportsService.allGames.length > 1
            Layout.alignment: Qt.AlignHCenter
            spacing: 4

            MaterialSymbol {
                text: "touch_app"
                iconSize: 12
                color: Appearance.colors.colOnLayer3
            }

            StyledText {
                text: Translation.tr("Click to switch match")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnLayer3
            }
        }
    }
}
