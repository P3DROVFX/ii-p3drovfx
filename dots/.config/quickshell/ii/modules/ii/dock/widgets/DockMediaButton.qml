import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import "../"

DockButton {
    id: root
    property string symbolName: ""
    property real iconScale: 0.72

    buttonRadius: Appearance.rounding.full
    
    MaterialSymbol {
        renderType: Text.CurveRendering
        anchors.centerIn: parent
        iconSize: root.height * root.iconScale
        fill: 1
        text: root.symbolName
        color: Appearance.colors.colOnLayer0
    }
}
