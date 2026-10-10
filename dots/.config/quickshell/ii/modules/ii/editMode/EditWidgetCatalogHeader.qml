import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The top of a widget category: how many of its kinds are out, in big
 * condensed digits, and a strip with one segment per widget in list order -
 * lit when placed, raised while its card is under the pointer - so the list
 * and its summary read as one thing.
 */
Rectangle {
    id: root

    readonly property real padding: 16
    readonly property real hostRadius: Appearance.rounding.verylarge
    readonly property real hostPadding: 14
    readonly property real shapeSize: 56
    readonly property real glyphSize: 28
    readonly property real digitSize: 46
    readonly property real totalSize: Appearance.font.pixelSize.hugeass
    readonly property real segmentHeight: 6
    readonly property real segmentRaised: 12
    readonly property real segmentGap: 3
    readonly property real sectionGap: 12
    readonly property real segmentDimAlpha: 0.2
    readonly property real segmentRaisedAlpha: 0.65
    readonly property var digitAxes: ({ "wght": 760, "wdth": 40, "ROND": 100 })
    readonly property var totalAxes: ({ "wght": 420, "wdth": 70, "ROND": 100 })
    readonly property string categoryShape: "Cookie9Sided"
    readonly property color colSurface: Appearance.colors.colPrimaryContainer
    readonly property color colContent: Appearance.colors.colOnPrimaryContainer
    readonly property color colShape: Appearance.colors.colPrimary
    readonly property color colGlyph: Appearance.colors.colOnPrimary

    property string symbol: "widgets"
    property var items: []
    property var countOf: widgetId => 0
    property string hoveredId: ""
    property bool lockTab: false

    readonly property int placedKinds: {
        let n = 0;
        for (const widget of root.items)
            if (root.countOf(widget.widgetId) > 0)
                n++;
        return n;
    }

    radius: Math.max(Appearance.rounding.verysmall, root.hostRadius - root.hostPadding)
    color: root.colSurface
    implicitHeight: content.implicitHeight + root.padding * 2

    Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.padding
        spacing: root.sectionGap

        Item {
            width: parent.width
            height: Math.max(root.shapeSize, digits.height)

            Row {
                id: digits
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                StyledText {
                    id: placedText
                    animateChange: true
                    text: `${root.placedKinds}`
                    font.family: Appearance.font.family.main
                    font.variableAxes: root.digitAxes
                    font.pixelSize: root.digitSize
                    color: root.colContent
                }
                StyledText {
                    id: totalText
                    anchors.baseline: placedText.baseline
                    text: `/${root.items.length}`
                    font.family: Appearance.font.family.main
                    font.variableAxes: root.totalAxes
                    font.pixelSize: root.totalSize
                    color: root.colContent
                    opacity: 0.7
                }
                StyledText {
                    anchors.baseline: placedText.baseline
                    leftPadding: root.sectionGap
                    width: Math.max(0, digits.parent.width - root.shapeSize - root.sectionGap
                        - placedText.width - totalText.width - digits.spacing * 2)
                    text: root.lockTab ? Translation.tr("on the lock screen") : Translation.tr("on your desktop")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.colContent
                    elide: Text.ElideRight
                }
            }

            MaterialShapeWrappedMaterialSymbol {
                id: categoryShape
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: root.shapeSize
                shape: categoryShape.getShape(root.categoryShape)
                text: root.symbol
                iconSize: root.glyphSize
                fill: 1
                color: root.colShape
                colSymbol: root.colGlyph
            }
        }

        Row {
            id: strip
            width: parent.width
            height: root.segmentRaised
            spacing: root.segmentGap

            readonly property real segmentWidth: root.items.length > 0
                ? (strip.width - root.segmentGap * (root.items.length - 1)) / root.items.length : 0

            Repeater {
                model: root.items

                delegate: Item {
                    id: segment
                    required property var modelData
                    readonly property bool lit: root.countOf(segment.modelData.widgetId) > 0
                    readonly property bool raised: root.hoveredId !== "" && root.hoveredId === segment.modelData.widgetId

                    width: strip.segmentWidth
                    height: strip.height

                    Rectangle {
                        id: bar
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: segment.raised ? root.segmentRaised : root.segmentHeight
                        radius: height / 2
                        color: segment.lit ? root.colContent
                            : Qt.alpha(root.colContent, segment.raised ? root.segmentRaisedAlpha : root.segmentDimAlpha)

                        Behavior on height {
                            enabled: !Appearance.reducedMotion
                            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(bar)
                        }
                        Behavior on color {
                            enabled: !Appearance.reducedMotion
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(bar)
                        }
                    }
                }
            }
        }

        Row {
            width: parent.width
            spacing: 6

            MaterialSymbol {
                id: hintGlyph
                anchors.verticalCenter: parent.verticalCenter
                text: "drag_pan"
                iconSize: Appearance.font.pixelSize.normal
                color: root.colContent
                opacity: 0.8
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - hintGlyph.width - parent.spacing
                text: root.lockTab
                    ? Translation.tr("Click to add, or drag a card onto the lock screen")
                    : Translation.tr("Click to add, or drag a card onto the desktop")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.colContent
                opacity: 0.8
                wrapMode: Text.Wrap
            }
        }
    }
}
