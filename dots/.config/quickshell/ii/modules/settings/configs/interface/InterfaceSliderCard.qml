pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A slider that shows what it is for: a header that names the setting and states its value
 * in big digits, a stage above the slider (`default` content) drawn with the value itself,
 * and labels under the track that say which end is which. The header's shape morphs while
 * the handle is held. `markers` are evenly spaced labels: two are the ends, more are stops.
 */
Rectangle {
    id: root

    readonly property real padding: 20
    readonly property real headerSpacing: 14
    readonly property real iconSize: 22
    readonly property real iconPadding: 11
    readonly property real digitsSize: 32
    readonly property real sliderGap: 14
    readonly property real markerGap: 6
    readonly property var axesDigitsBold: ({ "wght": 760, "wdth": 40, "ROND": 100 })

    property string symbol: ""
    property var shapeIdle: MaterialShape.Shape.Cookie9Sided
    property var shapeEngaged: MaterialShape.Shape.Cookie12Sided
    property string title: ""
    property string hint: ""
    property string valueText: ""
    property alias from: slider.from
    property alias to: slider.to
    property alias stepSize: slider.stepSize
    property alias value: slider.value
    property alias stopIndicatorValues: slider.stopIndicatorValues
    property var markers: []
    default property alias stage: stageHolder.data

    signal moved(real value)

    readonly property bool engaged: slider.pressed
    readonly property bool hovered: cardHover.hovered

    implicitHeight: column.implicitHeight + root.padding * 2
    radius: Appearance.rounding.verylarge
    color: cardHover.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: cardHover
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.padding
        }
        spacing: root.sliderGap

        RowLayout {
            Layout.fillWidth: true
            spacing: root.headerSpacing

            MaterialShapeWrappedMaterialSymbol {
                text: root.symbol
                iconSize: root.iconSize
                padding: root.iconPadding
                fill: 1
                shape: root.engaged ? root.shapeEngaged : root.shapeIdle
                color: Appearance.colors.colPrimaryContainer
                colSymbol: Appearance.colors.colOnPrimaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.hint
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }

            StyledText {
                text: root.valueText
                font.family: Appearance.font.family.main
                font.pixelSize: Math.round(root.digitsSize)
                font.variableAxes: root.axesDigitsBold
                color: Appearance.colors.colPrimary
            }
        }

        ColumnLayout {
            id: stageHolder
            Layout.fillWidth: true
            visible: children.length > 0
            spacing: 0
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: root.markerGap

            StyledSlider {
                id: slider
                Layout.fillWidth: true
                configuration: StyledSlider.Configuration.M
                usePercentTooltip: false
                tooltipContent: root.valueText
                onMoved: root.moved(slider.value)
            }

            Item {
                id: markerRow
                Layout.fillWidth: true
                visible: root.markers.length > 0
                implicitHeight: markerMetrics.height

                FontMetrics {
                    id: markerMetrics
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                Repeater {
                    model: root.markers

                    delegate: StyledText {
                        id: marker

                        required property string modelData
                        required property int index
                        readonly property real span: Math.max(1, root.markers.length - 1)

                        x: (markerRow.width - marker.width) * marker.index / marker.span
                        text: marker.modelData
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
