import QtQuick

// Outlined circle annotation, centred on (x, y) with radius r.
Rectangle {
    property var annData: null
    readonly property var g: annData ? (annData.geom ?? annData) : null
    readonly property var s: annData ? (annData.style ?? annData) : null
    readonly property real r: g?.r ?? g?.radius ?? 0

    x: (g?.x ?? 0) - r
    y: (g?.y ?? 0) - r
    width: r * 2
    height: r * 2
    color: {
        if (!s || !s.fill)
            return "transparent";
        var c = Qt.color(s.fill);
        return Qt.rgba(c.r, c.g, c.b, s.fillOpacity ?? 0.25);
    }
    opacity: s?.opacity ?? 1
    border.color: s?.stroke ?? s?.color ?? "transparent"
    border.width: s?.strokeWidth ?? s?.lineWidth ?? 2
    radius: width / 2
    visible: annData !== null
}
