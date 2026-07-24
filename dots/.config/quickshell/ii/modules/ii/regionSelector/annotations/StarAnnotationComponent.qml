import QtQuick
import QtQuick.Shapes

// Five-pointed star annotation centred on (x, y).
Shape {
    id: starRoot
    property var annData: null
    readonly property var g: annData ? (annData.geom ?? annData) : null
    readonly property var s: annData ? (annData.style ?? annData) : null
    readonly property real outerR: g?.outerR ?? g?.outerRadius ?? 0
    readonly property real innerR: g?.innerR ?? g?.innerRadius ?? 0
    readonly property real cx: g?.x ?? 0
    readonly property real cy: g?.y ?? 0

    x: cx - outerR - 5
    y: cy - outerR - 5
    width: (outerR * 2) + 10
    height: (outerR * 2) + 10
    opacity: s?.opacity ?? 1
    visible: annData !== null

    ShapePath {
        strokeColor: starRoot.s?.stroke ?? starRoot.s?.color ?? "transparent"
        strokeWidth: starRoot.s?.strokeWidth ?? starRoot.s?.lineWidth ?? 2
        fillColor: {
            if (!starRoot.s || !starRoot.s.fill)
                return "transparent";
            var c = Qt.color(starRoot.s.fill);
            return Qt.rgba(c.r, c.g, c.b, starRoot.s.fillOpacity ?? 0.25);
        }
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin

        PathSvg {
            path: {
                if (!starRoot.g)
                    return "";
                var cx = starRoot.cx - starRoot.x;
                var cy = starRoot.cy - starRoot.y;
                var outerR = starRoot.outerR;
                var innerR = starRoot.innerR;
                var spikes = 5;
                var rot = Math.PI / 2 * 3;
                var step = Math.PI / spikes;

                var d = "";
                for (var i = 0; i < spikes; i++) {
                    var outerX = cx + Math.cos(rot) * outerR;
                    var outerY = cy + Math.sin(rot) * outerR;
                    d += (i === 0 ? "M " : " L ") + outerX + " " + outerY;
                    rot += step;
                    var innerX = cx + Math.cos(rot) * innerR;
                    var innerY = cy + Math.sin(rot) * innerR;
                    d += " L " + innerX + " " + innerY;
                    rot += step;
                }
                d += " Z";
                return d;
            }
        }
    }
}
