pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets

MaterialShape {
    id: root

    property color badgeColor: Appearance.colors.colLayer2
    property color glyphColor: Appearance.colors.colOnLayer2

    readonly property string superGlyph: {
        const configured = String(Config.options.cheatsheet.superKey ?? "").trim();
        return configured.length > 0 ? configured : "󰘵";
    }

    implicitSize: Appearance.font.pixelSize.huge
    shape: MaterialShape.Shape.Circle
    color: root.badgeColor

    StyledText {
        anchors.centerIn: parent
        width: parent.width - 6
        height: parent.height - 6
        text: root.superGlyph
        font.family: Appearance.font.family.iconNerd
        font.pixelSize: Appearance.font.pixelSize.smallie
        fontSizeMode: Text.Fit
        minimumPixelSize: Appearance.font.pixelSize.smallest
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: root.glyphColor
    }
}
