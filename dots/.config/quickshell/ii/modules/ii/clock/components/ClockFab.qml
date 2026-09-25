import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Material 3 Expressive floating action button: a rounded square that tightens its
 * corners under the finger, extends with a label, and enters and leaves on its own.
 */
RippleButton {
    id: root

    property string symbol: "add"
    property string label: ""
    property bool shown: true
    property bool large: false
    property real size: root.large ? ClockStyle.fabSizeLarge : ClockStyle.fabSize
    property color colContainer: ClockStyle.colPrimaryContainer
    property color colContainerHover: ClockStyle.colPrimaryContainerHover
    property color colContainerActive: ClockStyle.colPrimaryContainerActive
    property color colContent: ClockStyle.colOnPrimaryContainer

    readonly property bool extended: root.label.length > 0

    implicitHeight: root.size
    implicitWidth: root.extended ? fabRow.implicitWidth + root.size * 0.6 : root.size
    buttonRadius: root.large ? ClockStyle.radiusExtraLarge : ClockStyle.radiusFab
    buttonRadiusPressed: ClockStyle.radiusFabPressed
    colBackground: root.colContainer
    colBackgroundHover: root.colContainerHover
    colRipple: root.colContainerActive

    visible: opacity > 0
    enabled: root.shown
    opacity: root.shown ? 1 : 0
    scale: root.shown ? 1 : 0.7
    transformOrigin: Item.BottomRight

    Behavior on opacity {
        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
    }
    Behavior on scale {
        animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
    }
    Behavior on implicitWidth {
        animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
    }

    contentItem: Item {
        RowLayout {
            id: fabRow
            anchors.centerIn: parent
            spacing: ClockStyle.gapSmall

            MaterialSymbol {
                text: root.symbol
                iconSize: root.large ? ClockStyle.iconLarge + 8 : ClockStyle.iconLarge
                fill: 1
                color: root.colContent
            }

            StyledText {
                visible: root.extended
                text: root.label
                font.family: ClockStyle.fontTitle
                font.variableAxes: ClockStyle.axesTitle
                font.pixelSize: ClockStyle.textLarge
                color: root.colContent
            }
        }
    }
}
