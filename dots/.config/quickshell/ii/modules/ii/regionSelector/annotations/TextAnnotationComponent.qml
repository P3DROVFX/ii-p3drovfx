import QtQuick

// Committed text annotation. The live editing happens in a TextInput inside
// RegionSelection; this only renders the finished string.
Text {
    id: textRoot
    property var annData: null
    readonly property var g: annData ? (annData.geom ?? annData) : null
    readonly property var s: annData ? (annData.style ?? annData) : null

    x: g?.x ?? 0
    y: g?.y ?? 0
    text: g?.text ?? ""
    color: s?.stroke ?? s?.color ?? "#ff3b30"
    font.pixelSize: s?.fontPx ?? 20
    opacity: s?.opacity ?? 1
    // Hide while the string is empty (e.g. mid-edit before commit).
    visible: annData !== null && (g?.text ?? "") !== ""
}
