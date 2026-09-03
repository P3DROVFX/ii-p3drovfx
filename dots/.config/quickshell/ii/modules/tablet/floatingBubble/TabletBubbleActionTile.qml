import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

/**
 * One action in the bubble's sheet: a large glyph over its name.
 *
 * Sized well past the minimum touch target on purpose. The sheet is reached one-handed,
 * often while holding the device, and it is the surface the user goes to precisely when
 * aiming carefully is hardest — so the tiles are the size Android uses for its own quick
 * settings rather than the size a menu row would be.
 */
RippleButton {
    id: root

    property string symbol: ""
    property string label: ""
    property real tileSize: 84

    signal triggered

    implicitWidth: root.tileSize
    implicitHeight: root.tileSize
    buttonRadius: Appearance.rounding.large
    buttonRadiusPressed: Appearance.rounding.normal
    colBackground: Appearance.colors.colLayer1
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colBackgroundActive: Appearance.colors.colLayer1Active
    colRipple: Appearance.colors.colLayer1Active
    releaseAction: () => root.triggered()

    contentItem: ColumnLayout {
        anchors.centerIn: parent
        spacing: 4

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: root.symbol
            iconSize: Math.round(root.tileSize * 0.36)
            fill: 0
            color: Appearance.colors.colOnLayer1
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: root.tileSize - 12
            text: root.label
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnLayer1
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }
}
