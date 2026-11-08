import QtQuick
import QtQuick.Shapes
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "FootballFormat.js" as Format

/**
 * Both starting elevens on one pitch, home attacking right and away attacking
 * left, each laid out by its formation. Markers carry the shirt number and the
 * player's goals, bookings and substitution.
 */
Item {
    id: root

    property var homeLineup: null
    property var awayLineup: null
    property var positions: null
    property string homeName: ""
    property string awayName: ""

    readonly property var homeLines: Format.formationLines(root.homeLineup, root.positions)
    readonly property var awayLines: Format.formationLines(root.awayLineup, root.positions)
    readonly property real markerSize: Math.round(Math.max(28, Math.min(38, root.height / 11)))

    implicitHeight: Math.round(Math.max(380, Math.min(560, width * 0.56)))

    // Flatten a side into positioned players.
    function placed(lines, home) {
        const result = [];
        const count = lines.length;
        for (let i = 0; i < count; i++) {
            const line = lines[i];
            // Keeper near the goal line, forwards near (not on) halfway.
            const depth = count > 1 ? i / (count - 1) : 0;
            const xFraction = 0.05 + depth * 0.39;
            for (let j = 0; j < line.length; j++) {
                const lateral = (j + 1) / (line.length + 1);
                result.push({
                    player: line[j],
                    x: home ? xFraction : 1 - xFraction,
                    // Home attacks right: its left flank is at the top.
                    y: home ? lateral : 1 - lateral
                });
            }
        }
        return result;
    }

    Rectangle {
        id: pitch
        anchors.fill: parent
        radius: FootballStyle.radiusLarge
        color: FootballStyle.colRow

        // Markings, drawn as an illustration of the pitch.
        Shape {
            id: marks
            anchors.fill: parent
            anchors.margins: 14
            preferredRendererType: Shape.CurveRenderer
            readonly property real w: width
            readonly property real h: height
            readonly property real boxDepth: w * 0.13
            readonly property real boxHeight: h * 0.56
            readonly property real smallDepth: w * 0.05
            readonly property real smallHeight: h * 0.26
            readonly property real circle: h * 0.17

            ShapePath {
                strokeColor: FootballStyle.colOutline
                strokeWidth: 1.5
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                // Outline and halfway line
                PathRectangle { x: 0; y: 0; width: marks.w; height: marks.h; radius: FootballStyle.radiusSmall }
                PathMove { x: marks.w / 2; y: 0 }
                PathLine { x: marks.w / 2; y: marks.h }
                // Penalty and goal areas
                PathRectangle { x: 0; y: (marks.h - marks.boxHeight) / 2; width: marks.boxDepth; height: marks.boxHeight }
                PathRectangle { x: marks.w - marks.boxDepth; y: (marks.h - marks.boxHeight) / 2; width: marks.boxDepth; height: marks.boxHeight }
                PathRectangle { x: 0; y: (marks.h - marks.smallHeight) / 2; width: marks.smallDepth; height: marks.smallHeight }
                PathRectangle { x: marks.w - marks.smallDepth; y: (marks.h - marks.smallHeight) / 2; width: marks.smallDepth; height: marks.smallHeight }
                // Centre circle
                PathAngleArc { centerX: marks.w / 2; centerY: marks.h / 2; radiusX: marks.circle; radiusY: marks.circle; startAngle: 0; sweepAngle: 360 }
            }
        }

        // Formation labels
        StyledText {
            x: 24
            y: 18
            text: `${root.homeName}  ${root.homeLineup?.formation ?? ""}`
            font.pixelSize: FootballStyle.textSmall
            font.weight: Font.Bold
            color: FootballStyle.colPrimary
        }
        StyledText {
            anchors.right: parent.right
            anchors.rightMargin: 24
            y: 18
            text: `${root.awayLineup?.formation ?? ""}  ${root.awayName}`
            font.pixelSize: FootballStyle.textSmall
            font.weight: Font.Bold
            color: FootballStyle.colTertiary
        }

        Repeater {
            model: root.placed(root.homeLines, true).concat(root.placed(root.awayLines, false).map(item => Object.assign({ away: true }, item)))
            delegate: Item {
                id: marker
                required property var modelData
                readonly property var player: marker.modelData.player
                readonly property bool away: marker.modelData.away === true

                width: 96
                height: root.markerSize + 22
                x: Math.round(14 + (pitch.width - 28) * marker.modelData.x - width / 2)
                y: Math.round(28 + (pitch.height - 44) * marker.modelData.y - root.markerSize / 2 - 6)

                Rectangle {
                    id: shirt
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.markerSize
                    height: root.markerSize
                    radius: width / 2
                    color: marker.away ? FootballStyle.colTertiary : FootballStyle.colPrimary
                    StyledText {
                        shouldUseNumberFont: false
                        anchors.centerIn: parent
                        text: marker.player.jersey
                        font.pixelSize: Math.round(root.markerSize * 0.42)
                        font.variableAxes: FootballStyle.axesScore
                        color: marker.away ? FootballStyle.colOnTertiary : FootballStyle.colOnPrimary
                    }

                    // Goals: one ball per goal at the top right.
                    Row {
                        anchors.left: parent.right
                        anchors.leftMargin: -6
                        anchors.top: parent.top
                        anchors.topMargin: -4
                        spacing: -6
                        Repeater {
                            model: Math.min(3, marker.player.goals)
                            delegate: Rectangle {
                                width: 16
                                height: 16
                                radius: 8
                                color: FootballStyle.colField
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "sports_soccer"
                                    iconSize: 13
                                    fill: 1
                                    color: FootballStyle.colOnSurface
                                }
                            }
                        }
                    }
                    CardGlyph {
                        visible: marker.player.yellow > 0 || marker.player.red > 0
                        red: marker.player.red > 0
                        cardHeight: 13
                        anchors.right: parent.left
                        anchors.rightMargin: -5
                        anchors.top: parent.top
                        anchors.topMargin: -3
                    }
                    Rectangle {
                        visible: marker.player.subbedOut
                        width: 16
                        height: 16
                        radius: 8
                        anchors.right: parent.left
                        anchors.rightMargin: -6
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: -3
                        color: FootballStyle.colSecondaryContainer
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "arrow_downward"
                            iconSize: 12
                            color: FootballStyle.colOnSecondaryContainer
                        }
                    }
                }
                StyledText {
                    anchors.top: shirt.bottom
                    anchors.topMargin: 3
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: marker.player.last
                    elide: Text.ElideRight
                    font.pixelSize: FootballStyle.textSmaller
                    font.weight: Font.DemiBold
                    color: FootballStyle.colOnSurface
                }
            }
        }
    }
}
