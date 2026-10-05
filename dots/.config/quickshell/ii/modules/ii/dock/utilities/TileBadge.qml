import QtQuick
import qs.modules.common.widgets

/** A symbol on a Material shape, sharp under the lens (TileShape + TileSymbol). */
Item {
    id: badge

    property alias shape: plate.shape
    property alias shapeName: plate.shapeName
    property alias color: plate.color
    property alias renderScale: plate.renderScale
    property alias text: glyph.text
    property alias colSymbol: glyph.color
    property alias fill: glyph.fill
    property real iconScale: 0.5
    property real implicitSize: 0

    implicitWidth: badge.implicitSize
    implicitHeight: badge.implicitSize

    TileShape {
        id: plate
        anchors.fill: parent
    }
    TileSymbol {
        id: glyph
        anchors.centerIn: parent
        iconSize: Math.round(Math.min(badge.width, badge.height) * badge.iconScale)
        fill: 1
    }
}
