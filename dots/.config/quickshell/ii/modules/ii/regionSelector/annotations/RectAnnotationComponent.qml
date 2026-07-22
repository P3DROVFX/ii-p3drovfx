import QtQuick

// Outlined rectangle annotation. Reads the new { geom, style } shape,
// falling back to the legacy flat dict so old snapshots still render.
Rectangle {
    property var annData: null
    readonly property var g: annData ? (annData.geom ?? annData) : null
    readonly property var s: annData ? (annData.style ?? annData) : null

    x: g?.x ?? 0
    y: g?.y ?? 0
    width: g?.w ?? g?.width ?? 0
    height: g?.h ?? g?.height ?? 0
    color: "transparent"
    border.color: s?.stroke ?? s?.color ?? "#ff3b30"
    border.width: s?.strokeWidth ?? s?.lineWidth ?? 2
    radius: 0
    visible: annData !== null
}
