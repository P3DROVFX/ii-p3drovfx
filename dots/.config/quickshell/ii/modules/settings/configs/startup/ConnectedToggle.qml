import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * M3 Expressive connected button group for N choices (ColorsModeToggle's vocabulary):
 * segments 3 px apart, outer corners pill, inner corners very small; the current segment
 * fills with primary, rounds into a pill and its icon morphs into its own shape.
 *
 * model: [{ key, label, symbol, shape }]
 */
RowLayout {
    id: root

    property var model: []
    property string current: ""
    property real segmentHeight: 48
    signal selected(string key)

    spacing: 3

    Repeater {
        model: root.model
        delegate: RippleButton {
            id: segment
            required property var modelData
            required property int index

            readonly property bool first: segment.index === 0
            readonly property bool last: segment.index === root.model.length - 1
            readonly property bool isCurrent: root.current === segment.modelData.key
            readonly property real outer: Math.min(height / 2, Appearance.rounding.full)
            // Animated here: RippleButton owns a Behavior on each corner radius
            property real inner: segment.isCurrent ? segment.outer : Appearance.rounding.verysmall
            Behavior on inner {
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
            }
            readonly property color colContent: segment.isCurrent ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer

            Layout.fillWidth: true
            Layout.preferredWidth: 1
            implicitWidth: segmentRow.implicitWidth + 32
            implicitHeight: root.segmentHeight

            topLeftRadius: segment.first ? segment.outer : segment.inner
            bottomLeftRadius: segment.first ? segment.outer : segment.inner
            topRightRadius: segment.last ? segment.outer : segment.inner
            bottomRightRadius: segment.last ? segment.outer : segment.inner

            toggled: segment.isCurrent
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colBackgroundActive: Appearance.colors.colSecondaryContainerActive
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: {
                if (!segment.isCurrent)
                    root.selected(segment.modelData.key);
            }

            contentItem: Item {
                RowLayout {
                    id: segmentRow
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialShapeWrappedMaterialSymbol {
                        visible: (segment.modelData.symbol ?? "") !== ""
                        text: segment.modelData.symbol ?? ""
                        iconSize: 18
                        padding: 5
                        fill: segment.isCurrent ? 1 : 0
                        shape: segment.isCurrent ? (segment.modelData.shape ?? MaterialShape.Shape.Cookie9Sided) : MaterialShape.Shape.Circle
                        color: segment.isCurrent ? Appearance.colors.colOnPrimary : "transparent"
                        colSymbol: segment.isCurrent ? Appearance.colors.colPrimary : segment.colContent
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }

                    StyledText {
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
