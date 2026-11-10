import QtQuick
import QtQuick.Shapes

/**
 * A frequency response as a line over a soft fill: `values` are dB at log-spaced
 * frequencies, 0 dB in the middle and ±`range` at the edges. A second trace
 * (`secondary`) draws over it for a split equalizer's other channel.
 *
 * Vector, not painted: it follows its size without repainting, so a card that grows with
 * the window costs nothing. `grid` adds the dashed level lines; `highlight` (0..1 along
 * the frequency axis) marks the band being edited.
 */
Item {
    id: root

    property var values: []
    property var secondary: []
    property real range: 12
    property color colLine: EasyEffectsStyle.colPrimary
    property color colFill: EasyEffectsStyle.tint(root.colLine, EasyEffectsStyle.tintHover)
    property color colSecondary: EasyEffectsStyle.colTertiary
    property color colGrid: EasyEffectsStyle.tint(EasyEffectsStyle.colSubtext, EasyEffectsStyle.tintGrid)
    property real lineWidth: 4
    property bool grid: false
    property bool fill: true
    property real highlight: -1

    readonly property real inset: root.lineWidth / 2

    function toPoints(list: var): var {
        const count = list.length;
        if (count < 2 || root.width <= 0 || root.height <= 0)
            return [];
        const top = root.inset;
        const span = Math.max(1, root.height - root.inset * 2);
        const wide = Math.max(1, root.width - root.inset * 2);
        const points = [];
        for (let i = 0; i < count; i++) {
            const db = Math.max(-root.range, Math.min(root.range, Number(list[i]) || 0));
            points.push(Qt.point(root.inset + wide * i / (count - 1), top + span * (1 - (db + root.range) / (2 * root.range))));
        }
        return points;
    }

    readonly property var line: root.toPoints(root.values)
    readonly property var line2: root.toPoints(root.secondary)
    readonly property var area: root.line.length < 2 ? [] : root.line.concat([
        Qt.point(root.width - root.inset, root.height), Qt.point(root.inset, root.height)
    ])

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.grid ? root.colGrid : "transparent"
            strokeWidth: 1
            strokeStyle: ShapePath.DashLine
            dashPattern: [3, 7]

            PathMove { x: 0; y: root.height * 0.25 }
            PathLine { x: root.width; y: root.height * 0.25 }
            PathMove { x: 0; y: root.height * 0.5 }
            PathLine { x: root.width; y: root.height * 0.5 }
            PathMove { x: 0; y: root.height * 0.75 }
            PathLine { x: root.width; y: root.height * 0.75 }
        }

        ShapePath {
            fillColor: root.fill ? root.colFill : "transparent"
            strokeColor: "transparent"

            PathPolyline {
                path: root.area
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.colSecondary
            strokeWidth: root.line2.length > 1 ? root.lineWidth : 0
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathPolyline {
                path: root.line2
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.colLine
            strokeWidth: root.lineWidth
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathPolyline {
                path: root.line
            }
        }
    }

    Rectangle {
        visible: root.highlight >= 0
        x: root.inset + (root.width - root.inset * 2) * root.highlight - width / 2
        width: root.lineWidth * 2
        height: root.height
        radius: width / 2
        color: EasyEffectsStyle.tint(root.colLine, EasyEffectsStyle.tintHover)
    }
}
