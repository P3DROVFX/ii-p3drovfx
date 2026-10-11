import QtQuick

Text {
    renderType: Text.NativeRendering
    verticalAlignment: Text.AlignVCenter
    color: Theme.m3onSurface
    font {
        family: Theme.fontMain
        pixelSize: Theme.pxSmall
        hintingPreference: Font.PreferFullHinting
        variableAxes: Theme.axesMain
    }
    linkColor: Theme.m3primary
}
