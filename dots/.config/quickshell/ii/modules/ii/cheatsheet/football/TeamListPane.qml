import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.services

/**
 * Teams: a search over every ESPN football club and the starred favourites.
 * The star toggles a favourite in place; the row opens the team.
 */
Rectangle {
    id: root

    property string selectedTeamId: ""
    signal teamActivated(var team)

    property alias searchField: field

    color: FootballStyle.colPane
    radius: FootballStyle.radiusCard

    readonly property bool searching: FootballService.searchQuery.length >= 2

    Timer {
        id: debounce
        interval: 350
        onTriggered: FootballService.searchTeams(field.text)
    }

    component TeamGroup: ColumnLayout {
        id: group
        property string title: ""
        property var teams: []
        Layout.fillWidth: true
        spacing: 2
        visible: group.teams.length > 0

        StyledText {
            Layout.leftMargin: 4
            Layout.bottomMargin: 4
            text: group.title
            font.pixelSize: FootballStyle.textSmall
            font.weight: Font.Bold
            color: FootballStyle.colOnSurfaceVariant
        }
        Repeater {
            model: group.teams
            delegate: EntityRow {
                id: row
                required property var modelData
                required property int index
                readonly property bool favorite: FootballService.isFavorite(row.modelData.id)
                Layout.fillWidth: true
                logo: row.modelData.logo
                title: row.modelData.name
                subtitle: row.modelData.subtitle ?? (FootballService.leagueBySlug(row.modelData.league)?.name ?? "")
                selected: root.selectedTeamId === row.modelData.id
                isFirst: row.index === 0
                isLast: row.index === group.teams.length - 1
                prevSelected: row.index > 0 && group.teams[row.index - 1].id === root.selectedTeamId
                nextSelected: row.index < group.teams.length - 1 && group.teams[row.index + 1].id === root.selectedTeamId
                onClicked: root.teamActivated(row.modelData)

                ClockIconButton {
                    symbol: "star"
                    filled: row.favorite
                    tooltip: row.favorite ? Translation.tr("Remove from favorites") : Translation.tr("Add to favorites")
                    colIcon: row.favorite ? FootballStyle.colPrimary : FootballStyle.colOnSurfaceVariant
                    onClicked: FootballService.toggleFavorite(row.modelData)
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: FootballStyle.panePadding
        spacing: FootballStyle.gap

        PaneHeader {
            title: Translation.tr("Teams")
            subtitle: FootballService.favoriteTeams.length > 0
                ? Translation.tr("%1 favorites").arg(FootballService.favoriteTeams.length)
                : Translation.tr("Search and star your clubs")
        }

        // Search field: the shape morphs while it has focus.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 52
            radius: field.activeFocus ? FootballStyle.radiusLarge : height / 2
            color: field.activeFocus ? FootballStyle.colField : FootballStyle.colRow
            Behavior on radius {
                enabled: !FootballStyle.reducedMotion
                animation: FootballStyle.motionFast.numberAnimation.createObject(this)
            }
            Behavior on color {
                animation: FootballStyle.motionFast.colorAnimation.createObject(this)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: FootballStyle.gapSmall

                MaterialShapeWrappedMaterialSymbol {
                    text: "search"
                    iconSize: 18
                    padding: 8
                    shape: field.activeFocus ? MaterialShape.Shape.Sunny : MaterialShape.Shape.Clover4Leaf
                    color: FootballStyle.colPrimaryContainer
                    colSymbol: FootballStyle.colOnPrimaryContainer
                }
                ToolbarTextField {
                    id: field
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    colBackground: "transparent"
                    placeholderText: Translation.tr("Search teams")
                    font.pixelSize: FootballStyle.textNormal
                    onTextChanged: debounce.restart()
                    Keys.onEscapePressed: event => {
                        if (field.text.length > 0) {
                            field.clear();
                            event.accepted = true;
                        } else {
                            event.accepted = false;
                        }
                    }
                }
                ClockIconButton {
                    visible: field.text.length > 0
                    symbol: "close"
                    tooltip: Translation.tr("Clear")
                    onClicked: field.clear()
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledFlickable {
                id: flick
                anchors.fill: parent
                clip: true
                contentHeight: groups.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: groups
                    width: flick.width
                    spacing: FootballStyle.gapLarge
                    TeamGroup {
                        title: Translation.tr("Results")
                        teams: root.searching ? FootballService.searchResults : []
                    }
                    TeamGroup {
                        title: Translation.tr("Favorites")
                        teams: FootballService.favoriteTeams
                    }
                }
            }

            ScrollEdgeFade {
                target: flick
                color: FootballStyle.colPane
            }

            StyledIndeterminateProgressBar {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                visible: FootballService.searchLoading
            }

            ClockEmptyState {
                anchors.centerIn: parent
                width: parent.width
                visible: !FootballService.searchLoading && FootballService.favoriteTeams.length === 0
                    && (!root.searching || FootballService.searchResults.length === 0)
                symbol: root.searching ? "search_off" : "shield"
                shape: "Clover4Leaf"
                title: root.searching ? Translation.tr("No teams found") : Translation.tr("No favorite teams yet")
                subtitle: root.searching ? Translation.tr("Try the club's official name") : Translation.tr("Search a club and star it")
            }
        }
    }
}
