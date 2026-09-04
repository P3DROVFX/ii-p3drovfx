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
    /// A bar across the sheet instead of a square in the grid: glyph and label side by
    /// side, so the extra width buys a readable name rather than more empty tile.
    property bool wide: false
    /// Carried in the accent container. Reserved for the one action the sheet is trying
    /// to put in front of you; more than one of these and none of them stands out.
    property bool emphasised: false

    signal triggered

    readonly property color colOn: root.emphasised
        ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1

    implicitWidth: root.tileSize
    implicitHeight: root.tileSize
    buttonRadius: Appearance.rounding.large
    buttonRadiusPressed: Appearance.rounding.normal
    colBackground: root.emphasised
        ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
    colBackgroundHover: root.emphasised
        ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
    colBackgroundActive: root.emphasised
        ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer1Active
    colRipple: Appearance.colors.colLayer1Active
    releaseAction: () => root.triggered()

    contentItem: Item {
        anchors.fill: parent

        ColumnLayout {
            anchors.centerIn: parent
            visible: !root.wide
            spacing: 4

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: root.symbol
                iconSize: Math.round(root.tileSize * 0.36)
                fill: 0
                color: root.colOn
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: root.tileSize - 12
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.colOn
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        RowLayout {
            anchors.centerIn: parent
            visible: root.wide
            spacing: 10

            MaterialSymbol {
                text: root.symbol
                iconSize: Math.round(root.tileSize * 0.34)
                fill: 1
                color: root.colOn
            }

            StyledText {
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.colOn
                elide: Text.ElideRight
            }
        }
    }
}
