pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * Material 3 Sports Card Quick Toggle for Dynamic Island dashboard.
 *
 * Dedicated rich card variant with prominent team presentation,
 * live match progress, and period scores.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Sports Card")

    readonly property var game: SportsService.currentGame
    readonly property bool hasGame: game !== null && game !== undefined
    readonly property bool isLive: hasGame && (game.state === "in")
    readonly property string matchStatus: hasGame
        ? SportsService.compactMatchStatus(game.status ?? "", game.state ?? "")
        : Translation.tr("No live games")

    onIsUnusedChanged: {
        if (!root.isUnused)
            SportsService.acquireWidgetSubscriber();
        else
            SportsService.releaseWidgetSubscriber();
    }
    Component.onCompleted: {
        if (!root.isUnused)
            SportsService.acquireWidgetSubscriber();
    }
    Component.onDestruction: {
        if (!root.isUnused)
            SportsService.releaseWidgetSubscriber();
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.editMode
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (SportsService.allGames.length > 1)
                SportsService.nextGame();
        }
    }

    // Standby when no games
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
                    text: "scoreboard"
                    iconSize: Math.round(parent.implicitSize * 0.58)
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("Sports Card")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer2
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("No live games")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnLayer3
            }
        }
    }

    // Active Card Layout
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Math.max(8, Math.round(Math.min(root.surface.width, root.surface.height) * 0.06))
        spacing: 8
        visible: root.hasGame

        // Top bar
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                Layout.preferredHeight: 22
                Layout.preferredWidth: leagueText.implicitWidth + 14
                radius: Appearance.rounding.full
                color: Appearance.colors.colSurfaceContainerHighest

                StyledText {
                    id: leagueText
                    anchors.centerIn: parent
                    text: root.game?.league ?? Translation.tr("Sports")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer2
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredHeight: 22
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

        // Teams & Scores
        Item {
            Layout.fillWidth: true
            implicitHeight: Math.max(
                Math.min(root.surface.height * 0.32, 48) + 26,
                cardScoreContent.implicitHeight
            )

            // 1. Dead center: Scores / VS badge
            Item {
                id: cardScoreCenterContainer
                anchors.centerIn: parent
                width: cardScoreContent.width
                height: cardScoreContent.height

                Column {
                    id: cardScoreContent
                    anchors.centerIn: parent
                    spacing: 2

                    Row {
                        visible: root.game?.state !== "pre"
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8

                        StyledText {
                            text: root.game?.home?.score ?? "0"
                            font.pixelSize: Math.max(24, Math.min(root.surface.height * 0.28, 40))
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
                            font.pixelSize: Math.max(24, Math.min(root.surface.height * 0.28, 40))
                            font.weight: Font.Black
                            color: root.isLive ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
                        }
                    }

                    Rectangle {
                        visible: root.game?.state === "pre"
                        width: 36
                        height: 36
                        radius: 18
                        color: Appearance.colors.colSurfaceContainerHighest
                        anchors.horizontalCenter: parent.horizontalCenter

                        StyledText {
                            anchors.centerIn: parent
                            text: "VS"
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnLayer3
                        }
                    }
                }
            }

            // 2. Home team (left half, perfectly mirrored)
            Item {
                anchors.left: parent.left
                anchors.right: cardScoreCenterContainer.left
                anchors.rightMargin: 6
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 4

                    StyledImage {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(root.surface.height * 0.32, 48)
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
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer2
                        elide: Text.ElideRight
                    }
                }
            }

            // 3. Away team (right half, perfectly mirrored)
            Item {
                anchors.left: cardScoreCenterContainer.right
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
                        width: Math.min(root.surface.height * 0.32, 48)
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
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer2
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        // Bottom: game counter
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
                text: `${SportsService.currentGameIndex + 1} / ${SportsService.allGames.length} - ${Translation.tr("Click to switch match")}`
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnLayer3
            }
        }
    }
}
