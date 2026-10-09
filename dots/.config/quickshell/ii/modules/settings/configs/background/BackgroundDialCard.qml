pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A setting that has an amount, led by the amount: the value in big condensed digits that
 * set themselves from light to heavy as the card's switch turns on, the slider under it and
 * the end labels under that. On takes the primary container; the header's shape morphs
 * with it and the slider track follows the card. `default` content is the footer.
 */
Rectangle {
    id: root

    readonly property real padding: 20
    readonly property real headerSpacing: 12
    readonly property real iconSize: 22
    readonly property real iconPadding: 11
    readonly property real digitsSize: 56
    readonly property real unitSize: 24
    readonly property real unitGap: 4
    readonly property real blockGap: 14
    readonly property real markerGap: 6
    readonly property real subtitleOpacity: 0.8
    readonly property real disabledOpacity: 0.45
    readonly property real trackAlpha: 0.16
    readonly property real wghtOff: 340
    readonly property real wghtOn: 780
    readonly property real wdthOff: 60
    readonly property real wdthOn: 36

    property string symbol: ""
    property var shapeOn: MaterialShape.Shape.Cookie12Sided
    property var shapeOff: MaterialShape.Shape.Circle
    property string title: ""
    property string subtitle: ""
    property string valueText: ""
    property string unit: ""
    property var markers: []
    property bool checked: false
    property alias from: slider.from
    property alias to: slider.to
    property alias stepSize: slider.stepSize
    property alias value: slider.value
    default property alias footer: footerRow.data

    signal toggled(bool value)
    signal moved(real value)

    readonly property bool engaged: cardHover.hovered || slider.pressed
    readonly property color colContent: root.checked ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
    // The spatial curve overshoots; the axes must not.
    property real boldness: root.checked ? 1 : 0
    readonly property real weight: Math.max(0, Math.min(1, root.boldness))
    Behavior on boldness {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    implicitHeight: column.implicitHeight + root.padding * 2
    radius: Appearance.rounding.verylarge
    opacity: root.enabled ? 1 : root.disabledOpacity
    color: root.checked
        ? (root.engaged ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer)
        : (root.engaged ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1)
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
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
        spacing: root.blockGap

        Item {
            Layout.fillWidth: true
            implicitHeight: header.implicitHeight

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggled(!root.checked)
            }

            RowLayout {
                id: header
                anchors {
                    left: parent.left
                    right: parent.right
                }
                spacing: root.headerSpacing

                MaterialShapeWrappedMaterialSymbol {
                    text: root.symbol
                    iconSize: root.iconSize
                    padding: root.iconPadding
                    fill: root.checked ? 1 : 0
                    shape: root.checked ? root.shapeOn : root.shapeOff
                    color: root.checked ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                    colSymbol: root.checked ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
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
                        color: root.colContent
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.subtitle
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.colContent
                        opacity: root.subtitleOpacity
                        elide: Text.ElideRight
                    }
                }

                StyledSwitch {
                    Layout.alignment: Qt.AlignVCenter
                    sizeScale: 0.85
                    checked: root.checked
                    activeColor: Appearance.colors.colPrimary
                    activeThumbColor: Appearance.colors.colOnPrimary
                    inactiveColor: Appearance.colors.colSurfaceContainerHighest
                    onToggled: root.toggled(checked)
                }
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: digits.implicitHeight

            StyledText {
                id: digits
                text: root.valueText
                font.family: Appearance.font.family.main
                font.pixelSize: Math.round(root.digitsSize)
                font.variableAxes: ({
                    "wght": root.wghtOff + (root.wghtOn - root.wghtOff) * root.weight,
                    "wdth": root.wdthOff + (root.wdthOn - root.wdthOff) * root.weight,
                    "ROND": 100
                })
                color: root.checked ? Appearance.colors.colPrimary : root.colContent
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
            StyledText {
                anchors {
                    left: digits.right
                    leftMargin: root.unitGap
                    baseline: digits.baseline
                }
                text: root.unit
                font.family: Appearance.font.family.main
                font.pixelSize: Math.round(root.unitSize)
                font.variableAxes: ({ "wght": root.wghtOn, "wdth": root.wdthOn, "ROND": 100 })
                color: root.colContent
                opacity: root.subtitleOpacity
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: root.markerGap

            StyledSlider {
                id: slider
                Layout.fillWidth: true
                configuration: StyledSlider.Configuration.M
                usePercentTooltip: false
                tooltipContent: root.valueText + root.unit
                trackColor: root.checked
                    ? ColorUtils.applyAlpha(Appearance.colors.colOnPrimaryContainer, root.trackAlpha)
                    : Appearance.colors.colSecondaryContainer
                stopIndicatorValues: []
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
                        color: root.colContent
                        opacity: root.subtitleOpacity
                    }
                }
            }
        }

        RowLayout {
            id: footerRow
            Layout.fillWidth: true
            visible: children.length > 0
            spacing: 8
        }
    }
}
