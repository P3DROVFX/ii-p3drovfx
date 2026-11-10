import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "FootballFormat.js" as Format

/**
 * One match in a list: state on the left, both teams stacked with their
 * scores. Rows of a group share one shape: ends rounded large, joins small,
 * and the selected row turns pill like the rail.
 */
RippleButton {
    id: root

    property var match: null
    property bool selected: false
    property bool isFirst: true
    property bool isLast: true
    property bool prevSelected: false
    property bool nextSelected: false
    // Team pages show the date and competition; a perspective team gets a
    // result chip (win / draw / loss).
    property bool showDate: false
    property bool showCompetition: false
    property string perspectiveTeamId: ""

    readonly property bool live: root.match?.state === "in"
    readonly property bool started: root.match ? root.match.state !== "pre" : false
    readonly property string result: {
        if (root.perspectiveTeamId === "" || root.match?.state !== "post")
            return "";
        const home = root.match.home, away = root.match.away;
        const own = root.perspectiveTeamId === home.id ? parseFloat(home.score) : parseFloat(away.score);
        const other = root.perspectiveTeamId === home.id ? parseFloat(away.score) : parseFloat(home.score);
        return own > other ? "W" : (own < other ? "L" : "D");
    }

    implicitHeight: root.showCompetition ? 76 : FootballStyle.rowHeight
    padding: 0
    toggled: root.selected
    colBackground: FootballStyle.colRow
    colBackgroundHover: FootballStyle.colRowHover
    colRipple: FootballStyle.colRowActive
    colBackgroundToggled: FootballStyle.colSecondaryContainer
    colBackgroundToggledHover: FootballStyle.colSecondaryContainerHover
    colRippleToggled: FootballStyle.colSecondaryContainerActive

    readonly property real pillRadius: Math.min(root.implicitHeight / 2, FootballStyle.radiusLarge)
    readonly property bool topPill: root.selected || root.down || root.prevSelected
    readonly property bool bottomPill: root.selected || root.down || root.nextSelected
    topLeftRadius: root.topPill ? root.pillRadius : (root.isFirst ? FootballStyle.radiusLarge : FootballStyle.radiusJoin)
    topRightRadius: root.topLeftRadius
    bottomLeftRadius: root.bottomPill ? root.pillRadius : (root.isLast ? FootballStyle.radiusLarge : FootballStyle.radiusJoin)
    bottomRightRadius: root.bottomLeftRadius
    Behavior on topLeftRadius {
        enabled: !FootballStyle.reducedMotion
        animation: FootballStyle.motionFast.numberAnimation.createObject(this)
    }
    Behavior on bottomLeftRadius {
        enabled: !FootballStyle.reducedMotion
        animation: FootballStyle.motionFast.numberAnimation.createObject(this)
    }

    readonly property color colText: root.selected ? FootballStyle.colOnSecondaryContainer : FootballStyle.colOnSurface
    readonly property color colMuted: root.selected ? FootballStyle.colOnSecondaryContainer : FootballStyle.colOnSurfaceVariant

    component TeamLine: RowLayout {
        id: line
        property var team: null
        property bool other: false
        spacing: FootballStyle.gapSmall
        Layout.fillWidth: true

        TeamCrest {
            size: 22
            source: line.team?.logo ?? ""
            plate: "transparent"
        }
        StyledText {
            Layout.fillWidth: true
            text: line.team?.name ?? ""
            elide: Text.ElideRight
            font.pixelSize: FootballStyle.textNormal
            font.weight: root.started && line.team?.winner ? Font.Bold : Font.Medium
            color: root.colText
            opacity: root.match?.state === "post" && !line.team?.winner && (line.other ? root.match?.home?.winner : root.match?.away?.winner) ? 0.7 : 1
        }
        MaterialSymbol {
            visible: FootballService.isFavorite(line.team?.id)
            text: "star"
            fill: 1
            iconSize: 14
            color: root.selected ? FootballStyle.colOnSecondaryContainer : FootballStyle.colPrimary
        }
        StyledText {
            visible: line.team?.shootout !== "" && line.team?.shootout !== undefined
            text: `(${line.team?.shootout ?? ""})`
            font.pixelSize: FootballStyle.textSmaller
            color: root.colMuted
        }
        StyledText {
            shouldUseNumberFont: false
            visible: root.started
            Layout.minimumWidth: 18
            horizontalAlignment: Text.AlignRight
            text: line.team?.score ?? ""
            font.pixelSize: FootballStyle.textLarger + 2
            font.family: FootballStyle.fontMain
            font.variableAxes: line.team?.winner || root.live || root.match?.state === "post" && root.match?.home?.score === root.match?.away?.score
                ? FootballStyle.axesScoreHeavy : FootballStyle.axesScoreLight
            color: root.live ? (root.selected ? FootballStyle.colOnSecondaryContainer : FootballStyle.colTertiary) : root.colText
        }
    }

    contentItem: Item {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: FootballStyle.gapLarge
            anchors.rightMargin: FootballStyle.gapLarge
            spacing: FootballStyle.gap

            // State column
            ColumnLayout {
                Layout.preferredWidth: root.showDate ? 64 : 52
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                StyledText {
                    visible: root.showDate
                    Layout.alignment: Qt.AlignHCenter
                    text: Format.shortDate(root.match?.date, Qt.locale(Translation.languageCode))
                    font.pixelSize: FootballStyle.textSmaller
                    font.weight: Font.DemiBold
                    color: root.colMuted
                }
                StatusPill {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.live
                    match: root.match
                    pillHeight: 22
                }
                StyledText {
                    visible: !root.live
                    Layout.alignment: Qt.AlignHCenter
                    text: Format.statusText(root.match, "")
                    font.pixelSize: root.match?.state === "pre" ? FootballStyle.textNormal : FootballStyle.textSmall
                    font.weight: root.match?.state === "pre" ? Font.DemiBold : Font.Medium
                    color: root.match?.state === "pre" ? root.colText : root.colMuted
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 3

                StyledText {
                    visible: root.showCompetition
                    Layout.fillWidth: true
                    text: root.match?.league?.name ?? ""
                    elide: Text.ElideRight
                    font.pixelSize: FootballStyle.textSmallest
                    font.weight: Font.Bold
                    color: root.colMuted
                }
                TeamLine { team: root.match?.home ?? null; other: false }
                TeamLine { team: root.match?.away ?? null; other: true }
            }

            Rectangle {
                visible: root.result !== ""
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 28
                implicitHeight: 28
                radius: root.result === "W" ? FootballStyle.radiusSmall * 0.7 : 14
                color: root.result === "W" ? FootballStyle.colPrimary
                    : root.result === "D" ? FootballStyle.colSecondaryContainer : FootballStyle.colField
                StyledText {
                    anchors.centerIn: parent
                    text: root.result === "W" ? FootballService.resultLetter("W") : root.result === "D" ? FootballService.resultLetter("D") : FootballService.resultLetter("L")
                    font.pixelSize: FootballStyle.textSmall
                    font.weight: Font.Black
                    color: root.result === "W" ? FootballStyle.colOnPrimary
                        : root.result === "D" ? FootballStyle.colOnSecondaryContainer : FootballStyle.colOnSurface
                }
            }
        }
    }
}
