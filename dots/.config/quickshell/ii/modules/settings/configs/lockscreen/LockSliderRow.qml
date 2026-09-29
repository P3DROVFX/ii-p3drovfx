import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One strength, one slider: the switch it used to have is the slider's own zero.
 * The icon sits in a circle while the value is at the start and morphs into the
 * row's shape once it leaves it; the value reads on the right ("Off" at zero).
 */
ColumnLayout {
    id: root

    property string symbol: ""
    property string label: ""
    property var activeShape: MaterialShape.Shape.Cookie9Sided
    property real value: 0
    property real from: 0
    property real to: 1
    property real stepSize: 0.05
    /// Formats the value for the label; zero reads as "Off" unless `zeroText` says otherwise.
    property var format: v => `${Math.round(v * 100)}%`
    property string zeroText: Translation.tr("Off")

    signal moved(real value)

    readonly property bool on: root.value > root.from + 0.0001
    readonly property bool engaged: rowHover.hovered || slider.pressed

    spacing: 2

    HoverHandler {
        id: rowHover
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        MaterialShapeWrappedMaterialSymbol {
            text: root.symbol
            iconSize: 18
            padding: 5
            fill: root.on ? 1 : 0
            shape: root.on ? root.activeShape : MaterialShape.Shape.Circle
            color: root.on ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
            colSymbol: root.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.label
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
            elide: Text.ElideRight
        }

        StyledText {
            text: root.on ? root.format(root.value) : root.zeroText
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: root.on ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
        }
    }

    StyledSlider {
        id: slider
        Layout.fillWidth: true
        configuration: StyledSlider.Configuration.M
        // The row's header already spaces it; the control's own padding only adds height.
        topPadding: 0
        bottomPadding: 0
        from: root.from
        to: root.to
        stepSize: root.stepSize
        value: root.value
        usePercentTooltip: false
        tooltipContent: value > from + 0.0001 ? root.format(value) : root.zeroText
        onMoved: root.moved(value)
    }
}
