import QtQuick

// A Material Symbols ligature, sized and filled like the shell's MaterialSymbol.
StyledText {
    id: root
    property real iconSize: Theme.pxSmall
    property real fill: 0
    readonly property real truncatedFill: root.fill >= 0.5 ? 1 : 0

    renderType: Text.CurveRendering
    antialiasing: true
    smooth: true
    horizontalAlignment: Text.AlignHCenter

    font {
        hintingPreference: Font.PreferNoHinting
        family: Theme.fontIcons
        pixelSize: root.iconSize
        weight: Font.Normal
        variableAxes: ({
                "FILL": root.truncatedFill,
                "wght": 400,
                "opsz": Math.max(20, Math.min(48, root.iconSize))
            })
    }
}
