pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A way into a sub-page that shows what is behind it: a shape icon and an arrow on top, a
 * display in the middle (`default` content — a word, a count, glyphs) and the name with a
 * one-line summary at the bottom. `compact` lays it out as a row for a narrow page: icon,
 * name, display, arrow. The icon morphs and the arrow fills on hover.
 */
RippleButton {
    id: root

    readonly property real cardPadding: 22
    readonly property real iconSize: 20
    readonly property real iconPadding: 10
    readonly property real arrowSize: 32
    /// Room the display takes beside the name when `compact`.
    property real compactDisplayWidth: 96

    property string symbol: ""
    property var shapeIdle: MaterialShape.Shape.Cookie9Sided
    property var shapeHover: MaterialShape.Shape.Cookie12Sided
    property string title: ""
    property string summary: ""
    property bool compact: false
    default property alias displayData: displayHolder.data

    readonly property real displayWidth: displayHolder.width
    readonly property real displayHeight: displayHolder.height

    padding: 0
    buttonRadius: Appearance.rounding.verylarge
    buttonRadiusPressed: Appearance.rounding.large
    colBackground: Appearance.colors.colLayer1
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

    contentItem: Item {
        id: body

        MaterialShapeWrappedMaterialSymbol {
            id: icon
            x: root.cardPadding
            y: root.compact ? (body.height - height) / 2 : root.cardPadding
            text: root.symbol
            iconSize: root.iconSize
            padding: root.iconPadding
            fill: 1
            shape: root.hovered ? root.shapeHover : root.shapeIdle
            color: Appearance.colors.colPrimaryContainer
            colSymbol: Appearance.colors.colOnPrimaryContainer
        }

        Rectangle {
            id: arrow
            x: body.width - width - root.cardPadding
            // Bottom-right on a full card, so the name gets the whole header.
            y: root.compact ? (body.height - height) / 2 : body.height - height - root.cardPadding
            width: root.arrowSize
            height: root.arrowSize
            radius: width / 2
            color: root.hovered ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_forward"
                iconSize: 18
                color: root.hovered ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            }
        }

        ColumnLayout {
            id: titleBlock
            // Beside the icon in both layouts: the name leads, not the glyph.
            x: icon.x + icon.width + 14
            y: root.compact ? (body.height - height) / 2 : icon.y + (icon.height - height) / 2
            width: (root.compact ? displayHolder.x - 12 : body.width - root.cardPadding) - x
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.family: Appearance.font.family.title
                font.variableAxes: Appearance.font.variableAxes.titleRounded
                font.pixelSize: root.compact ? Appearance.font.pixelSize.larger : Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnLayer1
                wrapMode: Text.WordWrap
                maximumLineCount: root.compact ? 1 : 2
                lineHeight: 0.92
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: root.summary
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }

        Item {
            id: displayHolder
            x: root.compact ? arrow.x - width - 12 : root.cardPadding
            y: root.compact ? 10 : Math.max(icon.y + icon.height, titleBlock.y + titleBlock.height) + 10
            width: root.compact ? root.compactDisplayWidth : arrow.x - x - 12
            height: root.compact ? body.height - 20 : Math.max(0, body.height - y - root.cardPadding)
        }
    }
}
