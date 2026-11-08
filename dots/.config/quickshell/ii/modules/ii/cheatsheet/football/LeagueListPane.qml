import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Every competition the page knows. The switch follows a competition (its
 * matches join the Matches tab); the row opens its table and current round.
 */
Rectangle {
    id: root

    property string selectedSlug: ""
    signal leagueActivated(string slug)

    color: FootballStyle.colPane
    radius: FootballStyle.radiusCard

    readonly property var followed: FootballService.leagueCatalog.filter(league => FootballService.isLeagueEnabled(league.slug))
    readonly property var others: FootballService.leagueCatalog.filter(league => !FootballService.isLeagueEnabled(league.slug))

    component LeagueGroup: ColumnLayout {
        id: group
        property string title: ""
        property var leagues: []
        Layout.fillWidth: true
        spacing: 2
        visible: group.leagues.length > 0

        StyledText {
            Layout.leftMargin: 4
            Layout.bottomMargin: 4
            text: group.title
            font.pixelSize: FootballStyle.textSmall
            font.weight: Font.Bold
            color: FootballStyle.colOnSurfaceVariant
        }
        Repeater {
            model: group.leagues
            delegate: EntityRow {
                id: row
                required property var modelData
                required property int index
                Layout.fillWidth: true
                logo: row.modelData.logo
                title: row.modelData.name
                subtitle: row.modelData.country
                selected: root.selectedSlug === row.modelData.slug
                isFirst: row.index === 0
                isLast: row.index === group.leagues.length - 1
                prevSelected: row.index > 0 && group.leagues[row.index - 1].slug === root.selectedSlug
                nextSelected: row.index < group.leagues.length - 1 && group.leagues[row.index + 1].slug === root.selectedSlug
                onClicked: root.leagueActivated(row.modelData.slug)

                StyledSwitch {
                    checked: FootballService.isLeagueEnabled(row.modelData.slug)
                    onClicked: FootballService.setLeagueEnabled(row.modelData.slug, checked)
                    StyledToolTip {
                        text: Translation.tr("Show its matches in Matches")
                    }
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: FootballStyle.panePadding
        spacing: FootballStyle.gap

        PaneHeader {
            title: Translation.tr("Competitions")
            subtitle: Translation.tr("%1 followed").arg(root.followed.length)
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
                LeagueGroup {
                    title: Translation.tr("Following")
                    leagues: root.followed
                }
                LeagueGroup {
                    title: Translation.tr("More competitions")
                    leagues: root.others
                }
            }
        }

        ScrollEdgeFade {
            target: flick
            color: FootballStyle.colPane
        }
        }
    }
}
