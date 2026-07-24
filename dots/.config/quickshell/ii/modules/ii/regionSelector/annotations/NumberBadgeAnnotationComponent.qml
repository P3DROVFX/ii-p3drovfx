import QtQuick

// Auto-incrementing number badge: a filled circle centred on (x, y) with the
// number drawn on top. The circle fill uses the stroke colour.
Item {
    id: badgeRoot
    property var annData: null
    readonly property var g: annData ? (annData.geom ?? annData) : null
    readonly property var s: annData ? (annData.style ?? annData) : null
    readonly property real r: g?.r ?? 16

    x: (g?.x ?? 0) - r
    y: (g?.y ?? 0) - r
    width: r * 2
    height: r * 2
    opacity: s?.opacity ?? 1
    visible: annData !== null

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: badgeRoot.s?.stroke ?? badgeRoot.s?.color ?? "#ff3b30"
    }

    Text {
        anchors.centerIn: parent
        text: String(badgeRoot.g?.n ?? "")
        color: "#ffffff"
        font.bold: true
        font.pixelSize: badgeRoot.r
    }
}
