import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The match's key moments as a two-sided timeline: home events on the left,
 * away on the right, the minute in the middle; phases (kickoff, half time,
 * full time) cross the whole width as captions.
 */
ColumnLayout {
    id: root

    property var events: []
    // Newest first reads like a live feed; finished matches read top-down.
    property bool newestFirst: false

    readonly property var ordered: root.newestFirst ? root.events.slice().reverse() : root.events

    spacing: 4

    Repeater {
        model: root.ordered
        delegate: Item {
            id: row
            required property var modelData
            readonly property var event: row.modelData
            readonly property bool phase: row.event.kind === "phase" || row.event.side === ""
            readonly property bool home: row.event.side === "home"

            Layout.fillWidth: true
            implicitHeight: row.phase ? 34 : Math.max(48, sideColumn.implicitHeight + 12)

            // Phase caption
            Rectangle {
                visible: row.phase
                anchors.centerIn: parent
                height: 26
                width: phaseText.implicitWidth + 24
                radius: 13
                color: FootballStyle.colSecondaryContainer
                StyledText {
                    id: phaseText
                    anchors.centerIn: parent
                    text: [row.event.label, row.event.minute].filter(part => part !== "").join(" · ")
                    font.pixelSize: FootballStyle.textSmaller
                    font.weight: Font.Bold
                    color: FootballStyle.colOnSecondaryContainer
                }
            }

            // Minute in the middle
            Rectangle {
                visible: !row.phase
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: 46
                height: 28
                radius: row.event.kind === "goal" || row.event.kind === "own" ? FootballStyle.radiusSmall * 0.8 : 14
                color: row.event.kind === "goal" || row.event.kind === "own" ? FootballStyle.colPrimary : FootballStyle.colField
                StyledText {
                    shouldUseNumberFont: false
                    anchors.centerIn: parent
                    text: row.event.minute
                    font.pixelSize: FootballStyle.textSmall
                    font.variableAxes: FootballStyle.axesCondensed
                    color: row.event.kind === "goal" || row.event.kind === "own" ? FootballStyle.colOnPrimary : FootballStyle.colOnSurface
                }
            }

            // The event on its team's side
            RowLayout {
                id: sideRow
                visible: !row.phase
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width / 2 - 34
                x: row.home ? 0 : parent.width / 2 + 34
                layoutDirection: row.home ? Qt.RightToLeft : Qt.LeftToRight
                spacing: FootballStyle.gapSmall

                Item {
                    implicitWidth: 28
                    implicitHeight: 28
                    Layout.alignment: Qt.AlignVCenter
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: row.event.kind !== "yellow" && row.event.kind !== "red"
                        text: row.event.kind === "goal" || row.event.kind === "own" ? "sports_soccer"
                            : row.event.kind === "sub" ? "swap_vert"
                            : row.event.kind === "var" ? "videocam"
                            : row.event.kind === "penmiss" ? "block" : "info"
                        iconSize: 22
                        fill: 1
                        color: row.event.kind === "goal" ? FootballStyle.colPrimary
                            : row.event.kind === "own" ? FootballStyle.colOnSurfaceVariant : FootballStyle.colOnSurfaceVariant
                    }
                    CardGlyph {
                        anchors.centerIn: parent
                        visible: row.event.kind === "yellow" || row.event.kind === "red"
                        red: row.event.kind === "red"
                        cardHeight: 18
                    }
                }

                ColumnLayout {
                    id: sideColumn
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: row.home ? Text.AlignRight : Text.AlignLeft
                        text: row.event.kind === "goal" || row.event.kind === "own" ? (row.event.players[0] ?? row.event.label).toUpperCase() : (row.event.players[0] ?? row.event.label)
                        elide: Text.ElideRight
                        font.pixelSize: row.event.kind === "goal" || row.event.kind === "own" ? FootballStyle.textLarge : FootballStyle.textNormal
                        font.variableAxes: row.event.kind === "goal" || row.event.kind === "own" ? FootballStyle.axesHeadline : Appearance.font.variableAxes.main
                        font.weight: Font.DemiBold
                        color: row.event.kind === "sub" ? FootballStyle.colPrimary : FootballStyle.colOnSurface
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text !== ""
                        horizontalAlignment: row.home ? Text.AlignRight : Text.AlignLeft
                        text: row.event.kind === "sub" ? (row.event.players[1] ?? "")
                            : row.event.kind === "goal" && row.event.players.length > 1 ? Translation.tr("Assist: %1").arg(row.event.players[1])
                            : row.event.kind === "own" ? Translation.tr("Own goal")
                            : row.event.label
                        elide: Text.ElideRight
                        font.pixelSize: FootballStyle.textSmaller
                        color: FootballStyle.colSubtext
                    }
                }
            }
        }
    }
}
