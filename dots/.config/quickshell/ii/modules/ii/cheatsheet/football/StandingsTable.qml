import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * A league table: rank (with ESPN's qualification colour), club, played,
 * wins, draws, losses, goals and points. Highlighted clubs (the match's two)
 * fill with the secondary container; a row opens its club.
 */
ColumnLayout {
    id: root

    property var groups: []
    property string league: ""
    property bool showGoals: width > 620 && (root.groups[0]?.entries[0]?.goalsFor ?? "") !== ""
    signal teamActivated(var team)

    spacing: FootballStyle.gapLarge

    component Cell: StyledText {
        shouldUseNumberFont: false
        property bool strong: false
        Layout.preferredWidth: 34
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: FootballStyle.textSmall
        font.weight: strong ? Font.Bold : Font.Normal
        color: FootballStyle.colOnSurface
    }

    Repeater {
        model: root.groups
        delegate: ColumnLayout {
            id: group
            required property var modelData
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                visible: root.groups.length > 1 && group.modelData.name !== ""
                Layout.bottomMargin: 4
                text: group.modelData.name
                font.pixelSize: FootballStyle.textSmall
                font.weight: Font.Bold
                color: FootballStyle.colOnSurfaceVariant
            }

            // Header
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: FootballStyle.gap
                Layout.rightMargin: FootballStyle.gap
                spacing: 0
                Cell { text: "#"; color: FootballStyle.colSubtext }
                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 40
                    text: Translation.tr("Club")
                    font.pixelSize: FootballStyle.textSmaller
                    font.weight: Font.Bold
                    color: FootballStyle.colSubtext
                }
                Cell { text: Translation.tr("P"); color: FootballStyle.colSubtext }
                Cell { text: FootballService.resultLetter("W"); color: FootballStyle.colSubtext }
                Cell { text: FootballService.resultLetter("D"); color: FootballStyle.colSubtext }
                Cell { text: FootballService.resultLetter("L"); color: FootballStyle.colSubtext }
                Cell { visible: root.showGoals; text: Translation.tr("GF"); color: FootballStyle.colSubtext }
                Cell { visible: root.showGoals; text: Translation.tr("GA"); color: FootballStyle.colSubtext }
                Cell { text: Translation.tr("GD"); color: FootballStyle.colSubtext }
                Cell { text: Translation.tr("Pts"); color: FootballStyle.colSubtext; Layout.preferredWidth: 40 }
            }

            Repeater {
                model: group.modelData.entries
                delegate: RippleButton {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property var entry: row.modelData
                    readonly property int count: group.modelData.entries.length

                    Layout.fillWidth: true
                    implicitHeight: 40
                    padding: 0
                    toggled: row.entry.highlight || FootballService.isFavorite(row.entry.id)
                    colBackground: FootballStyle.colField
                    colBackgroundHover: FootballStyle.colFieldHover
                    colBackgroundToggled: FootballStyle.colSecondaryContainer
                    colBackgroundToggledHover: FootballStyle.colSecondaryContainerHover
                    topLeftRadius: row.index === 0 ? FootballStyle.radiusNormal : FootballStyle.radiusJoin
                    topRightRadius: topLeftRadius
                    bottomLeftRadius: row.index === row.count - 1 ? FootballStyle.radiusNormal : FootballStyle.radiusJoin
                    bottomRightRadius: bottomLeftRadius
                    onClicked: root.teamActivated({ id: row.entry.id, name: row.entry.name, logo: row.entry.logo, league: root.league })

                    readonly property color colText: row.toggled ? FootballStyle.colOnSecondaryContainer : FootballStyle.colOnSurface

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: FootballStyle.gap
                        anchors.rightMargin: FootballStyle.gap
                        spacing: 0

                        Item {
                            Layout.preferredWidth: 34
                            implicitHeight: 24
                            Rectangle {
                                visible: row.entry.noteColor !== ""
                                width: 4
                                height: 18
                                radius: 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: row.entry.noteColor !== "" ? row.entry.noteColor : "transparent"
                            }
                            StyledText {
                                anchors.centerIn: parent
                                text: row.entry.rank || (row.index + 1)
                                font.pixelSize: FootballStyle.textSmall
                                font.weight: Font.Bold
                                color: row.colText
                            }
                        }
                        TeamCrest {
                            size: 26
                            source: row.entry.logo
                            plate: "transparent"
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: FootballStyle.gapSmall
                            text: row.entry.name
                            elide: Text.ElideRight
                            font.pixelSize: FootballStyle.textSmall
                            font.weight: row.toggled ? Font.Bold : Font.Medium
                            color: row.colText
                        }
                        Cell { text: row.entry.played; color: row.colText }
                        Cell { text: row.entry.wins; color: row.colText }
                        Cell { text: row.entry.draws; color: row.colText }
                        Cell { text: row.entry.losses; color: row.colText }
                        Cell { visible: root.showGoals; text: row.entry.goalsFor; color: row.colText }
                        Cell { visible: root.showGoals; text: row.entry.goalsAgainst; color: row.colText }
                        Cell { text: row.entry.goalDiff; color: row.colText }
                        Cell {
                            shouldUseNumberFont: false
                            text: row.entry.points
                            strong: true
                            color: row.colText
                            Layout.preferredWidth: 40
                            font.variableAxes: FootballStyle.axesScoreHeavy
                            font.pixelSize: FootballStyle.textLarge
                        }
                    }
                }
            }
        }
    }
}
