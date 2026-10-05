pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A connected button group of any length (the Colors page's light/dark group,
 * generalised): segments 3 px apart, pill outer corners, small inner ones; the
 * current segment fills with primary and rounds into a pill, its glyph's shape
 * morphing from a circle into the segment's own.
 *
 * `options`: [{ value, label, icon, shape }] — `shape` is a MaterialShape name.
 */
RowLayout {
    id: root

    property var options: []
    property string currentValue: ""
    property real segmentHeight: 40
    /** Labels hide below this width per segment, leaving the glyphs. */
    property real labelMinWidth: 96

    signal selected(string value)

    spacing: 3

    Repeater {
        model: root.options

        delegate: RippleButton {
            id: segment

            required property var modelData
            required property int index

            readonly property bool first: segment.index === 0
            readonly property bool last: segment.index === root.options.length - 1
            readonly property bool current: root.currentValue === segment.modelData.value
            readonly property real outer: Math.min(height / 2, Appearance.rounding.full)
            // Animated here rather than on the corners: RippleButton owns a Behavior on each.
            property real inner: segment.current ? segment.outer : Appearance.rounding.verysmall
            Behavior on inner {
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
            }
            readonly property color colContent: segment.current ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            readonly property bool showLabel: segment.width >= root.labelMinWidth

            Layout.fillWidth: true
            Layout.preferredWidth: 1
            implicitWidth: segmentRow.implicitWidth + 28
            implicitHeight: root.segmentHeight

            topLeftRadius: segment.first ? segment.outer : segment.inner
            bottomLeftRadius: segment.first ? segment.outer : segment.inner
            topRightRadius: segment.last ? segment.outer : segment.inner
            bottomRightRadius: segment.last ? segment.outer : segment.inner

            toggled: segment.current
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colBackgroundActive: Appearance.colors.colSecondaryContainerActive
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: root.selected(segment.modelData.value)

            StyledToolTip {
                visible: !segment.showLabel && segment.hovered
                text: segment.modelData.label
            }

            contentItem: Item {
                RowLayout {
                    id: segmentRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialShapeWrappedMaterialSymbol {
                        id: glyph
                        text: segment.modelData.icon
                        iconSize: 17
                        padding: 4
                        fill: segment.current ? 1 : 0
                        shape: segment.current ? glyph.getShape(segment.modelData.shape ?? "Cookie9Sided") : MaterialShape.Shape.Circle
                        color: segment.current ? Appearance.colors.colOnPrimary : "transparent"
                        colSymbol: segment.current ? Appearance.colors.colPrimary : segment.colContent
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }

                    StyledText {
                        visible: segment.showLabel
                        text: segment.modelData.label
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: segment.colContent
                    }
                }
            }
        }
    }
}
