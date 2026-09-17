import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// Fixed geometry: revealing a shortcut never moves its control or neighbours.
Item {
    id: root
    property string symbol: ""
    property string shortcut: ""
    property bool showHint: false
    property bool circle: false
    property real iconSize: Appearance.font.pixelSize.larger
    property real fill: 0
    property color color: Appearance.colors.colOnSurface
    property color badgeColor: Appearance.colors.colPrimary
    property color badgeTextColor: Appearance.colors.colOnPrimary
    // Text button variant: a label stands in for the icon when there is none.
    property string labelText: ""
    property real labelPixelSize: Appearance.font.pixelSize.larger
    implicitWidth: symbol.length > 0 ? iconSize : Math.max(iconSize, label.implicitWidth)
    implicitHeight: iconSize
    property real hintProgress: showHint && shortcut.length > 0 ? 1 : 0

    Behavior on hintProgress {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: root.symbol.length > 0
        text: root.symbol
        iconSize: root.iconSize
        fill: root.fill
        color: root.color
        opacity: 1 - root.hintProgress
        transform: Translate { y: -root.hintProgress * root.iconSize / 3 }
    }

    StyledText {
        id: label
        anchors.centerIn: parent
        visible: root.symbol.length === 0 && root.labelText.length > 0
        text: root.labelText
        font.pixelSize: root.labelPixelSize
        color: root.color
        opacity: 1 - root.hintProgress
        transform: Translate { y: -root.hintProgress * root.iconSize / 3 }
    }

    Rectangle {
        anchors.centerIn: parent
        width: root.circle ? root.iconSize : parent.width
        height: root.circle ? width : parent.height
        radius: Appearance.rounding.full
        color: root.circle ? root.badgeColor : "transparent"
        opacity: root.hintProgress
        visible: opacity > 0
        transform: Translate { y: (1 - root.hintProgress) * root.iconSize / 3 }

        StyledText {
            anchors.fill: parent
            text: root.shortcut
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: Appearance.font.family.numbers
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Bold
            color: root.circle ? root.badgeTextColor : root.color
        }
    }
}
